import 'package:drip/firebase_options.dart';
import 'package:drip/payments/payments.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('creates and safely expires a hosted Stripe test checkout', (
    tester,
  ) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    final auth = FirebaseAuth.instance;
    await auth.currentUser?.reload();
    final user = auth.currentUser;
    expect(
      user,
      isNotNull,
      reason: 'The simulator must have a signed-in Drip test account.',
    );
    expect(
      user!.emailVerified,
      isTrue,
      reason: 'Checkout requires a verified Firebase account.',
    );

    final gateway = HttpCheckoutGateway.fromEnvironment(
      accessTokenProvider: () async {
        final currentUser = auth.currentUser;
        if (currentUser == null) return null;
        return currentUser.getIdToken(true);
      },
    );
    expect(await gateway.isCheckoutReady(), isTrue);

    final attemptId =
        'staging-smoke-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final session = await gateway.createCheckout(
      CheckoutRequest(
        attemptId: attemptId,
        lines: [CheckoutLine(listingId: 'white-heavy-tee', selectedSize: 'M')],
      ),
    );

    expect(session.checkoutUrl.scheme, 'https');
    expect(session.checkoutUrl.host, 'checkout.stripe.com');
    expect(session.status, CheckoutPaymentStatus.open);
    expect(session.quote.currency, 'usd');
    expect(session.quote.subtotalCents, 3800);

    final expired = await gateway.expireCheckout(
      checkoutSessionId: session.checkoutSessionId,
      attemptId: attemptId,
    );
    expect(
      expired.status,
      anyOf(CheckoutPaymentStatus.expired, CheckoutPaymentStatus.canceled),
    );
  });
}
