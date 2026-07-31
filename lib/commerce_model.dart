import 'dart:math' as math;

import 'product_model.dart';

/// Financial values are persisted as integer cents. Product keeps a display
/// price for the existing catalog UI, but every order snapshots exact cents.
int toCents(num dollars) => (dollars * 100).round();
double fromCents(int cents) => cents / 100;
double money(num value) => fromCents(toCents(value));

class MarketplacePolicy {
  static const basicSellerFeeBps = 1000;
  static const proSellerFeeBps = 700;
  static const proMonthlyPriceCents = 999;
  static const boostDayPriceCents = 199;
  static const boostWeekPriceCents = 599;
  static const shippingPerSellerCents = 699;

  static const basicSellerFeeRate = .10;
  static const proSellerFeeRate = .07;
  static const proMonthlyPrice = 9.99;
  static const boostDayPrice = 1.99;
  static const boostWeekPrice = 5.99;
  static const shippingPerSeller = 6.99;

  static int _basisPoints(int cents, int basisPoints) =>
      (cents * basisPoints + 5000) ~/ 10000;

  static int sellerFeeCents(int salePriceCents, {required bool sellerIsPro}) =>
      math.max(
        100,
        _basisPoints(
          salePriceCents,
          sellerIsPro ? proSellerFeeBps : basicSellerFeeBps,
        ),
      );

  static int buyerProtectionCents(int subtotalCents) =>
      math.max(149, math.min(499, _basisPoints(subtotalCents, 400) + 99));

  static int processingEstimateCents(int buyerTotalCents) =>
      _basisPoints(buyerTotalCents, 290) + 30;

  static int lossReserveCents(int subtotalCents) =>
      _basisPoints(subtotalCents, 100);

  static double sellerFee(double salePrice, {required bool sellerIsPro}) =>
      fromCents(sellerFeeCents(toCents(salePrice), sellerIsPro: sellerIsPro));

  static double buyerProtection(double subtotal) =>
      fromCents(buyerProtectionCents(toCents(subtotal)));

  static double processingEstimate(double total) =>
      fromCents(processingEstimateCents(toCents(total)));

  static double lossReserve(double subtotal) =>
      fromCents(lossReserveCents(toCents(subtotal)));
}

enum ListingStatus { live, sold, paused }

enum OrderStatus { placed, shipped, delivered }

/// Payment state is deliberately separate from fulfillment state. A Stripe
/// redirect is never enough to move an order to [PaymentStatus.paid]; only the
/// server's webhook-confirmed order response can do that.
enum PaymentProvider { demo, stripe }

enum PaymentStatus {
  demo,
  pending,
  processing,
  paid,
  failed,
  expired,
  refunded,
  disputed,
}

enum BoostPlan { oneDay, sevenDays }

extension BoostPlanDetails on BoostPlan {
  String get label =>
      this == BoostPlan.oneDay ? '24-hour boost' : '7-day boost';
  int get priceCents => this == BoostPlan.oneDay
      ? MarketplacePolicy.boostDayPriceCents
      : MarketplacePolicy.boostWeekPriceCents;
  double get price => fromCents(priceCents);
  Duration get duration => this == BoostPlan.oneDay
      ? const Duration(days: 1)
      : const Duration(days: 7);
}

class SellerListing {
  final Product product;
  final ListingStatus status;
  final DateTime createdAt;
  final int views;
  final int saves;
  final DateTime? promotionEndsAt;
  final bool createdByUser;

  const SellerListing({
    required this.product,
    required this.status,
    required this.createdAt,
    this.views = 0,
    this.saves = 0,
    this.promotionEndsAt,
    this.createdByUser = false,
  });

  bool get isPromoted =>
      promotionEndsAt != null && promotionEndsAt!.isAfter(DateTime.now());

  SellerListing copyWith({
    ListingStatus? status,
    int? views,
    int? saves,
    DateTime? promotionEndsAt,
  }) => SellerListing(
    product: product,
    status: status ?? this.status,
    createdAt: createdAt,
    views: views ?? this.views,
    saves: saves ?? this.saves,
    promotionEndsAt: promotionEndsAt ?? this.promotionEndsAt,
    createdByUser: createdByUser,
  );

  Map<String, Object?> toJson() => {
    'product': product.toJson(),
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'views': views,
    'saves': saves,
    'promotionEndsAt': promotionEndsAt?.toIso8601String(),
    'createdByUser': createdByUser,
  };

  factory SellerListing.fromJson(Map<String, Object?> json) => SellerListing(
    product: Product.fromJson(
      Map<String, Object?>.from(json['product']! as Map),
    ),
    status: ListingStatus.values.byName(json['status']! as String),
    createdAt: DateTime.parse(json['createdAt']! as String),
    views: json['views'] as int? ?? 0,
    saves: json['saves'] as int? ?? 0,
    promotionEndsAt: json['promotionEndsAt'] == null
        ? null
        : DateTime.parse(json['promotionEndsAt']! as String),
    createdByUser: json['createdByUser'] as bool? ?? false,
  );
}

class MarketplaceOrder {
  final String id;
  final String productId;
  final String productName;
  final String sellerHandle;
  final int salePriceCents;
  final int sellerFeeCents;
  final int sellerPayoutCents;
  final OrderStatus status;
  final DateTime createdAt;
  final PaymentProvider paymentProvider;
  final PaymentStatus paymentStatus;
  final String currency;
  final String? stripeCheckoutSessionId;
  final String? stripePaymentIntentId;

  const MarketplaceOrder({
    required this.id,
    required this.productId,
    required this.productName,
    required this.sellerHandle,
    required this.salePriceCents,
    required this.sellerFeeCents,
    required this.sellerPayoutCents,
    required this.status,
    required this.createdAt,
    this.paymentProvider = PaymentProvider.demo,
    this.paymentStatus = PaymentStatus.demo,
    this.currency = 'usd',
    this.stripeCheckoutSessionId,
    this.stripePaymentIntentId,
  });

  double get salePrice => fromCents(salePriceCents);
  double get sellerFee => fromCents(sellerFeeCents);
  double get sellerPayout => fromCents(sellerPayoutCents);
  @Deprecated('Use paymentProvider instead.')
  bool get demoPayment => paymentProvider == PaymentProvider.demo;

  MarketplaceOrder copyWith({
    OrderStatus? status,
    PaymentStatus? paymentStatus,
  }) => MarketplaceOrder(
    id: id,
    productId: productId,
    productName: productName,
    sellerHandle: sellerHandle,
    salePriceCents: salePriceCents,
    sellerFeeCents: sellerFeeCents,
    sellerPayoutCents: sellerPayoutCents,
    status: status ?? this.status,
    createdAt: createdAt,
    paymentProvider: paymentProvider,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    currency: currency,
    stripeCheckoutSessionId: stripeCheckoutSessionId,
    stripePaymentIntentId: stripePaymentIntentId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'productId': productId,
    'productName': productName,
    'sellerHandle': sellerHandle,
    'salePriceCents': salePriceCents,
    'sellerFeeCents': sellerFeeCents,
    'sellerPayoutCents': sellerPayoutCents,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'paymentProvider': paymentProvider.name,
    'paymentStatus': paymentStatus.name,
    'currency': currency,
    'stripeCheckoutSessionId': stripeCheckoutSessionId,
    'stripePaymentIntentId': stripePaymentIntentId,
  };

  factory MarketplaceOrder.fromJson(Map<String, Object?> json) {
    int cents(String centsKey, String legacyKey) => json[centsKey] is num
        ? (json[centsKey]! as num).round()
        : toCents((json[legacyKey] as num?) ?? 0);

    final providerName = json['paymentProvider'] as String?;
    final provider = providerName == null
        ? ((json['demoPayment'] as bool? ?? true)
              ? PaymentProvider.demo
              : PaymentProvider.stripe)
        : PaymentProvider.values.byName(providerName);
    final paymentStatusName = json['paymentStatus'] as String?;

    return MarketplaceOrder(
      id: json['id']! as String,
      productId: json['productId']! as String,
      productName: json['productName']! as String,
      sellerHandle: json['sellerHandle']! as String,
      salePriceCents: cents('salePriceCents', 'salePrice'),
      sellerFeeCents: cents('sellerFeeCents', 'sellerFee'),
      sellerPayoutCents: cents('sellerPayoutCents', 'sellerPayout'),
      status: OrderStatus.values.byName(json['status']! as String),
      createdAt: DateTime.parse(json['createdAt']! as String),
      paymentProvider: provider,
      paymentStatus: paymentStatusName == null
          ? (provider == PaymentProvider.demo
                ? PaymentStatus.demo
                : PaymentStatus.paid)
          : PaymentStatus.values.byName(paymentStatusName),
      currency: (json['currency'] as String? ?? 'usd').toLowerCase(),
      stripeCheckoutSessionId: json['stripeCheckoutSessionId'] as String?,
      stripePaymentIntentId: json['stripePaymentIntentId'] as String?,
    );
  }
}

class CheckoutReceipt {
  final String id;
  final int subtotalCents;
  final int buyerProtectionCents;
  final int shippingCents;
  final int totalCents;
  final int platformRevenueCents;
  final int contributionEstimateCents;
  final DateTime createdAt;
  final PaymentProvider paymentProvider;
  final PaymentStatus paymentStatus;
  final String currency;
  final int taxCents;
  final String? stripeCheckoutSessionId;
  final String? stripePaymentIntentId;

  const CheckoutReceipt({
    required this.id,
    required this.subtotalCents,
    required this.buyerProtectionCents,
    required this.shippingCents,
    required this.totalCents,
    required this.platformRevenueCents,
    required this.contributionEstimateCents,
    required this.createdAt,
    this.paymentProvider = PaymentProvider.demo,
    this.paymentStatus = PaymentStatus.demo,
    this.currency = 'usd',
    this.taxCents = 0,
    this.stripeCheckoutSessionId,
    this.stripePaymentIntentId,
  });

  double get subtotal => fromCents(subtotalCents);
  double get buyerProtection => fromCents(buyerProtectionCents);
  double get shipping => fromCents(shippingCents);
  double get total => fromCents(totalCents);
  double get platformRevenue => fromCents(platformRevenueCents);
  double get contributionEstimate => fromCents(contributionEstimateCents);
  double get tax => fromCents(taxCents);

  Map<String, Object?> toJson() => {
    'id': id,
    'subtotalCents': subtotalCents,
    'buyerProtectionCents': buyerProtectionCents,
    'shippingCents': shippingCents,
    'totalCents': totalCents,
    'platformRevenueCents': platformRevenueCents,
    'contributionEstimateCents': contributionEstimateCents,
    'createdAt': createdAt.toIso8601String(),
    'paymentProvider': paymentProvider.name,
    'paymentStatus': paymentStatus.name,
    'currency': currency,
    'taxCents': taxCents,
    'stripeCheckoutSessionId': stripeCheckoutSessionId,
    'stripePaymentIntentId': stripePaymentIntentId,
  };

  factory CheckoutReceipt.fromJson(Map<String, Object?> json) =>
      CheckoutReceipt(
        id: json['id']! as String,
        subtotalCents: json['subtotalCents']! as int,
        buyerProtectionCents: json['buyerProtectionCents']! as int,
        shippingCents: json['shippingCents']! as int,
        totalCents: json['totalCents']! as int,
        platformRevenueCents: json['platformRevenueCents']! as int,
        contributionEstimateCents: json['contributionEstimateCents']! as int,
        createdAt: DateTime.parse(json['createdAt']! as String),
        paymentProvider: json['paymentProvider'] == null
            ? PaymentProvider.demo
            : PaymentProvider.values.byName(json['paymentProvider']! as String),
        paymentStatus: json['paymentStatus'] == null
            ? PaymentStatus.demo
            : PaymentStatus.values.byName(json['paymentStatus']! as String),
        currency: (json['currency'] as String? ?? 'usd').toLowerCase(),
        taxCents: (json['taxCents'] as num?)?.toInt() ?? 0,
        stripeCheckoutSessionId: json['stripeCheckoutSessionId'] as String?,
        stripePaymentIntentId: json['stripePaymentIntentId'] as String?,
      );
}
