import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart' as google;

import 'auth_gateway.dart';
import 'auth_models.dart';
import 'firebase_email_code_client.dart';
import 'google_identity_client.dart';

/// Firebase-backed account access for the native Drip application.
///
/// Firebase owns credential storage and verified-account state. Email-link
/// verification remains the default. A build can explicitly opt into Drip's
/// narrow server-side email-code bridge without moving passwords out of
/// Firebase.
final class FirebaseAuthGateway
    implements
        AuthGateway,
        AuthBootstrapGateway,
        RefreshingAuthGateway,
        PendingVerificationGateway,
        PasswordResetGateway,
        GoogleAuthGateway {
  static const _verificationLifetime = Duration(hours: 1);
  static const _resendCooldown = Duration(seconds: 60);

  final firebase.FirebaseAuth _auth;
  final GoogleIdentityClient _googleIdentity;
  final FirebaseEmailCodeClient? _emailCodeClient;
  final DateTime Function() _clock;
  bool _googleSessionActive = false;

  FirebaseAuthGateway({
    firebase.FirebaseAuth? auth,
    GoogleIdentityClient? googleIdentity,
    FirebaseEmailCodeClient? emailCodeClient,
    bool emailCodeEnabled = FirebaseEmailCodeConfiguration.enabled,
    DateTime Function()? clock,
  }) : _auth = auth ?? firebase.FirebaseAuth.instance,
       _googleIdentity = googleIdentity ?? GoogleSignInIdentityClient(),
       _emailCodeClient = _resolveEmailCodeClient(
         enabled: emailCodeEnabled,
         injected: emailCodeClient,
       ),
       _clock = clock ?? DateTime.now;

  @override
  Future<AuthBootstrapResult> bootstrap() async {
    try {
      final current = _auth.currentUser;
      if (current == null) return const AuthBootstrapResult();
      await current.reload();
      final user = _auth.currentUser;
      if (user == null || user.uid != current.uid) {
        return const AuthBootstrapResult();
      }
      if (!user.emailVerified) {
        return AuthBootstrapResult(
          verificationChallenge: _challengeFor(
            user,
            canResendImmediately: true,
          ),
        );
      }
      return AuthBootstrapResult(session: await _sessionFor(user));
    } on AuthException {
      rethrow;
    } on firebase.FirebaseAuthException catch (error) {
      throw _mapFirebaseError(error);
    } on Object {
      throw const AuthException.providerUnavailable();
    }
  }

  @override
  Future<EmailVerificationChallenge> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) throw _invalidResponse();

      // The account remains usable if a profile-name update is interrupted.
      // It can be recovered from Firebase on the next successful sign-in.
      try {
        await user.updateDisplayName(name);
      } on firebase.FirebaseAuthException {
        // Email ownership verification is the security-critical step.
      }

      if (_emailCodeClient != null) {
        final recoverable = _challengeFor(user, canResendImmediately: true);
        try {
          return await _requestEmailCode(user);
        } on AuthException catch (error) {
          throw _recoverableDeliveryError(error, recoverable);
        } on firebase.FirebaseAuthException catch (error) {
          throw _mapFirebaseError(error, verificationChallenge: recoverable);
        } on Object {
          throw _recoverableDeliveryError(
            const AuthException.providerUnavailable(),
            recoverable,
          );
        }
      }

      final challenge = _challengeFor(user, canResendImmediately: false);
      try {
        await user.sendEmailVerification();
      } on firebase.FirebaseAuthException catch (error) {
        throw _mapFirebaseError(error, verificationChallenge: challenge);
      }
      return challenge;
    } on AuthException {
      rethrow;
    } on firebase.FirebaseAuthException catch (error) {
      throw _mapFirebaseError(error);
    } on Object {
      throw const AuthException.providerUnavailable();
    }
  }

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) throw _invalidResponse();
      if (!user.emailVerified) {
        final usesCode = _emailCodeClient != null;
        throw AuthException(
          code: AuthFailureCode.verificationRequired,
          publicMessage: usesCode
              ? 'Enter the confirmation code from your email before signing in.'
              : 'Verify your email before signing in. Open your verification email, then return to Drip.',
          verificationChallenge: _challengeFor(
            user,
            canResendImmediately: true,
          ),
        );
      }
      return AuthResult(session: await _sessionFor(user));
    } on AuthException {
      rethrow;
    } on firebase.FirebaseAuthException catch (error) {
      throw _mapFirebaseError(error);
    } on Object {
      throw const AuthException.providerUnavailable();
    }
  }

  @override
  Future<AuthResult?> signInWithGoogle() async {
    try {
      final firebase.UserCredential credential;
      if (kIsWeb) {
        credential = await _auth.signInWithPopup(firebase.GoogleAuthProvider());
      } else {
        final idToken = await _googleIdentity.requestIdToken();
        credential = await _auth.signInWithCredential(
          firebase.GoogleAuthProvider.credential(idToken: idToken),
        );
      }
      final user = credential.user;
      if (user == null || !user.emailVerified) throw _invalidResponse();
      _googleSessionActive = true;
      return AuthResult(session: await _sessionFor(user, forceRefresh: true));
    } on google.GoogleSignInException catch (error) {
      if (error.code == google.GoogleSignInExceptionCode.canceled) return null;
      throw _mapGoogleIdentityError(error);
    } on AuthException {
      rethrow;
    } on firebase.FirebaseAuthException catch (error) {
      if (error.code == 'popup-closed-by-user' ||
          error.code == 'cancelled-popup-request' ||
          error.code == 'web-context-cancelled') {
        return null;
      }
      throw _mapGoogleFirebaseError(error);
    } on Object {
      throw const AuthException(
        code: AuthFailureCode.providerUnavailable,
        publicMessage:
            'Google sign-in could not be completed. Try again or use email.',
        retryable: true,
      );
    }
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on firebase.FirebaseAuthException catch (error) {
      // Account-specific failures deliberately look identical to a successful
      // request so this endpoint cannot be used to discover Drip members.
      if (error.code == 'user-not-found' ||
          error.code == 'user-disabled' ||
          error.code == 'invalid-credential') {
        return;
      }
      throw _mapPasswordResetError(error);
    } on Object {
      throw const AuthException.providerUnavailable();
    }
  }

  @override
  Future<AuthResult> verifyEmail({
    required String challengeToken,
    required String code,
  }) async {
    try {
      final current = _auth.currentUser;
      if (current == null || current.uid != challengeToken) {
        throw const AuthException(
          code: AuthFailureCode.verificationExpired,
          publicMessage:
              'This verification request is no longer active. Sign in again to continue.',
        );
      }

      final emailCodeClient = _emailCodeClient;
      if (emailCodeClient != null) {
        if (!RegExp(r'^\d{6}$').hasMatch(code)) {
          throw const AuthException(
            code: AuthFailureCode.invalidVerificationCode,
            publicMessage: 'Enter the six-digit code from your email.',
          );
        }
        final idToken = await _pendingUserIdToken(current);
        final verification = await emailCodeClient.verifyCode(
          idToken: idToken,
          code: code,
        );
        if (_normalizedUserEmail(current) != verification.email ||
            !verification.refreshIdToken) {
          throw _invalidResponse();
        }
      }

      await current.reload();
      final user = _auth.currentUser;
      if (user == null || user.uid != challengeToken) {
        throw const AuthException(
          code: AuthFailureCode.sessionExpired,
          publicMessage: 'Your session ended. Sign in again to continue.',
        );
      }
      if (!user.emailVerified) {
        throw AuthException(
          code: AuthFailureCode.verificationRequired,
          publicMessage: _emailCodeClient == null
              ? 'We cannot see the verification yet. Open the link in your email, then try again.'
              : 'Drip could not confirm that code yet. Send a new code and try again.',
          retryable: true,
        );
      }
      return AuthResult(
        session: await _sessionFor(user, forceRefresh: true),
        welcomeEmailStatus: 'email_verified',
        welcomeEmailMessage:
            'Your email is verified and your Drip account is ready.',
      );
    } on AuthException {
      rethrow;
    } on firebase.FirebaseAuthException catch (error) {
      throw _mapFirebaseError(error);
    } on Object {
      throw const AuthException.providerUnavailable();
    }
  }

  @override
  Future<EmailVerificationChallenge> resendVerification({
    required String challengeToken,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.uid != challengeToken) {
        throw const AuthException(
          code: AuthFailureCode.verificationExpired,
          publicMessage:
              'This verification request is no longer active. Sign in again to continue.',
        );
      }
      if (user.emailVerified) {
        throw const AuthException(
          code: AuthFailureCode.verificationRequired,
          publicMessage:
              'Your email is already verified. Continue to your account.',
        );
      }
      if (_emailCodeClient != null) {
        return _requestEmailCode(user);
      }
      await user.sendEmailVerification();
      return _challengeFor(user, canResendImmediately: false);
    } on AuthException {
      rethrow;
    } on firebase.FirebaseAuthException catch (error) {
      throw _mapFirebaseError(error);
    } on Object {
      throw const AuthException.providerUnavailable();
    }
  }

  @override
  Future<AuthSession> restoreSession(AuthSession storedSession) async {
    try {
      final current = _auth.currentUser;
      if (current == null || current.uid != storedSession.user.id) {
        throw const AuthException(
          code: AuthFailureCode.sessionExpired,
          publicMessage: 'Your session ended. Sign in again to continue.',
        );
      }
      await current.reload();
      final user = _auth.currentUser;
      if (user == null || user.uid != storedSession.user.id) {
        throw const AuthException(
          code: AuthFailureCode.sessionExpired,
          publicMessage: 'Your session ended. Sign in again to continue.',
        );
      }
      if (!user.emailVerified) {
        throw const AuthException(
          code: AuthFailureCode.verificationRequired,
          publicMessage: 'Verify your email before signing in.',
        );
      }
      return _sessionFor(user);
    } on AuthException {
      rethrow;
    } on firebase.FirebaseAuthException catch (error) {
      throw _mapFirebaseError(error);
    } on Object {
      throw const AuthException.providerUnavailable();
    }
  }

  @override
  Future<AuthSession> refreshSession(AuthSession currentSession) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.uid != currentSession.user.id) {
        throw const AuthException(
          code: AuthFailureCode.sessionExpired,
          publicMessage: 'Your session ended. Sign in again to continue.',
        );
      }
      if (!user.emailVerified) {
        throw const AuthException(
          code: AuthFailureCode.verificationRequired,
          publicMessage: 'Verify your email before continuing.',
        );
      }
      return _sessionFor(user);
    } on AuthException {
      rethrow;
    } on firebase.FirebaseAuthException catch (error) {
      throw _mapFirebaseError(error);
    } on Object {
      throw const AuthException.providerUnavailable();
    }
  }

  @override
  Future<void> signOut(AuthSession session) async {
    try {
      await _auth.signOut();
      if (_googleSessionActive) {
        try {
          await _googleIdentity.signOut();
        } on Object {
          // Firebase has already ended the Drip session. Failure to clear the
          // provider's account-picker hint must not make sign-out look failed.
        }
      }
      _googleSessionActive = false;
    } on firebase.FirebaseAuthException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  @override
  Future<void> cancelPendingVerification() => _auth.signOut();

  @override
  void close() {
    _emailCodeClient?.close();
    // FirebaseAuth is owned by the Firebase application singleton.
  }

  EmailVerificationChallenge _challengeFor(
    firebase.User user, {
    required bool canResendImmediately,
  }) {
    final email = user.email;
    if (email == null || !isValidEmail(email)) throw _invalidResponse();
    final now = _clock().toUtc();
    return EmailVerificationChallenge(
      email: normalizeEmail(email),
      challengeToken: user.uid,
      expiresAt: now.add(_verificationLifetime),
      resendAvailableAt: canResendImmediately ? now : now.add(_resendCooldown),
      method: _emailCodeClient == null
          ? EmailVerificationMethod.link
          : EmailVerificationMethod.code,
    );
  }

  Future<EmailVerificationChallenge> _requestEmailCode(
    firebase.User user,
  ) async {
    final client = _emailCodeClient;
    if (client == null) throw _invalidResponse();
    final idToken = await _pendingUserIdToken(user);
    final challenge = await client.requestCode(idToken: idToken);
    if (_normalizedUserEmail(user) != challenge.email ||
        !challenge.expiresAt.isAfter(_clock().toUtc()) ||
        challenge.resendAvailableAt.isAfter(challenge.expiresAt)) {
      throw _invalidResponse();
    }
    return EmailVerificationChallenge(
      email: challenge.email,
      challengeToken: user.uid,
      expiresAt: challenge.expiresAt,
      resendAvailableAt: challenge.resendAvailableAt,
      method: EmailVerificationMethod.code,
    );
  }

  Future<String> _pendingUserIdToken(firebase.User user) async {
    final tokenResult = await user.getIdTokenResult(true);
    final token = tokenResult.token;
    final expiration = tokenResult.expirationTime?.toUtc();
    if (token == null ||
        token.isEmpty ||
        token.length > 8192 ||
        token.contains(RegExp(r'[\r\n]')) ||
        expiration == null ||
        !expiration.isAfter(_clock().toUtc())) {
      throw _invalidResponse();
    }
    return token;
  }

  static String _normalizedUserEmail(firebase.User user) {
    final email = user.email;
    if (email == null || !isValidEmail(email)) throw _invalidResponse();
    return normalizeEmail(email);
  }

  Future<AuthSession> _sessionFor(
    firebase.User user, {
    bool forceRefresh = false,
  }) async {
    _rememberGoogleProvider(user);
    final email = user.email;
    if (email == null || !isValidEmail(email) || !user.emailVerified) {
      throw _invalidResponse();
    }
    final tokenResult = await user.getIdTokenResult(forceRefresh);
    final token = tokenResult.token;
    final expiration = tokenResult.expirationTime?.toUtc();
    if (token == null ||
        token.isEmpty ||
        expiration == null ||
        !expiration.isAfter(_clock().toUtc())) {
      throw _invalidResponse();
    }
    final displayName = normalizeDisplayName(user.displayName ?? '');
    return AuthSession(
      user: AuthUser(
        id: user.uid,
        name: displayName.isEmpty ? 'Drip member' : displayName,
        email: normalizeEmail(email),
      ),
      accessToken: token,
      expiresAt: expiration,
    );
  }

  static FirebaseEmailCodeClient? _resolveEmailCodeClient({
    required bool enabled,
    required FirebaseEmailCodeClient? injected,
  }) {
    if (!enabled) return null;
    return injected ?? FirebaseEmailCodeHttpClient.fromEnvironment();
  }

  static AuthException _recoverableDeliveryError(
    AuthException error,
    EmailVerificationChallenge challenge,
  ) => AuthException(
    code: error.code,
    publicMessage:
        'Your account was created, but the confirmation code could not be sent. Check your connection and send a new code.',
    retryable: true,
    retryAfter: error.retryAfter,
    verificationChallenge: challenge,
  );

  static AuthException _mapFirebaseError(
    firebase.FirebaseAuthException error, {
    EmailVerificationChallenge? verificationChallenge,
  }) {
    final mapped = switch (error.code) {
      'invalid-email' => const AuthException(
        code: AuthFailureCode.invalidEmail,
        publicMessage: 'Enter a valid email address.',
      ),
      'weak-password' => const AuthException(
        code: AuthFailureCode.weakPassword,
        publicMessage: 'Choose a stronger password and try again.',
      ),
      'email-already-in-use' => const AuthException(
        code: AuthFailureCode.emailAlreadyInUse,
        publicMessage:
            'An account with that email already exists. Try signing in.',
      ),
      'wrong-password' ||
      'user-not-found' ||
      'invalid-credential' ||
      'invalid-login-credentials' => const AuthException.invalidCredentials(),
      'too-many-requests' || 'quota-exceeded' => const AuthException(
        code: AuthFailureCode.rateLimited,
        publicMessage:
            'Too many account attempts. Wait a moment before trying again.',
        retryable: true,
      ),
      'user-token-expired' ||
      'invalid-user-token' ||
      'requires-recent-login' => const AuthException(
        code: AuthFailureCode.sessionExpired,
        publicMessage: 'Your session ended. Sign in again to continue.',
      ),
      'operation-not-allowed' => const AuthException(
        code: AuthFailureCode.providerUnavailable,
        publicMessage:
            'Email and password sign-in is not enabled for Drip yet.',
      ),
      'user-disabled' => const AuthException.invalidCredentials(),
      _ => const AuthException.providerUnavailable(),
    };
    if (verificationChallenge == null) return mapped;
    final usesCode =
        verificationChallenge.method == EmailVerificationMethod.code;
    return AuthException(
      code: mapped.code,
      publicMessage: usesCode
          ? 'Your account was created, but the confirmation code could not be sent. Check your connection and send a new code.'
          : 'Your account was created, but the verification email could not be sent. Check your connection and send the link again.',
      retryable: true,
      retryAfter: mapped.retryAfter,
      verificationChallenge: verificationChallenge,
    );
  }

  static AuthException _mapPasswordResetError(
    firebase.FirebaseAuthException error,
  ) => switch (error.code) {
    'invalid-email' || 'missing-email' => const AuthException(
      code: AuthFailureCode.invalidEmail,
      publicMessage: 'Enter a valid email address.',
    ),
    'too-many-requests' || 'quota-exceeded' => const AuthException(
      code: AuthFailureCode.rateLimited,
      publicMessage:
          'Too many password reset attempts. Wait a moment and try again.',
      retryable: true,
    ),
    _ => const AuthException.providerUnavailable(),
  };

  void _rememberGoogleProvider(firebase.User user) {
    try {
      _googleSessionActive = user.providerData.any(
        (provider) => provider.providerId == 'google.com',
      );
    } on Object {
      // Some test doubles and older platform bridges may not expose provider
      // metadata. A successful Google flow sets this flag explicitly.
    }
  }

  static AuthException _mapGoogleIdentityError(
    google.GoogleSignInException error,
  ) => switch (error.code) {
    google.GoogleSignInExceptionCode.clientConfigurationError ||
    google.GoogleSignInExceptionCode.providerConfigurationError =>
      const AuthException(
        code: AuthFailureCode.providerUnavailable,
        publicMessage:
            'Google sign-in is not ready in this build. Use email for now.',
      ),
    google.GoogleSignInExceptionCode.interrupted ||
    google.GoogleSignInExceptionCode.uiUnavailable => const AuthException(
      code: AuthFailureCode.providerUnavailable,
      publicMessage:
          'Google sign-in was interrupted. Try again or use email instead.',
      retryable: true,
    ),
    _ => const AuthException(
      code: AuthFailureCode.providerUnavailable,
      publicMessage:
          'Google sign-in could not be completed. Try again or use email.',
      retryable: true,
    ),
  };

  static AuthException _mapGoogleFirebaseError(
    firebase.FirebaseAuthException error,
  ) => switch (error.code) {
    'operation-not-allowed' => const AuthException(
      code: AuthFailureCode.providerUnavailable,
      publicMessage:
          'Google sign-in is not ready in this build. Use email for now.',
    ),
    'too-many-requests' || 'quota-exceeded' => const AuthException(
      code: AuthFailureCode.rateLimited,
      publicMessage:
          'Too many sign-in attempts. Wait a moment before trying again.',
      retryable: true,
    ),
    'network-request-failed' => const AuthException(
      code: AuthFailureCode.providerUnavailable,
      publicMessage:
          'Google sign-in could not connect. Check your connection and try again.',
      retryable: true,
    ),
    'account-exists-with-different-credential' ||
    'credential-already-in-use' ||
    'invalid-credential' ||
    'user-disabled' => const AuthException(
      code: AuthFailureCode.invalidCredentials,
      publicMessage:
          'Google sign-in could not be completed. Try your usual sign-in method.',
    ),
    _ => const AuthException(
      code: AuthFailureCode.providerUnavailable,
      publicMessage:
          'Google sign-in could not be completed. Try again or use email.',
      retryable: true,
    ),
  };

  static AuthException _invalidResponse() => const AuthException(
    code: AuthFailureCode.invalidResponse,
    publicMessage: 'Drip could not verify this Firebase account. Try again.',
    retryable: true,
  );
}
