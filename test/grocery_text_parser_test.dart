import 'package:flutter_test/flutter_test.dart';

import 'package:pixels_to_macros/services/grocery_food_lexicon.dart';
import 'package:pixels_to_macros/services/grocery_text_parser.dart';

List<String> names(String receipt, {List<GroceryModelItem>? model}) =>
    GroceryTextParser.parseReceipt(receipt.split('\n'), modelItems: model)
        .map((c) => c.name)
        .toList();

void main() {
  test('English receipt keeps only foods; metadata never becomes an item', () {
    final items = names('''
TESCO STORES LTD
Receipt
Receipt number 004521
Date 12/11/2026 14:32
Semi Skimmed Milk 2L     1.45
Bananas loose  0.812 kg x 0.89/kg   0.72
Hovis Wholemeal Bread    1.40
Carrier bag              0.10
Fairy washing up liquid  2.10
Colgate toothpaste       1.99
Chicken breast fillets   4.25
SUBTOTAL                10.01
TOTAL                   10.01
VISA DEBIT              10.01
Clubcard points 10
Thank you for shopping''');
    expect(items, ['Milk', 'Bananas', 'Bread', 'Chicken breast']);
  });

  test('Dutch receipt: compounds, bonus and deposit lines', () {
    final result = GroceryTextParser.parseReceipt('''
Albert Heijn
Kassabon
Bonnummer 1234 5678
AH HALFVOLLE MELK      1,15
2 x 1,15
AH KIPFILET            4,99
BONUS KIPFILET        -1,00
AH VOLKORENBROOD       2,19
STATIEGELD             0,25
JONGE KAAS PLAKKEN     3,49
TOTAAL                11,07
PINNEN                11,07
BTW 9%                 0,91'''
        .split('\n'));
    expect(result.map((c) => c.name),
        ['Milk', 'Chicken breast', 'Bread', 'Cheese']);
    expect(result.first.quantity, 2);
  });

  test('German, Spanish and Polish receipts', () {
    expect(names('''
REWE Markt GmbH
Vollmilch 3,5%           1,19 B
Bio Bananen              1,79 B
Roggenbrot               2,49 B
Pfand 0,25               0,25 A
Hundefutter              3,99 A
SUMME EUR                9,71
Bar                     10,00
Rückgeld                 0,29'''), ['Milk', 'Bananas', 'Bread']);
    expect(names('''
MERCADONA S.A.
FACTURA SIMPLIFICADA
1 LECHE ENTERA           0,89
2 TOMATE PERA            1,30
1 PAN BARRA              0,45
1 DETERGENTE             3,50
TOTAL (€)                6,14
TARJETA BANCARIA         6,14'''), ['Milk', 'Tomatoes', 'Bread']);
    expect(names('''
BIEDRONKA
PARAGON FISKALNY
Mleko 2% 1l            2,99 C
Pomidory luz          4,50 C
Jabłka                3,20 C
Chleb żytni           4,99 C
Torba                 0,99 A
SUMA PLN             16,67
Gotówka              20,00'''), ['Milk', 'Tomatoes', 'Apples', 'Bread']);
  });

  test('model items are grounded to non-metadata lines and validated', () {
    final lines = '''
CARREFOUR
Ticket n 5521
YAOURT NAT. X4    1,20
BRIOCHE TRANCH    2,10
SAC CABAS         0,50
TOTAL             3,80'''
        .split('\n');
    final result = GroceryTextParser.parseReceipt(lines, modelItems: const [
      GroceryModelItem(line: 0, name: 'Carrefour'),
      GroceryModelItem(line: 1, name: 'Receipt number'),
      GroceryModelItem(line: 2, name: 'Plain yogurt'),
      GroceryModelItem(line: 3, name: 'Brioche bread'),
      GroceryModelItem(line: 4, name: 'Shopping bag'),
      GroceryModelItem(line: 5, name: 'Total'),
      GroceryModelItem(line: 42, name: 'Invented apples'),
    ]);
    expect(result.map((c) => c.name), ['Plain yogurt', 'Brioche bread']);
  });

  test('model names that are only synonyms map to the canonical name', () {
    expect(GroceryTextParser.canonicalModelName('semi skimmed milk'), 'Milk');
    expect(
        GroceryTextParser.canonicalModelName('Kidney beans'), 'Kidney beans');
    expect(GroceryTextParser.canonicalModelName('Receipt number'), isNull);
    expect(GroceryTextParser.canonicalModelName('Toilet paper'), isNull);
  });

  test('repeated receipt lines add up as separate purchases', () {
    final result = GroceryTextParser.parseReceipt(
        ['Bananen 1,79', 'Kaas 3,49', 'Bananen 1,79', 'Totaal 7,07']);
    expect(result.first.name, 'Bananas');
    expect(result.first.quantity, 2);
  });

  test('packaging text skips ingredient lists and nutrition tables', () {
    final result = GroceryTextParser.parsePackaging('''
Griekse yoghurt
Ingrediënten: melk, room, suiker
gemaakt met zout en boter

Energie 400 kJ
Vet 10 g

Haferflocken''', const {});
    expect(result.map((c) => c.name), ['Greek yogurt', 'Oats']);
  });

  test('lexicon is accent-insensitive and rejects household compounds', () {
    expect(GroceryFoodLexicon.match('JABLKA'), 'Apples');
    expect(GroceryFoodLexicon.match('Weissbrot'), 'Bread');
    expect(GroceryFoodLexicon.match('Zahnpasta'), isNull);
    expect(GroceryFoodLexicon.match('Eggplant'), 'Eggplant');
    expect(GroceryFoodLexicon.match('Receipt number'), isNull);
  });
}
