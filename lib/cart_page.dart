import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ai_assistant_page.dart';
import 'app_state.dart';
import 'assistant/assistant_models.dart';
import 'commerce_model.dart';
import 'design_system.dart';
import 'payments/payments.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Shopping cart')),
    body: Consumer<AppState>(
      builder: (context, app, _) {
        if (app.cart.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              const SizedBox(height: 80),
              const Icon(Icons.shopping_bag_outlined, size: 72, color: muted),
              const SizedBox(height: 18),
              const Center(
                child: Text(
                  'Your cart is empty',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Each resale listing is one-of-one. Add a piece before somebody else gets it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              ),
              const SizedBox(height: 22),
              GlassButton(
                onTap: () => Navigator.push(
                  context,
                  dripRoute(
                    const AiAssistantPage(
                      initialPrompt:
                          'Build a complete outfit for me and help me choose the right sizes.',
                      entryPoint: AssistantEntryPoint.cart,
                    ),
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Build a fit with Drip',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GlassButton(
                selected: true,
                onTap: () => Navigator.pop(context),
                child: const Center(
                  child: Text(
                    'Keep shopping',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 35),
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: electricBlue.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: electricBlue.withValues(alpha: .25)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_rounded, color: electricBlue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Stripe Checkout is required for every purchase. Payment and shipping details stay on Stripe’s secure page.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...app.cart.map((item) => _CartRow(item: item)),
            const SizedBox(height: 18),
            _OrderSummary(app: app),
            const SizedBox(height: 12),
            GlassButton(
              onTap: () => Navigator.push(
                context,
                dripRoute(
                  const AiAssistantPage(
                    initialPrompt:
                        'Review my cart, explain how the pieces work together, and complete this fit without changing my cart.',
                    entryPoint: AssistantEntryPoint.cart,
                  ),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome_rounded, color: electricBlue),
                  SizedBox(width: 9),
                  Text(
                    'Ask Drip about this cart',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${app.cartShipmentCount} seller ${app.cartShipmentCount == 1 ? 'package' : 'packages'} · shipping is pass-through, not Drip revenue',
              style: const TextStyle(color: muted, fontSize: 10),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GlassButton(
              selected: true,
              onTap: () =>
                  Navigator.push(context, dripRoute(const CheckoutPage())),
              child: const Center(
                child: Text(
                  'Continue to Stripe',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _OrderSummary extends StatelessWidget {
  final AppState app;
  const _OrderSummary({required this.app});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: .4),
      ),
    ),
    child: Column(
      children: [
        _totalLine('Merchandise', app.cartSubtotal),
        const SizedBox(height: 8),
        _totalLine('Buyer protection', app.cartBuyerProtection),
        const SizedBox(height: 8),
        _totalLine('Shipping · \$6.99 per seller', app.cartShipping),
        const Divider(height: 26),
        _totalLine('Total before tax', app.cartTotal, bold: true),
      ],
    ),
  );

  static Widget _totalLine(String label, double value, {bool bold = false}) =>
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: bold ? null : muted,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            '\$${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: bold ? 20 : 14,
              color: bold ? electricBlue : null,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
            ),
          ),
        ],
      );
}

class _CartRow extends StatelessWidget {
  final CartItem item;
  const _CartRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: SizedBox(
              width: 78,
              height: 78,
              child: productImage(item.product),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Size ${item.size} · ${item.product.condition}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  item.product.sellerHandle,
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
                const SizedBox(height: 7),
                Text(
                  '\$${item.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: electricBlue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove ${item.product.name}',
            onPressed: app.cartLockedForCheckout
                ? null
                : () => app.removeFromCart(item),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class CheckoutPage extends StatefulWidget {
  final CheckoutLauncher? launcher;

  const CheckoutPage({super.key, this.launcher});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage>
    with WidgetsBindingObserver {
  late final CheckoutLauncher launcher;
  String? celebratedSessionId;

  @override
  void initState() {
    super.initState();
    launcher = widget.launcher ?? UrlCheckoutLauncher();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final app = context.read<AppState>();
    if (app.pendingCheckout != null && !app.checkoutInProgress) {
      _refreshStatus(app, quiet: true);
    }
  }

  Future<void> _openStripe(AppState app) async {
    final session = await app.beginStripeCheckout();
    if (!mounted) return;
    if (session == null) {
      _showMessage(app.commerceError ?? 'Secure checkout could not start.');
      return;
    }
    if (!session.expiresAt.isAfter(DateTime.now().toUtc())) {
      await _refreshStatus(app);
      return;
    }
    try {
      await launcher.launchCheckout(session);
    } on CheckoutException catch (error) {
      if (mounted) _showMessage(error.publicMessage);
    } catch (_) {
      if (mounted) {
        _showMessage('Stripe Checkout could not be opened. Try again.');
      }
    }
  }

  Future<void> _refreshStatus(AppState app, {bool quiet = false}) async {
    final snapshot = await app.refreshStripeCheckout();
    if (!mounted) return;
    if (snapshot?.isPaid == true) {
      final receipt = app.lastReceipt;
      if (receipt != null &&
          receipt.stripeCheckoutSessionId == snapshot!.checkoutSessionId &&
          celebratedSessionId != snapshot.checkoutSessionId) {
        celebratedSessionId = snapshot.checkoutSessionId;
        await _showPaidDialog(receipt);
      }
      return;
    }
    if (quiet && app.commerceError == null) return;
    final message =
        app.commerceError ??
        switch (snapshot?.status) {
          CheckoutPaymentStatus.open =>
            'Checkout is still open. Finish payment on Stripe, then check again.',
          CheckoutPaymentStatus.processing =>
            'Stripe is still processing the payment. Your cart remains reserved.',
          CheckoutPaymentStatus.expired =>
            'Checkout expired. Your cart is unlocked so you can try again.',
          CheckoutPaymentStatus.canceled =>
            'Checkout was canceled. Your cart is ready when you are.',
          CheckoutPaymentStatus.failed =>
            'Stripe did not complete the payment. No order was created.',
          CheckoutPaymentStatus.refunded =>
            'This payment was refunded. The order record is being updated.',
          _ => 'Payment has not been confirmed yet.',
        };
    _showMessage(message);
  }

  Future<void> _cancelCheckout(AppState app) async {
    final canceled = await app.expireStripeCheckout();
    if (!mounted) return;
    _showMessage(
      canceled
          ? 'Checkout canceled. Your cart is unlocked.'
          : app.commerceError ?? 'Checkout could not be canceled yet.',
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showPaidDialog(CheckoutReceipt receipt) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF20B486),
          size: 44,
        ),
        title: const Text('Payment confirmed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stripe confirmed your payment of \$${receipt.total.toStringAsFixed(2)}.',
            ),
            const SizedBox(height: 10),
            Text(
              'Order ${receipt.id}',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your order is ready for the seller. Drip never received or stored your card number or CVC.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stripe Checkout')),
    body: Consumer<AppState>(
      builder: (context, app, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              electricBlue.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? .07
                    : .045,
              ),
              Theme.of(context).scaffoldBackgroundColor,
            ],
            stops: const [0, .34],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 35),
          children: [
            const PageHeader(
              eyebrow: 'SECURE PAYMENT',
              title: 'Finish on Stripe',
              subtitle:
                  'Review your total here, then pay on Stripe’s hosted checkout. Stripe collects payment and shipping details directly.',
            ),
            const SizedBox(height: 16),
            _CheckoutFlowRail(
              stripeReady: app.stripeCheckoutConfigured,
              stripeStarted: app.pendingCheckout != null,
              confirmed:
                  app.checkoutPaymentStatus == CheckoutPaymentStatus.paid,
            ),
            const SizedBox(height: 16),
            _StripeTrustCard(
              connection: app.stripeCheckoutConnection,
              onRetry: app.refreshStripeCheckoutConnection,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                dripRoute(
                  const AiAssistantPage(
                    initialPrompt:
                        'Explain how Stripe Checkout works and what happens after I pay.',
                    entryPoint: AssistantEntryPoint.cart,
                  ),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Questions about checkout? Ask Drip'),
            ),
            if (app.pendingCheckout case final pending?) ...[
              const SizedBox(height: 14),
              _PendingCheckoutCard(
                pending: pending,
                status: app.checkoutPaymentStatus,
              ),
            ],
            const SizedBox(height: 22),
            const SectionHeading('Order total'),
            if (app.pendingCheckout case final pending?)
              _StripeQuoteSummary(quote: pending.quote)
            else
              _OrderSummary(app: app),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: electricBlue.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: electricBlue.withValues(alpha: .12)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 18,
                    color: accentForeground(context),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      app.pendingCheckout == null
                          ? 'Stripe will confirm the server-verified total and collect your shipping address. Any tax appears before you pay.'
                          : 'This total is locked to the server quote for this Stripe session. Returning to Drip does not mark it paid—we verify Stripe’s confirmation first.',
                      style: TextStyle(
                        color: mutedForeground(context),
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (app.commerceError case final error?) ...[
              const SizedBox(height: 12),
              _InlineCheckoutMessage(message: error),
            ],
            const SizedBox(height: 18),
            if (app.checkoutInProgress)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (app.pendingCheckout != null) ...[
              GlassButton(
                selected: true,
                onTap: () => _openStripe(app),
                child: const Center(
                  child: Text(
                    'Resume Stripe Checkout',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _refreshStatus(app),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Check payment status'),
              ),
              TextButton(
                onPressed: () => _cancelCheckout(app),
                child: const Text('Cancel this checkout'),
              ),
            ] else
              GlassButton(
                selected: true,
                onTap: app.cart.isEmpty || !app.stripeCheckoutConfigured
                    ? null
                    : () => _openStripe(app),
                child: const Center(
                  child: Text(
                    'Continue to Stripe',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 13),
            const _CheckoutPrivacyNote(),
          ],
        ),
      ),
    ),
  );
}

class _CheckoutFlowRail extends StatelessWidget {
  final bool stripeReady;
  final bool stripeStarted;
  final bool confirmed;

  const _CheckoutFlowRail({
    required this.stripeReady,
    required this.stripeStarted,
    required this.confirmed,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Checkout progress: review in Drip, pay securely on Stripe, then return for confirmation',
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: .45),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            const Expanded(
              child: _CheckoutFlowStep(
                number: '1',
                label: 'Review',
                active: true,
              ),
            ),
            _CheckoutFlowConnector(active: stripeReady),
            Expanded(
              child: _CheckoutFlowStep(
                number: '2',
                label: stripeStarted ? 'Stripe open' : 'Stripe',
                active: stripeReady,
              ),
            ),
            _CheckoutFlowConnector(active: confirmed),
            Expanded(
              child: _CheckoutFlowStep(
                number: '3',
                label: 'Confirmed',
                active: confirmed,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CheckoutFlowStep extends StatelessWidget {
  final String number;
  final String label;
  final bool active;

  const _CheckoutFlowStep({
    required this.number,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 27,
        height: 27,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF58A6FF), Color(0xFF6D5DFB)],
                )
              : null,
          color: active
              ? null
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: electricBlue.withValues(alpha: .25),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Text(
          number,
          style: TextStyle(
            color: active ? Colors.white : mutedForeground(context),
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: active ? null : mutedForeground(context),
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _CheckoutFlowConnector extends StatelessWidget {
  final bool active;

  const _CheckoutFlowConnector({required this.active});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    width: 20,
    height: 2,
    margin: const EdgeInsets.only(bottom: 18),
    color: active
        ? electricBlue
        : Theme.of(context).dividerColor.withValues(alpha: .65),
  );
}

class _CheckoutPrivacyNote extends StatelessWidget {
  const _CheckoutPrivacyNote();

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 7,
    runSpacing: 4,
    children: [
      const Icon(Icons.lock_outline_rounded, size: 14, color: muted),
      const Text(
        'Drip never stores card numbers or CVCs',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: muted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      Container(
        width: 3,
        height: 3,
        decoration: const BoxDecoration(color: muted, shape: BoxShape.circle),
      ),
      const Text(
        'Stripe hosted',
        style: TextStyle(
          color: muted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _StripeTrustCard extends StatelessWidget {
  final StripeCheckoutConnectionState connection;
  final Future<void> Function() onRetry;

  const _StripeTrustCard({required this.connection, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final configured = connection == StripeCheckoutConnectionState.ready;
    final (title, message, icon) = switch (connection) {
      StripeCheckoutConnectionState.ready => (
        'Secure Stripe Checkout',
        'Cards and eligible wallet options are handled by Stripe. Shipping details are collected there too.',
        Icons.lock_rounded,
      ),
      StripeCheckoutConnectionState.checking => (
        'Checking Stripe connection',
        'Drip is securely verifying the payment server before enabling checkout.',
        Icons.sync_rounded,
      ),
      StripeCheckoutConnectionState.serverSetupRequired => (
        'Stripe server setup required',
        'The Drip payment server is online, but its Stripe key and Checkout webhook still need to be configured.',
        Icons.key_off_rounded,
      ),
      StripeCheckoutConnectionState.unavailable => (
        'Payment server unavailable',
        'Drip could not verify the secure payment server. Check the connection and try again.',
        Icons.cloud_off_rounded,
      ),
      StripeCheckoutConnectionState.notConfigured => (
        'Stripe isn’t connected',
        'Purchases stay disabled until this build is connected to the public Drip API URL.',
        Icons.link_off_rounded,
      ),
    };
    final retryable =
        connection == StripeCheckoutConnectionState.serverSetupRequired ||
        connection == StripeCheckoutConnectionState.unavailable;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: configured
            ? const LinearGradient(
                colors: [Color(0xFF635BFF), Color(0xFF4C6FFF)],
              )
            : null,
        color: configured
            ? null
            : Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: configured
              ? Colors.white.withValues(alpha: .22)
              : Theme.of(context).dividerColor,
        ),
        boxShadow: configured
            ? [
                BoxShadow(
                  color: const Color(0xFF635BFF).withValues(alpha: .2),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: configured
                  ? Colors.white.withValues(alpha: .18)
                  : electricBlue.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: connection == StripeCheckoutConnectionState.checking
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Icon(icon, color: configured ? Colors.white : electricBlue),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: configured ? Colors.white : null,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: configured
                        ? Colors.white70
                        : mutedForeground(context),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _StripeTrustPill(
                      icon: configured
                          ? Icons.open_in_new_rounded
                          : Icons.lock_outline_rounded,
                      label: configured ? 'STRIPE HOSTED' : 'SAFELY LOCKED',
                      configured: configured,
                    ),
                    _StripeTrustPill(
                      icon: Icons.price_check_rounded,
                      label: 'SERVER-VERIFIED TOTAL',
                      configured: configured,
                    ),
                  ],
                ),
                if (retryable) ...[
                  const SizedBox(height: 7),
                  TextButton.icon(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Check again'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StripeTrustPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool configured;

  const _StripeTrustPill({
    required this.icon,
    required this.label,
    required this.configured,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: configured
          ? Colors.white.withValues(alpha: .12)
          : electricBlue.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: configured
            ? Colors.white.withValues(alpha: .18)
            : electricBlue.withValues(alpha: .14),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 11,
          color: configured ? Colors.white70 : accentForeground(context),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: configured ? Colors.white70 : mutedForeground(context),
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: .45,
          ),
        ),
      ],
    ),
  );
}

class _PendingCheckoutCard extends StatelessWidget {
  final PendingCheckout pending;
  final CheckoutPaymentStatus? status;

  const _PendingCheckoutCard({required this.pending, required this.status});

  @override
  Widget build(BuildContext context) {
    final effective = status ?? CheckoutPaymentStatus.open;
    final (label, icon, color) = switch (effective) {
      CheckoutPaymentStatus.processing => (
        'Payment processing',
        Icons.hourglass_top_rounded,
        const Color(0xFFFFA94D),
      ),
      CheckoutPaymentStatus.paid => (
        'Payment confirmed',
        Icons.check_circle_rounded,
        const Color(0xFF20B486),
      ),
      CheckoutPaymentStatus.expired ||
      CheckoutPaymentStatus.canceled ||
      CheckoutPaymentStatus.failed => (
        'Checkout needs attention',
        Icons.error_outline_rounded,
        const Color(0xFFE75C62),
      ),
      _ => ('Checkout reserved', Icons.timer_outlined, electricBlue),
    };
    final expiry = pending.expiresAt.toLocal();
    final minute = expiry.minute.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  'Items held until ${expiry.hour}:$minute · Order ${pending.orderId}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mutedForeground(context),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StripeQuoteSummary extends StatelessWidget {
  final CheckoutQuote quote;

  const _StripeQuoteSummary({required this.quote});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: .4),
      ),
    ),
    child: Column(
      children: [
        _OrderSummary._totalLine('Merchandise', fromCents(quote.subtotalCents)),
        const SizedBox(height: 8),
        _OrderSummary._totalLine(
          'Buyer protection',
          fromCents(quote.protectionCents),
        ),
        const SizedBox(height: 8),
        _OrderSummary._totalLine('Shipping', fromCents(quote.shippingCents)),
        if (quote.taxCents > 0) ...[
          const SizedBox(height: 8),
          _OrderSummary._totalLine('Tax', fromCents(quote.taxCents)),
        ],
        const Divider(height: 26),
        _OrderSummary._totalLine(
          'Stripe total',
          fromCents(quote.totalCents),
          bold: true,
        ),
      ],
    ),
  );
}

class _InlineCheckoutMessage extends StatelessWidget {
  final String message;

  const _InlineCheckoutMessage({required this.message});

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFE75C62).withValues(alpha: .09),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: const Color(0xFFE75C62).withValues(alpha: .24),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFE75C62),
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );
}
