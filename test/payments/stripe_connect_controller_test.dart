import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:drip/payments/stripe_connect_controller.dart';
import 'package:drip/payments/stripe_connect_gateway.dart';
import 'package:drip/payments/stripe_connect_launcher.dart';
import 'package:drip/payments/stripe_connect_models.dart';

class _FakeGateway implements StripeConnectGateway {
  final ready = const StripeConnectSnapshot(
    status: StripeConnectStatus.ready,
    transfersReady: true,
    payoutsReady: true,
    requirementsDue: 0,
    canOpenDashboard: true,
    livemode: false,
  );
  Completer<StripeConnectSnapshot>? pending;
  Object? statusError;
  int statusCalls = 0;
  int onboardingCalls = 0;

  StripeConnectLink onboardingLink() => StripeConnectLink(
    url: Uri.parse('https://accounts.stripe.com/r/test#alu_opaque-state'),
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
    kind: StripeConnectLinkKind.onboarding,
  );

  StripeConnectLink dashboardLink() => StripeConnectLink(
    url: Uri.parse('https://connect.stripe.com/express/test-login'),
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
    kind: StripeConnectLinkKind.dashboard,
  );

  @override
  Future<StripeConnectLink> createDashboardLink() async => dashboardLink();

  @override
  Future<StripeConnectLink> createOnboardingLink() async {
    onboardingCalls++;
    return onboardingLink();
  }

  @override
  Future<StripeConnectSnapshot> getStatus() {
    statusCalls++;
    if (statusError case final error?) {
      return Future<StripeConnectSnapshot>.error(error);
    }
    return pending?.future ?? Future.value(ready);
  }

  @override
  void close() {}
}

class _FakeLauncher implements StripeConnectLinkLauncher {
  int calls = 0;

  @override
  Future<void> launch(StripeConnectLink link) async {
    calls++;
  }
}

void main() {
  test('status refresh is single-flight', () async {
    final gateway = _FakeGateway()..pending = Completer();
    final controller = StripeConnectController(
      gateway: gateway,
      observeLifecycle: false,
      initializeImmediately: false,
      ownsGateway: false,
    );
    addTearDown(controller.dispose);

    final first = controller.refresh();
    final second = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(gateway.statusCalls, 1);
    gateway.pending!.complete(gateway.ready);
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(controller.snapshot, same(gateway.ready));
  });

  test('failed refresh preserves the last verified status as stale', () async {
    final gateway = _FakeGateway();
    final controller = StripeConnectController(
      gateway: gateway,
      observeLifecycle: false,
      initializeImmediately: false,
      ownsGateway: false,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    gateway.statusError = const StripeConnectException.network();

    expect(await controller.refresh(), isFalse);
    expect(controller.snapshot, same(gateway.ready));
    expect(controller.stale, isTrue);
    expect(controller.error?.retryable, isTrue);
  });

  test('onboarding action creates and launches exactly one link', () async {
    final gateway = _FakeGateway();
    final launcher = _FakeLauncher();
    final controller = StripeConnectController(
      gateway: gateway,
      launcher: launcher,
      observeLifecycle: false,
      initializeImmediately: false,
      ownsGateway: false,
    );
    addTearDown(controller.dispose);

    expect(await controller.startOnboarding(), isTrue);
    expect(gateway.onboardingCalls, 1);
    expect(launcher.calls, 1);
  });
}
