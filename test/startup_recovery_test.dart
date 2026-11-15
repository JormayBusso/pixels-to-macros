import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:pixels_to_macros/app.dart';
import 'package:pixels_to_macros/models/user_preferences.dart';
import 'package:pixels_to_macros/providers/diabetes_provider.dart';
import 'package:pixels_to_macros/providers/locale_provider.dart';
import 'package:pixels_to_macros/providers/startup_provider.dart';
import 'package:pixels_to_macros/providers/user_prefs_provider.dart';
import 'package:pixels_to_macros/services/database_service.dart';

class _RetryDatabase extends Fake implements Database {
  _RetryDatabase(this.saved);

  final Map<String, Object?> saved;
  var queries = 0;

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
    expect(table, 'user_preferences');
    if (++queries == 1) throw StateError('temporary database failure');
    return [saved];
  }
}

class _InsulinSettings extends InsulinSettingsNotifier {
  @override
  Future<void> load() async {}
}

class _InsulinDoses extends InsulinDoseLogNotifier {
  @override
  Future<void> load({Duration lookback = const Duration(hours: 12)}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup retry reloads saved preferences after a database failure',
      () async {
    SharedPreferences.setMockInitialValues({'app_language_code': 'es'});
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final saved = const UserPreferences().copyWith(
      name: 'Saved user',
      onboardingComplete: true,
      fontScale: 1.2,
      waterIntakeDate: today,
      plateDiameterCm: 24.5,
    );
    final database = _RetryDatabase(saved.toMap());
    final container = ProviderContainer(overrides: [
      userPrefsProvider.overrideWith(
        (ref) => UserPrefsNotifier(
          databaseService: DatabaseService.forTesting(database),
        ),
      ),
      insulinSettingsProvider.overrideWith((ref) => _InsulinSettings()),
      insulinDoseLogProvider.overrideWith((ref) => _InsulinDoses()),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(startupLoadProvider, (_, __) {});
    addTearDown(subscription.close);

    await expectLater(
        container.read(startupLoadProvider.future), throwsStateError);
    container.invalidate(startupLoadProvider);
    await container.read(startupLoadProvider.future);

    expect(database.queries, 2);
    expect(container.read(userPrefsProvider).name, 'Saved user');
    expect(container.read(userPrefsProvider).onboardingComplete, isTrue);
    expect(container.read(userPrefsProvider).fontScale, 1.2);
    expect(container.read(userPrefsProvider).plateDiameterCm, 24.5);
    expect(container.read(localeProvider).code, 'es');
    expect(database.saved, saved.toMap());
  });

  testWidgets('root recovery retries a failed locale provider', (tester) async {
    var attempts = 0;
    final pendingStartup = Completer<void>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localeProvider.overrideWith((ref) {
          if (++attempts == 1) throw StateError('temporary locale failure');
          return LocaleNotifier();
        }),
        startupLoadProvider.overrideWith((ref) => pendingStartup.future),
      ],
      child: const PixelsToMacrosApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Try Again'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Try Again'), findsNothing);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
