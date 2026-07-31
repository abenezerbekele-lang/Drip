import 'checkout_models.dart';

/// Opens the provider-hosted payment page without exposing payment fields to
/// the Flutter application.
abstract interface class CheckoutLauncher {
  Future<void> launchCheckout(CheckoutSession session);
}
