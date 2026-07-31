import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:drip/ai_assistant_page.dart';
import 'package:drip/app_state.dart';
import 'package:drip/cart_page.dart';
import 'package:drip/commerce_model.dart';
import 'package:drip/design_system.dart';
import 'package:drip/image_search_page.dart';
import 'package:drip/payments/payments.dart';
import 'package:drip/product_model.dart';
import 'package:drip/sample_data.dart';
import 'package:drip/sell_page.dart';
import 'package:drip/seller_dashboard_page.dart';

import 'support/fake_checkout.dart';

void main() {
  Product purchasable() => products.firstWhere(
    (product) => product.sellerHandle != AppState.currentSellerHandle,
  );

  void invokeGlassButton(WidgetTester tester, String label) {
    final button = find.ancestor(
      of: find.text(label),
      matching: find.byType(GlassButton),
    );
    tester.widget<GlassButton>(button).onTap!();
  }

  CheckoutQuote quoteFor(AppState state) => CheckoutQuote(
    currency: 'usd',
    subtotalCents: state.cartSubtotalCents,
    protectionCents: state.cartBuyerProtectionCents,
    shippingCents: state.cartShippingCents,
    taxCents: 0,
    totalCents: state.cartTotalCents,
  );

  CheckoutSession sessionFor(AppState state) => CheckoutSession(
    orderId: 'order_widget_123',
    checkoutSessionId: 'cs_test_widget_123',
    checkoutUrl: Uri.parse(
      'https://checkout.stripe.com/c/pay/cs_test_widget_123',
    ),
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 31)),
    quote: quoteFor(state),
  );

  testWidgets('checkout requires Stripe and never asks for raw card data', (
    tester,
  ) async {
    final gateway = FakeCheckoutGateway();
    final launcher = FakeCheckoutLauncher();
    final state = AppState(checkoutGateway: gateway)..addToCart(purchasable());
    gateway.onCreate = (_) => sessionFor(state);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(home: CheckoutPage(launcher: launcher)),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Continue to Stripe'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    invokeGlassButton(tester, 'Continue to Stripe');
    await tester.pumpAndSettle();

    expect(find.text('Card number'), findsNothing);
    expect(find.text('CVC'), findsNothing);
    expect(find.textContaining('Save card'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(gateway.createCalls, 1);
    expect(launcher.calls, 1);
    expect(state.cart, isNotEmpty);
    expect(state.pendingCheckout, isNotNull);
  });

  testWidgets('webhook-confirmed Stripe checkout creates a visible receipt', (
    tester,
  ) async {
    final gateway = FakeCheckoutGateway();
    final launcher = FakeCheckoutLauncher();
    final state = AppState(checkoutGateway: gateway)..addToCart(purchasable());
    gateway.onCreate = (_) => sessionFor(state);
    gateway.onStatus = (_) {
      final pending = state.pendingCheckout!;
      final confirmation = CheckoutConfirmation(
        orderId: pending.orderId,
        checkoutSessionId: pending.checkoutSessionId,
        paymentIntentId: 'pi_widget_123',
        quote: pending.quote,
        purchasedListingIds: pending.lines
            .map((line) => line.listingId)
            .toList(),
        confirmedAt: DateTime.utc(2026, 7, 15, 20),
      );
      return CheckoutStatusSnapshot(
        orderId: pending.orderId,
        checkoutSessionId: pending.checkoutSessionId,
        status: CheckoutPaymentStatus.paid,
        quote: pending.quote,
        listingIds: confirmation.purchasedListingIds,
        paymentIntentId: confirmation.paymentIntentId,
        confirmation: confirmation,
      );
    };
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(home: CheckoutPage(launcher: launcher)),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Continue to Stripe'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    invokeGlassButton(tester, 'Continue to Stripe');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Check payment status'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Check payment status'));
    await tester.pumpAndSettle();

    expect(find.text('Payment confirmed'), findsOneWidget);
    expect(
      find.textContaining('Stripe confirmed your payment'),
      findsOneWidget,
    );
    expect(state.cart, isEmpty);
    expect(state.lastReceipt, isNotNull);
    expect(state.lastReceipt!.paymentProvider, PaymentProvider.stripe);
  });

  testWidgets('sell preview validates details, photo, and declaration', (
    tester,
  ) async {
    var completed = false;
    final state = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(body: SellPage(onComplete: () => completed = true)),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Preview listing'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Preview listing'));
    await tester.pump();

    expect(find.text('Required'), findsWidgets);
    expect(find.text('Choose at least one product photo.'), findsOneWidget);
    expect(completed, isFalse);
  });

  testWidgets('publishing adds a real listing to the seller inventory', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var completed = false;
    final state = AppState();
    final startingCount = state.sellerListings.length;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(body: SellPage(onComplete: () => completed = true)),
        ),
      ),
    );

    await tester.tap(find.text('Choose sample product photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Black runner'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Drip Acquisition Jacket');
    await tester.enterText(fields.at(1), 'Drip Labs');
    await tester.enterText(fields.at(2), 'Jackets');
    await tester.enterText(fields.at(3), 'L');
    await tester.enterText(fields.at(4), '145');
    await tester.enterText(
      fields.at(5),
      'Clean condition with one small mark.',
    );
    tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged!(
      true,
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Preview listing'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    invokeGlassButton(tester, 'Preview listing');
    await tester.pumpAndSettle();
    invokeGlassButton(tester, 'Publish listing');
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(state.sellerListings, hasLength(startingCount + 1));
    expect(
      state.catalogProducts.map((product) => product.name),
      contains('Drip Acquisition Jacket'),
    );
  });

  testWidgets('Seller Studio renders revenue, inventory, and Pro controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(home: SellerDashboardPage()),
      ),
    );

    expect(find.text('Seller Studio'), findsOneWidget);
    expect(find.text('AVAILABLE PAYOUT'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Marketplace revenue engine'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Marketplace revenue engine'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Drip Pro'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Drip Pro'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Your listings'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Your listings'), findsOneWidget);
  });

  testWidgets('image search reveals matches only after a scan', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(home: ImageSearchPage()),
      ),
    );

    expect(find.byType(ProductTile), findsNothing);
    await tester.tap(find.text('Scan sample photo'));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Visual matches'), findsOneWidget);
    expect(find.byType(ProductTile), findsWidgets);
  });

  testWidgets('concierge builds a grounded multi-piece outfit', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(home: AiAssistantPage()),
      ),
    );

    await tester.tap(find.text(r'Build a full fit under $150 total'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Top:'), findsOneWidget);
    expect(find.textContaining('Bottom:'), findsOneWidget);
    expect(find.textContaining('Shoes:'), findsOneWidget);
    expect(find.text('View piece'), findsNWidgets(3));
  });
}
