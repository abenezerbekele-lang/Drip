import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:drip/app_state.dart';
import 'package:drip/payments/stripe_connect_controller.dart';
import 'package:drip/payments/stripe_connect_gateway.dart';
import 'package:drip/payments/stripe_connect_models.dart';
import 'package:drip/seller_dashboard_page.dart';

class _StatusGateway implements StripeConnectGateway {
  final StripeConnectSnapshot snapshot;

  _StatusGateway(this.snapshot);

  @override
  Future<StripeConnectLink> createDashboardLink() => throw UnimplementedError();

  @override
  Future<StripeConnectLink> createOnboardingLink() =>
      throw UnimplementedError();

  @override
  Future<StripeConnectSnapshot> getStatus() async => snapshot;

  @override
  void close() {}
}

Future<void> _pumpStudio(
  WidgetTester tester,
  StripeConnectSnapshot snapshot,
) async {
  final controller = StripeConnectController(
    gateway: _StatusGateway(snapshot),
    observeLifecycle: false,
    initializeImmediately: false,
  );
  await controller.refresh();
  final app = AppState(
    sellerHandle: '@verified-seller',
    sellerName: 'Verified Seller',
    demoSellerMode: false,
  );
  addTearDown(controller.dispose);
  addTearDown(app.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: controller),
      ],
      child: const MaterialApp(home: SellerDashboardPage()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('real seller sees Stripe onboarding instead of demo payout', (
    tester,
  ) async {
    await _pumpStudio(
      tester,
      const StripeConnectSnapshot(
        status: StripeConnectStatus.notStarted,
        transfersReady: false,
        payoutsReady: false,
        requirementsDue: 0,
        canOpenDashboard: false,
        livemode: false,
      ),
    );

    expect(find.text('Connect your Stripe account'), findsOneWidget);
    expect(find.text('Connect with Stripe'), findsOneWidget);
    expect(find.text('Test mode'), findsOneWidget);
    expect(find.textContaining('Stripe’s secure hosted pages'), findsOneWidget);
    expect(find.textContaining('Request demo payout'), findsNothing);
    expect(find.textContaining('not your Stripe balance'), findsOneWidget);

    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('Stripe test mode. No live funds are moved.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Connect with Stripe'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        'Connect with Stripe. Opens a secure Stripe-hosted page.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('ready seller sees verified capabilities and dashboard action', (
    tester,
  ) async {
    await _pumpStudio(
      tester,
      const StripeConnectSnapshot(
        status: StripeConnectStatus.ready,
        transfersReady: true,
        payoutsReady: true,
        requirementsDue: 0,
        canOpenDashboard: true,
        livemode: false,
      ),
    );

    expect(find.text('Stripe is connected'), findsOneWidget);
    expect(find.text('Transfers ready'), findsOneWidget);
    expect(find.text('Payouts ready'), findsOneWidget);
    expect(find.text('Test mode'), findsOneWidget);
    expect(find.text('Open Stripe dashboard'), findsOneWidget);
    expect(find.textContaining('does not initiate automatic'), findsOneWidget);
  });
}
