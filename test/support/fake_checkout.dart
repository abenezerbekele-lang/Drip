import 'package:drip/payments/payments.dart';

final class FakeCheckoutGateway implements CheckoutGateway {
  CheckoutSession Function(CheckoutRequest request)? onCreate;
  CheckoutStatusSnapshot Function(String checkoutSessionId)? onStatus;
  CheckoutStatusSnapshot Function(String checkoutSessionId, String attemptId)?
  onExpire;

  int createCalls = 0;
  int statusCalls = 0;
  int expireCalls = 0;
  CheckoutRequest? lastRequest;
  bool closed = false;

  @override
  Future<CheckoutSession> createCheckout(CheckoutRequest request) async {
    createCalls++;
    lastRequest = request;
    final handler = onCreate;
    if (handler == null) throw StateError('onCreate was not configured');
    return handler(request);
  }

  @override
  Future<CheckoutStatusSnapshot> getCheckoutStatus(
    String checkoutSessionId,
  ) async {
    statusCalls++;
    final handler = onStatus;
    if (handler == null) throw StateError('onStatus was not configured');
    return handler(checkoutSessionId);
  }

  @override
  Future<CheckoutStatusSnapshot> expireCheckout({
    required String checkoutSessionId,
    required String attemptId,
  }) async {
    expireCalls++;
    final handler = onExpire;
    if (handler == null) throw StateError('onExpire was not configured');
    return handler(checkoutSessionId, attemptId);
  }

  @override
  void close() => closed = true;
}

final class FakeCheckoutLauncher implements CheckoutLauncher {
  int calls = 0;
  CheckoutSession? lastSession;
  Object? error;

  @override
  Future<void> launchCheckout(CheckoutSession session) async {
    calls++;
    lastSession = session;
    if (error case final failure?) throw failure;
  }
}
