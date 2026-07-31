import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'commerce_model.dart';
import 'design_system.dart';

class SellPage extends StatefulWidget {
  final VoidCallback onComplete;
  const SellPage({super.key, required this.onComplete});

  @override
  State<SellPage> createState() => _SellPageState();
}

class _SellPageState extends State<SellPage> {
  static const _samplePhotos = <(String, String)>[
    ('assets/products/black_luxe_runner.jpg', 'Black runner'),
    ('assets/products/washed_purple_graphic_tee.jpg', 'Graphic tee'),
    ('assets/products/chair_varsity_jacket_natural_v2.jpg', 'Varsity jacket'),
    ('assets/products/shelf_crossbody_bag.jpg', 'Crossbody bag'),
  ];

  final formKey = GlobalKey<FormState>();
  final titleController = TextEditingController();
  final brandController = TextEditingController();
  final categoryController = TextEditingController();
  final sizeController = TextEditingController();
  final priceController = TextEditingController();
  final storyController = TextEditingController();
  int condition = 0;
  String? selectedPhoto;
  bool sellerDeclaration = false;
  bool publishing = false;

  @override
  void dispose() {
    titleController.dispose();
    brandController.dispose();
    categoryController.dispose();
    sizeController.dispose();
    priceController.dispose();
    storyController.dispose();
    super.dispose();
  }

  Future<void> choosePhoto() async {
    final photo = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose a sample photo',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                'Bundled media keeps this acquisition demo reliable. Production uploads plug into object storage.',
                style: TextStyle(
                  color: mutedForeground(sheetContext),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.05,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _samplePhotos.length,
                itemBuilder: (context, index) {
                  final option = _samplePhotos[index];
                  return InkWell(
                    onTap: () => Navigator.pop(sheetContext, option.$1),
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.asset(option.$1, fit: BoxFit.cover),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: ink.withValues(alpha: .82),
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(18),
                                ),
                              ),
                              child: Text(
                                option.$2,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (photo != null && mounted) setState(() => selectedPhoto = photo);
  }

  Future<void> previewListing() async {
    FocusScope.of(context).unfocus();
    final valid = formKey.currentState?.validate() ?? false;
    if (selectedPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one product photo.')),
      );
    }
    if (!sellerDeclaration) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirm the seller declaration to continue.'),
        ),
      );
    }
    if (!valid || selectedPhoto == null || !sellerDeclaration) return;

    final app = context.read<AppState>();
    final conditionLabel = ['New', 'Excellent', 'Good', 'Worn'][condition];
    final price = double.parse(priceController.text);
    final sellerFee = MarketplacePolicy.sellerFee(
      price,
      sellerIsPro: app.sellerPro,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ready to go live',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                '${brandController.text.trim()} · ${categoryController.text.trim()} · $conditionLabel',
                style: TextStyle(color: mutedForeground(sheetContext)),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(sheetContext).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.asset(
                        selectedPhoto!,
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titleController.text.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Size ${sizeController.text.trim().isEmpty ? 'One size' : sizeController.text.trim()}',
                            style: TextStyle(
                              color: mutedForeground(sheetContext),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '\$${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: electricBlue,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _EarningsCard(price: price, fee: sellerFee, isPro: app.sellerPro),
              const SizedBox(height: 17),
              StatefulBuilder(
                builder: (context, updateSheet) => GlassButton(
                  selected: true,
                  onTap: publishing
                      ? null
                      : () async {
                          updateSheet(() => publishing = true);
                          final product = await app.createListing(
                            title: titleController.text.trim(),
                            brand: brandController.text.trim(),
                            category: categoryController.text.trim(),
                            condition: conditionLabel,
                            price: price,
                            description: storyController.text.trim(),
                            imageAsset: selectedPhoto!,
                            size: sizeController.text.trim(),
                          );
                          if (!mounted || !sheetContext.mounted) return;
                          if (product == null) {
                            updateSheet(() => publishing = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  app.commerceError ?? 'Could not publish.',
                                ),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(sheetContext);
                          _resetForm();
                          widget.onComplete();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${product.name} is live in Market and Seller Studio.',
                              ),
                            ),
                          );
                        },
                  child: Center(
                    child: publishing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Publish listing',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resetForm() {
    titleController.clear();
    brandController.clear();
    categoryController.clear();
    sizeController.clear();
    priceController.clear();
    storyController.clear();
    setState(() {
      selectedPhoto = null;
      sellerDeclaration = false;
      condition = 0;
      publishing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sellerIsPro = context.watch<AppState>().sellerPro;
    return SafeArea(
      bottom: false,
      child: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 115),
          children: [
            const PageHeader(
              eyebrow: 'New listing',
              title: 'Turn your closet into revenue',
              subtitle:
                  'Create one real local inventory record, preview the economics, and publish it across Drip.',
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: choosePhoto,
              borderRadius: BorderRadius.circular(26),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                constraints: const BoxConstraints(minHeight: 220),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: electricBlue.withValues(alpha: .45),
                  ),
                  gradient: const LinearGradient(
                    colors: [panel, Color(0xFF162D4C)],
                  ),
                  image: selectedPhoto == null
                      ? null
                      : DecorationImage(
                          image: AssetImage(selectedPhoto!),
                          fit: BoxFit.cover,
                          colorFilter: ColorFilter.mode(
                            ink.withValues(alpha: .14),
                            BlendMode.darken,
                          ),
                        ),
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: .82),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selectedPhoto == null
                              ? Icons.add_photo_alternate_rounded
                              : Icons.swap_horiz_rounded,
                          color: iceBlue,
                        ),
                        const SizedBox(width: 9),
                        Text(
                          selectedPhoto == null
                              ? 'Choose sample product photo'
                              : 'Change product photo',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Sandbox media · production uploads use a replaceable storage gateway',
              style: TextStyle(color: muted, fontSize: 10),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            const SectionHeading('Piece details'),
            _field(
              context,
              'Listing title',
              'e.g. Nike black runner size 10',
              controller: titleController,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _field(
                    context,
                    'Brand',
                    'Nike, Puma…',
                    controller: brandController,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    context,
                    'Category',
                    'Shoes, tees…',
                    controller: categoryController,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _field(
              context,
              'Size',
              'M, 10, or One size',
              controller: sizeController,
              isRequired: false,
            ),
            const SizedBox(height: 20),
            const Text(
              'CONDITION',
              style: TextStyle(
                color: muted,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                4,
                (i) => GlassButton(
                  selected: condition == i,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  onTap: () => setState(() => condition = i),
                  child: Text(
                    ['New', 'Excellent', 'Good', 'Worn'][i],
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _field(
              context,
              'Your price',
              '\$10 – \$10,000',
              controller: priceController,
              keyboard: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              validator: (value) {
                final price = int.tryParse(value ?? '');
                return price != null && price >= 10 && price <= 10000
                    ? null
                    : 'Enter a price from 10 to 10,000';
              },
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: priceController,
              builder: (context, value, _) {
                final price = double.tryParse(value.text) ?? 0;
                final fee = price <= 0
                    ? 0.0
                    : MarketplacePolicy.sellerFee(
                        price,
                        sellerIsPro: sellerIsPro,
                      );
                return _EarningsCard(
                  price: price,
                  fee: fee,
                  isPro: sellerIsPro,
                );
              },
            ),
            const SizedBox(height: 12),
            _field(
              context,
              'Story and condition notes',
              'Call out wear or flaws and tell buyers why it is worth buying',
              controller: storyController,
              lines: 3,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: sellerDeclaration,
              onChanged: (value) =>
                  setState(() => sellerDeclaration = value ?? false),
              title: const Text(
                'I own this item and accurately described its condition.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Seller declaration only; this does not create an authentication badge.',
                style: TextStyle(color: muted, fontSize: 10),
              ),
            ),
            const SizedBox(height: 12),
            GlassButton(
              selected: true,
              onTap: previewListing,
              child: const Center(
                child: Text(
                  'Preview listing',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context,
    String label,
    String hint, {
    required TextEditingController controller,
    TextInputType? keyboard,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    int lines = 1,
    bool isRequired = true,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 7),
      TextFormField(
        controller: controller,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        maxLines: lines,
        textInputAction: lines > 1
            ? TextInputAction.newline
            : TextInputAction.next,
        validator:
            validator ??
            (value) =>
                isRequired && (value ?? '').trim().isEmpty ? 'Required' : null,
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainer,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    ],
  );
}

class _EarningsCard extends StatelessWidget {
  final double price;
  final double fee;
  final bool isPro;

  const _EarningsCard({
    required this.price,
    required this.fee,
    required this.isPro,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: electricBlue.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: electricBlue.withValues(alpha: .18)),
    ),
    child: Column(
      children: [
        _line('Listing price', price),
        const SizedBox(height: 6),
        _line('Selling fee · ${isPro ? 'Pro 7%' : 'Free 10%'}', -fee),
        const Divider(height: 18),
        _line('Estimated payout', mathMax(0, price - fee), strong: true),
        const SizedBox(height: 7),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Buyer pays shipping. Exact order fees are snapshotted at checkout.',
            style: TextStyle(color: muted, fontSize: 10),
          ),
        ),
      ],
    ),
  );

  double mathMax(double a, double b) => a > b ? a : b;

  Widget _line(String label, double value, {bool strong = false}) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: strong ? null : muted,
            fontSize: 12,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ),
      Text(
        '${value < 0 ? '−' : ''}\$${value.abs().toStringAsFixed(2)}',
        style: TextStyle(
          color: strong ? electricBlue : null,
          fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
        ),
      ),
    ],
  );
}
