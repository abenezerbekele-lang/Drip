import 'package:flutter/foundation.dart';

final RegExp _connectControlCharacterPattern = RegExp(
  r'[\x00-\x1F\x7F\u0080-\u009F]',
);

enum StripeConnectStatus {
  notStarted,
  onboardingIncomplete,
  verificationPending,
  restricted,
  ready;

  static StripeConnectStatus parse(Object? value) => switch (value) {
    'not_started' => notStarted,
    'onboarding_incomplete' => onboardingIncomplete,
    'verification_pending' => verificationPending,
    'restricted' => restricted,
    'ready' => ready,
    _ => throw const FormatException('Invalid Connect status.'),
  };
}

@immutable
final class StripeConnectSnapshot {
  final StripeConnectStatus status;
  final bool transfersReady;
  final bool payoutsReady;
  final int requirementsDue;
  final bool canOpenDashboard;
  final bool livemode;
  final DateTime? lastSyncedAt;

  const StripeConnectSnapshot({
    required this.status,
    required this.transfersReady,
    required this.payoutsReady,
    required this.requirementsDue,
    required this.canOpenDashboard,
    required this.livemode,
    this.lastSyncedAt,
  });

  factory StripeConnectSnapshot.fromJson(Map<String, Object?> json) {
    bool requiredBool(String key) {
      final value = json[key];
      if (value is! bool) throw const FormatException('Invalid boolean.');
      return value;
    }

    final due = json['requirementsDue'];
    if (due is! int || due < 0 || due > 1000) {
      throw const FormatException('Invalid requirements count.');
    }
    final syncedValue = json['lastSyncedAt'];
    final syncedAt = syncedValue == null
        ? null
        : syncedValue is String
        ? DateTime.tryParse(syncedValue)?.toUtc()
        : null;
    if (syncedValue != null && syncedAt == null) {
      throw const FormatException('Invalid sync date.');
    }
    final snapshot = StripeConnectSnapshot(
      status: StripeConnectStatus.parse(json['status']),
      transfersReady: requiredBool('transfersReady'),
      payoutsReady: requiredBool('payoutsReady'),
      requirementsDue: due,
      canOpenDashboard: requiredBool('canOpenDashboard'),
      livemode: requiredBool('livemode'),
      lastSyncedAt: syncedAt,
    );
    if (snapshot.status == StripeConnectStatus.ready &&
        (!snapshot.transfersReady || !snapshot.payoutsReady)) {
      throw const FormatException('Inconsistent Connect readiness.');
    }
    return snapshot;
  }
}

enum StripeConnectLinkKind { onboarding, dashboard }

@immutable
final class StripeConnectLink {
  final Uri url;
  final DateTime expiresAt;
  final StripeConnectLinkKind kind;

  StripeConnectLink({
    required this.url,
    required DateTime expiresAt,
    required this.kind,
  }) : expiresAt = expiresAt.toUtc() {
    if (!isAllowedUrl(url, kind: kind) ||
        this.expiresAt.isBefore(DateTime.utc(2020)) ||
        this.expiresAt.isAfter(DateTime.utc(2200))) {
      throw const FormatException('Invalid Connect link.');
    }
  }

  factory StripeConnectLink.fromJson(
    Map<String, Object?> json, {
    required StripeConnectLinkKind kind,
  }) {
    final rawUrl = json['url'];
    final rawExpiry = json['expiresAt'];
    if (rawUrl is! String ||
        rawUrl.length > 4096 ||
        rawExpiry is! String ||
        rawExpiry.length > 80) {
      throw const FormatException('Invalid Connect link.');
    }
    final url = Uri.tryParse(rawUrl);
    final expiry = DateTime.tryParse(rawExpiry)?.toUtc();
    if (url == null || expiry == null) {
      throw const FormatException('Invalid Connect link.');
    }
    return StripeConnectLink(url: url, expiresAt: expiry, kind: kind);
  }

  static bool isAllowedUrl(Uri url, {required StripeConnectLinkKind kind}) {
    // Accounts v2 onboarding links use accounts.stripe.com and can include an
    // opaque #alu_ fragment. Express Dashboard login links remain on the
    // separate connect.stripe.com host and are not expected to use fragments.
    final host = url.host.toLowerCase();
    final expectedHost = switch (kind) {
      StripeConnectLinkKind.onboarding => 'accounts.stripe.com',
      StripeConnectLinkKind.dashboard => 'connect.stripe.com',
    };
    final fragmentAllowed = kind == StripeConnectLinkKind.onboarding;
    return url.scheme == 'https' &&
        url.hasAuthority &&
        url.userInfo.isEmpty &&
        (fragmentAllowed || !url.hasFragment) &&
        !url.hasPort &&
        !_containsControlCharacters(url) &&
        host == expectedHost;
  }

  static bool _containsControlCharacters(Uri url) {
    final serialized = url.toString();
    if (_connectControlCharacterPattern.hasMatch(serialized)) return true;
    try {
      return _connectControlCharacterPattern.hasMatch(
        Uri.decodeFull(serialized),
      );
    } on Object {
      return true;
    }
  }
}

enum StripeConnectFailureCode {
  notConfigured,
  authorizationRequired,
  actionUnavailable,
  rateLimited,
  network,
  invalidResponse,
  launchFailed,
}

final class StripeConnectException implements Exception {
  final StripeConnectFailureCode code;
  final String publicMessage;
  final bool retryable;
  final int? statusCode;

  const StripeConnectException({
    required this.code,
    required this.publicMessage,
    this.retryable = false,
    this.statusCode,
  });

  const StripeConnectException.notConfigured()
    : this(
        code: StripeConnectFailureCode.notConfigured,
        publicMessage: 'Seller payouts are not configured for this build.',
      );

  const StripeConnectException.network()
    : this(
        code: StripeConnectFailureCode.network,
        publicMessage: 'Could not reach Stripe payout services. Try again.',
        retryable: true,
      );

  const StripeConnectException.invalidResponse()
    : this(
        code: StripeConnectFailureCode.invalidResponse,
        publicMessage: 'Drip received an invalid payout response. Try again.',
        retryable: true,
      );

  @override
  String toString() => publicMessage;
}
