import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/core/grocery_packaging.dart';

void main() {
  group('GroceryPackaging.cleanName strips multilingual descriptors', () {
    test('English prep words', () {
      expect(GroceryPackaging.cleanName('small ripe avocados, sliced'),
          'avocados');
      expect(GroceryPackaging.cleanName('finely chopped onion'), 'onion');
    });
    test('Dutch descriptors', () {
      expect(GroceryPackaging.cleanName('milde olijfolie'), 'olijfolie');
      expect(GroceryPackaging.cleanName('ongezouten roomboter'), 'roomboter');
      expect(GroceryPackaging.cleanName('fijngesneden ui'), 'ui');
    });
    test('German descriptors', () {
      expect(GroceryPackaging.cleanName('fein gehackte Zwiebel'), 'zwiebel');
      expect(GroceryPackaging.cleanName('frische Petersilie'), 'petersilie');
    });
    test('Polish descriptors', () {
      expect(GroceryPackaging.cleanName('drobno posiekany czosnek'),
          'czosnek');
    });
  });

  group('GroceryPackaging.stapleOf recognises staples across languages', () {
    test('eggs', () {
      expect(GroceryPackaging.stapleOf('eggs'), Staple.eggs);
      expect(GroceryPackaging.stapleOf('middelgrote scharreleieren'),
          Staple.eggs);
      expect(GroceryPackaging.stapleOf('Ei(er)'), Staple.eggs);
      expect(GroceryPackaging.stapleOf('jajka'), Staple.eggs);
    });
    test('garlic', () {
      expect(GroceryPackaging.stapleOf('garlic cloves'), Staple.garlic);
      expect(GroceryPackaging.stapleOf('tenen knoflook'), Staple.garlic);
      expect(GroceryPackaging.stapleOf('knoblauchzehe(n)'), Staple.garlic);
      expect(GroceryPackaging.stapleOf('czosnku'), Staple.garlic);
    });
    test('flour', () {
      expect(GroceryPackaging.stapleOf('plain flour'), Staple.flour);
      expect(GroceryPackaging.stapleOf('tarwebloem'), Staple.flour);
      expect(GroceryPackaging.stapleOf('Mehl'), Staple.flour);
    });
  });

  group('GroceryPackaging.isPantryAssumed', () {
    test('salt, pepper and water are omitted', () {
      expect(GroceryPackaging.isPantryAssumed('salt'), isTrue);
      expect(GroceryPackaging.isPantryAssumed('zout'), isTrue);
      expect(GroceryPackaging.isPantryAssumed('Salz'), isTrue);
      expect(GroceryPackaging.isPantryAssumed('black pepper'), isTrue);
      expect(GroceryPackaging.isPantryAssumed('water'), isTrue);
      expect(GroceryPackaging.isPantryAssumed('chicken breast'), isFalse);
    });
  });

  group('GroceryPackaging.purchaseLine rounds up to whole packages', () {
    test('eggs: needing 4 eggs buys a box of 10', () {
      final line = GroceryPackaging.purchaseLine('eggs', 4 * 55);
      expect(line, isNotNull);
      expect(line!.quantity, 10);
      expect(line.unit, 'pcs');
      expect(line.packaged, isTrue);
      expect(line.packages, 1);
    });
    test('eggs: needing 12 eggs buys two boxes (20)', () {
      final line = GroceryPackaging.purchaseLine('eggs', 12 * 55);
      expect(line!.quantity, 20);
      expect(line.packages, 2);
    });
    test('flour: 230 g rounds up to a 1 kg bag', () {
      final line = GroceryPackaging.purchaseLine('plain flour', 230);
      expect(line!.quantity, 1000);
      expect(line.unit, 'g');
      expect(line.packaged, isTrue);
    });
    test('milk: 1200 ml needs two 1 L cartons', () {
      final line = GroceryPackaging.purchaseLine('halfvolle melk', 1200);
      expect(line!.quantity, 2000);
      expect(line.unit, 'ml');
      expect(line.packages, 2);
    });
    test('garlic: sold loose by the clove', () {
      final line = GroceryPackaging.purchaseLine('garlic', 12);
      expect(line!.unit, 'cloves');
      expect(line.quantity, 3);
      expect(line.packaged, isFalse);
    });
    test('generic item rounds up to a sensible amount', () {
      final line = GroceryPackaging.purchaseLine('chicken breast', 233);
      expect(line!.unit, 'g');
      expect(line.quantity, 240);
    });
    test('trace amounts and water return null', () {
      expect(GroceryPackaging.purchaseLine('olive oil', 0.4), isNull);
      expect(GroceryPackaging.purchaseLine('water', 500), isNull);
      expect(GroceryPackaging.purchaseLine('salt', 5), isNull);
    });
  });
}
