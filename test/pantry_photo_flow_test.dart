import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:pixels_to_macros/core/app_localizations.dart';
import 'package:pixels_to_macros/models/grocery_item.dart';
import 'package:pixels_to_macros/models/mascot_type.dart';
import 'package:pixels_to_macros/models/pantry_item.dart';
import 'package:pixels_to_macros/providers/grocery_provider.dart';
import 'package:pixels_to_macros/providers/history_provider.dart';
import 'package:pixels_to_macros/providers/pantry_provider.dart';
import 'package:pixels_to_macros/screens/grocery_list_screen.dart';
import 'package:pixels_to_macros/services/database_service.dart';
import 'package:pixels_to_macros/services/pantry_photo_service.dart';
import 'package:pixels_to_macros/theme/app_theme.dart';

const aliases = {
  'apple': 'Apples',
  'apples': 'Apples',
  'banana': 'Bananas',
  'almond': 'Almonds',
  'milk': 'Milk',
  'almond milk': 'Almond milk',
  'butter': 'Butter',
  'peanut butter': 'Peanut butter',
};

PantryItem stock(String name, double quantity, {String? unit}) => PantryItem(
    name: name,
    quantity: quantity,
    unit: unit,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026));

class _MemoryDatabase extends Fake implements Database {
  final rows = <Map<String, Object?>>[];
  int transactions = 0;
  bool failUpdate = false;

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
      {bool? exclusive}) async {
    transactions++;
    final backup = rows.map((r) => Map<String, Object?>.from(r)).toList();
    try {
      return await action(_MemoryTransaction(this));
    } catch (_) {
      rows
        ..clear()
        ..addAll(backup);
      rethrow;
    }
  }
}

class _MemoryTransaction extends Fake implements Transaction {
  _MemoryTransaction(this.db);
  final _MemoryDatabase db;

  @override
  Future<List<Map<String, Object?>>> query(String table,
          {bool? distinct,
          List<String>? columns,
          String? where,
          List<Object?>? whereArgs,
          String? groupBy,
          String? having,
          String? orderBy,
          int? limit,
          int? offset}) async =>
      db.rows.map((r) => Map<String, Object?>.from(r)).toList();

  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    final id = db.rows.length + 1;
    db.rows.add({...values, 'id': id});
    return id;
  }

  @override
  Future<int> update(String table, Map<String, Object?> values,
      {String? where,
      List<Object?>? whereArgs,
      ConflictAlgorithm? conflictAlgorithm}) async {
    if (db.failUpdate) throw StateError('write failed');
    final index = db.rows.indexWhere((r) => r['id'] == whereArgs!.first);
    db.rows[index] = {...values};
    return 1;
  }
}

class _Groceries extends GroceryNotifier {
  _Groceries() {
    state = GroceryState(items: [
      GroceryItem(name: 'Bread', createdAt: DateTime(2026)),
    ]);
  }
  @override
  Future<void> load() async {}
}

class _Pantry extends PantryNotifier {
  int saves = 0;
  Completer<void>? saving;
  @override
  Future<void> load() async {}
  @override
  Future<void> saveReviewedItems(List<PantryItem> items,
      {bool observations = true}) async {
    saves++;
    if (saving != null) await saving!.future;
    state = PantryState(items: items);
  }
}

class _History extends HistoryNotifier {
  _History(super.ref);
  @override
  Future<void> load() async {}
}

Future<void> _openGrocery(WidgetTester tester, _Pantry pantry,
    {PantryPhotoService? photos,
    AppColorSeed seed = AppColorSeed.green,
    Brightness brightness = Brightness.light}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      groceryProvider.overrideWith((ref) => _Groceries()),
      pantryProvider.overrideWith((ref) => pantry),
      historyProvider.overrideWith((ref) => _History(ref)),
    ],
    child: MaterialApp(
      theme: AppTheme.fromSeed(seed, brightness: brightness),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: GroceryListScreen(photoService: photos),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('specific whole-word aliases consume the longest product phrase', () {
    expect(PantryPhotoService.matchProducts('almond milk', aliases),
        ['Almond milk']);
    expect(PantryPhotoService.matchProducts('peanut butter', aliases),
        ['Peanut butter']);
    expect(PantryPhotoService.matchProducts('pineapple food produce', aliases),
        isEmpty);
    expect(PantryPhotoService.matchProducts('apples, banana', aliases),
        containsAll(['Apples', 'Bananas']));
  });

  test('OCR counts are explicit, never prices or repeated label occurrences',
      () {
    final items = PantryPhotoService.textCandidates(
        '3 apples\napples x 3\n0.5 kg almond milk\nMilk 1.99 €', aliases);
    expect(items.firstWhere((i) => i.name == 'Apples').quantity, 3);
    expect(items.firstWhere((i) => i.name == 'Almond milk').quantity, 0.5);
    expect(items.firstWhere((i) => i.name == 'Milk').quantity, 1);
  });

  test('multi-photo picker cancellation/errors do not analyze or save',
      () async {
    var analyzed = 0;
    final service = PantryPhotoService(
      aliases: aliases,
      photoPicker: (_) async => [],
      analyzer: (_) async {
        analyzed++;
        return [];
      },
    );
    expect(await service.pick(ImageSource.camera), isEmpty);
    expect(await service.analyzeAll([]), isEmpty);
    expect(analyzed, 0);
    final failed = PantryPhotoService(
        aliases: aliases, photoPicker: (_) async => throw StateError('denied'));
    await expectLater(failed.pick(ImageSource.gallery), throwsStateError);
  });

  test('repeat photos deduplicate paths and stock counts use maximum not sum',
      () async {
    var calls = 0;
    final service = PantryPhotoService(
        aliases: aliases,
        analyzer: (_) async {
          calls++;
          return [
            const PantryPhotoCandidate('Apples', quantity: 3),
            const PantryPhotoCandidate('Bananas')
          ];
        });
    final result = await service
        .analyzeAll([XFile('first'), XFile('first'), XFile('second')]);
    expect(calls, 2);
    expect(result.length, 2);
    expect(result.first.quantity, 3);
  });

  test('reviewed stock save is atomic/idempotent; purchases remain additive',
      () async {
    final db = _MemoryDatabase();
    final service = DatabaseService.forTesting(db);
    await service.saveReviewedPantryItems([stock('Apples', 3)]);
    await service.saveReviewedPantryItems([stock('apple', 3)]);
    expect(db.rows.single['quantity'], 3);
    await service
        .saveReviewedPantryItems([stock('Apples', 2)], observations: false);
    expect(db.rows.single['quantity'], 5);
    db.failUpdate = true;
    await expectLater(
        service
            .saveReviewedPantryItems([stock('Bananas', 2), stock('Apples', 8)]),
        throwsStateError);
    expect(db.rows.length, 1);
    expect(db.rows.single['quantity'], 5);
    expect(db.transactions, 4);
  });

  test('unit conflict and invalid review roll back the whole save', () async {
    final db = _MemoryDatabase();
    final service = DatabaseService.forTesting(db);
    await service.saveReviewedPantryItems([stock('Milk', 500, unit: 'ml')]);
    await expectLater(
        service.saveReviewedPantryItems(
            [stock('Apples', 3), stock('Milk', 1, unit: 'l')]),
        throwsArgumentError);
    expect(db.rows.length, 1);
    await expectLater(service.saveReviewedPantryItems([stock('Bananas', -1)]),
        throwsArgumentError);
    expect(db.rows.length, 1);
  });

  testWidgets(
      'context switch preserves shopping list and reviewed save is once',
      (tester) async {
    final pantry = _Pantry();
    final photos = PantryPhotoService(
      aliases: aliases,
      photoPicker: (_) async => [XFile('assets/app_icon.png')],
      analyzer: (_) async => [
        const PantryPhotoCandidate('Apples', quantity: 3),
      ],
    );
    await _openGrocery(tester, pantry, photos: photos);
    expect(find.text('Bread'), findsOneWidget);
    await tester.tap(find.text('At home'));
    await tester.pumpAndSettle();
    expect(find.text('Bread'), findsNothing);
    await tester.tap(find.text('AI Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review foods'));
    await tester.pumpAndSettle();
    expect(pantry.saves, 0);
    await tester.enterText(
        find.byWidgetPredicate((widget) =>
            widget is TextField && widget.decoration?.labelText == 'Quantity'),
        '4');
    pantry.saving = Completer<void>();
    final save = find.byType(ElevatedButton);
    await tester.tap(save);
    await tester.pump();
    await tester.tap(save, warnIfMissed: false);
    expect(pantry.saves, 1);
    pantry.saving!.complete();
    await tester.pumpAndSettle();
    expect(pantry.state.items.single.quantity, 4);
    await tester.tap(find.descendant(
        of: find.byType(SegmentedButton<bool>),
        matching: find.text('Groceries')));
    await tester.pumpAndSettle();
    expect(find.text('Bread'), findsOneWidget);
  });

  testWidgets('canceling photos leaves pantry unchanged', (tester) async {
    final pantry = _Pantry();
    await _openGrocery(tester, pantry);
    await tester.tap(find.text('At home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(pantry.saves, 0);
    expect(pantry.state.items, isEmpty);
  });

  for (final seed in AppColorSeed.values) {
    testWidgets('${seed.name} shopping-frequency popup has readable colors',
        (tester) async {
      for (final brightness in Brightness.values) {
        await _openGrocery(tester, _Pantry(),
            seed: seed, brightness: brightness);
        await tester.tap(find.text('AI Scan'));
        await tester.pumpAndSettle();
        final dropdown = tester
            .widget<DropdownButton<int>>(find.byType(DropdownButton<int>));
        final foreground = dropdown.style!.color!;
        final background = dropdown.dropdownColor!;
        final a = foreground.computeLuminance();
        final b = background.computeLuminance();
        expect(((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05),
            greaterThanOrEqualTo(4.5));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }
}
