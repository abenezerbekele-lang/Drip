import 'package:flutter/foundation.dart';

/// Resolves the one public Drip API origin used by accounts and commerce.
///
/// `DRIP_API_URL` is canonical. `DRIP_CHECKOUT_API_URL` remains a legacy
/// fallback so older builds keep working, but it can no longer point checkout
/// and account traffic at different services. Debug builds default to the
/// loopback server; release builds never do.
abstract final class DripApiEndpoint {
  static const environmentKey = 'DRIP_API_URL';
  static const legacyCheckoutEnvironmentKey = 'DRIP_CHECKOUT_API_URL';
  static const _configured = String.fromEnvironment(environmentKey);
  static const _legacyCheckout = String.fromEnvironment(
    legacyCheckoutEnvironmentKey,
  );
  static const debugLoopbackUrl = 'http://localhost:4242';

  static bool get hasExplicitConfiguration =>
      _configured.trim().isNotEmpty || _legacyCheckout.trim().isNotEmpty;

  static String get value {
    final shared = _configured.trim();
    if (shared.isNotEmpty) return shared;
    final legacy = _legacyCheckout.trim();
    if (legacy.isNotEmpty) return legacy;
    return kReleaseMode ? '' : debugLoopbackUrl;
  }

  static Uri? get uri {
    final candidate = Uri.tryParse(value);
    return candidate != null && isAllowedBaseUri(candidate) ? candidate : null;
  }

  static bool isAllowedBaseUri(Uri uri) {
    if (!uri.hasScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.pathSegments.contains('..')) {
      return false;
    }
    if (uri.scheme.toLowerCase() == 'https') return true;
    if (kReleaseMode || uri.scheme.toLowerCase() != 'http') return false;
    final host = uri.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }
}
