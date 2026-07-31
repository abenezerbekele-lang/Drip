import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:drip/app_state.dart';
import 'package:drip/home_feed.dart';
import 'package:drip/product_detail.dart';

Future<AppState> _pumpHome(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  final app = AppState(storageNamespace: 'home-feed-test');
  addTearDown(app.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true),
        themeMode: ThemeMode.dark,
        home: Scaffold(body: HomeFeed(onThemeToggle: () {})),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testWidgets('premium hero and discovery drop remain actionable on a phone', (
    tester,
  ) async {
    final app = await _pumpHome(tester);
    final spotlight = app.catalogProducts.firstWhere(
      (product) =>
          product.isAssetImage &&
          !app.isOwnListing(product) &&
          app.isListingAvailable(product),
      orElse: () => app.catalogProducts.first,
    );

    expect(find.text('Find your fit.\nOwn the room.'), findsOneWidget);
    expect(find.text('Ask Drip'), findsOneWidget);
    expect(find.text('Top shoppers'), findsOneWidget);
    expect(find.text('DISCOVERY DROP'), findsOneWidget);
    expect(find.text(spotlight.name), findsWidgets);
    expect(find.text('View piece'), findsOneWidget);
    expect(find.byTooltip('Ask Drip about this piece'), findsOneWidget);

    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(
        'Drip editorial: two friends browsing denim at a night clothing market',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Discovery drop, ${spotlight.name}')),
      findsOneWidget,
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('View piece'));
    await tester.tap(find.text('View piece'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductDetail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home composition handles a compact phone with large text', (
    tester,
  ) async {
    await _pumpHome(tester, size: const Size(320, 568), textScale: 2);

    await tester.scrollUntilVisible(
      find.text('DISCOVERY DROP'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('DISCOVERY DROP'), findsOneWidget);
    expect(find.text('View piece'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
