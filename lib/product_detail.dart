import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ai_assistant_page.dart';
import 'app_state.dart';
import 'assistant/assistant_models.dart';
import 'cart_page.dart';
import 'commerce_model.dart';
import 'design_system.dart';
import 'messages_page.dart';
import 'product_model.dart';

class ProductDetail extends StatefulWidget {
  final Product item;
  const ProductDetail({super.key, required this.item});

  @override
  State<ProductDetail> createState() => _ProductDetailState();
}

class _ProductDetailState extends State<ProductDetail> {
  late String selectedSize;

  List<String> get availableSizes =>
      widget.item.sizes.isEmpty ? const ['One size'] : widget.item.sizes;

  @override
  void initState() {
    super.initState();
    selectedSize = availableSizes.first;
  }

  void addToCart({bool checkout = false}) {
    final app = context.read<AppState>();
    if (app.isOwnListing(widget.item)) return;
    final added = app.addToCart(widget.item, size: selectedSize);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? '${widget.item.name} added to cart.'
              : app.commerceError ?? 'This item could not be added.',
        ),
      ),
    );
    if (checkout && added) {
      Navigator.push(context, dripRoute(const CartPage()));
    }
  }

  void askDripToStyle() => Navigator.push(
    context,
    dripRoute(
      AiAssistantPage(
        initialPrompt:
            'Build a complete outfit around ${widget.item.name}. I selected size $selectedSize for this piece.',
        entryPoint: AssistantEntryPoint.product,
        focusProductId: widget.item.id,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ownListing = app.isOwnListing(widget.item);
    final available = app.isListingAvailable(widget.item);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: CircleAvatar(
            backgroundColor: ink.withValues(alpha: .75),
            child: BackButton(
              color: Colors.white,
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Consumer<AppState>(
              builder: (context, app, _) {
                final saved = app.isFavorite(widget.item);
                return CircleAvatar(
                  backgroundColor: const Color(0xC007101F),
                  child: IconButton(
                    onPressed: () => app.toggleFavorite(widget.item),
                    icon: Icon(
                      saved
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: saved ? const Color(0xFFFF6B9A) : Colors.white,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Stack(
            children: [
              Hero(
                tag: 'product-image-${widget.item.id}',
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: SizedBox(
                    width: double.infinity,
                    height: 430,
                    child: productImage(widget.item, fit: BoxFit.contain),
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
                        Colors.black.withValues(alpha: .22),
                        Colors.transparent,
                        Colors.black.withValues(alpha: .35),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                bottom: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: .8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_rounded, color: iceBlue, size: 15),
                      SizedBox(width: 6),
                      Text(
                        'BUYER PROTECTION AT CHECKOUT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 35),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: .55),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        widget.item.mediaRole == ProductMediaRole.demoCatalog
                            ? Icons.science_outlined
                            : Icons.photo_camera_outlined,
                        color: accentForeground(context),
                        size: 19,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.mediaRole.label,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .8,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.item.mediaRole.disclosure,
                              style: TextStyle(
                                color: mutedForeground(context),
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      '${widget.item.brand} · ${widget.item.category}'
                          .toUpperCase(),
                      style: const TextStyle(
                        color: electricBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      widget.item.condition,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  widget.item.name,
                  style: const TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '\$${widget.item.price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 27,
                        color: electricBlue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(
                            Icons.receipt_long_rounded,
                            color: electricBlue,
                            size: 18,
                          ),
                          SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Fees shown at checkout',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Select size',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: availableSizes
                      .map(
                        (size) => GlassButton(
                          selected: selectedSize == size,
                          onTap: () => setState(() => selectedSize = size),
                          child: Text(size),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),
                const Text(
                  'The details',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.item.description,
                  style: const TextStyle(
                    color: muted,
                    height: 1.6,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.item.tags
                      .take(5)
                      .map((tag) => _Tag(tag))
                      .toList(),
                ),
                if (available && !ownListing) ...[
                  const SizedBox(height: 18),
                  GlassButton(
                    onTap: askDripToStyle,
                    child: const Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded, color: electricBlue),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Style this piece with Drip',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Build a complete, budget-aware outfit around it',
                                style: TextStyle(color: muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (!ownListing) _PurchaseEstimate(price: widget.item.price),
                if (!ownListing) const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: electricBlue.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      DripAvatar(label: widget.item.seller, size: 46),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.sellerHandle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              ownListing
                                  ? 'Your listing · seller-declared details'
                                  : 'Seller profile · seller-declared details',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!ownListing)
                        IconButton(
                          tooltip: 'Message ${widget.item.sellerHandle}',
                          onPressed: () => Navigator.push(
                            context,
                            dripRoute(
                              ConversationPage(
                                seller: widget.item.seller,
                                handle: widget.item.sellerHandle,
                                product: widget.item,
                              ),
                            ),
                          ),
                          icon: const Icon(
                            Icons.forum_rounded,
                            color: electricBlue,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                if (!available)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: muted.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, color: muted),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This one-of-one listing is sold and no longer available.',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (ownListing)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: electricBlue.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: electricBlue.withValues(alpha: .22),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.storefront_rounded, color: electricBlue),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This is your listing. Manage pricing, promotion, and orders in Seller Studio.',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: GlassButton(
                          selected: true,
                          onTap: () => addToCart(checkout: true),
                          child: const Center(
                            child: Text(
                              'Buy now',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GlassButton(
                          onTap: addToCart,
                          child: const Center(
                            child: Text(
                              'Add to cart',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GlassButton(
                    onTap: () => Navigator.push(
                      context,
                      dripRoute(
                        ConversationPage(
                          seller: widget.item.seller,
                          handle: widget.item.sellerHandle,
                          product: widget.item,
                        ),
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'Message seller / make offer',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
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

class _PurchaseEstimate extends StatelessWidget {
  final double price;
  const _PurchaseEstimate({required this.price});

  @override
  Widget build(BuildContext context) {
    final protection = MarketplacePolicy.buyerProtection(price);
    final total = money(
      price + protection + MarketplacePolicy.shippingPerSeller,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: .4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Purchase estimate',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF635BFF).withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFF635BFF).withValues(alpha: .2),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xFF635BFF),
                      size: 11,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'STRIPE CHECKOUT',
                      style: TextStyle(
                        color: Color(0xFF635BFF),
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _line('Item', price),
          const SizedBox(height: 5),
          _line('Buyer protection', protection),
          const SizedBox(height: 5),
          _line('Shipping', MarketplacePolicy.shippingPerSeller),
          const Divider(height: 18),
          _line('Estimated total before tax', total, strong: true),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 15,
                color: accentForeground(context),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'The payment server verifies the final total before Stripe collects payment and shipping details.',
                  style: TextStyle(
                    color: mutedForeground(context),
                    fontSize: 9,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(String label, double value, {bool strong = false}) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: strong ? null : muted,
            fontSize: 11,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ),
      Text(
        '\$${value.toStringAsFixed(2)}',
        style: TextStyle(
          color: strong ? electricBlue : null,
          fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
        ),
      ),
    ],
  );
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: electricBlue.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '#$text',
      style: const TextStyle(
        color: electricBlue,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
