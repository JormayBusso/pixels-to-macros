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
}
