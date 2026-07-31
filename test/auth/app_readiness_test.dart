import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drip/auth/auth_gateway.dart';
import 'package:drip/auth/auth_models.dart';
import 'package:drip/auth/auth_session_store.dart';
import 'package:drip/main.dart';

import 'auth_test_fakes.dart';

class _ReadinessAuthGateway extends FakeAuthGateway
    implements AuthReadinessGateway {
  final List<Future<DripServiceReadiness>> responses;
  int readinessCalls = 0;

  _ReadinessAuthGateway(this.responses);

  @override
  Future<DripServiceReadiness> getServiceReadiness() {
    readinessCalls++;
    return responses.removeAt(0);
  }
}

Widget _app(_ReadinessAuthGateway gateway) => DripApp(
  authGateway: gateway,
  authSessionStore: MemoryAuthSessionStore(),
  allowDemo: true,
);

void main() {
  testWidgets('startup waits for health before exposing account controls', (
    tester,
  ) async {
    final health = Completer<DripServiceReadiness>();
    final gateway = _ReadinessAuthGateway([health.future]);

    await tester.pumpWidget(_app(gateway));
    await tester.pump();
    await tester.pump();

    expect(find.text('Getting sign-in ready'), findsOneWidget);
    expect(find.byKey(const Key('auth-email-field')), findsNothing);
    expect(gateway.readinessCalls, 1);

    health.complete(
      const DripServiceReadiness(
        accountsConfigured: true,
        paymentsConfigured: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-email-field')), findsOneWidget);
    expect(find.byKey(const Key('auth-password-field')), findsOneWidget);
    expect(find.text('Getting sign-in ready'), findsNothing);
  });

  testWidgets('reachable health can keep accounts safely disabled', (
    tester,
  ) async {
    final gateway = _ReadinessAuthGateway([
      Future.value(
        const DripServiceReadiness(
          accountsConfigured: false,
          paymentsConfigured: true,
        ),
      ),
    ]);

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(
      find.text('Account access is temporarily unavailable'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('auth-email-field')), findsNothing);
    expect(find.byKey(const Key('auth-connection-retry')), findsOneWidget);
    expect(find.byKey(const Key('auth-demo-button')), findsOneWidget);
  });

  testWidgets(
    'unreachable health retries and enables auth only after success',
    (tester) async {
      final initial = Completer<DripServiceReadiness>();
      final recovery = Completer<DripServiceReadiness>();
      final gateway = _ReadinessAuthGateway([initial.future, recovery.future]);

      await tester.pumpWidget(_app(gateway));
      await tester.pump();
      initial.completeError(const AuthException.providerUnavailable());
      await tester.pumpAndSettle();

      expect(find.text('Account access is unavailable'), findsOneWidget);
      expect(find.byKey(const Key('auth-email-field')), findsNothing);
      expect(find.byKey(const Key('auth-demo-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('auth-connection-retry')));
      await tester.pump();
      expect(find.text('Getting sign-in ready'), findsOneWidget);
      recovery.complete(
        const DripServiceReadiness(
          accountsConfigured: true,
          paymentsConfigured: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(gateway.readinessCalls, 2);
      expect(find.byKey(const Key('auth-email-field')), findsOneWidget);
    },
  );
}
