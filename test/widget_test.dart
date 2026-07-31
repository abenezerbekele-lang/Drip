// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drip/design_system.dart';
import 'package:drip/auth/auth_session_store.dart';
import 'package:drip/main.dart';

void main() {
  testWidgets('renders the marketplace home', (WidgetTester tester) async {
    await _openLocalDemo(tester);

    expect(find.text('Shop the fit.\nJoin the community.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Start shopping'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Start shopping'));
    await tester.pumpAndSettle();

    expect(find.text('drip.'), findsOneWidget);
    expect(find.textContaining('Search Adidas'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('keeps each tab state while browsing', (
    WidgetTester tester,
  ) async {
    await _openLocalDemo(tester);
    await tester.scrollUntilVisible(
      find.text('Start shopping'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Start shopping'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, 'Puma');
    await tester.tap(find.text('Market'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    final homeSearch = tester.widget<EditableText>(
      find.byType(EditableText).first,
    );
    expect(homeSearch.controller.text, 'Puma');
  });

  testWidgets('opens a product route without duplicate hero collisions', (
    WidgetTester tester,
  ) async {
    await _openLocalDemo(tester);
    await tester.scrollUntilVisible(
      find.text('Start shopping'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Start shopping'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Nike Noir Runner'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    final firstProduct = find.ancestor(
      of: find.text('Nike Noir Runner'),
      matching: find.byType(ProductTile),
    );
    tester.widget<ProductTile>(firstProduct).onTap();
    await tester.pumpAndSettle();

    expect(find.text('Select size'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact phone layout supports larger text in dark mode', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await _openLocalDemo(
      tester,
      initialDarkMode: true,
      initiallyWelcomed: true,
    );

    expect(find.text('drip.'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop layout uses the adaptive marketplace navigation', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _openLocalDemo(tester, initiallyWelcomed: true);

    expect(find.text('MARKETPLACE'), findsOneWidget);
    expect(find.text('Your edit'), findsOneWidget);
    expect(find.text('Secure checkout'), findsOneWidget);
    expect(find.text('DRIP CONCIERGE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Market'));
    await tester.pumpAndSettle();
    expect(find.text('The market'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openLocalDemo(
  WidgetTester tester, {
  bool initialDarkMode = false,
  bool initiallyWelcomed = false,
}) async {
  await tester.pumpWidget(
    DripApp(
      initialDarkMode: initialDarkMode,
      initiallyWelcomed: initiallyWelcomed,
      authSessionStore: MemoryAuthSessionStore(),
      allowDemo: true,
    ),
  );
  await tester.pumpAndSettle();
  final demoButton = find.byKey(const Key('auth-demo-button'));
  await tester.ensureVisible(demoButton);
  await tester.pumpAndSettle();
  await tester.tap(demoButton);
  await tester.pumpAndSettle();
}
