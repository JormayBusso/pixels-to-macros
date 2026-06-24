import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/services/ingredient_localizer.dart';

void main() {
  group('IngredientLocalizer', () {
    test('translates a single English ingredient to Polish', () {
      expect(
        IngredientLocalizer.localize('onion', targetLang: 'pl', sourceLang: 'en'),
        'cebula',
      );
    });

    test('translates Dutch ingredient to Spanish', () {
      expect(
        IngredientLocalizer.localize('ui', targetLang: 'es', sourceLang: 'nl'),
        'cebolla',
      );
    });

    test('preserves leading capital letter', () {
      expect(
        IngredientLocalizer.localize('Garlic', targetLang: 'de', sourceLang: 'en'),
        'Knoblauch',
      );
    });

    test('translates multi-word phrase (olive oil)', () {
      expect(
        IngredientLocalizer.localize('olive oil',
            targetLang: 'de', sourceLang: 'en'),
        'Olivenöl',
      );
    });

    test('keeps descriptors and quantities, translates only known words', () {
      final result = IngredientLocalizer.localize(
        '2 finely chopped onion',
        targetLang: 'pl',
        sourceLang: 'en',
      );
      expect(result.contains('cebula'), isTrue);
      expect(result.contains('2'), isTrue);
      expect(result.contains('finely'), isTrue);
    });

    test('returns text unchanged when source equals target', () {
      expect(
        IngredientLocalizer.localize('onion', targetLang: 'en', sourceLang: 'en'),
        'onion',
      );
    });

    test('returns text unchanged for unsupported target language', () {
      expect(
        IngredientLocalizer.localize('onion', targetLang: 'fr', sourceLang: 'en'),
        'onion',
      );
    });

    test('passes through unknown ingredient words', () {
      expect(
        IngredientLocalizer.localize('worcestershire sauce',
            targetLang: 'pl', sourceLang: 'en'),
        'worcestershire sauce',
      );
    });

    test('preserves trailing punctuation', () {
      final result = IngredientLocalizer.localize(
        'onion,',
        targetLang: 'es',
        sourceLang: 'en',
      );
      expect(result, 'cebolla,');
    });
  });
}
