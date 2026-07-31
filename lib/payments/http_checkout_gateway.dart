import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_endpoint.dart';
import 'checkout_exception.dart';
import 'checkout_gateway.dart';
import 'checkout_models.dart';

/// Checkout API client configured by a non-secret Drip API URL.
///
/// The configured value is a base URL, such as `https://api.example.com`.
/// This client appends the canonical `/v1/checkout/sessions` routes. Stripe
/// credentials are never accepted by or stored in this class.
final class HttpCheckoutGateway
    implements CheckoutGateway, CheckoutReadinessGateway {
  static const environmentKey = DripApiEndpoint.environmentKey;
  static const _maximumResponseBytes = 256 * 1024;
  static final RegExp _idPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$',
  );
  static final RegExp _errorCodePattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;
  final CheckoutAccessTokenProvider? accessTokenProvider;
  final bool _ownsClient;

  HttpCheckoutGateway({
    required Uri baseUri,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.accessTokenProvider,
  }) : _baseUri = _validateBaseUri(baseUri),
       _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 1)) {
      throw const CheckoutConfigurationException();
    }
  }

  factory HttpCheckoutGateway.fromEnvironment({
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
    CheckoutAccessTokenProvider? accessTokenProvider,
  }) {
    final uri = DripApiEndpoint.uri;
    if (uri == null) throw const CheckoutConfigurationException();
    return HttpCheckoutGateway(
      baseUri: uri,
      client: client,
      timeout: timeout,
      accessTokenProvider: accessTokenProvider,
    );
  }

  static bool get isEnvironmentConfigured => DripApiEndpoint.uri != null;

  @override
  Future<bool> isCheckoutReady() async {
    final response = await _send(
      method: 'GET',
      uri: _endpoint(const ['healthz']),
      includeAuthorization: false,
    );
    _expectSuccess(response, const {200});
    try {
      final health = _decodeObject(response);
      if (health['status'] != 'ok' ||
          health['service'] != 'drip-checkout' ||
          health['paymentsConfigured'] is! bool) {
        throw const CheckoutProtocolException();
      }
      return health['paymentsConfigured']! as bool;
    } on CheckoutException {
      rethrow;
    } on Object {
      throw const CheckoutProtocolException();
    }
  }

  @override
  Future<CheckoutSession> createCheckout(CheckoutRequest request) async {
    final response = await _send(
      method: 'POST',
      uri: _endpoint(const ['v1', 'checkout', 'sessions']),
      body: request.toJson(),
      extraHeaders: {'Idempotency-Key': request.attemptId},
    );
    _expectSuccess(response, const {200, 201});
    try {
      return CheckoutSession.fromJson(_decodeObject(response));
    } on CheckoutException {
      rethrow;
    } on Object {
      throw const CheckoutProtocolException();
    }
  }

  @override
  Future<CheckoutStatusSnapshot> getCheckoutStatus(
    String checkoutSessionId,
  ) async {
    final normalized = _validatedId(checkoutSessionId);
    final response = await _send(
      method: 'GET',
      uri: _endpoint(['v1', 'checkout', 'sessions', normalized]),
    );
    _expectSuccess(response, const {200});
    final result = _parseStatus(response);
    if (result.checkoutSessionId != normalized) {
      throw const CheckoutProtocolException();
    }
    return result;
  }

  @override
  Future<CheckoutStatusSnapshot> expireCheckout({
    required String checkoutSessionId,
    required String attemptId,
  }) async {
    final normalizedSessionId = _validatedId(checkoutSessionId);
    final normalizedAttemptId = _validatedId(attemptId);
    final response = await _send(
      method: 'POST',
      uri: _endpoint([
        'v1',
        'checkout',
        'sessions',
        normalizedSessionId,
        'expire',
      ]),
      body: {'attemptId': normalizedAttemptId},
    );
    _expectSuccess(response, const {200, 202});
    final result = _parseStatus(response);
    if (result.checkoutSessionId != normalizedSessionId) {
      throw const CheckoutProtocolException();
    }
    return result;
  }

  CheckoutStatusSnapshot _parseStatus(http.Response response) {
    try {
      return CheckoutStatusSnapshot.fromJson(_decodeObject(response));
    } on CheckoutException {
      rethrow;
    } on Object {
      throw const CheckoutProtocolException();
    }
  }

  Future<http.Response> _send({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
    Map<String, String> extraHeaders = const {},
    bool includeAuthorization = true,
  }) async {
    try {
      final headers = await _headers(
        includeAuthorization: includeAuthorization,
      ).timeout(timeout);
      headers.addAll(extraHeaders);
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(timeout);
      final bytes = await streamed.stream.toBytes().timeout(timeout);
      if (bytes.length > _maximumResponseBytes) {
        throw const CheckoutProtocolException();
      }
      return http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
        request: request,
        reasonPhrase: streamed.reasonPhrase,
      );
    } on CheckoutException {
      rethrow;
    } on TimeoutException {
      throw const CheckoutNetworkException(timedOut: true);
    } on http.ClientException {
      throw const CheckoutNetworkException();
    } on Object {
      throw const CheckoutNetworkException();
    }
  }

  Future<Map<String, String>> _headers({
    required bool includeAuthorization,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
    };
    final token = includeAuthorization
        ? (await accessTokenProvider?.call())?.trim()
        : null;
    if (token != null && token.isNotEmpty) {
      if (token.length > 4096 || token.contains(RegExp(r'[\r\n]'))) {
        throw const CheckoutAuthorizationException(statusCode: 401);
      }
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    if (response.bodyBytes.isEmpty) throw const CheckoutProtocolException();
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw const CheckoutProtocolException();
    return Map<String, Object?>.from(decoded);
  }

  void _expectSuccess(http.Response response, Set<int> accepted) {
    if (accepted.contains(response.statusCode)) return;
    final serverCode = _serverErrorCode(response);
    if (response.statusCode == 409 &&
        serverCode == 'seller_payout_unavailable') {
      throw const CheckoutSellerPayoutUnavailableException();
    }
    switch (response.statusCode) {
      case 401:
      case 403:
        throw CheckoutAuthorizationException(statusCode: response.statusCode);
      case 404:
        throw const CheckoutNotFoundException();
      case 409:
        throw const CheckoutConflictException();
      case 422:
        throw const CheckoutRejectedException();
      case 429:
      case 502:
      case 503:
      case 504:
        throw CheckoutUnavailableException(statusCode: response.statusCode);
      default:
        if (response.statusCode >= 500) {
          throw CheckoutUnavailableException(statusCode: response.statusCode);
        }
        if (response.statusCode >= 400) {
          throw CheckoutRejectedException(statusCode: response.statusCode);
        }
        throw const CheckoutProtocolException();
    }
  }

  String? _serverErrorCode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;
      final error = decoded['error'];
      if (error is! Map) return null;
      final code = error['code'];
      if (code is! String || !_errorCodePattern.hasMatch(code)) return null;
      return code;
    } on Object {
      return null;
    }
  }

  Uri _endpoint(List<String> segments) => _baseUri.replace(
    pathSegments: [
      ..._baseUri.pathSegments.where((segment) => segment.isNotEmpty),
      ...segments,
    ],
    query: null,
    fragment: null,
  );

  static String _validatedId(String value) {
    final normalized = value.trim();
    if (!_idPattern.hasMatch(normalized)) {
      throw const CheckoutValidationException();
    }
    return normalized;
  }

  static Uri _validateBaseUri(Uri uri) {
    if (!_isAllowedApiBaseUrl(uri) ||
        uri.query.isNotEmpty ||
        uri.pathSegments.any((segment) => segment == '..')) {
      throw const CheckoutConfigurationException();
    }
    return uri.replace(query: null, fragment: null);
  }

  static bool _isAllowedApiBaseUrl(Uri uri) {
    return DripApiEndpoint.isAllowedBaseUri(uri);
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
