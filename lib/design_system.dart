import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'product_model.dart';

const ink = Color(0xFF07101F);
const panel = Color(0xFF101D33);
const electricBlue = Color(0xFF58A6FF);
const iceBlue = Color(0xFFBDE7FF);
const signalGreen = Color(0xFF36D49A);
const softViolet = Color(0xFF8B78FF);
const muted = Color(0xFF8996AA);

Color accentForeground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? iceBlue
    : const Color(0xFF1F65B5);

Color mutedForeground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFACB8C9)
    : const Color(0xFF58677C);

const productGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 270,
  childAspectRatio: .64,
  crossAxisSpacing: 15,
  mainAxisSpacing: 15,
);

class GlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final double radius;

  const GlassButton({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    this.selected = false,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      selected: selected && onTap != null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: onTap == null ? .48 : 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: selected && onTap != null
                  ? [
                      BoxShadow(
                        color: electricBlue.withValues(alpha: .28),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(radius),
                child: Ink(
                  padding: padding,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: selected
                          ? const [Color(0xFF224C88), Color(0xFF102648)]
                          : dark
                          ? const [Color(0xFF172944), Color(0xFF0D192C)]
                          : const [Color(0xFFFFFFFF), Color(0xFFE8F1FF)],
                    ),
                    border: Border.all(
                      color: selected
                          ? iceBlue.withValues(alpha: .8)
                          : (dark ? Colors.white12 : const Color(0xFFD7E4F6)),
                    ),
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(color: selected ? Colors.white : null),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: selected ? Colors.white : null),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onTap;

  const SectionHeading(this.title, {super.key, this.action, this.onTap});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 3,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 25,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [iceBlue, electricBlue, softViolet],
                ),
                boxShadow: [
                  BoxShadow(
                    color: electricBlue.withValues(alpha: .24),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.45,
                ),
              ),
            ),
          ],
        ),
      ),
      if (action != null) ...[
        const SizedBox(width: 10),
        Flexible(
          flex: 2,
          child: onTap != null
              ? TextButton(
                  onPressed: onTap,
                  child: Text(
                    action!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    action!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: mutedForeground(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
      ],
    ],
  );
}

class PageHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow.toUpperCase(),
              style: TextStyle(
                color: accentForeground(context),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: TextStyle(color: mutedForeground(context), height: 1.4),
            ),
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

class DripAvatar extends StatelessWidget {
  final String label;
  final double size;
  final bool live;
  final IconData? icon;

  const DripAvatar({
    super.key,
    required this.label,
    this.size = 48,
    this.live = false,
    this.icon,
  });

  static const _palettes = [
    [Color(0xFF58A6FF), Color(0xFF6D5DFB)],
    [Color(0xFFFF6B9A), Color(0xFF7C3AED)],
    [Color(0xFFFFB86B), Color(0xFFFF5C7A)],
    [Color(0xFF2EE6A6), Color(0xFF1C7CFF)],
    [Color(0xFFBDE7FF), Color(0xFF244F89)],
  ];

  @override
  Widget build(BuildContext context) {
    final seed = label.codeUnits.fold<int>(0, (sum, code) => sum + code);
    final colors = _palettes[seed % _palettes.length];
    final initials = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            padding: EdgeInsets.all(live ? 3 : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: live
                  ? const LinearGradient(colors: [iceBlue, electricBlue])
                  : null,
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.last.withValues(alpha: .28),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Center(
                child: icon == null
                    ? Text(
                        initials.isEmpty ? '?' : initials,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: size * .34,
                        ),
                      )
                    : Icon(icon, color: Colors.white, size: size * .42),
              ),
            ),
          ),
          if (live)
            Positioned(
              right: 1,
              bottom: 1,
              child: Container(
                width: size * .24,
                height: size * .24,
                decoration: BoxDecoration(
                  color: const Color(0xFF2EE6A6),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Route<T> dripRoute<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (_, _, _) => page,
  transitionDuration: const Duration(milliseconds: 360),
  reverseTransitionDuration: const Duration(milliseconds: 260),
  transitionsBuilder: (context, animation, _, child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.05, .04),
          end: Offset.zero,
        ).animate(curve),
        child: ScaleTransition(
          scale: Tween<double>(begin: .985, end: 1).animate(curve),
          child: child,
        ),
      ),
    );
  },
);

Widget productImage(
  Product item, {
  BoxFit fit = BoxFit.cover,
  int? cacheWidth,
}) {
  if (item.isAssetImage) {
    return Image.asset(
      item.image,
      fit: fit,
      cacheWidth: cacheWidth,
      errorBuilder: (_, _, _) => const ProductImageFallback(),
    );
  }

  return Image.network(
    item.image,
    fit: fit,
    cacheWidth: cacheWidth,
    frameBuilder: (context, child, frame, loadedSynchronously) {
      if (loadedSynchronously || frame != null) return child;
      return const ProductImagePlaceholder();
    },
    errorBuilder: (_, _, _) => const ProductImageFallback(),
  );
}

class ProductImagePlaceholder extends StatelessWidget {
  const ProductImagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: Center(
      child: SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: electricBlue.withValues(alpha: .7),
        ),
      ),
    ),
  );
}

class ProductImageFallback extends StatelessWidget {
  const ProductImageFallback({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 96 || constraints.maxHeight < 96;
        return Center(
          child: compact
              ? const Icon(Icons.checkroom_rounded, size: 23, color: muted)
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.checkroom_rounded, size: 38, color: muted),
                    SizedBox(height: 6),
                    Text(
                      'Image unavailable',
                      style: TextStyle(color: muted, fontSize: 10),
                    ),
                  ],
                ),
        );
      },
    ),
  );
}

class ProductTile extends StatefulWidget {
  final Product item;
  final VoidCallback onTap;
  const ProductTile({super.key, required this.item, required this.onTap});

  @override
  State<ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<ProductTile> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final promoted = context.select<AppState, bool>(
      (app) => app.isPromoted(item),
    );
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.45;
    final active = _hovered || _focused;
    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Semantics(
      button: true,
      container: true,
      explicitChildNodes: true,
      label:
          '${item.name}, ${item.brand}, ${item.price.toStringAsFixed(0)} dollars',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          duration: duration,
          curve: Curves.easeOutCubic,
          scale: _pressed ? .985 : (active ? 1.012 : 1),
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0xFF14233B), Color(0xFF09111F)]
                    : const [Color(0xFFFFFFFF), Color(0xFFF2F6FC)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: active
                    ? electricBlue.withValues(alpha: dark ? .68 : .48)
                    : dark
                    ? Colors.white.withValues(alpha: .11)
                    : const Color(0xFFDCE5F1),
                width: active ? 1.2 : .8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .3 : .1),
                  blurRadius: active ? 28 : 20,
                  offset: Offset(0, active ? 15 : 11),
                ),
                BoxShadow(
                  color: electricBlue.withValues(
                    alpha: active ? (dark ? .18 : .13) : .045,
                  ),
                  blurRadius: active ? 34 : 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                onFocusChange: (value) => setState(() => _focused = value),
                onHighlightChanged: (value) => setState(() => _pressed = value),
                borderRadius: BorderRadius.circular(24),
                splashColor: electricBlue.withValues(alpha: .12),
                highlightColor: electricBlue.withValues(alpha: .045),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment.topLeft,
                                radius: 1.25,
                                colors: [
                                  electricBlue.withValues(alpha: .22),
                                  Theme.of(context).colorScheme.surfaceContainer
                                      .withValues(alpha: .32),
                                  ink.withValues(alpha: .24),
                                ],
                              ),
                            ),
                          ),
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(23),
                            ),
                            child: Hero(
                              tag: 'product-image-${item.id}',
                              child: AnimatedScale(
                                duration: duration,
                                curve: Curves.easeOutCubic,
                                scale: active ? 1.035 : 1,
                                child: RepaintBoundary(
                                  child: productImage(item, cacheWidth: 640),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    stops: const [0, .3, .7, 1],
                                    colors: [
                                      Colors.white.withValues(alpha: .13),
                                      Colors.transparent,
                                      ink.withValues(alpha: .04),
                                      ink.withValues(alpha: .58),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .15),
                                    width: .8,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            left: 10,
                            right: 62,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _ProductMediaBadge(role: item.mediaRole),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Consumer<AppState>(
                              builder: (context, app, _) {
                                final saved = app.isFavorite(item);
                                final saveDuration = reducedMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 160);
                                return Semantics(
                                  button: true,
                                  excludeSemantics: true,
                                  label: saved
                                      ? 'Remove from saved'
                                      : 'Save item',
                                  onTap: () => app.toggleFavorite(item),
                                  child: IconButton.filled(
                                    tooltip: saved
                                        ? 'Remove from saved'
                                        : 'Save item',
                                    onPressed: () => app.toggleFavorite(item),
                                    style: IconButton.styleFrom(
                                      backgroundColor: saved
                                          ? Colors.white.withValues(alpha: .94)
                                          : ink.withValues(alpha: .78),
                                      foregroundColor: saved
                                          ? const Color(0xFFE83E75)
                                          : Colors.white,
                                      minimumSize: const Size(44, 44),
                                      padding: EdgeInsets.zero,
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: saved ? .8 : .18,
                                        ),
                                      ),
                                    ),
                                    icon: AnimatedSwitcher(
                                      duration: saveDuration,
                                      switchInCurve: Curves.easeOutBack,
                                      transitionBuilder: (child, animation) =>
                                          ScaleTransition(
                                            scale: animation,
                                            child: child,
                                          ),
                                      child: Icon(
                                        saved
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                        key: ValueKey(saved),
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Positioned(
                            left: 10,
                            bottom: 10,
                            child: _ProductTrustBadge(promoted: promoted),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(13, 11, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.brand.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: accentForeground(context),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.05,
                                  ),
                                ),
                              ),
                              if (!largeText) ...[
                                const SizedBox(width: 8),
                                _ProductConditionBadge(
                                  condition: item.condition,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              height: 1.08,
                              letterSpacing: -.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.vibe,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: mutedForeground(context),
                              fontSize: 10.5,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 9),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final showArrow = constraints.maxWidth >= 138;
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '\$${item.price.toStringAsFixed(0)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: dark
                                            ? Colors.white
                                            : const Color(0xFF10233E),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                        height: 1,
                                        letterSpacing: -.45,
                                      ),
                                    ),
                                  ),
                                  if (!largeText) ...[
                                    const SizedBox(width: 4),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'USD',
                                        style: TextStyle(
                                          color: mutedForeground(context),
                                          fontSize: 8,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: .65,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (showArrow && !largeText) ...[
                                    const Spacer(),
                                    AnimatedContainer(
                                      duration: duration,
                                      width: 27,
                                      height: 27,
                                      decoration: BoxDecoration(
                                        color: active
                                            ? electricBlue
                                            : electricBlue.withValues(
                                                alpha: dark ? .14 : .1,
                                              ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.arrow_outward_rounded,
                                        size: 14,
                                        color: active
                                            ? ink
                                            : accentForeground(context),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductMediaBadge extends StatelessWidget {
  final ProductMediaRole role;

  const _ProductMediaBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final sellerPhoto = role != ProductMediaRole.demoCatalog;
    return Container(
      constraints: const BoxConstraints(maxWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .79),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .17)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: sellerPhoto
                  ? const Color(0xFF56E5B7)
                  : const Color(0xFFBFA8FF),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color:
                      (sellerPhoto
                              ? const Color(0xFF56E5B7)
                              : const Color(0xFFBFA8FF))
                          .withValues(alpha: .55),
                  blurRadius: 5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              role.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: .55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTrustBadge extends StatelessWidget {
  final bool promoted;

  const _ProductTrustBadge({required this.promoted});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: ink.withValues(alpha: .8),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: .15)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          promoted ? Icons.bolt_rounded : Icons.shield_rounded,
          color: promoted ? const Color(0xFFCEB9FF) : iceBlue,
          size: 12,
        ),
        const SizedBox(width: 4),
        Text(
          promoted ? 'PROMOTED' : 'PROTECTED',
          style: const TextStyle(
            color: iceBlue,
            fontSize: 8.5,
            fontWeight: FontWeight.w900,
            letterSpacing: .72,
          ),
        ),
      ],
    ),
  );
}

class _ProductConditionBadge extends StatelessWidget {
  final String condition;

  const _ProductConditionBadge({required this.condition});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final normalized = condition.trim().toLowerCase();
    final color = switch (normalized) {
      'new' => const Color(0xFF39D9A3),
      'excellent' => const Color(0xFF63B3FF),
      _ => const Color(0xFFFFB963),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? .13 : .1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            condition,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: dark ? Colors.white.withValues(alpha: .86) : ink,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
