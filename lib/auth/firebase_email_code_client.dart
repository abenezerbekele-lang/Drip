import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_endpoint.dart';
import 'auth_models.dart';

/// Build-time gate for Drip's optional Firebase email-code bridge.
///
/// A code client is created only when the feature flag is explicitly true and
/// the canonical `DRIP_API_URL` is present and safe. The debug loopback default
/// and the legacy checkout URL never opt authentication into this feature.
abstract final class FirebaseEmailCodeConfiguration {
  static const enabledEnvironmentKey = 'DRIP_FIREBASE_EMAIL_CODE_ENABLED';
  static const enabled = bool.fromEnvironment(
    enabledEnvironmentKey,
    defaultValue: false,
  );
  static const _configuredApiUrl = String.fromEnvironment(
    DripApiEndpoint.environmentKey,
  );

  static Uri? get apiUri =>
      resolveApiUri(enabled: enabled, configuredApiUrl: _configuredApiUrl);

  static Uri? resolveApiUri({
    required bool enabled,
    required String configuredApiUrl,
  }) {
    if (!enabled) return null;
    final value = configuredApiUrl.trim();
    if (value.isEmpty ||
        RegExp(
          r'(?:^|/)(?:\.|%2e)(?:\.|%2e)?(?=/|[?#]|$)',
          caseSensitive: false,
        ).hasMatch(value)) {
      return null;
    }
    final candidate = Uri.tryParse(value);
    return candidate != null && DripApiEndpoint.isAllowedBaseUri(candidate)
        ? candidate
        : null;
  }
}

final class FirebaseEmailCodeChallengeData {
  final String email;
  final DateTime expiresAt;
  final DateTime resendAvailableAt;

  const FirebaseEmailCodeChallengeData({
    required this.email,
    required this.expiresAt,
    required this.resendAvailableAt,
  });
}

final class FirebaseEmailCodeVerificationData {
  final String email;
  final bool refreshIdToken;

  const FirebaseEmailCodeVerificationData({
    required this.email,
    required this.refreshIdToken,
  });
}

/// Narrow transport boundary for the two server routes that may accept an
/// unverified Firebase ID token.
abstract interface class FirebaseEmailCodeClient {
  Future<FirebaseEmailCodeChallengeData> requestCode({required String idToken});

  Future<FirebaseEmailCodeVerificationData> verifyCode({
    required String idToken,
    required String code,
  });

  void close();
}

final class FirebaseEmailCodeHttpClient implements FirebaseEmailCodeClient {
  static const _maximumResponseBytes = 64 * 1024;

  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;
  final bool _ownsClient;
  final DateTime Function() _clock;

  FirebaseEmailCodeHttpClient({
    required Uri baseUri,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _baseUri = _validateBaseUri(baseUri),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _clock = clock ?? DateTime.now {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 1)) {
      throw const AuthException(
        code: AuthFailureCode.invalidResponse,
        publicMessage: 'Email confirmation is not configured correctly.',
      );
    }
  }

  static FirebaseEmailCodeHttpClient? fromEnvironment({
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) {
    final uri = FirebaseEmailCodeConfiguration.apiUri;
    return uri == null
        ? null
        : FirebaseEmailCodeHttpClient(
            baseUri: uri,
            client: client,
            timeout: timeout,
            clock: clock,
          );
  }

  @override
  Future<FirebaseEmailCodeChallengeData> requestCode({
    required String idToken,
  }) async {
    final response = await _post(
      const ['v1', 'auth', 'firebase', 'email-code', 'request'],
      idToken: idToken,
      body: const {},
    );
    _expect(response, const {200, 202});
    try {
      final body = _decode(response);
      final rawVerification = body['verification'];
      if (rawVerification is! Map) throw const FormatException();
      final verification = Map<String, Object?>.from(rawVerification);
      if (verification['status'] != 'code_sent') {
        throw const FormatException();
      }
      final email = verification['email'];
      final expiresAt = _parseDate(verification['expiresAt']);
      final resendAvailableAt = _parseDate(verification['resendAvailableAt']);
      if (email is! String ||
          !isValidEmail(email) ||
          expiresAt == null ||
          resendAvailableAt == null ||
          !expiresAt.isAfter(_clock().toUtc()) ||
          resendAvailableAt.isAfter(expiresAt)) {
        throw const FormatException();
      }
      return FirebaseEmailCodeChallengeData(
        email: normalizeEmail(email),
        expiresAt: expiresAt,
        resendAvailableAt: resendAvailableAt,
      );
    } on AuthException {
      rethrow;
    } on Object {
      throw _invalidResponse();
    }
  }

  @override
  Future<FirebaseEmailCodeVerificationData> verifyCode({
    required String idToken,
    required String code,
  }) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const AuthException(
        code: AuthFailureCode.invalidVerificationCode,
        publicMessage: 'Enter the six-digit code from your email.',
      );
    }
    final response = await _post(
      const ['v1', 'auth', 'firebase', 'email-code', 'verify'],
      idToken: idToken,
      body: {'code': code},
    );
    _expect(response, const {200});
    try {
      final body = _decode(response);
      final email = body['email'];
      if (body['verified'] != true ||
          body['refreshIdToken'] != true ||
          email is! String ||
          !isValidEmail(email)) {
        throw const FormatException();
      }
      return FirebaseEmailCodeVerificationData(
        email: normalizeEmail(email),
        refreshIdToken: true,
      );
    } on AuthException {
      rethrow;
    } on Object {
      throw _invalidResponse();
    }
  }

  Future<http.Response> _post(
    List<String> path, {
    required String idToken,
    required Map<String, Object?> body,
  }) async {
    if (!_isSafeToken(idToken)) {
      throw const AuthException(
        code: AuthFailureCode.sessionExpired,
        publicMessage: 'Your session ended. Sign in again to continue.',
      );
    }
    try {
      final response = await _client
          .post(
            _endpoint(path),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $idToken',
              'Cache-Control': 'no-store',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (response.bodyBytes.length > _maximumResponseBytes) {
        throw const AuthException.providerUnavailable();
      }
      return response;
    } on AuthException {
      rethrow;
    } on TimeoutException {
      throw const AuthException.providerUnavailable();
    } on http.ClientException {
      throw const AuthException.providerUnavailable();
    } on Object {
      throw const AuthException.providerUnavailable();
    }
  }

  void _expect(http.Response response, Set<int> success) {
    if (success.contains(response.statusCode)) return;
    final code = _safeErrorCode(response);
    if (response.statusCode == 401 ||
        code == 'invalid_token' ||
        code == 'invalid_user_token') {
      throw const AuthException(
        code: AuthFailureCode.sessionExpired,
        publicMessage: 'Your session ended. Sign in again to continue.',
      );
    }
    if (code == 'invalid_verification_code') {
      throw const AuthException(
        code: AuthFailureCode.invalidVerificationCode,
        publicMessage:
            'That confirmation code is invalid or expired. Send a new code if needed.',
      );
    }
    if (response.statusCode == 429 || code == 'auth_rate_limited') {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '');
      final retryAfter = seconds == null || seconds < 1 || seconds > 3600
          ? null
          : Duration(seconds: seconds);
      throw AuthException(
        code: AuthFailureCode.rateLimited,
        publicMessage: retryAfter == null
            ? 'Too many confirmation attempts. Wait before trying again.'
            : 'Too many confirmation attempts. Try again in about ${_friendlyWait(retryAfter)}.',
        retryable: true,
        retryAfter: retryAfter,
      );
    }
    if (response.statusCode >= 500 ||
        response.statusCode == 408 ||
        code == 'firebase_email_code_unavailable') {
      throw const AuthException(
        code: AuthFailureCode.providerUnavailable,
        publicMessage:
            'Email confirmation is taking a moment. Please try again shortly.',
        retryable: true,
      );
    }
    throw _invalidResponse();
  }

  String? _safeErrorCode(http.Response response) {
    try {
      final body = _decode(response);
      final rawError = body['error'];
      if (rawError is! Map) return null;
      final error = Map<String, Object?>.from(rawError);
      final code = error['code'];
      return code is String && code.length <= 80 ? code : null;
    } on Object {
      return null;
    }
  }

  Map<String, Object?> _decode(http.Response response) {
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! Map) throw const FormatException();
    return Map<String, Object?>.from(value);
  }

  static DateTime? _parseDate(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  Uri _endpoint(List<String> suffix) => _baseUri.replace(
    pathSegments: [
      ..._baseUri.pathSegments.where((part) => part.isNotEmpty),
      ...suffix,
    ],
    query: null,
    fragment: null,
  );

  @override
  void close() {
    if (_ownsClient) _client.close();
  }

  static Uri _validateBaseUri(Uri uri) {
    if (!DripApiEndpoint.isAllowedBaseUri(uri)) {
      throw const AuthException(
        code: AuthFailureCode.invalidResponse,
        publicMessage: 'Email confirmation is not configured correctly.',
      );
    }
    return uri;
  }

  static bool _isSafeToken(String value) =>
      value.isNotEmpty &&
      value.length <= 8192 &&
      !value.contains(RegExp(r'[\r\n]'));

  static String _friendlyWait(Duration wait) {
    final seconds = wait.inSeconds;
    if (seconds < 60) return '$seconds second${seconds == 1 ? '' : 's'}';
    final minutes = (seconds / 60).ceil();
    return '$minutes minute${minutes == 1 ? '' : 's'}';
  }

  static AuthException _invalidResponse() => const AuthException(
    code: AuthFailureCode.invalidResponse,
    publicMessage: 'Drip received an unexpected confirmation response.',
    retryable: true,
  );
}
