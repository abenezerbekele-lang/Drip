import 'dart:async';

// Public dependency names intentionally initialize private fields.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/widgets.dart';

import 'stripe_connect_gateway.dart';
import 'stripe_connect_launcher.dart';
import 'stripe_connect_models.dart';

enum StripeConnectAction { onboarding, dashboard }

final class StripeConnectController extends ChangeNotifier
    with WidgetsBindingObserver {
  final StripeConnectGateway _gateway;
  final StripeConnectLinkLauncher _launcher;
  final bool _ownsGateway;
  final bool _observeLifecycle;

  StripeConnectSnapshot? _snapshot;
  StripeConnectException? _error;
  Future<bool>? _statusRequest;
  StripeConnectAction? _action;
  bool _loaded = false;
  bool _stale = false;
  bool _disposed = false;

  StripeConnectController({
    required StripeConnectGateway gateway,
    StripeConnectLinkLauncher? launcher,
    bool ownsGateway = true,
    bool observeLifecycle = true,
    bool initializeImmediately = true,
  }) : _gateway = gateway,
       _launcher = launcher ?? UrlStripeConnectLinkLauncher(),
       _ownsGateway = ownsGateway,
       _observeLifecycle = observeLifecycle {
    if (_observeLifecycle) WidgetsBinding.instance.addObserver(this);
    if (initializeImmediately) unawaited(refresh());
  }

  StripeConnectSnapshot? get snapshot => _snapshot;
  StripeConnectException? get error => _error;
  bool get loaded => _loaded;
  bool get refreshing => _statusRequest != null;
  bool get stale => _stale;
  StripeConnectAction? get action => _action;
  bool get busy => refreshing || _action != null;

  Future<bool> refresh() {
    if (_disposed) return Future.value(false);
    final active = _statusRequest;
    if (active != null) return active;
    final future = _runRefresh();
    _statusRequest = future;
    _notify();
    return future.whenComplete(() {
      if (identical(_statusRequest, future)) {
        _statusRequest = null;
        _notify();
      }
    });
  }

  Future<bool> _runRefresh() async {
    try {
      final result = await _gateway.getStatus();
      if (_disposed) return false;
      _snapshot = result;
      _error = null;
      _stale = false;
      _loaded = true;
      return true;
    } on StripeConnectException catch (error) {
      if (_disposed) return false;
      _error = error;
      _stale = _snapshot != null;
      _loaded = true;
      return false;
    } on Object {
      if (_disposed) return false;
      _error = const StripeConnectException.network();
      _stale = _snapshot != null;
      _loaded = true;
      return false;
    }
  }

  Future<bool> startOnboarding() =>
      _runAction(StripeConnectAction.onboarding, _gateway.createOnboardingLink);

  Future<bool> openDashboard() =>
      _runAction(StripeConnectAction.dashboard, _gateway.createDashboardLink);

  Future<bool> _runAction(
    StripeConnectAction action,
    Future<StripeConnectLink> Function() createLink,
  ) async {
    if (_disposed || busy) return false;
    _action = action;
    _error = null;
    _notify();
    try {
      final link = await createLink();
      if (_disposed) return false;
      await _launcher.launch(link);
      return true;
    } on StripeConnectException catch (error) {
      if (!_disposed) _error = error;
      return false;
    } on Object {
      if (!_disposed) _error = const StripeConnectException.network();
      return false;
    } finally {
      if (!_disposed) {
        _action = null;
        _notify();
      }
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) unawaited(refresh());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    if (_ownsGateway) _gateway.close();
    super.dispose();
  }
}
