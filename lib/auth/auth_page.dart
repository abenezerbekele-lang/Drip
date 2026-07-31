import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design_system.dart';
import 'auth_controller.dart';
import 'auth_models.dart';

enum _AuthMode { signIn, createAccount }

class AuthPage extends StatefulWidget {
  final AccountServiceConnectionState accountServiceConnection;
  final Future<void> Function()? onRetryConnection;

  const AuthPage({
    super.key,
    required this.accountServiceConnection,
    this.onRetryConnection,
  });

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _codeFocus = FocusNode();
  _AuthMode _mode = _AuthMode.signIn;
  bool _showPassword = false;
  bool _hasSubmitted = false;
  bool _demoAttempted = false;
  bool _passwordResetAttempted = false;
  bool _googleAttempted = false;
  Timer? _resendTicker;
  String? _resendNotice;

  bool get _creating => _mode == _AuthMode.createAccount;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _codeFocus.dispose();
    _resendTicker?.cancel();
    super.dispose();
  }

  void _setMode(_AuthMode mode) {
    if (_mode == mode) return;
    final auth = context.read<AuthController>();
    auth.clearError();
    auth.clearPasswordResetNotice();
    setState(() {
      _mode = mode;
      _passwordController.clear();
      _showPassword = false;
      _hasSubmitted = false;
      _demoAttempted = false;
      _passwordResetAttempted = false;
      _googleAttempted = false;
    });
    _formKey.currentState?.reset();
  }

  void _startResendTicker() {
    _resendTicker?.cancel();
    final auth = context.read<AuthController>();
    if (auth.verificationResendWait <= Duration.zero) {
      return;
    }
    _resendTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      final controller = context.read<AuthController>();
      if (controller.pendingVerification == null ||
          controller.verificationResendWait <= Duration.zero) {
        timer.cancel();
      }
      setState(() {});
    });
  }

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    if (auth.busy) return;
    _demoAttempted = false;
    _passwordResetAttempted = false;
    _googleAttempted = false;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_formKey.currentState?.validate() != true) {
      if (_creating && validateDisplayName(_nameController.text) != null) {
        _nameFocus.requestFocus();
      } else if (validateEmail(_emailController.text) != null) {
        _emailFocus.requestFocus();
      } else {
        _passwordFocus.requestFocus();
      }
      return;
    }
    if (_creating) {
      _hasSubmitted = true;
      final started = await auth.signUp(
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (started && mounted) {
        _codeController.clear();
        _resendNotice = null;
        _startResendTicker();
        if (auth.pendingVerification?.method == EmailVerificationMethod.code) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _codeFocus.requestFocus();
          });
        }
      }
    } else {
      _hasSubmitted = true;
      await auth.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
    }
  }

  Future<void> _requestPasswordReset() async {
    final auth = context.read<AuthController>();
    if (auth.busy || !auth.supportsPasswordReset) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _demoAttempted = false;
      _hasSubmitted = false;
      _passwordResetAttempted = true;
      _googleAttempted = false;
    });
    final sent = await auth.requestPasswordReset(email: _emailController.text);
    if (!mounted) return;
    if (!sent && auth.error?.code == AuthFailureCode.invalidEmail) {
      _emailFocus.requestFocus();
    }
  }

  void _emailChanged(String _) {
    final auth = context.read<AuthController>();
    final hadResetFeedback =
        _passwordResetAttempted || auth.passwordResetNotice != null;
    if (_passwordResetAttempted || _googleAttempted) {
      setState(() {
        _passwordResetAttempted = false;
        _googleAttempted = false;
      });
    }
    if (auth.passwordResetNotice != null) {
      auth.clearPasswordResetNotice();
    }
    if (hadResetFeedback && auth.error != null) auth.clearError();
  }

  Future<void> _verifyCode() async {
    final auth = context.read<AuthController>();
    if (auth.busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _resendNotice = null);
    final verified = await auth.verifyEmail(_codeController.text);
    if (!verified &&
        mounted &&
        auth.pendingVerification?.method == EmailVerificationMethod.code) {
      _codeFocus.requestFocus();
    }
  }

  Future<void> _resendCode() async {
    final auth = context.read<AuthController>();
    if (auth.busy) return;
    final sent = await auth.resendVerification();
    if (!mounted) return;
    if (sent) {
      _codeController.clear();
      final isLink =
          auth.pendingVerification?.method == EmailVerificationMethod.link;
      setState(
        () => _resendNotice = isLink
            ? 'We requested a new verification link. Check your inbox and spam folder.'
            : 'We requested a fresh security code. Check your inbox and spam folder.',
      );
      _startResendTicker();
      if (!isLink) _codeFocus.requestFocus();
    }
  }

  Future<void> _editEmail() async {
    final auth = context.read<AuthController>();
    if (auth.busy) return;
    final cancelled = await auth.cancelEmailVerification();
    if (!mounted || !cancelled) return;
    _resendTicker?.cancel();
    _codeController.clear();
    _passwordController.clear();
    setState(() {
      _resendNotice = null;
      _hasSubmitted = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emailFocus.requestFocus();
    });
  }

  Future<void> _enterDemo() async {
    _demoAttempted = true;
    _hasSubmitted = false;
    _googleAttempted = false;
    await context.read<AuthController>().continueAsDemo();
  }

  Future<void> _continueWithGoogle() async {
    final auth = context.read<AuthController>();
    if (auth.busy || !auth.supportsGoogleSignIn) return;
    FocusManager.instance.primaryFocus?.unfocus();
    auth.clearError();
    auth.clearPasswordResetNotice();
    setState(() {
      _demoAttempted = false;
      _passwordResetAttempted = false;
      _hasSubmitted = false;
      _googleAttempted = true;
    });
    await auth.signInWithGoogle();
  }

  ({String label, Uri uri})? _mailShortcutFor(String email) {
    final separator = email.lastIndexOf('@');
    if (separator < 0) return null;
    final domain = email.substring(separator + 1).toLowerCase();
    if (domain == 'gmail.com' || domain == 'googlemail.com') {
      return (
        label: 'Open Gmail',
        uri: Uri.https('mail.google.com', '/mail/u/0/'),
      );
    }
    if (domain == 'yahoo.com' || domain.endsWith('.yahoo.com')) {
      return (label: 'Open Yahoo Mail', uri: Uri.https('mail.yahoo.com', '/'));
    }
    return null;
  }

  Future<void> _openMailShortcut(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      // The verification screen remains fully usable when a device has no
      // browser/mail handler; resend and manual inbox access still work.
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0xFF06101F), Color(0xFF102C50), ink]
                    : const [
                        Color(0xFFEAF4FF),
                        Color(0xFFF9FBFF),
                        Color(0xFFDDEBFA),
                      ],
                stops: const [0, .54, 1],
              ),
            ),
          ),
          Positioned(
            top: -100,
            right: -90,
            child: _Glow(color: iceBlue.withValues(alpha: dark ? .16 : .28)),
          ),
          Positioned(
            bottom: -130,
            left: -100,
            child: _Glow(
              size: 360,
              color: electricBlue.withValues(alpha: dark ? .18 : .16),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 900;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    desktop ? 48 : 20,
                    desktop ? 42 : 18,
                    desktop ? 48 : 20,
                    28 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          (constraints.maxHeight -
                                  (desktop ? 70 : 34) -
                                  MediaQuery.viewInsetsOf(context).bottom)
                              .clamp(0, double.infinity),
                    ),
                    child: desktop
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 470,
                                  ),
                                  child: const _BrandStory(),
                                ),
                              ),
                              const SizedBox(width: 64),
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 500,
                                  ),
                                  child: _formCard(auth),
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const _CompactBrand(),
                                  const SizedBox(height: 20),
                                  _formCard(auth),
                                ],
                              ),
                            ),
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard(AuthController auth) {
    if (widget.accountServiceConnection !=
        AccountServiceConnectionState.ready) {
      return _connectionCard(auth);
    }
    final challenge = auth.pendingVerification;
    if (challenge != null) return _verificationCard(auth, challenge);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final compactLargeText =
        MediaQuery.sizeOf(context).width < 360 &&
        MediaQuery.textScalerOf(context).scale(12) >= 18;
    final passwordResetNotice = auth.passwordResetNotice;
    final googleBusy = auth.busy && _googleAttempted;
    final formBusy = auth.busy && !_googleAttempted;
    return Container(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 360 ? 18 : 26),
      decoration: BoxDecoration(
        color: dark
            ? panel.withValues(alpha: .92)
            : Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: dark ? Colors.white12 : const Color(0xFFD7E5F4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .28 : .1),
            blurRadius: 42,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _creating ? 'Create your Drip account' : 'Welcome back',
                style: const TextStyle(
                  fontSize: 25,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _creating
                    ? 'Save your style, ask the concierge, and check out securely.'
                    : 'Sign in to keep your wardrobe and shopping session connected.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 22),
              _ModeSwitch(mode: _mode, onChanged: auth.busy ? null : _setMode),
              if (auth.supportsGoogleSignIn) ...[
                const SizedBox(height: 18),
                Semantics(
                  button: true,
                  label: googleBusy
                      ? 'Connecting to Google'
                      : 'Continue with Google',
                  value: googleBusy ? 'In progress' : null,
                  excludeSemantics: true,
                  child: OutlinedButton(
                    key: const Key('auth-google-button'),
                    onPressed: auth.busy ? null : _continueWithGoogle,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      foregroundColor: theme.colorScheme.onSurface,
                      backgroundColor: dark
                          ? Colors.white.withValues(alpha: .055)
                          : Colors.white.withValues(alpha: .86),
                      side: BorderSide(
                        color: dark
                            ? Colors.white.withValues(alpha: .2)
                            : const Color(0xFFC8D5E4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: googleBusy
                          ? const SizedBox(
                              key: ValueKey('google-busy'),
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : compactLargeText
                          ? const Text(
                              'Continue with Google',
                              key: ValueKey('google-ready-compact'),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w900),
                            )
                          : const Row(
                              key: ValueKey('google-ready'),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _GoogleMark(),
                                SizedBox(width: 11),
                                Flexible(
                                  child: Text(
                                    'Continue with Google',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 17),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Flexible(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OR USE EMAIL',
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.15,
                          ),
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _creating
                    ? Padding(
                        key: const ValueKey('name-field'),
                        padding: const EdgeInsets.only(bottom: 14),
                        child: TextFormField(
                          key: const Key('auth-name-field'),
                          controller: _nameController,
                          focusNode: _nameFocus,
                          enabled: !auth.busy,
                          autofillHints: const [AutofillHints.name],
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          maxLength: 80,
                          decoration: InputDecoration(
                            labelText: 'Full name',
                            hintText: compactLargeText ? null : 'Jordan Lee',
                            prefixIcon: compactLargeText
                                ? null
                                : const Icon(Icons.person_outline_rounded),
                            counterText: '',
                          ),
                          validator: (value) =>
                              validateDisplayName(value ?? ''),
                          onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('no-name-field')),
              ),
              TextFormField(
                key: const Key('auth-email-field'),
                controller: _emailController,
                focusNode: _emailFocus,
                enabled: !auth.busy,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                textInputAction: TextInputAction.next,
                maxLength: 254,
                decoration: InputDecoration(
                  labelText: 'Email address',
                  hintText: compactLargeText ? null : 'you@example.com',
                  prefixIcon: compactLargeText
                      ? null
                      : const Icon(Icons.alternate_email_rounded),
                  counterText: '',
                ),
                validator: (value) => validateEmail(value ?? ''),
                onChanged: _emailChanged,
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('auth-password-field'),
                controller: _passwordController,
                focusNode: _passwordFocus,
                enabled: !auth.busy,
                obscureText: !_showPassword,
                enableSuggestions: false,
                autocorrect: false,
                autofillHints: [
                  _creating
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: compactLargeText
                      ? null
                      : _creating
                      ? '12+ secure characters'
                      : 'Your password',
                  prefixIcon: compactLargeText
                      ? null
                      : const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    onPressed: auth.busy
                        ? null
                        : () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  final password = value ?? '';
                  if (!_creating) {
                    return password.isEmpty ? 'Enter your password.' : null;
                  }
                  return validatePassword(
                    password,
                    email: _emailController.text,
                  );
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              if (!_creating && auth.supportsPasswordReset)
                Align(
                  alignment: Alignment.centerRight,
                  child: Semantics(
                    button: true,
                    label: auth.passwordResetting
                        ? 'Sending password reset instructions'
                        : 'Forgot password',
                    value: auth.passwordResetting ? 'In progress' : null,
                    excludeSemantics: true,
                    child: TextButton.icon(
                      key: const Key('auth-forgot-password'),
                      onPressed: auth.busy ? null : _requestPasswordReset,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      icon: auth.passwordResetting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_reset_rounded, size: 19),
                      label: Text(
                        auth.passwordResetting
                            ? 'Sending reset link…'
                            : 'Forgot password?',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              if (_creating) ...[
                const SizedBox(height: 10),
                Text(
                  'Use 12–128 characters and at least three types: uppercase, lowercase, numbers, or symbols.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: auth.error == null && passwordResetNotice == null
                    ? const SizedBox(height: 20)
                    : Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 16),
                        child: Semantics(
                          liveRegion: true,
                          container: true,
                          child: auth.error != null
                              ? _ErrorNotice(
                                  message: auth.error!.publicMessage,
                                  retry:
                                      auth.error!.retryable &&
                                          auth.status == AuthStatus.signedOut
                                      ? (_googleAttempted
                                            ? _continueWithGoogle
                                            : _demoAttempted
                                            ? _enterDemo
                                            : _passwordResetAttempted
                                            ? _requestPasswordReset
                                            : _hasSubmitted
                                            ? _submit
                                            : auth.initialize)
                                      : null,
                                )
                              : KeyedSubtree(
                                  key: const Key('auth-password-reset-notice'),
                                  child: _SuccessNotice(
                                    message: passwordResetNotice!,
                                  ),
                                ),
                        ),
                      ),
              ),
              Semantics(
                button: true,
                label: formBusy
                    ? (_creating ? 'Creating account' : 'Signing in')
                    : (_creating ? 'Create account' : 'Sign in'),
                value: formBusy ? 'In progress' : null,
                child: FilledButton(
                  key: const Key('auth-submit-button'),
                  onPressed: auth.busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: electricBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: formBusy
                        ? const SizedBox(
                            key: ValueKey('busy'),
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _creating ? 'Create account' : 'Sign in',
                            key: const ValueKey('ready'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                  ),
                ),
              ),
              if (auth.allowDemo) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'PREVIEW',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  key: const Key('auth-demo-button'),
                  onPressed: auth.busy ? null : _enterDemo,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.explore_outlined, size: 20),
                      SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          'Explore the local demo',
                          textAlign: TextAlign.center,
                          softWrap: true,
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Demo mode does not create an account or a production session. Seller tools and saved activity stay on this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10.5,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectionCard(AuthController auth) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final state = widget.accountServiceConnection;
    final descriptor = switch (state) {
      AccountServiceConnectionState.notConfigured => const (
        title: 'Explore Drip',
        subtitle:
            'Browse standout pieces, build complete outfits, and try Drip Concierge.',
        noticeTitle: 'Account access isn’t available yet',
        noticeMessage:
            'You can still explore Drip without an account. Sign-up and sign-in will appear when account access is ready.',
        icon: Icons.link_off_rounded,
      ),
      AccountServiceConnectionState.checking => const (
        title: 'Getting sign-in ready',
        subtitle:
            'Drip is securely checking account access before showing sign-in.',
        noticeTitle: 'Checking account access',
        noticeMessage:
            'This usually takes only a moment. No account request is sent until the connection is ready.',
        icon: Icons.sync_rounded,
      ),
      AccountServiceConnectionState.serverSetupRequired => const (
        title: 'Account access is temporarily unavailable',
        subtitle:
            'Drip is online, but sign-in and account creation aren’t ready right now.',
        noticeTitle: 'Sign-in needs a little more time',
        noticeMessage:
            'Try again shortly. You can still explore Drip without an account.',
        icon: Icons.admin_panel_settings_outlined,
      ),
      AccountServiceConnectionState.unavailable => const (
        title: 'Account access is unavailable',
        subtitle:
            'Drip couldn’t reach account services. Try again in a moment. Your account details have not been sent.',
        noticeTitle: 'Sign-in is currently offline',
        noticeMessage:
            'Sign-in stays off until Drip can verify a secure connection.',
        icon: Icons.cloud_off_rounded,
      ),
      AccountServiceConnectionState.ready => throw StateError(
        'The ready account state uses the sign-in form.',
      ),
    };
    final checking = state == AccountServiceConnectionState.checking;
    final retryable =
        state == AccountServiceConnectionState.serverSetupRequired ||
        state == AccountServiceConnectionState.unavailable;
    return Container(
      key: const Key('auth-preview-card'),
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 360 ? 20 : 28),
      decoration: BoxDecoration(
        color: dark
            ? panel.withValues(alpha: .92)
            : Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: dark ? Colors.white12 : const Color(0xFFD7E5F4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .28 : .1),
            blurRadius: 42,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            descriptor.title,
            key: const Key('auth-connection-title'),
            semanticsLabel: state == AccountServiceConnectionState.notConfigured
                ? 'Explore Drip preview'
                : descriptor.title,
            style: const TextStyle(
              fontSize: 27,
              height: 1.08,
              fontWeight: FontWeight.w900,
              letterSpacing: -.7,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            descriptor.subtitle,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 22),
          _PreviewAccountNotice(
            title: descriptor.noticeTitle,
            message: descriptor.noticeMessage,
            icon: descriptor.icon,
            checking: checking,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: !_demoAttempted || auth.error == null
                ? const SizedBox(height: 24)
                : Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 18),
                    child: Semantics(
                      liveRegion: true,
                      container: true,
                      child: _ErrorNotice(
                        message: auth.error!.publicMessage,
                        retry: auth.error!.retryable ? _enterDemo : null,
                      ),
                    ),
                  ),
          ),
          if (checking)
            FilledButton.icon(
              key: const Key('auth-connection-checking'),
              onPressed: null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.3),
              ),
              label: const Text(
                'Checking connection…',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          else if (retryable)
            FilledButton.icon(
              key: const Key('auth-connection-retry'),
              onPressed: auth.busy || widget.onRetryConnection == null
                  ? null
                  : () => unawaited(widget.onRetryConnection!.call()),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: electricBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 21),
              label: const Text(
                'Try again',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          else
            FilledButton.icon(
              key: const Key('auth-demo-button'),
              onPressed: auth.busy || !auth.allowDemo ? null : _enterDemo,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: electricBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: auth.busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.3,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.explore_outlined, size: 21),
              label: Text(
                auth.busy ? 'Opening Drip…' : 'Explore Drip',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          if ((checking || retryable) && auth.allowDemo) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('auth-demo-button'),
              onPressed: auth.busy ? null : _enterDemo,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: const Icon(Icons.explore_outlined, size: 20),
              label: const Text(
                'Explore without an account',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.phone_iphone_rounded,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Preview activity stays on this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _verificationCard(
    AuthController auth,
    EmailVerificationChallenge challenge,
  ) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final resendWait = auth.verificationResendWait;
    final resendSeconds =
        resendWait.inSeconds + (resendWait.inMilliseconds % 1000 == 0 ? 0 : 1);
    final canResend = resendWait <= Duration.zero && !auth.busy;
    final usesLink = challenge.method == EmailVerificationMethod.link;
    final mailShortcut = _mailShortcutFor(challenge.email);
    return Container(
      key: const Key('auth-verification-card'),
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 360 ? 18 : 28),
      decoration: BoxDecoration(
        color: dark
            ? panel.withValues(alpha: .94)
            : Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: dark ? iceBlue.withValues(alpha: .2) : const Color(0xFFD7E5F4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .3 : .1),
            blurRadius: 42,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton.outlined(
                key: const Key('auth-verification-back'),
                onPressed: auth.busy ? null : _editEmail,
                tooltip: 'Go back and edit email',
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: electricBlue.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: electricBlue,
                  size: 31,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              usesLink ? 'Verify your email' : 'Check your email',
              style: TextStyle(
                fontSize: 27,
                height: 1.08,
                fontWeight: FontWeight.w900,
                letterSpacing: -.7,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              usesLink
                  ? 'We requested a secure verification link for'
                  : 'We requested a six-digit security code for',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 3),
            Semantics(
              label: 'Confirmation email ${challenge.email}',
              child: Text(
                challenge.email,
                key: const Key('auth-verification-email'),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (usesLink) ...[
              _VerificationLinkSteps(theme: theme),
            ] else
              TextField(
                key: const Key('auth-verification-code'),
                controller: _codeController,
                focusNode: _codeFocus,
                enabled: !auth.busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                ),
                decoration: const InputDecoration(
                  labelText: 'Confirmation code',
                  hintText: '000000',
                  counterText: '',
                  prefixIcon: Icon(Icons.password_rounded),
                ),
                onChanged: (_) {
                  if (auth.error != null) auth.clearError();
                  if (_resendNotice != null) {
                    setState(() => _resendNotice = null);
                  }
                },
                onSubmitted: (_) => _verifyCode(),
              ),
            if (mailShortcut != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('auth-open-mail-provider'),
                onPressed: auth.busy
                    ? null
                    : () => _openMailShortcut(mailShortcut.uri),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 19),
                label: Text(
                  mailShortcut.label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 17,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    usesLink
                        ? 'Your password stays with the secure sign-in service and is never included in email.'
                        : 'The code expires soon and can only be used once.',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: auth.error == null && _resendNotice == null
                  ? const SizedBox(height: 20)
                  : Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 16),
                      child: Semantics(
                        liveRegion: true,
                        container: true,
                        child: auth.error != null
                            ? _ErrorNotice(message: auth.error!.publicMessage)
                            : _SuccessNotice(message: _resendNotice!),
                      ),
                    ),
            ),
            Semantics(
              button: true,
              label: auth.busy
                  ? 'Checking email verification'
                  : usesLink
                  ? 'I verified my email'
                  : 'Confirm email',
              value: auth.busy ? 'In progress' : null,
              child: FilledButton(
                key: const Key('auth-verification-submit'),
                onPressed: auth.busy ? null : _verifyCode,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: electricBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                child: auth.busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        usesLink ? 'I verified my email' : 'Confirm email',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              key: const Key('auth-verification-resend'),
              onPressed: canResend ? _resendCode : null,
              child: Text(
                canResend
                    ? usesLink
                          ? 'Send verification link again'
                          : 'Send a new code'
                    : auth.busy
                    ? 'Sending…'
                    : 'Send again in ${resendSeconds}s',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              key: const Key('auth-verification-edit-email'),
              onPressed: auth.busy ? null : _editEmail,
              child: const Text('Use a different email'),
            ),
            Text(
              usesLink
                  ? 'After opening the email link, return here and tap “I verified my email.”'
                  : 'You can safely close this screen. Return to Drip and request a fresh code if this one expires.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationLinkSteps extends StatelessWidget {
  final ThemeData theme;

  const _VerificationLinkSteps({required this.theme});

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.search_rounded, 'Search for “Verify your email for drip”'),
      (
        Icons.mark_email_unread_outlined,
        'Check Spam and Promotions if it is not in your inbox',
      ),
      (
        Icons.touch_app_outlined,
        'Open the secure link—there is no six-digit code',
      ),
      (Icons.keyboard_return_rounded, 'Return here to finish'),
    ];
    return Container(
      key: const Key('auth-verification-link-steps'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: electricBlue.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: electricBlue.withValues(alpha: .16)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < steps.length; index++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: electricBlue.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Icon(steps[index].$1, size: 18, color: electricBlue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      steps[index].$2,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            if (index != steps.length - 1)
              Divider(
                height: 1,
                color: theme.dividerColor.withValues(alpha: .55),
              ),
          ],
        ],
      ),
    );
  }
}

class AuthLoadingPage extends StatelessWidget {
  const AuthLoadingPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF06101F), Color(0xFF15375D)],
        ),
      ),
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: 'Checking your secure Drip session',
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DripMark(size: 70),
              SizedBox(height: 24),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: iceBlue,
                  strokeWidth: 2.5,
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Securing your session…',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SignupSuccessPage extends StatelessWidget {
  final AuthResult result;
  final VoidCallback onContinue;

  const SignupSuccessPage({
    super.key,
    required this.result,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final sent = result.welcomeEmailSent == true;
    final status = result.welcomeEmailStatus?.toLowerCase();
    final emailVerified = status == 'email_verified';
    final failed =
        status == 'failed' || status == 'rejected' || status == 'undeliverable';
    final accent = sent || emailVerified
        ? const Color(0xFF75E5BD)
        : failed
        ? const Color(0xFFFF8F8F)
        : const Color(0xFFFFD77A);
    final statusTitle = emailVerified
        ? 'Email verified'
        : sent
        ? 'Welcome email on the way'
        : failed
        ? 'Welcome email could not be sent'
        : 'Welcome email queued';
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF06101F), Color(0xFF163E6B), ink],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: panel.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: iceBlue.withValues(alpha: .28)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: .14),
                        ),
                        child: Icon(
                          sent || emailVerified
                              ? Icons.mark_email_read_rounded
                              : failed
                              ? Icons.mark_email_unread_outlined
                              : Icons.schedule_send_rounded,
                          size: 38,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'You’re in, ${result.session.user.name.split(' ').first}.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Your account was created securely.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 22),
                      Semantics(
                        liveRegion: true,
                        container: true,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                sent || emailVerified
                                    ? Icons.check_circle_outline_rounded
                                    : failed
                                    ? Icons.error_outline_rounded
                                    : Icons.info_outline_rounded,
                                color: accent,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      statusTitle,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      result.signupNotice(),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        key: const Key('auth-success-continue'),
                        onPressed: onContinue,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          backgroundColor: iceBlue,
                          foregroundColor: ink,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text(
                          'Enter Drip',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  final _AuthMode mode;
  final ValueChanged<_AuthMode>? onChanged;

  const _ModeSwitch({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stack =
          constraints.maxWidth < 330 &&
          MediaQuery.textScalerOf(context).scale(12) >= 18;
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(15),
        ),
        child: stack
            ? Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: _button(context, _AuthMode.signIn, 'Sign in'),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: _button(
                      context,
                      _AuthMode.createAccount,
                      'Create account',
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: _button(context, _AuthMode.signIn, 'Sign in'),
                  ),
                  Expanded(
                    child: _button(
                      context,
                      _AuthMode.createAccount,
                      'Create account',
                    ),
                  ),
                ],
              ),
      );
    },
  );

  Widget _button(BuildContext context, _AuthMode value, String label) {
    final active = mode == value;
    return Semantics(
      selected: active,
      button: true,
      child: InkWell(
        key: Key(
          value == _AuthMode.signIn ? 'auth-mode-login' : 'auth-mode-signup',
        ),
        onTap: onChanged == null ? null : () => onChanged!(value),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.surface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .08),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w900 : FontWeight.w700,
              color: active ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewAccountNotice extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final bool checking;

  const _PreviewAccountNotice({
    required this.title,
    required this.message,
    required this.icon,
    required this.checking,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: '$title. $message',
    child: Container(
      key: const Key('auth-preview-account-notice'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: electricBlue.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: electricBlue.withValues(alpha: .22)),
      ),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            checking
                ? const SizedBox(
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Icon(icon, color: electricBlue, size: 21),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ErrorNotice extends StatelessWidget {
  final String message;
  final VoidCallback? retry;

  const _ErrorNotice({required this.message, this.retry});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.errorContainer.withValues(alpha: .58),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: Theme.of(context).colorScheme.error.withValues(alpha: .25),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (retry != null)
          TextButton(
            onPressed: retry,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Retry'),
          ),
      ],
    ),
  );
}

class _SuccessNotice extends StatelessWidget {
  final String message;

  const _SuccessNotice({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFF32B887).withValues(alpha: .12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF32B887).withValues(alpha: .3)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.check_circle_outline_rounded,
          color: Color(0xFF218966),
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _BrandStory extends StatelessWidget {
  const _BrandStory();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _DripMark(size: 72),
      SizedBox(height: 28),
      Text(
        'Your wardrobe,\nwith better instincts.',
        style: TextStyle(
          fontSize: 48,
          height: 1.03,
          fontWeight: FontWeight.w900,
          letterSpacing: -2,
        ),
      ),
      SizedBox(height: 18),
      Text(
        'Shop standout resale pieces, build complete fits with Drip Concierge, and move to secure checkout when you’re ready.',
        style: TextStyle(fontSize: 16, height: 1.6, color: muted),
      ),
      SizedBox(height: 28),
      _Benefit(
        icon: Icons.auto_awesome_rounded,
        text: 'Professional outfit guidance grounded in live listings',
      ),
      SizedBox(height: 13),
      _Benefit(
        icon: Icons.lock_outline_rounded,
        text: 'Secure sessions and Stripe-hosted payment handoff',
      ),
      SizedBox(height: 13),
      _Benefit(
        icon: Icons.favorite_outline_rounded,
        text: 'A personal space for saved pieces, carts, and seller tools',
      ),
    ],
  );
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(31) > 48;
    final wordmark = Text(
      'drip.',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: largeText ? 28 : 31,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.5,
      ),
    );
    if (largeText) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DripMark(size: 48),
          const SizedBox(height: 8),
          wordmark,
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _DripMark(size: 48),
        const SizedBox(width: 12),
        wordmark,
      ],
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFE1E5EA)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .08),
          blurRadius: 5,
          offset: const Offset(0, 1),
        ),
      ],
    ),
    child: const Text(
      'G',
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        color: Color(0xFF4285F4),
        fontSize: 15,
        height: 1,
        fontWeight: FontWeight.w900,
        fontFamily: 'Roboto',
      ),
    ),
  );
}

class _DripMark extends StatelessWidget {
  final double size;

  const _DripMark({required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .3),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [iceBlue, electricBlue],
      ),
      boxShadow: [
        BoxShadow(color: electricBlue.withValues(alpha: .32), blurRadius: 24),
      ],
    ),
    child: Icon(Icons.water_drop_rounded, color: ink, size: size * .56),
  );
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Benefit({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: electricBlue.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 19, color: electricBlue),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, this.size = 300});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ),
  );
}
