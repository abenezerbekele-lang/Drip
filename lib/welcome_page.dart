import 'package:flutter/material.dart';

import 'design_system.dart';

class WelcomePage extends StatelessWidget {
  final VoidCallback onDone;
  const WelcomePage({super.key, required this.onDone});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - value)),
            child: child,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 34, 24, 30),
          children: [
            const Text(
              'drip.',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: -2.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(minHeight: 330),
              clipBehavior: Clip.antiAlias,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF244F89),
                    Color(0xFF0A1629),
                    Color(0xFF07101F),
                  ],
                ),
                border: Border.all(color: iceBlue.withValues(alpha: .35)),
                boxShadow: [
                  BoxShadow(
                    color: electricBlue.withValues(alpha: .2),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -42,
                    top: -38,
                    width: 235,
                    height: 190,
                    child: Opacity(
                      opacity: .82,
                      child: Image.asset(
                        'assets/products/black_luxe_runner.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CURATED DAILY',
                        style: TextStyle(
                          color: iceBlue,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      SizedBox(height: 145),
                      Text(
                        'Shop the fit.\nJoin the community.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          height: 1.03,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.4,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Protected checkout, smarter styling, and community-first resale—all in one place.',
                        style: TextStyle(color: Colors.white70, height: 1.45),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _WelcomeFeature(
              Icons.shield_rounded,
              'Transparent buyer protection',
            ),
            const _WelcomeFeature(
              Icons.auto_awesome_rounded,
              'AI outfit helper',
            ),
            const _WelcomeFeature(
              Icons.image_search_rounded,
              'Find similar items by photo',
            ),
            const _WelcomeFeature(
              Icons.forum_rounded,
              'Message sellers and make offers',
            ),
            const SizedBox(height: 18),
            GlassButton(
              selected: true,
              onTap: onDone,
              child: const Center(
                child: Text(
                  'Start shopping',
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
    ),
  );
}

class _WelcomeFeature extends StatelessWidget {
  final IconData icon;
  final String text;
  const _WelcomeFeature(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: electricBlue.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: electricBlue, size: 20),
        ),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}
