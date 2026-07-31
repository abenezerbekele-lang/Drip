import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'commerce_model.dart';
import 'payments/payments.dart';
import 'product_model.dart';
import 'sample_data.dart';

class CartItem {
  final Product product;
  final String size;
  final int quantity;

  const CartItem({
    required this.product,
    required this.size,
    this.quantity = 1,
  });

  double get total => product.price;
  int get totalCents => toCents(product.price);

  CartItem copyWith({int? quantity}) =>
      CartItem(product: product, size: size, quantity: 1);

  Map<String, Object?> toJson() => {
    'product': product.toJson(),
    'size': size,
    'quantity': 1,
  };

  factory CartItem.fromJson(Map<String, Object?> json) => CartItem(
    product: Product.fromJson(
      Map<String, Object?>.from(json['product']! as Map),
    ),
    size: json['size'] as String? ?? 'One size',
  );
}

enum StripeCheckoutConnectionState {
  notConfigured,
  checking,
  ready,
  serverSetupRequired,
  unavailable,
}

/// Marketplace facade for buyer and seller screens.
///
/// Stripe payment and inventory authority lives on the checkout server. This
/// class persists only a resumable handoff and a post-confirmation local cache;
/// it never stores provider secrets or raw payment credentials. Seller growth
/// controls remain an explicitly labeled on-device demo until their repository
/// is moved server-side too.
class AppState extends ChangeNotifier {
  static const currentSellerHandle = '@alexwears';
  static const currentSellerName = 'Alex Morgan';
  static const _legacySnapshotKey = 'drip.marketplace.v2';

  final SharedPreferences? _preferences;
  final CheckoutGateway? _checkoutGateway;
  final String storageNamespace;
  final String activeSellerHandle;
  final String activeSellerName;
  final bool demoSellerMode;
  late final String _snapshotKey;
  final Set<String> _favoriteIds = {};
  final List<CartItem> _cart = [];
  final List<SellerListing> _sellerListings = [];
  final List<MarketplaceOrder> _orders = [];
  final List<CheckoutReceipt> _receipts = [];

  int _lifetimeSpendCents = 0;
  int _payoutsRequestedCents = 0;
  int _boostRevenueCents = 0;
  int _subscriptionRevenueCents = 0;
  int _boostCredits = 0;
  bool _sellerPro = false;
  bool _checkoutInProgress = false;
  bool _disposed = false;
  String? _commerceError;
  PendingCheckout? _pendingCheckout;
  CheckoutPaymentStatus? _checkoutPaymentStatus;
  String? _checkoutAttemptId;
  StripeCheckoutConnectionState _stripeCheckoutConnection =
      StripeCheckoutConnectionState.notConfigured;
  Future<void>? _checkoutReadinessRequest;

  // Kept as `preferences` at the public boundary for readable test/app setup.
  AppState({
    SharedPreferences? preferences,
    CheckoutGateway? checkoutGateway,
    this.storageNamespace = 'demo',
    String? sellerHandle,
    String? sellerName,
    this.demoSellerMode = true,
  })
    // ignore: prefer_initializing_formals
    : _preferences = preferences,
       activeSellerHandle = sellerHandle ?? currentSellerHandle,
       activeSellerName = sellerName ?? currentSellerName,
       _checkoutGateway =
           checkoutGateway ??
           (HttpCheckoutGateway.isEnvironmentConfigured
               ? HttpCheckoutGateway.fromEnvironment()
               : null) {
    final normalizedNamespace = storageNamespace.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final safeNamespace = normalizedNamespace.length <= 120
        ? normalizedNamespace
        : normalizedNamespace.substring(0, 120);
    _snapshotKey =
        'drip.marketplace.v3.${safeNamespace.isEmpty ? 'demo' : safeNamespace}';
    if (!_restoreSnapshot()) {
      _seedMarketplace();
      if (storageNamespace == 'demo') _restoreLegacyBuyerState();
    } else {
      _ensureCatalogInventory();
    }
    if (_checkoutGateway == null) {
      _stripeCheckoutConnection = StripeCheckoutConnectionState.notConfigured;
    } else if (_checkoutGateway is CheckoutReadinessGateway) {
      _stripeCheckoutConnection = StripeCheckoutConnectionState.checking;
      unawaited(refreshStripeCheckoutConnection());
    } else {
      // Injected gateways used by native integrations and tests are already a
      // deliberate, trusted configuration boundary.
      _stripeCheckoutConnection = StripeCheckoutConnectionState.ready;
    }
  }

  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);
  List<CartItem> get cart => List.unmodifiable(_cart);
  List<SellerListing> get sellerListings => List.unmodifiable(
    _sellerListings.where(
      (listing) => listing.product.sellerHandle == activeSellerHandle,
    ),
  );
  List<MarketplaceOrder> get orders => List.unmodifiable(_orders);
  List<MarketplaceOrder> get sellerOrders => List.unmodifiable(
    _orders.where((order) => order.sellerHandle == activeSellerHandle),
  );
  List<CheckoutReceipt> get receipts => List.unmodifiable(_receipts);

  List<Product> get catalogProducts {
    final marketplaceIds = _sellerListings
        .map((listing) => listing.product.id)
        .toSet();
    final live =
        _sellerListings
            .where(
              (listing) =>
                  listing.status == ListingStatus.live && !listing.isPromoted,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final promoted =
        _sellerListings
            .where(
              (listing) =>
                  listing.status == ListingStatus.live && listing.isPromoted,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final organic = <Product>[
      ...live.map((listing) => listing.product),
      ...products.where((product) => !marketplaceIds.contains(product.id)),
    ];
    final result = <Product>[];
    var promotedIndex = 0;
    for (var index = 0; index < organic.length; index++) {
      if (index % 7 == 0 && promotedIndex < promoted.length) {
        result.add(promoted[promotedIndex++].product);
      }
      result.add(organic[index]);
    }
    while (promotedIndex < promoted.length) {
      result.add(promoted[promotedIndex++].product);
    }
    return List.unmodifiable(result);
  }

  int get cartCount => _cart.length;
  int get cartSubtotalCents =>
      _cart.fold(0, (total, item) => total + item.totalCents);
  double get cartSubtotal => fromCents(cartSubtotalCents);
  int get cartShipmentCount =>
      _cart.map((item) => item.product.sellerHandle).toSet().length;
  int get cartShippingCents => _cart.isEmpty
      ? 0
      : cartShipmentCount * MarketplacePolicy.shippingPerSellerCents;
  double get cartShipping => fromCents(cartShippingCents);
  int get cartBuyerProtectionCents => _cart.isEmpty
      ? 0
      : MarketplacePolicy.buyerProtectionCents(cartSubtotalCents);
  double get cartBuyerProtection => fromCents(cartBuyerProtectionCents);
  int get cartTotalCents =>
      cartSubtotalCents + cartBuyerProtectionCents + cartShippingCents;
  double get cartTotal => fromCents(cartTotalCents);
  double get lifetimeSpend => fromCents(_lifetimeSpendCents);
  bool get checkoutInProgress => _checkoutInProgress;
  String? get commerceError => _commerceError;
  CheckoutReceipt? get lastReceipt => _receipts.isEmpty ? null : _receipts.last;
  PendingCheckout? get pendingCheckout => _pendingCheckout;
  CheckoutPaymentStatus? get checkoutPaymentStatus => _checkoutPaymentStatus;
  bool get cartLockedForCheckout =>
      _pendingCheckout != null || _checkoutAttemptId != null;
  bool get stripeCheckoutConfigured =>
      _stripeCheckoutConnection == StripeCheckoutConnectionState.ready;
  StripeCheckoutConnectionState get stripeCheckoutConnection =>
      _stripeCheckoutConnection;

  bool get sellerPro => _sellerPro;
  int get boostCredits => _boostCredits;
  double get boostRevenue => fromCents(_boostRevenueCents);
  double get subscriptionRevenue => fromCents(_subscriptionRevenueCents);
  int get sellerLiveListings => sellerListings
      .where((listing) => listing.status == ListingStatus.live)
      .length;
  int get sellerSoldListings => sellerListings
      .where((listing) => listing.status == ListingStatus.sold)
      .length;
  double get sellerGrossSales => money(
    sellerOrders.fold<int>(0, (sum, order) => sum + order.salePriceCents) / 100,
  );
  double get sellerFees => money(
    sellerOrders.fold<int>(0, (sum, order) => sum + order.sellerFeeCents) / 100,
  );
  double get sellerNetEarnings => money(
    sellerOrders.fold<int>(0, (sum, order) => sum + order.sellerPayoutCents) /
        100,
  );
  double get availablePayout {
    final settled = sellerOrders
        .where((order) => order.status == OrderStatus.delivered)
        .fold<int>(0, (sum, order) => sum + order.sellerPayoutCents);
    return fromCents(math.max(0, settled - _payoutsRequestedCents));
  }

  double get pendingPayout => fromCents(
    sellerOrders
        .where((order) => order.status != OrderStatus.delivered)
        .fold<int>(0, (sum, order) => sum + order.sellerPayoutCents),
  );
  double get sellerSellThrough {
    final offered = sellerLiveListings + sellerOrders.length;
    return offered == 0 ? 0 : sellerOrders.length / offered;
  }

  double get marketplaceGmv => fromCents(
    _orders.fold<int>(0, (sum, order) => sum + order.salePriceCents),
  );
  double get platformRevenue => fromCents(
    _orders.fold<int>(0, (sum, order) => sum + order.sellerFeeCents) +
        _receipts.fold<int>(
          0,
          (sum, receipt) => sum + receipt.buyerProtectionCents,
        ) +
        _boostRevenueCents +
        _subscriptionRevenueCents,
  );
  double get contributionEstimate => fromCents(
    _receipts.fold<int>(
          0,
          (sum, receipt) => sum + receipt.contributionEstimateCents,
        ) +
        _boostRevenueCents +
        _subscriptionRevenueCents,
  );

  bool isFavorite(Product product) => _favoriteIds.contains(product.id);

  bool isOwnListing(Product product) =>
      product.sellerHandle == activeSellerHandle;

  bool isPromoted(Product product) => _sellerListings.any(
    (listing) =>
        listing.product.id == product.id &&
        listing.status == ListingStatus.live &&
        listing.isPromoted,
  );

  bool isListingAvailable(Product product) {
    final listing = _sellerListings
        .where((candidate) => candidate.product.id == product.id)
        .firstOrNull;
    return listing == null || listing.status == ListingStatus.live;
  }

  void toggleFavorite(Product product) {
    if (!_favoriteIds.add(product.id)) _favoriteIds.remove(product.id);
    notifyListeners();
    unawaited(_persistCurrent());
  }

  bool addToCart(Product product, {String size = 'M'}) {
    _commerceError = null;
    if (cartLockedForCheckout) {
      _commerceError =
          'Finish or cancel the open Stripe checkout before changing the cart.';
      notifyListeners();
      return false;
    }
    if (isOwnListing(product)) {
      _commerceError = 'You cannot buy your own listing.';
      notifyListeners();
      return false;
    }
    if (!isListingAvailable(product)) {
      _commerceError = 'This one-of-one item is no longer available.';
      notifyListeners();
      return false;
    }
    if (_cart.any((item) => item.product.id == product.id)) {
      _commerceError = 'This one-of-one item is already in your cart.';
      return false;
    }
    _cart.add(CartItem(product: product, size: size));
    notifyListeners();
    unawaited(_persistCurrent());
    return true;
  }

  void changeQuantity(CartItem item, int quantity) {
    if (quantity <= 0) removeFromCart(item);
  }

  void removeFromCart(CartItem item) {
    if (cartLockedForCheckout) {
      _commerceError =
          'Finish or cancel the open Stripe checkout before changing the cart.';
      notifyListeners();
      return;
    }
    _cart.remove(item);
    notifyListeners();
    unawaited(_persistCurrent());
  }

  Future<Product?> createListing({
    required String title,
    required String brand,
    required String category,
    required String condition,
    required double price,
    required String description,
    required String imageAsset,
    String size = 'One size',
  }) async {
    _commerceError = null;
    if (price < 10 || price > 10000 || imageAsset.isEmpty) {
      _commerceError = 'Check the price and choose a product photo.';
      notifyListeners();
      return null;
    }
    final now = DateTime.now();
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final product = Product(
      id: 'seller-$slug-${now.microsecondsSinceEpoch}',
      name: title.trim(),
      brand: brand.trim(),
      price: money(price),
      image: imageAsset,
      isAssetImage: true,
      mediaRole: ProductMediaRole.sellerEvidence,
      category: category.trim(),
      condition: condition,
      seller: activeSellerName,
      sellerHandle: activeSellerHandle,
      vibe: 'Seller drop',
      description: description.trim(),
      tags: {
        brand.trim().toLowerCase(),
        category.trim().toLowerCase(),
        condition.toLowerCase(),
        'seller declared',
      }.toList(),
      sizes: [size.trim().isEmpty ? 'One size' : size.trim()],
    );
    final next = [
      SellerListing(
        product: product,
        status: ListingStatus.live,
        createdAt: now,
        createdByUser: true,
      ),
      ..._sellerListings,
    ];
    final saved = await _persistSnapshot(sellerListings: next);
    if (!saved) {
      _commerceError = 'The listing could not be saved. Try again.';
      notifyListeners();
      return null;
    }
    _sellerListings
      ..clear()
      ..addAll(next);
    notifyListeners();
    return product;
  }

  void boostListing(String productId, BoostPlan plan) {
    final index = _sellerListings.indexWhere(
      (listing) =>
          listing.product.id == productId &&
          listing.product.sellerHandle == activeSellerHandle &&
          listing.status == ListingStatus.live,
    );
    if (index < 0) return;
    final start =
        _sellerListings[index].promotionEndsAt?.isAfter(DateTime.now()) == true
        ? _sellerListings[index].promotionEndsAt!
        : DateTime.now();
    _sellerListings[index] = _sellerListings[index].copyWith(
      promotionEndsAt: start.add(plan.duration),
    );
    if (_sellerPro && plan == BoostPlan.oneDay && _boostCredits > 0) {
      _boostCredits--;
    } else {
      _boostRevenueCents += plan.priceCents;
    }
    notifyListeners();
    unawaited(_persistCurrent());
  }

  void toggleListingPaused(String productId) {
    final index = _sellerListings.indexWhere(
      (listing) =>
          listing.product.id == productId &&
          listing.product.sellerHandle == activeSellerHandle &&
          listing.status != ListingStatus.sold,
    );
    if (index < 0) return;
    final nextStatus = _sellerListings[index].status == ListingStatus.paused
        ? ListingStatus.live
        : ListingStatus.paused;
    _sellerListings[index] = _sellerListings[index].copyWith(
      status: nextStatus,
    );
    _cart.removeWhere((item) => item.product.id == productId);
    notifyListeners();
    unawaited(_persistCurrent());
  }

  Future<MarketplaceOrder?> simulateSellerDemoSale(String productId) async {
    _commerceError = null;
    final index = _sellerListings.indexWhere(
      (listing) =>
          listing.product.id == productId &&
          listing.product.sellerHandle == activeSellerHandle &&
          listing.status == ListingStatus.live,
    );
    if (index < 0) {
      _commerceError = 'Only a live seller listing can receive a demo sale.';
      notifyListeners();
      return null;
    }
    final listing = _sellerListings[index];
    final priceCents = toCents(listing.product.price);
    final feeCents = MarketplacePolicy.sellerFeeCents(
      priceCents,
      sellerIsPro: _sellerPro,
    );
    final now = DateTime.now();
    final order = MarketplaceOrder(
      id: 'DEMO-SALE-${now.microsecondsSinceEpoch}',
      productId: listing.product.id,
      productName: listing.product.name,
      sellerHandle: activeSellerHandle,
      salePriceCents: priceCents,
      sellerFeeCents: feeCents,
      sellerPayoutCents: priceCents - feeCents,
      status: OrderStatus.placed,
      createdAt: now,
    );
    final nextListings = List<SellerListing>.from(_sellerListings);
    nextListings[index] = listing.copyWith(status: ListingStatus.sold);
    final nextOrders = [..._orders, order];
    final saved = await _persistSnapshot(
      sellerListings: nextListings,
      orders: nextOrders,
    );
    if (!saved) {
      _commerceError = 'The demo sale was not recorded. Try again.';
      notifyListeners();
      return null;
    }
    _sellerListings
      ..clear()
      ..addAll(nextListings);
    _orders
      ..clear()
      ..addAll(nextOrders);
    notifyListeners();
    return order;
  }

  void advanceSellerOrder(String orderId) {
    final index = _orders.indexWhere(
      (order) =>
          order.id == orderId && order.sellerHandle == activeSellerHandle,
    );
    if (index < 0 || _orders[index].status == OrderStatus.delivered) return;
    final status = _orders[index].status == OrderStatus.placed
        ? OrderStatus.shipped
        : OrderStatus.delivered;
    _orders[index] = _orders[index].copyWith(status: status);
    notifyListeners();
    unawaited(_persistCurrent());
  }

  void setSellerPro(bool enabled) {
    if (_sellerPro == enabled) return;
    _sellerPro = enabled;
    if (enabled) {
      _boostCredits += 3;
      _subscriptionRevenueCents += MarketplacePolicy.proMonthlyPriceCents;
    }
    notifyListeners();
    unawaited(_persistCurrent());
  }

  void requestPayout() {
    final cents = toCents(availablePayout);
    if (cents <= 0) return;
    _payoutsRequestedCents += cents;
    notifyListeners();
    unawaited(_persistCurrent());
  }

  CheckoutSession? get resumableStripeSession {
    final pending = _pendingCheckout;
    if (pending == null) return null;
    return CheckoutSession(
      orderId: pending.orderId,
      checkoutSessionId: pending.checkoutSessionId,
      checkoutUrl: pending.checkoutUrl,
      expiresAt: pending.expiresAt,
      quote: pending.quote,
      status: _checkoutPaymentStatus ?? CheckoutPaymentStatus.open,
    );
  }

  Future<void> refreshStripeCheckoutConnection() {
    if (_disposed) return Future.value();
    final active = _checkoutReadinessRequest;
    if (active != null) return active;
    final future = _refreshStripeCheckoutConnection();
    _checkoutReadinessRequest = future;
    return future.whenComplete(() {
      if (identical(_checkoutReadinessRequest, future)) {
        _checkoutReadinessRequest = null;
      }
    });
  }

  Future<void> _refreshStripeCheckoutConnection() async {
    final gateway = _checkoutGateway;
    if (gateway == null) {
      _stripeCheckoutConnection = StripeCheckoutConnectionState.notConfigured;
      if (!_disposed) notifyListeners();
      return;
    }
    if (gateway is! CheckoutReadinessGateway) {
      _stripeCheckoutConnection = StripeCheckoutConnectionState.ready;
      if (!_disposed) notifyListeners();
      return;
    }
    final readinessGateway = gateway as CheckoutReadinessGateway;
    _stripeCheckoutConnection = StripeCheckoutConnectionState.checking;
    if (!_disposed) notifyListeners();
    try {
      final ready = await readinessGateway.isCheckoutReady();
      if (_disposed) return;
      _stripeCheckoutConnection = ready
          ? StripeCheckoutConnectionState.ready
          : StripeCheckoutConnectionState.serverSetupRequired;
    } on Object {
      if (_disposed) return;
      _stripeCheckoutConnection = StripeCheckoutConnectionState.unavailable;
    }
    notifyListeners();
  }

  /// Creates one server-authoritative Stripe Checkout Session and persists the
  /// resumable handoff before the browser opens. A stable attempt ID survives
  /// network timeouts and app restarts, allowing the server to return the same
  /// Session instead of charging twice.
  Future<CheckoutSession?> beginStripeCheckout() async {
    if (_checkoutInProgress) return null;
    _commerceError = null;
    final gateway = _checkoutGateway;
    if (gateway == null) {
      _commerceError =
          'Stripe is not connected for this build. Add the secure checkout server URL to enable payments.';
      notifyListeners();
      return null;
    }
    final existing = resumableStripeSession;
    if (existing != null) return existing;
    if (_stripeCheckoutConnection != StripeCheckoutConnectionState.ready) {
      _commerceError = switch (_stripeCheckoutConnection) {
        StripeCheckoutConnectionState.checking =>
          'Drip is still verifying the secure Stripe connection.',
        StripeCheckoutConnectionState.serverSetupRequired =>
          'The payment server is online, but Stripe still needs to be configured there.',
        StripeCheckoutConnectionState.unavailable =>
          'The secure payment server could not be reached. Check the connection and try again.',
        StripeCheckoutConnectionState.notConfigured =>
          'Stripe is not connected for this build. Add the Drip API URL to enable payments.',
        StripeCheckoutConnectionState.ready =>
          'Secure checkout could not start.',
      };
      notifyListeners();
      return null;
    }
    if (_cart.isEmpty) {
      _commerceError = 'Add an item before checking out.';
      notifyListeners();
      return null;
    }
    for (final item in _cart) {
      if (isOwnListing(item.product) || !isListingAvailable(item.product)) {
        _commerceError = isOwnListing(item.product)
            ? 'Remove your own listing before checkout.'
            : '${item.product.name} is no longer available.';
        notifyListeners();
        return null;
      }
    }

    _checkoutInProgress = true;
    notifyListeners();
    try {
      final attemptId =
          _checkoutAttemptId ??
          'drip-${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
      if (_checkoutAttemptId == null) {
        _checkoutAttemptId = attemptId;
        if (!await _persistCurrent()) {
          _checkoutAttemptId = null;
          _commerceError =
              'Checkout could not start safely because its retry record was not saved.';
          return null;
        }
      }
      final request = CheckoutRequest(
        attemptId: attemptId,
        lines: _cart.map(
          (item) =>
              CheckoutLine(listingId: item.product.id, selectedSize: item.size),
        ),
      );
      final session = await gateway.createCheckout(request);
      if (!_quoteMatchesCurrentCart(session.quote) ||
          !session.expiresAt.isAfter(DateTime.now().toUtc())) {
        await _bestEffortExpire(session, attemptId);
        _checkoutAttemptId = null;
        await _persistCurrent();
        _commerceError =
            'The secure price check did not match your cart. Nothing was charged; refresh the cart and try again.';
        return null;
      }

      final pending = PendingCheckout.fromSession(
        request: request,
        session: session,
        createdAt: DateTime.now().toUtc(),
      );
      _pendingCheckout = pending;
      _checkoutPaymentStatus = session.status;
      if (!await _persistCurrent()) {
        _pendingCheckout = null;
        _checkoutPaymentStatus = null;
        _checkoutAttemptId = null;
        await _bestEffortExpire(session, attemptId);
        _commerceError =
            'Checkout was stopped safely because its recovery record could not be saved.';
        return null;
      }
      return session;
    } on CheckoutException catch (error) {
      _commerceError = error.publicMessage;
      if (!error.retryable && _pendingCheckout == null) {
        _checkoutAttemptId = null;
        await _persistCurrent();
      }
      return null;
    } catch (_) {
      _commerceError = 'Secure checkout could not start. Please try again.';
      return null;
    } finally {
      _checkoutInProgress = false;
      notifyListeners();
    }
  }

  /// Reconciles the current browser handoff with the backend. The return URL
  /// itself is never considered proof of payment.
  Future<CheckoutStatusSnapshot?> refreshStripeCheckout({
    String? checkoutSessionId,
  }) async {
    if (_checkoutInProgress) return null;
    _commerceError = null;
    final gateway = _checkoutGateway;
    final sessionId = checkoutSessionId ?? _pendingCheckout?.checkoutSessionId;
    if (gateway == null || sessionId == null) {
      _commerceError = gateway == null
          ? 'Stripe is not connected for this build.'
          : 'There is no open checkout to confirm.';
      notifyListeners();
      return null;
    }
    _checkoutInProgress = true;
    notifyListeners();
    try {
      final snapshot = await gateway.getCheckoutStatus(sessionId);
      await _reconcileStripeSnapshot(snapshot);
      return snapshot;
    } on CheckoutException catch (error) {
      _commerceError = error.publicMessage;
      return null;
    } catch (_) {
      _commerceError = 'Payment status could not be confirmed. Try again.';
      return null;
    } finally {
      _checkoutInProgress = false;
      notifyListeners();
    }
  }

  Future<bool> expireStripeCheckout() async {
    if (_checkoutInProgress) return false;
    _commerceError = null;
    final gateway = _checkoutGateway;
    final pending = _pendingCheckout;
    if (gateway == null || pending == null) return false;
    _checkoutInProgress = true;
    notifyListeners();
    try {
      final snapshot = await gateway.expireCheckout(
        checkoutSessionId: pending.checkoutSessionId,
        attemptId: pending.attemptId,
      );
      await _reconcileStripeSnapshot(snapshot);
      return snapshot.status == CheckoutPaymentStatus.expired ||
          snapshot.status == CheckoutPaymentStatus.canceled;
    } on CheckoutException catch (error) {
      _commerceError = error.publicMessage;
      return false;
    } catch (_) {
      _commerceError = 'The open checkout could not be canceled. Try again.';
      return false;
    } finally {
      _checkoutInProgress = false;
      notifyListeners();
    }
  }

  bool _quoteMatchesCurrentCart(CheckoutQuote quote) =>
      quote.currency == 'usd' &&
      quote.subtotalCents == cartSubtotalCents &&
      quote.protectionCents == cartBuyerProtectionCents &&
      quote.shippingCents == cartShippingCents &&
      quote.totalCents == cartTotalCents + quote.taxCents;

  Future<void> _bestEffortExpire(
    CheckoutSession session,
    String attemptId,
  ) async {
    try {
      await _checkoutGateway?.expireCheckout(
        checkoutSessionId: session.checkoutSessionId,
        attemptId: attemptId,
      );
    } catch (_) {
      // Stripe/server expiry remains the final recovery path. This cleanup is
      // best-effort and must not replace the buyer-facing validation failure.
    }
  }

  Future<void> _reconcileStripeSnapshot(CheckoutStatusSnapshot snapshot) async {
    final pending = _pendingCheckout;
    if (pending != null &&
        snapshot.checkoutSessionId == pending.checkoutSessionId) {
      final expectedIds = pending.lines.map((line) => line.listingId).toSet();
      if (snapshot.orderId != pending.orderId ||
          (snapshot.quote != null && snapshot.quote != pending.quote) ||
          (snapshot.listingIds.isNotEmpty &&
              !_sameIds(snapshot.listingIds.toSet(), expectedIds))) {
        throw const CheckoutProtocolException();
      }
    }

    _checkoutPaymentStatus = snapshot.status;
    if (snapshot.isPaid) {
      final confirmation = snapshot.confirmation!;
      final receipt = await _applyStripeConfirmation(confirmation);
      if (receipt == null) {
        _commerceError ??=
            'Payment is confirmed. Your order is safe, but this device still needs to sync it.';
      }
      return;
    }

    if (snapshot.status == CheckoutPaymentStatus.expired ||
        snapshot.status == CheckoutPaymentStatus.canceled ||
        snapshot.status == CheckoutPaymentStatus.failed) {
      if (pending != null &&
          pending.checkoutSessionId == snapshot.checkoutSessionId) {
        _pendingCheckout = null;
        _checkoutAttemptId = null;
        if (!await _persistCurrent()) {
          _pendingCheckout = pending;
          _checkoutAttemptId = pending.attemptId;
        }
      }
    }
  }

  Future<CheckoutReceipt?> _applyStripeConfirmation(
    CheckoutConfirmation confirmation,
  ) async {
    final existing = _receipts
        .where(
          (receipt) =>
              receipt.stripeCheckoutSessionId == confirmation.checkoutSessionId,
        )
        .firstOrNull;
    if (existing != null) {
      _pendingCheckout = null;
      _checkoutAttemptId = null;
      _checkoutPaymentStatus = CheckoutPaymentStatus.paid;
      await _persistCurrent();
      return existing;
    }

    final pending = _pendingCheckout;
    if (pending == null ||
        pending.orderId != confirmation.orderId ||
        pending.checkoutSessionId != confirmation.checkoutSessionId ||
        pending.quote != confirmation.quote) {
      _commerceError =
          'Payment is confirmed for order ${confirmation.orderId}, but its local recovery record is missing.';
      return null;
    }
    final expectedIds = pending.lines.map((line) => line.listingId).toSet();
    final confirmedIds = confirmation.purchasedListingIds.toSet();
    if (!_sameIds(expectedIds, confirmedIds)) {
      throw const CheckoutProtocolException();
    }

    final cartById = {for (final item in _cart) item.product.id: item};
    final listingsById = {
      for (final listing in _sellerListings) listing.product.id: listing,
    };
    final purchasedItems = <CartItem>[];
    for (final line in pending.lines) {
      final cartItem = cartById[line.listingId];
      if (cartItem != null) {
        purchasedItems.add(cartItem);
        continue;
      }
      final listing = listingsById[line.listingId];
      if (listing == null) {
        _commerceError =
            'Payment is confirmed. Order ${confirmation.orderId} is waiting for a catalog sync on this device.';
        return null;
      }
      purchasedItems.add(
        CartItem(product: listing.product, size: line.selectedSize),
      );
    }
    if (purchasedItems.fold<int>(0, (sum, item) => sum + item.totalCents) !=
        confirmation.subtotalCents) {
      throw const CheckoutProtocolException();
    }

    var sellerFeeTotalCents = 0;
    final confirmedAt = confirmation.confirmedAt ?? DateTime.now().toUtc();
    final nextOrders = List<MarketplaceOrder>.from(_orders);
    for (var index = 0; index < purchasedItems.length; index++) {
      final item = purchasedItems[index];
      final priceCents = item.totalCents;
      final feeCents = MarketplacePolicy.sellerFeeCents(
        priceCents,
        sellerIsPro:
            item.product.sellerHandle == activeSellerHandle && _sellerPro,
      );
      sellerFeeTotalCents += feeCents;
      nextOrders.add(
        MarketplaceOrder(
          id: '${confirmation.orderId}-${index + 1}',
          productId: item.product.id,
          productName: item.product.name,
          sellerHandle: item.product.sellerHandle,
          salePriceCents: priceCents,
          sellerFeeCents: feeCents,
          sellerPayoutCents: priceCents - feeCents,
          status: OrderStatus.placed,
          createdAt: confirmedAt,
          paymentProvider: PaymentProvider.stripe,
          paymentStatus: PaymentStatus.paid,
          currency: confirmation.currency,
          stripeCheckoutSessionId: confirmation.checkoutSessionId,
          stripePaymentIntentId: confirmation.paymentIntentId,
        ),
      );
    }

    final nextListings = _sellerListings
        .map(
          (listing) => confirmedIds.contains(listing.product.id)
              ? listing.copyWith(status: ListingStatus.sold)
              : listing,
        )
        .toList();
    final platformRevenueCents =
        confirmation.buyerProtectionCents + sellerFeeTotalCents;
    final contributionCents = math.max(
      0,
      platformRevenueCents -
          MarketplacePolicy.processingEstimateCents(confirmation.totalCents) -
          MarketplacePolicy.lossReserveCents(confirmation.subtotalCents) -
          50 * purchasedItems.length,
    );
    final receipt = CheckoutReceipt(
      id: confirmation.orderId,
      subtotalCents: confirmation.subtotalCents,
      buyerProtectionCents: confirmation.buyerProtectionCents,
      shippingCents: confirmation.shippingCents,
      totalCents: confirmation.totalCents,
      platformRevenueCents: platformRevenueCents,
      contributionEstimateCents: contributionCents,
      createdAt: confirmedAt,
      paymentProvider: PaymentProvider.stripe,
      paymentStatus: PaymentStatus.paid,
      currency: confirmation.currency,
      taxCents: confirmation.taxCents,
      stripeCheckoutSessionId: confirmation.checkoutSessionId,
      stripePaymentIntentId: confirmation.paymentIntentId,
    );
    final nextCart = _cart
        .where((item) => !confirmedIds.contains(item.product.id))
        .toList();
    final nextReceipts = [..._receipts, receipt];
    final nextSpend = _lifetimeSpendCents + receipt.totalCents;
    final nextFavorites = Set<String>.from(_favoriteIds)
      ..removeAll(confirmedIds);

    _pendingCheckout = null;
    _checkoutAttemptId = null;
    final saved = await _persistSnapshot(
      favoriteIds: nextFavorites,
      cart: nextCart,
      sellerListings: nextListings,
      orders: nextOrders,
      receipts: nextReceipts,
      lifetimeSpendCents: nextSpend,
    );
    if (!saved) {
      _pendingCheckout = pending;
      _checkoutAttemptId = pending.attemptId;
      _checkoutPaymentStatus = CheckoutPaymentStatus.paid;
      _commerceError =
          'Payment is confirmed and safe. This device will retry syncing the order.';
      return null;
    }

    _cart
      ..clear()
      ..addAll(nextCart);
    _sellerListings
      ..clear()
      ..addAll(nextListings);
    _orders
      ..clear()
      ..addAll(nextOrders);
    _receipts
      ..clear()
      ..addAll(nextReceipts);
    _favoriteIds
      ..clear()
      ..addAll(nextFavorites);
    _lifetimeSpendCents = nextSpend;
    _checkoutPaymentStatus = CheckoutPaymentStatus.paid;
    return receipt;
  }

  static bool _sameIds(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  bool _restoreSnapshot() {
    final encoded =
        _preferences?.getString(_snapshotKey) ??
        (storageNamespace == 'demo'
            ? _preferences?.getString(_legacySnapshotKey)
            : null);
    if (encoded == null) return false;
    try {
      final json = Map<String, Object?>.from(jsonDecode(encoded) as Map);
      final schemaVersion = (json['schemaVersion'] as num?)?.toInt();
      if (schemaVersion != 2 && schemaVersion != 3) return false;
      _favoriteIds.addAll((json['favoriteIds'] as List? ?? const []).cast());
      _cart.addAll(
        (json['cart'] as List? ?? const []).map(
          (item) => CartItem.fromJson(Map<String, Object?>.from(item as Map)),
        ),
      );
      _sellerListings.addAll(
        (json['sellerListings'] as List? ?? const []).map(
          (item) =>
              SellerListing.fromJson(Map<String, Object?>.from(item as Map)),
        ),
      );
      _orders.addAll(
        (json['orders'] as List? ?? const []).map(
          (item) =>
              MarketplaceOrder.fromJson(Map<String, Object?>.from(item as Map)),
        ),
      );
      _receipts.addAll(
        (json['receipts'] as List? ?? const []).map(
          (item) =>
              CheckoutReceipt.fromJson(Map<String, Object?>.from(item as Map)),
        ),
      );
      _lifetimeSpendCents = (json['lifetimeSpendCents'] as num?)?.toInt() ?? 0;
      _payoutsRequestedCents =
          (json['payoutsRequestedCents'] as num?)?.toInt() ?? 0;
      _boostRevenueCents = (json['boostRevenueCents'] as num?)?.toInt() ?? 0;
      _subscriptionRevenueCents =
          (json['subscriptionRevenueCents'] as num?)?.toInt() ?? 0;
      _boostCredits = (json['boostCredits'] as num?)?.toInt() ?? 0;
      _sellerPro = json['sellerPro'] as bool? ?? false;
      _checkoutAttemptId = json['checkoutAttemptId'] as String?;
      if (json['pendingCheckout'] case final Map value) {
        _pendingCheckout = PendingCheckout.fromJson(
          Map<String, Object?>.from(value),
        );
        _checkoutPaymentStatus = CheckoutPaymentStatus.open;
      }
      return _sellerListings.isNotEmpty;
    } catch (_) {
      _commerceError = 'A damaged local demo snapshot was safely reset.';
      _favoriteIds.clear();
      _cart.clear();
      _sellerListings.clear();
      _orders.clear();
      _receipts.clear();
      _pendingCheckout = null;
      _checkoutPaymentStatus = null;
      _checkoutAttemptId = null;
      return false;
    }
  }

  void _restoreLegacyBuyerState() {
    final savedFavorites = _preferences?.getStringList('drip.favorites');
    if (savedFavorites != null) _favoriteIds.addAll(savedFavorites);
    _lifetimeSpendCents = toCents(
      _preferences?.getDouble('drip.lifetimeSpend') ?? 0,
    );
    final productById = {for (final product in products) product.id: product};
    for (final encoded
        in _preferences?.getStringList('drip.cart') ?? const []) {
      final parts = encoded.split('|');
      if (parts.length < 2) continue;
      final product = productById[parts.first];
      if (product == null) continue;
      _cart.add(CartItem(product: product, size: parts[1]));
    }
  }

  void _seedMarketplace() {
    final now = DateTime.now();
    for (var index = 0; index < products.length; index++) {
      final product = products[index];
      final owned = product.sellerHandle == activeSellerHandle;
      _sellerListings.add(
        SellerListing(
          product: product,
          status: product.id == 'black-backpack'
              ? ListingStatus.sold
              : ListingStatus.live,
          createdAt: now.subtract(Duration(days: 5 + index * 4)),
          views: owned ? math.max(18, 128 - index * 2) : 0,
          saves: owned ? math.max(2, 14 - index ~/ 3) : 0,
          promotionEndsAt: product.id == 'black-street-sneakers'
              ? now.add(const Duration(hours: 18))
              : null,
        ),
      );
    }
    if (!demoSellerMode) return;
    _orders.addAll([
      MarketplaceOrder(
        id: 'DEMO-ORDER-1001',
        productId: 'black-backpack',
        productName: 'Black Backpack',
        sellerHandle: activeSellerHandle,
        salePriceCents: 3000,
        sellerFeeCents: 300,
        sellerPayoutCents: 2700,
        status: OrderStatus.delivered,
        createdAt: now.subtract(const Duration(days: 9)),
      ),
      MarketplaceOrder(
        id: 'DEMO-ORDER-1002',
        productId: 'demo-archive-tee',
        productName: 'Archive Graphic Tee',
        sellerHandle: activeSellerHandle,
        salePriceCents: 5800,
        sellerFeeCents: 580,
        sellerPayoutCents: 5220,
        status: OrderStatus.delivered,
        createdAt: now.subtract(const Duration(days: 17)),
      ),
    ]);
  }

  void _ensureCatalogInventory() {
    final knownIds = _sellerListings
        .map((listing) => listing.product.id)
        .toSet();
    final soldIds = _orders.map((order) => order.productId).toSet();
    final now = DateTime.now();
    for (var index = 0; index < products.length; index++) {
      final product = products[index];
      if (knownIds.contains(product.id)) continue;
      _sellerListings.add(
        SellerListing(
          product: product,
          status: soldIds.contains(product.id) || product.id == 'black-backpack'
              ? ListingStatus.sold
              : ListingStatus.live,
          createdAt: now.subtract(Duration(days: 5 + index * 4)),
        ),
      );
    }
  }

  Future<bool> _persistCurrent() => _persistSnapshot();

  Future<bool> _persistSnapshot({
    Set<String>? favoriteIds,
    List<CartItem>? cart,
    List<SellerListing>? sellerListings,
    List<MarketplaceOrder>? orders,
    List<CheckoutReceipt>? receipts,
    int? lifetimeSpendCents,
  }) async {
    if (_preferences == null) return true;
    final snapshot = <String, Object?>{
      'schemaVersion': 3,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'favoriteIds': (favoriteIds ?? _favoriteIds).toList(),
      'cart': (cart ?? _cart).map((item) => item.toJson()).toList(),
      'sellerListings': (sellerListings ?? _sellerListings)
          .map((listing) => listing.toJson())
          .toList(),
      'orders': (orders ?? _orders).map((order) => order.toJson()).toList(),
      'receipts': (receipts ?? _receipts)
          .map((receipt) => receipt.toJson())
          .toList(),
      'lifetimeSpendCents': lifetimeSpendCents ?? _lifetimeSpendCents,
      'payoutsRequestedCents': _payoutsRequestedCents,
      'boostRevenueCents': _boostRevenueCents,
      'subscriptionRevenueCents': _subscriptionRevenueCents,
      'boostCredits': _boostCredits,
      'sellerPro': _sellerPro,
      'pendingCheckout': _pendingCheckout?.toJson(),
      'checkoutAttemptId': _checkoutAttemptId,
    };
    try {
      final saved = await _preferences.setString(
        _snapshotKey,
        jsonEncode(snapshot),
      );
      if (!saved) _commerceError = 'Local marketplace changes were not saved.';
      return saved;
    } catch (_) {
      _commerceError = 'Local marketplace changes were not saved.';
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _checkoutGateway?.close();
    super.dispose();
  }
}
