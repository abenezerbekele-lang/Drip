import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../commerce_model.dart';
import 'assistant_models.dart';

typedef AssistantAccessTokenProvider = Future<String?> Function();

final _assistantCardPattern = RegExp(r'(?:\d[\s-]?){13,19}');
final _assistantCodePattern = RegExp(
  r'\b(cvv|cvc)\s*[:#=-]?\s*\d{3,4}\b',
  caseSensitive: false,
);
final _assistantSecretPattern = RegExp(
  r'\b(password|api key|secret key|stripe secret|auth token)\b',
  caseSensitive: false,
);

bool containsSensitiveAssistantData(String value) {
  final card = _assistantCardPattern.firstMatch(value)?.group(0);
  final digitCount = card?.replaceAll(RegExp(r'\D'), '').length ?? 0;
  return (digitCount >= 13 && digitCount <= 19) ||
      _assistantCodePattern.hasMatch(value) ||
      _assistantSecretPattern.hasMatch(value);
}

String redactSensitiveAssistantData(String value) {
  var redacted = value.replaceAllMapped(_assistantCardPattern, (match) {
    final digits = match.group(0)!.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 13 && digits.length <= 19
        ? '[payment details hidden]'
        : match.group(0)!;
  });
  redacted = redacted.replaceAllMapped(
    _assistantCodePattern,
    (match) => '${match.group(1)!.toUpperCase()} [hidden]',
  );
  if (_assistantSecretPattern.hasMatch(redacted)) {
    redacted = '[credential details hidden]';
  }
  return redacted;
}

abstract interface class AssistantGateway {
  Future<AssistantResponse> respond(AssistantRequest request);

  void close();
}

class AssistantGatewayException implements Exception {
  final bool retryable;
  final String publicMessage;

  const AssistantGatewayException({
    required this.retryable,
    this.publicMessage =
        'Drip Concierge is taking a moment. Please try that again.',
  });
}

class HttpAssistantGateway implements AssistantGateway {
  static const environmentKey = 'DRIP_AI_API_URL';
  static const _aiEnvironmentUrl = String.fromEnvironment(environmentKey);
  static const _sharedApiEnvironmentUrl = String.fromEnvironment(
    'DRIP_API_URL',
  );
  static const _checkoutEnvironmentUrl = String.fromEnvironment(
    'DRIP_CHECKOUT_API_URL',
  );
  static const _maximumResponseBytes = 128 * 1024;

  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;
  final AssistantAccessTokenProvider? accessTokenProvider;
  final bool _ownsClient;

  HttpAssistantGateway({
    required Uri baseUri,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.accessTokenProvider,
  }) : _baseUri = _validateBaseUri(baseUri),
       _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 1)) {
      throw const AssistantGatewayException(retryable: false);
    }
  }

  factory HttpAssistantGateway.fromEnvironment({
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
    AssistantAccessTokenProvider? accessTokenProvider,
  }) {
    final value = _environmentValue;
    final uri = value.isEmpty ? null : Uri.tryParse(value);
    if (uri == null) {
      throw const AssistantGatewayException(retryable: false);
    }
    return HttpAssistantGateway(
      baseUri: uri,
      client: client,
      timeout: timeout,
      accessTokenProvider: accessTokenProvider,
    );
  }

  static String get _environmentValue {
    final explicit = _aiEnvironmentUrl.trim();
    if (explicit.isNotEmpty) return explicit;
    final shared = _sharedApiEnvironmentUrl.trim();
    return shared.isNotEmpty ? shared : _checkoutEnvironmentUrl.trim();
  }

  static bool get isEnvironmentConfigured {
    final value = _environmentValue;
    final uri = value.isEmpty ? null : Uri.tryParse(value);
    if (uri == null) return false;
    try {
      _validateBaseUri(uri);
      return true;
    } on AssistantGatewayException {
      return false;
    }
  }

  @override
  Future<AssistantResponse> respond(AssistantRequest request) async {
    if (request.message.trim().isEmpty || request.message.length > 1200) {
      throw const AssistantGatewayException(
        retryable: false,
        publicMessage: 'Keep each question under 1,200 characters.',
      );
    }
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      };
      final token = (await accessTokenProvider?.call())?.trim();
      if (token != null && token.isNotEmpty) {
        if (token.length > 4096 || token.contains(RegExp(r'[\r\n]'))) {
          throw const AssistantGatewayException(retryable: false);
        }
        headers['Authorization'] = 'Bearer $token';
      }
      final response = await _client
          .post(
            _endpoint(const ['v1', 'ai', 'chat']),
            headers: headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(timeout);
      if (response.bodyBytes.length > _maximumResponseBytes) {
        throw const AssistantGatewayException(retryable: true);
      }
      if (response.statusCode != 200) {
        final retryable =
            response.statusCode == 429 || response.statusCode >= 500;
        throw AssistantGatewayException(retryable: retryable);
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const AssistantGatewayException(retryable: true);
      }
      final result = AssistantResponse.fromJson(
        Map<String, Object?>.from(decoded),
      );
      _validateGrounding(result, request.context);
      return result.copyWith(usedRemoteModel: true);
    } on AssistantGatewayException {
      rethrow;
    } on TimeoutException {
      throw const AssistantGatewayException(retryable: true);
    } on http.ClientException {
      throw const AssistantGatewayException(retryable: true);
    } on FormatException {
      throw const AssistantGatewayException(retryable: true);
    } on Object {
      throw const AssistantGatewayException(retryable: true);
    }
  }

  static void _validateGrounding(
    AssistantResponse response,
    AssistantContext context,
  ) {
    final ids = {...response.productIds, ...?response.outfit?.productIds};
    for (final id in ids) {
      final product = context.productById(id);
      if (product == null || !context.isPurchasable(product)) {
        throw const AssistantGatewayException(retryable: true);
      }
    }
    final outfit = response.outfit;
    if (outfit == null) return;
    final uniqueIds = outfit.productIds.toSet();
    if (uniqueIds.length != outfit.productIds.length) {
      throw const AssistantGatewayException(retryable: true);
    }
    final calculated = outfit.productIds.fold<int>(0, (total, id) {
      final product = context.productById(id)!;
      return total + (product.price * 100).round();
    });
    final sellerCount = outfit.productIds
        .map((id) => context.productById(id)!.sellerHandle)
        .toSet()
        .length;
    final estimatedTotal =
        calculated +
        MarketplacePolicy.buyerProtectionCents(calculated) +
        sellerCount * MarketplacePolicy.shippingPerSellerCents;
    if (calculated != outfit.subtotalCents ||
        (outfit.budgetCents != null && estimatedTotal > outfit.budgetCents!)) {
      throw const AssistantGatewayException(retryable: true);
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

  static Uri _validateBaseUri(Uri uri) {
    final local =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    if (!uri.hasAuthority ||
        (uri.scheme != 'https' && !(local && uri.scheme == 'http')) ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.pathSegments.contains('..')) {
      throw const AssistantGatewayException(retryable: false);
    }
    return uri.replace(query: null, fragment: null);
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}

/// Uses the hosted model when configured and a deterministic, app-grounded
/// concierge when the network or model service is unavailable. Sensitive
/// payment data is intercepted before any network request is made.
class ResilientAssistantGateway implements AssistantGateway {
  final AssistantGateway? remote;
  final AssistantGateway fallback;

  const ResilientAssistantGateway({required this.fallback, this.remote});

  @override
  Future<AssistantResponse> respond(AssistantRequest request) async {
    if (containsSensitiveAssistantData(request.message) ||
        request.history.any(
          (turn) => containsSensitiveAssistantData(turn.content),
        ) ||
        remote == null) {
      return fallback.respond(request);
    }
    try {
      return await remote!.respond(request);
    } on AssistantGatewayException catch (error) {
      if (!error.retryable) rethrow;
      return fallback.respond(request);
    }
  }

  @override
  void close() {
    remote?.close();
    fallback.close();
  }
}
