import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pixels_to_macros/core/constants.dart';
import 'package:pixels_to_macros/models/food_data.dart';
import 'package:pixels_to_macros/models/scan_diagnostics.dart';
import 'package:pixels_to_macros/models/scan_result.dart';
import 'package:pixels_to_macros/models/user_preferences.dart';
import 'package:pixels_to_macros/providers/analytics_provider.dart';
import 'package:pixels_to_macros/providers/scan_result_provider.dart';
import 'package:pixels_to_macros/services/database_service.dart';
import 'package:pixels_to_macros/services/native_bridge.dart';

const rice = FoodData(
    label: 'rice',
    densityMin: 0.5,
    densityMax: 0.9,
    kcalPer100g: 130,
    category: 'grain');

class _MigrationDatabase extends Fake implements DatabaseExecutor {
  String? sql;
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    this.sql = sql;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'extra accuracy defaults ON for new and legacy preferences and persists OFF',
      () {
    expect(const UserPreferences().extraAccuracy, isTrue);
    expect(UserPreferences.fromMap({}).extraAccuracy, isTrue);
    final off = const UserPreferences().copyWith(extraAccuracy: false);
    expect(off.toMap()['extra_accuracy'], 0);
    expect(UserPreferences.fromMap(off.toMap()).extraAccuracy, isFalse);
    expect(off.copyWith(name: 'A').extraAccuracy, isFalse);
  });

  test('version49 migration is additive default ON and fresh schema matches',
      () async {
    final db = _MigrationDatabase();
    await DatabaseService.migrateExtraAccuracy(db);
    expect(db.sql,
        'ALTER TABLE user_preferences ADD COLUMN extra_accuracy INTEGER NOT NULL DEFAULT 1');
    final source =
        File('lib/services/database_service.dart').readAsStringSync();
    expect(source, contains('version: 49'));
    expect(source, contains('if (oldVersion < 49)'));
    expect(source,
        contains('extra_accuracy           INTEGER NOT NULL DEFAULT 1'));
  });

  test(
      'bridge sends explicit strict default or approximate without changing exemplars',
      () async {
    const channel = MethodChannel(AppConstants.methodChannelName);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return '[]';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await NativeBridge.instance.runVideoInference();
    await NativeBridge.instance.runVideoInference(extraAccuracy: false);
    expect(calls.map((call) => (call.arguments as Map)['scan_mode']),
        ['strict', 'approximate']);
    expect(calls.every((call) => call.method == 'runVideoInference'), isTrue);
  });

  test('OFF bypasses side geometry and requires review before any nutrition',
      () async {
    final notifier = ScanResultNotifier(
      runInference: () async => [
        {
          'label': 'rice',
          'scan_mode': 'approximate',
          'volume_cm3': 0,
          'volume_measured': false,
        }
      ],
      lookupFood: (label) async => label == 'rice' ? rice : null,
      lookupPortion: (_) async => 175,
    );
    addTearDown(notifier.dispose);
    await notifier.runVideoScan(extraAccuracy: false);
    expect(notifier.state.failureKind, isNull);
    expect(notifier.state.needsPortionReview, isTrue);
    expect(notifier.state.foods, isEmpty);
    expect(notifier.state.portions.single.grams, 175);
    expect(
        await notifier.confirmApproximatePortions([
          const ApproximatePortion(label: 'rice', grams: 150),
        ]),
        isTrue);
    expect(notifier.state.foods.single.volumeCm3, 0);
    expect(notifier.state.foods.single.caloriesMin, 195);
    expect(notifier.state.metadata.single['portion_status'], 'estimated');
    expect(notifier.state.metadata.single['volume_status'], 'unavailable');
    expect(notifier.state.metadata.single.containsKey('height_cm'), isFalse);
    expect(
        await notifier.confirmApproximatePortions([
          const ApproximatePortion(label: 'rice', grams: 150),
        ]),
        isFalse);

    final scan = ScanResult(
        timestamp: DateTime(2026),
        depthMode: 'approximate',
        foods: notifier.state.foods,
        modelObjectsJson: jsonEncode(notifier.state.metadata));
    final restored = ScanResult.fromMap(scan.toMap(), foods: [
      for (final food in scan.foods) DetectedFood.fromMap(food.toMap()),
    ]);
    expect(restored.isApproximate, isTrue);
    expect(restored.reviewedPortionFor(restored.foods.single), 150);
    expect(restored.unmeasuredFoodLabels, isEmpty);
    expect(restored.modelPath, isNull);
    expect(restored.sideImagePath, isNull);
    final diagnostic = FoodDiagnostic.fromMap(notifier.state.metadata.single);
    expect(diagnostic.hasMeasuredVolume, isFalse);
    expect(diagnostic.heightCm, isNull);
    expect(diagnostic.densityGCm3, isNull);
    expect(diagnostic.estimated, isTrue);
  });

  test('unknown food and invalid portions cannot become success defaults',
      () async {
    final notifier = ScanResultNotifier(
      runInference: () async => [
        {'label': 'mystery casserole'}
      ],
      lookupFood: (label) async => label == 'rice' ? rice : null,
      lookupPortion: (_) async => null,
    );
    addTearDown(notifier.dispose);
    await notifier.runVideoScan(extraAccuracy: false);
    expect(notifier.state.portions.single.grams, isNull);
    expect(notifier.state.portions.single.foodData, isNull);
    for (final portion in [
      const ApproximatePortion(label: 'mystery casserole', grams: 120),
      const ApproximatePortion(label: 'rice', grams: 0),
      const ApproximatePortion(label: 'rice', grams: double.nan),
    ]) {
      expect(await notifier.confirmApproximatePortions([portion]), isFalse);
      expect(notifier.state.foods, isEmpty);
      expect(notifier.state.needsPortionReview, isTrue);
    }
    expect(
        await notifier.confirmApproximatePortions([
          const ApproximatePortion(label: 'rice', grams: 120),
        ]),
        isTrue);
  });

  test('strict default still rejects missing side atomically after an estimate',
      () async {
    final notifier = ScanResultNotifier(
      runInference: () async => [
        {
          'label': 'rice',
          'scan_mode': 'monocular_top_only',
          'volume_cm3': 0,
          'volume_measured': false,
        }
      ],
      lookupFood: (_) async => rice,
      lookupPortion: (_) async => null,
    );
    addTearDown(notifier.dispose);
    await notifier.runVideoScan(extraAccuracy: false);
    await notifier.confirmApproximatePortions([
      const ApproximatePortion(label: 'rice', grams: 100),
    ]);
    await notifier.runVideoScan();
    expect(notifier.state.failureKind, ScanFailureKind.sideViewRequired);
    expect(notifier.state.foods, isEmpty);
    expect(notifier.state.portions, isEmpty);
  });

  test('analytics retains the approximate status separately from calories', () {
    final state = AnalyticsState(days: [
      DaySummary(
          date: DateTime(2026),
          caloriesAvg: 195,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
          scanCount: 1,
          approximateScanCount: 1),
    ]);
    expect(state.includesApproximateEstimates, isTrue);
    expect(state.averageDaily, 195);
    expect(const AnalyticsState().includesApproximateEstimates, isFalse);
  });

  test('reviewed drink amounts stay ml, never fabricated grams or scan volume',
      () async {
    final notifier = ScanResultNotifier(
      runInference: () async => [
        {'label': 'milk'}
      ],
      lookupFood: (_) async => const FoodData(
          label: 'milk',
          densityMin: 1,
          densityMax: 1,
          kcalPer100g: 50,
          category: 'drink',
          perMl: true),
      lookupPortion: (_) async => null,
    );
    addTearDown(notifier.dispose);
    await notifier.runVideoScan(extraAccuracy: false);
    expect(
        await notifier.confirmApproximatePortions([
          const ApproximatePortion(label: 'milk', grams: 200),
        ]),
        isTrue);
    final metadata = notifier.state.metadata.single;
    expect(metadata['portion_amount'], 200);
    expect(metadata['portion_unit'], 'ml');
    expect(metadata.containsKey('weight_g'), isFalse);
    expect(notifier.state.foods.single.volumeCm3, 0);
    expect(notifier.state.foods.single.caloriesMin, 100);
    final diagnostic = FoodDiagnostic.fromMap(metadata);
    expect(diagnostic.portionUnit, 'ml');
    expect(diagnostic.weightG, isNull);
    expect(diagnostic.hasMeasuredVolume, isFalse);
  });
}
