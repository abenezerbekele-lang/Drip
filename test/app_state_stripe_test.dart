import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drip/app_state.dart';
import 'package:drip/commerce_model.dart';
import 'package:drip/payments/payments.dart';
import 'package:drip/product_model.dart';
import 'package:drip/sample_data.dart';

import 'support/fake_checkout.dart';

final class _ReadinessCheckoutGateway
    implements CheckoutGateway, CheckoutReadinessGateway {
  final Future<bool> Function() readiness;
  int createCalls = 0;

  _ReadinessCheckoutGateway(this.readiness);

  @override
  Future<bool> isCheckoutReady() => readiness();

  @override
  Future<CheckoutSession> createCheckout(CheckoutRequest request) async {
    createCalls++;
    throw StateError('Checkout should not have started.');
  }

  @override
  Future<CheckoutStatusSnapshot> expireCheckout({
    required String checkoutSessionId,
    required String attemptId,
  }) => throw UnimplementedError();

  @override
  Future<CheckoutStatusSnapshot> getCheckoutStatus(String checkoutSessionId) =>
      throw UnimplementedError();

  @override
  void close() {}
}

void main() {
  Product purchasable() => products.firstWhere(
    (product) => product.sellerHandle != AppState.currentSellerHandle,
  );

  CheckoutQuote quoteFor(AppState state, {int taxCents = 0}) => CheckoutQuote(
    currency: 'usd',
    subtotalCents: state.cartSubtotalCents,
    protectionCents: state.cartBuyerProtectionCents,
    shippingCents: state.cartShippingCents,
    taxCents: taxCents,
    totalCents: state.cartTotalCents + taxCents,
  );

  CheckoutSession sessionFor(AppState state, CheckoutRequest request) =>
      CheckoutSession(
        orderId: 'order_123',
        checkoutSessionId: 'cs_test_123',
        checkoutUrl: Uri.parse('https://checkout.stripe.com/c/pay/cs_test_123'),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 31)),
        quote: quoteFor(state),
      );

  CheckoutStatusSnapshot statusFor(
    AppState state,
    CheckoutPaymentStatus status,
  ) {
    final quote = quoteFor(state);
    final ids = state.pendingCheckout!.lines
        .map((line) => line.listingId)
        .toList();
    final confirmation = status == CheckoutPaymentStatus.paid
        ? CheckoutConfirmation(
            orderId: 'order_123',
            checkoutSessionId: 'cs_test_123',
            paymentIntentId: 'pi_123',
            quote: quote,
            purchasedListingIds: ids,
            confirmedAt: DateTime.utc(2026, 7, 15, 20),
          )
        : null;
    return CheckoutStatusSnapshot(
      orderId: 'order_123',
      checkoutSessionId: 'cs_test_123',
      status: status,
      quote: quote,
      listingIds: ids,
      paymentIntentId: confirmation?.paymentIntentId,
      confirmation: confirmation,
    );
  }

  group('Stripe checkout state', () {
    test(
      'reachable server keeps checkout disabled until Stripe is ready',
      () async {
        final gateway = _ReadinessCheckoutGateway(() async => false);
        final state = AppState(checkoutGateway: gateway)
          ..addToCart(purchasable());
        addTearDown(state.dispose);

        await state.refreshStripeCheckoutConnection();

        expect(
          state.stripeCheckoutConnection,
          StripeCheckoutConnectionState.serverSetupRequired,
        );
        expect(state.stripeCheckoutConfigured, isFalse);
        expect(await state.beginStripeCheckout(), isNull);
        expect(gateway.createCalls, 0);
        expect(state.commerceError, contains('payment server is online'));
      },
    );

    test('verified health enables checkout handoff', () async {
      final gateway = _ReadinessCheckoutGateway(() async => true);
      final state = AppState(checkoutGateway: gateway);
      addTearDown(state.dispose);

      await state.refreshStripeCheckoutConnection();

      expect(
        state.stripeCheckoutConnection,
        StripeCheckoutConnectionState.ready,
      );
      expect(state.stripeCheckoutConfigured, isTrue);
    });

    test('session creation sends only listing IDs and sizes', () async {
      final gateway = FakeCheckoutGateway();
      final state = AppState(checkoutGateway: gateway)
        ..addToCart(purchasable(), size: '9');
      final startingOrders = state.orders.length;
      gateway.onCreate = (request) => sessionFor(state, request);

      final session = await state.beginStripeCheckout();

      expect(session, isNotNull);
      expect(gateway.createCalls, 1);
      expect(gateway.lastRequest!.lines.single.listingId, purchasable().id);
      expect(gateway.lastRequest!.lines.single.selectedSize, '9');
      expect(gateway.lastRequest!.toJson()['items'], [
        {'listingId': purchasable().id, 'selectedSize': '9'},
      ]);
      expect(
        gateway.lastRequest!.toJson().toString(),
        isNot(contains('price')),
      );
      expect(state.orders, hasLength(startingOrders));
      expect(state.receipts, isEmpty);
      expect(state.cart, hasLength(1));
      expect(state.cartLockedForCheckout, isTrue);
    });

    test('repeated starts reuse the persisted Stripe Session', () async {
      final gateway = FakeCheckoutGateway();
      final state = AppState(checkoutGateway: gateway)
        ..addToCart(purchasable());
      gateway.onCreate = (request) => sessionFor(state, request);

      final first = await state.beginStripeCheckout();
      final second = await state.beginStripeCheckout();

      expect(second, first);
      expect(gateway.createCalls, 1);
    });

    test(
      'only paid server confirmation creates the local order cache',
      () async {
        final gateway = FakeCheckoutGateway();
        final product = purchasable();
        final state = AppState(checkoutGateway: gateway)..addToCart(product);
        final startingOrders = state.orders.length;
        gateway.onCreate = (request) => sessionFor(state, request);
        await state.beginStripeCheckout();
        gateway.onStatus = (_) => statusFor(state, CheckoutPaymentStatus.paid);

        final result = await state.refreshStripeCheckout();

        expect(result?.isPaid, isTrue);
        expect(state.cart, isEmpty);
        expect(state.pendingCheckout, isNull);
        expect(state.receipts, hasLength(1));
        expect(state.lastReceipt!.paymentProvider, PaymentProvider.stripe);
        expect(state.lastReceipt!.paymentStatus, PaymentStatus.paid);
        expect(state.lastReceipt!.stripeCheckoutSessionId, 'cs_test_123');
        expect(state.orders, hasLength(startingOrders + 1));
        expect(state.orders.last.productId, product.id);
        expect(state.orders.last.paymentProvider, PaymentProvider.stripe);
        expect(state.orders.last.paymentStatus, PaymentStatus.paid);
        expect(state.isListingAvailable(product), isFalse);
      },
    );

    test(
      'processing status preserves cart and never creates a receipt',
      () async {
        final gateway = FakeCheckoutGateway();
        final state = AppState(checkoutGateway: gateway)
          ..addToCart(purchasable());
        gateway.onCreate = (request) => sessionFor(state, request);
        await state.beginStripeCheckout();
        gateway.onStatus = (_) =>
            statusFor(state, CheckoutPaymentStatus.processing);

        await state.refreshStripeCheckout();

        expect(state.checkoutPaymentStatus, CheckoutPaymentStatus.processing);
        expect(state.pendingCheckout, isNotNull);
        expect(state.cart, hasLength(1));
        expect(state.receipts, isEmpty);
      },
    );

    test('expired status unlocks the unchanged cart', () async {
      final gateway = FakeCheckoutGateway();
      final state = AppState(checkoutGateway: gateway)
        ..addToCart(purchasable());
      gateway.onCreate = (request) => sessionFor(state, request);
      await state.beginStripeCheckout();
      gateway.onStatus = (_) => statusFor(state, CheckoutPaymentStatus.expired);

      await state.refreshStripeCheckout();

      expect(state.pendingCheckout, isNull);
      expect(state.cartLockedForCheckout, isFalse);
      expect(state.cart, hasLength(1));
      expect(state.receipts, isEmpty);
    });

    test('pending Stripe Session survives an app restart', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final gateway = FakeCheckoutGateway();
      final state = AppState(preferences: preferences, checkoutGateway: gateway)
        ..addToCart(purchasable());
      gateway.onCreate = (request) => sessionFor(state, request);

      await state.beginStripeCheckout();
      final restored = AppState(
        preferences: preferences,
        checkoutGateway: FakeCheckoutGateway(),
      );

      expect(restored.pendingCheckout?.checkoutSessionId, 'cs_test_123');
      expect(restored.cartLockedForCheckout, isTrue);
      expect(restored.cart, hasLength(1));
    });

    test(
      'mismatched server quote is expired and never launched as valid',
      () async {
        final gateway = FakeCheckoutGateway();
        final state = AppState(checkoutGateway: gateway)
          ..addToCart(purchasable());
        gateway.onCreate = (request) {
          final expected = quoteFor(state);
          return CheckoutSession(
            orderId: 'order_123',
            checkoutSessionId: 'cs_test_123',
            checkoutUrl: Uri.parse(
              'https://checkout.stripe.com/c/pay/cs_test_123',
            ),
            expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 31)),
            quote: CheckoutQuote(
              currency: 'usd',
              subtotalCents: expected.subtotalCents + 100,
              protectionCents: expected.protectionCents,
              shippingCents: expected.shippingCents,
              taxCents: 0,
              totalCents: expected.totalCents + 100,
            ),
          );
        };
        gateway.onExpire = (sessionId, attemptId) => CheckoutStatusSnapshot(
          orderId: 'order_123',
          checkoutSessionId: sessionId,
          status: CheckoutPaymentStatus.expired,
        );

        final session = await state.beginStripeCheckout();

        expect(session, isNull);
        expect(gateway.expireCalls, 1);
        expect(state.pendingCheckout, isNull);
        expect(state.cartLockedForCheckout, isFalse);
        expect(state.cart, hasLength(1));
        expect(state.commerceError, contains('price check'));
      },
    );

    test('duplicate paid reconciliation is idempotent', () async {
      final gateway = FakeCheckoutGateway();
      final state = AppState(checkoutGateway: gateway)
        ..addToCart(purchasable());
      gateway.onCreate = (request) => sessionFor(state, request);
      await state.beginStripeCheckout();
      final paid = statusFor(state, CheckoutPaymentStatus.paid);
      gateway.onStatus = (_) => paid;

      await state.refreshStripeCheckout();
      await state.refreshStripeCheckout(checkoutSessionId: 'cs_test_123');

      expect(state.receipts, hasLength(1));
      expect(
        state.orders
            .where((order) => order.stripeCheckoutSessionId == 'cs_test_123')
            .length,
        1,
      );
    });
  });
}
