import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pixels_to_macros/core/app_localizations.dart';
import 'package:pixels_to_macros/core/constants.dart';
import 'package:pixels_to_macros/core/scan_state.dart';
import 'package:pixels_to_macros/models/food_data.dart';
import 'package:pixels_to_macros/models/scan_diagnostics.dart';
import 'package:pixels_to_macros/models/scan_result.dart';
import 'package:pixels_to_macros/models/user_preferences.dart';
import 'package:pixels_to_macros/providers/analytics_provider.dart';
import 'package:pixels_to_macros/providers/scan_result_provider.dart';
import 'package:pixels_to_macros/providers/scan_state_provider.dart';
import 'package:pixels_to_macros/providers/user_prefs_provider.dart';
import 'package:pixels_to_macros/screens/scan_screen.dart';
import 'package:pixels_to_macros/screens/settings_screen.dart';
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

class _MemoryUserPrefsNotifier extends UserPrefsNotifier {
  _MemoryUserPrefsNotifier(UserPreferences preferences) {
    state = preferences;
  }

  Map<String, dynamic>? saved;

  @override
  Future<void> update(UserPreferences prefs) async {
    saved = prefs.toMap();
    state = UserPreferences.fromMap(saved!);
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
    expect(source, contains('version: 52'));
    expect(source, contains('if (oldVersion < 49)'));
    expect(source,
        contains('extra_accuracy           INTEGER NOT NULL DEFAULT 1'));
  });

  test('existing installs restore extra accuracy ON once at version50',
      () async {
    final db = _MigrationDatabase();
    await DatabaseService.restoreExtraAccuracyDefault(db);
    expect(db.sql, 'UPDATE user_preferences SET extra_accuracy = 1');
    final source =
        File('lib/services/database_service.dart').readAsStringSync();
    expect(source, contains('if (oldVersion < 50)'));
    expect(source, contains('await restoreExtraAccuracyDefault(db)'));
    final chosenOff = const UserPreferences().copyWith(extraAccuracy: false);
    expect(UserPreferences.fromMap(chosenOff.toMap()).extraAccuracy, isFalse);
  });

  test('plate diameter is nullable for legacy rows and resets explicitly', () {
    expect(const UserPreferences().plateDiameterCm, isNull);
    expect(UserPreferences.fromMap({}).plateDiameterCm, isNull);
    final custom = const UserPreferences().copyWith(plateDiameterCm: 24.5);
    expect(custom.toMap()['plate_diameter_cm'], 24.5);
    expect(UserPreferences.fromMap(custom.toMap()).plateDiameterCm, 24.5);
    expect(custom.copyWith(name: 'A').plateDiameterCm, 24.5);
    final reset = custom.copyWith(plateDiameterCm: null);
    expect(reset.toMap()['plate_diameter_cm'], isNull);
    expect(UserPreferences.fromMap(reset.toMap()).plateDiameterCm, isNull);
    expect(custom.copyWith(plateDiameterCm: 25).plateDiameterCm, 25.0);
    for (final value in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => custom.copyWith(plateDiameterCm: value), throwsArgumentError);
      expect(
        UserPreferences.fromMap({'plate_diameter_cm': value}).plateDiameterCm,
        isNull,
      );
      expect(
        () => UserPreferences(plateDiameterCm: value).toMap(),
        throwsArgumentError,
      );
    }
  });

  test('plate input accepts positive decimals and blank, rejects unsafe values',
      () {
    expect(UserPreferences.parsePlateDiameterCm(' 24,5 '), 24.5);
    expect(UserPreferences.parsePlateDiameterCm('26.25'), 26.25);
    expect(UserPreferences.parsePlateDiameterCm('  '), isNull);
    for (final input in [
      '0', '-1', 'NaN', 'Infinity', '-Infinity', '1e999', 'abc', '26 cm',
    ]) {
      expect(() => UserPreferences.parsePlateDiameterCm(input),
          throwsFormatException);
    }
  });

  test('version51 adds a nullable plate diameter without backfilling legacy rows',
      () async {
    final db = _MigrationDatabase();
    await DatabaseService.migratePlateDiameter(db);
    expect(db.sql,
        'ALTER TABLE user_preferences ADD COLUMN plate_diameter_cm REAL');
    final source = File('lib/services/database_service.dart').readAsStringSync();
    expect(source, contains('version: 52'));
    expect(source, contains('if (oldVersion < 51)'));
    expect(source, contains('await migratePlateDiameter(db)'));
    expect(source, contains('plate_diameter_cm        REAL'));
  });

  test('bridge omits unset diameter and rejects invalid values before native',
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
    for (final value in [0.0, -1.0, double.nan, double.infinity]) {
      await expectLater(
        NativeBridge.instance.runVideoInference(plateDiameterCm: value),
        throwsArgumentError,
      );
    }
    expect(calls.length, 1);
    expect((calls.single.arguments as Map).containsKey('plate_diameter_cm'),
        isFalse);
  });

  for (final extraAccuracy in [true, false]) {
    test('provider forwards plate diameter and exemplars in mode=$extraAccuracy',
        () async {
      const channel = MethodChannel(AppConstants.methodChannelName);
      final calls = <MethodCall>[];
      const exemplars = [
        {'label': 'rice', 'embedding': [0.1, 0.2]},
      ];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return '[]';
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final notifier =
          ScanResultNotifier(lookupExemplars: () async => exemplars);
      addTearDown(notifier.dispose);
      await notifier.runVideoScan(
          extraAccuracy: extraAccuracy, plateDiameterCm: 24.5);
      await notifier.runVideoScan(extraAccuracy: extraAccuracy);
      expect((calls.first.arguments as Map)['plate_diameter_cm'], 24.5);
      expect((calls.last.arguments as Map).containsKey('plate_diameter_cm'),
          isFalse);
      for (final call in calls) {
        expect((call.arguments as Map)['user_exemplars'], exemplars);
        expect((call.arguments as Map)['scan_mode'],
            extraAccuracy ? 'strict' : 'approximate');
      }
    });
  }

  for (final language in ['en', 'nl', 'es', 'de', 'pl']) {
    testWidgets('plate setting validates, saves and resets in $language',
        (tester) async {
      final prefs = _MemoryUserPrefsNotifier(const UserPreferences());
      final container = ProviderContainer(overrides: [
        userPrefsProvider.overrideWith((ref) => prefs),
      ]);
      addTearDown(container.dispose);
      final l10n = AppLocalizations(Locale(language));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(language),
          supportedLocales: [Locale(language)],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(
            body: SingleChildScrollView(child: PlateDiameterSetting()),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(l10n.knownPlateDiameterHelp), findsOneWidget);
      expect(find.text(l10n.assumedPlateDiameter), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'NaN');
      await tester.tap(find.text(l10n.save));
      await tester.pump();
      expect(find.text(l10n.plateDiameterInvalid), findsOneWidget);
      expect(prefs.saved, isNull);
      await tester.enterText(find.byType(TextFormField), '24,5');
      await tester.tap(find.text(l10n.save));
      await tester.pump();
      expect(prefs.saved!['plate_diameter_cm'], 24.5);
      expect(prefs.state.plateDiameterCm, 24.5);
      await tester.tap(find.text(l10n.resetPlateDiameter));
      await tester.pump();
      expect(prefs.saved!['plate_diameter_cm'], isNull);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
        isEmpty,
      );
      await tester.enterText(find.byType(TextFormField), '25');
      await tester.tap(find.text(l10n.save));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text(l10n.save));
      await tester.pump();
      expect(prefs.saved!['plate_diameter_cm'], isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final extraAccuracy in [true, false]) {
    for (final diameter in <double?>[null, 24.5]) {
      testWidgets(
          'capture snapshots mode=$extraAccuracy diameter=$diameter before top photo',
          (tester) async {
        const scanner = MethodChannel(AppConstants.methodChannelName);
        const liveGlow = MethodChannel('com.pixelstomacros/live_glow');
        const permissions =
            MethodChannel('flutter.baseflow.com/permissions/methods');
        final prefs = _MemoryUserPrefsNotifier(UserPreferences(
          hasSeenScanTutorial: true,
          extraAccuracy: extraAccuracy,
          plateDiameterCm: diameter,
        ));
        final container = ProviderContainer(overrides: [
          userPrefsProvider.overrideWith((ref) => prefs),
          scanResultProvider.overrideWith(
              (ref) => ScanResultNotifier(lookupExemplars: () async => [])),
        ]);
        addTearDown(container.dispose);
        final calls = <MethodCall>[];
        var topCaptures = 0;
        var sideCaptures = 0;
        final messenger = TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(permissions,
            (_) async => {Permission.camera.value: 1});
        messenger.setMockMethodCallHandler(SystemChannels.platform_views,
            (_) async => null);
        messenger.setMockMethodCallHandler(SystemChannels.platform,
            (_) async => null);
        messenger.setMockMethodCallHandler(liveGlow, (_) async => null);
        messenger.setMockMethodCallHandler(scanner, (call) async {
          switch (call.method) {
            case 'startSession':
              return 1;
            case 'getDepthMode':
              return 'monocular_scale';
            case 'getPhonePitch':
              final state = container.read(scanStateProvider);
              return state == ScanState.moveSide ||
                      state == ScanState.captureSide
                  ? 0.0
                  : -1.5707963267948966;
            case 'getMotionStability':
              return 1.0;
            case 'getAmbientIntensity':
              return 500.0;
            case 'captureTopFrame':
              topCaptures++;
              await prefs.update(prefs.state.copyWith(
                  extraAccuracy: !extraAccuracy, plateDiameterCm: 31.0));
              return true;
            case 'captureSideFrame':
              sideCaptures++;
              return true;
            case 'runVideoInference':
              calls.add(call);
              return '[]';
            default:
              return null;
          }
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(scanner, null);
          messenger.setMockMethodCallHandler(permissions, null);
          messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
          messenger.setMockMethodCallHandler(SystemChannels.platform, null);
          messenger.setMockMethodCallHandler(liveGlow, null);
        });
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            home: const ScanScreen(),
          ),
        ));
        for (var tick = 0; tick < 60 && calls.isEmpty; tick++) {
          await tester.pump(const Duration(milliseconds: 80));
        }
        expect(calls.length, 1);
        expect(topCaptures, 1);
        expect(sideCaptures, extraAccuracy ? 1 : 0);
        final arguments = calls.single.arguments as Map;
        expect(arguments['scan_mode'], extraAccuracy ? 'strict' : 'approximate');
        expect(arguments.containsKey('plate_diameter_cm'), diameter != null);
        if (diameter != null) {
          expect(arguments['plate_diameter_cm'], diameter);
        }
        final nextDiameter = diameter == null ? 31.0 : null;
        await prefs.update(prefs.state.copyWith(plateDiameterCm: nextDiameter));
        await tester.pump();
        await tester.tap(find.text(AppLocalizations(const Locale('en')).retry));
        for (var tick = 0; tick < 60 && calls.length < 2; tick++) {
          await tester.pump(const Duration(milliseconds: 80));
        }
        expect(calls.length, 2);
        expect(topCaptures, 2);
        expect(sideCaptures, 1);
        final retryArguments = calls.last.arguments as Map;
        expect(retryArguments['scan_mode'],
            extraAccuracy ? 'approximate' : 'strict');
        expect(retryArguments.containsKey('plate_diameter_cm'),
            nextDiameter != null);
        if (nextDiameter != null) {
          expect(retryArguments['plate_diameter_cm'], nextDiameter);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }

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

  test('separate same-label portions keep their own reviewed amount in history',
      () async {
    final notifier = ScanResultNotifier(
      runInference: () async => [
        {'id': 'approximate_0', 'label': 'rice'},
        {'id': 'approximate_1', 'label': 'rice'},
      ],
      lookupFood: (_) async => rice,
      lookupPortion: (_) async => null,
    );
    addTearDown(notifier.dispose);
    await notifier.runVideoScan(extraAccuracy: false);
    expect(notifier.state.portions.length, 2);
    expect(
      await notifier.confirmApproximatePortions([
        const ApproximatePortion(label: 'rice', grams: 100),
        const ApproximatePortion(label: 'rice', grams: 200),
      ]),
      isTrue,
    );
    final scan = ScanResult(
      timestamp: DateTime(2026),
      depthMode: 'approximate',
      foods: notifier.state.foods,
      modelObjectsJson: jsonEncode(notifier.state.metadata),
    );
    final restored = ScanResult.fromMap(scan.toMap(), foods: [
      for (final food in scan.foods) DetectedFood.fromMap(food.toMap()),
    ]);
    expect(restored.foods.map(restored.reviewedPortionFor), [100, 200]);
    expect(restored.totalCaloriesMin, 390);
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
