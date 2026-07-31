import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ai_assistant_page.dart';
import 'app_state.dart';
import 'assistant/assistant_models.dart';
import 'design_system.dart';
import 'product_detail.dart';

class WishlistPage extends StatelessWidget {
  const WishlistPage({super.key});

  @override
  Widget build(BuildContext context) => Consumer<AppState>(
    builder: (context, app, _) {
      final saved = app.catalogProducts
          .where((product) => app.favoriteIds.contains(product.id))
          .toList();
      return SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 22, 20, 12),
              sliver: SliverToBoxAdapter(
                child: PageHeader(
                  eyebrow: 'Your collection',
                  title: 'Saved pieces',
                  subtitle:
                      'Keep an eye on favorites before someone else checks out.',
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: electricBlue.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: electricBlue.withValues(alpha: .22),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active_rounded,
                        color: electricBlue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          saved.isEmpty
                              ? 'Tap the heart on any item to build your favorites.'
                              : '${saved.length} saved ${saved.length == 1 ? 'piece is' : 'pieces are'} synced on this device.',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: GlassButton(
                  onTap: () => Navigator.push(
                    context,
                    dripRoute(
                      AiAssistantPage(
                        initialPrompt: saved.isEmpty
                            ? 'Build a complete outfit for me and help me start a saved collection.'
                            : 'Build a complete outfit from my saved pieces when possible, and fill any missing category with a live listing.',
                        entryPoint: AssistantEntryPoint.saved,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: electricBlue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              saved.isEmpty
                                  ? 'Build my first fit'
                                  : 'Build a fit from saved pieces',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Drip checks current availability before recommending',
                              style: TextStyle(color: muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
            if (saved.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(50),
                  child: Center(
                    child: Text(
                      'No favorites yet. Start saving your best finds.',
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 115),
                sliver: SliverGrid.builder(
                  itemCount: saved.length,
                  gridDelegate: productGridDelegate,
                  itemBuilder: (_, i) => ProductTile(
                    item: saved[i],
                    onTap: () => Navigator.push(
                      context,
                      dripRoute(ProductDetail(item: saved[i])),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
