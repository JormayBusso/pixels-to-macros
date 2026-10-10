import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/services/database_service.dart';

void main() {
  group('bestFuzzyLabelMatch', () {
    const dbLabels = [
      'salmon',
      'bread',
      'rice',
      'fried rice',
      'chicken',
      'egg',
      'avocado',
      'ice cream',
      'eggplant',
      'pasta',
      'green peas',
      'carrot',
      'sauce',
      'mayonnaise',
    ];

    test('maps a specialised name to its base food via shared word', () {
      expect(
        DatabaseService.bestFuzzyLabelMatch('smoked salmon', dbLabels),
        'salmon',
      );
    });

    test('case-insensitive exact match wins', () {
      expect(DatabaseService.bestFuzzyLabelMatch('Bread', dbLabels), 'bread');
    });

    test('exact mixed-dish labels stay mixed when available', () {
      expect(
        DatabaseService.bestFuzzyLabelMatch('fried rice', dbLabels),
        'fried rice',
      );
    });

    test('does not match on accidental substrings (rice vs ice cream)', () {
      // "rice" must NOT resolve to "ice cream"; no shared whole word.
      expect(
        DatabaseService.bestFuzzyLabelMatch('rice', dbLabels),
        'rice',
      );
    });

    test('egg does not bleed into eggplant', () {
      expect(DatabaseService.bestFuzzyLabelMatch('egg', dbLabels), 'egg');
    });

    test('returns null when nothing meaningful overlaps', () {
      expect(
        DatabaseService.bestFuzzyLabelMatch('mystery gadget', dbLabels),
        isNull,
      );
    });

    test('cooking-style-only overlap does not force a match', () {
      // "grilled" is a stop word; "grilled mystery" shares no content word.
      expect(
        DatabaseService.bestFuzzyLabelMatch('grilled mystery', dbLabels),
        isNull,
      );
    });

    test('plural visible vegetables map to base foods', () {
      expect(DatabaseService.bestFuzzyLabelMatch('carrots', dbLabels), 'carrot');
      expect(
        DatabaseService.bestFuzzyLabelMatch('peas', dbLabels),
        'green peas',
      );
    });

    test('sauce variants map to available condiment nutrition', () {
      expect(
        DatabaseService.bestFuzzyLabelMatch('tomato sauce', dbLabels),
        'sauce',
      );
      expect(
        DatabaseService.bestFuzzyLabelMatch('garlic mayonnaise', dbLabels),
        'mayonnaise',
      );
    });
  });
}
