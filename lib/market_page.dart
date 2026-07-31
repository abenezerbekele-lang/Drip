import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'design_system.dart';
import 'image_search_page.dart';
import 'product_detail.dart';
import 'product_model.dart';
import 'rankings_page.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  String query = '';
  String mood = 'All';

  final moods = const [
    'All',
    'Trending',
    'Luxury',
    'Basketball',
    'Nike',
    'Adidas',
    'Puma',
    'Balenciaga',
    'Rick Owens',
    'Vans',
    'Designer',
    'Streetwear',
    'Tees',
    'Shirts',
    'Jackets',
    'Hoodies',
    'Pants',
    'Accessories',
    'Outfits',
  ];

  List<Product> visible(List<Product> catalog) => catalog.where((product) {
    final search = product.matches(query);
    final filtered = switch (mood) {
      'All' => true,
      'Trending' => product.price < 90,
      'Luxury' => product.tags.contains('luxury'),
      'Basketball' => product.tags.contains('basketball'),
      'Nike' => product.brand == 'Nike',
      'Adidas' => product.brand == 'Adidas',
      'Puma' => product.brand == 'Puma',
      'Balenciaga' => product.brand == 'Balenciaga',
      'Rick Owens' => product.brand == 'Rick Owens',
      'Vans' => product.brand == 'Vans',
      'Designer' => product.tags.contains('designer'),
      'Streetwear' => product.tags.contains('streetwear'),
      'Tees' => product.category == 'T-Shirts',
      'Shirts' => product.category == 'Shirts',
      'Jackets' => product.category == 'Jackets',
      'Hoodies' => product.category == 'Hoodies',
      'Pants' => product.category == 'Pants',
      'Accessories' => product.category == 'Accessories',
      'Outfits' => product.category == 'Outfits',
      _ => true,
    };
    return search && filtered;
  }).toList();

  @override
  Widget build(BuildContext context) {
    final items = visible(context.watch<AppState>().catalogProducts);
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            sliver: SliverList.list(
              children: [
                const PageHeader(
                  eyebrow: 'Discover',
                  title: 'The market',
                  subtitle:
                      'Search shoes, designer brands, streetwear layers, and luxury tees under \$100.',
                ),
                const SizedBox(height: 18),
                TextField(
                  onChanged: (value) => setState(() => query = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Try “Vans”, “Rick Owens”, “cargos”, or “Puma”',
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _trend(
                        context,
                        Icons.image_search_rounded,
                        'Image search',
                        'Find similar',
                        const Color(0xFF386BA8),
                        () => Navigator.push(
                          context,
                          dripRoute(const ImageSearchPage()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _trend(
                        context,
                        Icons.emoji_events_rounded,
                        'Top shoppers',
                        'Rank 1–100',
                        const Color(0xFF654DAA),
                        () => Navigator.push(
                          context,
                          dripRoute(const RankingsPage()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const SectionHeading('Shop by mood'),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: moods.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 9),
                    itemBuilder: (_, i) => GlassButton(
                      selected: mood == moods[i],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 11,
                      ),
                      onTap: () => setState(() => mood = moods[i]),
                      child: Text(
                        moods[i],
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SectionHeading('Most wanted', action: '${items.length} found'),
              ],
            ),
          ),
          if (items.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 40, 30, 130),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 42,
                      color: muted.withValues(alpha: .8),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Nothing matches that search',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Try another brand, category, or mood.',
                      style: TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 115),
              sliver: SliverGrid.builder(
                itemCount: items.length,
                gridDelegate: productGridDelegate,
                itemBuilder: (_, i) => ProductTile(
                  item: items[i],
                  onTap: () => Navigator.push(
                    context,
                    dripRoute(ProductDetail(item: items[i])),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Widget _trend(
    BuildContext context,
    IconData icon,
    String title,
    String count,
    Color color,
    VoidCallback onTap,
  ) => Semantics(
    button: true,
    label: '$title, $count',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(23),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(23),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, ink],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iceBlue),
              const SizedBox(height: 36),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              Text(
                count,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
