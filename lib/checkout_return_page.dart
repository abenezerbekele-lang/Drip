import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'commerce_model.dart';
import 'design_system.dart';
import 'payments/payments.dart';

/// Safe landing screen for Stripe's success URL.
///
/// The presence of this route never means payment succeeded. It always asks
/// Drip's backend for the webhook-confirmed order state before showing success.
class CheckoutReturnPage extends StatefulWidget {
  final String checkoutSessionId;
  final VoidCallback onDone;

  const CheckoutReturnPage({
    super.key,
    required this.checkoutSessionId,
    required this.onDone,
  });

  @override
  State<CheckoutReturnPage> createState() => _CheckoutReturnPageState();
}

class _CheckoutReturnPageState extends State<CheckoutReturnPage> {
  CheckoutStatusSnapshot? snapshot;
  bool checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() => checking = true);
    final result = await context.read<AppState>().refreshStripeCheckout(
      checkoutSessionId: widget.checkoutSessionId,
    );
    if (!mounted) return;
    setState(() {
      snapshot = result;
      checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final state = snapshot?.status;
    final paid = snapshot?.isPaid == true;
    final (icon, color, title, message) = checking
        ? (
            Icons.sync_rounded,
            electricBlue,
            'Confirming payment',
            'Waiting for Stripe’s verified payment status…',
          )
        : paid
        ? (
            Icons.check_circle_rounded,
            const Color(0xFF20B486),
            'Payment confirmed',
            'Your order is paid and ready for the seller.',
          )
        : switch (state) {
            CheckoutPaymentStatus.processing => (
              Icons.hourglass_top_rounded,
              const Color(0xFFFFA94D),
              'Payment processing',
              'Stripe is still processing this payment. Your order is not marked paid yet.',
            ),
            CheckoutPaymentStatus.expired || CheckoutPaymentStatus.canceled => (
              Icons.timer_off_outlined,
              const Color(0xFFE75C62),
              'Checkout ended',
              'No confirmed payment was found. Your cart can be checked out again.',
            ),
            CheckoutPaymentStatus.failed => (
              Icons.error_outline_rounded,
              const Color(0xFFE75C62),
              'Payment not completed',
              'Stripe did not confirm this payment. No order was fulfilled.',
            ),
            _ => (
              Icons.shield_outlined,
              electricBlue,
              'Still checking',
              app.commerceError ??
                  'Payment has not been confirmed. You can safely check again.',
            ),
          };
    final quote = snapshot?.confirmation?.quote ?? snapshot?.quote;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withValues(alpha: .5),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        shape: BoxShape.circle,
                      ),
                      child: checking
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: color,
                              ),
                            )
                          : Icon(icon, color: color, size: 36),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: mutedForeground(context),
                        height: 1.45,
                      ),
                    ),
                    if (quote != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: electricBlue.withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Column(
                          children: [
                            _returnLine(
                              'Order',
                              snapshot?.orderId ?? 'Pending',
                            ),
                            const SizedBox(height: 8),
                            _returnLine(
                              'Total',
                              '\$${fromCents(quote.totalCents).toStringAsFixed(2)} ${quote.currency.toUpperCase()}',
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (!paid &&
                        state != CheckoutPaymentStatus.expired &&
                        state != CheckoutPaymentStatus.canceled &&
                        state != CheckoutPaymentStatus.failed)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: checking ? null : _check,
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('Check again'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: checking ? null : widget.onDone,
                        child: Text(
                          paid ? 'Continue to Drip' : 'Return to Drip',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'A browser redirect alone never creates an order.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _returnLine(String label, String value) => Row(
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 11)),
      const Spacer(),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        ),
      ),
    ],
  );
}
