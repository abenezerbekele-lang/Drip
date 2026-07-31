import '../app_state.dart';
import '../product_model.dart';

enum AssistantRole { user, assistant }

enum AssistantIntent {
  outfit,
  discovery,
  sizing,
  checkout,
  orders,
  seller,
  general,
  safety,
}

enum AssistantEntryPoint { general, product, cart, saved, seller }

class AssistantTurn {
  final AssistantRole role;
  final String content;

  const AssistantTurn({required this.role, required this.content});

  Map<String, Object?> toJson() => {'role': role.name, 'content': content};
}

class AssistantContext {
  final AssistantEntryPoint entryPoint;
  final List<Product> catalog;
  final Set<String> unavailableProductIds;
  final Set<String> ownProductIds;
  final Set<String> savedProductIds;
  final List<AssistantCartLine> cart;
  final String? focusProductId;
  final int cartSubtotalCents;
  final int cartProtectionCents;
  final int cartShippingCents;
  final int cartTotalCents;
  final String? checkoutStatus;
  final int receiptCount;
  final int? lastReceiptTotalCents;
  final String? lastReceiptStatus;
  final bool sellerPro;
  final int sellerLiveListings;
  final int sellerSoldListings;

  const AssistantContext({
    required this.entryPoint,
    required this.catalog,
    required this.unavailableProductIds,
    required this.ownProductIds,
    required this.savedProductIds,
    required this.cart,
    required this.focusProductId,
    required this.cartSubtotalCents,
    required this.cartProtectionCents,
    required this.cartShippingCents,
    required this.cartTotalCents,
    required this.checkoutStatus,
    required this.receiptCount,
    required this.lastReceiptTotalCents,
    required this.lastReceiptStatus,
    required this.sellerPro,
    required this.sellerLiveListings,
    required this.sellerSoldListings,
  });

  factory AssistantContext.fromAppState(
    AppState app, {
    AssistantEntryPoint entryPoint = AssistantEntryPoint.general,
    String? focusProductId,
  }) {
    final catalog = app.catalogProducts;
    final lastReceipt = app.lastReceipt;
    return AssistantContext(
      entryPoint: entryPoint,
      catalog: catalog,
      unavailableProductIds: {
        for (final product in catalog)
          if (!app.isListingAvailable(product)) product.id,
      },
      ownProductIds: {
        for (final product in catalog)
          if (app.isOwnListing(product)) product.id,
      },
      savedProductIds: app.favoriteIds,
      cart: [
        for (final item in app.cart)
          AssistantCartLine(
            listingId: item.product.id,
            selectedSize: item.size,
          ),
      ],
      focusProductId: focusProductId,
      cartSubtotalCents: app.cartSubtotalCents,
      cartProtectionCents: app.cartBuyerProtectionCents,
      cartShippingCents: app.cartShippingCents,
      cartTotalCents: app.cartTotalCents,
      checkoutStatus: app.checkoutPaymentStatus?.name,
      receiptCount: app.receipts.length,
      lastReceiptTotalCents: lastReceipt?.totalCents,
      lastReceiptStatus: lastReceipt?.paymentStatus.name,
      sellerPro: app.sellerPro,
      sellerLiveListings: app.sellerLiveListings,
      sellerSoldListings: app.sellerSoldListings,
    );
  }

  Product? productById(String id) {
    for (final product in catalog) {
      if (product.id == id) return product;
    }
    return null;
  }

  bool isPurchasable(Product product) =>
      !unavailableProductIds.contains(product.id) &&
      !ownProductIds.contains(product.id);

  List<Product> get purchasableCatalog =>
      catalog.where(isPurchasable).toList(growable: false);

  Map<String, Object?> toJson() => {
    'entryPoint': entryPoint.name,
    'focusProductId': focusProductId,
    'cart': cart.map((line) => line.toJson()).toList(growable: false),
    'savedListingIds': savedProductIds.take(50).toList(growable: false),
    // These totals personalize explanations. The server still recalculates all
    // authoritative prices and fees rather than trusting client values.
    'cartSubtotalCents': cartSubtotalCents,
    'cartTotalCents': cartTotalCents,
    'checkoutStatus': checkoutStatus,
    'sellerPro': sellerPro,
  };
}

class AssistantCartLine {
  final String listingId;
  final String selectedSize;

  const AssistantCartLine({
    required this.listingId,
    required this.selectedSize,
  });

  Map<String, Object?> toJson() => {
    'listingId': listingId,
    'selectedSize': selectedSize,
  };
}

class AssistantRequest {
  final String message;
  final List<AssistantTurn> history;
  final AssistantContext context;

  const AssistantRequest({
    required this.message,
    required this.history,
    required this.context,
  });

  Map<String, Object?> toJson() => {
    'message': message,
    'history': history
        .take(12)
        .map((turn) => turn.toJson())
        .toList(growable: false),
    'context': context.toJson(),
  };
}

class OutfitPlan {
  final String title;
  final String rationale;
  final List<String> productIds;
  final int subtotalCents;
  final int? budgetCents;

  const OutfitPlan({
    required this.title,
    required this.rationale,
    required this.productIds,
    required this.subtotalCents,
    this.budgetCents,
  });

  factory OutfitPlan.fromJson(Map<String, Object?> json) => OutfitPlan(
    title: _requiredString(json, 'title'),
    rationale: _requiredString(json, 'rationale'),
    productIds: _stringList(json['productIds'], maximum: 6),
    subtotalCents: _requiredInt(json, 'subtotalCents', minimum: 0),
    budgetCents: json['budgetCents'] == null
        ? null
        : _requiredInt(json, 'budgetCents', minimum: 0),
  );
}

class AssistantResponse {
  final String reply;
  final AssistantIntent intent;
  final List<String> followUps;
  final List<String> productIds;
  final OutfitPlan? outfit;
  final bool needsHumanSupport;
  final bool usedRemoteModel;

  const AssistantResponse({
    required this.reply,
    required this.intent,
    this.followUps = const [],
    this.productIds = const [],
    this.outfit,
    this.needsHumanSupport = false,
    this.usedRemoteModel = false,
  });

  AssistantResponse copyWith({bool? usedRemoteModel}) => AssistantResponse(
    reply: reply,
    intent: intent,
    followUps: followUps,
    productIds: productIds,
    outfit: outfit,
    needsHumanSupport: needsHumanSupport,
    usedRemoteModel: usedRemoteModel ?? this.usedRemoteModel,
  );

  factory AssistantResponse.fromJson(Map<String, Object?> json) {
    final intentName = _requiredString(json, 'intent');
    final intent = AssistantIntent.values
        .where((candidate) => candidate.name == intentName)
        .firstOrNull;
    if (intent == null) {
      throw const FormatException('Unknown assistant intent.');
    }
    final rawOutfit = json['outfit'];
    if (rawOutfit != null && rawOutfit is! Map) {
      throw const FormatException('Invalid outfit payload.');
    }
    return AssistantResponse(
      reply: _requiredString(json, 'reply'),
      intent: intent,
      followUps: _stringList(json['followUps'], maximum: 4),
      productIds: _stringList(json['productIds'], maximum: 6),
      outfit: rawOutfit == null
          ? null
          : OutfitPlan.fromJson(Map<String, Object?>.from(rawOutfit as Map)),
      needsHumanSupport: json['needsHumanSupport'] as bool? ?? false,
      usedRemoteModel: true,
    );
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty || value.length > 6000) {
    throw FormatException('Invalid $key.');
  }
  return value.trim();
}

int _requiredInt(
  Map<String, Object?> json,
  String key, {
  required int minimum,
}) {
  final value = json[key];
  if (value is! num || value != value.roundToDouble() || value < minimum) {
    throw FormatException('Invalid $key.');
  }
  return value.toInt();
}

List<String> _stringList(Object? value, {required int maximum}) {
  if (value == null) return const [];
  if (value is! List || value.length > maximum) {
    throw const FormatException('Invalid string list.');
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String || item.trim().isEmpty || item.length > 500) {
      throw const FormatException('Invalid string list item.');
    }
    result.add(item.trim());
  }
  return List.unmodifiable(result);
}
