import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drip/app_state.dart';
import 'package:drip/commerce_model.dart';
import 'package:drip/product_model.dart';
import 'package:drip/sample_data.dart';

void main() {
  Product purchasable() => products.firstWhere(
    (product) => product.sellerHandle != AppState.currentSellerHandle,
  );

  group('AppState one-of-one cart', () {
    test('deduplicates a listing across size choices and quotes every fee', () {
      final state = AppState();
      final product = purchasable();

      expect(state.addToCart(product, size: '8'), isTrue);
      expect(state.addToCart(product, size: '9'), isFalse);

      expect(state.cart, hasLength(1));
      expect(state.cart.single.quantity, 1);
      expect(state.cartSubtotal, product.price);
      expect(
        state.cartBuyerProtection,
        MarketplacePolicy.buyerProtection(product.price),
      );
      expect(state.cartShipping, MarketplacePolicy.shippingPerSeller);
      expect(
        state.cartTotal,
        money(
          product.price +
              MarketplacePolicy.buyerProtection(product.price) +
              MarketplacePolicy.shippingPerSeller,
        ),
      );
    });

    test('rejects own inventory', () {
      final state = AppState();
      final ownProduct = products.firstWhere(state.isOwnListing);

      expect(state.addToCart(ownProduct), isFalse);
      expect(state.cart, isEmpty);
      expect(state.commerceError, contains('own listing'));
    });

    test('quantity zero removes the listing', () {
      final state = AppState()..addToCart(purchasable());

      state.changeQuantity(state.cart.single, 0);

      expect(state.cart, isEmpty);
      expect(state.cartTotal, 0);
    });

    test('multi-seller carts charge one shipment per seller', () {
      final state = AppState();
      final first = purchasable();
      final second = products.firstWhere(
        (product) =>
            !state.isOwnListing(product) &&
            product.sellerHandle != first.sellerHandle,
      );

      state
        ..addToCart(first)
        ..addToCart(second);

      expect(state.cartShipmentCount, 2);
      expect(state.cartShipping, 13.98);
    });
  });

  group('seller business', () {
    test('publishing creates inventory that survives restart', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final state = AppState(preferences: preferences);
      final startingListings = state.sellerListings.length;

      final product = await state.createListing(
        title: 'Acquisition Ready Jacket',
        brand: 'Drip Labs',
        category: 'Jackets',
        condition: 'Excellent',
        price: 145,
        description: 'A fully persisted seller-created listing.',
        imageAsset: 'assets/products/chair_varsity_jacket_natural_v2.jpg',
        size: 'L',
      );

      expect(product, isNotNull);
      expect(state.sellerListings, hasLength(startingListings + 1));
      expect(
        state.catalogProducts.map((item) => item.id),
        contains(product!.id),
      );
      expect(preferences.getString('drip.marketplace.v3.demo'), isNotNull);

      final restored = AppState(preferences: preferences);
      expect(
        restored.sellerListings.map((listing) => listing.product.id),
        contains(product.id),
      );
      expect(
        restored.catalogProducts.map((item) => item.id),
        contains(product.id),
      );
    });

    test('Pro changes growth economics and consumes included credits', () {
      final state = AppState();
      final listing = state.sellerListings.firstWhere(
        (item) => item.status == ListingStatus.live && !item.isPromoted,
      );

      state.setSellerPro(true);
      expect(state.boostCredits, 3);
      expect(state.subscriptionRevenue, 9.99);

      state.boostListing(listing.product.id, BoostPlan.oneDay);
      expect(state.boostCredits, 2);
      expect(state.boostRevenue, 0);

      state.boostListing(listing.product.id, BoostPlan.sevenDays);
      expect(state.boostRevenue, 5.99);
    });

    test('seller can pause and reactivate live inventory', () {
      final state = AppState();
      final listing = state.sellerListings.firstWhere(
        (item) => item.status == ListingStatus.live,
      );

      state.toggleListingPaused(listing.product.id);
      expect(
        state.sellerListings
            .firstWhere((item) => item.product.id == listing.product.id)
            .status,
        ListingStatus.paused,
      );
      expect(
        state.catalogProducts.map((product) => product.id),
        isNot(contains(listing.product.id)),
      );

      state.toggleListingPaused(listing.product.id);
      expect(
        state.sellerListings
            .firstWhere((item) => item.product.id == listing.product.id)
            .status,
        ListingStatus.live,
      );
    });

    test(
      'external-buyer simulation reconciles sale, fee, and fulfillment',
      () async {
        final state = AppState();
        final listing = state.sellerListings.firstWhere(
          (item) => item.status == ListingStatus.live,
        );
        final availableBefore = state.availablePayout;

        final order = await state.simulateSellerDemoSale(listing.product.id);

        expect(order, isNotNull);
        expect(order!.sellerFeeCents, toCents(listing.product.price * .10));
        expect(
          order.sellerPayoutCents + order.sellerFeeCents,
          order.salePriceCents,
        );
        expect(state.isListingAvailable(listing.product), isFalse);
        expect(state.pendingPayout, greaterThan(0));

        state.advanceSellerOrder(order.id);
        expect(state.sellerOrders.last.status, OrderStatus.shipped);
        state.advanceSellerOrder(order.id);
        expect(state.sellerOrders.last.status, OrderStatus.delivered);
        expect(
          state.availablePayout,
          closeTo(availableBefore + order.sellerPayout, .001),
        );
      },
    );

    test('demo payout reconciles and clears the available balance', () {
      final state = AppState();
      expect(state.availablePayout, greaterThan(0));

      state.requestPayout();

      expect(state.availablePayout, 0);
    });
  });

  test('favorite toggle is reversible', () {
    final state = AppState();
    final product = products.last;
    final initiallySaved = state.isFavorite(product);

    state.toggleFavorite(product);
    expect(state.isFavorite(product), isNot(initiallySaved));

    state.toggleFavorite(product);
    expect(state.isFavorite(product), initiallySaved);
  });
}
