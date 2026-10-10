import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/services/recipe_translation_glossary.dart';

void main() {
  group('RecipeTranslationGlossary', () {
    test('protects dish names with tokens and restores them', () {
      final p = RecipeTranslationGlossary.protect('Stamppot met spinazie');
      expect(p.terms, ['Stamppot']);
      expect(p.masked, '⟦0⟧ met spinazie');
      expect(
        RecipeTranslationGlossary.restore('⟦0⟧ with spinach', p.terms),
        'Stamppot with spinach',
      );
      // Translators sometimes insert spaces inside the brackets.
      expect(
        RecipeTranslationGlossary.restore('Spinach ⟦ 0 ⟧', p.terms),
        'Spinach Stamppot',
      );
    });

    test('multi-word and non-ASCII terms are matched longest-first', () {
      final p = RecipeTranslationGlossary.protect(
          'Kotlet schabowy z ziemniakami i żurek');
      expect(p.terms, ['Kotlet schabowy', 'żurek']);
      expect(p.masked, '⟦0⟧ z ziemniakami i ⟦1⟧');
    });

    test('terms are not matched inside other words', () {
      final p = RecipeTranslationGlossary.protect('Currysaus met rijst');
      expect(p.terms, isEmpty);
    });

    test('mangled, duplicated or missing tokens are rejected', () {
      const terms = ['Pierogi'];
      expect(RecipeTranslationGlossary.restore('Dumplings', terms), isNull);
      expect(
          RecipeTranslationGlossary.restore('⟦0⟧ and ⟦0⟧', terms), isNull);
      expect(RecipeTranslationGlossary.restore('⟦1⟧ ruskie', terms), isNull);
      expect(RecipeTranslationGlossary.restore('⟦0 ruskie', terms), isNull);
    });

    test('entirely protected names are kept as-is and not sent', () async {
      expect(RecipeTranslationGlossary.isEntirelyProtected('Hummus'), isTrue);
      expect(RecipeTranslationGlossary.isEntirelyProtected('Pierogi!'), isTrue);
      expect(
          RecipeTranslationGlossary.isEntirelyProtected('Hummus met wortel'),
          isFalse);
      var calls = 0;
      final out = await RecipeTranslationGlossary.translateAll(
        ['Pierogi', 'Shakshuka'],
        (texts) async {
          calls++;
          return texts;
        },
      );
      expect(out, ['Pierogi', 'Shakshuka']);
      expect(calls, 0);
    });

    test('happy path restores protected terms after translation', () async {
      final out = await RecipeTranslationGlossary.translateAll(
        ['Stamppot met spinazie', 'Tomatensoep'],
        (texts) async => [
          for (final t in texts)
            t
                .replaceAll('met spinazie', 'with spinach')
                .replaceAll('Tomatensoep', 'Tomato soup'),
        ],
      );
      expect(out, ['Stamppot with spinach', 'Tomato soup']);
    });

    test('falls back to translating around terms when a token is mangled',
        () async {
      final batches = <List<String>>[];
      final out = await RecipeTranslationGlossary.translateAll(
        ['Stamppot met spinazie'],
        (texts) async {
          batches.add(texts);
          if (batches.length == 1) {
            // Simulate the translator dropping the placeholder.
            return ['Mash with spinach'];
          }
          return [
            for (final t in texts) t == 'met spinazie' ? 'with spinach' : t,
          ];
        },
      );
      expect(batches.length, 2);
      expect(batches[1], ['met spinazie']);
      expect(out, ['Stamppot with spinach']);
    });

    test('keeps originals silently when translation fails', () async {
      final texts = ['Stamppot met spinazie', 'Tomatensoep'];
      expect(
        await RecipeTranslationGlossary.translateAll(texts, (_) async => null),
        texts,
      );
      expect(
        await RecipeTranslationGlossary.translateAll(
            texts, (_) async => throw Exception('boom')),
        texts,
      );
      expect(
        await RecipeTranslationGlossary.translateAll(
            texts, (_) async => ['only one']),
        texts,
      );
    });
  });
}
