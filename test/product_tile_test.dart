import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:drip/app_state.dart';
import 'package:drip/design_system.dart';
import 'package:drip/sample_data.dart';

void main() {
  testWidgets('product tile preserves open and save behavior', (tester) async {
    final app = AppState();
    final item = products.first;
    var opens = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 220,
                height: 340,
                child: ProductTile(item: item, onTap: () => opens++),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('Nike Noir Runner, Nike, 86 dollars'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Save item'), findsOneWidget);

    await tester.tap(find.text('Nike Noir Runner'));
    await tester.pumpAndSettle();
    expect(opens, 1);

    await tester.tap(find.byTooltip('Save item'));
    await tester.pumpAndSettle();
    expect(app.isFavorite(item), isTrue);
    expect(find.bySemanticsLabel('Remove from saved'), findsWidgets);
    expect(opens, 1);
  });

  testWidgets('product tile stays responsive with larger text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 150,
                height: 250,
                child: ProductTile(item: products[1], onTap: () {}),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Nike Red Court'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
