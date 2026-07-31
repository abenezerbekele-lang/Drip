import 'package:flutter_test/flutter_test.dart';

import 'package:drip/commerce_model.dart';

void main() {
  group('MarketplacePolicy integer-cent invariants', () {
    test('buyer protection applies minimum, formula, and cap', () {
      expect(MarketplacePolicy.buyerProtectionCents(1000), 149);
      expect(MarketplacePolicy.buyerProtectionCents(5186), 306);
      expect(MarketplacePolicy.buyerProtectionCents(10000), 499);
      expect(MarketplacePolicy.buyerProtectionCents(100000), 499);
    });

    test('seller fee respects Basic, Pro, and minimum fee', () {
      expect(MarketplacePolicy.sellerFeeCents(500, sellerIsPro: false), 100);
      expect(MarketplacePolicy.sellerFeeCents(10000, sellerIsPro: false), 1000);
      expect(MarketplacePolicy.sellerFeeCents(10000, sellerIsPro: true), 700);
    });

    test('cent conversion rounds once at the boundary', () {
      expect(toCents(19.999), 2000);
      expect(fromCents(2000), 20);
      expect(money(12.345), 12.35);
    });
  });

  group('payment records', () {
    test('Stripe order metadata survives a persistence round trip', () {
      final order = MarketplaceOrder(
        id: 'order_123',
        productId: 'listing_123',
        productName: 'Archive jacket',
        sellerHandle: '@seller',
        salePriceCents: 12000,
        sellerFeeCents: 1200,
        sellerPayoutCents: 10800,
        status: OrderStatus.placed,
        createdAt: DateTime.utc(2026, 7, 15),
        paymentProvider: PaymentProvider.stripe,
        paymentStatus: PaymentStatus.paid,
        stripeCheckoutSessionId: 'cs_test_123',
        stripePaymentIntentId: 'pi_123',
      );

      final restored = MarketplaceOrder.fromJson(order.toJson());

      expect(restored.paymentProvider, PaymentProvider.stripe);
      expect(restored.paymentStatus, PaymentStatus.paid);
      expect(restored.stripeCheckoutSessionId, 'cs_test_123');
      expect(restored.stripePaymentIntentId, 'pi_123');
      expect(restored.demoPayment, isFalse);
    });

    test('legacy demo records migrate without being labeled as Stripe', () {
      final restored = MarketplaceOrder.fromJson({
        'id': 'DEMO-1',
        'productId': 'listing_1',
        'productName': 'Demo item',
        'sellerHandle': '@seller',
        'salePriceCents': 5000,
        'sellerFeeCents': 500,
        'sellerPayoutCents': 4500,
        'status': 'delivered',
        'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'demoPayment': true,
      });

      expect(restored.paymentProvider, PaymentProvider.demo);
      expect(restored.paymentStatus, PaymentStatus.demo);
    });
  });
}
