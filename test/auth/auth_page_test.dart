import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:drip/auth/auth_controller.dart';
import 'package:drip/auth/auth_models.dart';
import 'package:drip/auth/auth_page.dart';
import 'package:drip/auth/auth_session_store.dart';

import 'auth_test_fakes.dart';

class _ViewportCase {
  final String name;
  final Size size;
  final double textScale;
  final double keyboardInset;
  final Brightness brightness;

  const _ViewportCase({
    required this.name,
    required this.size,
    required this.textScale,
    required this.keyboardInset,
    required this.brightness,
  });
}

Widget _authHarness(
  AuthController controller, {
  Brightness brightness = Brightness.light,
  bool accountServicesConfigured = true,
  AccountServiceConnectionState? accountServiceConnection,
  Future<void> Function()? onRetryConnection,
}) => ChangeNotifierProvider.value(
  value: controller,
  child: MaterialApp(
    theme: ThemeData(brightness: brightness, useMaterial3: true),
    home: AuthPage(
      accountServiceConnection:
          accountServiceConnection ??
          (accountServicesConfigured
              ? AccountServiceConnectionState.ready
              : AccountServiceConnectionState.notConfigured),
      onRetryConnection: onRetryConnection,
    ),
  ),
);

AuthController _signedOutController(FakeAuthGateway gateway) => AuthController(
  gateway: gateway,
  store: MemoryAuthSessionStore(),
  clock: () => authTestNow,
  ownsGateway: false,
  initializeImmediately: false,
);

TextField _textField(WidgetTester tester, String key) =>
    tester.widget<TextField>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(TextField),
      ),
    );

void main() {
  const viewports = <_ViewportCase>[
    _ViewportCase(
      name: 'compact phone with large text and keyboard',
      size: Size(320, 568),
      textScale: 2,
      keyboardInset: 220,
      brightness: Brightness.light,
    ),
    _ViewportCase(
      name: 'standard phone in dark mode',
      size: Size(390, 844),
      textScale: 1,
      keyboardInset: 0,
      brightness: Brightness.dark,
    ),
    _ViewportCase(
      name: 'desktop layout with large text',
      size: Size(1024, 768),
      textScale: 2,
      keyboardInset: 0,
      brightness: Brightness.light,
    ),
  ];

  for (final viewport in viewports) {
    testWidgets('login and signup fit ${viewport.name}', (tester) async {
      tester.view.physicalSize = viewport.size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: viewport.keyboardInset);
      tester.platformDispatcher.textScaleFactorTestValue = viewport.textScale;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      final controller = _signedOutController(FakeAuthGateway());
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(
        _authHarness(controller, brightness: viewport.brightness),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-email-field')), findsOneWidget);
      expect(find.byKey(const Key('auth-password-field')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byKey(const Key('auth-mode-signup')));
      await tester.tap(find.byKey(const Key('auth-mode-signup')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('auth-submit-button')));

      expect(find.byKey(const Key('auth-name-field')), findsOneWidget);
      expect(find.text('Create your Drip account'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final loginSwitchSize = tester.getSize(
        find.byKey(const Key('auth-mode-login')),
      );
      final signupSwitchSize = tester.getSize(
        find.byKey(const Key('auth-mode-signup')),
      );
      final submitSize = tester.getSize(
        find.byKey(const Key('auth-submit-button')),
      );
      expect(loginSwitchSize.height, greaterThanOrEqualTo(48));
      expect(signupSwitchSize.height, greaterThanOrEqualTo(48));
      expect(submitSize.height, greaterThanOrEqualTo(48));
    });
  }

  testWidgets(
    'Google button is accessible, ignores rapid taps, and creates a Firebase session',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final pending = Completer<AuthResult?>();
      final gateway = FakeGoogleAuthGateway()..googleSignInCompleter = pending;
      final controller = _signedOutController(gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(_authHarness(controller));

      final googleButton = find.byKey(const Key('auth-google-button'));
      expect(googleButton, findsOneWidget);
      expect(find.bySemanticsLabel('Continue with Google'), findsOneWidget);
      expect(tester.getSize(googleButton).height, greaterThanOrEqualTo(48));

      await tester.tap(googleButton);
      await tester.tap(googleButton);
      await tester.pump();

      expect(gateway.googleSignInCalls, 1);
      expect(controller.busy, isTrue);
      expect(find.bySemanticsLabel('Connecting to Google'), findsOneWidget);

      pending.complete(authTestResult());
      await tester.pumpAndSettle();

      expect(controller.status, AuthStatus.signedIn);
      expect(controller.error, isNull);
      semantics.dispose();
    },
  );

  testWidgets('Google option fits a compact phone at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final controller = _signedOutController(FakeGoogleAuthGateway());
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(_authHarness(controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-google-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'fields expose autofill, keyboard, and password visibility semantics',
    (tester) async {
      final controller = _signedOutController(FakeAuthGateway());
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(_authHarness(controller));

      final email = _textField(tester, 'auth-email-field');
      var password = _textField(tester, 'auth-password-field');
      expect(email.keyboardType, TextInputType.emailAddress);
      expect(email.autofillHints, contains(AutofillHints.email));
      expect(email.autofillHints, contains(AutofillHints.username));
      expect(password.autofillHints, [AutofillHints.password]);
      expect(password.obscureText, isTrue);
      expect(find.byTooltip('Show password'), findsOneWidget);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      password = _textField(tester, 'auth-password-field');
      expect(password.obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);

      await tester.tap(find.byKey(const Key('auth-mode-signup')));
      await tester.pumpAndSettle();
      final name = _textField(tester, 'auth-name-field');
      password = _textField(tester, 'auth-password-field');
      expect(name.autofillHints, [AutofillHints.name]);
      expect(password.autofillHints, [AutofillHints.newPassword]);
      expect(password.obscureText, isTrue);
    },
  );

  testWidgets(
    'forgot password validates email and announces enumeration-safe success',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final pending = Completer<void>();
      final gateway = FakeAuthGateway()..passwordResetCompleter = pending;
      final controller = _signedOutController(gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(_authHarness(controller));

      final forgot = find.byKey(const Key('auth-forgot-password'));
      expect(forgot, findsOneWidget);
      await tester.ensureVisible(forgot);
      await tester.tap(forgot);
      await tester.pumpAndSettle();

      expect(gateway.passwordResetCalls, 0);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(
        _textField(tester, 'auth-email-field').focusNode?.hasFocus,
        isTrue,
      );
      var liveRegion = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.text('Enter a valid email address.'),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(liveRegion.properties.liveRegion, isTrue);

      await tester.enterText(
        find.byKey(const Key('auth-email-field')),
        ' Jordan@Example.COM ',
      );
      await tester.ensureVisible(forgot);
      await tester.tap(forgot);
      await tester.pump();

      expect(gateway.passwordResetCalls, 1);
      expect(gateway.lastPasswordResetEmail, 'jordan@example.com');
      expect(controller.passwordResetting, isTrue);
      expect(
        find.bySemanticsLabel('Sending password reset instructions'),
        findsOneWidget,
      );

      pending.complete();
      await tester.pumpAndSettle();

      const notice = AuthController.passwordResetSuccessMessage;
      expect(
        find.byKey(const Key('auth-password-reset-notice')),
        findsOneWidget,
      );
      expect(find.text(notice), findsOneWidget);
      expect(find.textContaining('account exists'), findsNothing);
      expect(find.textContaining('registered account'), findsNothing);
      liveRegion = tester.widget<Semantics>(
        find
            .ancestor(of: find.text(notice), matching: find.byType(Semantics))
            .first,
      );
      expect(liveRegion.properties.liveRegion, isTrue);

      await tester.tap(find.byKey(const Key('auth-mode-signup')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auth-forgot-password')), findsNothing);
      expect(find.byKey(const Key('auth-password-reset-notice')), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('forgot password failure is safe, announced, and retryable', (
    tester,
  ) async {
    const message =
        'Too many password reset attempts. Wait a moment and try again.';
    final gateway = FakeAuthGateway()
      ..passwordResetError = const AuthException(
        code: AuthFailureCode.rateLimited,
        publicMessage: message,
        retryable: true,
      );
    final controller = _signedOutController(gateway);
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(_authHarness(controller));
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'jordan@example.com',
    );

    await tester.ensureVisible(find.byKey(const Key('auth-forgot-password')));
    await tester.tap(find.byKey(const Key('auth-forgot-password')));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.textContaining('registered'), findsNothing);
    final liveRegion = tester.widget<Semantics>(
      find
          .ancestor(of: find.text(message), matching: find.byType(Semantics))
          .first,
    );
    expect(liveRegion.properties.liveRegion, isTrue);
    expect(find.text('Retry'), findsOneWidget);

    gateway.passwordResetError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(gateway.passwordResetCalls, 2);
    expect(
      find.text(AuthController.passwordResetSuccessMessage),
      findsOneWidget,
    );
  });

  testWidgets('validation is actionable and focuses the first invalid field', (
    tester,
  ) async {
    final gateway = FakeAuthGateway();
    final controller = _signedOutController(gateway);
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(_authHarness(controller));

    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(_textField(tester, 'auth-email-field').focusNode?.hasFocus, isTrue);
    expect(gateway.signInCalls, 0);

    await tester.tap(find.byKey(const Key('auth-mode-signup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('auth-name-field')),
      'Jordan Lee',
    );
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'jordan@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'too-short',
    );
    await tester.ensureVisible(find.byKey(const Key('auth-submit-button')));
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Use 12 to 128 characters with no control characters.'),
      findsOneWidget,
    );
    expect(
      _textField(tester, 'auth-password-field').focusNode?.hasFocus,
      isTrue,
    );
    expect(gateway.signUpCalls, 0);
  });

  testWidgets(
    'rapid taps submit once and generic login failure is a live region',
    (tester) async {
      final pending = Completer<AuthResult>();
      final gateway = FakeAuthGateway()..signInCompleter = pending;
      final controller = _signedOutController(gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(_authHarness(controller));
      await tester.enterText(
        find.byKey(const Key('auth-email-field')),
        'missing@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('auth-password-field')),
        'Wrong-Password-9!',
      );

      await tester.tap(find.byKey(const Key('auth-submit-button')));
      await tester.tap(find.byKey(const Key('auth-submit-button')));
      await tester.pump();

      expect(gateway.signInCalls, 1);
      expect(controller.busy, isTrue);
      expect(find.bySemanticsLabel('Signing in'), findsOneWidget);

      pending.completeError(const AuthException.invalidCredentials());
      await tester.pumpAndSettle();

      const publicMessage = 'Email or password is incorrect.';
      expect(find.text(publicMessage), findsOneWidget);
      expect(find.textContaining('account exists'), findsNothing);
      final liveRegion = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.text(publicMessage),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(liveRegion.properties.liveRegion, isTrue);
    },
  );

  testWidgets(
    'account creation moves through an accessible emailed-code challenge',
    (tester) async {
      final gateway = FakeAuthGateway()
        ..resendVerificationResult = authTestVerification(
          challengeToken: authTestRotatedChallengeToken,
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
      await tester.pumpWidget(_authHarness(controller));

      await tester.tap(find.byKey(const Key('auth-mode-signup')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('auth-name-field')),
        'Jordan Lee',
      );
      await tester.enterText(
        find.byKey(const Key('auth-email-field')),
        'jordan@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('auth-password-field')),
        'Correct-Horse-9!Battery',
      );
      await tester.ensureVisible(find.byKey(const Key('auth-submit-button')));
      await tester.tap(find.byKey(const Key('auth-submit-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-verification-card')), findsOneWidget);
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.text('jordan@example.com'), findsOneWidget);
      expect(controller.status, AuthStatus.signedOut);
      expect(controller.session, isNull);
      expect(store.value, isNull);
      expect(find.byKey(const Key('auth-password-field')), findsNothing);

      final codeField = tester.widget<TextField>(
        find.byKey(const Key('auth-verification-code')),
      );
      expect(codeField.keyboardType, TextInputType.number);
      expect(codeField.autofillHints, [AutofillHints.oneTimeCode]);
      expect(codeField.maxLength, 6);

      await tester.ensureVisible(
        find.byKey(const Key('auth-verification-resend')),
      );
      await tester.tap(find.byKey(const Key('auth-verification-resend')));
      await tester.pumpAndSettle();
      expect(gateway.resendVerificationCalls, 1);
      expect(gateway.lastChallengeToken, authTestChallengeToken);
      expect(
        find.text(
          'We requested a fresh security code. Check your inbox and spam folder.',
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('auth-verification-code')),
        '12a345678',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('auth-verification-code')))
            .controller
            ?.text,
        '123456',
      );
      await tester.ensureVisible(
        find.byKey(const Key('auth-verification-submit')),
      );
      await tester.tap(find.byKey(const Key('auth-verification-submit')));
      await tester.pumpAndSettle();

      expect(gateway.verifyEmailCalls, 1);
      expect(gateway.lastChallengeToken, authTestRotatedChallengeToken);
      expect(controller.status, AuthStatus.signedIn);
      expect(controller.pendingVerification, isNull);
      expect(store.value, same(gateway.verifyEmailResult.session));
    },
  );

  testWidgets(
    'email-link verification is clear, code-free, retryable, and accessible',
    (tester) async {
      const notVerifiedMessage =
          'We cannot see the verification yet. Open the link in your email, then try again.';
      final linkChallenge = authTestVerification(
        method: EmailVerificationMethod.link,
      );
      final gateway = FakeAuthGateway()
        ..signUpResult = linkChallenge
        ..resendVerificationResult = authTestVerification(
          challengeToken: authTestRotatedChallengeToken,
          method: EmailVerificationMethod.link,
        )
        ..verifyEmailError = const AuthException(
          code: AuthFailureCode.verificationRequired,
          publicMessage: notVerifiedMessage,
          retryable: true,
        );
      final controller = _signedOutController(gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.signUp(
        name: 'Jordan Lee',
        email: 'jordan@example.com',
        password: 'Correct-Horse-9!Battery',
      );

      await tester.pumpWidget(_authHarness(controller));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-verification-card')), findsOneWidget);
      expect(find.text('Verify your email'), findsOneWidget);
      expect(
        find.text('We requested a secure verification link for'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('auth-verification-link-steps')),
        findsOneWidget,
      );
      expect(
        find.text('Search for “Verify your email for drip”'),
        findsOneWidget,
      );
      expect(
        find.text('Check Spam and Promotions if it is not in your inbox'),
        findsOneWidget,
      );
      expect(
        find.text('Open the secure link—there is no six-digit code'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('auth-verification-code')), findsNothing);
      expect(find.text('Confirmation code'), findsNothing);
      expect(find.text('I verified my email'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('auth-verification-submit')),
      );
      await tester.tap(find.byKey(const Key('auth-verification-submit')));
      await tester.pumpAndSettle();

      expect(gateway.verifyEmailCalls, 1);
      expect(gateway.lastChallengeToken, authTestChallengeToken);
      expect(gateway.lastCode, isEmpty);
      expect(controller.status, AuthStatus.signedOut);
      expect(controller.pendingVerification, same(linkChallenge));
      expect(find.text(notVerifiedMessage), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('auth-verification-resend')),
      );
      await tester.tap(find.byKey(const Key('auth-verification-resend')));
      await tester.pumpAndSettle();

      expect(gateway.resendVerificationCalls, 1);
      expect(gateway.verifyEmailCalls, 1);
      expect(
        find.text(
          'We requested a new verification link. Check your inbox and spam folder.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('auth-verification-code')), findsNothing);
      expect(
        controller.pendingVerification?.challengeToken,
        authTestRotatedChallengeToken,
      );

      await tester.tap(find.byKey(const Key('auth-verification-edit-email')));
      await tester.pumpAndSettle();

      expect(controller.pendingVerification, isNull);
      expect(find.byKey(const Key('auth-email-field')), findsOneWidget);
    },
  );

  testWidgets('link verification offers matching Gmail and Yahoo shortcuts', (
    tester,
  ) async {
    for (final mailCase in [
      (email: 'jordan@gmail.com', label: 'Open Gmail'),
      (email: 'jordan@yahoo.com', label: 'Open Yahoo Mail'),
    ]) {
      final gateway = FakeAuthGateway()
        ..signUpResult = authTestVerification(
          email: mailCase.email,
          method: EmailVerificationMethod.link,
        );
      final controller = _signedOutController(gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.signUp(
        name: 'Jordan Lee',
        email: mailCase.email,
        password: 'Correct-Horse-9!Battery',
      );

      await tester.pumpWidget(_authHarness(controller));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-open-mail-provider')), findsOneWidget);
      expect(find.text(mailCase.label), findsOneWidget);
    }
  });

  testWidgets('code verification also offers Gmail and Yahoo shortcuts', (
    tester,
  ) async {
    for (final mailCase in [
      (email: 'jordan@gmail.com', label: 'Open Gmail'),
      (email: 'jordan@yahoo.com', label: 'Open Yahoo Mail'),
    ]) {
      final gateway = FakeAuthGateway()
        ..signUpResult = authTestVerification(
          email: mailCase.email,
          method: EmailVerificationMethod.code,
        );
      final controller = _signedOutController(gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.signUp(
        name: 'Jordan Lee',
        email: mailCase.email,
        password: 'Correct-Horse-9!Battery',
      );

      await tester.pumpWidget(_authHarness(controller));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-verification-code')), findsOneWidget);
      expect(find.byKey(const Key('auth-open-mail-provider')), findsOneWidget);
      expect(find.text(mailCase.label), findsOneWidget);
    }
  });

  testWidgets('wrong code is announced and keeps the challenge available', (
    tester,
  ) async {
    final gateway = FakeAuthGateway()
      ..verifyEmailError = const AuthException(
        code: AuthFailureCode.invalidVerificationCode,
        publicMessage: 'That confirmation code is not correct. Try again.',
      );
    final controller = _signedOutController(gateway);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.signUp(
      name: 'Jordan Lee',
      email: 'jordan@example.com',
      password: 'Correct-Horse-9!Battery',
    );
    await tester.pumpWidget(_authHarness(controller));

    await tester.enterText(
      find.byKey(const Key('auth-verification-code')),
      '000000',
    );
    await tester.ensureVisible(
      find.byKey(const Key('auth-verification-submit')),
    );
    await tester.tap(find.byKey(const Key('auth-verification-submit')));
    await tester.pumpAndSettle();

    const message = 'That confirmation code is not correct. Try again.';
    expect(find.text(message), findsOneWidget);
    expect(controller.pendingVerification, isNotNull);
    expect(controller.status, AuthStatus.signedOut);
    final liveRegion = tester.widget<Semantics>(
      find
          .ancestor(of: find.text(message), matching: find.byType(Semantics))
          .first,
    );
    expect(liveRegion.properties.liveRegion, isTrue);

    await tester.tap(find.byKey(const Key('auth-verification-edit-email')));
    await tester.pumpAndSettle();
    expect(controller.pendingVerification, isNull);
    expect(find.byKey(const Key('auth-email-field')), findsOneWidget);
  });

  testWidgets('resend failure never retries an unrelated blank code', (
    tester,
  ) async {
    final gateway = FakeAuthGateway()
      ..resendVerificationError = const AuthException.providerUnavailable();
    final controller = _signedOutController(gateway);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.signUp(
      name: 'Jordan Lee',
      email: 'jordan@example.com',
      password: 'Correct-Horse-9!Battery',
    );
    await tester.pumpWidget(_authHarness(controller));

    await tester.ensureVisible(
      find.byKey(const Key('auth-verification-resend')),
    );
    await tester.tap(find.byKey(const Key('auth-verification-resend')));
    await tester.pumpAndSettle();

    expect(gateway.resendVerificationCalls, 1);
    expect(gateway.verifyEmailCalls, 0);
    expect(find.text('Retry'), findsNothing);
    expect(find.byKey(const Key('auth-verification-submit')), findsOneWidget);
    expect(find.byKey(const Key('auth-verification-resend')), findsOneWidget);
  });

  testWidgets('failed demo clear still opens an isolated local preview', (
    tester,
  ) async {
    final store = MemoryAuthSessionStore()
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
    await tester.pumpWidget(_authHarness(controller));

    await tester.ensureVisible(find.byKey(const Key('auth-demo-button')));
    await tester.tap(find.byKey(const Key('auth-demo-button')));
    await tester.pumpAndSettle();
    expect(controller.status, AuthStatus.demo);
    expect(controller.error, isNull);
    expect(controller.session, isNull);
    expect(await controller.accessToken(), isNull);
    expect(gateway.signInCalls, 0);
  });

  testWidgets('unconfigured builds present one clear preview action', (
    tester,
  ) async {
    final gateway = FakeAuthGateway();
    final controller = AuthController(
      gateway: gateway,
      store: MemoryAuthSessionStore(),
      clock: () => authTestNow,
      allowDemo: true,
      ownsGateway: false,
      initializeImmediately: false,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(
      _authHarness(controller, accountServicesConfigured: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account access isn’t available yet'), findsOneWidget);
    expect(
      find.textContaining('explore Drip without an account'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Browse standout pieces, build complete outfits, and try Drip Concierge.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('API URL'), findsNothing);
    expect(find.textContaining('local product preview'), findsNothing);
    expect(find.byKey(const Key('auth-mode-login')), findsNothing);
    expect(find.byKey(const Key('auth-mode-signup')), findsNothing);
    expect(find.byKey(const Key('auth-name-field')), findsNothing);
    expect(find.byKey(const Key('auth-email-field')), findsNothing);
    expect(find.byKey(const Key('auth-password-field')), findsNothing);
    expect(find.byKey(const Key('auth-submit-button')), findsNothing);
    expect(find.byKey(const Key('auth-preview-card')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('auth-demo-button')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('auth-demo-button')));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.demo);
    expect(gateway.signUpCalls, 0);
    expect(gateway.signInCalls, 0);
  });

  testWidgets(
    'runtime readiness distinguishes checking, server setup, and outage',
    (tester) async {
      var retryCalls = 0;
      final gateway = FakeAuthGateway();
      final controller = AuthController(
        gateway: gateway,
        store: MemoryAuthSessionStore(),
        clock: () => authTestNow,
        allowDemo: true,
        ownsGateway: false,
        initializeImmediately: false,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(
        _authHarness(
          controller,
          accountServiceConnection: AccountServiceConnectionState.checking,
          onRetryConnection: () async => retryCalls++,
        ),
      );
      expect(find.text('Getting sign-in ready'), findsOneWidget);
      expect(find.text('Checking account access'), findsOneWidget);
      expect(find.byKey(const Key('auth-connection-checking')), findsOneWidget);
      expect(find.byKey(const Key('auth-email-field')), findsNothing);

      await tester.pumpWidget(
        _authHarness(
          controller,
          accountServiceConnection:
              AccountServiceConnectionState.serverSetupRequired,
          onRetryConnection: () async => retryCalls++,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Account access is temporarily unavailable'),
        findsOneWidget,
      );
      expect(
        find.textContaining('sign-in and account creation'),
        findsOneWidget,
      );
      expect(find.text('Sign-in needs a little more time'), findsOneWidget);
      await tester.tap(find.byKey(const Key('auth-connection-retry')));
      await tester.pump();
      expect(retryCalls, 1);

      await tester.pumpWidget(
        _authHarness(
          controller,
          accountServiceConnection: AccountServiceConnectionState.unavailable,
          onRetryConnection: () async => retryCalls++,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Account access is unavailable'), findsOneWidget);
      expect(find.text('Sign-in is currently offline'), findsOneWidget);
      expect(find.textContaining('account services'), findsOneWidget);
      expect(find.byKey(const Key('auth-email-field')), findsNothing);
      expect(find.byKey(const Key('auth-demo-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('auth-connection-retry')));
      await tester.pump();
      expect(retryCalls, 2);
      await tester.tap(find.byKey(const Key('auth-demo-button')));
      await tester.pumpAndSettle();
      expect(controller.status, AuthStatus.demo);
      expect(gateway.signInCalls, 0);
      expect(gateway.signUpCalls, 0);
    },
  );

  for (final viewport in const [
    _ViewportCase(
      name: 'small phone at 200 percent text',
      size: Size(320, 568),
      textScale: 2,
      keyboardInset: 0,
      brightness: Brightness.light,
    ),
    _ViewportCase(
      name: 'wide desktop at 200 percent text',
      size: Size(1024, 768),
      textScale: 2,
      keyboardInset: 0,
      brightness: Brightness.dark,
    ),
  ]) {
    testWidgets('preview remains usable on ${viewport.name}', (tester) async {
      tester.view.physicalSize = viewport.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = viewport.textScale;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      final controller = AuthController(
        gateway: FakeAuthGateway(),
        store: MemoryAuthSessionStore(),
        clock: () => authTestNow,
        allowDemo: true,
        ownsGateway: false,
        initializeImmediately: false,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(
        _authHarness(
          controller,
          brightness: viewport.brightness,
          accountServicesConfigured: false,
        ),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(const Key('auth-demo-button'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();

      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(find.byKey(const Key('auth-email-field')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('preview account status and action are accessible', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = AuthController(
      gateway: FakeAuthGateway(),
      store: MemoryAuthSessionStore(),
      clock: () => authTestNow,
      allowDemo: true,
      ownsGateway: false,
      initializeImmediately: false,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(
      _authHarness(controller, accountServicesConfigured: false),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        'Account access isn’t available yet. You can still explore Drip '
        'without an account. Sign-up and sign-in will appear when account '
        'access is ready.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Explore Drip'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('signup success distinguishes queued and failed welcome email', (
    tester,
  ) async {
    var continued = false;
    final sent = authTestResult(
      welcomeEmailSent: true,
      welcomeEmailStatus: 'sent',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SignupSuccessPage(
          result: sent,
          onContinue: () => continued = true,
        ),
      ),
    );
    expect(find.text('Welcome email on the way'), findsOneWidget);
    expect(find.textContaining('accepted for delivery'), findsOneWidget);
    expect(find.text('Welcome email sent'), findsNothing);

    final pending = authTestResult(
      welcomeEmailSent: false,
      welcomeEmailStatus: 'pending',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SignupSuccessPage(
          result: pending,
          onContinue: () => continued = true,
        ),
      ),
    );

    expect(find.text('Welcome email queued'), findsOneWidget);
    expect(find.text('Welcome email sent'), findsNothing);
    expect(find.textContaining('delivery is still pending'), findsOneWidget);

    final failed = authTestResult(
      welcomeEmailSent: false,
      welcomeEmailStatus: 'failed',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SignupSuccessPage(
          result: failed,
          onContinue: () => continued = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Welcome email could not be sent'), findsOneWidget);
    expect(
      find.textContaining('welcome email could not be sent'),
      findsOneWidget,
    );
    expect(find.textContaining('delivery is still pending'), findsNothing);
    expect(find.text('Welcome email sent'), findsNothing);
    await tester.tap(find.byKey(const Key('auth-success-continue')));
    expect(continued, isTrue);
  });
}
