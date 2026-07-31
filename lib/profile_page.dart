import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ai_assistant_page.dart';
import 'app_state.dart';
import 'assistant/assistant_models.dart';
import 'auth/auth_controller.dart';
import 'cart_page.dart';
import 'design_system.dart';
import 'messages_page.dart';
import 'rankings_page.dart';
import 'seller_dashboard_page.dart';

class ProfilePage extends StatelessWidget {
  final VoidCallback onThemeToggle;
  const ProfilePage({super.key, required this.onThemeToggle});

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Consumer2<AuthController, AppState>(
      builder: (context, auth, app, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 115),
        children: [
          Row(
            children: [
              const Text(
                'Your space',
                style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              GlassButton(
                padding: const EdgeInsets.all(11),
                onTap: onThemeToggle,
                child: const Icon(Icons.brightness_6_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(27),
              gradient: const LinearGradient(
                colors: [Color(0xFF1C3F70), panel],
              ),
              border: Border.all(color: iceBlue.withValues(alpha: .35)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    DripAvatar(
                      label: auth.user?.name ?? 'Demo shopper',
                      size: 72,
                      live: auth.isSignedIn,
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.user?.name ?? 'Local demo shopper',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            auth.user?.email ??
                                'No production account connected',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                auth.isSignedIn
                                    ? Icons.verified_user_outlined
                                    : Icons.science_outlined,
                                color: iceBlue,
                                size: 16,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  auth.isSignedIn
                                      ? 'Signed in securely · payout status is server-verified'
                                      : 'Local demo · no account session',
                                  maxLines: 2,
                                  style: const TextStyle(
                                    color: iceBlue,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: Colors.white12),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat('${app.sellerListings.length}', 'Listings'),
                    _Stat('${app.sellerOrders.length}', 'Seller orders'),
                    _Stat(app.sellerPro ? 'Pro' : 'Free', 'Plan'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _SellerStudioCard(
            listingCount: app.sellerListings.length,
            onTap: () =>
                Navigator.push(context, dripRoute(const SellerDashboardPage())),
          ),
          const SizedBox(height: 22),
          const SectionHeading('Shopping overview'),
          Row(
            children: [
              Expanded(
                child: _metric(
                  Icons.shopping_bag_rounded,
                  '${app.cartCount}',
                  'In cart',
                  () => Navigator.push(context, dripRoute(const CartPage())),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _metric(
                  Icons.emoji_events_rounded,
                  '—',
                  'Not ranked',
                  () =>
                      Navigator.push(context, dripRoute(const RankingsPage())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const SectionHeading('Help & community'),
          _setting(
            context,
            Icons.forum_rounded,
            'Messages',
            'Talk to sellers and make offers',
            const MessagesPage(),
          ),
          _setting(
            context,
            Icons.auto_awesome_rounded,
            'Drip Concierge',
            'Outfits, checkout, orders, and selling guidance',
            const AiAssistantPage(entryPoint: AssistantEntryPoint.general),
          ),
          _setting(
            context,
            Icons.emoji_events_rounded,
            'Top shoppers',
            'See the top 100 buyers',
            const RankingsPage(),
          ),
          _setting(
            context,
            Icons.account_balance_wallet_rounded,
            'Orders & cart',
            'Review your bag and protected checkout',
            const CartPage(),
          ),
          const SizedBox(height: 22),
          const SectionHeading('Account'),
          _accountAction(context, auth),
          if (auth.error != null && auth.isSignedIn)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  auth.error!.publicMessage,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  static Widget _metric(
    IconData icon,
    String value,
    String label,
    VoidCallback onTap,
  ) => GlassButton(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: electricBlue),
        const SizedBox(height: 15),
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        Text(label, style: const TextStyle(color: muted, fontSize: 11)),
      ],
    ),
  );

  static Widget _setting(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Widget page,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    onTap: () => Navigator.push(context, dripRoute(page)),
    leading: Container(
      width: 43,
      height: 43,
      decoration: BoxDecoration(
        color: electricBlue.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: electricBlue, size: 21),
    ),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
    ),
    subtitle: Text(
      subtitle,
      style: const TextStyle(color: muted, fontSize: 11),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, color: muted),
  );

  static Widget _accountAction(BuildContext context, AuthController auth) =>
      ListTile(
        key: const Key('profile-sign-out'),
        contentPadding: EdgeInsets.zero,
        enabled: !auth.busy,
        onTap: auth.busy ? null : auth.signOut,
        leading: Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.error.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: auth.busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  auth.isDemo
                      ? Icons.exit_to_app_rounded
                      : Icons.logout_rounded,
                  color: Theme.of(context).colorScheme.error,
                  size: 21,
                ),
        ),
        title: Text(
          auth.isDemo ? 'Leave local demo' : 'Sign out',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        subtitle: Text(
          auth.isDemo
              ? 'Return to account sign in'
              : 'Securely end this account session on Drip',
          style: const TextStyle(color: muted, fontSize: 11),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: muted),
      );
}

class _SellerStudioCard extends StatelessWidget {
  final int listingCount;
  final VoidCallback onTap;

  const _SellerStudioCard({required this.listingCount, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Open Seller Studio',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF173965), Color(0xFF0A1930)],
            ),
            border: Border.all(color: iceBlue.withValues(alpha: .32)),
            boxShadow: [
              BoxShadow(
                color: electricBlue.withValues(alpha: .16),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: iceBlue.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: iceBlue.withValues(alpha: .2)),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: iceBlue,
                  size: 25,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Seller Studio',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: electricBlue,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            child: Text(
                              'BUSINESS',
                              style: TextStyle(
                                color: ink,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .7,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Manage $listingCount ${listingCount == 1 ? 'listing' : 'listings'}, promotions, and payouts',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, color: iceBlue),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    ],
  );
}
