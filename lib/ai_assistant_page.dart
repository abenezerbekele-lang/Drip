import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'assistant/assistant_gateway.dart';
import 'assistant/assistant_models.dart';
import 'assistant/local_concierge.dart';
import 'auth/auth_controller.dart';
import 'commerce_model.dart';
import 'design_system.dart';
import 'product_detail.dart';
import 'product_model.dart';

class AiAssistantPage extends StatefulWidget {
  final String? initialPrompt;
  final AssistantEntryPoint entryPoint;
  final String? focusProductId;
  final AssistantGateway? gateway;

  const AiAssistantPage({
    super.key,
    this.initialPrompt,
    this.entryPoint = AssistantEntryPoint.general,
    this.focusProductId,
    this.gateway,
  });

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final controller = TextEditingController();
  final scrollController = ScrollController();
  final focusNode = FocusNode();
  late final AssistantGateway gateway;
  late final bool ownsGateway;
  late final List<_ConversationMessage> messages;
  bool sending = false;
  bool initialPromptSent = false;
  String? lastFailedPrompt;

  @override
  void initState() {
    super.initState();
    ownsGateway = widget.gateway == null;
    gateway = widget.gateway ?? _defaultGateway();
    messages = [_ConversationMessage.assistant(_welcomeResponse())];
  }

  AssistantGateway _defaultGateway() {
    final remote = HttpAssistantGateway.isEnvironmentConfigured
        ? HttpAssistantGateway.fromEnvironment(
            accessTokenProvider: context.read<AuthController>().accessToken,
          )
        : null;
    return ResilientAssistantGateway(
      remote: remote,
      fallback: const LocalAssistantGateway(),
    );
  }

  AssistantResponse _welcomeResponse() => AssistantResponse(
    reply: switch (widget.entryPoint) {
      AssistantEntryPoint.product =>
        'Let’s style this piece with intention. I can build a complete outfit around it, check seller-listed sizes, compare alternatives, and help you decide what to ask before buying.',
      AssistantEntryPoint.cart =>
        'I can make your cart feel more cohesive, explain every part of the checkout estimate, or find the missing piece without changing your cart for you.',
      AssistantEntryPoint.saved =>
        'I can compare your saved pieces and turn them into a practical outfit using listings that are still available.',
      AssistantEntryPoint.seller =>
        'I can help sharpen a listing, explain the fees shown in Seller Studio, and separate today’s demo tools from what still needs a production workflow.',
      AssistantEntryPoint.general =>
        'I’m your professional streetwear stylist and Drip shopping concierge. I can build outfits from available listings, compare pieces, explain checkout, and help you find the right next step.',
    },
    intent: AssistantIntent.general,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialPromptSent || widget.initialPrompt?.trim().isEmpty != false) {
      return;
    }
    initialPromptSent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) send(widget.initialPrompt);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    focusNode.dispose();
    if (ownsGateway) gateway.close();
    super.dispose();
  }

  Future<void> send([String? quick]) async {
    if (sending) return;
    final text = (quick ?? controller.text).trim();
    if (text.isEmpty) return;
    if (text.length > 1200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keep each question under 1,200 characters.'),
        ),
      );
      return;
    }

    final app = context.read<AppState>();
    final safeDisplayText = redactSensitiveAssistantData(text);
    final history = messages
        .skip(1)
        .map(
          (message) => AssistantTurn(
            role: message.mine ? AssistantRole.user : AssistantRole.assistant,
            content: message.text,
          ),
        )
        .toList(growable: false);
    final request = AssistantRequest(
      message: text,
      history: history,
      context: AssistantContext.fromAppState(
        app,
        entryPoint: widget.entryPoint,
        focusProductId: widget.focusProductId,
      ),
    );

    controller.clear();
    focusNode.unfocus();
    setState(() {
      lastFailedPrompt = null;
      sending = true;
      messages.add(_ConversationMessage.user(safeDisplayText));
    });
    _scrollToLatest();

    try {
      final response = containsSensitiveAssistantData(text)
          ? await const LocalAssistantGateway().respond(request)
          : await gateway.respond(request);
      if (!mounted) return;
      setState(() {
        messages.add(_ConversationMessage.assistant(response));
        sending = false;
      });
    } on AssistantGatewayException catch (error) {
      if (!mounted) return;
      setState(() {
        lastFailedPrompt = text;
        sending = false;
        messages.add(
          _ConversationMessage.assistant(
            AssistantResponse(
              reply: error.publicMessage,
              intent: AssistantIntent.general,
              followUps: const ['Try again'],
            ),
          ),
        );
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        lastFailedPrompt = text;
        sending = false;
        messages.add(
          _ConversationMessage.assistant(
            const AssistantResponse(
              reply:
                  'I couldn’t finish that answer. Your cart and payment state were not changed. Please try again.',
              intent: AssistantIntent.general,
              followUps: ['Try again'],
            ),
          ),
        );
      });
    }
    _scrollToLatest();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _clearConversation() {
    setState(() {
      messages
        ..clear()
        ..add(_ConversationMessage.assistant(_welcomeResponse()));
      sending = false;
      lastFailedPrompt = null;
    });
  }

  List<String> get quickPrompts => switch (widget.entryPoint) {
    AssistantEntryPoint.product => const [
      'Style this piece',
      'Will this size work?',
      'What should I ask the seller?',
    ],
    AssistantEntryPoint.cart => const [
      'Complete this fit',
      'Explain my total',
      'Reduce my shipping cost',
    ],
    AssistantEntryPoint.saved => const [
      'Build a fit from my saved pieces',
      'Compare my saved shoes',
      'Find a cheaper alternative',
    ],
    AssistantEntryPoint.seller => const [
      'Estimate my seller fee',
      'Help improve a listing',
      'Explain seller payouts',
    ],
    AssistantEntryPoint.general => const [
      'Build a full fit under \$150 total',
      'Find shoes in size 9',
      'Explain Stripe Checkout',
      'Help with selling',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(
          children: [
            _ConciergeMark(size: 38),
            SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Drip Concierge',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                Text(
                  'Style · shopping · support',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Start a new conversation',
            onPressed: messages.length > 1 ? _clearConversation : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ConciergeHero(entryPoint: widget.entryPoint),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 42,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: quickPrompts.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, index) => ActionChip(
                              avatar: Icon(
                                _promptIcon(quickPrompts[index]),
                                size: 17,
                                color: accentForeground(context),
                              ),
                              label: Text(quickPrompts[index]),
                              onPressed: sending
                                  ? null
                                  : () => send(quickPrompts[index]),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        for (final message in messages)
                          if (message.mine)
                            _UserBubble(text: message.text)
                          else
                            _AssistantAnswer(
                              response: message.response!,
                              app: app,
                              onPrompt: send,
                            ),
                        if (sending) const _ThinkingBubble(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _Composer(
            controller: controller,
            focusNode: focusNode,
            sending: sending,
            onSend: send,
            onRetry: lastFailedPrompt == null
                ? null
                : () => send(lastFailedPrompt),
          ),
        ],
      ),
    );
  }

  static IconData _promptIcon(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('fit') || lower.contains('style')) {
      return Icons.checkroom_rounded;
    }
    if (lower.contains('stripe') || lower.contains('total')) {
      return Icons.lock_rounded;
    }
    if (lower.contains('sell') || lower.contains('listing')) {
      return Icons.storefront_rounded;
    }
    if (lower.contains('size')) return Icons.straighten_rounded;
    return Icons.auto_awesome_rounded;
  }
}

class _ConversationMessage {
  final bool mine;
  final String text;
  final AssistantResponse? response;

  const _ConversationMessage._({
    required this.mine,
    required this.text,
    this.response,
  });

  factory _ConversationMessage.user(String text) =>
      _ConversationMessage._(mine: true, text: text);

  factory _ConversationMessage.assistant(AssistantResponse response) =>
      _ConversationMessage._(
        mine: false,
        text: response.reply,
        response: response,
      );
}

class _ConciergeHero extends StatelessWidget {
  final AssistantEntryPoint entryPoint;

  const _ConciergeHero({required this.entryPoint});

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (entryPoint) {
      AssistantEntryPoint.product =>
        'Build around this item using available listings and seller-provided details.',
      AssistantEntryPoint.cart =>
        'Complete the look, understand the estimate, and keep every cart change under your control.',
      AssistantEntryPoint.saved =>
        'Turn saved pieces into a coherent look while checking current availability.',
      AssistantEntryPoint.seller =>
        'Get precise guidance about listings, displayed fees, and seller tools.',
      AssistantEntryPoint.general =>
        'Outfits, product discovery, sizing guidance, checkout answers, and seller help in one conversation.',
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 226),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: const Color(0xFF151515),
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              image: true,
              label:
                  'Drip editorial: two people comparing vintage jackets in a clothing shop',
              child: Image.asset(
                'assets/editorial/drip_concierge_editorial_v2.jpg',
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0, .56, .84, 1],
                  colors: [
                    Colors.black.withValues(alpha: .96),
                    Colors.black.withValues(alpha: .84),
                    Colors.black.withValues(alpha: .30),
                    Colors.black.withValues(alpha: .10),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(19),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .46),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Wrap(
                      spacing: 8,
                      runSpacing: 3,
                      children: [
                        Text(
                          'APP-AWARE CONCIERGE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.15,
                          ),
                        ),
                        Text(
                          'DRIP EDITORIAL',
                          style: TextStyle(
                            color: Color(0xFFFFDFC0),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Ask the style question\nyou thought was too weird.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.4,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white,
                      height: 1.4,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _TrustPill(Icons.inventory_2_rounded, 'Live inventory'),
                      _TrustPill(Icons.lock_rounded, 'Stripe stays secure'),
                      _TrustPill(
                        Icons.record_voice_over_rounded,
                        'Body-neutral advice',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustPill(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iceBlue, size: 13),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _ConciergeMark extends StatelessWidget {
  final double size;

  const _ConciergeMark({required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .32),
      gradient: const LinearGradient(colors: [iceBlue, electricBlue]),
      boxShadow: [
        BoxShadow(
          color: electricBlue.withValues(alpha: .35),
          blurRadius: size * .35,
        ),
      ],
    ),
    child: Icon(Icons.auto_awesome_rounded, color: ink, size: size * .5),
  );
}

class _UserBubble extends StatelessWidget {
  final String text;

  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 560),
      margin: const EdgeInsets.only(left: 42, bottom: 13),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2766B2), Color(0xFF17437D)],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(6),
        ),
        boxShadow: [
          BoxShadow(color: electricBlue.withValues(alpha: .14), blurRadius: 16),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, height: 1.4),
      ),
    ),
  );
}

class _AssistantAnswer extends StatelessWidget {
  final AssistantResponse response;
  final AppState app;
  final ValueChanged<String> onPrompt;

  const _AssistantAnswer({
    required this.response,
    required this.app,
    required this.onPrompt,
  });

  @override
  Widget build(BuildContext context) {
    final recommended = response.productIds
        .map(app.catalogProducts.whereId)
        .whereType<Product>()
        .where(app.isListingAvailable)
        .where((product) => !app.isOwnListing(product))
        .toList(growable: false);
    return Semantics(
      liveRegion: true,
      label: 'Drip Concierge response',
      child: Padding(
        padding: const EdgeInsets.only(right: 24, bottom: 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _ConciergeMark(size: 30),
                const SizedBox(width: 8),
                Text(
                  'DRIP CONCIERGE',
                  style: TextStyle(
                    color: accentForeground(context),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxWidth: 660),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: .55),
                ),
              ),
              child: SelectionArea(
                child: Text(
                  response.reply,
                  style: const TextStyle(height: 1.5),
                ),
              ),
            ),
            if (response.outfit != null) ...[
              const SizedBox(height: 10),
              _OutfitSummary(plan: response.outfit!, app: app),
            ],
            if (recommended.isNotEmpty) ...[
              const SizedBox(height: 12),
              _RecommendationRail(products: recommended),
            ],
            if (response.needsHumanSupport) ...[
              const SizedBox(height: 10),
              const _HumanHandoff(),
            ],
            if (response.followUps.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final prompt in response.followUps)
                    ActionChip(
                      avatar: const Icon(Icons.arrow_outward_rounded, size: 15),
                      label: Text(prompt),
                      onPressed: () => onPrompt(prompt),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension on List<Product> {
  Product? whereId(String id) {
    for (final product in this) {
      if (product.id == id) return product;
    }
    return null;
  }
}

class _OutfitSummary extends StatelessWidget {
  final OutfitPlan plan;
  final AppState app;

  const _OutfitSummary({required this.plan, required this.app});

  @override
  Widget build(BuildContext context) {
    final products = plan.productIds
        .map(app.catalogProducts.whereId)
        .whereType<Product>()
        .toList();
    final sellers = products.map((item) => item.sellerHandle).toSet().length;
    final protection = MarketplacePolicy.buyerProtectionCents(
      plan.subtotalCents,
    );
    final shipping = sellers * MarketplacePolicy.shippingPerSellerCents;
    final estimate = plan.subtotalCents + protection + shipping;
    final insideBudget =
        plan.budgetCents == null || estimate <= plan.budgetCents!;
    return Container(
      constraints: const BoxConstraints(maxWidth: 660),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: electricBlue.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: electricBlue.withValues(alpha: .26)),
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: electricBlue.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.checkroom_rounded, color: electricBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  '${products.length} pieces · ${_money(estimate)} est. before tax',
                  style: TextStyle(
                    color: mutedForeground(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (plan.budgetCents != null)
            Icon(
              insideBudget ? Icons.check_circle_rounded : Icons.info_rounded,
              color: insideBudget ? const Color(0xFF2EBB88) : Colors.orange,
            ),
        ],
      ),
    );
  }
}

class _RecommendationRail extends StatelessWidget {
  final List<Product> products;

  const _RecommendationRail({required this.products});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 222,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: products.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (_, index) => _RecommendationCard(product: products[index]),
    ),
  );
}

class _RecommendationCard extends StatelessWidget {
  final Product product;

  const _RecommendationCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final saved = context.select<AppState, bool>(
      (app) => app.isFavorite(product),
    );
    return Container(
      width: 176,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: .55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                productImage(product, fit: BoxFit.cover, cacheWidth: 360),
                Positioned(
                  top: 7,
                  right: 7,
                  child: Material(
                    color: ink.withValues(alpha: .72),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: saved ? 'Remove from saved' : 'Save item',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          context.read<AppState>().toggleFavorite(product),
                      icon: Icon(
                        saved
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: saved ? const Color(0xFFFF6B9A) : Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_money((product.price * 100).round())} · ${product.condition}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mutedForeground(context),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 7),
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.push(
                      context,
                      dripRoute(ProductDetail(item: product)),
                    ),
                    child: const Text('View piece'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HumanHandoff extends StatelessWidget {
  const _HumanHandoff();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 660),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.orange.withValues(alpha: .25)),
    ),
    child: const Row(
      children: [
        Icon(Icons.support_agent_rounded, color: Colors.orange, size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'A human review is the right next step. A verified support contact is not available in this build yet.',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Drip Concierge is preparing an answer',
    child: Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Checking Drip…', style: TextStyle(color: muted)),
          ],
        ),
      ),
    ),
  );
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final ValueChanged<String?> onSend;
  final VoidCallback? onRetry;

  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: .96),
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onRetry != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: sending ? null : onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Retry last question'),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: !sending,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1200,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: sending ? null : (_) => onSend(null),
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText:
                            'Ask about a fit, item, checkout, or selling…',
                        prefixIcon: Icon(Icons.auto_awesome_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Semantics(
                    button: true,
                    label: 'Send question',
                    child: IconButton.filled(
                      tooltip: 'Send',
                      onPressed: sending ? null : () => onSend(null),
                      padding: const EdgeInsets.all(15),
                      icon: sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Seller details may be incomplete. Never share payment details in chat.',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedForeground(context), fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';
