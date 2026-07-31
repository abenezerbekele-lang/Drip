import 'checkout_exception.dart';

final RegExp _opaqueIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');
final RegExp _currencyPattern = RegExp(r'^[a-zA-Z]{3}$');
final RegExp _controlCharacterPattern = RegExp(r'[\x00-\x1F\x7F\u0080-\u009F]');

const _stripeCheckoutHost = 'checkout.stripe.com';
const _maximumCheckoutItems = 20;

String _validatedId(String value, String label) {
  final normalized = value.trim();
  if (!_opaqueIdPattern.hasMatch(normalized)) {
    throw CheckoutValidationException('$label is not valid.');
  }
  return normalized;
}

String _validatedSize(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > 40 ||
      _controlCharacterPattern.hasMatch(normalized)) {
    throw const CheckoutValidationException('The selected size is not valid.');
  }
  return normalized;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) throw const FormatException();
  return value.trim();
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) throw const FormatException();
  return value.trim();
}

int _requiredCents(Map<String, Object?> json, String key) {
  final value = json[key];
  final parsed = switch (value) {
    int amount => amount,
    num amount when amount.isFinite && amount == amount.roundToDouble() =>
      amount.toInt(),
    _ => throw const FormatException(),
  };
  if (parsed < 0 || parsed > 1000000000) throw const FormatException();
  return parsed;
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final parsed = DateTime.tryParse(_requiredString(json, key));
  if (parsed == null) throw const FormatException();
  return parsed.toUtc();
}

DateTime? _optionalDate(Map<String, Object?> json, String key) {
  final value = _optionalString(json, key);
  if (value == null) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException();
  return parsed.toUtc();
}

Map<String, Object?> _requiredMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) throw const FormatException();
  return Map<String, Object?>.from(value);
}

List<Object?> _requiredList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) throw const FormatException();
  return value;
}

/// Returns true only for a Stripe-hosted Checkout URL.
///
/// Stripe currently returns `checkout.stripe.com`. Descendants of that exact
/// registrable boundary are also accepted so Stripe can use a controlled
/// regional host without allowing lookalikes such as
/// `checkout.stripe.com.example.com`. Stripe's hosted URL can carry an opaque
/// `#fid...` fragment, so fragments are preserved only after the exact Stripe
/// host and the full decoded URL pass the safety checks below.
bool isAllowedCheckoutUrl(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      _uriContainsControlCharacters(uri)) {
    return false;
  }
  final host = uri.host.toLowerCase();
  return host == _stripeCheckoutHost || host.endsWith('.$_stripeCheckoutHost');
}

bool _uriContainsControlCharacters(Uri uri) {
  final serialized = uri.toString();
  if (_controlCharacterPattern.hasMatch(serialized)) return true;
  try {
    return _controlCharacterPattern.hasMatch(Uri.decodeFull(serialized));
  } on Object {
    return true;
  }
}

/// A one-of-one marketplace item requested for checkout.
///
/// Price, seller fee, shipping, tax, and payout are intentionally absent. The
/// server derives every monetary value from its authoritative listing record.
final class CheckoutLine {
  final String listingId;
  final String selectedSize;

  CheckoutLine({required String listingId, required String selectedSize})
    : listingId = _validatedId(listingId, 'Listing'),
      selectedSize = _validatedSize(selectedSize);

  factory CheckoutLine.fromJson(Map<String, Object?> json) => CheckoutLine(
    listingId: _requiredString(json, 'listingId'),
    selectedSize: _requiredString(json, 'selectedSize'),
  );

  Map<String, Object?> toJson() => {
    'listingId': listingId,
    'selectedSize': selectedSize,
  };

  @override
  bool operator ==(Object other) =>
      other is CheckoutLine &&
      other.listingId == listingId &&
      other.selectedSize == selectedSize;

  @override
  int get hashCode => Object.hash(listingId, selectedSize);
}

/// The complete client payload for creating a Checkout Session.
final class CheckoutRequest {
  final String attemptId;
  final List<CheckoutLine> lines;

  CheckoutRequest({
    required String attemptId,
    required Iterable<CheckoutLine> lines,
  }) : attemptId = _validatedId(attemptId, 'Checkout attempt'),
       lines = List.unmodifiable(lines) {
    if (this.lines.isEmpty || this.lines.length > _maximumCheckoutItems) {
      throw const CheckoutValidationException(
        'Checkout must contain between 1 and 20 items.',
      );
    }
    final uniqueIds = this.lines.map((line) => line.listingId).toSet();
    if (uniqueIds.length != this.lines.length) {
      throw const CheckoutValidationException(
        'A one-of-one listing can only appear once.',
      );
    }
  }

  factory CheckoutRequest.fromJson(Map<String, Object?> json) =>
      CheckoutRequest(
        attemptId: _requiredString(json, 'attemptId'),
        lines: _requiredList(json, 'items').map((value) {
          if (value is! Map) throw const FormatException();
          return CheckoutLine.fromJson(Map<String, Object?>.from(value));
        }),
      );

  Map<String, Object?> toJson() => {
    'attemptId': attemptId,
    'items': lines.map((line) => line.toJson()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      other is CheckoutRequest &&
      other.attemptId == attemptId &&
      _listEquals(other.lines, lines);

  @override
  int get hashCode => Object.hash(attemptId, Object.hashAll(lines));
}

enum CheckoutPaymentStatus {
  creating,
  open,
  processing,
  paymentReview,
  paid,
  expired,
  canceled,
  failed,
  refunded,
  unknown;

  bool get isTerminal => switch (this) {
    paid || expired || canceled || failed || refunded => true,
    creating || open || processing || paymentReview || unknown => false,
  };

  bool get isPaid => this == paid;

  static CheckoutPaymentStatus parse(Object? value) {
    if (value is! String) throw const FormatException();
    return switch (value.trim().toLowerCase()) {
      'creating' => creating,
      'open' || 'pending' || 'created' || 'requires_payment' => open,
      'processing' || 'payment_processing' => processing,
      'payment_review' || 'review' => paymentReview,
      'paid' || 'complete' || 'completed' || 'succeeded' => paid,
      'expired' => expired,
      'canceled' || 'cancelled' => canceled,
      'failed' || 'payment_failed' => failed,
      'refunded' => refunded,
      _ => unknown,
    };
  }

  String get wireValue => switch (this) {
    paymentReview => 'payment_review',
    unknown => 'unknown',
    _ => name,
  };
}

/// Exact quote calculated by the server. The client never submits these values.
final class CheckoutQuote {
  final String currency;
  final int subtotalCents;
  final int protectionCents;
  final int shippingCents;
  final int taxCents;
  final int totalCents;

  CheckoutQuote({
    required String currency,
    required this.subtotalCents,
    required this.protectionCents,
    required this.shippingCents,
    required this.taxCents,
    required this.totalCents,
  }) : currency = currency.trim().toLowerCase() {
    final components =
        subtotalCents + protectionCents + shippingCents + taxCents;
    if (!_currencyPattern.hasMatch(this.currency) ||
        subtotalCents < 0 ||
        protectionCents < 0 ||
        shippingCents < 0 ||
        taxCents < 0 ||
        totalCents < 0 ||
        components != totalCents) {
      throw const CheckoutValidationException(
        'The checkout quote is not valid.',
      );
    }
  }

  factory CheckoutQuote.fromJson(Map<String, Object?> json) {
    final subtotal = json.containsKey('merchandiseSubtotalCents')
        ? _requiredCents(json, 'merchandiseSubtotalCents')
        : _requiredCents(json, 'subtotalCents');
    final protection = json.containsKey('protectionCents')
        ? _requiredCents(json, 'protectionCents')
        : _requiredCents(json, 'buyerProtectionCents');
    final shipping = _requiredCents(json, 'shippingCents');
    final total = _requiredCents(json, 'totalCents');
    final tax = json.containsKey('taxCents')
        ? _requiredCents(json, 'taxCents')
        : total - subtotal - protection - shipping;
    return CheckoutQuote(
      currency: _requiredString(json, 'currency'),
      subtotalCents: subtotal,
      protectionCents: protection,
      shippingCents: shipping,
      taxCents: tax,
      totalCents: total,
    );
  }

  Map<String, Object?> toJson() => {
    'currency': currency,
    'merchandiseSubtotalCents': subtotalCents,
    'buyerProtectionCents': protectionCents,
    'shippingCents': shippingCents,
    'taxCents': taxCents,
    'totalCents': totalCents,
  };

  @override
  bool operator ==(Object other) =>
      other is CheckoutQuote &&
      other.currency == currency &&
      other.subtotalCents == subtotalCents &&
      other.protectionCents == protectionCents &&
      other.shippingCents == shippingCents &&
      other.taxCents == taxCents &&
      other.totalCents == totalCents;

  @override
  int get hashCode => Object.hash(
    currency,
    subtotalCents,
    protectionCents,
    shippingCents,
    taxCents,
    totalCents,
  );
}

Map<String, Object?> _quoteJsonFromEnvelope(Map<String, Object?> json) {
  final quote = json['quote'];
  if (quote == null) return json;
  if (quote is! Map) throw const FormatException();
  return Map<String, Object?>.from(quote);
}

String _sessionIdFromJson(Map<String, Object?> json) {
  final value = json['checkoutSessionId'] ?? json['sessionId'];
  if (value is! String || value.trim().isEmpty) throw const FormatException();
  return value.trim();
}

List<String> _listingIdsFromJson(Map<String, Object?> json) {
  final direct = json['purchasedListingIds'] ?? json['listingIds'];
  if (direct is List) {
    return direct
        .map((value) => value is String ? value : throw const FormatException())
        .toList(growable: false);
  }
  final items = json['items'];
  if (items is! List) throw const FormatException();
  return items
      .map((value) {
        if (value is String) return value;
        if (value is Map) {
          return _requiredString(Map<String, Object?>.from(value), 'listingId');
        }
        throw const FormatException();
      })
      .toList(growable: false);
}

/// A server-created Stripe-hosted Checkout Session.
final class CheckoutSession {
  final String orderId;
  final String checkoutSessionId;
  final Uri checkoutUrl;
  final DateTime expiresAt;
  final CheckoutQuote quote;
  final CheckoutPaymentStatus status;

  CheckoutSession({
    required String orderId,
    required String checkoutSessionId,
    required Uri checkoutUrl,
    required DateTime expiresAt,
    required this.quote,
    this.status = CheckoutPaymentStatus.open,
  }) : orderId = _validatedId(orderId, 'Order'),
       checkoutSessionId = _validatedId(checkoutSessionId, 'Checkout session'),
       checkoutUrl = checkoutUrl,
       expiresAt = expiresAt.toUtc() {
    if (!isAllowedCheckoutUrl(checkoutUrl)) {
      throw const CheckoutValidationException(
        'The secure checkout link is not valid.',
      );
    }
  }

  factory CheckoutSession.fromJson(Map<String, Object?> json) {
    final rawUrl = json['checkoutUrl'] ?? json['url'];
    if (rawUrl is! String) throw const FormatException();
    final url = Uri.tryParse(rawUrl);
    if (url == null || !isAllowedCheckoutUrl(url)) {
      throw const FormatException();
    }
    return CheckoutSession(
      orderId: _requiredString(json, 'orderId'),
      checkoutSessionId: _sessionIdFromJson(json),
      checkoutUrl: url,
      expiresAt: _requiredDate(json, 'expiresAt'),
      quote: CheckoutQuote.fromJson(_quoteJsonFromEnvelope(json)),
      status: json['status'] == null
          ? CheckoutPaymentStatus.open
          : CheckoutPaymentStatus.parse(json['status']),
    );
  }

  String get sessionId => checkoutSessionId;

  Map<String, Object?> toJson() => {
    'orderId': orderId,
    'checkoutSessionId': checkoutSessionId,
    'checkoutUrl': checkoutUrl.toString(),
    'expiresAt': expiresAt.toIso8601String(),
    'quote': quote.toJson(),
    'status': status.wireValue,
  };

  @override
  bool operator ==(Object other) =>
      other is CheckoutSession &&
      other.orderId == orderId &&
      other.checkoutSessionId == checkoutSessionId &&
      other.checkoutUrl == checkoutUrl &&
      other.expiresAt == expiresAt &&
      other.quote == quote &&
      other.status == status;

  @override
  int get hashCode => Object.hash(
    orderId,
    checkoutSessionId,
    checkoutUrl,
    expiresAt,
    quote,
    status,
  );
}

/// Exact, server-authoritative money and inventory confirmation.
final class CheckoutConfirmation {
  final String orderId;
  final String checkoutSessionId;
  final String? paymentIntentId;
  final CheckoutQuote quote;
  final List<String> purchasedListingIds;
  final DateTime? confirmedAt;

  CheckoutConfirmation({
    required String orderId,
    required String checkoutSessionId,
    String? paymentIntentId,
    required this.quote,
    required Iterable<String> purchasedListingIds,
    DateTime? confirmedAt,
  }) : orderId = _validatedId(orderId, 'Order'),
       checkoutSessionId = _validatedId(checkoutSessionId, 'Checkout session'),
       paymentIntentId = paymentIntentId == null
           ? null
           : _validatedId(paymentIntentId, 'Payment'),
       purchasedListingIds = List.unmodifiable(
         purchasedListingIds.map((id) => _validatedId(id, 'Listing')),
       ),
       confirmedAt = confirmedAt?.toUtc() {
    if (this.purchasedListingIds.isEmpty ||
        this.purchasedListingIds.toSet().length !=
            this.purchasedListingIds.length) {
      throw const CheckoutValidationException(
        'The checkout confirmation is not valid.',
      );
    }
  }

  factory CheckoutConfirmation.fromJson(Map<String, Object?> json) =>
      CheckoutConfirmation(
        orderId: _requiredString(json, 'orderId'),
        checkoutSessionId: _sessionIdFromJson(json),
        paymentIntentId: _optionalString(json, 'paymentIntentId'),
        quote: CheckoutQuote.fromJson(_quoteJsonFromEnvelope(json)),
        purchasedListingIds: _listingIdsFromJson(json),
        confirmedAt:
            _optionalDate(json, 'confirmedAt') ?? _optionalDate(json, 'paidAt'),
      );

  String get receiptId => orderId;
  String get currency => quote.currency;
  int get subtotalCents => quote.subtotalCents;
  int get buyerProtectionCents => quote.protectionCents;
  int get shippingCents => quote.shippingCents;
  int get taxCents => quote.taxCents;
  int get totalCents => quote.totalCents;

  Map<String, Object?> toJson() => {
    'orderId': orderId,
    'checkoutSessionId': checkoutSessionId,
    if (paymentIntentId != null) 'paymentIntentId': paymentIntentId,
    'quote': quote.toJson(),
    'purchasedListingIds': purchasedListingIds,
    if (confirmedAt != null) 'confirmedAt': confirmedAt!.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is CheckoutConfirmation &&
      other.orderId == orderId &&
      other.checkoutSessionId == checkoutSessionId &&
      other.paymentIntentId == paymentIntentId &&
      other.quote == quote &&
      _listEquals(other.purchasedListingIds, purchasedListingIds) &&
      other.confirmedAt == confirmedAt;

  @override
  int get hashCode => Object.hash(
    orderId,
    checkoutSessionId,
    paymentIntentId,
    quote,
    Object.hashAll(purchasedListingIds),
    confirmedAt,
  );
}

/// Current server view of a checkout. Unknown future states remain non-paid.
final class CheckoutStatusSnapshot {
  final String orderId;
  final String checkoutSessionId;
  final CheckoutPaymentStatus status;
  final DateTime? expiresAt;
  final CheckoutQuote? quote;
  final List<String> listingIds;
  final String? paymentIntentId;
  final CheckoutConfirmation? confirmation;

  CheckoutStatusSnapshot({
    required String orderId,
    required String checkoutSessionId,
    required this.status,
    DateTime? expiresAt,
    this.quote,
    Iterable<String> listingIds = const [],
    String? paymentIntentId,
    this.confirmation,
  }) : orderId = _validatedId(orderId, 'Order'),
       checkoutSessionId = _validatedId(checkoutSessionId, 'Checkout session'),
       expiresAt = expiresAt?.toUtc(),
       listingIds = List.unmodifiable(
         listingIds.map((id) => _validatedId(id, 'Listing')),
       ),
       paymentIntentId = paymentIntentId == null
           ? null
           : _validatedId(paymentIntentId, 'Payment') {
    if (confirmation != null &&
        (confirmation!.orderId != this.orderId ||
            confirmation!.checkoutSessionId != this.checkoutSessionId)) {
      throw const CheckoutValidationException(
        'The checkout confirmation does not match.',
      );
    }
    if (status == CheckoutPaymentStatus.paid && confirmation == null) {
      throw const CheckoutValidationException(
        'Paid checkout is missing its confirmation.',
      );
    }
  }

  factory CheckoutStatusSnapshot.fromJson(Map<String, Object?> json) {
    final status = CheckoutPaymentStatus.parse(json['status']);
    final nested = json['confirmation'] ?? json['receipt'];
    CheckoutConfirmation? confirmation;
    if (nested != null) {
      if (nested is! Map) throw const FormatException();
      confirmation = CheckoutConfirmation.fromJson(
        Map<String, Object?>.from(nested),
      );
    } else if (status == CheckoutPaymentStatus.paid) {
      confirmation = CheckoutConfirmation.fromJson(json);
    }
    CheckoutQuote? quote;
    if (json['quote'] != null || json['totalCents'] != null) {
      quote = CheckoutQuote.fromJson(_quoteJsonFromEnvelope(json));
    }
    List<String> listingIds = const [];
    if (json['items'] != null ||
        json['listingIds'] != null ||
        json['purchasedListingIds'] != null) {
      listingIds = _listingIdsFromJson(json);
    }
    return CheckoutStatusSnapshot(
      orderId: _requiredString(json, 'orderId'),
      checkoutSessionId: _sessionIdFromJson(json),
      status: status,
      expiresAt: _optionalDate(json, 'expiresAt'),
      quote: quote ?? confirmation?.quote,
      listingIds: listingIds.isEmpty
          ? confirmation?.purchasedListingIds ?? const []
          : listingIds,
      paymentIntentId:
          _optionalString(json, 'paymentIntentId') ??
          confirmation?.paymentIntentId,
      confirmation: confirmation,
    );
  }

  String get sessionId => checkoutSessionId;

  Map<String, Object?> toJson() => {
    'orderId': orderId,
    'checkoutSessionId': checkoutSessionId,
    'status': status.wireValue,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    if (quote != null) 'quote': quote!.toJson(),
    if (listingIds.isNotEmpty) 'listingIds': listingIds,
    if (paymentIntentId != null) 'paymentIntentId': paymentIntentId,
    if (confirmation != null) 'confirmation': confirmation!.toJson(),
  };

  bool get isPaid => status.isPaid && confirmation != null;

  @override
  bool operator ==(Object other) =>
      other is CheckoutStatusSnapshot &&
      other.orderId == orderId &&
      other.checkoutSessionId == checkoutSessionId &&
      other.status == status &&
      other.expiresAt == expiresAt &&
      other.quote == quote &&
      _listEquals(other.listingIds, listingIds) &&
      other.paymentIntentId == paymentIntentId &&
      other.confirmation == confirmation;

  @override
  int get hashCode => Object.hash(
    orderId,
    checkoutSessionId,
    status,
    expiresAt,
    quote,
    Object.hashAll(listingIds),
    paymentIntentId,
    confirmation,
  );
}

/// Minimal resumable state saved before handing the buyer to Stripe.
final class PendingCheckout {
  final String attemptId;
  final String orderId;
  final String checkoutSessionId;
  final Uri checkoutUrl;
  final CheckoutQuote quote;
  final List<CheckoutLine> lines;
  final DateTime createdAt;
  final DateTime expiresAt;

  PendingCheckout({
    required String attemptId,
    required String orderId,
    required String checkoutSessionId,
    required Uri checkoutUrl,
    required this.quote,
    required Iterable<CheckoutLine> lines,
    required DateTime createdAt,
    required DateTime expiresAt,
  }) : attemptId = _validatedId(attemptId, 'Checkout attempt'),
       orderId = _validatedId(orderId, 'Order'),
       checkoutSessionId = _validatedId(checkoutSessionId, 'Checkout session'),
       checkoutUrl = checkoutUrl,
       lines = List.unmodifiable(lines),
       createdAt = createdAt.toUtc(),
       expiresAt = expiresAt.toUtc() {
    if (!isAllowedCheckoutUrl(checkoutUrl) || this.lines.isEmpty) {
      throw const CheckoutValidationException(
        'The pending checkout is not valid.',
      );
    }
  }

  factory PendingCheckout.fromSession({
    required CheckoutRequest request,
    required CheckoutSession session,
    required DateTime createdAt,
  }) => PendingCheckout(
    attemptId: request.attemptId,
    orderId: session.orderId,
    checkoutSessionId: session.checkoutSessionId,
    checkoutUrl: session.checkoutUrl,
    quote: session.quote,
    lines: request.lines,
    createdAt: createdAt,
    expiresAt: session.expiresAt,
  );

  factory PendingCheckout.fromJson(Map<String, Object?> json) =>
      PendingCheckout(
        attemptId: _requiredString(json, 'attemptId'),
        orderId: _requiredString(json, 'orderId'),
        checkoutSessionId: _sessionIdFromJson(json),
        checkoutUrl: Uri.parse(_requiredString(json, 'checkoutUrl')),
        quote: CheckoutQuote.fromJson(_requiredMap(json, 'quote')),
        lines: _requiredList(json, 'items').map((value) {
          if (value is! Map) throw const FormatException();
          return CheckoutLine.fromJson(Map<String, Object?>.from(value));
        }),
        createdAt: _requiredDate(json, 'createdAt'),
        expiresAt: _requiredDate(json, 'expiresAt'),
      );

  String get sessionId => checkoutSessionId;

  Map<String, Object?> toJson() => {
    'attemptId': attemptId,
    'orderId': orderId,
    'checkoutSessionId': checkoutSessionId,
    'checkoutUrl': checkoutUrl.toString(),
    'quote': quote.toJson(),
    'items': lines.map((line) => line.toJson()).toList(growable: false),
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());

  @override
  bool operator ==(Object other) =>
      other is PendingCheckout &&
      other.attemptId == attemptId &&
      other.orderId == orderId &&
      other.checkoutSessionId == checkoutSessionId &&
      other.checkoutUrl == checkoutUrl &&
      other.quote == quote &&
      _listEquals(other.lines, lines) &&
      other.createdAt == createdAt &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(
    attemptId,
    orderId,
    checkoutSessionId,
    checkoutUrl,
    quote,
    Object.hashAll(lines),
    createdAt,
    expiresAt,
  );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
