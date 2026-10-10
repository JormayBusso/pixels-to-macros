import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/core/app_localizations.dart';
import 'package:pixels_to_macros/models/food_data.dart';
import 'package:pixels_to_macros/models/scan_diagnostics.dart';
import 'package:pixels_to_macros/models/scan_result.dart';
import 'package:pixels_to_macros/providers/scan_result_provider.dart';
import 'package:pixels_to_macros/screens/scan_3d_viewer_screen.dart';
import 'package:pixels_to_macros/widgets/scan_3d_viewer.dart';

Map<String, dynamic> _object({
  String id = 'beef_0',
  String label = 'beef',
  double volume = 0,
  bool? measured = false,
  String mode = 'monocular_top_only',
}) =>
    {
      'id': id,
      'label': label,
      'volume_cm3': volume,
      'pixel_count': 4200,
      'scan_mode': mode,
      if (measured != null) 'volume_measured': measured,
      if (measured == false) 'side_missing_reason': 'missing_capture',
    };

const _beef = FoodData(
  label: 'beef',
  densityMin: 1,
  densityMax: 1,
  kcalPer100g: 200,
  category: 'meat',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Volume status metadata', () {
    test('explicit status survives model metadata and history round-trip', () {
      final object = Scan3DObject.fromMap(_object());
      expect(object.volumeStatus, ScanVolumeStatus.unmeasured);
      expect(object.hasMeasuredVolume, isFalse);
      final decoded = Scan3DObject.fromMap(object.toMap());
      expect(decoded.volumeStatus, ScanVolumeStatus.unmeasured);
      expect(decoded.sideMissingReason, 'missing_capture');

      final saved = ScanResult(
        timestamp: DateTime(2026, 10, 10),
        depthMode: 'monocular_scale',
        foods: const [],
        modelPath: 'top-outline.usdz',
        modelObjectsJson: jsonEncode([object.toMap()]),
      );
      final restored = ScanResult.fromMap(saved.toMap());
      expect(restored.unmeasuredFoodLabels, ['beef']);
      expect(restored.modelPath, 'top-outline.usdz');
      expect(restored.foods, isEmpty);
    });

    test('legacy positive volumes stay usable without inventing status', () {
      final legacy = Scan3DObject.fromMap(
        _object(volume: 100, measured: null, mode: 'lidar_mesh'),
      );
      expect(legacy.volumeStatus, isNull);
      expect(legacy.hasMeasuredVolume, isTrue);
      expect(legacy.toMap().containsKey('volume_measured'), isFalse);
      final restored = Scan3DObject.fromMap(legacy.toMap());
      expect(restored.volumeStatus, isNull);
      expect(restored.hasMeasuredVolume, isTrue);
    });

    test('zero and invalid volume never become a usable measurement', () {
      for (final volume in [0.0, -1.0, double.nan, double.infinity]) {
        final object = Scan3DObject.fromMap(
          _object(volume: volume, measured: true, mode: 'lidar_mesh'),
        );
        expect(object.hasMeasuredVolume, isFalse);
      }
      expect(
        Scan3DObject.fromMap(_object(measured: null)).volumeStatus,
        ScanVolumeStatus.unmeasured,
      );
    });

    test('explicit unmeasured overrides a positive LiDAR volume', () {
      final object = Scan3DObject.fromMap(
        _object(volume: 150, mode: 'lidar_mesh'),
      );
      expect(object.hasMeasuredVolume, isFalse);
    });

    test('old or malformed history metadata remains readable', () {
      for (final raw in [null, '', 'not-json', '{}']) {
        final scan = ScanResult(
          timestamp: DateTime(2026),
          depthMode: 'lidar_mesh',
          foods: const [],
          modelObjectsJson: raw,
        );
        expect(scan.unmeasuredFoodLabels, isEmpty);
      }
    });
  });

  group('Native result to nutrition', () {
    test('top-only scan succeeds without nutrition or DB lookup', () async {
      final notifier = ScanResultNotifier(
        runInference: () async => [_object()],
        lookupFood: (_) async => throw StateError('must not look up nutrition'),
      );
      addTearDown(notifier.dispose);
      await notifier.runVideoScan();
      expect(notifier.state.error, isNull);
      expect(notifier.state.failureKind, isNull);
      expect(notifier.state.foods, isEmpty);
      expect(notifier.state.unmeasuredFoodLabels, ['beef']);
      expect(notifier.state.hasUnmeasuredFoods, isTrue);
      expect(notifier.state.totalCaloriesMin, 0);
      expect(notifier.state.totalCaloriesMax, 0);
    });

    test('LiDAR missing-side status excludes even positive depth volume',
        () async {
      final notifier = ScanResultNotifier(
        runInference: () async => [_object(volume: 100, mode: 'lidar_mesh')],
        lookupFood: (_) async =>
            throw StateError('unmatched LiDAR is not nutrition'),
      );
      addTearDown(notifier.dispose);
      await notifier.runVideoScan();
      expect(notifier.state.error, isNull);
      expect(notifier.state.foods, isEmpty);
      expect(notifier.state.unmeasuredFoodLabels, ['beef']);
      expect(notifier.state.totalCaloriesMax, 0);
    });

    test('partial scan keeps measured instances only, including same label',
        () async {
      final lookups = <String>[];
      final notifier = ScanResultNotifier(
        runInference: () async => [
          _object(volume: 100, measured: true, mode: 'monocular_visual_hull'),
          _object(id: 'beef_1'),
          _object(id: 'beef_2', volume: 100, mode: 'lidar_mesh'),
        ],
        lookupFood: (label) async {
          lookups.add(label);
          return _beef;
        },
      );
      addTearDown(notifier.dispose);
      await notifier.runVideoScan();
      expect(notifier.state.error, isNull);
      expect(notifier.state.foods, hasLength(1));
      expect(notifier.state.foods.single.volumeCm3, 100);
      expect(notifier.state.totalCaloriesMin, 200);
      expect(notifier.state.totalCaloriesMax, 200);
      expect(notifier.state.unmeasuredFoodLabels, ['beef', 'beef']);
      expect(lookups, ['beef']);
    });

    test('legacy measured scan keeps existing nutrition calculation', () async {
      final notifier = ScanResultNotifier(
        runInference: () async =>
            [_object(volume: 100, measured: null, mode: 'lidar_mesh')],
        lookupFood: (_) async => _beef,
      );
      addTearDown(notifier.dispose);
      await notifier.runVideoScan();
      expect(notifier.state.foods, hasLength(1));
      expect(notifier.state.totalCaloriesMin, 200);
      expect(notifier.state.hasUnmeasuredFoods, isFalse);
    });

    test('zero without status retained as unmeasured, not silently rejected',
        () async {
      final notifier = ScanResultNotifier(
        runInference: () async => [_object(measured: null, mode: 'lidar_mesh')],
        lookupFood: (_) async => throw StateError('no nutrition for zero'),
      );
      addTearDown(notifier.dispose);
      await notifier.runVideoScan();
      expect(notifier.state.error, isNull);
      expect(notifier.state.hasUnmeasuredFoods, isTrue);
      expect(notifier.state.foods, isEmpty);
    });

    test('existing measured size gate and no-food behavior remain', () async {
      final notifier = ScanResultNotifier(
        runInference: () async => [
          _object(volume: 3, measured: true, mode: 'lidar_mesh'),
          _object(label: 'plate'),
        ],
        lookupFood: (_) async => throw StateError('size gate must reject'),
      );
      addTearDown(notifier.dispose);
      await notifier.runVideoScan();
      expect(notifier.state.failureKind, ScanFailureKind.noFood);
      expect(notifier.state.unmeasuredFoodLabels, isEmpty);
    });
  });

  test('diagnostics distinguish raw zero from measured volume and weight', () {
    final raw = {..._object(), 'weight_g': 0, 'height_cm': 0};
    final diagnostic = FoodDiagnostic.fromMap(raw);
    expect(diagnostic.volumeStatus, ScanVolumeStatus.unmeasured);
    expect(diagnostic.sideMissingReason, 'missing_capture');
    expect(diagnostic.hasMeasuredVolume, isFalse);
    final scan = ScanDiagnostics.fromCapture(
      depthMode: 'monocular_scale',
      nativeObjects: [raw],
      timings: const {},
    );
    final report = scan.toReport();
    expect(report, contains('unmeasured (nutrition excluded)'));
    expect(report, contains('side_missing_reason=missing_capture'));
    expect(report, isNot(contains('volume:    0.0 cm³')));
    expect(report, isNot(contains('weight:    0 g')));
  });

  test('recapture and partial nutrition copy exists in all five languages', () {
    final guidance = <String>{};
    for (final language in ['en', 'nl', 'es', 'de', 'pl']) {
      final l10n = AppLocalizations(Locale(language));
      expect(l10n.scanVolumeUnmeasured, isNotEmpty);
      expect(l10n.scanUnmeasuredFoods('beef'), contains('beef'));
      expect(l10n.scanPartialNutrition, isNotEmpty);
      expect(l10n.scanMeasuredFoodsLogged, isNotEmpty);
      guidance.add(l10n.scanSideRecaptureGuidance);
    }
    expect(guidance, hasLength(5));
  });

  testWidgets('unmeasured viewer shows recapture guidance, not a zero meal',
      (tester) async {
    final l10n = AppLocalizations(const Locale('en'));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scan3DViewerScreen(
        modelPath: null,
        objects: [Scan3DObject.fromMap(_object())],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining(l10n.scanSideRecaptureGuidance), findsOneWidget);
    expect(
        find.textContaining(l10n.scanUnmeasuredFoods('beef')), findsOneWidget);
    expect(find.text(l10n.close), findsOneWidget);
    expect(find.textContaining('0 kcal'), findsNothing);
    expect(find.textContaining('0 g'), findsNothing);
  });
}
