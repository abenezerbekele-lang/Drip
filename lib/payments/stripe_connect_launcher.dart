import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import 'stripe_connect_models.dart';

abstract interface class StripeConnectLinkLauncher {
  Future<void> launch(StripeConnectLink link);
}

final class UrlStripeConnectLinkLauncher implements StripeConnectLinkLauncher {
  final Future<bool> Function(Uri) _open;
  final Duration timeout;

  UrlStripeConnectLinkLauncher({
    Future<bool> Function(Uri)? open,
    this.timeout = const Duration(seconds: 10),
  }) : _open = open ?? _openExternally;

  @override
  Future<void> launch(StripeConnectLink link) async {
    if (!StripeConnectLink.isAllowedUrl(link.url, kind: link.kind) ||
        !link.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const StripeConnectException(
        code: StripeConnectFailureCode.launchFailed,
        publicMessage: 'This secure Stripe link expired. Create a new one.',
        retryable: true,
      );
    }
    try {
      final opened = await _open(link.url).timeout(timeout);
      if (!opened) throw const FormatException();
    } on StripeConnectException {
      rethrow;
    } on Object {
      throw const StripeConnectException(
        code: StripeConnectFailureCode.launchFailed,
        publicMessage: 'Stripe could not be opened. Try again.',
        retryable: true,
      );
    }
  }

  static Future<bool> _openExternally(Uri url) => launchUrl(
    url,
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_self',
  );
}
