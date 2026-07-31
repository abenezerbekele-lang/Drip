import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ai_assistant_page.dart';
import 'app_state.dart';
import 'assistant/assistant_models.dart';
import 'commerce_model.dart';
import 'design_system.dart';
import 'payments/payments.dart';

class SellerDashboardPage extends StatelessWidget {
  const SellerDashboardPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Seller Studio',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: Consumer<AppState>(
      builder: (context, app, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: [
          _StudioHeader(pro: app.sellerPro, demo: app.demoSellerMode),
          const SizedBox(height: 12),
          GlassButton(
            onTap: () => Navigator.push(
              context,
              dripRoute(
                AiAssistantPage(
                  initialPrompt:
                      'Review my Seller Studio. I have ${app.sellerLiveListings} live listings and ${app.sellerSoldListings} sold listings. Give me the strongest truthful next step for improving my listings and sales.',
                  entryPoint: AssistantEntryPoint.seller,
                ),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: electricBlue),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ask the Seller Concierge',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Listing guidance, displayed fees, and seller tools',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (app.demoSellerMode)
            _PayoutCard(
              available: app.availablePayout,
              onRequest: app.availablePayout > 0
                  ? () => _confirmPayout(context, app)
                  : null,
            )
          else
            _StripeConnectCard(localEarnings: app.availablePayout),
          const SizedBox(height: 18),
          _KpiGrid(app: app),
          const SizedBox(height: 26),
          _SalesPulse(orders: app.sellerOrders),
          const SizedBox(height: 26),
          _BusinessModelCard(app: app),
          const SizedBox(height: 18),
          _ProCard(app: app),
          const SizedBox(height: 28),
          SectionHeading(
            'Your listings',
            action: '${app.sellerListings.length} total',
          ),
          const SizedBox(height: 10),
          if (app.sellerListings.isEmpty)
            const _EmptyPanel(
              icon: Icons.add_photo_alternate_rounded,
              title: 'Your storefront is ready',
              message:
                  'Publish a listing from the Sell tab and it will appear here with live performance data.',
            )
          else
            ...app.sellerListings.map(
              (listing) => Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: _ListingRow(
                  listing: listing,
                  onBoost: listing.status == ListingStatus.live
                      ? () => _showBoostSheet(context, app, listing)
                      : null,
                  onToggleStatus: listing.status != ListingStatus.sold
                      ? () => app.toggleListingPaused(listing.product.id)
                      : null,
                  onDemoSale: listing.status == ListingStatus.live
                      ? () => _confirmDemoSale(context, app, listing)
                      : null,
                ),
              ),
            ),
          const SizedBox(height: 18),
          SectionHeading(
            'Recent seller orders',
            action: '${app.sellerOrders.length} orders',
          ),
          const SizedBox(height: 10),
          if (app.sellerOrders.isEmpty)
            const _EmptyPanel(
              icon: Icons.local_shipping_outlined,
              title: 'No seller orders yet',
              message:
                  'Completed demo purchases for your listings will create an order and payout record here.',
            )
          else
            _OrdersPanel(
              orders: app.sellerOrders,
              onAdvance: app.advanceSellerOrder,
            ),
          const SizedBox(height: 18),
          _DataBoundaryNote(demo: app.demoSellerMode),
        ],
      ),
    ),
  );

  static Future<void> _confirmPayout(BuildContext context, AppState app) async {
    final amount = app.availablePayout;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.account_balance_wallet_rounded),
        title: const Text('Request demo payout?'),
        content: Text(
          '\$${amount.toStringAsFixed(2)} will move from available to paid '
          'in this on-device ledger. No bank transfer occurs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Request payout'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    app.requestPayout();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Demo payout of \$${amount.toStringAsFixed(2)} recorded on this device.',
        ),
      ),
    );
  }

  static Future<void> _showBoostSheet(
    BuildContext context,
    AppState app,
    SellerListing listing,
  ) async {
    final selected = await showModalBottomSheet<BoostPlan>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            2,
            20,
            20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Boost this listing',
                style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                listing.product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: mutedForeground(sheetContext)),
              ),
              const SizedBox(height: 8),
              const _DemoLabel(label: 'On this device · no charge is made'),
              const SizedBox(height: 18),
              _BoostOption(
                icon: Icons.bolt_rounded,
                title: BoostPlan.oneDay.label,
                subtitle:
                    'A short discovery lift. Pro includes three 24-hour credits each month.',
                priceLabel: app.sellerPro && app.boostCredits > 0
                    ? 'Use 1 credit'
                    : '\$${BoostPlan.oneDay.price.toStringAsFixed(2)}',
                onTap: () => Navigator.pop(sheetContext, BoostPlan.oneDay),
              ),
              const SizedBox(height: 10),
              _BoostOption(
                icon: Icons.rocket_launch_rounded,
                title: BoostPlan.sevenDays.label,
                subtitle:
                    'A full week of promoted placement for an important drop.',
                priceLabel: '\$${BoostPlan.sevenDays.price.toStringAsFixed(2)}',
                onTap: () => Navigator.pop(sheetContext, BoostPlan.sevenDays),
              ),
              const SizedBox(height: 10),
              Text(
                'Promoted listings should always be labeled in the market. '
                'This demo records boost revenue locally.',
                style: TextStyle(
                  color: mutedForeground(sheetContext),
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    final usedCredit =
        selected == BoostPlan.oneDay && app.sellerPro && app.boostCredits > 0;
    app.boostListing(listing.product.id, selected);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          usedCredit
              ? '${listing.product.name} is promoted. Pro credit balance updated.'
              : '${listing.product.name} is promoted in this demo.',
        ),
      ),
    );
  }

  static Future<void> _confirmDemoSale(
    BuildContext context,
    AppState app,
    SellerListing listing,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.point_of_sale_rounded),
        title: const Text('Simulate an external buyer?'),
        content: Text(
          '${listing.product.name} will become sold and a seller order will be '
          'created with the active fee policy. This is an on-device demo; no '
          'buyer or payment is created.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Create demo sale'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final order = await app.simulateSellerDemoSale(listing.product.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          order == null
              ? app.commerceError ?? 'The demo sale was not created.'
              : 'Demo sale created · projected payout '
                    '\$${order.sellerPayout.toStringAsFixed(2)}.',
        ),
      ),
    );
  }
}

class _StudioHeader extends StatelessWidget {
  final bool pro;
  final bool demo;

  const _StudioHeader({required this.pro, required this.demo});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: PageHeader(
              eyebrow: 'Your business',
              title: 'Run your shop',
              subtitle:
                  'Price inventory, grow demand, and understand every marketplace dollar.',
            ),
          ),
          if (pro) ...[
            const SizedBox(width: 12),
            const _StatusPill(
              label: 'PRO',
              color: Color(0xFF9A7CFF),
              icon: Icons.workspace_premium_rounded,
            ),
          ],
        ],
      ),
      const SizedBox(height: 12),
      _DemoLabel(
        label: demo
            ? 'On this device · demo projections'
            : 'Signed-in seller workspace',
      ),
    ],
  );
}

class _StripeConnectCard extends StatelessWidget {
  final double localEarnings;

  const _StripeConnectCard({required this.localEarnings});

  @override
  Widget build(BuildContext context) => Consumer<StripeConnectController>(
    builder: (context, connect, _) {
      final snapshot = connect.snapshot;
      if (!connect.loaded && snapshot == null) {
        return _ConnectPanel(
          icon: Icons.sync_rounded,
          title: 'Checking payout setup',
          message: 'Verifying your Stripe connection with Drip…',
          trailing: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );
      }
      if (snapshot == null) {
        return _ConnectPanel(
          icon: Icons.cloud_off_rounded,
          title: 'Payout connection unavailable',
          message:
              connect.error?.publicMessage ??
              'Drip could not verify your Stripe payout status.',
          actionLabel: 'Try again',
          onAction: connect.busy ? null : connect.refresh,
          busy: connect.busy,
        );
      }

      final descriptor = switch (snapshot.status) {
        StripeConnectStatus.notStarted => const _ConnectDescriptor(
          Icons.account_balance_rounded,
          'Connect your Stripe account',
          'Start Stripe-hosted onboarding to enter the business and bank details required for future payouts.',
          'Connect with Stripe',
          StripeConnectAction.onboarding,
        ),
        StripeConnectStatus.onboardingIncomplete => const _ConnectDescriptor(
          Icons.edit_note_rounded,
          'Finish Stripe onboarding',
          'Stripe saved your progress. A few details are still required before capability checks can finish.',
          'Continue setup',
          StripeConnectAction.onboarding,
        ),
        StripeConnectStatus.verificationPending => const _ConnectDescriptor(
          Icons.hourglass_top_rounded,
          'Stripe verification in progress',
          'Stripe is reviewing your information. Drip keeps payout status pending until both capabilities are ready.',
          'Refresh status',
          null,
        ),
        StripeConnectStatus.restricted => const _ConnectDescriptor(
          Icons.error_outline_rounded,
          'Action required on Stripe',
          'Stripe reports missing or updated information. Review the requirements in its secure hosted flow.',
          'Resolve on Stripe',
          StripeConnectAction.onboarding,
        ),
        StripeConnectStatus.ready => const _ConnectDescriptor(
          Icons.verified_rounded,
          'Stripe is connected',
          'Stripe reports transfer and payout capabilities ready. Drip does not initiate automatic seller transfers yet.',
          'Open Stripe dashboard',
          StripeConnectAction.dashboard,
        ),
      };
      Future<bool> Function()? action;
      if (!connect.busy) {
        action = switch (descriptor.action) {
          StripeConnectAction.onboarding => connect.startOnboarding,
          StripeConnectAction.dashboard => connect.openDashboard,
          null => connect.refresh,
        };
      }
      return _ConnectPanel(
        icon: descriptor.icon,
        title: descriptor.title,
        message: descriptor.message,
        actionLabel:
            descriptor.action == StripeConnectAction.dashboard &&
                !snapshot.canOpenDashboard
            ? 'Refresh status'
            : descriptor.actionLabel,
        onAction:
            descriptor.action == StripeConnectAction.dashboard &&
                !snapshot.canOpenDashboard
            ? (connect.busy ? null : connect.refresh)
            : action,
        opensStripe:
            descriptor.action != null &&
            !(descriptor.action == StripeConnectAction.dashboard &&
                !snapshot.canOpenDashboard),
        busy: connect.busy,
        status: snapshot,
        stale: connect.stale,
        error: connect.error?.publicMessage,
        localEarnings: localEarnings,
      );
    },
  );
}

class _ConnectDescriptor {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final StripeConnectAction? action;

  const _ConnectDescriptor(
    this.icon,
    this.title,
    this.message,
    this.actionLabel,
    this.action,
  );
}

class _ConnectPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? trailing;
  final String? actionLabel;
  final Future<bool> Function()? onAction;
  final bool opensStripe;
  final bool busy;
  final StripeConnectSnapshot? status;
  final bool stale;
  final String? error;
  final double? localEarnings;

  const _ConnectPanel({
    required this.icon,
    required this.title,
    required this.message,
    this.trailing,
    this.actionLabel,
    this.onAction,
    this.opensStripe = false,
    this.busy = false,
    this.status,
    this.stale = false,
    this.error,
    this.localEarnings,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _connectAccent(status?.status);
    final mode = status?.livemode == true ? 'Live mode' : 'Test mode';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF11172C),
            Color.lerp(const Color(0xFF1A2450), accent, .2)!,
            const Color(0xFF09111F),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: .52)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .14),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -55,
            top: -70,
            child: ExcludeSemantics(
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: .25),
                      accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(21),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: accent.withValues(alpha: .34),
                        ),
                      ),
                      child: Icon(Icons.link_rounded, color: accent, size: 17),
                    ),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Text(
                        'STRIPE CONNECT',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.35,
                        ),
                      ),
                    ),
                    if (status != null) _ConnectModeBadge(label: mode),
                    if (trailing != null) ...[
                      const SizedBox(width: 10),
                      trailing!,
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .12),
                        ),
                      ),
                      child: Icon(icon, color: accent),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            message,
                            style: const TextStyle(
                              color: Color(0xFFC4CBDA),
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (status case final value?) ...[
                  const SizedBox(height: 18),
                  _CapabilityPanel(value: value, accent: accent),
                ],
                if (localEarnings case final amount?) ...[
                  const SizedBox(height: 12),
                  _LocalEarningsPreview(amount: amount),
                ],
                if (stale || error != null) ...[
                  const SizedBox(height: 12),
                  _ConnectNotice(
                    icon: Icons.history_rounded,
                    message: stale
                        ? 'Showing the last server-verified status. ${error ?? 'Refresh to check again.'}'
                        : error!,
                  ),
                ],
                const SizedBox(height: 12),
                const _StripeHostedTrustNote(),
                if (actionLabel != null) ...[
                  const SizedBox(height: 17),
                  SizedBox(
                    width: double.infinity,
                    child: Semantics(
                      container: true,
                      button: true,
                      enabled: onAction != null,
                      label: opensStripe
                          ? '$actionLabel. Opens a secure Stripe-hosted page.'
                          : actionLabel,
                      excludeSemantics: true,
                      child: FilledButton.icon(
                        onPressed: onAction == null ? null : () => onAction!(),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: ink,
                          disabledBackgroundColor: Colors.white24,
                          disabledForegroundColor: Colors.white54,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: busy
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                opensStripe
                                    ? Icons.open_in_new_rounded
                                    : Icons.refresh_rounded,
                                size: 19,
                              ),
                        label: Text(
                          busy ? 'Working securely…' : actionLabel!,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                  if (opensStripe) ...[
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'A fresh, one-time secure link is created when you continue.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatConnectSync(DateTime value) {
    final local = value.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day}/${local.year} at ${local.hour}:$minute';
  }
}

Color _connectAccent(StripeConnectStatus? status) => switch (status) {
  StripeConnectStatus.notStarted => electricBlue,
  StripeConnectStatus.onboardingIncomplete => const Color(0xFFA994FF),
  StripeConnectStatus.verificationPending => const Color(0xFFFFC46B),
  StripeConnectStatus.restricted => const Color(0xFFFF827A),
  StripeConnectStatus.ready => const Color(0xFF43E6AE),
  null => const Color(0xFF8B86FF),
};

class _ConnectModeBadge extends StatelessWidget {
  final String label;

  const _ConnectModeBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final live = label == 'Live mode';
    final color = live ? const Color(0xFF43E6AE) : const Color(0xFFFFC46B);
    return Semantics(
      container: true,
      label: live
          ? 'Stripe live mode'
          : 'Stripe test mode. No live funds are moved.',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: .3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapabilityPanel extends StatelessWidget {
  final StripeConnectSnapshot value;
  final Color accent;

  const _CapabilityPanel({required this.value, required this.accent});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .09)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'ACCOUNT CAPABILITIES',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Icon(Icons.verified_user_outlined, color: accent, size: 15),
          ],
        ),
        const SizedBox(height: 11),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ConnectPill(
              value.transfersReady ? 'Transfers ready' : 'Transfers pending',
              value.transfersReady,
            ),
            _ConnectPill(
              value.payoutsReady ? 'Payouts ready' : 'Payouts pending',
              value.payoutsReady,
            ),
          ],
        ),
        if (value.requirementsDue > 0) ...[
          const SizedBox(height: 11),
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFFFFC46B),
                size: 15,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${value.requirementsDue} ${value.requirementsDue == 1 ? 'requirement' : 'requirements'} due on Stripe',
                  style: const TextStyle(
                    color: Color(0xFFFFD89C),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (value.lastSyncedAt case final synced?) ...[
          const SizedBox(height: 10),
          Text(
            'Last checked with the payment server ${_ConnectPanel._formatConnectSync(synced)}',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              height: 1.3,
            ),
          ),
        ],
      ],
    ),
  );
}

class _LocalEarningsPreview extends StatelessWidget {
  final double amount;

  const _LocalEarningsPreview({required this.amount});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Colors.white.withValues(alpha: .09),
          Colors.white.withValues(alpha: .035),
        ],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'LOCAL ACTIVITY PREVIEW',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.05,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          maxLines: 1,
          overflow: TextOverflow.fade,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 25,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Estimated from activity saved on this device. This is not your Stripe balance, a transfer, or a bank payout confirmation.',
          style: TextStyle(color: Colors.white54, fontSize: 9, height: 1.4),
        ),
      ],
    ),
  );
}

class _StripeHostedTrustNote extends StatelessWidget {
  const _StripeHostedTrustNote();

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label:
        'Secure Stripe-hosted account setup. Sensitive bank details are entered on Stripe, not in Drip.',
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF58A6FF).withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF58A6FF).withValues(alpha: .16),
          ),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded, color: iceBlue, size: 16),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Onboarding and account management open on Stripe’s secure hosted pages. Enter sensitive bank details there—not in Drip.',
                style: TextStyle(
                  color: Color(0xFFB8CBE3),
                  fontSize: 9,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ConnectNotice extends StatelessWidget {
  final IconData icon;
  final String message;

  const _ConnectNotice({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: const Color(0xFFFFC46B), size: 16),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          message,
          style: const TextStyle(
            color: Color(0xFFFFD89C),
            fontSize: 10,
            height: 1.35,
          ),
        ),
      ),
    ],
  );
}

class _ConnectPill extends StatelessWidget {
  final String label;
  final bool ready;

  const _ConnectPill(this.label, this.ready);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: (ready ? const Color(0xFF2EE6A6) : Colors.white).withValues(
        alpha: .12,
      ),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: .14)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ready ? Icons.check_circle_rounded : Icons.schedule_rounded,
          color: ready ? const Color(0xFF8BFFD5) : Colors.white54,
          size: 13,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: ready ? const Color(0xFF8BFFD5) : Colors.white70,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _PayoutCard extends StatelessWidget {
  final double available;
  final VoidCallback? onRequest;

  const _PayoutCard({required this.available, required this.onRequest});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(21),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF285A95), Color(0xFF132640), Color(0xFF10182B)],
      ),
      border: Border.all(color: iceBlue.withValues(alpha: .34)),
      boxShadow: [
        BoxShadow(
          color: electricBlue.withValues(alpha: .16),
          blurRadius: 30,
          offset: const Offset(0, 16),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.account_balance_wallet_rounded, color: iceBlue),
            SizedBox(width: 9),
            Text(
              'AVAILABLE PAYOUT',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        Text(
          '\$${available.toStringAsFixed(2)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'After marketplace fees · local ledger balance',
          style: TextStyle(color: Colors.white60, fontSize: 11),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onRequest,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: ink,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.arrow_outward_rounded, size: 19),
            label: Text(
              available > 0 ? 'Request demo payout' : 'No payout available',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    ),
  );
}

class _KpiGrid extends StatelessWidget {
  final AppState app;

  const _KpiGrid({required this.app});

  @override
  Widget build(BuildContext context) {
    final liveListings = app.sellerListings
        .where((listing) => listing.status == ListingStatus.live)
        .length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 11) / columns;
        return Wrap(
          spacing: 11,
          runSpacing: 11,
          children: [
            _KpiTile(
              width: width,
              icon: Icons.inventory_2_rounded,
              value: '$liveListings',
              label: 'Live listings',
              accent: electricBlue,
            ),
            _KpiTile(
              width: width,
              icon: Icons.trending_up_rounded,
              value: '\$${app.sellerGrossSales.toStringAsFixed(0)}',
              label: 'Gross sales',
              accent: const Color(0xFF2EE6A6),
            ),
            _KpiTile(
              width: width,
              icon: Icons.savings_rounded,
              value: '\$${app.sellerNetEarnings.toStringAsFixed(0)}',
              label: 'Net earnings',
              accent: const Color(0xFFFFB86B),
            ),
            _KpiTile(
              width: width,
              icon: Icons.speed_rounded,
              value: _formatPercent(app.sellerSellThrough),
              label: 'Sell-through',
              accent: const Color(0xFF9A7CFF),
            ),
          ],
        );
      },
    );
  }

  static String _formatPercent(double value) {
    final percent = value > 1 ? value : value * 100;
    return '${percent.round()}%';
  }
}

class _KpiTile extends StatelessWidget {
  final double width;
  final IconData icon;
  final String value;
  final String label;
  final Color accent;

  const _KpiTile({
    required this.width,
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(21),
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: .45),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: accent, size: 19),
        ),
        const SizedBox(height: 15),
        Text(
          value,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: mutedForeground(context), fontSize: 11),
        ),
      ],
    ),
  );
}

class _SalesPulse extends StatelessWidget {
  final List<MarketplaceOrder> orders;

  const _SalesPulse({required this.orders});

  @override
  Widget build(BuildContext context) {
    final days = _buildDays(orders);
    final peak = days.fold<double>(
      0,
      (highest, day) => day.amount > highest ? day.amount : highest,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          '7-day sales pulse',
          action: peak == 0 ? 'No demo orders' : 'Net payout',
        ),
        const SizedBox(height: 10),
        Container(
          height: 190,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: .45),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: days
                .map(
                  (day) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (day.amount > 0)
                            Text(
                              '\$${day.amount.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: electricBlue,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            )
                          else
                            const SizedBox(height: 11),
                          const SizedBox(height: 5),
                          Flexible(
                            child: FractionallySizedBox(
                              heightFactor: peak == 0
                                  ? .06
                                  : (.10 + .90 * day.amount / peak).clamp(
                                      .10,
                                      1,
                                    ),
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: 18,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: day.amount > 0
                                        ? const [
                                            Color(0xFF286CBD),
                                            Color(0xFF7CC8FF),
                                          ]
                                        : [
                                            muted.withValues(alpha: .15),
                                            muted.withValues(alpha: .28),
                                          ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            day.label,
                            style: TextStyle(
                              color: mutedForeground(context),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  static List<_DaySales> _buildDays(List<MarketplaceOrder> orders) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(7, (index) {
      final day = today.subtract(Duration(days: 6 - index));
      final amount = orders
          .where((order) {
            final created = order.createdAt.toLocal();
            return created.year == day.year &&
                created.month == day.month &&
                created.day == day.day;
          })
          .fold<double>(0, (sum, order) => sum + order.sellerPayout);
      return _DaySales(_weekday(day.weekday), amount);
    });
  }

  static String _weekday(int weekday) =>
      const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][weekday - 1];
}

class _DaySales {
  final String label;
  final double amount;

  const _DaySales(this.label, this.amount);
}

class _BusinessModelCard extends StatelessWidget {
  final AppState app;

  const _BusinessModelCard({required this.app});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: Theme.of(context).brightness == Brightness.dark
          ? const LinearGradient(colors: [Color(0xFF182947), Color(0xFF0C1526)])
          : const LinearGradient(
              colors: [Color(0xFFF8FBFF), Color(0xFFE4EFFF)],
            ),
      border: Border.all(color: electricBlue.withValues(alpha: .22)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: electricBlue.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.insights_rounded, color: electricBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Marketplace revenue engine',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'Transparent economics for every side of the market',
                    style: TextStyle(
                      color: mutedForeground(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _RevenueRule(
          icon: Icons.sell_rounded,
          title: 'Seller fee',
          value: app.sellerPro ? '7% Pro' : '10% Basic',
          detail:
              'A minimum \$1 fee. Pro lowers the rate for higher-volume shops.',
        ),
        const SizedBox(height: 10),
        const _RevenueRule(
          icon: Icons.shield_rounded,
          title: 'Buyer protection',
          value: '4% + \$0.99',
          detail: 'Included at checkout, with a \$1.49 minimum and \$4.99 cap.',
        ),
        const SizedBox(height: 10),
        const _RevenueRule(
          icon: Icons.bolt_rounded,
          title: 'Growth products',
          value: '\$1.99–\$9.99',
          detail: 'Optional boosts and Pro create repeatable seller revenue.',
        ),
        const SizedBox(height: 17),
        Divider(color: Theme.of(context).dividerColor.withValues(alpha: .5)),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 470;
            final metrics = [
              _ModelMetric(
                'Platform revenue',
                '\$${app.platformRevenue.toStringAsFixed(2)}',
              ),
              _ModelMetric(
                'Contribution',
                '\$${app.contributionEstimate.toStringAsFixed(2)}',
              ),
              _ModelMetric(
                'Growth revenue',
                '\$${(app.boostRevenue + app.subscriptionRevenue).toStringAsFixed(2)}',
              ),
            ];
            if (compact) {
              return Column(
                children: metrics
                    .map(
                      (metric) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ModelMetricRow(metric: metric),
                      ),
                    )
                    .toList(),
              );
            }
            return Row(
              children: metrics
                  .map(
                    (metric) =>
                        Expanded(child: _ModelMetricColumn(metric: metric)),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 5),
        Text(
          'Contribution is a demo estimate after processing, a 1% loss reserve, '
          'and support cost. It is not an accounting statement.',
          style: TextStyle(
            color: mutedForeground(context),
            fontSize: 10,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class _RevenueRule extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String detail;

  const _RevenueRule({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: electricBlue.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: accentForeground(context), size: 17),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: accentForeground(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: TextStyle(
                color: mutedForeground(context),
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ModelMetric {
  final String label;
  final String value;

  const _ModelMetric(this.label, this.value);
}

class _ModelMetricColumn extends StatelessWidget {
  final _ModelMetric metric;

  const _ModelMetricColumn({required this.metric});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        metric.value,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
      Text(
        metric.label,
        style: TextStyle(color: mutedForeground(context), fontSize: 9),
      ),
    ],
  );
}

class _ModelMetricRow extends StatelessWidget {
  final _ModelMetric metric;

  const _ModelMetricRow({required this.metric});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          metric.label,
          style: TextStyle(color: mutedForeground(context), fontSize: 11),
        ),
      ),
      Text(metric.value, style: const TextStyle(fontWeight: FontWeight.w900)),
    ],
  );
}

class _ProCard extends StatelessWidget {
  final AppState app;

  const _ProCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final active = app.sellerPro;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A3E9A), Color(0xFF202B57), Color(0xFF111A2E)],
        ),
        border: Border.all(
          color: const Color(0xFFCEB9FF).withValues(alpha: .4),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8D6AFF).withValues(alpha: .15),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFFE2D7FF),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Drip Pro',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _StatusPill(
                label: active ? 'ACTIVE' : '\$9.99 / MO',
                color: const Color(0xFFCEB9FF),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Lower your seller fee from 10% to 7%, unlock performance insights, '
            'and get three 24-hour boost credits each month.',
            style: TextStyle(color: Colors.white70, height: 1.45, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const Icon(Icons.calculate_rounded, color: iceBlue, size: 19),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    active
                        ? '${app.boostCredits} monthly boost credits remaining'
                        : 'Fee savings break even near \$333 in monthly sales',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                app.setSellerPro(!active);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      active
                          ? 'Pro turned off in this demo.'
                          : 'Pro activated on this device. No payment was made.',
                    ),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF35245E),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                active ? 'Turn off demo Pro' : 'Activate demo Pro',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Local product simulation · no subscription is created',
              style: TextStyle(color: Colors.white54, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingRow extends StatelessWidget {
  final SellerListing listing;
  final VoidCallback? onBoost;
  final VoidCallback? onToggleStatus;
  final VoidCallback? onDemoSale;

  const _ListingRow({
    required this.listing,
    required this.onBoost,
    required this.onToggleStatus,
    required this.onDemoSale,
  });

  @override
  Widget build(BuildContext context) {
    final status = switch (listing.status) {
      ListingStatus.live => ('LIVE', const Color(0xFF2EE6A6)),
      ListingStatus.sold => ('SOLD', electricBlue),
      ListingStatus.paused => ('PAUSED', const Color(0xFFFFB86B)),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: .45),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: SizedBox(
              width: 75,
              height: 84,
              child: productImage(listing.product, cacheWidth: 240),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _StatusPill(label: status.$1, color: status.$2),
                    if (listing.isPromoted) ...[
                      const SizedBox(width: 6),
                      const _StatusPill(
                        label: 'PROMOTED',
                        color: Color(0xFF9A7CFF),
                        icon: Icons.bolt_rounded,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  listing.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '\$${listing.product.price.toStringAsFixed(0)} · '
                  '${listing.createdByUser ? 'Your listing' : 'Demo inventory'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mutedForeground(context),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(
                      Icons.visibility_rounded,
                      size: 13,
                      color: muted,
                    ),
                    const SizedBox(width: 4),
                    Text('${listing.views}', style: _smallMetricStyle),
                    const SizedBox(width: 11),
                    const Icon(Icons.bookmark_rounded, size: 13, color: muted),
                    const SizedBox(width: 4),
                    Text('${listing.saves}', style: _smallMetricStyle),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onBoost != null)
                IconButton.filledTonal(
                  tooltip: listing.isPromoted
                      ? 'Extend boost'
                      : 'Boost listing',
                  onPressed: onBoost,
                  icon: const Icon(Icons.bolt_rounded, size: 19),
                ),
              if (onToggleStatus != null || onDemoSale != null)
                PopupMenuButton<String>(
                  tooltip: 'Listing actions',
                  onSelected: (value) {
                    if (value == 'status') onToggleStatus?.call();
                    if (value == 'sale') onDemoSale?.call();
                  },
                  itemBuilder: (context) => [
                    if (onToggleStatus != null)
                      PopupMenuItem(
                        value: 'status',
                        child: Text(
                          listing.status == ListingStatus.paused
                              ? 'Reactivate listing'
                              : 'Pause listing',
                        ),
                      ),
                    if (onDemoSale != null)
                      const PopupMenuItem(
                        value: 'sale',
                        child: Text('Simulate buyer sale'),
                      ),
                  ],
                  icon: const Icon(Icons.more_horiz_rounded, size: 20),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static const _smallMetricStyle = TextStyle(
    color: muted,
    fontSize: 10,
    fontWeight: FontWeight.w700,
  );
}

class _OrdersPanel extends StatelessWidget {
  final List<MarketplaceOrder> orders;
  final ValueChanged<String> onAdvance;

  const _OrdersPanel({required this.orders, required this.onAdvance});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: .45),
      ),
    ),
    child: Column(
      children: orders.take(5).toList().asMap().entries.map((entry) {
        final order = entry.value;
        final isLast = entry.key == orders.take(5).length - 1;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: [
                  Container(
                    width: 41,
                    height: 41,
                    decoration: BoxDecoration(
                      color: electricBlue.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.local_shipping_rounded,
                      color: electricBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.productName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_prettyStatus(order.status)} · ${_shortDate(order.createdAt)} · '
                          'Fee \$${order.sellerFee.toStringAsFixed(2)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mutedForeground(context),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '+\$${order.sellerPayout.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Color(0xFF2FBF88),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '#${order.id.length > 8 ? order.id.substring(order.id.length - 8) : order.id}',
                            style: TextStyle(
                              color: mutedForeground(context),
                              fontSize: 8,
                            ),
                          ),
                        ],
                      ),
                      if (order.status != OrderStatus.delivered) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: order.status == OrderStatus.placed
                              ? 'Mark shipped'
                              : 'Mark delivered',
                          onPressed: () => onAdvance(order.id),
                          icon: Icon(
                            order.status == OrderStatus.placed
                                ? Icons.local_shipping_outlined
                                : Icons.inventory_rounded,
                            size: 18,
                            color: electricBlue,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (!isLast)
              Divider(
                height: 1,
                indent: 67,
                color: Theme.of(context).dividerColor.withValues(alpha: .38),
              ),
          ],
        );
      }).toList(),
    ),
  );

  static String _prettyStatus(OrderStatus status) => switch (status) {
    OrderStatus.placed => 'Ready to ship',
    OrderStatus.shipped => 'Shipped',
    OrderStatus.delivered => 'Delivered',
  };

  static String _shortDate(DateTime value) {
    final local = value.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}';
  }
}

class _BoostOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String priceLabel;
  final VoidCallback onTap;

  const _BoostOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.priceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: .5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: electricBlue.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: electricBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: mutedForeground(context),
                      fontSize: 10,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              priceLabel,
              style: TextStyle(
                color: accentForeground(context),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: muted),
          ],
        ),
      ),
    ),
  );
}

class _EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: .45),
      ),
    ),
    child: Column(
      children: [
        Icon(icon, color: muted, size: 34),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: mutedForeground(context),
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _StatusPill({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .28)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: .7,
          ),
        ),
      ],
    ),
  );
}

class _DemoLabel extends StatelessWidget {
  final String label;

  const _DemoLabel({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: electricBlue.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: electricBlue.withValues(alpha: .18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.devices_rounded, color: electricBlue, size: 13),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: accentForeground(context),
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _DataBoundaryNote extends StatelessWidget {
  final bool demo;

  const _DataBoundaryNote({required this.demo});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainer.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: .35),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: muted, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            demo
                ? 'Seller Studio is a working on-device business sandbox. A production '
                      'launch connects this interface to verified accounts, payment rails, '
                      'tax reporting, shipping events, and a server-side ledger.'
                : 'Stripe connection status is verified by Drip’s server. Listings, '
                      'earnings previews, Pro, boosts, and fulfillment controls on this '
                      'screen remain device-local until their server workflows are connected.',
            style: TextStyle(
              color: mutedForeground(context),
              fontSize: 10,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );
}
