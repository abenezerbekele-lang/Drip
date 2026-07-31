import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:drip/auth/auth_controller.dart';
import 'package:drip/auth/auth_gateway.dart';
import 'package:drip/auth/auth_models.dart';
import 'package:drip/auth/auth_session_store.dart';

import 'auth_test_fakes.dart';

final class _ProviderAuthGateway extends FakeAuthGateway
    implements
        AuthBootstrapGateway,
        RefreshingAuthGateway,
        PendingVerificationGateway {
  AuthBootstrapResult bootstrapResult = const AuthBootstrapResult();
  AuthSession refreshResult = authTestSession(
    accessToken: 'refreshed-provider-token',
  );
  Object? bootstrapError;
  Object? refreshError;
  Object? cancelPendingError;
  Completer<AuthBootstrapResult>? bootstrapCompleter;
  Completer<AuthSession>? refreshCompleter;
  Completer<void>? cancelPendingCompleter;
  int bootstrapCalls = 0;
  int refreshCalls = 0;
  int cancelPendingCalls = 0;
  AuthSession? lastRefreshSession;

  @override
  Future<AuthBootstrapResult> bootstrap() {
    bootstrapCalls += 1;
    final error = bootstrapError;
    if (error != null) return Future<AuthBootstrapResult>.error(error);
    return bootstrapCompleter?.future ??
        Future<AuthBootstrapResult>.value(bootstrapResult);
  }

  @override
  Future<AuthSession> refreshSession(AuthSession currentSession) {
    refreshCalls += 1;
    lastRefreshSession = currentSession;
    final error = refreshError;
    if (error != null) return Future<AuthSession>.error(error);
    return refreshCompleter?.future ?? Future<AuthSession>.value(refreshResult);
  }

  @override
  Future<void> cancelPendingVerification() {
    cancelPendingCalls += 1;
    final error = cancelPendingError;
    if (error != null) return Future<void>.error(error);
    return cancelPendingCompleter?.future ?? Future<void>.value();
  }
}

void main() {
  group('AuthController', () {
    test(
      'normalizes identity fields and permits only one active submission',
      () async {
        final gateway = FakeAuthGateway();
        final pending = Completer<AuthResult>();
        gateway.signInCompleter = pending;
        final store = MemoryAuthSessionStore();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        final first = controller.signIn(
          email: '  Jordan@Example.COM  ',
          password: ' Password-is-not-trimmed-9! ',
        );
        final duplicate = await controller.signIn(
          email: 'jordan@example.com',
          password: 'Another-Password-9!',
        );

        expect(duplicate, isFalse);
        expect(controller.busy, isTrue);
        expect(gateway.signInCalls, 1);
        expect(gateway.lastEmail, 'jordan@example.com');
        expect(gateway.lastPassword, ' Password-is-not-trimmed-9! ');

        pending.complete(gateway.signInResult);
        expect(await first, isTrue);
        expect(controller.status, AuthStatus.signedIn);
        expect(store.value, same(gateway.signInResult.session));
      },
    );

    test(
      'password reset validates and normalizes email without creating a session',
      () async {
        final gateway = FakeAuthGateway();
        final controller = AuthController(
          gateway: gateway,
          store: MemoryAuthSessionStore(),
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        expect(
          await controller.requestPasswordReset(email: 'not-an-email'),
          isFalse,
        );
        expect(controller.error?.code, AuthFailureCode.invalidEmail);
        expect(gateway.passwordResetCalls, 0);

        final pending = Completer<void>();
        gateway.passwordResetCompleter = pending;
        final first = controller.requestPasswordReset(
          email: '  Jordan@Example.COM ',
        );
        await Future<void>.delayed(Duration.zero);

        expect(controller.busy, isTrue);
        expect(controller.passwordResetting, isTrue);
        expect(gateway.passwordResetCalls, 1);
        expect(gateway.lastPasswordResetEmail, 'jordan@example.com');
        expect(
          await controller.requestPasswordReset(email: 'other@example.com'),
          isFalse,
        );
        expect(gateway.passwordResetCalls, 1);

        pending.complete();
        expect(await first, isTrue);
        expect(controller.busy, isFalse);
        expect(controller.passwordResetting, isFalse);
        expect(
          controller.passwordResetNotice,
          AuthController.passwordResetSuccessMessage,
        );
        expect(controller.passwordResetNotice, contains('account matches'));
        expect(controller.passwordResetNotice, isNot(contains('exists')));
        expect(controller.status, AuthStatus.signedOut);
        expect(controller.session, isNull);
      },
    );

    test(
      'password reset fails safely when its optional capability is absent',
      () async {
        final controller = AuthController(
          gateway: const UnavailableAuthGateway(),
          store: MemoryAuthSessionStore(),
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        expect(controller.supportsPasswordReset, isFalse);
        expect(
          await controller.requestPasswordReset(email: 'jordan@example.com'),
          isFalse,
        );
        expect(controller.error?.code, AuthFailureCode.providerUnavailable);
        expect(
          controller.error?.publicMessage,
          isNot(contains('account exists')),
        );
        expect(controller.passwordResetNotice, isNull);
      },
    );

    test('password reset exposes only safe provider failures', () async {
      final gateway = FakeGoogleAuthGateway()
        ..passwordResetError = const AuthException(
          code: AuthFailureCode.rateLimited,
          publicMessage:
              'Too many password reset attempts. Wait a moment and try again.',
          retryable: true,
        );
      final controller = AuthController(
        gateway: gateway,
        store: MemoryAuthSessionStore(),
        clock: () => authTestNow,
        ownsGateway: false,
        initializeImmediately: false,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(
        await controller.requestPasswordReset(email: 'jordan@example.com'),
        isFalse,
      );
      expect(controller.error?.code, AuthFailureCode.rateLimited);
      expect(controller.error?.retryable, isTrue);
      expect(controller.error?.publicMessage, isNot(contains('registered')));
      expect(controller.passwordResetNotice, isNull);
    });

    test(
      'weak signup input creates no gateway or storage side effect',
      () async {
        final gateway = FakeAuthGateway();
        final store = MemoryAuthSessionStore();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        final success = await controller.signUp(
          name: 'Jordan Lee',
          email: 'jordan@example.com',
          password: 'too-short',
        );

        expect(success, isFalse);
        expect(controller.error?.code, AuthFailureCode.weakPassword);
        expect(gateway.signUpCalls, 0);
        expect(store.value, isNull);
        expect(controller.status, AuthStatus.signedOut);
      },
    );

    test(
      'signup creates only an in-memory challenge until the code is verified',
      () async {
        final gateway = FakeAuthGateway();
        final store = MemoryAuthSessionStore();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        final started = await controller.signUp(
          name: '  Jordan   Lee ',
          email: ' Jordan@Example.COM ',
          password: 'Correct-Horse-9!Battery',
        );

        expect(started, isTrue);
        expect(controller.status, AuthStatus.signedOut);
        expect(controller.session, isNull);
        expect(controller.signupResult, isNull);
        expect(store.value, isNull);
        expect(controller.pendingVerification?.email, 'jordan@example.com');
        expect(
          controller.pendingVerification?.challengeToken,
          authTestChallengeToken,
        );
        expect(gateway.lastName, 'Jordan Lee');
        expect(gateway.lastEmail, 'jordan@example.com');
      },
    );

    test(
      'only a valid six-digit code can create and persist the session',
      () async {
        final gateway = FakeAuthGateway();
        final store = MemoryAuthSessionStore();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.signUp(
          name: 'Jordan Lee',
          email: 'jordan@example.com',
          password: 'Correct-Horse-9!Battery',
        );

        expect(await controller.verifyEmail('12a45'), isFalse);
        expect(gateway.verifyEmailCalls, 0);
        expect(controller.error?.code, AuthFailureCode.invalidVerificationCode);
        expect(store.value, isNull);

        final verified = await controller.verifyEmail(' 123456 ');

        expect(verified, isTrue);
        expect(gateway.verifyEmailCalls, 1);
        expect(gateway.lastChallengeToken, authTestChallengeToken);
        expect(gateway.lastCode, '123456');
        expect(controller.pendingVerification, isNull);
        expect(controller.status, AuthStatus.signedIn);
        expect(store.value, same(gateway.verifyEmailResult.session));
        expect(controller.signupResult, same(gateway.verifyEmailResult));
      },
    );

    test(
      'email-link verification needs no numeric code and persists its session',
      () async {
        final gateway = FakeAuthGateway()
          ..signUpResult = authTestVerification(
            method: EmailVerificationMethod.link,
          );
        final store = MemoryAuthSessionStore();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.signUp(
          name: 'Jordan Lee',
          email: 'jordan@example.com',
          password: 'Correct-Horse-9!Battery',
        );

        final verified = await controller.verifyEmail();

        expect(verified, isTrue);
        expect(gateway.verifyEmailCalls, 1);
        expect(gateway.lastChallengeToken, authTestChallengeToken);
        expect(gateway.lastCode, isEmpty);
        expect(controller.pendingVerification, isNull);
        expect(controller.status, AuthStatus.signedIn);
        expect(store.value, same(gateway.verifyEmailResult.session));
      },
    );

    test(
      'provider bootstrap restores a pending email-link challenge without a local token',
      () async {
        final challenge = authTestVerification(
          method: EmailVerificationMethod.link,
        );
        final gateway = _ProviderAuthGateway()
          ..bootstrapResult = AuthBootstrapResult(
            verificationChallenge: challenge,
          );
        final store = MemoryAuthSessionStore();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(gateway.bootstrapCalls, 1);
        expect(controller.status, AuthStatus.signedOut);
        expect(controller.pendingVerification, same(challenge));
        expect(controller.session, isNull);
        expect(store.value, isNull);
      },
    );

    test(
      'provider bootstrap persists an already verified Firebase session',
      () async {
        final session = authTestSession(accessToken: 'bootstrap-token');
        final gateway = _ProviderAuthGateway()
          ..bootstrapResult = AuthBootstrapResult(session: session);
        final store = MemoryAuthSessionStore();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(gateway.bootstrapCalls, 1);
        expect(controller.status, AuthStatus.signedIn);
        expect(controller.session, same(session));
        expect(store.value, same(session));
        expect(controller.pendingVerification, isNull);
      },
    );

    test(
      'refresh-capable provider restores an expired cached token on restart',
      () async {
        final expired = authTestSession(
          accessToken: 'expired-cache-token',
          expiresAt: authTestNow,
        );
        final restored = authTestSession(
          accessToken: 'restored-firebase-token',
        );
        final store = MemoryAuthSessionStore(expired);
        final gateway = _ProviderAuthGateway()..restoreResult = restored;
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(gateway.restoreCalls, 1);
        expect(gateway.lastRestoredSession, same(expired));
        expect(controller.status, AuthStatus.signedIn);
        expect(controller.session, same(restored));
        expect(store.value, same(restored));
      },
    );

    test(
      'unverified sign-in moves to the provider email-link challenge',
      () async {
        final challenge = authTestVerification(
          method: EmailVerificationMethod.link,
        );
        final gateway = _ProviderAuthGateway()
          ..signInError = AuthException(
            code: AuthFailureCode.verificationRequired,
            publicMessage: 'Verify your email before signing in.',
            verificationChallenge: challenge,
          );
        final controller = AuthController(
          gateway: gateway,
          store: MemoryAuthSessionStore(),
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        final signedIn = await controller.signIn(
          email: 'jordan@example.com',
          password: 'Correct-Horse-9!Battery',
        );

        expect(signedIn, isFalse);
        expect(controller.status, AuthStatus.signedOut);
        expect(controller.pendingVerification, same(challenge));
        expect(controller.error?.code, AuthFailureCode.verificationRequired);
        expect(controller.session, isNull);
      },
    );

    test(
      'access tokens refresh through the provider and update the cache',
      () async {
        final initial = authTestSession(accessToken: 'cached-firebase-token');
        final refreshed = authTestSession(accessToken: 'fresh-firebase-token');
        final store = MemoryAuthSessionStore(initial);
        final gateway = _ProviderAuthGateway()
          ..restoreResult = initial
          ..refreshResult = refreshed;
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        final token = await controller.accessToken();

        expect(token, 'fresh-firebase-token');
        expect(gateway.refreshCalls, 1);
        expect(gateway.lastRefreshSession, same(initial));
        expect(controller.session, same(refreshed));
        expect(store.value, same(refreshed));
      },
    );

    test(
      'editing email waits for provider cleanup before dropping the challenge',
      () async {
        final pendingCancel = Completer<void>();
        final gateway = _ProviderAuthGateway()
          ..signUpResult = authTestVerification(
            method: EmailVerificationMethod.link,
          )
          ..cancelPendingCompleter = pendingCancel;
        final controller = AuthController(
          gateway: gateway,
          store: MemoryAuthSessionStore(),
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.signUp(
          name: 'Jordan Lee',
          email: 'jordan@example.com',
          password: 'Correct-Horse-9!Battery',
        );

        final cancel = controller.cancelEmailVerification();
        await Future<void>.delayed(Duration.zero);

        expect(gateway.cancelPendingCalls, 1);
        expect(controller.busy, isTrue);
        expect(controller.pendingVerification, isNotNull);

        pendingCancel.complete();
        expect(await cancel, isTrue);
        expect(controller.busy, isFalse);
        expect(controller.pendingVerification, isNull);
      },
    );

    test(
      'wrong code preserves the challenge and resend rotates its opaque token',
      () async {
        var now = authTestNow;
        final initial = authTestVerification(
          resendAvailableAt: authTestNow.add(const Duration(seconds: 30)),
        );
        final rotated = authTestVerification(
          challengeToken: authTestRotatedChallengeToken,
          resendAvailableAt: authTestNow.add(const Duration(minutes: 1)),
        );
        final gateway = FakeAuthGateway()
          ..signUpResult = initial
          ..resendVerificationResult = rotated
          ..verifyEmailError = const AuthException(
            code: AuthFailureCode.invalidVerificationCode,
            publicMessage: 'That confirmation code is not correct. Try again.',
          );
        final store = MemoryAuthSessionStore();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => now,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.signUp(
          name: 'Jordan Lee',
          email: 'jordan@example.com',
          password: 'Correct-Horse-9!Battery',
        );

        expect(await controller.verifyEmail('000000'), isFalse);
        expect(controller.pendingVerification, same(initial));
        expect(store.value, isNull);

        expect(await controller.resendVerification(), isFalse);
        expect(gateway.resendVerificationCalls, 0);
        expect(controller.error?.code, AuthFailureCode.rateLimited);

        now = now.add(const Duration(seconds: 30));
        expect(await controller.resendVerification(), isTrue);
        expect(gateway.resendVerificationCalls, 1);
        expect(gateway.lastChallengeToken, initial.challengeToken);
        expect(controller.pendingVerification, same(rotated));
        expect(store.value, isNull);
      },
    );

    test(
      'an expired code can be refreshed without creating a session',
      () async {
        var now = authTestNow;
        final gateway = FakeAuthGateway()
          ..resendVerificationResult = authTestVerification(
            challengeToken: authTestRotatedChallengeToken,
            expiresAt: authTestNow.add(const Duration(minutes: 25)),
            resendAvailableAt: authTestNow.add(const Duration(minutes: 16)),
          );
        final store = MemoryAuthSessionStore();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => now,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.signUp(
          name: 'Jordan Lee',
          email: 'jordan@example.com',
          password: 'Correct-Horse-9!Battery',
        );
        now = now.add(const Duration(minutes: 15));

        expect(await controller.verifyEmail('123456'), isFalse);
        expect(gateway.verifyEmailCalls, 0);
        expect(controller.error?.code, AuthFailureCode.verificationExpired);
        expect(
          controller.error?.publicMessage,
          'This code expired. Send a new code.',
        );
        expect(controller.pendingVerification, isNotNull);
        expect(store.value, isNull);

        expect(await controller.resendVerification(), isTrue);
        expect(
          controller.pendingVerification?.challengeToken,
          authTestRotatedChallengeToken,
        );
        expect(controller.status, AuthStatus.signedOut);
        expect(store.value, isNull);
      },
    );

    test(
      'initialization is single-flight and persists the verified session',
      () async {
        final stored = authTestSession(accessToken: 'stored-token');
        final refreshed = authTestSession(accessToken: 'verified-token');
        final store = MemoryAuthSessionStore(stored);
        final gateway = FakeAuthGateway();
        final pending = Completer<AuthSession>();
        gateway.restoreCompleter = pending;
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);

        final first = controller.initialize();
        final second = controller.initialize();
        await Future<void>.delayed(Duration.zero);

        expect(gateway.restoreCalls, 1);
        expect(gateway.lastRestoredSession, same(stored));
        pending.complete(refreshed);
        await Future.wait([first, second]);

        expect(controller.status, AuthStatus.signedIn);
        expect(store.value, same(refreshed));
        expect(await controller.accessToken(), 'verified-token');
      },
    );

    test(
      'an exactly expired session is cleared without contacting the provider',
      () async {
        final expired = authTestSession(expiresAt: authTestNow);
        final store = MemoryAuthSessionStore(expired);
        final gateway = FakeAuthGateway();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(controller.status, AuthStatus.signedOut);
        expect(controller.session, isNull);
        expect(store.value, isNull);
        expect(gateway.restoreCalls, 0);
        expect(await controller.accessToken(), isNull);
      },
    );

    test(
      'logout clears local state and revokes the verified server session',
      () async {
        final session = authTestSession();
        final store = MemoryAuthSessionStore(session);
        final gateway = FakeAuthGateway()..restoreResult = session;
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.signOut();

        expect(controller.status, AuthStatus.signedOut);
        expect(controller.session, isNull);
        expect(store.value, isNull);
        expect(gateway.signOutCalls, 1);
        expect(gateway.lastSignedOutSession, same(session));
        expect(await controller.accessToken(), isNull);
      },
    );

    test(
      'logout stays signed in when both secure clear and revocation fail',
      () async {
        final session = authTestSession();
        final store = MemoryAuthSessionStore(session);
        final gateway = FakeAuthGateway()..restoreResult = session;
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        store.clearError = StateError('secure store unavailable');
        gateway.signOutError = const AuthException.providerUnavailable();

        await controller.signOut();

        expect(controller.status, AuthStatus.signedIn);
        expect(controller.session, same(session));
        expect(controller.error?.code, AuthFailureCode.storageUnavailable);
        expect(
          controller.error?.publicMessage,
          isNot(contains('secure store')),
        );
        expect(await controller.accessToken(), session.accessToken);
      },
    );

    test(
      'logout suppresses the bearer token while revocation is pending',
      () async {
        final session = authTestSession();
        final store = MemoryAuthSessionStore(session);
        final pendingRevocation = Completer<void>();
        final gateway = FakeAuthGateway()
          ..restoreResult = session
          ..signOutCompleter = pendingRevocation;
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        final signOut = controller.signOut();
        await Future<void>.delayed(Duration.zero);

        expect(controller.busy, isTrue);
        expect(await controller.accessToken(), isNull);
        pendingRevocation.complete();
        await signOut;
        expect(controller.status, AuthStatus.signedOut);
      },
    );

    test(
      'demo mode never exposes an account token and can be left cleanly',
      () async {
        final store = MemoryAuthSessionStore();
        final gateway = FakeAuthGateway();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          allowDemo: true,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.continueAsDemo();
        expect(controller.status, AuthStatus.demo);
        expect(await controller.accessToken(), isNull);

        await controller.signOut();
        expect(controller.status, AuthStatus.signedOut);
        expect(store.value, isNull);
        expect(gateway.signOutCalls, 0);
      },
    );

    test(
      'signed-out demo remains available when secure storage is unavailable',
      () async {
        final store = MemoryAuthSessionStore()
          ..readError = StateError('secure read failed')
          ..clearError = StateError('secure clear failed');
        final gateway = FakeAuthGateway();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          allowDemo: true,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        expect(controller.status, AuthStatus.signedOut);
        expect(controller.error?.code, AuthFailureCode.storageUnavailable);

        await controller.continueAsDemo();

        expect(controller.status, AuthStatus.demo);
        expect(controller.session, isNull);
        expect(controller.error, isNull);
        expect(await controller.accessToken(), isNull);
      },
    );

    test(
      'signed-in session still fails closed when demo clear fails',
      () async {
        final stored = authTestResult().session;
        final store = MemoryAuthSessionStore(stored)
          ..clearError = StateError('secure clear failed');
        final gateway = FakeAuthGateway()..restoreResult = stored;
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          allowDemo: true,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        expect(controller.status, AuthStatus.signedIn);

        await controller.continueAsDemo();

        expect(controller.status, AuthStatus.signedIn);
        expect(controller.session, same(stored));
        expect(controller.error?.code, AuthFailureCode.storageUnavailable);
        expect(await controller.accessToken(), stored.accessToken);
      },
    );

    test(
      'provider failure never creates a local account or claims success',
      () async {
        final gateway = FakeAuthGateway()
          ..signUpError = const AuthException.providerUnavailable();
        final store = MemoryAuthSessionStore();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        final success = await controller.signUp(
          name: 'Jordan Lee',
          email: 'jordan@example.com',
          password: 'Correct-Horse-9!Battery',
        );

        expect(success, isFalse);
        expect(controller.status, AuthStatus.signedOut);
        expect(controller.session, isNull);
        expect(controller.signupResult, isNull);
        expect(store.value, isNull);
        expect(controller.error?.code, AuthFailureCode.providerUnavailable);
      },
    );

    test('Google sign-in stores only the Firebase session', () async {
      final googleSession = authTestSession(
        accessToken: 'firebase-google-id-token',
      );
      final gateway = FakeGoogleAuthGateway()
        ..googleSignInResult = AuthResult(session: googleSession);
      final store = MemoryAuthSessionStore();
      final controller = AuthController(
        gateway: gateway,
        store: store,
        clock: () => authTestNow,
        ownsGateway: false,
        initializeImmediately: false,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      final success = await controller.signInWithGoogle();

      expect(controller.supportsGoogleSignIn, isTrue);
      expect(success, isTrue);
      expect(gateway.googleSignInCalls, 1);
      expect(controller.status, AuthStatus.signedIn);
      expect(controller.session, same(googleSession));
      expect(store.value, same(googleSession));
      expect(controller.error, isNull);
    });

    test(
      'closing the Google account picker is silent and signs in nobody',
      () async {
        final gateway = FakeGoogleAuthGateway()..googleSignInResult = null;
        final store = MemoryAuthSessionStore();
        final controller = AuthController(
          gateway: gateway,
          store: store,
          clock: () => authTestNow,
          ownsGateway: false,
          initializeImmediately: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        final success = await controller.signInWithGoogle();

        expect(success, isFalse);
        expect(gateway.googleSignInCalls, 1);
        expect(controller.status, AuthStatus.signedOut);
        expect(controller.session, isNull);
        expect(controller.error, isNull);
        expect(store.value, isNull);
      },
    );

    test('signup notice distinguishes sent, pending, and failed delivery', () {
      final sent = authTestResult(
        welcomeEmailSent: true,
        welcomeEmailStatus: 'sent',
      );
      final pending = authTestResult(
        welcomeEmailSent: false,
        welcomeEmailStatus: 'pending',
      );
      final failed = authTestResult(
        welcomeEmailSent: false,
        welcomeEmailStatus: 'failed',
      );

      expect(sent.signupNotice(), contains('accepted for delivery'));
      expect(pending.signupNotice(), contains('delivery is still pending'));
      expect(pending.signupNotice(), isNot(contains('was sent')));
      expect(failed.signupNotice(), contains('could not be sent'));
      expect(failed.signupNotice(), isNot(contains('pending')));
    });
  });
}
