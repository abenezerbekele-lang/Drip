import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ai_assistant_page.dart';
import 'app_state.dart';
import 'assistant/assistant_models.dart';
import 'cart_page.dart';
import 'design_system.dart';
import 'image_search_page.dart';
import 'messages_page.dart';
import 'product_detail.dart';
import 'product_model.dart';
import 'rankings_page.dart';
import 'sample_data.dart' show sellerStories;
import 'story_view_page.dart';

class HomeFeed extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const HomeFeed({super.key, required this.onThemeToggle});

  @override
  State<HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends State<HomeFeed> {
  int selected = 0;
  String query = '';

  final filters = const [
    'All',
    'Nike',
    'Adidas',
    'Puma',
    'Balenciaga',
    'Rick Owens',
    'Vans',
    'Designer',
    'Streetwear',
    'Shoes',
    'Basketball',
    'Running',
    'T-Shirts',
    'Shirts',
    'Jackets',
    'Hoodies',
    'Pants',
    'Accessories',
    'Outfits',
    'Luxury',
    'Under \$50',
  ];

  List<Product> visibleProducts(List<Product> catalog) =>
      catalog.where((product) {
        final matchesSearch = product.matches(query);
        final filter = filters[selected];
        final matchesFilter = switch (filter) {
          'All' => true,
          'Nike' => product.brand.toLowerCase() == 'nike',
          'Adidas' => product.brand.toLowerCase() == 'adidas',
          'Puma' => product.brand.toLowerCase() == 'puma',
          'Balenciaga' => product.brand.toLowerCase() == 'balenciaga',
          'Rick Owens' => product.brand.toLowerCase() == 'rick owens',
          'Vans' => product.brand.toLowerCase() == 'vans',
          'Designer' => product.tags.contains('designer'),
          'Streetwear' => product.tags.contains('streetwear'),
          'Shoes' => product.category == 'Shoes',
          'Basketball' => product.tags.contains('basketball'),
          'Running' => product.tags.contains('running'),
          'T-Shirts' => product.category == 'T-Shirts',
          'Shirts' => product.category == 'Shirts',
          'Jackets' => product.category == 'Jackets',
          'Hoodies' => product.category == 'Hoodies',
          'Pants' => product.category == 'Pants',
          'Accessories' => product.category == 'Accessories',
          'Outfits' => product.category == 'Outfits',
          'Luxury' => product.tags.contains('luxury'),
          'Under \$50' => product.price <= 50,
          _ => true,
        };
        return matchesSearch && matchesFilter;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final catalog = app.catalogProducts;
    final visible = visibleProducts(catalog);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.35;
    Product? spotlight;
    for (final preferAsset in const [true, false]) {
      for (final product in catalog) {
        final purchasable =
            !app.isOwnListing(product) && app.isListingAvailable(product);
        if (purchasable && (!preferAsset || product.isAssetImage)) {
          spotlight = product;
          break;
        }
      }
      if (spotlight != null) break;
    }
    spotlight ??= catalog.isEmpty ? null : catalog.first;

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1380),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final horizontal = wide ? 30.0 : 20.0;
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 0),
                    sliver: SliverList.list(
                      children: [
                        _TopBar(onThemeToggle: widget.onThemeToggle),
                        const SizedBox(height: 18),
                        _SearchCommand(
                          onChanged: (value) => setState(() => query = value),
                          onImageSearch: () => Navigator.push(
                            context,
                            dripRoute(const ImageSearchPage()),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _EntranceReveal(
                          child: _EditorialLead(
                            spotlight: spotlight,
                            onAi: () => Navigator.push(
                              context,
                              dripRoute(
                                const AiAssistantPage(
                                  initialPrompt:
                                      'Build a complete outfit for me under \$150 total.',
                                  entryPoint: AssistantEntryPoint.general,
                                ),
                              ),
                            ),
                            onRanks: () => Navigator.push(
                              context,
                              dripRoute(const RankingsPage()),
                            ),
                            onViewSpotlight: spotlight == null
                                ? null
                                : () => Navigator.push(
                                    context,
                                    dripRoute(ProductDetail(item: spotlight!)),
                                  ),
                            onAskSpotlight: spotlight == null
                                ? null
                                : () => Navigator.push(
                                    context,
                                    dripRoute(
                                      AiAssistantPage(
                                        initialPrompt:
                                            'Build a complete outfit around ${spotlight!.name} under \$150 total.',
                                        entryPoint: AssistantEntryPoint.general,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const _TrustRibbon(),
                        const SizedBox(height: 25),
                        const SectionHeading(
                          'Curated closets',
                          action: 'Shop the stories',
                        ),
                        const SizedBox(height: 10),
                        _StoriesRow(),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 46,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: filters.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 9),
                            itemBuilder: (_, i) => GlassButton(
                              selected: selected == i,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              radius: 16,
                              onTap: () => setState(() => selected = i),
                              child: Text(
                                filters[i],
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SectionHeading(
                          selected == 0 ? 'Fresh for you' : filters[selected],
                          action:
                              '${visible.length} ${visible.length == 1 ? 'piece' : 'pieces'}',
                        ),
                      ],
                    ),
                  ),
                  if (visible.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          24,
                          horizontal,
                          120,
                        ),
                        child: const _EmptySearchState(),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        3,
                        horizontal,
                        wide ? 44 : 115,
                      ),
                      sliver: SliverGrid.builder(
                        itemCount: visible.length,
                        gridDelegate: largeText
                            ? const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 1,
                                childAspectRatio: .78,
                                mainAxisSpacing: 15,
                              )
                            : const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 270,
                                childAspectRatio: .64,
                                crossAxisSpacing: 15,
                                mainAxisSpacing: 15,
                              ),
                        itemBuilder: (_, i) => ProductTile(
                          item: visible[i],
                          onTap: () => Navigator.push(
                            context,
                            dripRoute(ProductDetail(item: visible[i])),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SearchCommand extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final VoidCallback onImageSearch;

  const _SearchCommand({required this.onChanged, required this.onImageSearch});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Search the Drip marketplace',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .22 : .08),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: electricBlue.withValues(alpha: .07),
              blurRadius: 24,
            ),
          ],
        ),
        child: TextField(
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.search_rounded),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 50),
            suffixIcon: Padding(
              padding: const EdgeInsets.all(6),
              child: IconButton.filledTonal(
                tooltip: 'Search with an image',
                icon: const Icon(Icons.center_focus_strong_rounded, size: 19),
                onPressed: onImageSearch,
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  backgroundColor: electricBlue.withValues(
                    alpha: dark ? .16 : .11,
                  ),
                  foregroundColor: accentForeground(context),
                ),
              ),
            ),
            hintText: 'Search Adidas, Puma, Vans, Rick, cargos...',
            hintStyle: TextStyle(
              color: mutedForeground(context).withValues(alpha: .8),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            filled: true,
            fillColor: dark
                ? const Color(0xFF101D31).withValues(alpha: .94)
                : Colors.white.withValues(alpha: .94),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(
                color: dark
                    ? Colors.white.withValues(alpha: .1)
                    : const Color(0xFFDDE7F3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: electricBlue, width: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorialLead extends StatelessWidget {
  final Product? spotlight;
  final VoidCallback onAi;
  final VoidCallback onRanks;
  final VoidCallback? onViewSpotlight;
  final VoidCallback? onAskSpotlight;

  const _EditorialLead({
    required this.spotlight,
    required this.onAi,
    required this.onRanks,
    required this.onViewSpotlight,
    required this.onAskSpotlight,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 850 && spotlight != null;
      final hero = _HeroCard(onAi: onAi, onRanks: onRanks, desktop: desktop);
      if (!desktop) {
        return Column(
          children: [
            hero,
            if (spotlight != null) ...[
              const SizedBox(height: 14),
              _DiscoveryDrop(
                item: spotlight!,
                onView: onViewSpotlight!,
                onAsk: onAskSpotlight!,
              ),
            ],
          ],
        );
      }

      return SizedBox(
        height: 408,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 7, child: hero),
            const SizedBox(width: 15),
            Expanded(
              flex: 4,
              child: _DiscoveryDrop(
                item: spotlight!,
                onView: onViewSpotlight!,
                onAsk: onAskSpotlight!,
                editorialTall: true,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _TrustRibbon extends StatelessWidget {
  const _TrustRibbon();

  static const _items = <(IconData, String, String)>[
    (Icons.lock_rounded, 'STRIPE CHECKOUT', 'Hosted payment'),
    (Icons.auto_awesome_rounded, 'DRIP CONCIERGE', 'Outfit answers'),
    (Icons.verified_user_rounded, 'BUYER PROTECTION', 'Clear order trail'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: .04)
            : Colors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: .08)
              : const Color(0xFFDCE6F2),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 590;
          final children = List.generate(_items.length, (index) {
            final item = _items[index];
            return Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: stack ? 4 : 9,
                  vertical: stack ? 5 : 2,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: electricBlue.withValues(alpha: .11),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        item.$1,
                        size: 16,
                        color: accentForeground(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .65,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: mutedForeground(context),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          });

          if (stack) {
            return Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  Row(children: [children[index]]),
                  if (index != children.length - 1)
                    Divider(
                      height: 1,
                      indent: 44,
                      color: Theme.of(context).dividerColor,
                    ),
                ],
              ],
            );
          }
          return Row(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1)
                  Container(
                    width: 1,
                    height: 31,
                    color: Theme.of(context).dividerColor,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Column(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: electricBlue.withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.manage_search_rounded,
            color: accentForeground(context),
            size: 26,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Nothing in this edit yet',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'Try a brand, category, or price—Nike, jackets, and under \$50 are good places to start.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: mutedForeground(context),
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    ),
  );
}

class _TopBar extends StatelessWidget {
  final VoidCallback onThemeToggle;
  const _TopBar({required this.onThemeToggle});

  @override
  Widget build(BuildContext context) {
    final showLiveEdit =
        MediaQuery.sizeOf(context).width >= 380 &&
        MediaQuery.textScalerOf(context).scale(1) <= 1.25;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Flexible(
                    child: Text(
                      'drip.',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2.4,
                        height: .95,
                      ),
                    ),
                  ),
                  if (showLiveEdit) ...[
                    const SizedBox(width: 9),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: signalGreen.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: signalGreen.withValues(alpha: .28),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 6,
                            height: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: signalGreen,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          SizedBox(width: 5),
                          Text(
                            'LIVE EDIT',
                            style: TextStyle(
                              color: Color(0xFF1C9971),
                              fontSize: 7.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .7,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Independent closets · one sharp edit',
                maxLines: 2,
                style: TextStyle(
                  color: mutedForeground(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .35,
                ),
              ),
            ],
          ),
        ),
        GlassButton(
          padding: const EdgeInsets.all(11),
          radius: 16,
          onTap: () => Navigator.push(context, dripRoute(const MessagesPage())),
          child: const Tooltip(
            message: 'Messages',
            child: Icon(Icons.forum_rounded, size: 20),
          ),
        ),
        const SizedBox(width: 9),
        Consumer<AppState>(
          builder: (context, app, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              GlassButton(
                padding: const EdgeInsets.all(11),
                radius: 16,
                onTap: () =>
                    Navigator.push(context, dripRoute(const CartPage())),
                child: const Tooltip(
                  message: 'Shopping bag',
                  child: Icon(Icons.shopping_bag_rounded, size: 20),
                ),
              ),
              if (app.cartCount > 0)
                Positioned(
                  right: -4,
                  top: -5,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: electricBlue,
                    child: Text(
                      '${app.cartCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 9),
        Consumer<AppState>(
          builder: (context, app, _) => Tooltip(
            message: app.demoSellerMode
                ? 'Local demo profile'
                : app.activeSellerName,
            child: GestureDetector(
              onLongPress: onThemeToggle,
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Your profile is in the You tab.'),
                ),
              ),
              child: DripAvatar(
                label: app.demoSellerMode
                    ? 'Demo shopper'
                    : app.activeSellerName,
                size: 44,
                live: !app.demoSellerMode,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EntranceReveal extends StatelessWidget {
  final Widget child;

  const _EntranceReveal({required this.child});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 720),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 10),
          child: child,
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final VoidCallback onAi;
  final VoidCallback onRanks;
  final bool desktop;

  const _HeroCard({
    required this.onAi,
    required this.onRanks,
    this.desktop = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: desktop ? 408 : 324),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(32),
      color: const Color(0xFF151719),
      border: Border.all(color: Colors.white.withValues(alpha: .12)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .24),
          blurRadius: 34,
          offset: const Offset(0, 18),
        ),
        BoxShadow(
          color: electricBlue.withValues(alpha: .10),
          blurRadius: 38,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: Semantics(
            container: true,
            image: true,
            label:
                'Drip editorial: two friends browsing denim at a night clothing market',
            child: TweenAnimationBuilder<double>(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 1.045, end: 1),
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Image.asset(
                'assets/editorial/drip_night_market_editorial_v3.jpg',
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: const [0, .45, .76, 1],
                colors: [
                  const Color(0xFF05070C).withValues(alpha: .97),
                  const Color(0xFF05070C).withValues(alpha: .82),
                  const Color(0xFF05070C).withValues(alpha: .28),
                  const Color(0xFF05070C).withValues(alpha: .06),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: .52),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 18,
          right: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .38),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .18)),
            ),
            child: const Text(
              '01 / EDIT',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: .85,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 19),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 250),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .48),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .28),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: iceBlue, size: 11),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'DRIP EDITORIAL  ·  NIGHT MARKET',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .85,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 45),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 310),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Find your fit.\nOwn the room.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        height: .98,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.25,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Build from live listings—or ask about colors, care, dress codes, proportions, and the weird style questions too.',
                      style: TextStyle(
                        color: Color(0xFFEAF3FF),
                        fontSize: 11,
                        height: 1.42,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  GlassButton(
                    selected: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    onTap: onAi,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 15),
                        SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            'Ask Drip',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: onRanks,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black.withValues(alpha: .38),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: .34),
                      ),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Top shoppers',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SizedBox(width: 5),
                        Icon(
                          Icons.arrow_outward_rounded,
                          size: 14,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DiscoveryDrop extends StatelessWidget {
  final Product item;
  final VoidCallback onView;
  final VoidCallback onAsk;
  final bool editorialTall;

  const _DiscoveryDrop({
    required this.item,
    required this.onView,
    required this.onAsk,
    this.editorialTall = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final largeText = textScale > 1.45;
    final effectiveTextScale = largeText ? 1.45 : textScale;
    final cardHeight = editorialTall
        ? null
        : largeText
        ? 360.0
        : 174.0 + ((textScale - 1).clamp(0.0, 1.0) * 52).toDouble();
    final price = item.price == item.price.roundToDouble()
        ? item.price.toStringAsFixed(0)
        : item.price.toStringAsFixed(2);

    return Semantics(
      container: true,
      label: 'Discovery drop, ${item.name} by ${item.brand}, $price dollars',
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(effectiveTextScale)),
        child: Container(
          height: cardHeight,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xFF172A47), Color(0xFF090F1B)]
                  : const [Color(0xFFF8FBFF), Color(0xFFE3EEFF)],
            ),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: .13)
                  : const Color(0xFFC7D9F1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .10),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: electricBlue.withValues(alpha: .08),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: editorialTall
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 11, child: _media(context)),
                    Expanded(flex: 9, child: _details(context, price)),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: largeText ? 72 : 120,
                      child: _media(context),
                    ),
                    Expanded(child: _details(context, price)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _media(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Semantics(
        image: true,
        label: '${item.name} catalog image',
        child: productImage(item, cacheWidth: editorialTall ? 760 : 480),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              ink.withValues(alpha: .1),
              ink.withValues(alpha: .72),
            ],
          ),
        ),
      ),
      Positioned(
        left: 12,
        right: 10,
        bottom: 11,
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.mediaRole.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
            ),
            if (editorialTall)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .48),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: .2)),
                ),
                child: Text(
                  item.condition.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .55,
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _details(BuildContext context, String price) => Padding(
    padding: EdgeInsets.fromLTRB(
      editorialTall ? 17 : 15,
      editorialTall ? 16 : 14,
      editorialTall ? 16 : 13,
      editorialTall ? 15 : 13,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: signalGreen,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: signalGreen.withValues(alpha: .5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'DISCOVERY DROP',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accentForeground(context),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: editorialTall ? 8 : 9),
        Text(
          item.name,
          maxLines: editorialTall ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.03,
            letterSpacing: -.25,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${item.brand}  ·  \$$price',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: mutedForeground(context),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: onView,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'View piece',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Ask Drip about this piece',
              onPressed: onAsk,
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            ),
          ],
        ),
      ],
    ),
  );
}

class _StoriesRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<AppState>().catalogProducts;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final rowHeight = 102.0 + ((textScale - 1).clamp(0.0, 1.5) * 18);
    return SizedBox(
      height: rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sellerStories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final story = sellerStories[i];
          Product? cover;
          for (final id in story.productIds) {
            for (final item in catalog) {
              if (item.id == id) {
                cover = item;
                break;
              }
            }
            if (cover != null) break;
          }
          return GestureDetector(
            onTap: () =>
                Navigator.push(context, dripRoute(StoryViewPage(story: story))),
            child: SizedBox(
              width: 82,
              child: Column(
                children: [
                  if (cover == null)
                    DripAvatar(label: story.seller, size: 64)
                  else
                    Container(
                      width: 66,
                      height: 66,
                      padding: const EdgeInsets.all(2.5),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFF0D2A0), Color(0xFF9D4038)],
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).scaffoldBackgroundColor,
                        ),
                        child: ClipOval(
                          child: productImage(cover, cacheWidth: 256),
                        ),
                      ),
                    ),
                  const SizedBox(height: 7),
                  Text(
                    story.seller,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
