import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrient_data.dart';
import '../models/scan_result.dart';
import '../services/app_recovery_service.dart';
import '../services/database_service.dart';
import '../services/debug_log.dart';
import '../services/notification_service.dart';

/// Today's aggregated calorie and macro intake from all scans.
class DailyIntake {
  final bool loading;
  final double caloriesMin;
  final double caloriesMax;
  final int scanCount;
  final List<DetectedFood> foods;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final NutrientTotals nutrientTotals;

  const DailyIntake({
    this.loading = false,
    this.caloriesMin = 0,
    this.caloriesMax = 0,
    this.scanCount = 0,
    this.foods = const [],
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.nutrientTotals = const NutrientTotals(),
  });

  double get caloriesAvg => (caloriesMin + caloriesMax) / 2;
}

class DailyIntakeNotifier extends StateNotifier<DailyIntake> {
  DailyIntakeNotifier({
    DatabaseService? database,
    Future<void> Function()? refreshMealReminders,
  })  : _database = database ?? DatabaseService.instance,
        _refreshMealReminders = refreshMealReminders ??
            NotificationService.instance.refreshMealReminders,
        super(const DailyIntake());

  final DatabaseService _database;
  final Future<void> Function() _refreshMealReminders;

  Future<void> load() async {
    state = const DailyIntake(loading: true);

    try {
      final allScans = await _database.getAllScanResults();
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final todayScans = allScans.where(
        (s) => s.timestamp.isAfter(todayStart),
      );

      double minSum = 0;
      double maxSum = 0;
      double proteinSum = 0;
      double carbsSum = 0;
      double fatSum = 0;
      var nutrientSum = const NutrientTotals();
      final allFoods = <DetectedFood>[];

      for (final scan in todayScans) {
        minSum += scan.totalCaloriesMin;
        maxSum += scan.totalCaloriesMax;
        allFoods.addAll(scan.foods);

        // Estimate macros from food DB lookup
        for (final food in scan.foods) {
          final foodData = await _database.getFoodForNutrition(food);
          if (foodData != null && foodData.kcalPer100g > 0) {
            final avgCal = (food.caloriesMin + food.caloriesMax) / 2;
            final weightG = avgCal / (foodData.kcalPer100g / 100);
            proteinSum += weightG * foodData.proteinPer100g / 100;
            carbsSum += weightG * foodData.carbsPer100g / 100;
            fatSum += weightG * foodData.fatPer100g / 100;
            nutrientSum = nutrientSum +
                nutrientsForFood(
                  food: foodData,
                  weightG: weightG,
                );
          }
        }
      }

      state = DailyIntake(
        caloriesMin: minSum,
        caloriesMax: maxSum,
        scanCount: todayScans.length,
        foods: allFoods,
        proteinG: proteinSum,
        carbsG: carbsSum,
        fatG: fatSum,
        nutrientTotals: nutrientSum,
      );
    } catch (e, st) {
      DebugLog.instance.log('DailyIntake', 'Load failed: $e\n$st');
      state = const DailyIntake();
      AppRecoveryService.recover(e, st, source: 'Daily intake');
    }

    // Re-evaluate meal reminders so a meal that was just logged has its
    // pending reminder cancelled (best-effort, never blocks intake loading).
    unawaited(_refreshMealReminders());
  }
}

final dailyIntakeProvider =
    StateNotifierProvider<DailyIntakeNotifier, DailyIntake>(
  (ref) => DailyIntakeNotifier(),
);
