import '../commerce_model.dart';
import '../product_model.dart';
import 'assistant_gateway.dart';
import 'assistant_models.dart';

/// Deterministic concierge used for instant, grounded answers and graceful
/// service fallback. It never claims knowledge beyond current app state.
class LocalAssistantGateway implements AssistantGateway {
  const LocalAssistantGateway();

  @override
  Future<AssistantResponse> respond(AssistantRequest request) async {
    final text = request.message.trim();
    final lower = text.toLowerCase();

    final sensitive = _sensitiveResponse(lower, text);
    if (sensitive != null) return sensitive;

    // Give useful fashion guidance before catalog intent detection. Questions
    // such as "stripes with plaid" or "will this hoodie shrink?" should not
    // become checkout or product-search requests simply because they mention
    // a garment name.
    final fashionAdvice = _fashionAdvice(request, lower);
    if (fashionAdvice != null) return fashionAdvice;

    final intent = _classify(request, lower);
    return switch (intent) {
      AssistantIntent.outfit => _buildOutfit(request, lower),
      AssistantIntent.discovery => _discover(request, lower),
      AssistantIntent.sizing => _sizing(request, lower),
      AssistantIntent.checkout => _checkout(request, lower),
      AssistantIntent.orders => _orders(request, lower),
      AssistantIntent.seller => _seller(request, lower),
      AssistantIntent.general => _general(request, lower),
      AssistantIntent.safety => _safety(),
    };
  }

  AssistantIntent _classify(AssistantRequest request, String lower) {
    if (_hasAny(lower, const [
      'fit for me',
      'make a fit',
      'full fit',
      'fit under',
      'outfit',
      'what should i wear',
      'style this',
      'style me',
      'build around',
      'make me look',
      'complete this fit',
      'complete my fit',
      'build a fit',
      'put together a fit',
      'make it cheaper',
      'too loud',
    ])) {
      return AssistantIntent.outfit;
    }
    final discoveryVerb = _hasAny(lower, const [
      'find ',
      'show ',
      'recommend',
      'compare',
      'looking for',
    ]);
    final discoveryConstraint =
        _hasAny(lower, const [
          'under ',
          '\$',
          'shoe',
          'sneaker',
          'hoodie',
          'jacket',
          'pants',
          'cargo',
          'shirt',
          'tee',
          'piece',
          'item',
          'something',
          'similar',
        ]) ||
        _brandIn(lower, request.context.catalog) != null;
    if (discoveryVerb && discoveryConstraint) {
      return AssistantIntent.discovery;
    }
    if (RegExp(r'\b(?:will|would|does|do).+\bfit\b').hasMatch(lower) ||
        _hasAny(lower, const [
          'size',
          'sizing',
          'fit me',
          'measurements',
          'too small',
          'too big',
        ])) {
      return AssistantIntent.sizing;
    }
    if (_hasAny(lower, const [
      'what should i ask the seller',
      'ask this seller',
      'ask the seller',
      'make an offer',
      'send an offer',
      'offer \$',
    ])) {
      return AssistantIntent.general;
    }
    if (_hasAny(lower, const [
          'refund',
          'return',
          'checkout',
          'charged',
          'payment',
          'buyer protection',
          'card',
          'shipping twice',
          'explain my total',
          'cart total',
        ]) ||
        RegExp(r'\bstripe\b').hasMatch(lower)) {
      return AssistantIntent.checkout;
    }
    if (_hasAny(lower, const [
      'my order',
      'order status',
      'tracking',
      'arrive',
      'delivery',
      'paid yet',
      'processing',
    ])) {
      return AssistantIntent.orders;
    }
    if (_hasAny(lower, const [
      'seller',
      'sell ',
      'selling',
      'listing',
      'payout',
      'boost',
      'drip pro',
      'seller fee',
      'publish',
    ])) {
      return AssistantIntent.seller;
    }
    if (_hasAny(lower, const [
      'find ',
      'show me',
      'recommend',
      'looking for',
      'compare',
      'under \$',
      'shoe',
      'sneaker',
      'hoodie',
      'jacket',
      'pants',
      'shirt',
      'tee',
    ])) {
      return AssistantIntent.discovery;
    }
    if (request.context.entryPoint == AssistantEntryPoint.cart) {
      return AssistantIntent.checkout;
    }
    if (request.context.entryPoint == AssistantEntryPoint.seller) {
      return AssistantIntent.seller;
    }
    return AssistantIntent.general;
  }

  AssistantResponse? _sensitiveResponse(String lower, String original) {
    final digits = original.replaceAll(RegExp(r'[^0-9]'), '');
    final mentionsSecret = RegExp(
      r'\b(cvv|cvc|card number|password|api key|secret key|stripe secret|auth token)\b',
    ).hasMatch(lower);
    if (!mentionsSecret && !(digits.length >= 13 && digits.length <= 19)) {
      return null;
    }
    return const AssistantResponse(
      reply:
          'For your security, do not put card numbers, security codes, passwords, or API keys in chat. Drip purchases are completed on Stripe’s hosted Checkout page, where payment details belong. If you shared a real credential, remove it where possible and contact the card issuer or credential owner immediately.',
      intent: AssistantIntent.safety,
      followUps: ['Explain Stripe Checkout', 'Review my cart total'],
    );
  }

  AssistantResponse _buildOutfit(AssistantRequest request, String lower) {
    final context = request.context;
    final available = context.purchasableCatalog;
    final sizes = _requestedSizes(lower);
    final focus = context.focusProductId == null
        ? null
        : context.productById(context.focusProductId!);
    final extraAnchor = focus != null && _roleFor(focus) == null ? focus : null;
    final budget = _moneyMentionCents(lower) == null && extraAnchor != null
        ? 22000
        : _outfitBudgetCents(request, lower);

    if (focus != null && !context.isPurchasable(focus)) {
      return AssistantResponse(
        reply:
            '${focus.name} is not currently available for this account, so I won’t build a checkout-ready outfit around it. I can find a live alternative with a similar direction instead.',
        intent: AssistantIntent.outfit,
        followUps: const [
          'Find a similar live piece',
          'Build a clean fit under \$150 total',
        ],
      );
    }

    List<Product> eligibleFor(String role) => available
        .where((product) {
          if (_roleFor(product) != role) return false;
          final requested = sizes[role];
          return requested == null || _hasSize(product, requested);
        })
        .toList(growable: false);

    final tops = eligibleFor('Top');
    final bottoms = eligibleFor('Bottom');
    final shoes = eligibleFor('Shoes');
    if (tops.isEmpty || bottoms.isEmpty || shoes.isEmpty) {
      final missing = <String>[
        if (tops.isEmpty) 'top',
        if (bottoms.isEmpty) 'bottom',
        if (shoes.isEmpty) 'shoe',
      ].join(', ');
      return AssistantResponse(
        reply:
            'I can’t verify a complete outfit with the current $missing size options. I’d rather be exact than substitute an item that does not meet your request. Try another size or let me build the outfit without a size filter, then verify each listing before checkout.',
        intent: AssistantIntent.outfit,
        followUps: const ['Build without size filters', 'Show available sizes'],
      );
    }

    final cartAnchors = <String, Product>{};
    if (context.entryPoint == AssistantEntryPoint.cart) {
      for (final line in context.cart) {
        final product = context.productById(line.listingId);
        final role = product == null ? null : _roleFor(product);
        if (product != null && role != null && context.isPurchasable(product)) {
          cartAnchors.putIfAbsent(role, () => product);
        }
      }
    }
    if (focus != null && _roleFor(focus) != null) {
      cartAnchors[_roleFor(focus)!] = focus;
    }

    final requestedBrand = _brandIn(lower, available);
    final vibeTokens = _vibeTokens(lower);
    _OutfitCandidate? best;
    _OutfitCandidate? cheapest;
    final topPool = cartAnchors['Top'] == null ? tops : [cartAnchors['Top']!];
    final bottomPool = cartAnchors['Bottom'] == null
        ? bottoms
        : [cartAnchors['Bottom']!];
    final shoePool = cartAnchors['Shoes'] == null
        ? shoes
        : [cartAnchors['Shoes']!];

    for (final top in topPool) {
      for (final bottom in bottomPool) {
        for (final shoe in shoePool) {
          final items = [top, bottom, shoe, ?extraAnchor];
          if (items.map((item) => item.id).toSet().length != items.length) {
            continue;
          }
          final subtotal = items.fold<int>(
            0,
            (total, product) => total + toCents(product.price),
          );
          final sellerCount = items
              .map((product) => product.sellerHandle)
              .toSet()
              .length;
          final protection = MarketplacePolicy.buyerProtectionCents(subtotal);
          final shipping =
              sellerCount * MarketplacePolicy.shippingPerSellerCents;
          final estimatedTotal = subtotal + protection + shipping;
          final score =
              items.fold<double>(
                0,
                (total, item) =>
                    total +
                    _styleScore(
                      item,
                      requestedBrand: requestedBrand,
                      vibeTokens: vibeTokens,
                      context: context,
                    ),
              ) +
              (4 - sellerCount) * 4 -
              estimatedTotal / 10000;
          final candidate = _OutfitCandidate(
            items: items,
            subtotalCents: subtotal,
            protectionCents: protection,
            shippingCents: shipping,
            estimatedTotalCents: estimatedTotal,
            score: score,
          );
          if (cheapest == null ||
              candidate.estimatedTotalCents < cheapest.estimatedTotalCents) {
            cheapest = candidate;
          }
          if (estimatedTotal <= budget &&
              (best == null || candidate.score > best.score)) {
            best = candidate;
          }
        }
      }
    }

    if (best == null) {
      if (cheapest == null) {
        return const AssistantResponse(
          reply:
              'I can’t verify a complete outfit from the currently available listings. I can still help you choose one anchor piece or retry when the catalog updates.',
          intent: AssistantIntent.outfit,
          followUps: ['Find one anchor piece', 'Try a different vibe'],
        );
      }
      final lowest = _money(cheapest.estimatedTotalCents);
      return AssistantResponse(
        reply:
            'I can’t honestly fit a complete top, bottom, and shoe combination inside ${_money(budget)}. The lowest verified estimate I can build is $lowest before tax, including current buyer protection and seller-based shipping. I can show that option, raise the limit, or focus on one anchor piece.',
        intent: AssistantIntent.outfit,
        productIds: cheapest.items.map((item) => item.id).toList(),
        followUps: [
          'Show the lowest-cost fit',
          'Find one anchor piece',
          'Build under ${_money(cheapest.estimatedTotalCents + 1000)} total',
        ],
      );
    }

    final itemLines = best.items
        .map(
          (product) =>
              '${_roleFor(product) ?? 'Anchor'}: ${product.name} — ${_money(toCents(product.price))}',
        )
        .join('\n');
    final vibe = _outfitVibe(lower);
    final rationale = extraAnchor == null
        ? _rationaleFor(best.items, vibe)
        : '${extraAnchor.name} is the anchor piece. ${_rationaleFor(best.items, vibe)}';
    final sizeNote = sizes.isEmpty
        ? 'Tell me your top, bottom or waist, and shoe sizes and I’ll verify every listed option.'
        : 'The requested sizes appear in these seller-provided options, but listed size is not a fit guarantee.';
    final sellerCount = best.items
        .map((product) => product.sellerHandle)
        .toSet()
        .length;
    final breakdown =
        '${_money(best.subtotalCents)} merchandise + ${_money(best.protectionCents)} buyer protection + ${_money(best.shippingCents)} shipping across $sellerCount ${sellerCount == 1 ? 'seller' : 'sellers'} = ${_money(best.estimatedTotalCents)} before tax.';

    return AssistantResponse(
      reply:
          'Absolutely — here’s a $vibe outfit built from pieces currently available on Drip.\n\n$itemLines\n\n$rationale $breakdown $sizeNote',
      intent: AssistantIntent.outfit,
      productIds: best.items.map((item) => item.id).toList(growable: false),
      outfit: OutfitPlan(
        title: '${_titleCase(vibe)} fit',
        rationale: rationale,
        productIds: best.items.map((item) => item.id).toList(growable: false),
        subtotalCents: best.subtotalCents,
        budgetCents: budget,
      ),
      followUps: sizes.isEmpty
          ? const [
              'My sizes are top M, pants M, shoes 9',
              'Make it more elevated',
              'Make it cheaper',
            ]
          : const [
              'Make it more elevated',
              'Make it cheaper',
              'Show a one-seller option',
            ],
    );
  }

  AssistantResponse _discover(AssistantRequest request, String lower) {
    final context = request.context;
    final available = context.purchasableCatalog;
    final budget = _moneyMentionCents(lower);
    final brand = _brandIn(lower, context.catalog);
    final category = _requestedCategory(lower);
    final requestedSize = _looseSize(lower);
    final focus = context.focusProductId == null
        ? null
        : context.productById(context.focusProductId!);

    final explicitlyNamed = context.catalog
        .where(
          (product) =>
              lower.contains(product.name.toLowerCase()) ||
              lower.contains(product.id.toLowerCase()),
        )
        .toList(growable: false);
    final blockedNamed = explicitlyNamed
        .where((product) => !context.isPurchasable(product))
        .firstOrNull;
    if (blockedNamed != null) {
      final reason = context.ownProductIds.contains(blockedNamed.id)
          ? 'belongs to this seller account, and self-purchase is blocked'
          : 'is not currently live and available';
      return AssistantResponse(
        reply:
            '${blockedNamed.name} $reason. I won’t add it, recommend it as purchasable, or substitute something unrelated without telling you. I can find a similar live option instead.',
        intent: AssistantIntent.discovery,
        followUps: const [
          'Find a similar live option',
          'Browse available items',
        ],
      );
    }

    var matches = available.where((product) {
      if (explicitlyNamed.isNotEmpty &&
          !explicitlyNamed.any((named) => named.id == product.id)) {
        return false;
      }
      if (budget != null && toCents(product.price) > budget) return false;
      if (brand != null && product.brand.toLowerCase() != brand) return false;
      if (category != null && product.category != category) return false;
      if (requestedSize != null && !_hasSize(product, requestedSize)) {
        return false;
      }
      return true;
    }).toList();

    matches.sort((a, b) {
      final aScore = _queryScore(a, lower, context);
      final bScore = _queryScore(b, lower, context);
      final scoreOrder = bScore.compareTo(aScore);
      return scoreOrder != 0 ? scoreOrder : a.price.compareTo(b.price);
    });

    if (matches.isEmpty) {
      final constraints = [
        if (brand != null) _titleCase(brand),
        ?category,
        if (budget != null) 'at or below ${_money(budget)}',
        if (requestedSize != null) 'with size $requestedSize listed',
      ].join(' ');
      return AssistantResponse(
        reply:
            'I couldn’t verify a live, purchasable match for ${constraints.isEmpty ? 'those filters' : constraints}. I won’t swap in an unrelated item and pretend it matches. Change one constraint and I’ll search again.',
        intent: AssistantIntent.discovery,
        followUps: const [
          'Raise the budget',
          'Show similar live pieces',
          'Browse all available items',
        ],
      );
    }

    final selected = matches.take(3).toList(growable: false);
    final lines = selected
        .map(
          (product) =>
              '${product.name} — ${_money(toCents(product.price))}, ${product.condition}; sizes ${product.sizes.join(', ')}.',
        )
        .join('\n');
    final comparison =
        focus != null && selected.any((item) => item.id == focus.id)
        ? 'I kept the piece you were viewing in the comparison.'
        : 'These are seller-declared details from listings that are currently available in the app.';
    return AssistantResponse(
      reply:
          'Here are the strongest verified matches:\n\n$lines\n\n$comparison Open a piece to review its full description and choose a listed size.',
      intent: AssistantIntent.discovery,
      productIds: selected.map((product) => product.id).toList(growable: false),
      followUps: const [
        'Build an outfit with the first one',
        'Make the picks cheaper',
        'Compare the top two',
      ],
    );
  }

  AssistantResponse _sizing(AssistantRequest request, String lower) {
    final context = request.context;
    final focus = context.focusProductId == null
        ? null
        : context.productById(context.focusProductId!);
    if (focus != null) {
      return AssistantResponse(
        reply:
            '${focus.name} currently lists ${focus.sizes.join(', ')}. Those options are provided by the seller, and Drip does not have garment measurements or a fit guarantee. Compare the listing with an item you own, and ask the seller for exact measurements and any shrinkage or alteration details before checkout.',
        intent: AssistantIntent.sizing,
        productIds: [focus.id],
        followUps: const [
          'Style this piece',
          'Find another size',
          'What should I ask the seller?',
        ],
      );
    }
    return const AssistantResponse(
      reply:
          'I can filter by the size options sellers list, but I can’t guarantee fit from height, weight, or a letter size alone. Tell me whether you need a top, waist or bottom, or shoe size, and I’ll only show available listings with that option. For exact fit, compare measurements with something you own and ask the seller about alterations or shrinkage.',
      intent: AssistantIntent.sizing,
      followUps: [
        'Top M, pants 32, shoes 9',
        'Find shoes in size 10',
        'Build a fit in my sizes',
      ],
    );
  }

  AssistantResponse _checkout(AssistantRequest request, String lower) {
    final context = request.context;
    if (_hasAny(lower, const ['cancel checkout', 'cancel this checkout'])) {
      return const AssistantResponse(
        reply:
            'I won’t cancel anything from chat. Open the checkout screen and use its explicit cancel action after reviewing the session. Canceling an open Stripe Checkout releases the checkout attempt; it is not the same as refunding a completed payment.',
        intent: AssistantIntent.checkout,
        followUps: ['Check my payment status', 'Explain refunds'],
      );
    }
    if (_hasAny(lower, const [
      'refund',
      'return',
      'dispute',
      'fraud',
      'duplicate charge',
    ])) {
      return const AssistantResponse(
        reply:
            'Drip does not yet publish a complete refund, return, or dispute policy inside this app, so I can’t promise eligibility or an outcome. Keep the Stripe receipt and order ID, do not send card details in chat, and use a verified human-support channel once one is available. A production support route is still required before launch.',
        intent: AssistantIntent.checkout,
        followUps: ['Check my payment status', 'Find my latest order ID'],
        needsHumanSupport: true,
      );
    }
    if (lower.contains('buyer protection')) {
      final amount = context.cartProtectionCents;
      final fee = context.cart.isEmpty
          ? 'The fee is 4% of merchandise plus \$0.99, limited to \$1.49–\$4.99.'
          : 'For the current cart, the fee is ${_money(amount)}.';
      return AssistantResponse(
        reply:
            '$fee This build calculates the fee, but it does not publish a complete claims-coverage policy, so I won’t invent what a claim would cover. Review the checkout total before paying on Stripe.',
        intent: AssistantIntent.checkout,
        followUps: const ['Explain my total', 'How does Stripe Checkout work?'],
      );
    }
    if (context.cart.isEmpty) {
      return const AssistantResponse(
        reply:
            'Your cart is empty. Drip uses Stripe-hosted Checkout for purchases; card and shipping details are entered on Stripe’s secure page, not in chat. Add a live listing first, then I can explain the exact merchandise, buyer-protection, and seller-based shipping amounts shown in the app.',
        intent: AssistantIntent.checkout,
        followUps: ['Find something under \$75', 'Build a full fit'],
      );
    }
    final shipmentCount = context.cart
        .map((line) => context.productById(line.listingId)?.sellerHandle)
        .whereType<String>()
        .toSet()
        .length;
    final status = context.checkoutStatus == null
        ? 'No Stripe session is currently open.'
        : 'The current Stripe payment status is ${context.checkoutStatus}.';
    return AssistantResponse(
      reply:
          'Your current estimate is ${_money(context.cartTotalCents)} before Stripe-calculated tax: ${_money(context.cartSubtotalCents)} merchandise, ${_money(context.cartProtectionCents)} buyer protection, and ${_money(context.cartShippingCents)} shipping across $shipmentCount ${shipmentCount == 1 ? 'seller package' : 'seller packages'}. $status Payment is only confirmed after the server verifies Stripe’s status—not simply when the browser returns to Drip.',
      intent: AssistantIntent.checkout,
      productIds: context.cart.map((line) => line.listingId).toList(),
      followUps: const [
        'Complete this fit',
        'Why is shipping per seller?',
        'Check my payment status',
      ],
    );
  }

  AssistantResponse _orders(AssistantRequest request, String lower) {
    final context = request.context;
    if (_hasAny(lower, const [
      'tracking',
      'arrive',
      'delivery',
      'ship today',
    ])) {
      return const AssistantResponse(
        reply:
            'Drip does not currently have carrier tracking or a published delivery-time guarantee in this app, so I can’t give you an arrival date. Seller statements are not a shipping guarantee. Keep the order ID and seller conversation, and check a verified support or tracking route when the product adds one.',
        intent: AssistantIntent.orders,
        followUps: ['Check my payment status', 'Show my latest receipt'],
        needsHumanSupport: true,
      );
    }
    if (context.checkoutStatus != null) {
      return AssistantResponse(
        reply:
            'Your current Stripe checkout status is ${context.checkoutStatus}. A browser return is not proof of payment; Drip waits for the server-confirmed Stripe status before recording a paid receipt or changing inventory. If it is still open or processing, wait briefly and refresh the status rather than starting a second payment.',
        intent: AssistantIntent.orders,
        followUps: const ['Explain processing', 'Review my cart total'],
      );
    }
    if (context.lastReceiptTotalCents != null) {
      return AssistantResponse(
        reply:
            'This device has ${context.receiptCount} confirmed checkout ${context.receiptCount == 1 ? 'receipt' : 'receipts'}. The latest is ${_money(context.lastReceiptTotalCents!)} with payment status ${context.lastReceiptStatus ?? 'recorded'}. This does not provide live carrier tracking or a delivery estimate.',
        intent: AssistantIntent.orders,
        followUps: const ['Explain buyer protection', 'When will it arrive?'],
      );
    }
    return const AssistantResponse(
      reply:
          'I don’t see a confirmed buyer receipt on this device or an open Stripe checkout to check. A return from Stripe alone does not prove payment. If you paid elsewhere or lost access to the original device, a verified human-support lookup is needed.',
      intent: AssistantIntent.orders,
      followUps: ['Explain Stripe Checkout', 'Review my cart'],
      needsHumanSupport: true,
    );
  }

  AssistantResponse _seller(AssistantRequest request, String lower) {
    final context = request.context;
    if (lower.contains('payout')) {
      return const AssistantResponse(
        reply:
            'For a signed-in seller on a configured server, Seller Studio can open Stripe-hosted Connect onboarding and show verified transfer and payout capability status. The earnings figure is still a local preview, not a Stripe balance or completed bank transfer, and Drip does not yet send automatic Transfers—so I won’t claim money was paid out.',
        intent: AssistantIntent.seller,
        followUps: ['Explain seller fees', 'Improve my listing'],
      );
    }
    if (_hasAny(lower, const ['boost', 'drip pro', 'activate pro'])) {
      return const AssistantResponse(
        reply:
            'Drip Pro and listing boosts are currently local demonstrations; they do not create a real subscription, charge, or paid promotion. The planned pricing shown in the app is \$9.99 per month for Pro, \$1.99 for 24 hours, or \$5.99 for seven days, but production billing still needs a server-backed subscription and promotion system.',
        intent: AssistantIntent.seller,
        followUps: ['Explain seller fees', 'Help improve a listing'],
      );
    }
    if (_hasAny(lower, const ['publish', 'buyers can check out'])) {
      return const AssistantResponse(
        reply:
            'New listings created in this build are saved locally and are not synchronized to the checkout server’s inventory, so I can’t claim another buyer can purchase them yet. Production publishing needs server-side listing creation, moderation, inventory, and seller-account ownership checks.',
        intent: AssistantIntent.seller,
        followUps: ['Help write the listing', 'Explain checkout inventory'],
      );
    }
    final currentRate = context.sellerPro ? '7%' : '10%';
    return AssistantResponse(
      reply:
          'Your current demo seller plan is ${context.sellerPro ? 'Pro' : 'Free'}, with ${context.sellerLiveListings} live and ${context.sellerSoldListings} sold listings. The displayed seller fee is $currentRate of the sale price with a \$1 minimum; the Free rate is 10% and the planned Pro rate is 7%. Pricing, payouts, Pro, and boosts need server-backed production workflows before they can represent real billing.',
      intent: AssistantIntent.seller,
      followUps: const [
        'Estimate my seller fee',
        'Help improve a listing',
        'Explain payouts',
      ],
    );
  }

  AssistantResponse _general(AssistantRequest request, String lower) {
    final context = request.context;
    if (_hasAny(lower, const [
      'what should i ask the seller',
      'ask this seller',
      'ask the seller',
    ])) {
      final focus = context.focusProductId == null
          ? null
          : context.productById(context.focusProductId!);
      final item = focus == null ? 'the item' : focus.name;
      return AssistantResponse(
        reply:
            'For $item, ask for exact measurements, close-up photos of wear or flaws, any repairs or alterations, what is included, and when the seller realistically expects to ship. If brand authenticity matters, ask for labels, style codes, and proof of purchase—but treat seller replies as evidence to review, not a Drip guarantee.',
        intent: AssistantIntent.general,
        productIds: focus == null ? const [] : [focus.id],
        followUps: const ['Check listed sizes', 'Style this piece'],
      );
    }
    if (_hasAny(lower, const ['make an offer', 'send an offer', 'offer \$'])) {
      return const AssistantResponse(
        reply:
            'I can help you draft a respectful offer, but I can’t claim an offer was sent or received. Messaging and offers are not yet a server-confirmed workflow in this build. Open the seller conversation yourself and confirm the amount before sending anything.',
        intent: AssistantIntent.general,
        followUps: ['Draft a polite offer', 'Open item details'],
      );
    }
    if (_hasAny(lower, const ['authentic', 'verified', 'real or fake'])) {
      return const AssistantResponse(
        reply:
            'Drip does not currently provide a completed item-authentication or seller-verification process. Brand, condition, photos, and descriptions are seller-declared. Ask for close-up labels, serial or style codes, receipts where available, flaws, repairs, and additional photos—but treat those as evidence to review, not a guarantee.',
        intent: AssistantIntent.general,
        followUps: ['What should I ask the seller?', 'Find another listing'],
        needsHumanSupport: true,
      );
    }
    if (lower.contains('condition')) {
      return const AssistantResponse(
        reply:
            'Condition labels are seller-declared. Before buying, review every photo and ask about stains, odor, sole wear, repairs, alterations, missing parts, and flaws not shown. Drip does not currently authenticate the condition label.',
        intent: AssistantIntent.general,
        followUps: ['What should I ask the seller?', 'Compare two items'],
      );
    }
    if (_hasAny(lower, const ['real person', 'are you human'])) {
      return const AssistantResponse(
        reply:
            'I’m Drip Concierge, an AI shopping and marketplace assistant—not a human stylist or support employee. I can build outfits from available listings, compare seller-provided item details, explain the app’s checkout math, and help you choose the right next step.',
        intent: AssistantIntent.general,
        followUps: ['Build a full fit', 'Explain Stripe Checkout'],
      );
    }
    return const AssistantResponse(
      reply:
          'I’m your Drip shopping and marketplace concierge. I can build a complete outfit from available pieces, untangle unusual style combinations, explain dress codes and garment care, search by budget or listed size, style an item you’re viewing, explain Stripe Checkout and cart totals, and guide sellers through the features that actually exist. What would you like to solve first?',
      intent: AssistantIntent.general,
      followUps: [
        'Build a full fit under \$150 total',
        'Find something in my size',
        'Explain Stripe Checkout',
        'Help with selling',
      ],
    );
  }

  AssistantResponse? _fashionAdvice(AssistantRequest request, String lower) {
    AssistantResponse advice(
      String reply, {
      List<String> followUps = const [
        'Ask another style question',
        'Build a fit from live listings',
      ],
    }) => AssistantResponse(
      reply: reply,
      intent: AssistantIntent.general,
      followUps: followUps,
    );

    // Chemical-cleaner combinations are a safety issue, not a styling or
    // shopping request. Keep this ahead of all other care routing.
    if (lower.contains('bleach') && lower.contains('ammonia')) {
      return advice(
        'Never mix bleach and ammonia. The combination can release dangerous, toxic gas. Stop using both products, move to fresh air, and do not try to neutralize the mixture with another cleaner. If anyone has trouble breathing, chest pain, severe coughing, or eye irritation, contact emergency services or Poison Control now. For the tee, use only one care-label-approved product after the area is safe.',
        followUps: const [
          'Safer stain-care steps',
          'How do I read a care label?',
        ],
      );
    }

    if (lower.contains('oil stain') || lower.contains('grease stain')) {
      return advice(
        'Blot the fresh oil gently—do not rub it deeper into the cotton. Check the care label, place an absorbent towel behind the stain, and spot test a small amount of mild dish soap or laundry detergent on a hidden area first. Rinse and wash only as the label allows. Air dry until the stain is fully gone, because dryer heat can set remaining oil. A delicate, vintage, dyed, or valuable tee is safer with a professional cleaner.',
        followUps: const [
          'What do the care symbols mean?',
          'Ask about another fabric',
        ],
      );
    }

    if (lower.contains('suede') &&
        _hasAny(lower, const ['rain', 'wet', 'soak', 'water'])) {
      return advice(
        'For rain-soaked suede, blot moisture with a clean cloth without rubbing. Reshape the sneakers with plain paper and let them air dry naturally away from a dryer, radiator, hair dryer, or other direct heat. Once fully dry, lift the nap gently with a clean suede brush. Test any suede product on a hidden area first; for dyed, valuable, or badly stained suede, use a professional cleaner.',
        followUps: const [
          'How should I protect suede?',
          'Ask about another material',
        ],
      );
    }

    if (_hasAny(lower, const ['shrink', 'shrinking', 'shrank'])) {
      return advice(
        'I can’t confirm whether this hoodie will shrink without its fiber content, construction, prior wash history, and care label. Cotton-rich fabric often reacts more to heat, while blends vary. Ask the seller for a clear label photo and whether it has already been washed; then use cold water and air dry or the lowest label-approved heat. There is no way to guarantee the final size, so compare current garment measurements before buying.',
        followUps: const [
          'Draft a question for the seller',
          'How do I compare measurements?',
        ],
      );
    }

    if (_hasAny(lower, const ['puffer', 'down jacket', 'insulated jacket']) &&
        _hasAny(lower, const ['dryer', 'tumble dry'])) {
      return advice(
        'I can’t confirm that this puffer jacket is dryer-safe because Drip does not have a verified care label for it. Heat and tumbling can damage some shells, coatings, insulation, or trims. Check the care label and ask the seller for a clear photo plus the fiber and fill details; if those remain unknown, do not guess. A professional cleaner is the safer choice for a valuable or technical jacket.',
        followUps: const [
          'Draft a care question for the seller',
          'Explain care-label symbols',
        ],
      );
    }

    if (_hasAny(lower, const ['heavy rain', 'waterproof', 'water resistant']) &&
        _hasAny(lower, const ['jacket', 'puffer', 'coat'])) {
      return advice(
        'I can’t confirm a waterproof rating or reliable water resistance for this jacket from the listing. A puffer can be warm without being rainproof. For heavy rain, wear a verified waterproof shell over it, and ask the seller for the material, care label, and any manufacturer weather rating before relying on it outdoors.',
        followUps: const [
          'Draft a question for the seller',
          'How should I layer for rain?',
        ],
      );
    }

    if (lower.contains('brown') &&
        lower.contains('black') &&
        _hasAny(lower, const ['wear', 'work', 'match', 'go with'])) {
      return advice(
        'Yes—brown shoes can work with black pants. Make the contrast look intentional: choose a rich, clearly brown tone instead of one that almost reads black, then repeat a little warmth in a belt, bag, watch strap, or textured layer. A clean trouser break and one or two neutral colors elsewhere keep the combination composed.',
      );
    }

    if (lower.contains('socks') && lower.contains('sandals')) {
      return advice(
        'Socks with sandals are not automatically wrong; context and intention matter. They work best in casual, outdoors, or sport-influenced outfits when the socks are clean, the sandal shape is substantial, and the color or texture connects to another piece. Keep the proportions deliberate rather than treating the socks as an afterthought.',
      );
    }

    if (lower.contains('black tie') || lower.contains('black-tie')) {
      return advice(
        'Black tie is a formal dress code, so sneakers are normally outside the expectation even when they are clean. Respect the invitation and the couple or host; choose formal footwear unless they have explicitly relaxed the dress code or accessibility requires another option. If sneakers are approved, use the sleekest, least athletic pair and keep the rest properly formal.',
        followUps: const [
          'What does black tie include?',
          'Build a formal-inspired fit',
        ],
      );
    }

    if (lower.contains('sneaker') &&
        lower.contains('suit') &&
        _hasAny(lower, const ['wedding', 'wear', 'work'])) {
      return advice(
        'Clean sneakers can work with a suit when the occasion and dress code allow it. For a wedding, check the invitation first: a relaxed cocktail or smart-casual setting gives you more room than formal or black tie. Choose a minimal, sleek, low-profile sneaker in excellent condition and a suit with a modern, clean trouser break.',
      );
    }

    if (lower.contains('silver') &&
        lower.contains('gold') &&
        _hasAny(lower, const ['mix', 'together', 'wear'])) {
      return advice(
        'Yes, silver and gold jewelry can look intentional together. Repeat each metal at least once, or use one mixed-metal piece as a bridge, then let one finish be dominant and the other an accent. Similar visual weight and a little spacing keep the balance controlled rather than accidental.',
      );
    }

    if (lower.contains('stripe') && lower.contains('plaid')) {
      return advice(
        'Stripes and plaid can work together when their scale is different. Let one pattern be dominant, keep the other quieter, and connect them with at least one shared color or color family. For example, pair a broad plaid with a fine stripe, then keep shoes and accessories simple.',
      );
    }

    if (_hasAny(lower, const ['business casual', 'business-casual']) &&
        lower.contains('interview')) {
      return advice(
        'For a business casual interview, aim one step more polished than the company’s everyday office style. A structured shirt or knit with trousers or chinos, an optional clean jacket, and loafers or very minimal clean shoes is a reliable base. Company, office, and industry norms differ, so check the employer’s dress code or public team photos before deciding.',
        followUps: const ['Make it more creative', 'Make it more conservative'],
      );
    }

    if (lower.contains('smart casual')) {
      return advice(
        'Smart casual means polished and intentional, but still relaxed. Combine one structured or tailored piece—such as trousers, a clean overshirt, or a blazer—with simpler casual pieces. Good fit, clean shoes, restrained graphics, and tidy fabric condition matter more than wearing a full suit.',
      );
    }

    if (lower.contains('funeral') || lower.contains('memorial service')) {
      return advice(
        'For a funeral, prioritize respect and avoid making the outfit the focus. Subdued colors, quiet details, clean shoes, and a conservative amount of skin exposure are a safe starting point, but culture, faith, family tradition, climate, and venue can change what is appropriate. When possible, ask the family or organizer about expectations.',
        followUps: const [
          'Help with warm-weather options',
          'Help with a specific tradition',
        ],
      );
    }

    if ((lower.contains('45°') ||
            lower.contains('45f') ||
            lower.contains('45 f') ||
            lower.contains('45°f')) &&
        lower.contains('rain')) {
      return advice(
        'For 45°F weather with steady rain, use a moisture-managing base layer, a warm but breathable midlayer, and a waterproof rain shell with a hood. Add water-resistant footwear and socks that stay warm when damp, while leaving enough room for movement. Keep spare dry socks available if you will be outside for long.',
      );
    }

    if ((lower.contains('90°') ||
            lower.contains('90f') ||
            lower.contains('90 f') ||
            lower.contains('90°f')) &&
        _hasAny(lower, const ['humid', 'humidity', 'heat', 'hot'])) {
      return advice(
        'In 90°F heat and high humidity, choose lightweight, breathable fabric and a loose or relaxed cut that allows airflow. Keep the outfit to one light layer where practical, reduce heavy linings and tight synthetic pieces, and use sun protection appropriate to your plans. Light color can help in direct sun, but fabric weight and ventilation matter most.',
      );
    }

    if (lower.contains('hoodie') &&
        lower.contains('jacket') &&
        _hasAny(lower, const ['layer', 'bulky', 'bulk'])) {
      return advice(
        'Use a thin, lightweight, low-bulk hoodie and a jacket with enough room through the shoulders, chest, and sleeves. Keep the hoodie hem close to or slightly below the jacket hem, avoid stacking multiple thick cuffs, and check mobility when you reach forward. A cleaner proportion and one roomier outer layer prevent the outfit from feeling bulky.',
      );
    }

    if (_hasAny(lower, const [
      'look skinnier',
      'look slimmer',
      'hide my body',
    ])) {
      return advice(
        'You do not need to correct your body. If your goal is a more streamlined silhouette, use a continuous color line, clean hems, and structured pieces that skim rather than squeeze. You can define one area—such as the waist or shoulder—while keeping the rest simple. The right choice is the proportion that supports your preference and feels comfortable.',
      );
    }

    if (_hasAny(lower, const ['i am short', "i'm short", 'short person']) &&
        _hasAny(lower, const [
          'pant',
          'trouser',
          'longer line',
          'proportion',
        ])) {
      return advice(
        'To create a longer line with pants, try a mid- or higher rise, a clean vertical silhouette, and a hem with little or no break. Keeping the top and pants close in color can make the line more continuous. These are proportion options, not rules—choose the rise and shape that feel best to you.',
      );
    }

    if (lower.contains('broad shoulder')) {
      return advice(
        'Broad shoulders can support many silhouettes. If your preference is visual balance, try an open neckline or clean shoulder seam with straight or wider trousers, or add a little volume below the waist. If you want to emphasize the shoulder instead, keep the lower half streamlined. The goal is your preferred proportion, not fixing a body feature.',
      );
    }

    if (lower.contains('plus size') && lower.contains('oversized')) {
      return advice(
        'Absolutely—you can wear oversized clothes at any size. Make the proportion feel intentional by anchoring the outfit with one clearer edge, such as a visible cuff, defined shoulder, shorter outer layer, or structured shoe. You can balance one oversized piece with a straighter one, or go fully relaxed; comfort and your own preference matter most.',
      );
    }

    if (_hasAny(lower, const [
      "men's clothes",
      'mens clothes',
      "women's clothes",
      'womens clothes',
      'different gender section',
    ])) {
      return advice(
        'Clothing does not have to be limited by the section where it was sold. Focus on the silhouette, measurements, rise, shoulder width, and closure placement you want; labeled sizes can vary significantly between departments and brands. Compare exact garment measurements with something you already like rather than treating the gender label as a fit rule.',
      );
    }

    if (_hasAny(lower, const [
      'care label',
      'wash this',
      'how do i wash',
      'remove a stain',
      'iron this',
      'fabric care',
    ])) {
      return advice(
        'Start with the garment’s care label and fiber content; Drip cannot verify either from appearance alone. Spot test any treatment on a hidden area, use the gentlest label-approved method, and avoid heat until a stain is gone. For vintage, embellished, leather, suede, structured, or valuable pieces, ask the seller for details and consider a professional cleaner.',
        followUps: const [
          'Tell me the fabric and stain',
          'Explain care-label symbols',
        ],
      );
    }

    if (_hasAny(lower, const [
      'dress code',
      'what do i wear to',
      'what should i wear to',
    ])) {
      return advice(
        'Start with the stated dress code, venue, weather, time of day, and the host or community’s expectations. A useful formula is one polished base, occasion-appropriate coverage, clean footwear, and one personal detail. Tell me the exact occasion and dress code, and I’ll translate it without forcing you into a gendered uniform.',
        followUps: const [
          'It is a daytime wedding',
          'It is a creative work event',
        ],
      );
    }

    return null;
  }

  AssistantResponse _safety() => const AssistantResponse(
    reply:
        'I can help with style, shopping, checkout, and selling on Drip, but I can’t help expose private credentials or bypass marketplace safeguards.',
    intent: AssistantIntent.safety,
  );

  int _outfitBudgetCents(AssistantRequest request, String lower) {
    final direct = _moneyMentionCents(lower);
    if (direct != null) return direct;
    if (_hasAny(lower, const [
      'cheaper',
      'lower the price',
      'less expensive',
    ])) {
      for (final turn in request.history.reversed) {
        if (turn.role != AssistantRole.assistant) continue;
        final amounts = RegExp(r'\$(\d+(?:\.\d{1,2})?)')
            .allMatches(turn.content)
            .map((match) => double.tryParse(match.group(1)!))
            .whereType<double>()
            .toList();
        if (amounts.isNotEmpty) {
          return (amounts.last * 80).round();
        }
      }
      return 12000;
    }
    return 15000;
  }

  int? _moneyMentionCents(String lower) {
    final matches = RegExp(
      r'(?:under|below|less than|max(?:imum)?|budget(?: is| of|:)?|for|\$)\s*\$?\s*(\d+(?:\.\d{1,2})?)',
    ).allMatches(lower).toList();
    if (matches.isEmpty) return null;
    final value = double.tryParse(matches.last.group(1)!);
    return value == null ? null : toCents(value);
  }

  Map<String, String> _requestedSizes(String lower) {
    final result = <String, String>{};
    String? group(RegExp expression) => expression.firstMatch(lower)?.group(1);
    final shoe = group(
      RegExp(r'(?:shoe|sneaker)(?:\s+size)?\s*(\d{1,2}(?:\.5)?)'),
    );
    final bottom = group(
      RegExp(r'(?:pants?|bottom|waist)(?:\s+size)?\s*([a-z]{1,3}|\d{2})'),
    );
    final top = group(
      RegExp(r'(?:top|shirt|tee|hoodie)(?:\s+size)?\s*([a-z]{1,3})'),
    );
    final general = group(RegExp(r'\bsize\s+([a-z]{1,3})\b'));
    if (shoe != null) result['Shoes'] = shoe;
    if (bottom != null) result['Bottom'] = bottom.toUpperCase();
    if (top != null) result['Top'] = top.toUpperCase();
    if (general != null) {
      result.putIfAbsent('Top', () => general.toUpperCase());
      result.putIfAbsent('Bottom', () => general.toUpperCase());
    }
    return result;
  }

  String? _looseSize(String lower) {
    final match = RegExp(
      r'\bsize\s+([a-z]{1,3}|\d{1,2}(?:\.5)?)\b',
    ).firstMatch(lower);
    return match?.group(1)?.toUpperCase();
  }

  bool _hasSize(Product product, String requested) => product.sizes.any(
    (size) => size.trim().toUpperCase() == requested.trim().toUpperCase(),
  );

  String? _brandIn(String lower, Iterable<Product> products) {
    final brands =
        products
            .map((product) => product.brand.trim().toLowerCase())
            .where((brand) => brand.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    for (final brand in brands) {
      if (lower.contains(brand)) return brand;
    }
    return null;
  }

  String? _requestedCategory(String lower) {
    if (_hasAny(lower, const ['shoe', 'sneaker', 'runner', 'boot'])) {
      return 'Shoes';
    }
    if (_hasAny(lower, const ['hoodie', 'sweatshirt'])) return 'Hoodies';
    if (_hasAny(lower, const ['jacket', 'coat', 'puffer', 'bomber'])) {
      return 'Jackets';
    }
    if (_hasAny(lower, const ['pants', 'cargo', 'jeans', 'denim'])) {
      return 'Pants';
    }
    if (_hasAny(lower, const ['accessory', 'cap', 'beanie', 'bag'])) {
      return 'Accessories';
    }
    if (_hasAny(lower, const ['shirt', 'tee', 't-shirt', 'top'])) {
      return null;
    }
    return null;
  }

  String? _roleFor(Product product) => switch (product.category) {
    'T-Shirts' || 'Shirts' || 'Hoodies' => 'Top',
    'Pants' => 'Bottom',
    'Shoes' => 'Shoes',
    _ => null,
  };

  Set<String> _vibeTokens(String lower) {
    const tokens = {
      'basketball',
      'clean',
      'minimal',
      'luxury',
      'designer',
      'streetwear',
      'running',
      'sporty',
      'black',
      'white',
      'cream',
      'neutral',
      'night',
      'elevated',
      'casual',
    };
    return {
      for (final token in tokens)
        if (lower.contains(token)) token,
    };
  }

  double _styleScore(
    Product product, {
    required String? requestedBrand,
    required Set<String> vibeTokens,
    required AssistantContext context,
  }) {
    final haystack = [
      product.name,
      product.brand,
      product.vibe,
      product.description,
      ...product.tags,
    ].join(' ').toLowerCase();
    var score = 0.0;
    if (requestedBrand != null &&
        product.brand.toLowerCase() == requestedBrand) {
      score += 10;
    }
    for (final token in vibeTokens) {
      if (haystack.contains(token)) score += 3;
    }
    if (context.savedProductIds.contains(product.id)) score += 5;
    if (context.cart.any((line) => line.listingId == product.id)) score += 6;
    if (product.condition.toLowerCase() == 'excellent') score += 1;
    return score;
  }

  int _queryScore(Product product, String lower, AssistantContext context) {
    final haystack = [
      product.name,
      product.brand,
      product.category,
      product.condition,
      product.vibe,
      product.description,
      ...product.tags,
    ].join(' ').toLowerCase();
    final tokens = lower
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length > 2)
        .where(
          (token) => !const {
            'show',
            'find',
            'under',
            'recommend',
            'looking',
            'with',
            'something',
          }.contains(token),
        );
    var score = tokens.where(haystack.contains).length * 3;
    if (context.savedProductIds.contains(product.id)) score += 2;
    return score;
  }

  String _outfitVibe(String lower) {
    if (lower.contains('basket')) return 'basketball-inspired';
    if (_hasAny(lower, const ['night', 'dinner', 'date'])) return 'night-out';
    if (_hasAny(lower, const ['luxury', 'elevated', 'designer'])) {
      return 'clean elevated';
    }
    if (_hasAny(lower, const ['sport', 'gym', 'running'])) return 'sporty';
    if (_hasAny(lower, const ['street', 'graphic', 'loud'])) {
      return 'streetwear';
    }
    return 'clean everyday';
  }

  String _rationaleFor(List<Product> items, String vibe) {
    final top = items.firstWhere((item) => _roleFor(item) == 'Top');
    final bottom = items.firstWhere((item) => _roleFor(item) == 'Bottom');
    final shoes = items.firstWhere((item) => _roleFor(item) == 'Shoes');
    return 'The ${top.name.toLowerCase()} sets a clear base, the ${bottom.name.toLowerCase()} adds shape, and the ${shoes.name.toLowerCase()} grounds the $vibe direction without competing with the rest of the outfit.';
  }

  static bool _hasAny(String value, List<String> needles) =>
      needles.any(value.contains);

  static String _money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

  static String _titleCase(String value) => value
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word.substring(0, 1).toUpperCase()}${word.substring(1)}',
      )
      .join(' ');

  @override
  void close() {}
}

class _OutfitCandidate {
  final List<Product> items;
  final int subtotalCents;
  final int protectionCents;
  final int shippingCents;
  final int estimatedTotalCents;
  final double score;

  const _OutfitCandidate({
    required this.items,
    required this.subtotalCents,
    required this.protectionCents,
    required this.shippingCents,
    required this.estimatedTotalCents,
    required this.score,
  });
}
