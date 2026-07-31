import 'package:flutter/material.dart';

import 'design_system.dart';
import 'product_model.dart';
import 'sample_data.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Messages')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 35),
      children: [
        const PageHeader(
          eyebrow: 'Community',
          title: 'Talk with sellers',
          subtitle:
              'Ask for more photos, send an offer, or check shipping before buying.',
        ),
        const SizedBox(height: 20),
        ...sellerStories.map((story) => _MessageTile(story: story)),
      ],
    ),
  );
}

class _MessageTile extends StatelessWidget {
  final SellerStory story;
  const _MessageTile({required this.story});

  void openConversation(BuildContext context) => Navigator.push(
    context,
    dripRoute(ConversationPage(seller: story.seller, handle: story.handle)),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => openConversation(context),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              DripAvatar(label: story.seller, size: 50, live: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.handle,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '“I can ship today. Want to make an offer?”',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              GlassButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                onTap: () => openConversation(context),
                child: const Text(
                  'Chat',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ConversationPage extends StatefulWidget {
  final String seller;
  final String handle;
  final Product? product;

  const ConversationPage({
    super.key,
    required this.seller,
    required this.handle,
    this.product,
  });

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final controller = TextEditingController();
  final messages = <String>['I can ship today. Want any extra photos?'];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void sendMessage() {
    final message = controller.text.trim();
    if (message.isEmpty) return;
    setState(() => messages.add(message));
    controller.clear();
  }

  void makeOffer() {
    final product = widget.product;
    if (product == null) {
      controller.text = 'Hey! What’s your best price?';
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Make an offer',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                '${product.name} is listed at \$${product.price.toStringAsFixed(0)}.',
                style: TextStyle(color: mutedForeground(sheetContext)),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [.9, .85, .8].map((multiplier) {
                  final offer = product.price * multiplier;
                  return GlassButton(
                    onTap: () {
                      Navigator.pop(sheetContext);
                      setState(
                        () => messages.add(
                          'Offer sent: \$${offer.toStringAsFixed(0)} for ${product.name}.',
                        ),
                      );
                    },
                    child: Text(
                      '\$${offer.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.handle)),
    body: Column(
      children: [
        if (widget.product case final product?)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox.square(
                    dimension: 54,
                    child: productImage(product),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '\$${product.price.toStringAsFixed(0)} · ${product.condition}',
                        style: TextStyle(color: mutedForeground(context)),
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: makeOffer, child: const Text('Offer')),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final mine = index > 0;
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 310),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: mine
                        ? electricBlue.withValues(alpha: .18)
                        : Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Text(messages[index]),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Make an offer',
                  onPressed: makeOffer,
                  icon: const Icon(Icons.sell_rounded),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onSubmitted: (_) => sendMessage(),
                    decoration: const InputDecoration(
                      hintText: 'Message the seller…',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Send message',
                  onPressed: sendMessage,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
