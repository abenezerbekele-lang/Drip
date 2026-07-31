import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_endpoint.dart';
import 'auth_models.dart';

abstract interface class AuthGateway {
  Future<EmailVerificationChallenge> signUp({
    required String name,
    required String email,
    required String password,
  });

  Future<AuthResult> verifyEmail({
    required String challengeToken,
    required String code,
  });

  Future<EmailVerificationChallenge> resendVerification({
    required String challengeToken,
  });

  Future<AuthResult> signIn({required String email, required String password});

  Future<AuthSession> restoreSession(AuthSession storedSession);

  Future<void> signOut(AuthSession session);

  void close();
}

abstract interface class AuthReadinessGateway {
  Future<DripServiceReadiness> getServiceReadiness();
}

/// Optional provider-owned persistence used to recover Firebase sessions when
/// Drip's short-lived token cache is empty (for example after an app update).
abstract interface class AuthBootstrapGateway {
  Future<AuthBootstrapResult> bootstrap();
}

/// Optional capability for providers, such as Firebase, whose short-lived
/// bearer tokens can be refreshed without asking the customer to sign in again.
abstract interface class RefreshingAuthGateway {
  Future<AuthSession> refreshSession(AuthSession currentSession);
}

/// Optional cleanup hook for providers that keep a pending, unverified SDK
/// session while the customer is on the email-verification screen.
abstract interface class PendingVerificationGateway {
  Future<void> cancelPendingVerification();
}

/// Optional account-recovery capability.
///
/// Keeping password reset separate from [AuthGateway] lets legacy Drip API
/// implementations continue to satisfy the core authentication contract while
/// providers such as Firebase expose their native, secure reset flow.
abstract interface class PasswordResetGateway {
  Future<void> sendPasswordResetEmail({required String email});
}

/// Optional Google account capability.
///
/// A `null` result means the customer closed Google's account picker without
/// signing in. Cancellation is intentionally not presented as an account
/// error.
abstract interface class GoogleAuthGateway {
  Future<AuthResult?> signInWithGoogle();
}

class UnavailableAuthGateway implements AuthGateway {
  const UnavailableAuthGateway();

  Never _unavailable() => throw const AuthException.providerUnavailable();

  @override
  Future<AuthSession> restoreSession(AuthSession storedSession) async =>
      _unavailable();

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async => _unavailable();

  @override
  Future<void> signOut(AuthSession session) async {}

  @override
  Future<EmailVerificationChallenge> signUp({
    required String name,
    required String email,
    required String password,
  }) async => _unavailable();

  @override
  Future<AuthResult> verifyEmail({
    required String challengeToken,
    required String code,
  }) async => _unavailable();

  @override
  Future<EmailVerificationChallenge> resendVerification({
    required String challengeToken,
  }) async => _unavailable();

  @override
  void close() {}
}

class HttpAuthGateway implements AuthGateway, AuthReadinessGateway {
  static const environmentKey = DripApiEndpoint.environmentKey;
  static const _maximumResponseBytes = 128 * 1024;

  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;
  final bool _ownsClient;

  HttpAuthGateway({
    required Uri baseUri,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = _validateBaseUri(baseUri),
       _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 1)) {
      throw const AuthException(
        code: AuthFailureCode.invalidResponse,
        publicMessage: 'Account services are not configured correctly.',
      );
    }
  }

  factory HttpAuthGateway.fromEnvironment({
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
  }) {
    final uri = DripApiEndpoint.uri;
    if (uri == null) {
      throw const AuthException(
        code: AuthFailureCode.invalidResponse,
        publicMessage: 'Account services are not configured correctly.',
      );
    }
    return HttpAuthGateway(baseUri: uri, client: client, timeout: timeout);
  }

  static bool get isEnvironmentConfigured => DripApiEndpoint.uri != null;

  @override
  Future<DripServiceReadiness> getServiceReadiness() async {
    final response = await _send(method: 'GET', path: const ['healthz']);
    _expect(response, const {200});
    final health = _decode(response);
    if (health['status'] != 'ok' ||
        health['service'] != 'drip-checkout' ||
        health['accountAuthConfigured'] is! bool ||
        health['paymentsConfigured'] is! bool) {
      throw const AuthException(
        code: AuthFailureCode.invalidResponse,
        publicMessage: 'Drip could not verify the account server.',
        retryable: true,
      );
    }
    return DripServiceReadiness(
      accountsConfigured: health['accountAuthConfigured']! as bool,
      paymentsConfigured: health['paymentsConfigured']! as bool,
    );
  }

  @override
  Future<EmailVerificationChallenge> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _send(
      method: 'POST',
      path: const ['v1', 'auth', 'signup'],
      body: {'name': name, 'email': email, 'password': password},
    );
    _expect(response, const {200, 201, 202});
    return _parseVerificationChallenge(_decode(response), fallbackEmail: email);
  }

  @override
  Future<AuthResult> verifyEmail({
    required String challengeToken,
    required String code,
  }) async {
    final response = await _send(
      method: 'POST',
      path: const ['v1', 'auth', 'verify-email'],
      body: {'challengeToken': challengeToken, 'code': code},
    );
    _expect(response, const {200, 201});
    return _parseAuthResult(_decode(response), signup: true);
  }

  @override
  Future<EmailVerificationChallenge> resendVerification({
    required String challengeToken,
  }) async {
    final response = await _send(
      method: 'POST',
      path: const ['v1', 'auth', 'resend-verification'],
      body: {'challengeToken': challengeToken},
    );
    _expect(response, const {200, 202});
    return _parseVerificationChallenge(_decode(response));
  }

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _send(
      method: 'POST',
      path: const ['v1', 'auth', 'login'],
      body: {'email': email, 'password': password},
    );
    _expect(response, const {200});
    return _parseAuthResult(_decode(response));
  }

  @override
  Future<AuthSession> restoreSession(AuthSession storedSession) async {
    final response = await _send(
      method: 'GET',
      path: const ['v1', 'auth', 'session'],
      accessToken: storedSession.accessToken,
    );
    _expect(response, const {200}, restoring: true);
    final body = _decode(response);
    if (body['authenticated'] != true) {
      throw const AuthException(
        code: AuthFailureCode.sessionExpired,
        publicMessage: 'Your session ended. Sign in again to continue.',
      );
    }
    final userJson = body['user'];
    final expiresAt = _parseDate(body['expiresAt']);
    if (userJson is! Map || expiresAt == null) {
      throw const AuthException(
        code: AuthFailureCode.invalidResponse,
        publicMessage: 'Drip could not verify this session. Please try again.',
        retryable: true,
      );
    }
    return AuthSession(
      user: AuthUser.fromJson(Map<String, Object?>.from(userJson)),
      accessToken: storedSession.accessToken,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<void> signOut(AuthSession session) async {
    final response = await _send(
      method: 'POST',
      path: const ['v1', 'auth', 'logout'],
      body: const {},
      accessToken: session.accessToken,
    );
    _expect(response, const {200, 204}, restoring: true);
  }

  Future<http.Response> _send({
    required String method,
    required List<String> path,
    Map<String, Object?>? body,
    String? accessToken,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Cache-Control': 'no-store',
    };
    if (body != null) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }
    if (accessToken != null) headers['Authorization'] = 'Bearer $accessToken';
    try {
      final uri = _endpoint(path);
      final future = switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        ),
        _ => throw StateError('Unsupported method'),
      };
      final response = await future.timeout(timeout);
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

  void _expect(
    http.Response response,
    Set<int> success, {
    bool restoring = false,
  }) {
    if (success.contains(response.statusCode)) return;
    final error = _safeError(response);
    final code = error.$1;
    if (response.statusCode == 401 && restoring) {
      throw const AuthException(
        code: AuthFailureCode.sessionExpired,
        publicMessage: 'Your session ended. Sign in again to continue.',
      );
    }
    if (code == 'invalid_verification_code' || code == 'verification_invalid') {
      throw const AuthException(
        code: AuthFailureCode.invalidVerificationCode,
        publicMessage: 'That confirmation code is not correct. Try again.',
      );
    }
    if (code == 'invalid_verification_challenge') {
      throw const AuthException(
        code: AuthFailureCode.verificationExpired,
        publicMessage:
            'This confirmation request is no longer valid. Go back and create the account again for a fresh code.',
      );
    }
    if (code == 'verification_expired' || code == 'verification_code_expired') {
      throw const AuthException(
        code: AuthFailureCode.verificationExpired,
        publicMessage: 'That confirmation code expired. Send a new code.',
        retryable: true,
      );
    }
    if (code == 'verification_required' || code == 'email_not_verified') {
      throw const AuthException(
        code: AuthFailureCode.verificationRequired,
        publicMessage: 'Confirm your email before signing in.',
      );
    }
    if (code == 'verification_attempts_exceeded') {
      throw const AuthException(
        code: AuthFailureCode.verificationExpired,
        publicMessage:
            'For your security, this code can no longer be used. Send a new code.',
        retryable: true,
      );
    }
    if (response.statusCode == 401 || code == 'invalid_credentials') {
      throw const AuthException.invalidCredentials();
    }
    if (response.statusCode == 409 || code == 'account_exists') {
      throw const AuthException(
        code: AuthFailureCode.emailAlreadyInUse,
        publicMessage:
            'An account with that email already exists. Try signing in.',
      );
    }
    if (code == 'weak_password') {
      throw const AuthException(
        code: AuthFailureCode.weakPassword,
        publicMessage:
            'Use an uncommon password with at least 12 characters and a mix of letters, numbers, and symbols.',
      );
    }
    if (code == 'invalid_email') {
      throw const AuthException(
        code: AuthFailureCode.invalidEmail,
        publicMessage: 'Enter a valid email address.',
      );
    }
    if (code == 'invalid_name') {
      throw const AuthException(
        code: AuthFailureCode.invalidName,
        publicMessage: 'Use a name between 1 and 80 characters.',
      );
    }
    if (response.statusCode == 429 || code == 'auth_rate_limited') {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '');
      throw AuthException(
        code: AuthFailureCode.rateLimited,
        publicMessage: seconds == null
            ? 'Too many attempts. Please wait before trying again.'
            : 'Too many attempts. Try again in about ${_friendlyWait(seconds)}.',
        retryable: true,
        retryAfter: seconds == null ? null : Duration(seconds: seconds),
      );
    }
    if (response.statusCode >= 500 || response.statusCode == 408) {
      throw const AuthException.providerUnavailable();
    }
    throw const AuthException(
      code: AuthFailureCode.invalidResponse,
      publicMessage: 'Drip could not complete that request.',
    );
  }

  (String?, String?) _safeError(http.Response response) {
    try {
      final body = _decode(response);
      final error = body['error'];
      if (error is! Map) return (null, null);
      final value = Map<String, Object?>.from(error);
      final code = value['code'];
      final message = value['message'];
      return (
        code is String && code.length <= 80 ? code : null,
        message is String && message.length <= 240 ? message : null,
      );
    } on Object {
      return (null, null);
    }
  }

  Map<String, Object?> _decode(http.Response response) {
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is! Map) throw const FormatException();
      return Map<String, Object?>.from(value);
    } on Object {
      throw const AuthException(
        code: AuthFailureCode.invalidResponse,
        publicMessage: 'Drip received an unexpected account response.',
        retryable: true,
      );
    }
  }

  AuthResult _parseAuthResult(
    Map<String, Object?> body, {
    bool signup = false,
  }) {
    try {
      final userJson = body['user'];
      final sessionJson = body['session'];
      if (userJson is! Map || sessionJson is! Map) {
        throw const FormatException();
      }
      final user = AuthUser.fromJson(Map<String, Object?>.from(userJson));
      final sessionMap = Map<String, Object?>.from(sessionJson);
      final token = sessionMap['accessToken'] ?? sessionMap['access_token'];
      final expiresAt = _parseDate(
        sessionMap['expiresAt'] ?? sessionMap['expires_at'],
      );
      if (token is! String ||
          token.trim().isEmpty ||
          token.length > 4096 ||
          token.contains(RegExp(r'[\r\n]')) ||
          expiresAt == null) {
        throw const FormatException();
      }
      final welcomeJson = body['welcomeEmail'];
      final welcome = welcomeJson is Map
          ? Map<String, Object?>.from(welcomeJson)
          : const <String, Object?>{};
      final statusValue = welcome['status'];
      final status = statusValue is String ? statusValue.toLowerCase() : null;
      final explicitSent = body['welcomeEmailSent'] ?? welcome['sent'];
      final statusSaysSent = status == 'sent' || status == 'delivered';
      final statusSaysNotSent = status != null && !statusSaysSent;
      final sent = explicitSent is bool
          ? explicitSent && !statusSaysNotSent
          : status == null
          ? null
          : statusSaysSent;
      final messageValue = welcome['message'] ?? body['welcomeEmailMessage'];
      return AuthResult(
        session: AuthSession(
          user: user,
          accessToken: token,
          expiresAt: expiresAt,
        ),
        welcomeEmailSent: signup ? (sent ?? false) : null,
        welcomeEmailStatus: signup
            ? (status ?? (sent == true ? 'sent' : 'pending'))
            : null,
        welcomeEmailMessage:
            messageValue is String && messageValue.length <= 240
            ? messageValue
            : null,
      );
    } on AuthException {
      rethrow;
    } on Object {
      throw const AuthException(
        code: AuthFailureCode.invalidResponse,
        publicMessage: 'Drip received an unexpected account response.',
        retryable: true,
      );
    }
  }

  EmailVerificationChallenge _parseVerificationChallenge(
    Map<String, Object?> body, {
    String? fallbackEmail,
  }) {
    try {
      final verificationJson = body['verification'];
      final verification = verificationJson is Map
          ? Map<String, Object?>.from(verificationJson)
          : body;
      final rawEmail = verification['email'] ?? body['email'] ?? fallbackEmail;
      final email = rawEmail is String ? normalizeEmail(rawEmail) : '';
      final rawChallengeToken =
          verification['challengeToken'] ??
          verification['challenge_token'] ??
          body['challengeToken'] ??
          body['challenge_token'];
      final challengeToken = rawChallengeToken is String
          ? rawChallengeToken
          : '';
      final expiresAt = _parseDate(
        verification['expiresAt'] ??
            verification['expires_at'] ??
            body['expiresAt'] ??
            body['expires_at'],
      );
      var resendAvailableAt = _parseDate(
        verification['resendAvailableAt'] ??
            verification['resend_available_at'] ??
            body['resendAvailableAt'] ??
            body['resend_available_at'],
      );
      final resendSeconds =
          verification['resendAfterSeconds'] ??
          verification['resend_after_seconds'] ??
          body['resendAfterSeconds'] ??
          body['resend_after_seconds'];
      if (resendAvailableAt == null && resendSeconds is int) {
        resendAvailableAt = DateTime.now().toUtc().add(
          Duration(seconds: resendSeconds.clamp(0, 3600)),
        );
      }
      if (!isValidEmail(email) ||
          (fallbackEmail != null && email != normalizeEmail(fallbackEmail)) ||
          challengeToken.length < 43 ||
          challengeToken.length > 200 ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(challengeToken) ||
          expiresAt == null ||
          resendAvailableAt == null) {
        throw const FormatException();
      }
      return EmailVerificationChallenge(
        email: email,
        challengeToken: challengeToken,
        expiresAt: expiresAt,
        resendAvailableAt: resendAvailableAt,
      );
    } on AuthException {
      rethrow;
    } on Object {
      throw const AuthException(
        code: AuthFailureCode.invalidResponse,
        publicMessage: 'Drip received an unexpected confirmation response.',
        retryable: true,
      );
    }
  }

  Uri _endpoint(List<String> suffix) => _baseUri.replace(
    pathSegments: [
      ..._baseUri.pathSegments.where((part) => part.isNotEmpty),
      ...suffix,
    ],
    query: null,
    fragment: null,
  );

  static Uri _validateBaseUri(Uri uri) {
    if (!DripApiEndpoint.isAllowedBaseUri(uri)) {
      throw const AuthException(
        code: AuthFailureCode.invalidResponse,
        publicMessage:
            'Account API must use HTTPS (or debug localhost during development).',
      );
    }
    return uri;
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    if (value is int) {
      final milliseconds = value < 100000000000 ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    return null;
  }

  static String _friendlyWait(int seconds) {
    if (seconds < 60) return '$seconds seconds';
    final minutes = (seconds / 60).ceil();
    return '$minutes minute${minutes == 1 ? '' : 's'}';
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
