import 'package:flutter/material.dart';

import 'design_system.dart';
import 'sample_data.dart';

class RankingsPage extends StatelessWidget {
  const RankingsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Top shoppers')),
    body: SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(28, 12, 28, 18),
            sliver: SliverToBoxAdapter(
              child: PageHeader(
                eyebrow: 'Leaderboard',
                title: 'Top 100 shoppers',
                subtitle:
                    'A community rank for customers who spend the most on the app.',
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 35),
            sliver: SliverList.builder(
              itemCount: topShoppers.length,
              itemBuilder: (context, index) {
                final shopper = topShoppers[index];
                return _RankTile(
                  rank: shopper.rank,
                  name: shopper.name,
                  handle: shopper.handle,
                  orders: shopper.orders,
                  spent: shopper.spent,
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _RankTile extends StatelessWidget {
  final int rank;
  final String name;
  final String handle;
  final int orders;
  final double spent;

  const _RankTile({
    required this.rank,
    required this.name,
    required this.handle,
    required this.orders,
    required this.spent,
  });

  @override
  Widget build(BuildContext context) {
    final topThree = rank <= 3;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .96, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : Duration(milliseconds: 180 + (rank.clamp(1, 10).toInt() * 25)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: topThree
              ? electricBlue.withValues(alpha: .11)
              : Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: topThree
                ? electricBlue.withValues(alpha: .2)
                : Theme.of(context).dividerColor.withValues(alpha: .2),
          ),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                DripAvatar(label: name, size: 52, live: topThree),
                Positioned(
                  left: -5,
                  top: -5,
                  child: Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      color: topThree ? electricBlue : ink,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$handle · $orders orders',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${spent.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: electricBlue,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  topThree ? 'hot streak' : 'shopper',
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
