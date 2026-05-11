import 'package:flutter/material.dart';

import '../models/food_data.dart';
import '../models/nutrient_data.dart';
import '../models/nutrition_goal.dart';
import '../models/scan_result.dart';
import '../models/user_preferences.dart';
import 'database_service.dart';

class WeeklyBadge {
  const WeeklyBadge({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.metric,
    required this.icon,
    required this.color,
  });

  final String id;
  final String title;
  final String subtitle;
  final String metric;
  final IconData icon;
  final Color color;
}

class WeeklyBadgeRecap {
  const WeeklyBadgeRecap({
    required this.currentWeekKey,
    required this.previousWeekStart,
    required this.previousWeekEnd,
    required this.badges,
  });

  final String currentWeekKey;
  final DateTime previousWeekStart;
  final DateTime previousWeekEnd;
  final List<WeeklyBadge> badges;
}

class WeeklyBadgeService {
  WeeklyBadgeService._();
  static final WeeklyBadgeService instance = WeeklyBadgeService._();

  Future<WeeklyBadgeRecap> buildPreviousWeekRecap({
    required UserPreferences prefs,
  }) async {
    final now = DateTime.now();
    final currentWeekStart = _weekStart(now);
    final previousWeekStart =
        currentWeekStart.subtract(const Duration(days: 7));
    final previousWeekEnd = currentWeekStart.subtract(const Duration(days: 1));
    final scans = await DatabaseService.instance.getAllScanResults();
    final weekScans = scans.where((scan) {
      final day = DateTime(
        scan.timestamp.year,
        scan.timestamp.month,
        scan.timestamp.day,
      );
      return !day.isBefore(previousWeekStart) && day.isBefore(currentWeekStart);
    }).toList();

    if (weekScans.isEmpty) {
      return WeeklyBadgeRecap(
        currentWeekKey: _dateKey(currentWeekStart),
        previousWeekStart: previousWeekStart,
        previousWeekEnd: previousWeekEnd,
        badges: const [],
      );
    }

    final foodScans = weekScans
        .where((scan) => scan.depthMode != 'hydration' && scan.foods.isNotEmpty)
        .toList();
    final hydrationScans =
        weekScans.where((scan) => scan.depthMode == 'hydration').toList();
    final loggedDays = <int>{};
    final hydrationDays = <int>{};
    final proteinByDay = List<double>.filled(7, 0);
    final calorieByDay = List<double>.filled(7, 0);
    final nutrientsByDay = List<NutrientTotals>.filled(
      7,
      const NutrientTotals(),
    );
    final foodCache = <String, FoodData?>{};

    for (final scan in hydrationScans) {
      hydrationDays.add(_dayIndex(scan.timestamp, previousWeekStart));
    }

    for (final scan in foodScans) {
      final index = _dayIndex(scan.timestamp, previousWeekStart);
      loggedDays.add(index);
      calorieByDay[index] += scan.totalCaloriesMin +
          ((scan.totalCaloriesMax - scan.totalCaloriesMin) / 2);

      for (final food in scan.foods) {
        final foodData = await _foodFor(food, foodCache);
        if (foodData == null) continue;
        final weightG = _estimatedWeight(food, foodData);
        proteinByDay[index] += weightG * foodData.proteinPer100g / 100;
        nutrientsByDay[index] = nutrientsByDay[index] +
            nutrientsForFood(
              food: foodData,
              weightG: weightG,
            );
      }
    }

    final longestRun = _longestConsecutiveRun(loggedDays);
    final proteinDays = proteinByDay
        .where((grams) => grams >= prefs.dailyProteinTargetG * 0.75)
        .length;
    final balancedDays = List.generate(7, (index) {
      final logged = loggedDays.contains(index);
      final calories = calorieByDay[index];
      final protein = proteinByDay[index];
      return logged &&
          calories >= prefs.dailyCalorieGoal * 0.65 &&
          calories <= prefs.dailyCalorieGoal * 1.20 &&
          protein >= prefs.dailyProteinTargetG * 0.55;
    }).where((ok) => ok).length;
    final micronutrientDays = nutrientsByDay
        .where((totals) => _reachedNutrientCount(totals, prefs.gender, prefs.nutritionGoal) >= 8)
        .length;

    final badges = <WeeklyBadge>[];
    if (loggedDays.length == 7) {
      badges.add(
        const WeeklyBadge(
          id: 'perfect_log_week',
          title: 'Perfect Log Week',
          subtitle: 'You logged food every day last week.',
          metric: '7 / 7 days',
          icon: Icons.verified_outlined,
          color: Color(0xFF2E7D32),
        ),
      );
    } else if (loggedDays.length >= 5) {
      badges.add(
        WeeklyBadge(
          id: 'steady_tracker',
          title: 'Steady Tracker',
          subtitle: 'You kept nutrition tracking consistent.',
          metric: '${loggedDays.length} days logged',
          icon: Icons.event_available_outlined,
          color: const Color(0xFF00897B),
        ),
      );
    }

    if (longestRun >= 3) {
      badges.add(
        WeeklyBadge(
          id: 'streak_builder',
          title: 'Streak Builder',
          subtitle: 'Your logging rhythm held for consecutive days.',
          metric: '$longestRun-day run',
          icon: Icons.local_fire_department_outlined,
          color: const Color(0xFFEF6C00),
        ),
      );
    }

    if (foodScans.length >= 10) {
      badges.add(
        WeeklyBadge(
          id: 'scanner_momentum',
          title: 'Scanner Momentum',
          subtitle: 'You used the app often enough to build a useful record.',
          metric: '${foodScans.length} food logs',
          icon: Icons.camera_alt_outlined,
          color: const Color(0xFF1565C0),
        ),
      );
    }

    if (proteinDays >= 4) {
      badges.add(
        WeeklyBadge(
          id: 'protein_focus',
          title: 'Protein Focus',
          subtitle: 'You stayed close to your protein target most of the week.',
          metric: '$proteinDays target days',
          icon: Icons.fitness_center_outlined,
          color: const Color(0xFF6A1B9A),
        ),
      );
    }

    if (balancedDays >= 3) {
      badges.add(
        WeeklyBadge(
          id: 'balanced_plate',
          title: 'Balanced Plate',
          subtitle:
              'Your calorie and protein pattern stayed in a healthy range.',
          metric: '$balancedDays balanced days',
          icon: Icons.donut_large_outlined,
          color: const Color(0xFF455A64),
        ),
      );
    }

    if (micronutrientDays >= 3) {
      badges.add(
        WeeklyBadge(
          id: 'micronutrient_pro',
          title: 'Micronutrient Pro',
          subtitle: 'You reached broad vitamin and mineral coverage.',
          metric: '$micronutrientDays rich days',
          icon: Icons.spa_outlined,
          color: const Color(0xFF558B2F),
        ),
      );
    }

    if (hydrationDays.length >= 4) {
      badges.add(
        WeeklyBadge(
          id: 'hydration_rhythm',
          title: 'Hydration Rhythm',
          subtitle: 'You logged drinks across the week.',
          metric: '${hydrationDays.length} hydration days',
          icon: Icons.water_drop_outlined,
          color: const Color(0xFF0277BD),
        ),
      );
    }

    return WeeklyBadgeRecap(
      currentWeekKey: _dateKey(currentWeekStart),
      previousWeekStart: previousWeekStart,
      previousWeekEnd: previousWeekEnd,
      badges: badges,
    );
  }

  Future<FoodData?> _foodFor(
    DetectedFood food,
    Map<String, FoodData?> cache,
  ) async {
    final label = _normaliseLabel(food.label);
    if (cache.containsKey(label)) return cache[label];
    final foodData = await DatabaseService.instance.getFoodByLabel(label);
    cache[label] = foodData;
    return foodData;
  }

  static String _normaliseLabel(String label) {
    const aliases = {'chicken duck': 'chicken'};
    final lower = label.toLowerCase();
    return aliases[lower] ?? label;
  }

  static double _estimatedWeight(DetectedFood food, FoodData foodData) {
    final calories = (food.caloriesMin + food.caloriesMax) / 2;
    if (foodData.kcalPer100g > 0 && calories > 0) {
      return calories / (foodData.kcalPer100g / 100);
    }
    return food.volumeCm3 * ((foodData.densityMin + foodData.densityMax) / 2);
  }

  static int _reachedNutrientCount(
    NutrientTotals totals,
    UserGender gender,
    NutritionGoalType goal,
  ) {
    final isMale = gender == UserGender.male || gender == UserGender.preferNotToSay;
    final drv = NutrientDRV.forContext(isMale: isMale, goal: goal);
    final targets = [
      totals.fiberG      / drv.fiberG,
      totals.vitaminAUg  / drv.vitaminAUg,
      totals.vitaminCMg  / drv.vitaminCMg,
      totals.vitaminDUg  / drv.vitaminDUg,
      totals.vitaminEMg  / drv.vitaminEMg,
      totals.vitaminKUg  / drv.vitaminKUg,
      totals.folateMcg   / drv.folateMcg,
      totals.b12Mcg      / drv.b12Mcg,
      totals.calciumMg   / drv.calciumMg,
      totals.ironMg      / drv.ironMg,
      totals.magnesiumMg / drv.magnesiumMg,
      totals.potassiumMg / drv.potassiumMg,
      totals.zincMg      / drv.zincMg,
    ];
    return targets.where((ratio) => ratio >= 1).length;
  }

  static int _longestConsecutiveRun(Set<int> days) {
    var longest = 0;
    var current = 0;
    for (var day = 0; day < 7; day++) {
      if (days.contains(day)) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 0;
      }
    }
    return longest;
  }

  static int _dayIndex(DateTime date, DateTime weekStart) {
    final day = DateTime(date.year, date.month, date.day);
    return day.difference(weekStart).inDays.clamp(0, 6).toInt();
  }

  static DateTime _weekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static String _dateKey(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}
