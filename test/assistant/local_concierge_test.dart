import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:drip/ai_assistant_page.dart';
import 'package:drip/app_state.dart';
import 'package:drip/assistant/assistant_gateway.dart';
import 'package:drip/assistant/assistant_models.dart';
import 'package:drip/assistant/local_concierge.dart';
import 'package:drip/commerce_model.dart';
import 'package:drip/payments/payments.dart';
import 'package:drip/product_model.dart';

import '../support/fake_checkout.dart';

void main() {
  const local = LocalAssistantGateway();

  Future<AssistantResponse> ask(
    AppState state,
    String message, {
    AssistantEntryPoint entryPoint = AssistantEntryPoint.general,
    String? focusProductId,
    List<AssistantTurn> history = const [],
    AssistantGateway gateway = local,
  }) => gateway.respond(
    AssistantRequest(
      message: message,
      history: history,
      context: AssistantContext.fromAppState(
        state,
        entryPoint: entryPoint,
        focusProductId: focusProductId,
      ),
    ),
  );

  Product product(AppState state, String id) =>
      state.catalogProducts.firstWhere((item) => item.id == id);

  String role(Product item) => switch (item.category) {
    'T-Shirts' || 'Shirts' || 'Hoodies' => 'Top',
    'Pants' => 'Bottom',
    'Shoes' => 'Shoes',
    _ => 'Other',
  };

  String money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

  group('LocalAssistantGateway outfit contract', () {
    test(
      'builds a coherent three-role outfit inside the complete budget',
      () async {
        final state = AppState();
        final context = AssistantContext.fromAppState(state);

        final response = await ask(
          state,
          r'Build a clean fit under $150 total. Top M, pants M, shoes 9.',
        );

        expect(response.intent, AssistantIntent.outfit);
        expect(response.outfit, isNotNull);
        expect(response.productIds, hasLength(3));
        expect(response.productIds.toSet(), hasLength(3));

        final selected = response.productIds
            .map((id) => context.productById(id))
            .whereType<Product>()
            .toList();
        expect(selected, hasLength(3));
        expect(selected.map(role).toSet(), {'Top', 'Bottom', 'Shoes'});
        expect(selected.every(context.isPurchasable), isTrue);
        expect(
          selected.where((item) => role(item) == 'Top').single.sizes,
          contains('M'),
        );
        expect(
          selected.where((item) => role(item) == 'Bottom').single.sizes,
          contains('M'),
        );
        expect(
          selected.where((item) => role(item) == 'Shoes').single.sizes,
          contains('9'),
        );

        final subtotal = selected.fold<int>(
          0,
          (sum, item) => sum + toCents(item.price),
        );
        final sellers = selected.map((item) => item.sellerHandle).toSet();
        final protection = MarketplacePolicy.buyerProtectionCents(subtotal);
        final shipping =
            sellers.length * MarketplacePolicy.shippingPerSellerCents;
        final checkoutEstimate = subtotal + protection + shipping;

        expect(response.outfit!.subtotalCents, subtotal);
        expect(response.outfit!.budgetCents, 15000);
        expect(checkoutEstimate, lessThanOrEqualTo(15000));
        expect(response.reply, contains(money(subtotal)));
        expect(response.reply, contains(money(protection)));
        expect(response.reply, contains(money(shipping)));
        expect(response.reply, contains(money(checkoutEstimate)));
        expect(response.reply, contains('before tax'));
        expect(response.reply, contains('not a fit guarantee'));
      },
    );

    test(
      'is honest when no complete outfit can fit the total budget',
      () async {
        final state = AppState();

        final response = await ask(
          state,
          r'Build a full top, pants, and shoe fit under $40 total.',
        );

        expect(response.intent, AssistantIntent.outfit);
        expect(response.outfit, isNull);
        expect(response.reply.toLowerCase(), contains('honestly fit'));
        expect(response.reply, contains(r'$40.00'));
        expect(response.reply, contains('buyer protection'));
        expect(response.reply, contains('shipping'));
        expect(
          response.reply.toLowerCase(),
          isNot(contains('inside your budget')),
        );
      },
    );

    test(
      'does not substitute a different size when a role is impossible',
      () async {
        final state = AppState();

        final response = await ask(
          state,
          r'Build a fit under $300 total with top XS, pants 32, shoes 9.',
        );

        expect(response.intent, AssistantIntent.outfit);
        expect(response.outfit, isNull);
        expect(response.productIds, isEmpty);
        expect(response.reply, contains('verify a complete outfit'));
        expect(response.reply, contains('top'));
        expect(response.reply, contains('rather be exact'));
      },
    );
  });

  group('LocalAssistantGateway grounded discovery', () {
    test(
      'filters every discovery result by the requested listed size',
      () async {
        final state = AppState();
        final context = AssistantContext.fromAppState(state);

        final response = await ask(state, r'Find shoes in size 12 under $100.');

        expect(response.intent, AssistantIntent.discovery);
        expect(response.productIds, isNotEmpty);
        for (final id in response.productIds) {
          final item = context.productById(id)!;
          expect(item.category, 'Shoes');
          expect(item.sizes, contains('12'));
          expect(toCents(item.price), lessThanOrEqualTo(10000));
          expect(context.isPurchasable(item), isTrue);
        }
      },
    );

    test(
      'never invents a Nike fallback when no Nike meets the price',
      () async {
        final state = AppState();

        final response = await ask(state, r'Show me Nike under $20.');

        expect(response.intent, AssistantIntent.discovery);
        expect(response.productIds, isEmpty);
        expect(response.reply, contains('verify a live, purchasable match'));
        expect(response.reply, contains('Nike'));
        expect(response.reply, contains('swap in an unrelated item'));
        expect(response.reply, isNot(contains('Basic White Tee')));
      },
    );

    test(
      'excludes sold inventory and the current seller own inventory',
      () async {
        final state = AppState();
        final context = AssistantContext.fromAppState(state);

        final soldResponse = await ask(state, 'Show me the Black Backpack.');
        final ownResponse = await ask(state, 'Show me the Nike Noir Runner.');

        expect(soldResponse.productIds, isNot(contains('black-backpack')));
        expect(ownResponse.productIds, isNot(contains('nike-noir-runner')));
        for (final id in {
          ...soldResponse.productIds,
          ...ownResponse.productIds,
        }) {
          expect(context.isPurchasable(context.productById(id)!), isTrue);
        }
      },
    );
  });

  group('LocalAssistantGateway checkout grounding', () {
    test('explains the real AppState cart math and seller shipments', () async {
      final state = AppState();
      state
        ..addToCart(product(state, 'nike-red-court'), size: '9')
        ..addToCart(product(state, 'white-heavy-tee'), size: 'M');

      final response = await ask(
        state,
        'Explain my total and why shipping is charged twice.',
        entryPoint: AssistantEntryPoint.cart,
      );

      expect(response.intent, AssistantIntent.checkout);
      expect(response.productIds.toSet(), {
        'nike-red-court',
        'white-heavy-tee',
      });
      expect(response.reply, contains(money(state.cartSubtotalCents)));
      expect(response.reply, contains(money(state.cartBuyerProtectionCents)));
      expect(response.reply, contains(money(state.cartShippingCents)));
      expect(response.reply, contains(money(state.cartTotalCents)));
      expect(response.reply, contains('2 seller packages'));
      expect(response.reply, contains('No Stripe session is currently open'));
      expect(response.reply, contains('server verifies Stripe'));
    });

    test('reports processing without claiming an order is paid', () async {
      final checkout = FakeCheckoutGateway();
      final state = AppState(checkoutGateway: checkout)
        ..addToCart(product(AppState(), 'nike-red-court'), size: '9');
      checkout.onCreate = (_) => CheckoutSession(
        orderId: 'order_ai_processing',
        checkoutSessionId: 'cs_test_ai_processing',
        checkoutUrl: Uri.parse(
          'https://checkout.stripe.com/c/pay/cs_test_ai_processing',
        ),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 31)),
        quote: CheckoutQuote(
          currency: 'usd',
          subtotalCents: state.cartSubtotalCents,
          protectionCents: state.cartBuyerProtectionCents,
          shippingCents: state.cartShippingCents,
          taxCents: 0,
          totalCents: state.cartTotalCents,
        ),
      );
      await state.beginStripeCheckout();
      checkout.onStatus = (_) => CheckoutStatusSnapshot(
        orderId: 'order_ai_processing',
        checkoutSessionId: 'cs_test_ai_processing',
        status: CheckoutPaymentStatus.processing,
        quote: state.pendingCheckout!.quote,
        listingIds: const ['nike-red-court'],
      );
      await state.refreshStripeCheckout();

      final response = await ask(state, 'Is my order paid yet?');

      expect(state.checkoutPaymentStatus, CheckoutPaymentStatus.processing);
      expect(state.receipts, isEmpty);
      expect(response.reply.toLowerCase(), contains('processing'));
      expect(response.reply, contains('not proof of payment'));
      expect(response.reply, contains('server-confirmed Stripe status'));
      expect(response.reply, contains('rather than starting a second payment'));
    });

    test(
      'states the buyer-protection fee without inventing coverage',
      () async {
        final state = AppState()
          ..addToCart(product(AppState(), 'nike-red-court'), size: '9');

        final response = await ask(state, 'What does buyer protection cover?');

        expect(response.intent, AssistantIntent.checkout);
        expect(response.reply, contains(money(state.cartBuyerProtectionCents)));
        expect(
          response.reply,
          contains('does not publish a complete claims-coverage policy'),
        );
        expect(response.reply, contains('invent what a claim would cover'));
      },
    );
  });

  group('LocalAssistantGateway trust and support boundaries', () {
    test('intercepts card data and never repeats it', () async {
      final state = AppState();
      const cardNumber = '4242 4242 4242 4242';

      final response = await ask(
        state,
        'Use $cardNumber and CVC 123 to pay for me.',
      );

      expect(response.intent, AssistantIntent.safety);
      expect(response.productIds, isEmpty);
      expect(response.reply, isNot(contains(cardNumber)));
      expect(response.reply, isNot(contains('123')));
      expect(response.reply, contains('do not put card numbers'));
      expect(response.reply, contains('Stripe’s hosted Checkout page'));
      expect(redactSensitiveAssistantData(cardNumber), isNot(contains('4242')));
      expect(redactSensitiveAssistantData('CVC 123'), equals('CVC [hidden]'));
    });

    test(
      'keeps sensitive data away from a configured remote gateway',
      () async {
        final state = AppState();
        final remote = _RecordingAssistantGateway();
        final resilient = ResilientAssistantGateway(
          remote: remote,
          fallback: local,
        );
        addTearDown(resilient.close);

        final response = await ask(
          state,
          'My card number is 4242 4242 4242 4242.',
          gateway: resilient,
        );

        expect(remote.calls, 0);
        expect(response.intent, AssistantIntent.safety);
      },
    );

    test('never sends sensitive prior history to the remote gateway', () async {
      final state = AppState();
      final remote = _RecordingAssistantGateway();
      final resilient = ResilientAssistantGateway(
        remote: remote,
        fallback: local,
      );
      addTearDown(resilient.close);

      await ask(
        state,
        'Build a clean fit.',
        gateway: resilient,
        history: const [
          AssistantTurn(
            role: AssistantRole.user,
            content: 'My card is 4242 4242 4242 4242.',
          ),
        ],
      );

      expect(remote.calls, 0);
    });

    test(
      'does not promise refund eligibility or invent support contact',
      () async {
        final response = await ask(
          AppState(),
          'I paid yesterday. Give me a refund.',
        );

        expect(response.intent, AssistantIntent.checkout);
        expect(response.needsHumanSupport, isTrue);
        expect(
          response.reply,
          contains('does not yet publish a complete refund'),
        );
        expect(response.reply, contains('promise eligibility or an outcome'));
        expect(response.reply, contains('once one is available'));
        expect(response.reply, isNot(contains('@')));
      },
    );

    test('treats authenticity and condition as seller-declared', () async {
      final state = AppState();
      final response = await ask(
        state,
        'Is the Balenciaga Neon Chunky authentic and verified?',
        entryPoint: AssistantEntryPoint.product,
        focusProductId: 'balenciaga-neon-chunky',
      );

      expect(response.intent, AssistantIntent.general);
      expect(response.needsHumanSupport, isTrue);
      expect(response.reply, contains('does not currently provide'));
      expect(response.reply, contains('seller-verification'));
      expect(response.reply, contains('seller-declared'));
      expect(response.reply, contains('not a guarantee'));
    });

    test(
      'does not invent tracking, delivery date, or seller guarantee',
      () async {
        final response = await ask(
          AppState(),
          'The seller says ship today. When will it arrive and where is tracking?',
        );

        expect(response.intent, AssistantIntent.orders);
        expect(response.needsHumanSupport, isTrue);
        expect(
          response.reply,
          contains('does not currently have carrier tracking'),
        );
        expect(response.reply, contains('give you an arrival date'));
        expect(
          response.reply,
          contains('Seller statements are not a shipping guarantee'),
        );
      },
    );

    test('does not present the payout ledger as transferred money', () async {
      final response = await ask(AppState(), 'Where is my seller payout?');

      expect(response.intent, AssistantIntent.seller);
      expect(response.reply, contains('Stripe-hosted Connect onboarding'));
      expect(
        response.reply,
        contains('not a Stripe balance or completed bank transfer'),
      );
      expect(response.reply, contains('does not yet send automatic Transfers'));
      expect(response.reply, contains('claim money was paid out'));
    });

    test('does not activate or charge for demo Pro', () async {
      final response = await ask(
        AppState(),
        'Activate Drip Pro and charge me now.',
      );

      expect(response.intent, AssistantIntent.seller);
      expect(response.reply, contains('currently local demonstrations'));
      expect(
        response.reply,
        contains('do not create a real subscription, charge'),
      );
      expect(response.reply, contains('server-backed subscription'));
    });
  });

  testWidgets('concierge renders a professional, honest human handoff', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final state = AppState();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: AiAssistantPage(
            gateway: LocalAssistantGateway(),
            entryPoint: AssistantEntryPoint.product,
            focusProductId: 'balenciaga-neon-chunky',
            initialPrompt: 'Is this authentic and verified?',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Drip Concierge'), findsOneWidget);
    expect(find.text('APP-AWARE CONCIERGE'), findsOneWidget);
    expect(find.textContaining('professional'), findsNothing);
    expect(find.textContaining('does not currently provide'), findsOneWidget);
    expect(
      find.textContaining('A human review is the right next step'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Seller details may be incomplete. Never share payment details in chat.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Basketball energy'), findsNothing);
  });
}

final class _RecordingAssistantGateway implements AssistantGateway {
  int calls = 0;

  @override
  Future<AssistantResponse> respond(AssistantRequest request) async {
    calls++;
    return const AssistantResponse(
      reply: 'Remote response should not be used for sensitive input.',
      intent: AssistantIntent.general,
    );
  }

  @override
  void close() {}
}
