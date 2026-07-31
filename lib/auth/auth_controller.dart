import 'dart:async';

// Named public dependency parameters intentionally initialize private fields.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import 'auth_gateway.dart';
import 'auth_models.dart';
import 'auth_session_store.dart';

enum AuthStatus { initializing, signedOut, signedIn, demo }

typedef AuthClock = DateTime Function();

class AuthController extends ChangeNotifier {
  static const passwordResetSuccessMessage =
      'If an account matches that email, password reset instructions will be '
      'sent. Check your inbox and spam folder.';

  final AuthGateway _gateway;
  final AuthSessionStore _store;
  final AuthClock _clock;
  final bool allowDemo;
  final bool _ownsGateway;

  AuthStatus _status = AuthStatus.initializing;
  bool _busy = false;
  bool _passwordResetting = false;
  bool _signingOut = false;
  AuthSession? _session;
  AuthException? _error;
  AuthResult? _signupResult;
  String? _passwordResetNotice;
  EmailVerificationChallenge? _pendingVerification;
  bool _disposed = false;
  Future<void>? _initialization;

  AuthController({
    required AuthGateway gateway,
    required AuthSessionStore store,
    AuthClock clock = DateTime.now,
    this.allowDemo = false,
    bool ownsGateway = true,
    bool initializeImmediately = true,
  }) : _gateway = gateway,
       _store = store,
       _clock = clock,
       _ownsGateway = ownsGateway {
    if (initializeImmediately) initialize();
  }

  AuthStatus get status => _status;
  bool get busy => _busy;
  bool get passwordResetting => _passwordResetting;
  bool get supportsPasswordReset => _gateway is PasswordResetGateway;
  bool get supportsGoogleSignIn => _gateway is GoogleAuthGateway;
  bool get isSignedIn => _status == AuthStatus.signedIn;
  bool get isDemo => _status == AuthStatus.demo;
  AuthSession? get session => _session;
  AuthUser? get user => _session?.user;
  AuthException? get error => _error;
  AuthResult? get signupResult => _signupResult;
  String? get passwordResetNotice => _passwordResetNotice;
  EmailVerificationChallenge? get pendingVerification => _pendingVerification;
  Duration get verificationResendWait =>
      _pendingVerification?.resendWait(_clock()) ?? Duration.zero;

  Future<void> initialize() {
    if (_disposed) return Future.value();
    final active = _initialization;
    if (active != null) return active;
    final completer = Completer<void>();
    _initialization = completer.future;
    _runInitialization().then(
      completer.complete,
      onError: completer.completeError,
    );
    return completer.future.whenComplete(() {
      if (identical(_initialization, completer.future)) {
        _initialization = null;
      }
    });
  }

  Future<void> _runInitialization() async {
    if (_busy || _disposed) return;
    _status = AuthStatus.initializing;
    _error = null;
    _notify();
    AuthSession? stored;
    try {
      stored = await _store.read();
    } on Object {
      _status = AuthStatus.signedOut;
      _error = const AuthException(
        code: AuthFailureCode.storageUnavailable,
        publicMessage:
            'Drip could not open secure account storage. Please retry.',
        retryable: true,
      );
      _notify();
      return;
    }
    if (stored == null) {
      final gateway = _gateway;
      if (gateway is AuthBootstrapGateway) {
        try {
          final bootstrap = await (gateway as AuthBootstrapGateway).bootstrap();
          final verification = bootstrap.verificationChallenge;
          if (verification != null) {
            if (verification.isExpired(_clock())) {
              throw const AuthException(
                code: AuthFailureCode.invalidResponse,
                publicMessage: 'Drip received an expired verification request.',
                retryable: true,
              );
            }
            _pendingVerification = verification;
            _status = AuthStatus.signedOut;
            _notify();
            return;
          }
          final providerSession = bootstrap.session;
          if (providerSession != null) {
            if (providerSession.isExpired(_clock())) {
              throw const AuthException(
                code: AuthFailureCode.sessionExpired,
                publicMessage: 'Your session ended. Sign in again to continue.',
              );
            }
            try {
              await _store.write(providerSession);
            } on Object {
              throw const AuthException(
                code: AuthFailureCode.storageUnavailable,
                publicMessage:
                    'Drip verified your account but could not save the session securely. Please retry.',
                retryable: true,
              );
            }
            _session = providerSession;
            _status = AuthStatus.signedIn;
            _notify();
            return;
          }
        } on AuthException catch (error) {
          _status = AuthStatus.signedOut;
          _error = error;
          _notify();
          return;
        } on Object {
          _status = AuthStatus.signedOut;
          _error = const AuthException.providerUnavailable();
          _notify();
          return;
        }
      }
      _status = AuthStatus.signedOut;
      _notify();
      return;
    }
    if (stored.isExpired(_clock()) && _gateway is! RefreshingAuthGateway) {
      await _clearStoreBestEffort();
      _status = AuthStatus.signedOut;
      _notify();
      return;
    }
    try {
      final restored = await _gateway.restoreSession(stored);
      if (restored.isExpired(_clock())) {
        throw const AuthException(
          code: AuthFailureCode.sessionExpired,
          publicMessage: 'Your session ended. Sign in again to continue.',
        );
      }
      try {
        await _store.write(restored);
      } on Object {
        throw const AuthException(
          code: AuthFailureCode.storageUnavailable,
          publicMessage:
              'Drip verified your account but could not save the session securely. Please retry.',
          retryable: true,
        );
      }
      _session = restored;
      _status = AuthStatus.signedIn;
    } on AuthException catch (error) {
      _status = AuthStatus.signedOut;
      _error = error;
      if (error.code == AuthFailureCode.sessionExpired ||
          error.code == AuthFailureCode.invalidCredentials) {
        await _clearStoreBestEffort();
      }
    } on Object {
      _status = AuthStatus.signedOut;
      _error = const AuthException.providerUnavailable();
    }
    _notify();
  }

  Future<bool> signIn({required String email, required String password}) async {
    if (_busy || _disposed || _initialization != null) return false;
    _passwordResetNotice = null;
    final emailError = validateEmail(email);
    if (emailError != null) {
      _setValidationError(AuthFailureCode.invalidEmail, emailError);
      return false;
    }
    if (password.isEmpty) {
      _setValidationError(
        AuthFailureCode.invalidCredentials,
        'Enter your password.',
      );
      return false;
    }
    return _authenticate(
      () => _gateway.signIn(email: normalizeEmail(email), password: password),
    );
  }

  Future<bool> signInWithGoogle() async {
    if (_busy || _disposed || _initialization != null) return false;
    final gateway = _gateway;
    if (gateway is! GoogleAuthGateway) {
      _error = const AuthException(
        code: AuthFailureCode.providerUnavailable,
        publicMessage:
            'Google sign-in is not available right now. Use email instead.',
        retryable: true,
      );
      _notify();
      return false;
    }
    return _authenticate((gateway as GoogleAuthGateway).signInWithGoogle);
  }

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    if (_busy || _disposed || _initialization != null) return false;
    _passwordResetNotice = null;
    final nameError = validateDisplayName(name);
    if (nameError != null) {
      _setValidationError(AuthFailureCode.invalidName, nameError);
      return false;
    }
    final emailError = validateEmail(email);
    if (emailError != null) {
      _setValidationError(AuthFailureCode.invalidEmail, emailError);
      return false;
    }
    final passwordError = validatePassword(password, email: email);
    if (passwordError != null) {
      _setValidationError(AuthFailureCode.weakPassword, passwordError);
      return false;
    }
    _busy = true;
    _error = null;
    _signupResult = null;
    _notify();
    try {
      final challenge = await _gateway.signUp(
        name: normalizeDisplayName(name),
        email: normalizeEmail(email),
        password: password,
      );
      if (challenge.isExpired(_clock())) {
        throw const AuthException(
          code: AuthFailureCode.invalidResponse,
          publicMessage: 'Drip received an expired confirmation request.',
          retryable: true,
        );
      }
      _pendingVerification = challenge;
      _status = AuthStatus.signedOut;
      return true;
    } on AuthException catch (error) {
      _pendingVerification = error.verificationChallenge;
      _error = error;
      _status = AuthStatus.signedOut;
      return error.verificationChallenge != null;
    } on Object {
      _pendingVerification = null;
      _error = const AuthException.providerUnavailable();
      _status = AuthStatus.signedOut;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> requestPasswordReset({required String email}) async {
    if (_busy || _disposed || _initialization != null) return false;
    _passwordResetNotice = null;
    final emailError = validateEmail(email);
    if (emailError != null) {
      _setValidationError(AuthFailureCode.invalidEmail, emailError);
      return false;
    }
    final gateway = _gateway;
    if (gateway is! PasswordResetGateway) {
      _error = const AuthException(
        code: AuthFailureCode.providerUnavailable,
        publicMessage:
            'Password reset is not available right now. Please try again shortly.',
        retryable: true,
      );
      _notify();
      return false;
    }
    _busy = true;
    _passwordResetting = true;
    _error = null;
    _notify();
    try {
      await (gateway as PasswordResetGateway).sendPasswordResetEmail(
        email: normalizeEmail(email),
      );
      _passwordResetNotice = passwordResetSuccessMessage;
      return true;
    } on AuthException catch (error) {
      _error = error;
      return false;
    } on Object {
      _error = const AuthException.providerUnavailable();
      return false;
    } finally {
      _busy = false;
      _passwordResetting = false;
      _notify();
    }
  }

  Future<bool> verifyEmail([String code = '']) async {
    if (_busy || _disposed || _initialization != null) return false;
    final challenge = _pendingVerification;
    if (challenge == null) return false;
    if (challenge.isExpired(_clock())) {
      _setValidationError(
        AuthFailureCode.verificationExpired,
        challenge.method == EmailVerificationMethod.link
            ? 'This verification request expired. Send a new link.'
            : 'This code expired. Send a new code.',
      );
      return false;
    }
    final normalizedCode = code.trim();
    if (challenge.method == EmailVerificationMethod.code &&
        !RegExp(r'^\d{6}$').hasMatch(normalizedCode)) {
      _setValidationError(
        AuthFailureCode.invalidVerificationCode,
        'Enter the six-digit code from your email.',
      );
      return false;
    }
    final verified = await _authenticate(
      () => _gateway.verifyEmail(
        challengeToken: challenge.challengeToken,
        code: normalizedCode,
      ),
      signup: true,
    );
    return verified;
  }

  Future<bool> resendVerification() async {
    if (_busy || _disposed || _initialization != null) return false;
    final challenge = _pendingVerification;
    if (challenge == null) return false;
    final wait = challenge.resendWait(_clock());
    if (wait > Duration.zero) {
      _setValidationError(
        AuthFailureCode.rateLimited,
        challenge.method == EmailVerificationMethod.link
            ? 'You can send another link in ${_friendlyWait(wait)}.'
            : 'You can send another code in ${_friendlyWait(wait)}.',
      );
      return false;
    }
    _busy = true;
    _error = null;
    _notify();
    try {
      final refreshed = await _gateway.resendVerification(
        challengeToken: challenge.challengeToken,
      );
      if (refreshed.email != challenge.email || refreshed.isExpired(_clock())) {
        throw const AuthException(
          code: AuthFailureCode.invalidResponse,
          publicMessage: 'Drip received an invalid confirmation request.',
          retryable: true,
        );
      }
      _pendingVerification = refreshed;
      return true;
    } on AuthException catch (error) {
      _error = error;
      return false;
    } on Object {
      _error = const AuthException.providerUnavailable();
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> cancelEmailVerification() async {
    if (_busy || _pendingVerification == null) return false;
    _busy = true;
    _error = null;
    _notify();
    final gateway = _gateway;
    try {
      if (gateway is PendingVerificationGateway) {
        await (gateway as PendingVerificationGateway)
            .cancelPendingVerification();
      }
      _pendingVerification = null;
      return true;
    } on Object {
      _error = const AuthException(
        code: AuthFailureCode.providerUnavailable,
        publicMessage:
            'Drip could not close this verification request. Try again.',
        retryable: true,
      );
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> _authenticate(
    Future<AuthResult?> Function() request, {
    bool signup = false,
  }) async {
    _busy = true;
    _error = null;
    _signupResult = null;
    _passwordResetNotice = null;
    _notify();
    try {
      final result = await request();
      // Closing a provider-owned account picker is a normal customer action,
      // not a failed sign-in. Keep the form ready without showing an error.
      if (result == null) return false;
      if (result.session.isExpired(_clock())) {
        throw const AuthException(
          code: AuthFailureCode.invalidResponse,
          publicMessage: 'Drip received an expired account session.',
          retryable: true,
        );
      }
      try {
        await _store.write(result.session);
      } on Object {
        try {
          await _gateway.signOut(result.session);
        } on Object {
          // The local client still fails closed even if remote cleanup fails.
        }
        throw const AuthException(
          code: AuthFailureCode.storageUnavailable,
          publicMessage:
              'Drip could not save your session securely. Check device storage and try again.',
          retryable: true,
        );
      }
      _session = result.session;
      _pendingVerification = null;
      _signupResult = signup ? result : null;
      _status = AuthStatus.signedIn;
      return true;
    } on AuthException catch (error) {
      _session = null;
      _status = AuthStatus.signedOut;
      _error = error;
      if (error.code == AuthFailureCode.verificationRequired &&
          error.verificationChallenge != null) {
        _pendingVerification = error.verificationChallenge;
      } else if (error.code == AuthFailureCode.storageUnavailable ||
          error.code == AuthFailureCode.sessionExpired ||
          error.code == AuthFailureCode.invalidCredentials) {
        _pendingVerification = null;
      }
      return false;
    } on Object {
      _session = null;
      _status = AuthStatus.signedOut;
      _error = const AuthException.providerUnavailable();
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  static String _friendlyWait(Duration wait) {
    final seconds = wait.inSeconds + (wait.inMilliseconds % 1000 == 0 ? 0 : 1);
    if (seconds < 60) return '$seconds second${seconds == 1 ? '' : 's'}';
    final minutes = (seconds / 60).ceil();
    return '$minutes minute${minutes == 1 ? '' : 's'}';
  }

  void completeSignupNotice() {
    if (_signupResult == null) return;
    _signupResult = null;
    _notify();
  }

  Future<void> continueAsDemo() async {
    if (!allowDemo || _busy || _disposed || _initialization != null) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      await _store.clear();
      final gateway = _gateway;
      if (_pendingVerification != null &&
          gateway is PendingVerificationGateway) {
        await (gateway as PendingVerificationGateway)
            .cancelPendingVerification();
      }
    } on Object {
      // A signed-in session must still fail closed if its persisted token
      // cannot be removed. The signed-out local preview is different: it never
      // exposes an account token or makes authenticated requests, so browser
      // storage being unavailable should not make the demo unusable.
      if (_session != null || _status == AuthStatus.signedIn) {
        _busy = false;
        _error = const AuthException(
          code: AuthFailureCode.storageUnavailable,
          publicMessage:
              'Drip could not clear the saved account safely. Please retry.',
          retryable: true,
        );
        _notify();
        return;
      }
    }
    _session = null;
    _signupResult = null;
    _passwordResetNotice = null;
    _pendingVerification = null;
    _error = null;
    _status = AuthStatus.demo;
    _busy = false;
    _notify();
  }

  Future<void> signOut() async {
    if (_busy || _disposed) return;
    final existing = _session;
    _busy = true;
    _signingOut = true;
    _notify();
    var localCleared = false;
    var remoteRevoked = existing == null;
    try {
      await _store.clear();
      localCleared = true;
    } on Object {
      // Remote revocation can still make a persisted token unusable.
    }
    if (existing != null) {
      try {
        await _gateway.signOut(existing);
        remoteRevoked = true;
      } on AuthException catch (error) {
        remoteRevoked =
            error.code == AuthFailureCode.sessionExpired ||
            error.code == AuthFailureCode.invalidCredentials;
      } on Object {
        remoteRevoked = false;
      }
    }
    if (localCleared || remoteRevoked) {
      _session = null;
      _signupResult = null;
      _passwordResetNotice = null;
      _pendingVerification = null;
      _error = null;
      _status = AuthStatus.signedOut;
    } else {
      _error = const AuthException(
        code: AuthFailureCode.storageUnavailable,
        publicMessage:
            'Drip could not sign you out safely. Check your connection and try again.',
        retryable: true,
      );
      _status = AuthStatus.signedIn;
    }
    _busy = false;
    _signingOut = false;
    _notify();
  }

  Future<String?> accessToken() async {
    if (_signingOut) return null;
    var current = _session;
    if (_status != AuthStatus.signedIn || current == null) return null;
    final gateway = _gateway;
    if (gateway is RefreshingAuthGateway) {
      try {
        final refreshed = await (gateway as RefreshingAuthGateway)
            .refreshSession(current);
        if (refreshed.isExpired(_clock())) {
          throw const AuthException(
            code: AuthFailureCode.sessionExpired,
            publicMessage: 'Your session ended. Sign in again to continue.',
          );
        }
        current = refreshed;
        _session = refreshed;
        try {
          await _store.write(refreshed);
        } on Object {
          // The live provider session is still valid. A later app start will
          // ask Firebase to restore it again rather than using a stale token.
        }
      } on AuthException catch (error) {
        if (error.code == AuthFailureCode.sessionExpired ||
            error.code == AuthFailureCode.invalidCredentials ||
            error.code == AuthFailureCode.verificationRequired) {
          _session = null;
          _status = AuthStatus.signedOut;
          _error = error;
          await _clearStoreBestEffort();
          _notify();
        }
        return null;
      } on Object {
        return null;
      }
    }
    if (current.isExpired(_clock())) {
      _session = null;
      _status = AuthStatus.signedOut;
      await _clearStoreBestEffort();
      _notify();
      return null;
    }
    return current.accessToken;
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  void clearPasswordResetNotice() {
    if (_passwordResetNotice == null) return;
    _passwordResetNotice = null;
    _notify();
  }

  void _setValidationError(AuthFailureCode code, String message) {
    _error = AuthException(code: code, publicMessage: message);
    _notify();
  }

  Future<void> _clearStoreBestEffort() async {
    try {
      await _store.clear();
    } on Object {
      // Invalid sessions still fail closed in memory.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsGateway) _gateway.close();
    super.dispose();
  }
}
