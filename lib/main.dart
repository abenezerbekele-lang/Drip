import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_shell.dart';
import 'app_state.dart';
import 'auth/auth_controller.dart';
import 'auth/firebase_auth_gateway.dart';
import 'auth/auth_gateway.dart';
import 'auth/auth_models.dart';
import 'auth/auth_page.dart';
import 'auth/auth_session_store.dart';
import 'checkout_return_page.dart';
import 'design_system.dart';
import 'firebase_options.dart';
import 'payments/payments.dart';
import 'welcome_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final preferences = await SharedPreferences.getInstance();
  runApp(
    DripApp(
      preferences: preferences,
      authSessionStore: const SecureAuthSessionStore(),
      initialDarkMode: preferences.getBool('drip.darkMode') ?? false,
      initiallyWelcomed: preferences.getBool('drip.welcomed') ?? false,
    ),
  );
}

class DripApp extends StatefulWidget {
  final SharedPreferences? preferences;
  final bool initialDarkMode;
  final bool initiallyWelcomed;
  final CheckoutGateway? checkoutGateway;
  final StripeConnectGateway? stripeConnectGateway;
  final String? checkoutReturnSessionId;
  final AuthController? authController;
  final AuthGateway? authGateway;
  final AuthSessionStore? authSessionStore;
  final bool? allowDemo;

  const DripApp({
    super.key,
    this.preferences,
    this.initialDarkMode = false,
    this.initiallyWelcomed = false,
    this.checkoutGateway,
    this.stripeConnectGateway,
    this.checkoutReturnSessionId,
    this.authController,
    this.authGateway,
    this.authSessionStore,
    this.allowDemo,
  });

  @override
  State<DripApp> createState() => _DripAppState();
}

class _DripAppState extends State<DripApp> {
  static const _explicitDemoMode = bool.fromEnvironment(
    'DRIP_ENABLE_DEMO_MODE',
    defaultValue: false,
  );

  late bool darkMode;
  late bool welcomed;
  late final AuthController authController;
  late final bool ownsAuthController;
  late AccountServiceConnectionState accountServiceConnection;
  AuthReadinessGateway? authReadinessGateway;
  Future<void>? _accountReadinessRequest;
  String? checkoutReturnSessionId;

  @override
  void initState() {
    super.initState();
    darkMode = widget.initialDarkMode;
    welcomed = widget.initiallyWelcomed;
    checkoutReturnSessionId =
        widget.checkoutReturnSessionId ??
        Uri.base.queryParameters['stripe_session_id'] ??
        Uri.base.queryParameters['session_id'];

    ownsAuthController = widget.authController == null;
    final injectedController = widget.authController;
    if (injectedController != null) {
      authController = injectedController;
      accountServiceConnection = AccountServiceConnectionState.ready;
      return;
    }

    final gateway = _createAuthGateway();
    authController = _createAuthController(gateway);
    if (gateway is UnavailableAuthGateway) {
      accountServiceConnection = AccountServiceConnectionState.notConfigured;
    } else if (gateway is AuthReadinessGateway) {
      authReadinessGateway = gateway as AuthReadinessGateway;
      accountServiceConnection = AccountServiceConnectionState.checking;
      unawaited(refreshAccountServiceConnection());
    } else {
      // An injected native/test gateway is an explicit trusted boundary.
      accountServiceConnection = AccountServiceConnectionState.ready;
    }
  }

  AuthGateway _createAuthGateway() {
    final injectedGateway = widget.authGateway;
    if (injectedGateway != null) return injectedGateway;
    // `main()` initializes Firebase before creating the app. The empty-app
    // fallback keeps isolated widget tests and unsupported preview targets from
    // trying to access a native Firebase plugin that has not been configured.
    return Firebase.apps.isEmpty
        ? const UnavailableAuthGateway()
        : FirebaseAuthGateway();
  }

  AuthController _createAuthController(AuthGateway gateway) => AuthController(
    gateway: gateway,
    store: widget.authSessionStore ?? const SecureAuthSessionStore(),
    allowDemo: widget.allowDemo ?? _explicitDemoMode,
    ownsGateway: widget.authGateway == null,
  );

  Future<void> refreshAccountServiceConnection() {
    final active = _accountReadinessRequest;
    if (active != null) return active;
    final gateway = authReadinessGateway;
    if (gateway == null) return Future.value();
    authController.clearError();
    final future = _refreshAccountServiceConnection(gateway);
    _accountReadinessRequest = future;
    return future.whenComplete(() {
      if (identical(_accountReadinessRequest, future)) {
        _accountReadinessRequest = null;
      }
    });
  }

  Future<void> _refreshAccountServiceConnection(
    AuthReadinessGateway gateway,
  ) async {
    if (mounted &&
        accountServiceConnection != AccountServiceConnectionState.checking) {
      setState(() {
        accountServiceConnection = AccountServiceConnectionState.checking;
      });
    }
    try {
      final readiness = await gateway.getServiceReadiness();
      if (!mounted) return;
      setState(() {
        accountServiceConnection = readiness.accountsConfigured
            ? AccountServiceConnectionState.ready
            : AccountServiceConnectionState.serverSetupRequired;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        accountServiceConnection = AccountServiceConnectionState.unavailable;
      });
    }
  }

  @override
  void dispose() {
    if (ownsAuthController) authController.dispose();
    super.dispose();
  }

  void toggleTheme() {
    setState(() => darkMode = !darkMode);
    widget.preferences?.setBool('drip.darkMode', darkMode);
  }

  void completeWelcome() {
    setState(() => welcomed = true);
    widget.preferences?.setBool('drip.welcomed', true);
  }

  void completeCheckoutReturn() {
    setState(() {
      checkoutReturnSessionId = null;
      welcomed = true;
    });
    widget.preferences?.setBool('drip.welcomed', true);
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: authController,
    child: Consumer<AuthController>(
      builder: (context, auth, _) {
        final app = MaterialApp(
          title: 'drip',
          debugShowCheckedModeBanner: false,
          theme: _lightTheme(),
          darkTheme: _darkTheme(),
          themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
          home: _homeFor(auth),
        );
        final marketplaceReady =
            auth.status == AuthStatus.demo ||
            (auth.status == AuthStatus.signedIn && auth.signupResult == null);
        if (!marketplaceReady) return app;

        final namespace = auth.status == AuthStatus.signedIn
            ? 'account-${auth.user!.id}'
            : 'demo';
        final signedInUser = auth.status == AuthStatus.signedIn
            ? auth.user
            : null;
        return _MarketplaceScope(
          key: ValueKey(namespace),
          preferences: widget.preferences,
          storageNamespace: namespace,
          injectedCheckoutGateway: widget.checkoutGateway,
          injectedStripeConnectGateway: widget.stripeConnectGateway,
          accessTokenProvider: auth.accessToken,
          sellerName: signedInUser?.name,
          sellerHandle: signedInUser == null
              ? null
              : signedInUser.sellerHandle ??
                    _localSellerHandle(signedInUser.name, signedInUser.id),
          child: app,
        );
      },
    ),
  );

  Widget _homeFor(AuthController auth) {
    if (auth.status == AuthStatus.initializing) {
      return const AuthLoadingPage();
    }
    if (auth.status == AuthStatus.signedOut) {
      return AuthPage(
        accountServiceConnection: accountServiceConnection,
        onRetryConnection: refreshAccountServiceConnection,
      );
    }
    final signupResult = auth.signupResult;
    if (auth.status == AuthStatus.signedIn && signupResult != null) {
      return SignupSuccessPage(
        result: signupResult,
        onContinue: auth.completeSignupNotice,
      );
    }
    if (checkoutReturnSessionId != null) {
      return CheckoutReturnPage(
        checkoutSessionId: checkoutReturnSessionId!,
        onDone: completeCheckoutReturn,
      );
    }
    return welcomed
        ? AppShell(onThemeToggle: toggleTheme)
        : WelcomePage(onDone: completeWelcome);
  }

  String _localSellerHandle(String name, String id) {
    final compactName = name.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    final slug = compactName.length <= 16
        ? compactName
        : compactName.substring(0, 16);
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final suffix = safeId.length <= 4
        ? safeId.toLowerCase()
        : safeId.substring(safeId.length - 4).toLowerCase();
    return '@${slug.isEmpty ? 'member' : slug}${suffix.isEmpty ? '' : '-$suffix'}';
  }

  ThemeData _lightTheme() => ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: electricBlue,
          brightness: Brightness.light,
          surface: const Color(0xFFF4F7FC),
        ).copyWith(
          primary: const Color(0xFF1F65B5),
          onSurfaceVariant: const Color(0xFF58677C),
        ),
    scaffoldBackgroundColor: const Color(0xFFF4F7FC),
    textTheme: GoogleFonts.manropeTextTheme(),
    dividerColor: const Color(0xFFD9E3F0),
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
    ),
    inputDecorationTheme: _inputTheme(
      fill: Colors.white.withValues(alpha: .78),
      border: const Color(0xFFDCE6F3),
    ),
  );

  ThemeData _darkTheme() => ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: electricBlue,
      brightness: Brightness.dark,
      surface: ink,
      surfaceContainer: panel,
    ).copyWith(primary: iceBlue, onSurfaceVariant: const Color(0xFFACB8C9)),
    scaffoldBackgroundColor: ink,
    textTheme: GoogleFonts.manropeTextTheme(ThemeData.dark().textTheme),
    dividerColor: Colors.white12,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
    ),
    inputDecorationTheme: _inputTheme(
      fill: panel.withValues(alpha: .88),
      border: Colors.white12,
    ),
  );

  InputDecorationTheme _inputTheme({
    required Color fill,
    required Color border,
  }) => InputDecorationTheme(
    filled: true,
    fillColor: fill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: electricBlue, width: 1.5),
    ),
  );
}

class _MarketplaceScope extends StatelessWidget {
  final SharedPreferences? preferences;
  final String storageNamespace;
  final CheckoutGateway? injectedCheckoutGateway;
  final StripeConnectGateway? injectedStripeConnectGateway;
  final CheckoutAccessTokenProvider accessTokenProvider;
  final String? sellerName;
  final String? sellerHandle;
  final Widget child;

  const _MarketplaceScope({
    super.key,
    required this.preferences,
    required this.storageNamespace,
    required this.injectedCheckoutGateway,
    required this.injectedStripeConnectGateway,
    required this.accessTokenProvider,
    required this.sellerName,
    required this.sellerHandle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) {
          final gateway =
              injectedCheckoutGateway ??
              (HttpCheckoutGateway.isEnvironmentConfigured
                  ? HttpCheckoutGateway.fromEnvironment(
                      accessTokenProvider: accessTokenProvider,
                    )
                  : null);
          return AppState(
            preferences: preferences,
            checkoutGateway: gateway,
            storageNamespace: storageNamespace,
            sellerName: sellerName,
            sellerHandle: sellerHandle,
            demoSellerMode: sellerHandle == null,
          );
        },
      ),
      ChangeNotifierProvider(
        create: (_) {
          final gateway =
              injectedStripeConnectGateway ??
              (sellerHandle != null &&
                      HttpStripeConnectGateway.isEnvironmentConfigured
                  ? HttpStripeConnectGateway.fromEnvironment(
                      accessTokenProvider: accessTokenProvider,
                    )
                  : const UnavailableStripeConnectGateway());
          return StripeConnectController(
            gateway: gateway,
            initializeImmediately: sellerHandle != null,
          );
        },
      ),
    ],
    child: child,
  );
}
