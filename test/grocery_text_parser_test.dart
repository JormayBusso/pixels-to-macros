import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pixels_to_macros/core/constants.dart';
import 'package:pixels_to_macros/services/grocery_food_lexicon.dart';
import 'package:pixels_to_macros/services/grocery_text_parser.dart';
import 'package:pixels_to_macros/services/pantry_photo_service.dart';

List<String> names(String receipt, {List<GroceryModelItem>? model}) =>
    GroceryTextParser.parseReceipt(receipt.split('\n'), modelItems: model)
        .map((c) => c.name)
        .toList();

class ReceiptPicker extends ImagePicker {
  final calls = <(ImageSource, double?, double?, int?)>[];
  bool cancelled = false;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    calls.add((source, maxWidth, maxHeight, imageQuality));
    return cancelled ? null : XFile('camera-original.jpg');
  }

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    calls.add((ImageSource.gallery, maxWidth, maxHeight, imageQuality));
    return cancelled ? [] : [XFile('gallery-original.jpg')];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('inline and adjacent purchase counts multiply explicit package contents',
      () {
    final result = GroceryTextParser.parseReceipt([
      'Rice 500g 2 x 1,29',
      'Milk 1L 1,19',
      '3 x 1,19',
      'Pasta 2x500g 2,49',
      'Cheese 0,5kg 2 x 3,49',
    ]);
    expect(result.map((c) => c.quantity), [1000, 3, 1000, 1]);
    expect(result.map((c) => c.unit), ['g', 'l', 'g', 'kg']);
    expect(result[1].sourceText, 'Milk 1L 1,19\n3 x 1,19');
  });

  test('preceding quantity row is used once and decimals retain dimensions',
      () {
    final result = GroceryTextParser.parseReceipt([
      '2 x 1,29',
      'Rice 0,5 kg 1,29',
      'Milk 1,5 l 1,89',
      'Yogurt 125,5g 0,99',
      'Orange juice 250,5ml 1,99',
    ]);
    expect(result.map((c) => c.quantity), [1, 1.5, 125.5, 250.5]);
    expect(result.map((c) => c.unit), ['kg', 'l', 'g', 'ml']);
    expect(result.first.sourceText, '2 x 1,29\nRice 0,5 kg 1,29');
  });

  test('purchase count multiplies a size multipack inline or adjacent', () {
    for (final rows in [
      ['Yogurt 4x125g 2 x 1.50'],
      ['Yogurt 4x125g', '2 x 1.50'],
      ['2 x 1.50', 'Yogurt 4x125g'],
    ]) {
      final candidate = GroceryTextParser.parseReceipt(rows).single;
      expect(candidate.quantity, 1000, reason: rows.join('\n'));
      expect(candidate.unit, 'g');
      expect(candidate.sourceText, rows.join('\n'));
    }
    expect(
        GroceryTextParser.parseReceipt(['Yogurt 4x125g 1.50']).single.quantity,
        500);
  });

  test('unit prices, fat percentages and currency never become contents', () {
    final result = GroceryTextParser.parseReceipt([
      'Rice 2,99/kg',
      'Milk 2% 1,29',
      'Cheese 3,49 EUR / kg',
      'Milk 1L 1,29',
      'Rice 0,512 kg x 2,49/kg',
      'TOTAL 9,99',
    ]);
    expect(result.map((c) => (c.name, c.quantity, c.unit)), [
      ('Rice', 1.0, null),
      ('Milk', 1.0, null),
      ('Cheese', 1.0, null),
      ('Milk', 1.0, 'l'),
      ('Rice', 0.512, 'kg'),
    ]);
  });

  test('weighed at-rate groceries survive while email addresses stay metadata',
      () {
    final result = GroceryTextParser.parseReceipt([
      'Bananas 0,512 kg @ 2,49/kg',
      'bananas@orchard.example',
      'Milk contact@dairy.example',
      'Milk contact @ dairy.example',
    ]);
    expect(result.map((c) => (c.name, c.quantity, c.unit)),
        [('Bananas', 0.512, 'kg')]);
    expect(GroceryTextParser.isReceiptMetadata('Bananas 0.512 kg @ 2.49/kg'),
        isFalse);
    expect(
        GroceryTextParser.isReceiptMetadata('bananas@orchard.example'), isTrue);
  });

  test('repeated litres add and compatible metric units convert without loss',
      () {
    final result = GroceryTextParser.parseReceipt([
      'Milk 1L 1,29',
      'Milk 1L 1,29',
      'Milk 500ml 0,99',
      'Rice 500g 1,29',
      'Rice 1kg 2,19',
    ]);
    expect(
        result.map((c) => (c.quantity, c.unit)), [(2.5, 'l'), (1500.0, 'g')]);
    expect(
        result.first.sourceText, 'Milk 1L 1,29\nMilk 1L 1,29\nMilk 500ml 0,99');
  });

  test('public purchase sum retains conflicts and sources across pages', () {
    final result = GroceryTextParser.sumPurchases(const [
      PantryPhotoCandidate('Milk',
          quantity: 1, unit: 'l', sourceText: 'Milk 1L'),
      PantryPhotoCandidate('milk', quantity: 250, unit: 'ml'),
      PantryPhotoCandidate('Milk', quantity: 2, sourceText: '2 Milk'),
      PantryPhotoCandidate('Milk', quantity: 500, unit: 'g'),
      PantryPhotoCandidate('Rice', quantity: 1, unit: 'kg'),
      PantryPhotoCandidate('Rice', quantity: 500, unit: 'g'),
    ]);
    expect(result.map((c) => (c.quantity, c.unit)),
        [(1.25, 'l'), (2.0, null), (500.0, 'g'), (1.5, 'kg')]);
    expect(result.first.sourceText, 'Milk 1L');
    expect(result[1].sourceText, '2 Milk');
  });

  group('receipt capture', () {
    const channel = MethodChannel(AppConstants.methodChannelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<ImageSource> fallbackSources;
    late PantryPhotoService service;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      fallbackSources = [];
      service = PantryPhotoService(
          aliases: const {},
          photoPicker: (source) async {
            fallbackSources.add(source);
            return [XFile('original.jpg')];
          });
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('native pages and cancellation never invoke camera fallback',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'captureReceipt');
        return ['page1.jpg', 'page2.jpg'];
      });
      expect((await service.captureReceipt()).map((f) => f.path),
          ['page1.jpg', 'page2.jpg']);
      messenger.setMockMethodCallHandler(channel, (_) async => []);
      expect(await service.captureReceipt(), isEmpty);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await service.captureReceipt(), isEmpty);
      expect(fallbackSources, isEmpty);
    });

    test('missing or unsupported capture falls back, real failures propagate',
        () async {
      expect(await service.captureReceipt(), hasLength(1));
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'RECEIPT_CAMERA_UNSUPPORTED');
      });
      expect(await service.captureReceipt(), hasLength(1));
      expect(fallbackSources, [ImageSource.camera, ImageSource.camera]);
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'CAPTURE_FAILED');
      });
      await expectLater(
          service.captureReceipt(), throwsA(isA<PlatformException>()));
      expect(fallbackSources, hasLength(2));
    });

    test('non-iOS capture and receipt gallery use separate original pickers',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await service.captureReceipt(), hasLength(1));
      expect(await service.pickReceiptGallery(), hasLength(1));
      expect(fallbackSources, [ImageSource.camera, ImageSource.gallery]);
    });

    test(
        'receipt picker keeps full quality and dimensions; stock pick unchanged',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final picker = ReceiptPicker();
      service = PantryPhotoService(aliases: const {}, picker: picker);
      expect(
          (await service.captureReceipt()).single.path, 'camera-original.jpg');
      expect((await service.pickReceiptGallery()).single.path,
          'gallery-original.jpg');
      await service.pick(ImageSource.camera);
      expect(picker.calls, [
        (ImageSource.camera, null, null, 100),
        (ImageSource.gallery, null, null, 100),
        (ImageSource.camera, 1600.0, 1600.0, 85),
      ]);
      picker.cancelled = true;
      expect(await service.captureReceipt(), isEmpty);
      expect(await service.pickReceiptGallery(), isEmpty);
    });
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
