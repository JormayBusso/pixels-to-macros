import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/screens/voice/voice_translation.dart';

void main() {
  group('voiceNormalizeToEnglish', () {
    test('English passes through unchanged (lowercased)', () {
      expect(voiceNormalizeToEnglish('Two Bananas', 'en'), 'two bananas');
    });

    test('German numbers, connectors and foods', () {
      expect(
        voiceNormalizeToEnglish('zwei Bananen und ein Apfel', 'de'),
        'two banana and a apple',
      );
      expect(
        voiceNormalizeToEnglish('200 Gramm Hähnchen', 'de'),
        '200 grams chicken',
      );
      expect(
        voiceNormalizeToEnglish('eine Scheibe Brot', 'de'),
        'a slice bread',
      );
    });

    test('Polish numbers, connectors and foods', () {
      expect(
        voiceNormalizeToEnglish('dwa jabłka i pół banana', 'pl'),
        'two apple and half banana',
      );
      expect(
        voiceNormalizeToEnglish('sto gramów ryżu', 'pl'),
        'hundred grams rice',
      );
    });

    test('Dutch numbers, connectors and foods', () {
      expect(
        voiceNormalizeToEnglish('twee appels en een banaan', 'nl'),
        'two apple and a banana',
      );
      expect(
        voiceNormalizeToEnglish('een plak kaas', 'nl'),
        'a slice cheese',
      );
    });

    test('Spanish numbers, connectors and foods', () {
      expect(
        voiceNormalizeToEnglish('dos manzanas y un plátano', 'es'),
        'two apple and a banana',
      );
      expect(
        voiceNormalizeToEnglish('200 gramos de pollo', 'es'),
        '200 grams of chicken',
      );
    });

    test('strips localized filler verbs', () {
      expect(
        voiceNormalizeToEnglish('he comido una pizza', 'es').trim(),
        'a pizza',
      );
      expect(
        voiceNormalizeToEnglish('ich habe einen Apfel gegessen', 'de').trim(),
        'a apple',
      );
    });

    test('multi-word foods are matched greedily', () {
      expect(
        voiceNormalizeToEnglish('pommes frites', 'de'),
        'french fries',
      );
      expect(
        voiceNormalizeToEnglish('mantequilla de maní', 'es'),
        'peanut butter',
      );
    });

    test('unknown language returns lowercased input', () {
      expect(voiceNormalizeToEnglish('Foo Bar', 'fr'), 'foo bar');
    });
  });

  group('parseSpokenFoods (native per-language, no English pivot)', () {
    SpokenItem only(List<SpokenItem> items) {
      expect(items, hasLength(1));
      return items.first;
    }

    test('English counts and articles', () {
      final items = parseSpokenFoods('two bananas and an apple', 'en');
      expect(items, hasLength(2));
      expect(items[0].foodQuery, 'banana');
      expect(items[0].pieceCount, 2);
      expect(items[0].resolved, isTrue);
      expect(items[1].foodQuery, 'apple');
      expect(items[1].pieceCount, 1);
    });

    test('German count + article resolve to English labels', () {
      final items = parseSpokenFoods('zwei Bananen und ein Apfel', 'de');
      expect(items, hasLength(2));
      expect(items[0].foodQuery, 'banana');
      expect(items[0].pieceCount, 2);
      expect(items[1].foodQuery, 'apple');
      expect(items[1].pieceCount, 1);
    });

    test('German weight unit', () {
      final item = only(parseSpokenFoods('200 Gramm Hähnchen', 'de'));
      expect(item.foodQuery, 'chicken');
      expect(item.grams, 200);
      expect(item.pieceCount, isNull);
    });

    test('German slice unit', () {
      final item = only(parseSpokenFoods('eine Scheibe Brot', 'de'));
      expect(item.foodQuery, 'bread');
      expect(item.grams, 30);
    });

    test('Polish inflected food + fraction', () {
      final items = parseSpokenFoods('dwa jabłka i pół banana', 'pl');
      expect(items, hasLength(2));
      expect(items[0].foodQuery, 'apple');
      expect(items[0].pieceCount, 2);
      expect(items[1].foodQuery, 'banana');
      expect(items[1].pieceCount, 0.5);
    });

    test('Polish weight (genitive food form)', () {
      final item = only(parseSpokenFoods('sto gramów ryżu', 'pl'));
      expect(item.foodQuery, 'rice');
      expect(item.grams, 100);
    });

    test('Dutch slice', () {
      final item = only(parseSpokenFoods('een plak kaas', 'nl'));
      expect(item.foodQuery, 'cheese');
      expect(item.grams, 30);
    });

    test('Spanish weight with "de" article', () {
      final item = only(parseSpokenFoods('200 gramos de pollo', 'es'));
      expect(item.foodQuery, 'chicken');
      expect(item.grams, 200);
    });

    test('Spanish strips filler verbs and keeps article count', () {
      final item = only(parseSpokenFoods('he comido una pizza', 'es'));
      expect(item.foodQuery, 'pizza');
      expect(item.pieceCount, 1);
    });

    test('multi-word food resolves greedily', () {
      final item = only(parseSpokenFoods('pommes frites', 'de'));
      expect(item.foodQuery, 'french fries');
      expect(item.resolved, isTrue);
    });

    test('unresolved native food keeps cleaned phrase, not English', () {
      final item = only(parseSpokenFoods('ośmiornica', 'pl'));
      expect(item.resolved, isFalse);
      // The phrase stays native (accent-folded) rather than being mistranslated.
      expect(item.foodQuery, contains('osmiornica'));
    });
  });
}

