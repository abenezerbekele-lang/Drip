import 'dart:async';

import 'package:drip/ai_assistant_page.dart';
import 'package:drip/app_shell.dart';
import 'package:drip/app_state.dart';
import 'package:drip/auth/auth_gateway.dart';
import 'package:drip/auth/auth_models.dart';
import 'package:drip/auth/auth_session_store.dart';
import 'package:drip/cart_page.dart';
import 'package:drip/design_system.dart';
import 'package:drip/main.dart';
import 'package:drip/payments/payments.dart';
import 'package:drip/sample_data.dart';
import 'package:drip/seller_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

const _fastWalkthrough = bool.fromEnvironment(
  'DRIP_DEMO_FAST',
  defaultValue: false,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'records the two-minute Drip product walkthrough',
    (tester) async {
      final session = AuthSession(
        user: const AuthUser(
          id: 'demo_jordan_lee',
          name: 'Jordan Lee',
          email: 'jordan@drip.app',
          sellerHandle: '@jordanfits',
        ),
        accessToken: 'recording-only-session-token',
        expiresAt: DateTime.utc(2035, 1, 1),
      );
      final checkout = _RecordingCheckoutGateway();

      await tester.pumpWidget(
        DripApp(
          initiallyWelcomed: true,
          authGateway: _RecordingAuthGateway(session),
          authSessionStore: MemoryAuthSessionStore(session),
          checkoutGateway: checkout,
          allowDemo: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);

      await _hold(const Duration(seconds: 9));
      await _slowScroll(tester, pixels: 520);
      await _hold(const Duration(seconds: 5));

      final askDripLabels = find.text('Ask Drip');
      expect(askDripLabels, findsNWidgets(2));
      await tester.tap(askDripLabels.at(1));
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantPage), findsOneWidget);
      await _hold(const Duration(seconds: 5));
      await tester.tap(find.text(r'Build a full fit under $150 total'));
      await tester.pumpAndSettle();
      await _hold(const Duration(seconds: 12));

      await tester.pageBack();
      await tester.pumpAndSettle();
      await _hold(const Duration(seconds: 2));
      await tester.tap(find.text('Market'));
      await tester.pumpAndSettle();
      await _hold(const Duration(seconds: 7));
      await _slowScroll(tester, pixels: 540);
      await _hold(const Duration(seconds: 5));

      final tiles = find.byType(ProductTile);
      expect(tiles, findsWidgets);
      await tester.tap(tiles.at(0));
      await tester.pumpAndSettle();
      await _hold(const Duration(seconds: 9));

      await tester.pageBack();
      await tester.pumpAndSettle();
      await _hold(const Duration(seconds: 2));
      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      await _hold(const Duration(seconds: 6));

      await tester.tap(find.text('You'));
      await tester.pumpAndSettle();
      await _hold(const Duration(seconds: 9));

      await tester.tap(find.text('Seller Studio'));
      await tester.pumpAndSettle();
      expect(find.byType(SellerDashboardPage), findsOneWidget);
      await _hold(const Duration(seconds: 9));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _hold(const Duration(seconds: 2));

      final shellContext = tester.element(find.byType(AppShell));
      final state = Provider.of<AppState>(shellContext, listen: false);
      final product = products.firstWhere(
        (item) =>
            item.sellerHandle != state.activeSellerHandle &&
            state.isListingAvailable(item),
      );
      state.addToCart(product, size: product.sizes.first);
      unawaited(
        Navigator.of(shellContext).push<void>(dripRoute(const CartPage())),
      );
      await tester.pumpAndSettle();
      await _hold(const Duration(seconds: 8));

      final cartContext = tester.element(find.byType(CartPage));
      unawaited(
        Navigator.of(cartContext).push<void>(dripRoute(const CheckoutPage())),
      );
      await tester.pumpAndSettle();
      await _hold(const Duration(seconds: 14));

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await _hold(const Duration(seconds: 8));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _hold(Duration duration) async {
  await Future<void>.delayed(
    _fastWalkthrough ? const Duration(milliseconds: 20) : duration,
  );
}

Future<void> _slowScroll(WidgetTester tester, {required double pixels}) async {
  final scrollable = find.byType(Scrollable);
  expect(scrollable, findsWidgets);
  final target = scrollable.at(0);
  final gesture = await tester.startGesture(tester.getCenter(target));
  final steps = _fastWalkthrough ? 3 : 24;
  for (var step = 0; step < steps; step++) {
    await gesture.moveBy(Offset(0, -pixels / steps));
    await tester.pump();
    await Future<void>.delayed(
      _fastWalkthrough
          ? const Duration(milliseconds: 5)
          : const Duration(milliseconds: 80),
    );
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

final class _RecordingAuthGateway implements AuthGateway {
  final AuthSession session;

  const _RecordingAuthGateway(this.session);

  @override
  Future<AuthSession> restoreSession(AuthSession storedSession) async =>
      session;

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async => AuthResult(session: session);

  @override
  Future<EmailVerificationChallenge> signUp({
    required String name,
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResult> verifyEmail({
    required String challengeToken,
    required String code,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<EmailVerificationChallenge> resendVerification({
    required String challengeToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut(AuthSession session) async {}

  @override
  void close() {}
}

final class _RecordingCheckoutGateway implements CheckoutGateway {
  @override
  Future<CheckoutSession> createCheckout(CheckoutRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<CheckoutStatusSnapshot> expireCheckout({
    required String checkoutSessionId,
    required String attemptId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CheckoutStatusSnapshot> getCheckoutStatus(String checkoutSessionId) {
    throw UnimplementedError();
  }

  @override
  void close() {}
}
