import 'package:flutter/material.dart';

import 'ai_assistant_page.dart';
import 'assistant/assistant_models.dart';
import 'design_system.dart';
import 'home_feed.dart';
import 'market_page.dart';
import 'profile_page.dart';
import 'sell_page.dart';
import 'wishlist_page.dart';

class AppShell extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const AppShell({super.key, required this.onThemeToggle});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _desktopBreakpoint = 980.0;

  int index = 0;
  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    pages = [
      HomeFeed(onThemeToggle: widget.onThemeToggle),
      const MarketPage(),
      SellPage(onComplete: () => setState(() => index = 1)),
      const WishlistPage(),
      ProfilePage(onThemeToggle: widget.onThemeToggle),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final assistantEntryPoint = switch (index) {
      2 => AssistantEntryPoint.seller,
      3 => AssistantEntryPoint.saved,
      _ => AssistantEntryPoint.general,
    };
    void openAssistant() => Navigator.push(
      context,
      dripRoute(AiAssistantPage(entryPoint: assistantEntryPoint)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= _desktopBreakpoint;
        final pageStack = IndexedStack(
          index: index,
          children: List.generate(
            pages.length,
            (pageIndex) => TickerMode(
              enabled: index == pageIndex,
              child: HeroMode(
                enabled: index == pageIndex,
                child: pages[pageIndex],
              ),
            ),
          ),
        );

        return Scaffold(
          extendBody: !desktop,
          body: Stack(
            children: [
              const Positioned.fill(child: _ShellBackdrop()),
              if (desktop)
                SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
                        child: _DesktopDock(
                          selectedIndex: index,
                          onSelected: _selectPage,
                          onAskDrip: openAssistant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(34),
                          ),
                          child: Material(
                            color: Theme.of(
                              context,
                            ).scaffoldBackgroundColor.withValues(alpha: .97),
                            child: pageStack,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                pageStack,
            ],
          ),
          floatingActionButton: desktop
              ? null
              : _AskDripLauncher(onTap: openAssistant),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          bottomNavigationBar: desktop
              ? null
              : _MobileDock(selectedIndex: index, onSelected: _selectPage),
        );
      },
    );
  }

  void _selectPage(int nextIndex) {
    if (nextIndex == index) return;
    setState(() => index = nextIndex);
  }
}

class _ShellBackdrop extends StatelessWidget {
  const _ShellBackdrop();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF050A13), ink, Color(0xFF0B1930)]
                : const [
                    Color(0xFFFBFCFF),
                    Color(0xFFF3F7FC),
                    Color(0xFFE8F2FF),
                  ],
            stops: const [0, .55, 1],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -180,
              right: -110,
              child: _AmbientOrb(
                size: 410,
                color: electricBlue.withValues(alpha: dark ? .13 : .16),
              ),
            ),
            Positioned(
              bottom: -220,
              left: -160,
              child: _AmbientOrb(
                size: 460,
                color: const Color(
                  0xFF8B5CF6,
                ).withValues(alpha: dark ? .08 : .07),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _AmbientOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
    ),
  );
}

class _MobileDock extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _MobileDock({required this.selectedIndex, required this.onSelected});

  static const _items = <(IconData, String)>[
    (Icons.home_rounded, 'Home'),
    (Icons.explore_rounded, 'Market'),
    (Icons.add_rounded, 'Sell'),
    (Icons.favorite_rounded, 'Saved'),
    (Icons.person_rounded, 'You'),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
    minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
    child: Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF207101F), Color(0xF2142540)],
        ),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: Colors.white.withValues(alpha: .15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .34),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: electricBlue.withValues(alpha: .12),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: List.generate(_items.length, (itemIndex) {
          final item = _items[itemIndex];
          return Expanded(
            child: _DockItem(
              icon: item.$1,
              label: item.$2,
              selected: selectedIndex == itemIndex,
              emphasized: itemIndex == 2,
              onTap: () => onSelected(itemIndex),
            ),
          );
        }),
      ),
    ),
  );
}

class _DockItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool emphasized;
  final VoidCallback onTap;

  const _DockItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.emphasized,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: emphasized ? 'Sell an item' : label,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            gradient: emphasized
                ? const LinearGradient(colors: [iceBlue, electricBlue])
                : selected
                ? LinearGradient(
                    colors: [
                      electricBlue.withValues(alpha: .24),
                      electricBlue.withValues(alpha: .09),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: emphasized
                  ? Colors.white.withValues(alpha: .45)
                  : selected
                  ? iceBlue.withValues(alpha: .22)
                  : Colors.transparent,
            ),
            boxShadow: emphasized
                ? [
                    BoxShadow(
                      color: electricBlue.withValues(alpha: .34),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: emphasized
                    ? ink
                    : selected
                    ? iceBlue
                    : muted,
                size: emphasized ? 25 : 21,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: emphasized
                      ? ink
                      : selected
                      ? iceBlue
                      : muted,
                  fontSize: 9.5,
                  fontWeight: selected || emphasized
                      ? FontWeight.w900
                      : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DesktopDock extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onAskDrip;

  const _DesktopDock({
    required this.selectedIndex,
    required this.onSelected,
    required this.onAskDrip,
  });

  static const _items = <(IconData, String, String)>[
    (Icons.home_rounded, 'Home', 'Your edit'),
    (Icons.explore_rounded, 'Market', 'Browse all'),
    (Icons.add_box_rounded, 'Sell', 'List a piece'),
    (Icons.favorite_rounded, 'Saved', 'Your shortlist'),
    (Icons.person_rounded, 'You', 'Profile & sales'),
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: 226,
    padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
    decoration: BoxDecoration(
      color: ink.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withValues(alpha: .12)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .32),
          blurRadius: 32,
          offset: const Offset(0, 16),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 2, 10, 0),
          child: _DesktopBrand(),
        ),
        const SizedBox(height: 30),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: _items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 7),
            itemBuilder: (context, itemIndex) {
              final item = _items[itemIndex];
              final selected = selectedIndex == itemIndex;
              return Semantics(
                button: true,
                selected: selected,
                label: item.$2,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelected(itemIndex),
                    borderRadius: BorderRadius.circular(19),
                    child: AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      constraints: const BoxConstraints(minHeight: 62),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      decoration: BoxDecoration(
                        gradient: selected
                            ? LinearGradient(
                                colors: [
                                  electricBlue.withValues(alpha: .3),
                                  electricBlue.withValues(alpha: .08),
                                ],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(
                          color: selected
                              ? iceBlue.withValues(alpha: .24)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: selected
                                  ? electricBlue
                                  : Colors.white.withValues(alpha: .055),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              item.$1,
                              size: 20,
                              color: selected ? ink : muted,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.$2,
                                  style: TextStyle(
                                    color: selected ? Colors.white : muted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.$3,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: selected
                                        ? iceBlue.withValues(alpha: .74)
                                        : muted.withValues(alpha: .64),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _AskDripLauncher(onTap: onAskDrip, expanded: true),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .045),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFF7BE8BF),
                size: 14,
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Secure checkout',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DesktopBrand extends StatelessWidget {
  const _DesktopBrand();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [iceBlue, electricBlue]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: electricBlue.withValues(alpha: .28),
              blurRadius: 18,
            ),
          ],
        ),
        child: const Icon(Icons.water_drop_rounded, color: ink, size: 21),
      ),
      const SizedBox(width: 11),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'drip.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              height: .9,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.5,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'MARKETPLACE',
            style: TextStyle(
              color: muted,
              fontSize: 7.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.25,
            ),
          ),
        ],
      ),
    ],
  );
}

class _AskDripLauncher extends StatelessWidget {
  final VoidCallback onTap;
  final bool expanded;

  const _AskDripLauncher({required this.onTap, this.expanded = false});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Open Drip Concierge',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 13 : 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Color(0xFF255B99), Color(0xFF102A4D)],
            ),
            border: Border.all(color: iceBlue.withValues(alpha: .65)),
            boxShadow: [
              BoxShadow(
                color: electricBlue.withValues(alpha: .28),
                blurRadius: 20,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded, color: iceBlue, size: 19),
              const SizedBox(width: 8),
              if (expanded)
                const Expanded(child: _AskDripLabel())
              else
                const _AskDripLabel(),
              if (expanded) ...[
                const SizedBox(width: 7),
                const Icon(
                  Icons.arrow_outward_rounded,
                  color: Colors.white70,
                  size: 15,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _AskDripLabel extends StatelessWidget {
  const _AskDripLabel();

  @override
  Widget build(BuildContext context) => const Text(
    'Ask Drip',
    maxLines: 1,
    textAlign: TextAlign.center,
    style: TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w900,
    ),
  );
}
