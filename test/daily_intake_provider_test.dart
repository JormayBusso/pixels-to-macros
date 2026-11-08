import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/core/app_localizations.dart';
import 'package:pixels_to_macros/models/food_data.dart';
import 'package:pixels_to_macros/models/nutrition_goal.dart';
import 'package:pixels_to_macros/models/scan_result.dart';
import 'package:pixels_to_macros/models/user_preferences.dart';
import 'package:pixels_to_macros/providers/analytics_provider.dart';
import 'package:pixels_to_macros/providers/daily_intake_provider.dart';
import 'package:pixels_to_macros/providers/history_provider.dart';
import 'package:pixels_to_macros/providers/scan_result_provider.dart';
import 'package:pixels_to_macros/providers/user_prefs_provider.dart';
import 'package:pixels_to_macros/screens/diabetes/bolus_calculator_card.dart';
import 'package:pixels_to_macros/screens/edit_food_screen.dart';
import 'package:pixels_to_macros/screens/scan_detail_screen.dart';
import 'package:pixels_to_macros/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

const salmon = FoodData(
  id: 1,
  label: 'salmon',
  densityMin: 1,
  densityMax: 1,
  kcalPer100g: 100,
  category: 'protein',
  proteinPer100g: 20,
  carbsPer100g: 5,
  fatPer100g: 10,
  vitaminCMgPer100g: 8,
);

class _FoodDatabase extends Fake implements Database {
  _FoodDatabase(List<FoodData> foods) : foods = [...foods];
  final List<FoodData> foods;
  final List<Map<String, Object?>> detected = [];

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    if (table == 'detected_foods') {
      return detected
          .where((row) =>
              row[where == 'id = ?' ? 'id' : 'scan_id'] == whereArgs!.first)
          .map((row) => Map<String, Object?>.from(row))
          .toList();
    }
    if (table != 'food_data') throw StateError('Unexpected table: $table');
    final matches = foods.where((food) {
      if (whereArgs == null) return true;
      if (where == 'id = ? AND label = ?') {
        return food.id == whereArgs[0] && food.label == whereArgs[1];
      }
      if (where == 'id = ? OR label = ?') {
        return food.id == whereArgs[0] || food.label == whereArgs[1];
      }
      return food.label.toLowerCase() ==
          (whereArgs.first as String).toLowerCase();
    });
    return matches.map((food) => food.toMap()).toList();
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    if (table != 'detected_foods') throw StateError('Unexpected table: $table');
    final id = detected.length + 1;
    detected.add({...values, 'id': id});
    return id;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
          {bool? exclusive}) =>
      action(_Transaction(this));

  Future<int> updateRows(
      Map<String, Object?> values, String? where, List<Object?>? args) async {
    var changed = 0;
    for (final row in detected) {
      final matches = where == 'nutrition_food_id = ?'
          ? row['nutrition_food_id'] == args![0]
          : row['id'] == args![0] &&
              (where != 'id = ? AND label != ?' || row['label'] != args[1]);
      if (matches) {
        row.addAll(values);
        changed++;
      }
    }
    return changed;
  }
}

class _Transaction extends Fake implements Transaction {
  _Transaction(this.db);
  final _FoodDatabase db;

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
          int? offset}) =>
      db.query(table, columns: columns, where: where, whereArgs: whereArgs);

  @override
  Future<int> update(String table, Map<String, Object?> values,
          {String? where,
          List<Object?>? whereArgs,
          ConflictAlgorithm? conflictAlgorithm}) =>
      db.updateRows(values, where, whereArgs);

  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    db.foods.removeWhere((food) =>
        food.id == values['id'] && food.id != null ||
        food.label == values['label']);
    db.foods.add(FoodData.fromMap(values));
    return (values['id'] as int?) ?? 99;
  }

  @override
  Future<int> delete(String table,
      {String? where, List<Object?>? whereArgs}) async {
    db.foods.removeWhere((food) => food.id == whereArgs!.first);
    return 1;
  }
}

class _MigrationDatabase extends Fake implements DatabaseExecutor {
  final statements = <String>[];
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    statements.add(sql);
  }
}

class _DatabaseService extends DatabaseService {
  factory _DatabaseService(List<FoodData> foods, List<ScanResult> scans) =>
      _DatabaseService.withDatabase(_FoodDatabase(foods), scans);

  _DatabaseService.withDatabase(this.db, this.scans) : super.forTesting(db);

  final _FoodDatabase db;
  final List<ScanResult> scans;

  @override
  Future<List<ScanResult>> getAllScanResults() async => scans;
}

class _History extends HistoryNotifier {
  _History(super.ref);
  @override
  Future<void> load() async {}
}

class _Intake extends DailyIntakeNotifier {
  @override
  Future<void> load() async {}
}

class _DiabetesPrefs extends UserPrefsNotifier {
  _DiabetesPrefs() {
    state = const UserPreferences(nutritionGoal: NutritionGoalType.diabetes);
  }
}

class _DelayedDatabase extends _DatabaseService {
  _DelayedDatabase(_FoodDatabase db) : super.withDatabase(db, []);
  final ready = Completer<void>();

  @override
  Future<FoodData?> getFoodForNutrition(DetectedFood food,
      {bool legacyAliasFirst = true}) async {
    await ready.future;
    return super.getFoodForNutrition(food, legacyAliasFirst: legacyAliasFirst);
  }
}

ScanResult _scan(String mode, String label,
        {double calories = 100,
        int? nutritionFoodId,
        String? nutritionFoodLabel}) =>
    ScanResult(
      timestamp: DateTime.now(),
      depthMode: mode,
      foods: [
        DetectedFood(
          label: label,
          nutritionFoodId: nutritionFoodId,
          nutritionFoodLabel: nutritionFoodLabel,
          volumeCm3: 100,
          caloriesMin: calories,
          caloriesMax: calories,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('version 52 adds nullable identity columns', () async {
    final db = _MigrationDatabase();
    await DatabaseService.migrateNutritionFoodIdentity(db);
    expect(db.statements, [
      'ALTER TABLE detected_foods ADD COLUMN nutrition_food_id INTEGER',
      'ALTER TABLE detected_foods ADD COLUMN nutrition_food_label TEXT',
    ]);
  });

  test('detected-food persistence round-trips identity without changing labels',
      () async {
    final database = _DatabaseService([salmon], []);
    final food = _scan('monocular_scale', 'smoked salmon',
            nutritionFoodId: 1, nutritionFoodLabel: 'salmon')
        .foods
        .single;
    await database.insertDetectedFood(7, food);
    final restored = (await database.getDetectedFoodsForScan(7)).single;
    expect(restored.label, 'smoked salmon');
    expect(restored.caloriesMin, 100);
    expect(restored.nutritionFoodId, 1);
    expect(restored.nutritionFoodLabel, 'salmon');
    expect((await database.getFoodForNutrition(restored))?.id, 1);
  });

  test('strict scan nutrition follows the same fuzzy lookup for both paths',
      () async {
    for (final mode in [
      'lidar_mesh',
      'lidar_depth',
      'monocular_scale',
      'monocular_visual_hull',
    ]) {
      final database = _DatabaseService([salmon], []);
      final scanNotifier = ScanResultNotifier(
        runInference: () async => [
          {
            'label': 'smoked salmon',
            'scan_mode': mode,
            'volume_cm3': 100,
            'volume_measured': true,
            'pixel_count': 4200,
          },
        ],
        lookupFood: database.getFoodByLabelFuzzy,
      );
      addTearDown(scanNotifier.dispose);
      await scanNotifier.runVideoScan();
      expect(scanNotifier.state.error, isNull);
      final food = scanNotifier.state.foods.single;
      expect(food.label, 'smoked salmon');
      expect(food.caloriesMin, 100);
      expect(food.nutritionFoodId, 1);
      expect(food.nutritionFoodLabel, 'salmon');
      final restored = DetectedFood.fromMap(food.toMap());
      expect(restored.nutritionFoodId, 1);
      expect(restored.nutritionFoodLabel, 'salmon');
      database.scans.add(ScanResult(
        timestamp: DateTime.now(),
        depthMode: mode,
        foods: [restored],
      ));

      final daily = DailyIntakeNotifier(
        database: database,
        refreshMealReminders: () async {},
      );
      final analytics = AnalyticsNotifier(database: database);
      addTearDown(daily.dispose);
      addTearDown(analytics.dispose);
      await daily.load();
      await analytics.load(rangeDays: 1);
      expect(daily.state.caloriesAvg, 100);
      expect(daily.state.proteinG, 20);
      expect(daily.state.carbsG, 5);
      expect(daily.state.fatG, 10);
      expect(daily.state.nutrientTotals.vitaminCMg, 8);
      expect(analytics.state.days.single.caloriesAvg, 100);
      expect(analytics.state.days.single.proteinG, 20);
      expect(analytics.state.days.single.carbsG, 5);
      expect(analytics.state.days.single.fatG, 10);
    }
  });

  test('exact labels and existing legacy alias precedence are retained',
      () async {
    const smoked = FoodData(
      label: 'smoked salmon',
      densityMin: 1,
      densityMax: 1,
      kcalPer100g: 100,
      category: 'protein',
      proteinPer100g: 30,
    );
    const chicken = FoodData(
      label: 'chicken',
      densityMin: 1,
      densityMax: 1,
      kcalPer100g: 100,
      category: 'protein',
      proteinPer100g: 12,
    );
    const chickenDuck = FoodData(
      label: 'chicken duck',
      densityMin: 1,
      densityMax: 1,
      kcalPer100g: 100,
      category: 'protein',
      proteinPer100g: 40,
    );
    final database = _DatabaseService(
      [salmon, smoked, chicken, chickenDuck],
      [
        _scan('lidar_mesh', 'Smoked Salmon'),
        _scan('lidar_mesh', 'chicken duck')
      ],
    );
    final daily = DailyIntakeNotifier(
      database: database,
      refreshMealReminders: () async {},
    );
    final analytics = AnalyticsNotifier(database: database);
    addTearDown(daily.dispose);
    addTearDown(analytics.dispose);
    await daily.load();
    await analytics.load(rangeDays: 1);
    expect(daily.state.proteinG, 42);
    expect(analytics.state.days.single.proteinG, 70);
    expect(daily.state.caloriesAvg, 200);

    final legacyOnly = _DatabaseService([chicken], []);
    final legacyFood = _scan('lidar_mesh', 'chicken duck').foods.single;
    expect(
        (await legacyOnly.getFoodForNutrition(legacyFood))?.label, 'chicken');
    expect(
        await legacyOnly.getFoodForNutrition(legacyFood,
            legacyAliasFirst: false),
        isNull);
  });

  test('unknown, manual and reviewed approximate entries retain their behavior',
      () async {
    final approximate = ScanResult(
      timestamp: DateTime.now(),
      depthMode: 'approximate',
      foods: const [
        DetectedFood(
          label: 'salmon',
          volumeCm3: 0,
          caloriesMin: 150,
          caloriesMax: 150,
        ),
      ],
      modelObjectsJson: jsonEncode([
        {
          'food_index': 0,
          'portion_reviewed': true,
          'portion_amount': 150,
          'portion_unit': 'g',
        },
      ]),
    );
    final database = _DatabaseService([
      salmon
    ], [
      _scan('lidar_mesh', 'smoked salmon',
          nutritionFoodId: 1, nutritionFoodLabel: 'salmon'),
      _scan('lidar_mesh', 'smoked salmon'),
      _scan('manual', 'smoked salmon'),
      _scan('approximate', 'smoked salmon'),
      _scan('monocular_scale', 'mystery gadget'),
      approximate,
    ]);
    final daily = DailyIntakeNotifier(
      database: database,
      refreshMealReminders: () async {},
    );
    final analytics = AnalyticsNotifier(database: database);
    addTearDown(daily.dispose);
    addTearDown(analytics.dispose);
    await daily.load();
    await analytics.load(rangeDays: 1);
    expect(daily.state.caloriesAvg, 650);
    expect(daily.state.proteinG, 50);
    expect(daily.state.nutrientTotals.vitaminCMg, 20);
    expect(analytics.state.days.single.proteinG, 50);
    expect(analytics.state.days.single.caloriesAvg, 650);
    expect(analytics.state.days.single.approximateScanCount, 2);
    expect(approximate.reviewedPortionFor(approximate.foods.single), 150);
    expect(approximate.foods.single.volumeCm3, 0);
    expect(
        await database.getFoodForNutrition(
            _scan('lidar_mesh', 'mystery gadget').foods.single),
        isNull);
  });

  test('captured identity stays fixed and corrections clear stale identity',
      () async {
    final database = _DatabaseService([salmon], []);
    final captured = _scan('lidar_mesh', 'smoked salmon',
            nutritionFoodId: 1, nutritionFoodLabel: 'salmon')
        .foods
        .single;
    database.db.foods.add(const FoodData(
      id: 2,
      label: 'smoked salmon',
      densityMin: 1,
      densityMax: 1,
      kcalPer100g: 200,
      category: 'protein',
    ));
    expect((await database.getFoodForNutrition(captured))?.id, 1);
    final renamed = _DatabaseService([
      const FoodData(
        id: 1,
        label: 'different food',
        densityMin: 1,
        densityMax: 1,
        kcalPer100g: 100,
        category: 'protein',
      ),
    ], []);
    expect(await renamed.getFoodForNutrition(captured), isNull);
    final replacement = _DatabaseService([
      const FoodData(
        id: 2,
        label: 'salmon',
        densityMin: 1,
        densityMax: 1,
        kcalPer100g: 100,
        category: 'protein',
      ),
    ], []);
    expect(await replacement.getFoodForNutrition(captured), isNull);
    expect(
      await database.getFoodForNutrition(
        _scan('lidar_mesh', 'salmon', nutritionFoodId: 1).foods.single,
      ),
      isNull,
    );
    database.db.detected.add({'id': 42, ...captured.toMap()});
    await database.updateDetectedFood(42,
        label: 'smoked salmon', caloriesMin: 120, caloriesMax: 120);
    expect(database.db.detected.single['nutrition_food_id'], 1);
    await database.updateDetectedFood(42,
        label: 'salmon', caloriesMin: 120, caloriesMax: 120);
    final corrected = DetectedFood.fromMap(database.db.detected.single);
    expect(corrected.nutritionFoodId, DetectedFood.unresolvedNutritionFoodId);
    expect(corrected.nutritionFoodLabel, isNull);
    expect(await database.getFoodForNutrition(corrected), isNull);
  });

  test('replacement and deletion invalidate identity even if id is reused',
      () async {
    for (final remove in [false, true]) {
      final database = _DatabaseService([salmon], []);
      final food = _scan('lidar_mesh', 'smoked salmon',
              nutritionFoodId: 1, nutritionFoodLabel: 'salmon')
          .foods
          .single;
      database.db.detected.add({'id': 42, ...food.toMap()});
      if (remove) {
        await database.deleteFood(1);
      }
      await database.insertFood(const FoodData(
        id: 1,
        label: 'salmon',
        densityMin: 1,
        densityMax: 1,
        kcalPer100g: 999,
        category: 'protein',
      ));
      final invalidated = DetectedFood.fromMap(database.db.detected.single);
      expect(invalidated.nutritionFoodId, -1);
      expect(await database.getFoodForNutrition(invalidated), isNull);
      expect(invalidated.caloriesMin, 100);
    }
  });

  test('unmatched new strict foods remain unmatched after a database addition',
      () async {
    for (final mode in ['lidar_mesh', 'monocular_visual_hull']) {
      final database = _DatabaseService([], []);
      final notifier = ScanResultNotifier(
        runInference: () async => [
          {
            'label': 'mystery',
            'scan_mode': mode,
            'volume_cm3': 100,
            'volume_measured': true,
            'pixel_count': 4200,
          }
        ],
        lookupFood: (_) async => null,
      );
      addTearDown(notifier.dispose);
      await notifier.runVideoScan();
      final food = DetectedFood.fromMap(notifier.state.foods.single.toMap());
      expect(food.nutritionFoodId, DetectedFood.unresolvedNutritionFoodId);
      final calories = food.caloriesMin;
      database.db.foods.add(const FoodData(
        id: 3,
        label: 'mystery',
        densityMin: 1,
        densityMax: 1,
        kcalPer100g: 200,
        category: 'protein',
        proteinPer100g: 30,
      ));
      expect(await database.getFoodForNutrition(food), isNull);
      expect(food.caloriesMin, calories);
      final legacy = _scan('lidar_mesh', 'mystery').foods.single;
      expect((await database.getFoodForNutrition(legacy))?.id, 3);
      expect(
          (await database
                  .getFoodForNutrition(_scan('manual', 'mystery').foods.single))
              ?.id,
          3);
      database.scans.add(ScanResult(
          timestamp: DateTime.now(), depthMode: mode, foods: [food]));
      final daily = DailyIntakeNotifier(
        database: database,
        refreshMealReminders: () async {},
      );
      final analytics = AnalyticsNotifier(database: database);
      addTearDown(daily.dispose);
      addTearDown(analytics.dispose);
      await daily.load();
      await analytics.load(rangeDays: 1);
      expect(daily.state.proteinG, 0);
      expect(analytics.state.days.single.proteinG, 0);
      expect(daily.state.caloriesMin, calories);
    }
  });

  test('manual corrections retain legacy exact lookup semantics', () async {
    final database = _DatabaseService([salmon], []);
    final original = _scan('manual', 'salmon').foods.single;
    database.db.detected.add({'id': 42, ...original.toMap()});
    await database.updateDetectedFood(
      42,
      label: 'salmon',
      caloriesMin: 150,
      caloriesMax: 150,
      recalculatedFood: salmon,
    );
    final corrected = DetectedFood.fromMap(database.db.detected.single);
    expect(corrected.nutritionFoodId, isNull);
    expect(corrected.nutritionFoodLabel, isNull);
    expect((await database.getFoodForNutrition(corrected))?.id, 1);
  });

  testWidgets(
      'same-label recalculation stores the newly selected food identity',
      (tester) async {
    final database = _DatabaseService([
      salmon,
      const FoodData(
        id: 2,
        label: 'smoked salmon',
        densityMin: 1,
        densityMax: 1,
        kcalPer100g: 200,
        category: 'protein',
        carbsPer100g: 40,
      ),
    ], []);
    final original = _scan('lidar_mesh', 'smoked salmon',
            nutritionFoodId: 1, nutritionFoodLabel: 'salmon')
        .foods
        .single;
    database.db.detected.add({'id': 42, ...original.toMap()});
    final saved = DetectedFood.fromMap(database.db.detected.single);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        historyProvider.overrideWith((ref) => _History(ref)),
        dailyIntakeProvider.overrideWith((ref) => _Intake()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Builder(
            builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => EditFoodScreen(
                        scanId: 7,
                        food: saved,
                        database: database,
                      ),
                    )),
                    child: const Text('Open'),
                  ),
                )),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final weight = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.labelText == 'Weight');
    await tester.enterText(weight, '150');
    await tester.pump();
    final save = find.byType(ElevatedButton).last;
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final corrected = DetectedFood.fromMap(database.db.detected.single);
    expect(corrected.label, 'smoked salmon');
    expect(corrected.nutritionFoodId, 2);
    expect(corrected.nutritionFoodLabel, 'smoked salmon');
    expect(corrected.caloriesMin, 285);
    expect(corrected.caloriesMax, 315);
    expect((await database.getFoodForNutrition(corrected))?.carbsPer100g, 40);
  });

  for (final unresolved in [false, true]) {
    testWidgets(
        'scan detail bolus prefill requires complete nutrition ($unresolved)',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'calc_info_seen_bolusEstimate': true,
        'calc_info_seen_plateScore': true,
        'calc_info_seen_glycemicLoad': true,
      });
      final db = _DelayedDatabase(_FoodDatabase([
        salmon,
        const FoodData(
          id: 2,
          label: 'smoked salmon',
          densityMin: 1,
          densityMax: 1,
          kcalPer100g: 200,
          category: 'protein',
          carbsPer100g: 40,
        ),
      ]));
      final scan = ScanResult(
        timestamp: DateTime.now(),
        depthMode: 'lidar_mesh',
        foods: [
          _scan('lidar_mesh', 'smoked salmon',
                  nutritionFoodId: 1, nutritionFoodLabel: 'salmon')
              .foods
              .single,
          _scan('manual', 'smoked salmon').foods.single,
          if (unresolved)
            _scan('lidar_mesh', 'smoked salmon',
                    nutritionFoodId: DetectedFood.unresolvedNutritionFoodId)
                .foods
                .single,
        ],
      );
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [userPrefsProvider.overrideWith((ref) => _DiabetesPrefs())],
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: ScanDetailScreen(scan: scan, database: db),
        ),
      ));
      await tester.pump();
      expect(find.byType(BolusCalculatorCard), findsNothing);
      db.ready.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final card =
          tester.widget<BolusCalculatorCard>(find.byType(BolusCalculatorCard));
      expect(card.initialCarbsG, unresolved ? null : 45);
      expect(card.key, ObjectKey(scan));
    });
  }
}
