import 'package:flutter/foundation.dart';

enum AccountServiceConnectionState {
  notConfigured,
  checking,
  ready,
  serverSetupRequired,
  unavailable,
}

@immutable
class DripServiceReadiness {
  final bool accountsConfigured;
  final bool paymentsConfigured;

  const DripServiceReadiness({
    required this.accountsConfigured,
    required this.paymentsConfigured,
  });
}

@immutable
class AuthUser {
  final String id;
  final String name;
  final String email;
  final String? sellerHandle;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.sellerHandle,
  });

  factory AuthUser.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'] ?? json['displayName'];
    final email = json['email'];
    final rawSellerHandle = json['sellerHandle'] ?? json['seller_handle'];
    if (id is! String ||
        id.trim().isEmpty ||
        id.length > 256 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 240 ||
        email is! String ||
        !isValidEmail(email)) {
      throw const FormatException('Invalid public user.');
    }
    final sellerHandle = switch (rawSellerHandle) {
      null => null,
      String value
          when RegExp(r'^@[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(value) =>
        value,
      _ => throw const FormatException('Invalid seller handle.'),
    };
    return AuthUser(
      id: id.trim(),
      name: normalizeDisplayName(name),
      email: normalizeEmail(email),
      sellerHandle: sellerHandle,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    if (sellerHandle != null) 'sellerHandle': sellerHandle,
  };
}

@immutable
class AuthSession {
  final AuthUser user;
  final String accessToken;
  final DateTime expiresAt;

  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.expiresAt,
  });

  bool isExpired(DateTime now) => !expiresAt.isAfter(now.toUtc());

  Map<String, Object?> toJson() => {
    'user': user.toJson(),
    'accessToken': accessToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory AuthSession.fromJson(Map<String, Object?> json) {
    final userJson = json['user'];
    final token = json['accessToken'];
    final expiresAtValue = json['expiresAt'];
    if (userJson is! Map ||
        token is! String ||
        token.trim().isEmpty ||
        token.length > 4096 ||
        token.contains(RegExp(r'[\r\n]')) ||
        expiresAtValue is! String) {
      throw const FormatException('Invalid session.');
    }
    final expiresAt = DateTime.tryParse(expiresAtValue)?.toUtc();
    if (expiresAt == null) throw const FormatException('Invalid session.');
    return AuthSession(
      user: AuthUser.fromJson(Map<String, Object?>.from(userJson)),
      accessToken: token,
      expiresAt: expiresAt,
    );
  }
}

enum EmailVerificationMethod {
  /// Legacy Drip API flow that asks the customer to enter a one-time code.
  code,

  /// Firebase flow completed by opening the secure link in the email.
  link,
}

@immutable
class EmailVerificationChallenge {
  final String email;
  final String challengeToken;
  final DateTime expiresAt;
  final DateTime resendAvailableAt;
  final EmailVerificationMethod method;

  const EmailVerificationChallenge({
    required this.email,
    required this.challengeToken,
    required this.expiresAt,
    required this.resendAvailableAt,
    this.method = EmailVerificationMethod.code,
  });

  Duration resendWait(DateTime now) {
    final remaining = resendAvailableAt.difference(now.toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool isExpired(DateTime now) => !expiresAt.isAfter(now.toUtc());
}

@immutable
class AuthBootstrapResult {
  final AuthSession? session;
  final EmailVerificationChallenge? verificationChallenge;

  const AuthBootstrapResult({this.session, this.verificationChallenge})
    : assert(
        session == null || verificationChallenge == null,
        'A provider bootstrap cannot be both signed in and pending.',
      );
}

@immutable
class AuthResult {
  final AuthSession session;
  final bool? welcomeEmailSent;
  final String? welcomeEmailStatus;
  final String? welcomeEmailMessage;

  const AuthResult({
    required this.session,
    this.welcomeEmailSent,
    this.welcomeEmailStatus,
    this.welcomeEmailMessage,
  });

  bool get isSignup => welcomeEmailSent != null || welcomeEmailStatus != null;

  String signupNotice() {
    final serverMessage = welcomeEmailMessage?.trim();
    if (welcomeEmailSent == true) {
      return 'Your account is ready. Your welcome email was accepted for delivery.';
    }
    final status = welcomeEmailStatus?.trim().toLowerCase();
    if (status == 'failed' ||
        status == 'rejected' ||
        status == 'undeliverable') {
      return 'Your account works, but the welcome email could not be sent.';
    }
    final safePendingMessage =
        serverMessage?.isNotEmpty == true &&
            !RegExp(
              r'\b(sent|delivered|failed|rejected|undeliverable)\b',
              caseSensitive: false,
            ).hasMatch(serverMessage!)
        ? serverMessage
        : null;
    return safePendingMessage ??
        'Your account is ready. Welcome-email delivery is still pending.';
  }
}

enum AuthFailureCode {
  invalidName,
  invalidEmail,
  weakPassword,
  emailAlreadyInUse,
  invalidCredentials,
  invalidVerificationCode,
  verificationExpired,
  verificationRequired,
  rateLimited,
  providerUnavailable,
  sessionExpired,
  storageUnavailable,
  invalidResponse,
}

class AuthException implements Exception {
  final AuthFailureCode code;
  final String publicMessage;
  final bool retryable;
  final Duration? retryAfter;
  final EmailVerificationChallenge? verificationChallenge;

  const AuthException({
    required this.code,
    required this.publicMessage,
    this.retryable = false,
    this.retryAfter,
    this.verificationChallenge,
  });

  const AuthException.invalidCredentials()
    : this(
        code: AuthFailureCode.invalidCredentials,
        publicMessage: 'Email or password is incorrect.',
      );

  const AuthException.providerUnavailable()
    : this(
        code: AuthFailureCode.providerUnavailable,
        publicMessage:
            'Account services are taking a moment. Please try again shortly.',
        retryable: true,
      );

  @override
  String toString() => 'AuthException(${code.name})';
}

String normalizeEmail(String value) => value.trim().toLowerCase();

bool isValidEmail(String value) {
  final email = normalizeEmail(value);
  if (email.length < 3 ||
      email.length > 254 ||
      email.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
    return false;
  }
  final match = RegExp(
    r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)+$",
  ).hasMatch(email);
  if (!match) return false;
  final separator = email.lastIndexOf('@');
  final local = email.substring(0, separator);
  final domain = email.substring(separator + 1);
  return local.length <= 64 &&
      !local.startsWith('.') &&
      !local.endsWith('.') &&
      !local.contains('..') &&
      domain
          .split('.')
          .every(
            (label) =>
                label.isNotEmpty &&
                label.length <= 63 &&
                !label.startsWith('-') &&
                !label.endsWith('-'),
          );
}

String normalizeDisplayName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

String? validateDisplayName(String value) {
  final name = normalizeDisplayName(value);
  if (name.isEmpty ||
      name.runes.length > 80 ||
      name.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
    return 'Use a name between 1 and 80 characters.';
  }
  return null;
}

String? validateEmail(String value) =>
    isValidEmail(value) ? null : 'Enter a valid email address.';

String? validatePassword(String value, {String? email}) {
  if (value.runes.length < 12 ||
      value.runes.length > 128 ||
      value.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
    return 'Use 12 to 128 characters with no control characters.';
  }
  final categoryCount = <bool>[
    RegExp(r'[a-z]').hasMatch(value),
    RegExp(r'[A-Z]').hasMatch(value),
    RegExp(r'[0-9]').hasMatch(value),
    RegExp(r'[^A-Za-z0-9\s]').hasMatch(value),
  ].where((present) => present).length;
  final localPart = email == null ? '' : normalizeEmail(email).split('@').first;
  if (categoryCount < 3 ||
      (localPart.length >= 4 && value.toLowerCase().contains(localPart))) {
    return 'Use an uncommon password with at least three of: lowercase, uppercase, numbers, and symbols.';
  }
  return null;
}
