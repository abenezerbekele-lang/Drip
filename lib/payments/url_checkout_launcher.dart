import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import 'checkout_exception.dart';
import 'checkout_launcher.dart';
import 'checkout_models.dart';

typedef CheckoutUrlOpener = Future<bool> Function(Uri url);

/// Launches Stripe-hosted Checkout in the system browser.
///
/// Web replaces the current tab to avoid popup blocking after the asynchronous
/// session-creation request. Native and desktop targets hand the HTTPS URL to
/// the operating system rather than embedding a card form or web view.
final class UrlCheckoutLauncher implements CheckoutLauncher {
  final CheckoutUrlOpener _openUrl;
  final Duration timeout;

  UrlCheckoutLauncher({
    CheckoutUrlOpener? openUrl,
    this.timeout = const Duration(seconds: 10),
  }) : _openUrl = openUrl ?? _launchWithPlugin {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 1)) {
      throw const CheckoutConfigurationException();
    }
  }

  @override
  Future<void> launchCheckout(CheckoutSession session) async {
    if (!isAllowedCheckoutUrl(session.checkoutUrl)) {
      throw const CheckoutLaunchException();
    }
    try {
      final launched = await _openUrl(session.checkoutUrl).timeout(timeout);
      if (!launched) throw const CheckoutLaunchException();
    } on CheckoutException {
      rethrow;
    } on TimeoutException {
      throw const CheckoutLaunchException(timedOut: true);
    } on Object {
      throw const CheckoutLaunchException();
    }
  }

  static Future<bool> _launchWithPlugin(Uri url) => launchUrl(
    url,
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_self',
  );
}
