import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:drip/payments/checkout_exception.dart';
import 'package:drip/payments/checkout_models.dart';
import 'package:drip/payments/url_checkout_launcher.dart';

void main() {
  CheckoutSession session() => CheckoutSession(
    orderId: 'order_123',
    checkoutSessionId: 'cs_test_123',
    checkoutUrl: Uri.parse(
      'https://checkout.stripe.com/c/pay/cs_test_123?token=opaque',
    ),
    expiresAt: DateTime.utc(2026, 7, 16),
    quote: CheckoutQuote(
      currency: 'usd',
      subtotalCents: 5200,
      protectionCents: 307,
      shippingCents: 699,
      taxCents: 0,
      totalCents: 6206,
    ),
  );

  test(
    'launcher is injectable and passes through only the verified URL',
    () async {
      Uri? opened;
      final launcher = UrlCheckoutLauncher(
        openUrl: (url) async {
          opened = url;
          return true;
        },
      );

      await launcher.launchCheckout(session());

      expect(opened, session().checkoutUrl);
    },
  );

  test('false launcher result maps to a sanitized typed exception', () async {
    final launcher = UrlCheckoutLauncher(openUrl: (_) async => false);

    expect(
      launcher.launchCheckout(session()),
      throwsA(
        isA<CheckoutLaunchException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains('token=opaque')),
        ),
      ),
    );
  });

  test('launcher timeout is typed and retryable', () async {
    final completer = Completer<bool>();
    final launcher = UrlCheckoutLauncher(
      openUrl: (_) => completer.future,
      timeout: const Duration(milliseconds: 1),
    );

    expect(
      launcher.launchCheckout(session()),
      throwsA(
        isA<CheckoutLaunchException>()
            .having((error) => error.retryable, 'retryable', isTrue)
            .having((error) => error.code, 'code', 'checkout_launch_timeout'),
      ),
    );
  });

  test('plugin failures are sanitized', () async {
    final launcher = UrlCheckoutLauncher(
      openUrl: (_) async => throw StateError('native provider secret detail'),
    );

    Object? caught;
    try {
      await launcher.launchCheckout(session());
    } catch (error) {
      caught = error;
    }

    expect(caught, isA<CheckoutLaunchException>());
    expect(caught.toString(), isNot(contains('native provider')));
  });
}
