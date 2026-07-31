import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart' as google;

import 'package:drip/auth/auth_models.dart';
import 'package:drip/auth/firebase_auth_gateway.dart';
import 'package:drip/auth/firebase_email_code_client.dart';
import 'package:drip/auth/google_identity_client.dart';

import 'auth_test_fakes.dart';

final class _FakeFirebaseAuth implements firebase.FirebaseAuth {
  firebase.User? user;
  firebase.UserCredential? signUpCredential;
  firebase.UserCredential? signInCredential;
  firebase.UserCredential? googleCredential;
  Object? signUpError;
  Object? signInError;
  Object? googleError;
  Object? signOutError;
  Object? passwordResetError;
  int signUpCalls = 0;
  int signInCalls = 0;
  int googleCalls = 0;
  int signOutCalls = 0;
  int passwordResetCalls = 0;
  String? lastEmail;
  String? lastPassword;
  String? lastPasswordResetEmail;
  firebase.AuthCredential? lastGoogleCredential;

  @override
  firebase.User? get currentUser => user;

  @override
  Future<firebase.UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signUpCalls += 1;
    lastEmail = email;
    lastPassword = password;
    final error = signUpError;
    if (error != null) throw error;
    final credential = signUpCredential;
    if (credential == null) throw StateError('Missing fake signup credential.');
    user = credential.user;
    return credential;
  }

  @override
  Future<firebase.UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signInCalls += 1;
    lastEmail = email;
    lastPassword = password;
    final error = signInError;
    if (error != null) throw error;
    final credential = signInCredential;
    if (credential == null) throw StateError('Missing fake signin credential.');
    user = credential.user;
    return credential;
  }

  @override
  Future<firebase.UserCredential> signInWithCredential(
    firebase.AuthCredential credential,
  ) async {
    googleCalls += 1;
    lastGoogleCredential = credential;
    final error = googleError;
    if (error != null) throw error;
    final result = googleCredential;
    if (result == null) throw StateError('Missing fake Google credential.');
    user = result.user;
    return result;
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    firebase.ActionCodeSettings? actionCodeSettings,
  }) async {
    passwordResetCalls += 1;
    lastPasswordResetEmail = email;
    final error = passwordResetError;
    if (error != null) throw error;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    final error = signOutError;
    if (error != null) throw error;
    user = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeGoogleIdentityClient implements GoogleIdentityClient {
  String idToken = 'google-provider-id-token';
  Object? requestError;
  Object? signOutError;
  int requestCalls = 0;
  int signOutCalls = 0;

  @override
  Future<String> requestIdToken() async {
    requestCalls += 1;
    final error = requestError;
    if (error != null) throw error;
    return idToken;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    final error = signOutError;
    if (error != null) throw error;
  }
}

final class _FakeFirebaseEmailCodeClient implements FirebaseEmailCodeClient {
  FirebaseEmailCodeChallengeData requestResult = FirebaseEmailCodeChallengeData(
    email: 'jordan@example.com',
    expiresAt: authTestNow.add(const Duration(minutes: 10)),
    resendAvailableAt: authTestNow.add(const Duration(seconds: 60)),
  );
  FirebaseEmailCodeVerificationData verificationResult =
      const FirebaseEmailCodeVerificationData(
        email: 'jordan@example.com',
        refreshIdToken: true,
      );
  Object? requestError;
  Object? verificationError;
  int requestCalls = 0;
  int verificationCalls = 0;
  int closeCalls = 0;
  String? lastRequestIdToken;
  String? lastVerificationIdToken;
  String? lastCode;

  @override
  Future<FirebaseEmailCodeChallengeData> requestCode({
    required String idToken,
  }) async {
    requestCalls += 1;
    lastRequestIdToken = idToken;
    final error = requestError;
    if (error != null) throw error;
    return requestResult;
  }

  @override
  Future<FirebaseEmailCodeVerificationData> verifyCode({
    required String idToken,
    required String code,
  }) async {
    verificationCalls += 1;
    lastVerificationIdToken = idToken;
    lastCode = code;
    final error = verificationError;
    if (error != null) throw error;
    return verificationResult;
  }

  @override
  void close() {
    closeCalls += 1;
  }
}

final class _FakeFirebaseUser implements firebase.User {
  @override
  final String uid = 'firebase_user_123';
  @override
  final String? email = 'jordan@example.com';
  @override
  bool emailVerified;
  @override
  String? displayName;
  _FakeIdTokenResult tokenResult;
  Object? updateDisplayNameError;
  Object? sendVerificationError;
  Object? reloadError;
  Object? tokenError;
  void Function()? onReload;
  int updateDisplayNameCalls = 0;
  int sendVerificationCalls = 0;
  int reloadCalls = 0;
  int tokenCalls = 0;
  bool? lastForceRefresh;
  final List<bool> forceRefreshHistory = [];

  _FakeFirebaseUser({
    this.emailVerified = false,
    this.displayName,
    _FakeIdTokenResult? tokenResult,
  }) : tokenResult =
           tokenResult ??
           _FakeIdTokenResult(
             token: 'firebase-id-token',
             expirationTime: authTestNow.add(const Duration(hours: 1)),
           );

  @override
  Future<void> updateDisplayName(String? displayName) async {
    updateDisplayNameCalls += 1;
    final error = updateDisplayNameError;
    if (error != null) throw error;
    this.displayName = displayName;
  }

  @override
  Future<void> sendEmailVerification([
    firebase.ActionCodeSettings? actionCodeSettings,
  ]) async {
    sendVerificationCalls += 1;
    final error = sendVerificationError;
    if (error != null) throw error;
  }

  @override
  Future<void> reload() async {
    reloadCalls += 1;
    final error = reloadError;
    if (error != null) throw error;
    onReload?.call();
  }

  @override
  Future<firebase.IdTokenResult> getIdTokenResult([
    bool forceRefresh = false,
  ]) async {
    tokenCalls += 1;
    lastForceRefresh = forceRefresh;
    forceRefreshHistory.add(forceRefresh);
    final error = tokenError;
    if (error != null) throw error;
    return tokenResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeUserCredential implements firebase.UserCredential {
  @override
  final firebase.User? user;

  const _FakeUserCredential(this.user);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeIdTokenResult implements firebase.IdTokenResult {
  @override
  final String? token;
  @override
  final DateTime? expirationTime;

  const _FakeIdTokenResult({required this.token, required this.expirationTime});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<AuthException> _authFailure(Future<Object?> operation) async {
  try {
    await operation;
    fail('Expected authentication to fail.');
  } on AuthException catch (error) {
    return error;
  }
}

void main() {
  group('FirebaseAuthGateway', () {
    test(
      'signup updates the profile and sends a Firebase verification link',
      () async {
        final user = _FakeFirebaseUser();
        final auth = _FakeFirebaseAuth()
          ..signUpCredential = _FakeUserCredential(user);
        final gateway = FirebaseAuthGateway(
          auth: auth,
          clock: () => authTestNow,
        );

        final challenge = await gateway.signUp(
          name: 'Jordan Lee',
          email: 'jordan@example.com',
          password: 'Correct-Horse-9!Battery',
        );

        expect(auth.signUpCalls, 1);
        expect(auth.lastEmail, 'jordan@example.com');
        expect(auth.lastPassword, 'Correct-Horse-9!Battery');
        expect(user.updateDisplayNameCalls, 1);
        expect(user.displayName, 'Jordan Lee');
        expect(user.sendVerificationCalls, 1);
        expect(challenge.method, EmailVerificationMethod.link);
        expect(challenge.email, 'jordan@example.com');
        expect(challenge.challengeToken, user.uid);
        expect(
          challenge.resendAvailableAt,
          authTestNow.add(const Duration(seconds: 60)),
        );
        expect(challenge.expiresAt, authTestNow.add(const Duration(hours: 1)));
      },
    );

    test(
      'verification-email delivery failure keeps a recoverable pending challenge',
      () async {
        final user = _FakeFirebaseUser()
          ..sendVerificationError = firebase.FirebaseAuthException(
            code: 'network-request-failed',
          );
        final auth = _FakeFirebaseAuth()
          ..signUpCredential = _FakeUserCredential(user);
        final gateway = FirebaseAuthGateway(
          auth: auth,
          clock: () => authTestNow,
        );

        final error = await _authFailure(
          gateway.signUp(
            name: 'Jordan Lee',
            email: 'jordan@example.com',
            password: 'Correct-Horse-9!Battery',
          ),
        );

        expect(error.code, AuthFailureCode.providerUnavailable);
        expect(error.retryable, isTrue);
        expect(
          error.verificationChallenge?.method,
          EmailVerificationMethod.link,
        );
        expect(error.verificationChallenge?.challengeToken, user.uid);
        expect(error.publicMessage, contains('account was created'));
        expect(auth.currentUser, same(user));
      },
    );

    test(
      'an injected code transport does not opt the current build out of Firebase links',
      () async {
        final user = _FakeFirebaseUser();
        final auth = _FakeFirebaseAuth()
          ..signUpCredential = _FakeUserCredential(user);
        final emailCodeClient = _FakeFirebaseEmailCodeClient();
        final gateway = FirebaseAuthGateway(
          auth: auth,
          emailCodeClient: emailCodeClient,
          clock: () => authTestNow,
        );

        final challenge = await gateway.signUp(
          name: 'Jordan Lee',
          email: 'jordan@example.com',
          password: 'Correct-Horse-9!Battery',
        );

        expect(challenge.method, EmailVerificationMethod.link);
        expect(user.sendVerificationCalls, 1);
        expect(emailCodeClient.requestCalls, 0);
        expect(user.tokenCalls, 0);
      },
    );

    test(
      'enabled signup requests a server code with a fresh unverified Firebase token',
      () async {
        final user = _FakeFirebaseUser();
        final auth = _FakeFirebaseAuth()
          ..signUpCredential = _FakeUserCredential(user);
        final emailCodeClient = _FakeFirebaseEmailCodeClient();
        final gateway = FirebaseAuthGateway(
          auth: auth,
          emailCodeClient: emailCodeClient,
          emailCodeEnabled: true,
          clock: () => authTestNow,
        );

        final challenge = await gateway.signUp(
          name: 'Jordan Lee',
          email: 'jordan@example.com',
          password: 'Correct-Horse-9!Battery',
        );

        expect(challenge.method, EmailVerificationMethod.code);
        expect(challenge.challengeToken, user.uid);
        expect(challenge.email, 'jordan@example.com');
        expect(challenge.expiresAt, emailCodeClient.requestResult.expiresAt);
        expect(
          challenge.resendAvailableAt,
          emailCodeClient.requestResult.resendAvailableAt,
        );
        expect(emailCodeClient.requestCalls, 1);
        expect(emailCodeClient.lastRequestIdToken, 'firebase-id-token');
        expect(user.forceRefreshHistory, [isTrue]);
        expect(user.sendVerificationCalls, 0);
      },
    );

    test(
      'code delivery failure keeps a privacy-safe recoverable code challenge',
      () async {
        final user = _FakeFirebaseUser();
        final auth = _FakeFirebaseAuth()
          ..signUpCredential = _FakeUserCredential(user);
        final emailCodeClient = _FakeFirebaseEmailCodeClient()
          ..requestError = StateError('sensitive upstream provider detail');
        final gateway = FirebaseAuthGateway(
          auth: auth,
          emailCodeClient: emailCodeClient,
          emailCodeEnabled: true,
          clock: () => authTestNow,
        );

        final error = await _authFailure(
          gateway.signUp(
            name: 'Jordan Lee',
            email: 'jordan@example.com',
            password: 'Correct-Horse-9!Battery',
          ),
        );

        expect(error.code, AuthFailureCode.providerUnavailable);
        expect(error.retryable, isTrue);
        expect(error.publicMessage, contains('account was created'));
        expect(error.publicMessage, contains('send a new code'));
        expect(error.publicMessage, isNot(contains('upstream')));
        expect(
          error.verificationChallenge?.method,
          EmailVerificationMethod.code,
        );
        expect(error.verificationChallenge?.challengeToken, user.uid);
        expect(error.verificationChallenge?.resendAvailableAt, authTestNow);
        expect(auth.currentUser, same(user));
        expect(user.sendVerificationCalls, 0);
      },
    );

    test(
      'unverified sign-in returns a link challenge and no app session',
      () async {
        final user = _FakeFirebaseUser(emailVerified: false);
        final auth = _FakeFirebaseAuth()
          ..signInCredential = _FakeUserCredential(user);
        final gateway = FirebaseAuthGateway(
          auth: auth,
          clock: () => authTestNow,
        );

        final error = await _authFailure(
          gateway.signIn(
            email: 'jordan@example.com',
            password: 'Correct-Horse-9!Battery',
          ),
        );

        expect(error.code, AuthFailureCode.verificationRequired);
        expect(
          error.verificationChallenge?.method,
          EmailVerificationMethod.link,
        );
        expect(error.verificationChallenge?.challengeToken, user.uid);
        expect(error.verificationChallenge?.resendAvailableAt, authTestNow);
        expect(user.tokenCalls, 0);
      },
    );

    test(
      'enabled sign-in and bootstrap recover code challenges without sending duplicates',
      () async {
        final user = _FakeFirebaseUser(emailVerified: false);
        final auth = _FakeFirebaseAuth()
          ..signInCredential = _FakeUserCredential(user);
        final emailCodeClient = _FakeFirebaseEmailCodeClient();
        final gateway = FirebaseAuthGateway(
          auth: auth,
          emailCodeClient: emailCodeClient,
          emailCodeEnabled: true,
          clock: () => authTestNow,
        );

        final signInError = await _authFailure(
          gateway.signIn(
            email: 'jordan@example.com',
            password: 'Correct-Horse-9!Battery',
          ),
        );
        final bootstrap = await gateway.bootstrap();

        expect(signInError.code, AuthFailureCode.verificationRequired);
        expect(
          signInError.verificationChallenge?.method,
          EmailVerificationMethod.code,
        );
        expect(
          signInError.verificationChallenge?.resendAvailableAt,
          authTestNow,
        );
        expect(signInError.publicMessage, contains('confirmation code'));
        expect(
          bootstrap.verificationChallenge?.method,
          EmailVerificationMethod.code,
        );
        expect(bootstrap.verificationChallenge?.challengeToken, user.uid);
        expect(emailCodeClient.requestCalls, 0);
        expect(user.sendVerificationCalls, 0);
      },
    );

    test(
      'Google ID token is exchanged for a verified Firebase session and cleared on sign-out',
      () async {
        final user = _FakeFirebaseUser(
          emailVerified: true,
          displayName: 'Jordan Lee',
          tokenResult: _FakeIdTokenResult(
            token: 'firebase-session-id-token',
            expirationTime: authTestNow.add(const Duration(minutes: 50)),
          ),
        );
        final auth = _FakeFirebaseAuth()
          ..googleCredential = _FakeUserCredential(user);
        final googleIdentity = _FakeGoogleIdentityClient();
        final gateway = FirebaseAuthGateway(
          auth: auth,
          googleIdentity: googleIdentity,
          clock: () => authTestNow,
        );

        final result = await gateway.signInWithGoogle();

        expect(result, isNotNull);
        expect(googleIdentity.requestCalls, 1);
        expect(auth.googleCalls, 1);
        expect(auth.lastGoogleCredential?.providerId, 'google.com');
        expect(result?.session.user.id, user.uid);
        expect(result?.session.user.name, 'Jordan Lee');
        expect(result?.session.accessToken, 'firebase-session-id-token');
        expect(
          result?.session.accessToken,
          isNot(googleIdentity.idToken),
          reason: 'Only Firebase ID tokens belong in Drip sessions.',
        );
        expect(user.lastForceRefresh, isTrue);

        await gateway.signOut(result!.session);

        expect(auth.signOutCalls, 1);
        expect(googleIdentity.signOutCalls, 1);
      },
    );

    test('closing Google account selection returns no account error', () async {
      final auth = _FakeFirebaseAuth();
      final googleIdentity = _FakeGoogleIdentityClient()
        ..requestError = const google.GoogleSignInException(
          code: google.GoogleSignInExceptionCode.canceled,
        );
      final gateway = FirebaseAuthGateway(
        auth: auth,
        googleIdentity: googleIdentity,
        clock: () => authTestNow,
      );

      final result = await gateway.signInWithGoogle();

      expect(result, isNull);
      expect(googleIdentity.requestCalls, 1);
      expect(auth.googleCalls, 0);
      expect(auth.currentUser, isNull);
    });

    test(
      'Google configuration failures use a safe actionable message',
      () async {
        final auth = _FakeFirebaseAuth();
        final googleIdentity = _FakeGoogleIdentityClient()
          ..requestError = const google.GoogleSignInException(
            code: google.GoogleSignInExceptionCode.clientConfigurationError,
            description: 'sensitive provider detail',
          );
        final gateway = FirebaseAuthGateway(
          auth: auth,
          googleIdentity: googleIdentity,
          clock: () => authTestNow,
        );

        final error = await _authFailure(gateway.signInWithGoogle());

        expect(error.code, AuthFailureCode.providerUnavailable);
        expect(error.publicMessage, contains('Use email for now'));
        expect(error.publicMessage, isNot(contains('sensitive')));
        expect(auth.googleCalls, 0);
      },
    );

    test(
      'password reset treats a missing account like an accepted request',
      () async {
        for (final providerError in <Object?>[
          null,
          firebase.FirebaseAuthException(code: 'user-not-found'),
        ]) {
          final auth = _FakeFirebaseAuth()..passwordResetError = providerError;
          final gateway = FirebaseAuthGateway(
            auth: auth,
            clock: () => authTestNow,
          );

          await gateway.sendPasswordResetEmail(email: 'jordan@example.com');

          expect(auth.passwordResetCalls, 1);
          expect(auth.lastPasswordResetEmail, 'jordan@example.com');
        }
      },
    );

    test(
      'password reset maps rate and network failures without account details',
      () async {
        for (final expectation in [
          (
            providerCode: 'too-many-requests',
            publicCode: AuthFailureCode.rateLimited,
          ),
          (
            providerCode: 'network-request-failed',
            publicCode: AuthFailureCode.providerUnavailable,
          ),
        ]) {
          final auth = _FakeFirebaseAuth()
            ..passwordResetError = firebase.FirebaseAuthException(
              code: expectation.providerCode,
            );
          final gateway = FirebaseAuthGateway(
            auth: auth,
            clock: () => authTestNow,
          );

          final error = await _authFailure(
            gateway.sendPasswordResetEmail(email: 'jordan@example.com'),
          );

          expect(error.code, expectation.publicCode);
          expect(error.retryable, isTrue);
          expect(error.publicMessage, isNot(contains('registered')));
          expect(error.publicMessage, isNot(contains('account exists')));
        }
      },
    );

    test(
      'email-link check reloads Firebase and force-refreshes a verified ID token',
      () async {
        final user = _FakeFirebaseUser(emailVerified: false)
          ..onReload = () {}
          ..tokenResult = _FakeIdTokenResult(
            token: 'verified-firebase-token',
            expirationTime: authTestNow.add(const Duration(minutes: 55)),
          );
        user.onReload = () => user.emailVerified = true;
        final auth = _FakeFirebaseAuth()..user = user;
        final gateway = FirebaseAuthGateway(
          auth: auth,
          clock: () => authTestNow,
        );

        final result = await gateway.verifyEmail(
          challengeToken: user.uid,
          code: '',
        );

        expect(user.reloadCalls, 1);
        expect(user.tokenCalls, 1);
        expect(user.lastForceRefresh, isTrue);
        expect(result.session.user.id, user.uid);
        expect(result.session.user.name, 'Drip member');
        expect(result.session.accessToken, 'verified-firebase-token');
        expect(result.welcomeEmailStatus, 'email_verified');
      },
    );

    test(
      'code verification posts the code then reloads and force-refreshes Firebase',
      () async {
        final user = _FakeFirebaseUser(emailVerified: false)
          ..tokenResult = _FakeIdTokenResult(
            token: 'fresh-pending-firebase-token',
            expirationTime: authTestNow.add(const Duration(minutes: 55)),
          );
        user.onReload = () => user.emailVerified = true;
        final auth = _FakeFirebaseAuth()..user = user;
        final emailCodeClient = _FakeFirebaseEmailCodeClient();
        final gateway = FirebaseAuthGateway(
          auth: auth,
          emailCodeClient: emailCodeClient,
          emailCodeEnabled: true,
          clock: () => authTestNow,
        );

        final result = await gateway.verifyEmail(
          challengeToken: user.uid,
          code: '042739',
        );

        expect(emailCodeClient.verificationCalls, 1);
        expect(
          emailCodeClient.lastVerificationIdToken,
          'fresh-pending-firebase-token',
        );
        expect(emailCodeClient.lastCode, '042739');
        expect(user.reloadCalls, 1);
        expect(user.tokenCalls, 2);
        expect(user.forceRefreshHistory, [isTrue, isTrue]);
        expect(result.session.user.id, user.uid);
        expect(result.session.accessToken, 'fresh-pending-firebase-token');
        expect(result.welcomeEmailStatus, 'email_verified');
      },
    );

    test(
      'code verification rejects malformed codes without sending a token',
      () async {
        final user = _FakeFirebaseUser(emailVerified: false);
        final auth = _FakeFirebaseAuth()..user = user;
        final emailCodeClient = _FakeFirebaseEmailCodeClient();
        final gateway = FirebaseAuthGateway(
          auth: auth,
          emailCodeClient: emailCodeClient,
          emailCodeEnabled: true,
          clock: () => authTestNow,
        );

        final error = await _authFailure(
          gateway.verifyEmail(challengeToken: user.uid, code: '12345x'),
        );

        expect(error.code, AuthFailureCode.invalidVerificationCode);
        expect(emailCodeClient.verificationCalls, 0);
        expect(user.tokenCalls, 0);
        expect(user.reloadCalls, 0);
      },
    );

    test(
      'code verification fails closed on a mismatched server identity',
      () async {
        final user = _FakeFirebaseUser(emailVerified: false);
        final auth = _FakeFirebaseAuth()..user = user;
        final emailCodeClient = _FakeFirebaseEmailCodeClient()
          ..verificationResult = const FirebaseEmailCodeVerificationData(
            email: 'attacker@example.com',
            refreshIdToken: true,
          );
        final gateway = FirebaseAuthGateway(
          auth: auth,
          emailCodeClient: emailCodeClient,
          emailCodeEnabled: true,
          clock: () => authTestNow,
        );

        final error = await _authFailure(
          gateway.verifyEmail(challengeToken: user.uid, code: '042739'),
        );

        expect(error.code, AuthFailureCode.invalidResponse);
        expect(emailCodeClient.verificationCalls, 1);
        expect(user.reloadCalls, 0);
      },
    );

    test(
      'enabled resend rotates the server code without using Firebase email links',
      () async {
        final user = _FakeFirebaseUser(emailVerified: false);
        final auth = _FakeFirebaseAuth()..user = user;
        final emailCodeClient = _FakeFirebaseEmailCodeClient();
        final gateway = FirebaseAuthGateway(
          auth: auth,
          emailCodeClient: emailCodeClient,
          emailCodeEnabled: true,
          clock: () => authTestNow,
        );

        final challenge = await gateway.resendVerification(
          challengeToken: user.uid,
        );

        expect(challenge.method, EmailVerificationMethod.code);
        expect(challenge.challengeToken, user.uid);
        expect(challenge.expiresAt, emailCodeClient.requestResult.expiresAt);
        expect(emailCodeClient.requestCalls, 1);
        expect(emailCodeClient.lastRequestIdToken, 'firebase-id-token');
        expect(user.sendVerificationCalls, 0);
      },
    );

    test(
      'code delivery rejects a response for another email without losing Firebase state',
      () async {
        final user = _FakeFirebaseUser(emailVerified: false);
        final auth = _FakeFirebaseAuth()..user = user;
        final emailCodeClient = _FakeFirebaseEmailCodeClient()
          ..requestResult = FirebaseEmailCodeChallengeData(
            email: 'attacker@example.com',
            expiresAt: authTestNow.add(const Duration(minutes: 10)),
            resendAvailableAt: authTestNow.add(const Duration(seconds: 60)),
          );
        final gateway = FirebaseAuthGateway(
          auth: auth,
          emailCodeClient: emailCodeClient,
          emailCodeEnabled: true,
          clock: () => authTestNow,
        );

        final error = await _authFailure(
          gateway.resendVerification(challengeToken: user.uid),
        );

        expect(error.code, AuthFailureCode.invalidResponse);
        expect(auth.currentUser, same(user));
        expect(user.sendVerificationCalls, 0);
      },
    );

    test(
      'bootstrap recovers both pending and verified provider state',
      () async {
        final pendingUser = _FakeFirebaseUser(emailVerified: false);
        final auth = _FakeFirebaseAuth()..user = pendingUser;
        final gateway = FirebaseAuthGateway(
          auth: auth,
          clock: () => authTestNow,
        );

        final pending = await gateway.bootstrap();

        expect(
          pending.verificationChallenge?.method,
          EmailVerificationMethod.link,
        );
        expect(pending.verificationChallenge?.challengeToken, pendingUser.uid);
        expect(pending.session, isNull);

        pendingUser.emailVerified = true;
        pendingUser.displayName = 'Jordan Lee';
        pendingUser.tokenResult = _FakeIdTokenResult(
          token: 'bootstrap-firebase-token',
          expirationTime: authTestNow.add(const Duration(minutes: 45)),
        );

        final verified = await gateway.bootstrap();

        expect(verified.verificationChallenge, isNull);
        expect(verified.session?.user.name, 'Jordan Lee');
        expect(verified.session?.accessToken, 'bootstrap-firebase-token');
        expect(pendingUser.reloadCalls, 2);
      },
    );

    test(
      'refresh returns the provider token instead of the stale cache',
      () async {
        final user = _FakeFirebaseUser(
          emailVerified: true,
          displayName: 'Jordan Lee',
          tokenResult: _FakeIdTokenResult(
            token: 'fresh-firebase-token',
            expirationTime: authTestNow.add(const Duration(minutes: 50)),
          ),
        );
        final auth = _FakeFirebaseAuth()..user = user;
        final gateway = FirebaseAuthGateway(
          auth: auth,
          clock: () => authTestNow,
        );
        final cached = authTestSession(
          user: authTestUser(id: user.uid),
          accessToken: 'stale-cached-token',
        );

        final refreshed = await gateway.refreshSession(cached);

        expect(refreshed.accessToken, 'fresh-firebase-token');
        expect(user.tokenCalls, 1);
        expect(user.lastForceRefresh, isFalse);
      },
    );

    test(
      'login failures do not reveal whether a Firebase account exists',
      () async {
        for (final providerCode in [
          'user-not-found',
          'wrong-password',
          'invalid-credential',
          'invalid-login-credentials',
          'user-disabled',
        ]) {
          final auth = _FakeFirebaseAuth()
            ..signInError = firebase.FirebaseAuthException(code: providerCode);
          final gateway = FirebaseAuthGateway(
            auth: auth,
            clock: () => authTestNow,
          );

          final error = await _authFailure(
            gateway.signIn(
              email: 'jordan@example.com',
              password: 'Wrong-Password-9!',
            ),
          );

          expect(
            error.code,
            AuthFailureCode.invalidCredentials,
            reason: providerCode,
          );
          expect(
            error.publicMessage,
            'Email or password is incorrect.',
            reason: providerCode,
          );
          expect(error.verificationChallenge, isNull, reason: providerCode);
        }
      },
    );

    test('canceling a pending verification signs Firebase out', () async {
      final auth = _FakeFirebaseAuth()..user = _FakeFirebaseUser();
      final gateway = FirebaseAuthGateway(auth: auth, clock: () => authTestNow);

      await gateway.cancelPendingVerification();

      expect(auth.signOutCalls, 1);
      expect(auth.currentUser, isNull);
    });

    test('closing an enabled gateway closes its code transport', () {
      final emailCodeClient = _FakeFirebaseEmailCodeClient();
      final gateway = FirebaseAuthGateway(
        auth: _FakeFirebaseAuth(),
        emailCodeClient: emailCodeClient,
        emailCodeEnabled: true,
        clock: () => authTestNow,
      );

      gateway.close();

      expect(emailCodeClient.closeCalls, 1);
    });
  });
}
