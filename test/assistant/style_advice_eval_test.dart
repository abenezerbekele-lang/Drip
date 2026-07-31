import 'package:flutter_test/flutter_test.dart';

import 'package:drip/app_state.dart';
import 'package:drip/assistant/assistant_models.dart';
import 'package:drip/assistant/local_concierge.dart';

void main() {
  const gateway = LocalAssistantGateway();

  Future<AssistantResponse> ask(
    String prompt, {
    String? focusProductId,
    AssistantEntryPoint entryPoint = AssistantEntryPoint.general,
  }) => gateway.respond(
    AssistantRequest(
      message: prompt,
      history: const [],
      context: AssistantContext.fromAppState(
        AppState(),
        entryPoint: entryPoint,
        focusProductId: focusProductId,
      ),
    ),
  );

  void expectConcepts(
    AssistantResponse response,
    List<List<String>> concepts, {
    List<String> forbidden = const [],
    bool expectNoProducts = false,
  }) {
    final reply = response.reply.toLowerCase();
    expect(
      reply,
      isNot(contains('what would you like to solve first')),
      reason: 'The concierge returned its generic capability message.',
    );
    for (final alternatives in concepts) {
      expect(
        alternatives.any(reply.contains),
        isTrue,
        reason:
            'Expected one of ${alternatives.join(' / ')} in: ${response.reply}',
      );
    }
    for (final phrase in forbidden) {
      expect(
        reply,
        isNot(contains(phrase)),
        reason: 'The answer used disallowed phrasing: $phrase',
      );
    }
    if (expectNoProducts) {
      expect(
        response.productIds,
        isEmpty,
        reason: 'A general style question should not become a product search.',
      );
    }
  }

  group('unconventional styling questions', () {
    test('explains how brown and black can work together', () async {
      final response = await ask(
        'Can I wear brown shoes with black pants without it looking like a mistake?',
      );

      expectConcepts(response, const [
        ['brown'],
        ['black'],
        ['can work', 'works', 'yes'],
        ['contrast', 'tone', 'texture', 'repeat', 'neutral'],
      ], expectNoProducts: true);
    });

    test(
      'treats socks and sandals as contextual, not categorically wrong',
      () async {
        final response = await ask('Are socks with sandals always wrong?');

        expectConcepts(response, const [
          ['socks'],
          ['sandals'],
          ['context', 'intentional', 'casual', 'sport'],
          ['color', 'proportion', 'clean', 'texture'],
        ], expectNoProducts: true);
      },
    );

    test(
      'qualifies sneakers with a suit by dress code and shoe design',
      () async {
        final response = await ask(
          'Can clean sneakers work with a suit at a wedding?',
        );

        expectConcepts(response, const [
          ['sneaker'],
          ['suit'],
          ['dress code', 'formality', 'invitation', 'occasion'],
          ['clean', 'minimal', 'sleek', 'low-profile'],
        ], expectNoProducts: true);
      },
    );

    test('makes mixed silver and gold jewelry feel intentional', () async {
      final response = await ask('Can I mix silver and gold jewelry?');

      expectConcepts(response, const [
        ['silver'],
        ['gold'],
        ['repeat', 'bridge', 'intentional', 'balance'],
      ], expectNoProducts: true);
    });

    test('balances stripes and plaid through scale and color', () async {
      final response = await ask('Can I wear stripes with plaid?');

      expectConcepts(response, const [
        ['stripe'],
        ['plaid'],
        ['scale', 'size'],
        ['shared color', 'color family', 'one color'],
        ['dominant', 'quieter', 'secondary'],
      ], expectNoProducts: true);
    });
  });

  group('garment care and material uncertainty', () {
    test('gives cautious, heat-aware oil stain guidance', () async {
      final response = await ask(
        'How do I remove a fresh oil stain from a cotton T-shirt?',
      );

      expectConcepts(
        response,
        const [
          ['blot'],
          ['care label', 'label'],
          ['spot test', 'test a hidden', 'test first'],
          ['air dry', 'avoid the dryer', 'no dryer', 'heat can set'],
        ],
        forbidden: const ['guaranteed to remove'],
        expectNoProducts: true,
      );
    });

    test('does not guarantee whether a seller hoodie will shrink', () async {
      final response = await ask(
        'Will this hoodie shrink in the wash?',
        entryPoint: AssistantEntryPoint.product,
        focusProductId: 'grey-hoodie',
      );

      expectConcepts(
        response,
        const [
          ['cannot confirm', 'can’t confirm', 'depends', 'no way to guarantee'],
          ['fiber', 'fabric', 'material'],
          ['care label', 'seller'],
          ['cold'],
          ['air dry', 'low heat', 'avoid high heat'],
        ],
        forbidden: const ['will not shrink'],
      );
    });

    test('handles rain-soaked suede without damaging heat advice', () async {
      final response = await ask(
        'My suede sneakers got caught in rain. What should I do?',
      );

      expectConcepts(
        response,
        const [
          ['suede'],
          ['blot'],
          ['air dry', 'dry naturally'],
          ['direct heat', 'dryer', 'radiator'],
          ['brush'],
        ],
        forbidden: const ['put them in the dryer'],
        expectNoProducts: true,
      );
    });

    test('will not guess whether an unknown jacket is dryer-safe', () async {
      final response = await ask(
        'Can I put this puffer jacket in the dryer?',
        entryPoint: AssistantEntryPoint.product,
        focusProductId: 'black-puffer-jacket',
      );

      expectConcepts(
        response,
        const [
          ['care label'],
          ['cannot confirm', 'can’t confirm', 'do not know', 'don’t know'],
          ['dryer', 'heat'],
          ['seller'],
        ],
        forbidden: const ['definitely safe'],
      );
    });

    test('warns against improvising dangerous cleaner combinations', () async {
      final response = await ask(
        'Can I mix bleach and ammonia to clean a white tee stain?',
      );

      expectConcepts(response, const [
        ['do not mix', 'never mix'],
        ['bleach'],
        ['ammonia'],
        ['toxic', 'dangerous', 'gas', 'fumes'],
        ['fresh air', 'poison control', 'emergency'],
      ], expectNoProducts: true);
    });
  });

  group('dress codes and respectful occasion guidance', () {
    test(
      'explains business casual for an interview without overpromising',
      () async {
        final response = await ask(
          'What should I wear to a business-casual interview?',
        );

        expectConcepts(response, const [
          ['business casual'],
          ['company', 'office', 'industry', 'dress code'],
          ['polished', 'structured'],
          ['trouser', 'chino', 'shirt', 'jacket'],
          ['clean shoe', 'loafer', 'minimal sneaker'],
        ], expectNoProducts: true);
      },
    );

    test('does not casually override a black-tie wedding dress code', () async {
      final response = await ask('Can I wear sneakers to a black-tie wedding?');

      expectConcepts(response, const [
        ['black tie', 'black-tie'],
        ['formal'],
        ['invitation', 'host', 'couple', 'dress code'],
        ['sneaker'],
      ], expectNoProducts: true);
    });

    test('defines smart casual as polished and relaxed', () async {
      final response = await ask('What does smart casual mean?');

      expectConcepts(response, const [
        ['polished', 'intentional'],
        ['relaxed', 'casual'],
        ['structured', 'tailored'],
        ['clean'],
      ], expectNoProducts: true);
    });

    test('handles funeral clothing with cultural sensitivity', () async {
      final response = await ask('What should I wear to a funeral?');

      expectConcepts(
        response,
        const [
          ['respect'],
          ['subdued', 'quiet', 'conservative'],
          ['culture', 'family', 'tradition', 'venue'],
        ],
        forbidden: const ['stand out', 'make a statement'],
        expectNoProducts: true,
      );
    });
  });

  group('weather and practical layering', () {
    test('builds a functional rain layering system', () async {
      final response = await ask(
        'How should I layer for 45°F weather and steady rain?',
      );

      expectConcepts(response, const [
        ['base layer', 'base'],
        ['midlayer', 'mid-layer', 'middle layer'],
        ['waterproof shell', 'rain shell', 'water-resistant outer'],
        ['rain'],
        ['dry'],
      ], expectNoProducts: true);
    });

    test('recommends breathable proportions for hot humid weather', () async {
      final response = await ask(
        'What clothing works for 90°F heat and high humidity?',
      );

      expectConcepts(response, const [
        ['lightweight'],
        ['breathable'],
        ['loose', 'relaxed', 'airflow'],
        ['layer'],
      ], expectNoProducts: true);
    });

    test(
      'does not invent a waterproof rating for the catalog puffer',
      () async {
        final response = await ask(
          'Can I wear this Black Puffer Jacket in heavy rain?',
          entryPoint: AssistantEntryPoint.product,
          focusProductId: 'black-puffer-jacket',
        );

        expectConcepts(
          response,
          const [
            ['cannot confirm', 'can’t confirm', 'no waterproof'],
            ['waterproof rating', 'weather rating', 'water resistance'],
            ['shell'],
            ['care label', 'seller'],
          ],
          forbidden: const ['is waterproof'],
        );
      },
    );

    test('explains hoodie-under-jacket layering without bulk', () async {
      final response = await ask(
        'How do I layer a hoodie under a jacket without looking bulky?',
      );

      expectConcepts(response, const [
        ['thin', 'lightweight', 'low-bulk'],
        ['room', 'roomier', 'ease'],
        ['jacket'],
        ['bulk'],
        ['hem', 'proportion', 'mobility'],
      ], expectNoProducts: true);
    });
  });

  group('body-neutral fit and proportion language', () {
    test(
      'reframes a skinnier request around silhouette, not body correction',
      () async {
        final response = await ask('Make me look skinnier.');

        expectConcepts(
          response,
          const [
            ['silhouette', 'line', 'proportion'],
            ['structured', 'streamlined', 'defined'],
            ['prefer', 'goal', 'feel', 'comfortable'],
          ],
          forbidden: const [
            'fat',
            'problem area',
            'fix your body',
            'hide your body',
          ],
        );
      },
    );

    test('answers a height question through pant proportion choices', () async {
      final response = await ask(
        'I am short. What pant proportions can create a longer line?',
      );

      expectConcepts(
        response,
        const [
          ['longer line', 'continuous line', 'vertical line'],
          ['rise'],
          ['hem', 'break'],
          ['proportion'],
        ],
        forbidden: const ['correct your height', 'hide being short'],
      );
    });

    test(
      'offers balance options for broad shoulders without judgment',
      () async {
        final response = await ask(
          'I have broad shoulders. What silhouettes can balance them?',
        );

        expectConcepts(
          response,
          const [
            ['shoulder'],
            ['balance'],
            ['straight', 'wide', 'volume', 'open'],
            ['preference', 'goal', 'if you want'],
          ],
          forbidden: const ['wrong shape', 'problem area'],
        );
      },
    );

    test('affirms oversized styling for plus-size users', () async {
      final response = await ask(
        'I am plus size. Can I still wear oversized clothes?',
      );

      expectConcepts(
        response,
        const [
          ['yes', 'absolutely', 'can wear'],
          ['oversized'],
          ['proportion'],
          ['structure', 'intentional', 'anchor'],
          ['comfort', 'preference', 'feel'],
        ],
        forbidden: const ['should not wear', 'too big for', 'hide your body'],
      );
    });
  });
}
