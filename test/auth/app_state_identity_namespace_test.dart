import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drip/app_state.dart';
import 'package:drip/product_model.dart';
import 'package:drip/sample_data.dart';

Future<void> _flushPreferenceWrites() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Product _purchasableFor(AppState state, {Set<String> excluding = const {}}) =>
    products.firstWhere(
      (product) =>
          !excluding.contains(product.id) &&
          !state.isOwnListing(product) &&
          state.isListingAvailable(product),
    );

void main() {
  test(
    'two authenticated account namespaces never share buyer state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final accountA = AppState(
        preferences: preferences,
        storageNamespace: 'account-acct_A',
        sellerHandle: '@account-a',
        sellerName: 'Account A',
        demoSellerMode: false,
      );
      final accountB = AppState(
        preferences: preferences,
        storageNamespace: 'account-acct_B',
        sellerHandle: '@account-b',
        sellerName: 'Account B',
        demoSellerMode: false,
      );
      addTearDown(accountA.dispose);
      addTearDown(accountB.dispose);
      final productA = _purchasableFor(accountA);
      final productB = _purchasableFor(accountB, excluding: {productA.id});

      accountA.toggleFavorite(productA);
      expect(accountA.addToCart(productA, size: productA.sizes.first), isTrue);
      accountB.toggleFavorite(productB);
      expect(accountB.addToCart(productB, size: productB.sizes.first), isTrue);
      await _flushPreferenceWrites();

      final restoredA = AppState(
        preferences: preferences,
        storageNamespace: 'account-acct_A',
        sellerHandle: '@account-a',
        sellerName: 'Account A',
        demoSellerMode: false,
      );
      final restoredB = AppState(
        preferences: preferences,
        storageNamespace: 'account-acct_B',
        sellerHandle: '@account-b',
        sellerName: 'Account B',
        demoSellerMode: false,
      );
      addTearDown(restoredA.dispose);
      addTearDown(restoredB.dispose);

      expect(restoredA.favoriteIds, {productA.id});
      expect(restoredA.cart.map((item) => item.product.id), [productA.id]);
      expect(restoredA.favoriteIds, isNot(contains(productB.id)));
      expect(
        restoredA.cart.map((item) => item.product.id),
        isNot(contains(productB.id)),
      );

      expect(restoredB.favoriteIds, {productB.id});
      expect(restoredB.cart.map((item) => item.product.id), [productB.id]);
      expect(restoredB.favoriteIds, isNot(contains(productA.id)));
      expect(
        restoredB.cart.map((item) => item.product.id),
        isNot(contains(productA.id)),
      );
    },
  );

  test(
    'authenticated namespaces do not import legacy demo buyer state',
    () async {
      final legacyProduct = products.first;
      SharedPreferences.setMockInitialValues({
        'drip.favorites': [legacyProduct.id],
        'drip.cart': ['${legacyProduct.id}|${legacyProduct.sizes.first}'],
      });
      final preferences = await SharedPreferences.getInstance();

      final signedIn = AppState(
        preferences: preferences,
        storageNamespace: 'account-acct_private',
        sellerHandle: '@private-member',
        sellerName: 'Private Member',
        demoSellerMode: false,
      );
      addTearDown(signedIn.dispose);

      expect(signedIn.favoriteIds, isEmpty);
      expect(signedIn.cart, isEmpty);
    },
  );
}
