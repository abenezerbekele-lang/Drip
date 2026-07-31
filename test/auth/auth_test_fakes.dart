import 'dart:async';

import 'package:drip/auth/auth_gateway.dart';
import 'package:drip/auth/auth_models.dart';

final authTestNow = DateTime.utc(2032, 4, 5, 12);
const authTestChallengeToken = 'test_12345678901234567890123456789012345678';
const authTestRotatedChallengeToken =
    'next_12345678901234567890123456789012345678';

AuthUser authTestUser({
  String id = 'acct_test_123',
  String name = 'Jordan Lee',
  String email = 'jordan@example.com',
}) => AuthUser(id: id, name: name, email: email);

AuthSession authTestSession({
  AuthUser? user,
  String accessToken = 'jwt-test-access-token',
  DateTime? expiresAt,
}) => AuthSession(
  user: user ?? authTestUser(),
  accessToken: accessToken,
  expiresAt: expiresAt ?? authTestNow.add(const Duration(hours: 1)),
);

AuthResult authTestResult({
  AuthSession? session,
  bool? welcomeEmailSent,
  String? welcomeEmailStatus,
  String? welcomeEmailMessage,
}) => AuthResult(
  session: session ?? authTestSession(),
  welcomeEmailSent: welcomeEmailSent,
  welcomeEmailStatus: welcomeEmailStatus,
  welcomeEmailMessage: welcomeEmailMessage,
);

EmailVerificationChallenge authTestVerification({
  String email = 'jordan@example.com',
  String challengeToken = authTestChallengeToken,
  DateTime? expiresAt,
  DateTime? resendAvailableAt,
  EmailVerificationMethod method = EmailVerificationMethod.code,
}) => EmailVerificationChallenge(
  email: email,
  challengeToken: challengeToken,
  expiresAt: expiresAt ?? authTestNow.add(const Duration(minutes: 10)),
  resendAvailableAt: resendAvailableAt ?? authTestNow,
  method: method,
);

class FakeAuthGateway implements AuthGateway, PasswordResetGateway {
  AuthResult signInResult = authTestResult();
  EmailVerificationChallenge signUpResult = authTestVerification();
  AuthResult verifyEmailResult = authTestResult(
    welcomeEmailSent: true,
    welcomeEmailStatus: 'sent',
  );
  EmailVerificationChallenge resendVerificationResult = authTestVerification();
  AuthSession restoreResult = authTestSession();

  Object? signInError;
  Object? signUpError;
  Object? verifyEmailError;
  Object? resendVerificationError;
  Object? restoreError;
  Object? signOutError;
  Object? passwordResetError;

  Completer<AuthResult>? signInCompleter;
  Completer<EmailVerificationChallenge>? signUpCompleter;
  Completer<AuthResult>? verifyEmailCompleter;
  Completer<EmailVerificationChallenge>? resendVerificationCompleter;
  Completer<AuthSession>? restoreCompleter;
  Completer<void>? signOutCompleter;
  Completer<void>? passwordResetCompleter;

  int signInCalls = 0;
  int signUpCalls = 0;
  int verifyEmailCalls = 0;
  int resendVerificationCalls = 0;
  int restoreCalls = 0;
  int signOutCalls = 0;
  int closeCalls = 0;
  int passwordResetCalls = 0;

  String? lastName;
  String? lastEmail;
  String? lastPassword;
  String? lastCode;
  String? lastChallengeToken;
  AuthSession? lastRestoredSession;
  AuthSession? lastSignedOutSession;
  String? lastPasswordResetEmail;

  @override
  Future<void> sendPasswordResetEmail({required String email}) {
    passwordResetCalls += 1;
    lastPasswordResetEmail = email;
    final error = passwordResetError;
    if (error != null) return Future<void>.error(error);
    return passwordResetCompleter?.future ?? Future<void>.value();
  }

  @override
  Future<AuthResult> signIn({required String email, required String password}) {
    signInCalls += 1;
    lastEmail = email;
    lastPassword = password;
    final error = signInError;
    if (error != null) return Future<AuthResult>.error(error);
    return signInCompleter?.future ?? Future<AuthResult>.value(signInResult);
  }

  @override
  Future<EmailVerificationChallenge> signUp({
    required String name,
    required String email,
    required String password,
  }) {
    signUpCalls += 1;
    lastName = name;
    lastEmail = email;
    lastPassword = password;
    final error = signUpError;
    if (error != null) return Future<EmailVerificationChallenge>.error(error);
    return signUpCompleter?.future ??
        Future<EmailVerificationChallenge>.value(signUpResult);
  }

  @override
  Future<AuthResult> verifyEmail({
    required String challengeToken,
    required String code,
  }) {
    verifyEmailCalls += 1;
    lastChallengeToken = challengeToken;
    lastCode = code;
    final error = verifyEmailError;
    if (error != null) return Future<AuthResult>.error(error);
    return verifyEmailCompleter?.future ??
        Future<AuthResult>.value(verifyEmailResult);
  }

  @override
  Future<EmailVerificationChallenge> resendVerification({
    required String challengeToken,
  }) {
    resendVerificationCalls += 1;
    lastChallengeToken = challengeToken;
    final error = resendVerificationError;
    if (error != null) return Future<EmailVerificationChallenge>.error(error);
    return resendVerificationCompleter?.future ??
        Future<EmailVerificationChallenge>.value(resendVerificationResult);
  }

  @override
  Future<AuthSession> restoreSession(AuthSession storedSession) {
    restoreCalls += 1;
    lastRestoredSession = storedSession;
    final error = restoreError;
    if (error != null) return Future<AuthSession>.error(error);
    return restoreCompleter?.future ?? Future<AuthSession>.value(restoreResult);
  }

  @override
  Future<void> signOut(AuthSession session) {
    signOutCalls += 1;
    lastSignedOutSession = session;
    final error = signOutError;
    if (error != null) return Future<void>.error(error);
    return signOutCompleter?.future ?? Future<void>.value();
  }

  @override
  void close() {
    closeCalls += 1;
  }
}

class FakeGoogleAuthGateway extends FakeAuthGateway
    implements GoogleAuthGateway {
  AuthResult? googleSignInResult = authTestResult();
  Object? googleSignInError;
  Completer<AuthResult?>? googleSignInCompleter;
  int googleSignInCalls = 0;

  @override
  Future<AuthResult?> signInWithGoogle() {
    googleSignInCalls += 1;
    final error = googleSignInError;
    if (error != null) return Future<AuthResult?>.error(error);
    return googleSignInCompleter?.future ??
        Future<AuthResult?>.value(googleSignInResult);
  }
}
