import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drip/payments/checkout_exception.dart';
import 'package:drip/payments/checkout_models.dart';
import 'package:drip/payments/http_checkout_gateway.dart';

void main() {
  Map<String, Object?> quoteJson() => {
    'currency': 'usd',
    'merchandiseSubtotalCents': 5200,
    'buyerProtectionCents': 307,
    'shippingCents': 699,
    'taxCents': 0,
    'totalCents': 6206,
  };

  Map<String, Object?> sessionJson({String status = 'open'}) => {
    'orderId': 'order_123',
    'sessionId': 'cs_test_123',
    'url':
        'https://checkout.stripe.com/c/pay/cs_test_123#fidkdWxOYHwnPyd1blpxYHZxWjA0',
    'expiresAt': '2026-07-16T12:00:00Z',
    'status': status,
    'quote': quoteJson(),
    'listingIds': ['listing_1'],
  };

  CheckoutRequest request() => CheckoutRequest(
    attemptId: 'attempt_123',
    lines: [CheckoutLine(listingId: 'listing_1', selectedSize: 'M')],
  );

  test(
    'health check verifies Stripe without sending the buyer token',
    () async {
      late http.Request captured;
      var tokenRequested = false;
      final gateway = HttpCheckoutGateway(
        baseUri: Uri.parse('https://api.drip.example'),
        accessTokenProvider: () async {
          tokenRequested = true;
          return 'buyer-jwt';
        },
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'status': 'ok',
              'service': 'drip-checkout',
              'paymentsConfigured': true,
            }),
            200,
          );
        }),
      );

      expect(await gateway.isCheckoutReady(), isTrue);
      expect(captured.method, 'GET');
      expect(captured.url.toString(), 'https://api.drip.example/healthz');
      expect(captured.headers, isNot(contains('authorization')));
      expect(tokenRequested, isFalse);
    },
  );

  test('health check reports reachable server with Stripe disabled', () async {
    final gateway = HttpCheckoutGateway(
      baseUri: Uri.parse('https://api.drip.example'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'status': 'ok',
            'service': 'drip-checkout',
            'paymentsConfigured': false,
          }),
          200,
        ),
      ),
    );

    expect(await gateway.isCheckoutReady(), isFalse);
  });

  test('health check rejects a lookalike service response', () async {
    final gateway = HttpCheckoutGateway(
      baseUri: Uri.parse('https://api.drip.example'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'status': 'ok',
            'service': 'lookalike',
            'paymentsConfigured': true,
          }),
          200,
        ),
      ),
    );

    await expectLater(
      gateway.isCheckoutReady(),
      throwsA(isA<CheckoutProtocolException>()),
    );
  });

  test(
    'create uses canonical endpoint and sends no client-side money',
    () async {
      late http.Request captured;
      final client = MockClient((baseRequest) async {
        captured = baseRequest;
        return http.Response(jsonEncode(sessionJson()), 201);
      });
      final gateway = HttpCheckoutGateway(
        baseUri: Uri.parse('https://api.drip.example'),
        client: client,
        accessTokenProvider: () async => 'buyer-jwt',
      );

      final session = await gateway.createCheckout(request());

      expect(captured.method, 'POST');
      expect(
        captured.url.toString(),
        'https://api.drip.example/v1/checkout/sessions',
      );
      expect(jsonDecode(captured.body), {
        'attemptId': 'attempt_123',
        'items': [
          {'listingId': 'listing_1', 'selectedSize': 'M'},
        ],
      });
      expect(captured.body, isNot(contains('Cents')));
      expect(captured.body, isNot(contains('price')));
      expect(captured.body, isNot(contains('seller')));
      expect(captured.headers['authorization'], 'Bearer buyer-jwt');
      expect(captured.headers['idempotency-key'], 'attempt_123');
      expect(captured.headers.keys.join(' '), isNot(contains('stripe')));
      expect(session.orderId, 'order_123');
      expect(session.quote.totalCents, 6206);
    },
  );

  test('status is fetched by sanitized session id', () async {
    late http.Request captured;
    final client = MockClient((baseRequest) async {
      captured = baseRequest;
      final body = sessionJson(status: 'payment_review')
        ..['paymentIntentId'] = 'pi_123';
      return http.Response(jsonEncode(body), 200);
    });
    final gateway = HttpCheckoutGateway(
      baseUri: Uri.parse('https://api.drip.example/api'),
      client: client,
    );

    final result = await gateway.getCheckoutStatus('cs_test_123');

    expect(captured.method, 'GET');
    expect(
      captured.url.toString(),
      'https://api.drip.example/api/v1/checkout/sessions/cs_test_123',
    );
    expect(result.status, CheckoutPaymentStatus.paymentReview);
    expect(result.isPaid, isFalse);
    expect(result.paymentIntentId, 'pi_123');
  });

  test('paid status is reconciled from exact backend values', () async {
    final client = MockClient((_) async {
      final body = sessionJson(status: 'paid')..['paymentIntentId'] = 'pi_123';
      return http.Response(jsonEncode(body), 200);
    });
    final gateway = HttpCheckoutGateway(
      baseUri: Uri.parse('https://api.drip.example'),
      client: client,
    );

    final result = await gateway.getCheckoutStatus('cs_test_123');

    expect(result.isPaid, isTrue);
    expect(result.confirmation!.totalCents, 6206);
    expect(result.confirmation!.purchasedListingIds, ['listing_1']);
  });

  test('expire sends only the attempt id to the canonical endpoint', () async {
    late http.Request captured;
    final client = MockClient((baseRequest) async {
      captured = baseRequest;
      return http.Response(jsonEncode(sessionJson(status: 'expired')), 200);
    });
    final gateway = HttpCheckoutGateway(
      baseUri: Uri.parse('https://api.drip.example'),
      client: client,
    );

    final result = await gateway.expireCheckout(
      checkoutSessionId: 'cs_test_123',
      attemptId: 'attempt_123',
    );

    expect(captured.method, 'POST');
    expect(
      captured.url.toString(),
      'https://api.drip.example/v1/checkout/sessions/cs_test_123/expire',
    );
    expect(jsonDecode(captured.body), {'attemptId': 'attempt_123'});
    expect(result.status, CheckoutPaymentStatus.expired);
  });

  for (final scenario in <(int, Type)>[
    (409, CheckoutConflictException),
    (422, CheckoutRejectedException),
    (503, CheckoutUnavailableException),
  ]) {
    test('maps HTTP ${scenario.$1} to a sanitized typed exception', () async {
      final client = MockClient(
        (_) async => http.Response(
          '{"error":"raw provider detail sk_test_should_not_escape"}',
          scenario.$1,
        ),
      );
      final gateway = HttpCheckoutGateway(
        baseUri: Uri.parse('https://api.drip.example'),
        client: client,
      );

      Object? caught;
      try {
        await gateway.createCheckout(request());
      } catch (error) {
        caught = error;
      }

      expect(caught.runtimeType, scenario.$2);
      expect(caught.toString(), isNot(contains('provider detail')));
      expect(caught.toString(), isNot(contains('sk_test')));
    });
  }

  test('preserves seller payout readiness as an actionable error', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'seller_payout_unavailable',
            'message': 'sensitive provider detail sk_test_hidden',
          },
        }),
        409,
      ),
    );
    final gateway = HttpCheckoutGateway(
      baseUri: Uri.parse('https://api.drip.example'),
      client: client,
    );

    await expectLater(
      gateway.createCheckout(request()),
      throwsA(
        isA<CheckoutSellerPayoutUnavailableException>()
            .having((error) => error.code, 'code', 'seller_payout_unavailable')
            .having(
              (error) => error.publicMessage,
              'message',
              allOf(contains('seller'), isNot(contains('sk_test'))),
            ),
      ),
    );
  });

  test('rejects a response with a non-browser checkout URL', () async {
    final client = MockClient((_) async {
      final body = sessionJson()..['url'] = 'javascript:alert(1)';
      return http.Response(jsonEncode(body), 201);
    });
    final gateway = HttpCheckoutGateway(
      baseUri: Uri.parse('https://api.drip.example'),
      client: client,
    );

    expect(
      gateway.createCheckout(request()),
      throwsA(isA<CheckoutProtocolException>()),
    );
  });

  test('rejects a non-Stripe HTTPS checkout URL from the backend', () async {
    final client = MockClient((_) async {
      final body = sessionJson()
        ..['url'] = 'https://payments.example.com/stripe-lookalike';
      return http.Response(jsonEncode(body), 201);
    });
    final gateway = HttpCheckoutGateway(
      baseUri: Uri.parse('https://api.drip.example'),
      client: client,
    );

    expect(
      gateway.createCheckout(request()),
      throwsA(isA<CheckoutProtocolException>()),
    );
  });

  test('rejects path injection before making a status request', () async {
    var requested = false;
    final client = MockClient((_) async {
      requested = true;
      return http.Response('{}', 200);
    });
    final gateway = HttpCheckoutGateway(
      baseUri: Uri.parse('https://api.drip.example'),
      client: client,
    );

    expect(
      gateway.getCheckoutStatus('../admin'),
      throwsA(isA<CheckoutValidationException>()),
    );
    expect(requested, isFalse);
  });

  test('maps request timeout without leaking a URL or response', () async {
    final client = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return http.Response(jsonEncode(sessionJson()), 201);
    });
    final gateway = HttpCheckoutGateway(
      baseUri: Uri.parse('https://api.drip.example'),
      client: client,
      timeout: const Duration(milliseconds: 1),
    );

    expect(
      gateway.createCheckout(request()),
      throwsA(
        isA<CheckoutNetworkException>()
            .having((error) => error.timedOut, 'timedOut', isTrue)
            .having(
              (error) => error.toString(),
              'message',
              isNot(contains('api.drip.example')),
            ),
      ),
    );
  });

  test('only allows HTTPS or loopback HTTP API bases', () {
    expect(
      () => HttpCheckoutGateway(
        baseUri: Uri.parse('http://api.drip.example'),
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
      throwsA(isA<CheckoutConfigurationException>()),
    );
    expect(
      () => HttpCheckoutGateway(
        baseUri: Uri.parse('http://localhost:4242'),
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
      returnsNormally,
    );
  });
}
