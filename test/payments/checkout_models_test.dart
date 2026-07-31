import 'package:flutter_test/flutter_test.dart';

import 'package:drip/payments/checkout_exception.dart';
import 'package:drip/payments/checkout_models.dart';

void main() {
  CheckoutQuote quote() => CheckoutQuote(
    currency: 'usd',
    subtotalCents: 5200,
    protectionCents: 307,
    shippingCents: 699,
    taxCents: 0,
    totalCents: 6206,
  );

  Map<String, Object?> sessionJson() => {
    'orderId': 'order_123',
    'sessionId': 'cs_test_123',
    'url': 'https://checkout.stripe.com/c/pay/cs_test_123',
    'expiresAt': '2026-07-16T12:00:00Z',
    'status': 'open',
    'quote': quote().toJson(),
  };

  group('checkout request', () {
    test('serializes only attempt and listing selection identifiers', () {
      final request = CheckoutRequest(
        attemptId: 'attempt_123',
        lines: [
          CheckoutLine(listingId: 'listing_1', selectedSize: ' M '),
          CheckoutLine(listingId: 'listing_2', selectedSize: '32 x 30'),
        ],
      );

      expect(request.toJson(), {
        'attemptId': 'attempt_123',
        'items': [
          {'listingId': 'listing_1', 'selectedSize': 'M'},
          {'listingId': 'listing_2', 'selectedSize': '32 x 30'},
        ],
      });
      expect(request.toJson().toString(), isNot(contains('price')));
      expect(request.toJson().toString(), isNot(contains('total')));
      expect(request.toJson().toString(), isNot(contains('seller')));
    });

    test('rejects duplicate one-of-one listings and control characters', () {
      expect(
        () => CheckoutRequest(
          attemptId: 'attempt_123',
          lines: [
            CheckoutLine(listingId: 'listing_1', selectedSize: 'M'),
            CheckoutLine(listingId: 'listing_1', selectedSize: 'L'),
          ],
        ),
        throwsA(isA<CheckoutValidationException>()),
      );
      expect(
        () => CheckoutLine(listingId: 'listing_1', selectedSize: 'M\nL'),
        throwsA(isA<CheckoutValidationException>()),
      );
    });

    test('matches the server limit of twenty one-of-one listings', () {
      final twenty = List.generate(
        20,
        (index) => CheckoutLine(listingId: 'listing_$index', selectedSize: 'M'),
      );

      expect(
        () => CheckoutRequest(attemptId: 'attempt_123', lines: twenty),
        returnsNormally,
      );
      expect(
        () => CheckoutRequest(
          attemptId: 'attempt_123',
          lines: [
            ...twenty,
            CheckoutLine(listingId: 'listing_20', selectedSize: 'M'),
          ],
        ),
        throwsA(
          isA<CheckoutValidationException>().having(
            (error) => error.publicMessage,
            'message',
            contains('20'),
          ),
        ),
      );
    });

    test('owns an immutable copy of its lines', () {
      final source = [CheckoutLine(listingId: 'listing_1', selectedSize: 'M')];
      final request = CheckoutRequest(attemptId: 'attempt_123', lines: source);
      source.add(CheckoutLine(listingId: 'listing_2', selectedSize: 'L'));

      expect(request.lines, hasLength(1));
      expect(() => request.lines.clear(), throwsUnsupportedError);
    });
  });

  group('server response models', () {
    test('parses canonical session fields and exact server quote', () {
      final session = CheckoutSession.fromJson(sessionJson());

      expect(session.orderId, 'order_123');
      expect(session.checkoutSessionId, 'cs_test_123');
      expect(session.checkoutUrl.host, 'checkout.stripe.com');
      expect(session.quote.totalCents, 6206);
      expect(session.quote.subtotalCents, 5200);
      expect(session.expiresAt.isUtc, isTrue);
    });

    test('also accepts documented compatibility aliases', () {
      final json = sessionJson()
        ..remove('sessionId')
        ..remove('url')
        ..['checkoutSessionId'] = 'cs_test_alias'
        ..['checkoutUrl'] = 'https://checkout.stripe.com/c/pay/cs_test_alias';

      final session = CheckoutSession.fromJson(json);

      expect(session.sessionId, 'cs_test_alias');
      expect(session.checkoutUrl.host, 'checkout.stripe.com');
    });

    test('accepts only strict Stripe-hosted HTTPS checkout URLs', () {
      expect(
        isAllowedCheckoutUrl(Uri.parse('https://checkout.stripe.com/c/pay/x')),
        isTrue,
      );
      expect(
        isAllowedCheckoutUrl(
          Uri.parse('https://regional.checkout.stripe.com/c/pay/x'),
        ),
        isTrue,
      );
      expect(
        isAllowedCheckoutUrl(Uri.parse('http://checkout.stripe.com/c/pay/x')),
        isFalse,
      );
      expect(
        isAllowedCheckoutUrl(Uri.parse('http://localhost:4242/checkout/x')),
        isFalse,
      );
      expect(
        isAllowedCheckoutUrl(
          Uri.parse('https://checkout.stripe.com.evil.example/c/pay/x'),
        ),
        isFalse,
      );
      expect(
        isAllowedCheckoutUrl(Uri.parse('https://stripe.com/c/pay/x')),
        isFalse,
      );
      expect(
        isAllowedCheckoutUrl(
          Uri.parse('https://checkout.stripe.com:8443/c/pay/x'),
        ),
        isFalse,
      );
      expect(isAllowedCheckoutUrl(Uri.parse('javascript:alert(1)')), isFalse);
      expect(
        isAllowedCheckoutUrl(
          Uri.parse('https://user:password@checkout.stripe.com/x'),
        ),
        isFalse,
      );
      expect(
        isAllowedCheckoutUrl(
          Uri.parse(
            'https://checkout.stripe.com/c/pay/x#fidkdWxOYHwnPyd1blpxYHZxWjA0',
          ),
        ),
        isTrue,
      );
      expect(
        isAllowedCheckoutUrl(
          Uri.parse('https://checkout.stripe.com/c/pay/x?value=%0Aheader'),
        ),
        isFalse,
      );
    });

    test('maps all backend states and keeps future states non-paid', () {
      expect(
        CheckoutPaymentStatus.parse('creating'),
        CheckoutPaymentStatus.creating,
      );
      expect(
        CheckoutPaymentStatus.parse('payment_review'),
        CheckoutPaymentStatus.paymentReview,
      );
      expect(
        CheckoutPaymentStatus.parse('payment_failed'),
        CheckoutPaymentStatus.failed,
      );
      expect(
        CheckoutPaymentStatus.parse('future_provider_state'),
        CheckoutPaymentStatus.unknown,
      );
      expect(CheckoutPaymentStatus.unknown.isPaid, isFalse);
      expect(CheckoutPaymentStatus.paymentReview.isTerminal, isFalse);
    });

    test('paid status constructs a confirmation only from server amounts', () {
      final status = CheckoutStatusSnapshot.fromJson({
        'orderId': 'order_123',
        'sessionId': 'cs_test_123',
        'status': 'paid',
        'paymentIntentId': 'pi_123',
        'listingIds': ['listing_1'],
        'quote': quote().toJson(),
      });

      expect(status.isPaid, isTrue);
      expect(status.confirmation, isNotNull);
      expect(status.confirmation!.paymentIntentId, 'pi_123');
      expect(status.confirmation!.totalCents, 6206);
      expect(status.confirmation!.purchasedListingIds, ['listing_1']);
    });

    test('future unknown state cannot be interpreted as payment success', () {
      final status = CheckoutStatusSnapshot.fromJson({
        'orderId': 'order_123',
        'sessionId': 'cs_test_123',
        'status': 'requires_future_action',
        'listingIds': ['listing_1'],
        'quote': quote().toJson(),
      });

      expect(status.status, CheckoutPaymentStatus.unknown);
      expect(status.isPaid, isFalse);
      expect(status.confirmation, isNull);
    });
  });

  test('pending checkout has a lossless immutable JSON round trip', () {
    final request = CheckoutRequest(
      attemptId: 'attempt_123',
      lines: [CheckoutLine(listingId: 'listing_1', selectedSize: 'M')],
    );
    final session = CheckoutSession.fromJson(sessionJson());
    final pending = PendingCheckout.fromSession(
      request: request,
      session: session,
      createdAt: DateTime.utc(2026, 7, 15, 12),
    );

    final restored = PendingCheckout.fromJson(pending.toJson());

    expect(restored, pending);
    expect(restored.checkoutSessionId, session.checkoutSessionId);
    expect(() => restored.lines.clear(), throwsUnsupportedError);
  });

  test('checkout exceptions never print server or credential details', () {
    const exception = CheckoutUnavailableException(statusCode: 503);

    expect(exception.toString(), exception.publicMessage);
    expect(exception.toString(), isNot(contains('503')));
    expect(exception.toString(), isNot(contains('sk_')));
    expect(exception.retryable, isTrue);
  });
}
