import 'package:flutter/material.dart';

import 'design_system.dart';
import 'product_detail.dart';
import 'product_model.dart';
import 'sample_data.dart';

class StoryViewPage extends StatelessWidget {
  final SellerStory story;
  const StoryViewPage({super.key, required this.story});

  @override
  Widget build(BuildContext context) {
    final storyProducts = products
        .where((product) => story.productIds.contains(product.id))
        .toList();
    final cover = storyProducts.firstOrNull;
    return Scaffold(
      backgroundColor: ink,
      appBar: AppBar(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        title: Text(story.handle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 35),
        children: [
          Container(
            height: 260,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: const Color(0xFF171717),
              border: Border.all(color: Colors.white24),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cover != null)
                  productImage(cover, fit: BoxFit.cover, cacheWidth: 1200),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: .06),
                        Colors.black.withValues(alpha: .25),
                        Colors.black.withValues(alpha: .92),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .62),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          'CURATED CLOSET · ${cover?.mediaRole.label ?? 'STORY'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        story.accent.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFFFFDFC0),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        story.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          height: 1.04,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${storyProducts.length} pieces curated by ${story.seller}. Tap below to inspect each listing.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Story items',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: storyProducts.length,
            gridDelegate: productGridDelegate,
            itemBuilder: (context, i) => ProductTile(
              item: storyProducts[i],
              onTap: () => Navigator.push(
                context,
                dripRoute(ProductDetail(item: storyProducts[i])),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
