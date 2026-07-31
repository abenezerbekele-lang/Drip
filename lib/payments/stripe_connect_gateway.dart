import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_endpoint.dart';
import 'checkout_gateway.dart';
import 'stripe_connect_models.dart';

abstract interface class StripeConnectGateway {
  Future<StripeConnectSnapshot> getStatus();

  Future<StripeConnectLink> createOnboardingLink();

  Future<StripeConnectLink> createDashboardLink();

  void close();
}

final class UnavailableStripeConnectGateway implements StripeConnectGateway {
  const UnavailableStripeConnectGateway();

  Never _unavailable() => throw const StripeConnectException.notConfigured();

  @override
  Future<StripeConnectLink> createDashboardLink() async => _unavailable();

  @override
  Future<StripeConnectLink> createOnboardingLink() async => _unavailable();

  @override
  Future<StripeConnectSnapshot> getStatus() async => _unavailable();

  @override
  void close() {}
}

final class HttpStripeConnectGateway implements StripeConnectGateway {
  static const _maximumResponseBytes = 128 * 1024;

  final Uri _baseUri;
  final http.Client _client;
  final CheckoutAccessTokenProvider accessTokenProvider;
  final Duration timeout;
  final bool _ownsClient;

  HttpStripeConnectGateway({
    required Uri baseUri,
    required this.accessTokenProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = _validateBaseUri(baseUri),
       _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 1)) {
      throw const StripeConnectException.notConfigured();
    }
  }

  factory HttpStripeConnectGateway.fromEnvironment({
    required CheckoutAccessTokenProvider accessTokenProvider,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
  }) {
    final uri = DripApiEndpoint.uri;
    if (uri == null) throw const StripeConnectException.notConfigured();
    return HttpStripeConnectGateway(
      baseUri: uri,
      accessTokenProvider: accessTokenProvider,
      client: client,
      timeout: timeout,
    );
  }

  static bool get isEnvironmentConfigured => DripApiEndpoint.uri != null;

  @override
  Future<StripeConnectSnapshot> getStatus() async {
    final response = await _send('GET', const [
      'v1',
      'seller',
      'connect',
      'status',
    ]);
    _expectSuccess(response);
    try {
      return StripeConnectSnapshot.fromJson(_decode(response));
    } on FormatException {
      throw const StripeConnectException.invalidResponse();
    }
  }

  @override
  Future<StripeConnectLink> createOnboardingLink() => _createLink(const [
    'v1',
    'seller',
    'connect',
    'onboarding',
  ], kind: StripeConnectLinkKind.onboarding);

  @override
  Future<StripeConnectLink> createDashboardLink() => _createLink(const [
    'v1',
    'seller',
    'connect',
    'dashboard',
  ], kind: StripeConnectLinkKind.dashboard);

  Future<StripeConnectLink> _createLink(
    List<String> path, {
    required StripeConnectLinkKind kind,
  }) async {
    final response = await _send('POST', path, body: const {});
    _expectSuccess(response, accepted: const {200, 201});
    try {
      return StripeConnectLink.fromJson(_decode(response), kind: kind);
    } on FormatException {
      throw const StripeConnectException.invalidResponse();
    }
  }

  Future<http.Response> _send(
    String method,
    List<String> path, {
    Map<String, Object?>? body,
  }) async {
    try {
      final token = (await accessTokenProvider())?.trim();
      if (token == null ||
          token.isEmpty ||
          token.length > 4096 ||
          token.contains(RegExp(r'[\r\n]'))) {
        throw const StripeConnectException(
          code: StripeConnectFailureCode.authorizationRequired,
          publicMessage: 'Please sign in again to manage seller payouts.',
          statusCode: 401,
        );
      }
      final headers = <String, String>{
        'Accept': 'application/json',
        'Cache-Control': 'no-store',
        'Authorization': 'Bearer $token',
      };
      if (body != null) {
        headers['Content-Type'] = 'application/json; charset=utf-8';
      }
      final request = http.Request(method, _endpoint(path))
        ..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(timeout);
      final bytes = await streamed.stream.toBytes().timeout(timeout);
      if (bytes.length > _maximumResponseBytes) {
        throw const StripeConnectException.invalidResponse();
      }
      return http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
        request: request,
      );
    } on StripeConnectException {
      rethrow;
    } on TimeoutException {
      throw const StripeConnectException.network();
    } on http.ClientException {
      throw const StripeConnectException.network();
    } on Object {
      throw const StripeConnectException.network();
    }
  }

  Map<String, Object?> _decode(http.Response response) {
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is! Map) throw const FormatException();
      return Map<String, Object?>.from(value);
    } on Object {
      throw const StripeConnectException.invalidResponse();
    }
  }

  void _expectSuccess(
    http.Response response, {
    Set<int> accepted = const {200},
  }) {
    if (accepted.contains(response.statusCode)) return;
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw StripeConnectException(
        code: StripeConnectFailureCode.authorizationRequired,
        publicMessage: 'Please sign in again to manage seller payouts.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode == 409 || response.statusCode == 422) {
      throw StripeConnectException(
        code: StripeConnectFailureCode.actionUnavailable,
        publicMessage:
            'Stripe payout setup needs attention before that action is available.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode == 429) {
      throw const StripeConnectException(
        code: StripeConnectFailureCode.rateLimited,
        publicMessage: 'Too many payout requests. Wait a moment and try again.',
        retryable: true,
        statusCode: 429,
      );
    }
    if (response.statusCode == 408 || response.statusCode >= 500) {
      throw StripeConnectException(
        code: StripeConnectFailureCode.network,
        publicMessage: 'Stripe payout services are temporarily unavailable.',
        retryable: true,
        statusCode: response.statusCode,
      );
    }
    throw StripeConnectException(
      code: StripeConnectFailureCode.actionUnavailable,
      publicMessage: 'That Stripe payout action could not be completed.',
      statusCode: response.statusCode,
    );
  }

  Uri _endpoint(List<String> suffix) => _baseUri.replace(
    pathSegments: [
      ..._baseUri.pathSegments.where((segment) => segment.isNotEmpty),
      ...suffix,
    ],
    query: null,
    fragment: null,
  );

  static Uri _validateBaseUri(Uri uri) {
    if (!DripApiEndpoint.isAllowedBaseUri(uri)) {
      throw const StripeConnectException.notConfigured();
    }
    return uri;
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
