import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/screens/voice/voice_translation.dart';
import 'package:pixels_to_macros/services/grocery_voice_parser.dart';

void main() {
  final transcripts = {
    'en': 'I bought 500 grams of rice and milk one litre and two apples '
        'and three apples and 250 grams of rice and 500 millilitres of milk',
    'nl': 'Ik heb 500 gram rijst en melk een liter en twee appels '
        'en drie appels en 250 gram rijst en 500 milliliter melk gekocht',
    'es': 'He comprado 500 gramos de arroz y leche un litro y dos manzanas '
        'y tres manzanas y 250 gramos de arroz y 500 mililitros de leche',
    'de': 'Ich habe 500 Gramm Reis und Milch einen Liter und zwei Äpfel '
        'und drei Äpfel und 250 Gramm Reis und 500 Milliliter Milch gekauft',
    'pl': 'Kupiłam 500 gramów ryżu i mleko jeden litr i dwa jabłka '
        'i trzy jabłka i 250 gramów ryżu i 500 mililitrów mleka',
  };
  for (final entry in transcripts.entries) {
    test('${entry.key} purchases preserve weights, suffix litres and counts',
        () {
      final result = GroceryVoiceParser.parse(entry.value, entry.key);
      expect(result.map((c) => (c.name, c.quantity, c.unit)), [
        ('Rice', 750.0, 'g'),
        ('Milk', 1.5, 'l'),
        ('Apples', 5.0, null),
      ]);
      expect(result.every((c) => c.sourceText == entry.value), isTrue);
    });
  }

  test('spoken localized numbers and kilograms remain explicit quantities', () {
    final examples = {
      'en': 'two kilograms rice and two litres milk',
      'nl': 'twee kilogram rijst en twee liter melk',
      'es': 'dos kilogramos de arroz y dos litros de leche',
      'de': 'zwei Kilogramm Reis und zwei Liter Milch',
      'pl': 'dwa kilogramy ryżu i dwa litry mleka',
    };
    for (final entry in examples.entries) {
      final result = GroceryVoiceParser.parse(entry.value, entry.key);
      expect(result.map((c) => (c.quantity, c.unit)), [(2.0, 'kg'), (2.0, 'l')],
          reason: entry.key);
    }
  });

  test('decimal comma, decimal point and compact metric suffixes are preserved',
      () {
    final result = GroceryVoiceParser.parse(
        'I bought 1,5l milk and 0.5 litres milk and 0,5kg rice', 'en-US');
    expect(result.map((c) => (c.quantity, c.unit)), [(2.0, 'l'), (0.5, 'kg')]);
  });

  test('explicit pack contents multiply; pack alone never means a meal portion',
      () {
    final examples = {
      'en': 'two 500 gram packs of rice',
      'nl': 'twee pakken van 500 gram rijst',
      'es': 'dos paquetes de 500 gramos de arroz',
      'de': 'zwei Packungen von 500 Gramm Reis',
      'pl': 'dwie paczki 500 gramów ryżu',
    };
    for (final entry in examples.entries) {
      final result = GroceryVoiceParser.parse(entry.value, entry.key);
      expect(result.single.name, 'Rice');
      expect(result.single.quantity, 1000, reason: entry.key);
      expect(result.single.unit, 'g');
    }
    final packs = GroceryVoiceParser.parse('two packs of rice', 'en').single;
    expect(packs.quantity, 2);
    expect(packs.unit, isNull);
    expect(GroceryVoiceParser.parse('a pack of rice', 'en').single.quantity, 1);
    final unknown = GroceryVoiceParser.parse('packs of rice', 'en').single;
    expect(unknown.quantity, 1);
    expect(unknown.unit, isNull);
  });

  test('repeated compatible purchases sum, dimension conflicts remain rows',
      () {
    final result = GroceryVoiceParser.parse(
        'one litre milk and 500 ml milk and two milk and 500 grams milk '
            'and 500 grams rice and one kilogram rice',
        'en');
    expect(result.map((c) => (c.quantity, c.unit)),
        [(1.5, 'l'), (2.0, null), (500.0, 'g'), (1500.0, 'g')]);
  });

  test('household phrases never fuzzy-match or leak an embedded food', () {
    final examples = {
      'en': 'two soaps and one milk detergent and two apples',
      'nl': 'twee zeep en een melk shampoo en twee appels',
      'es': 'dos jabones y un detergente de leche y dos manzanas',
      'de': 'zwei Seifen und ein Milch Shampoo und zwei Äpfel',
      'pl': 'dwa mydła i jeden detergent mleka i dwa jabłka',
    };
    for (final entry in examples.entries) {
      final result = GroceryVoiceParser.parse(entry.value, entry.key);
      expect(result.map((c) => c.name), ['Apples'], reason: entry.key);
    }
    expect(
        GroceryVoiceParser.parse('milk and rice', 'en')
            .map((c) => (c.name, c.quantity, c.unit)),
        [('Milk', 1.0, null), ('Rice', 1.0, null)]);
    expect(GroceryVoiceParser.parse('one cup rice', 'en'), isEmpty);
  });

  test('mixed unquantified foods survive five-language prefix/suffix amounts',
      () {
    final examples = {
      'en': 'I bought two apples and milk and rice 500 grams',
      'nl': 'Ik heb twee appels en melk en rijst 500 gram gekocht',
      'es': 'He comprado dos manzanas y leche y arroz 500 gramos',
      'de': 'Ich habe zwei Äpfel und Milch und Reis 500 Gramm gekauft',
      'pl': 'Kupiłam dwa jabłka i mleko i ryż 500 gramów',
    };
    for (final entry in examples.entries) {
      final result = GroceryVoiceParser.parse(entry.value, entry.key);
      expect(
          result.map((c) => (c.name, c.quantity, c.unit)),
          [
            ('Apples', 2.0, null),
            ('Milk', 1.0, null),
            ('Rice', 500.0, 'g'),
          ],
          reason: entry.key);
      expect(result.every((c) => c.sourceText == entry.value), isTrue);
      final raw =
          parseSpokenFoods(entry.value, entry.key, groceryPurchases: true);
      expect(raw[1].quantity, isNull);
    }
  });

  test(
      'multiple amount phrases stay unknown instead of arbitrary multiplication',
      () {
    for (final transcript in [
      'rice 500 grams 250 grams',
      'rice two 500 grams',
      'rice 2 3',
      'two 500 gram 250 gram packs rice',
      'milk one litre 500 grams',
    ]) {
      final candidate = GroceryVoiceParser.parse(transcript, 'en').single;
      expect(candidate.quantity, 1, reason: transcript);
      expect(candidate.unit, isNull);
      expect(candidate.sourceText, transcript);
    }
    expect(
        GroceryVoiceParser.parse('two hundred grams rice', 'en')
            .single
            .quantity,
        200);
    expect(GroceryVoiceParser.parse('twenty five apples', 'en').single.quantity,
        25);
    expect(GroceryVoiceParser.parse('a half litre milk', 'en').single.quantity,
        0.5);
  });

  test(
      'default meal callers keep volume/portion conversion and duplicate merge',
      () {
    final milk =
        parseSpokenFoods('one litre milk and 500 ml milk', 'en').single;
    expect(milk.grams, 1500);
    expect(milk.quantity, isNull);
    expect(milk.unit, isNull);
    expect(parseSpokenFoods('a slice bread', 'en').single.grams, 30);
    expect(
        parseSpokenFoods('two bananas and three bananas', 'en')
            .single
            .pieceCount,
        5);
  });
}
