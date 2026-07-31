import 'checkout_exception.dart';
import 'checkout_models.dart';

typedef CheckoutAccessTokenProvider = Future<String?> Function();

/// Optional capability implemented by network gateways that can verify the
/// public payment server before the buyer starts a checkout.
abstract interface class CheckoutReadinessGateway {
  /// Returns false when the Drip API is reachable but its Stripe credentials
  /// or webhook are not configured. Transport and protocol failures throw a
  /// sanitized [CheckoutException].
  Future<bool> isCheckoutReady();
}

/// Injectable boundary between Flutter state and the checkout backend.
///
/// Implementations must treat the backend as authoritative for inventory,
/// pricing, payment state, and fulfillment eligibility.
abstract interface class CheckoutGateway {
  Future<CheckoutSession> createCheckout(CheckoutRequest request);

  Future<CheckoutStatusSnapshot> getCheckoutStatus(String checkoutSessionId);

  Future<CheckoutStatusSnapshot> expireCheckout({
    required String checkoutSessionId,
    required String attemptId,
  });

  void close();
}
