import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'design_system.dart';
import 'product_detail.dart';
import 'product_model.dart';

class ImageSearchPage extends StatefulWidget {
  const ImageSearchPage({super.key});

  @override
  State<ImageSearchPage> createState() => _ImageSearchPageState();
}

class _ImageSearchPageState extends State<ImageSearchPage> {
  bool scanning = false;
  bool scanned = false;

  List<Product> matches(List<Product> catalog) =>
      catalog.where((product) => product.category == 'Shoes').take(12).toList();

  Future<void> scanSample() async {
    if (scanning) return;
    setState(() => scanning = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    setState(() {
      scanning = false;
      scanned = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visualMatches = matches(context.watch<AppState>().catalogProducts);
    return Scaffold(
      appBar: AppBar(title: const Text('Image search')),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
              sliver: SliverList.list(
                children: [
                  const PageHeader(
                    eyebrow: 'Find similar',
                    title: 'Search with a photo',
                    subtitle:
                        'Try a sample scan to preview how visual matching narrows the marketplace.',
                  ),
                  const SizedBox(height: 22),
                  Container(
                    constraints: const BoxConstraints(minHeight: 252),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1C3F70), panel],
                      ),
                      border: Border.all(color: iceBlue.withValues(alpha: .32)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: scanned
                              ? electricBlue
                              : const Color(0xFF244C7C),
                          child: Icon(
                            scanned
                                ? Icons.check_rounded
                                : Icons.image_search_rounded,
                            color: iceBlue,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          scanning
                              ? 'Reading the look…'
                              : scanned
                              ? 'Sample photo matched'
                              : 'Find the closest pieces',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          scanned
                              ? 'Black runner · shape, color, and category'
                              : 'Use a black sneaker sample for this demo scan.',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (scanning)
                          const SizedBox.square(
                            dimension: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: iceBlue,
                            ),
                          )
                        else
                          GlassButton(
                            selected: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 10,
                            ),
                            onTap: scanSample,
                            child: Text(
                              scanned ? 'Scan again' : 'Scan sample photo',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SectionHeading(
                    scanned ? 'Visual matches' : 'Similar items',
                    action: scanned ? '${visualMatches.length} found' : null,
                  ),
                ],
              ),
            ),
            if (!scanned)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 40),
                  child: Text(
                    'Your closest matches will appear here after the sample scan.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedForeground(context)),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 35),
                sliver: SliverGrid.builder(
                  itemCount: visualMatches.length,
                  gridDelegate: productGridDelegate,
                  itemBuilder: (context, i) => ProductTile(
                    item: visualMatches[i],
                    onTap: () => Navigator.push(
                      context,
                      dripRoute(ProductDetail(item: visualMatches[i])),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
