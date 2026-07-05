import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/food_data.dart';
import '../models/food_group.dart';
import '../services/database_service.dart';

/// Daily (today) and weekly (last 7 days) servings the user logged for each
/// tracked [FoodGroup], derived from scan/manual/voice history.
class FoodGroupBalance {
  const FoodGroupBalance({
    this.dailyServings = const {},
    this.weeklyServings = const {},
    this.loading = false,
  });

  final Map<FoodGroup, double> dailyServings;
  final Map<FoodGroup, double> weeklyServings;
  final bool loading;

  double daily(FoodGroup g) => dailyServings[g] ?? 0;
  double weekly(FoodGroup g) => weeklyServings[g] ?? 0;
}

class FoodGroupNotifier extends StateNotifier<FoodGroupBalance> {
  FoodGroupNotifier() : super(const FoodGroupBalance());

  Future<void> load() async {
    state = const FoodGroupBalance(loading: true);
    final scans = await DatabaseService.instance.getAllScanResults();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(const Duration(days: 6));

    final dailyG = <FoodGroup, double>{};
    final weeklyG = <FoodGroup, double>{};
    final cache = <String, FoodData?>{};

    for (final scan in scans) {
      if (scan.depthMode == 'hydration') continue;
      final day =
          DateTime(scan.timestamp.year, scan.timestamp.month, scan.timestamp.day);
      if (day.isBefore(weekStart)) continue;
      final isToday = !day.isBefore(todayStart);

      for (final food in scan.foods) {
        final fd = await _lookup(food.label, cache);
        if (fd == null || fd.kcalPer100g <= 0) continue;
        final group = foodGroupForCategory(fd.category, food.label);
        if (group == null) continue;
        final avgCal = (food.caloriesMin + food.caloriesMax) / 2;
        final weightG = avgCal / (fd.kcalPer100g / 100);
        weeklyG[group] = (weeklyG[group] ?? 0) + weightG;
        if (isToday) dailyG[group] = (dailyG[group] ?? 0) + weightG;
      }
    }

    Map<FoodGroup, double> toServings(Map<FoodGroup, double> grams) => {
          for (final g in FoodGroup.values)
            g: (grams[g] ?? 0) / kServingGrams[g]!,
        };

    state = FoodGroupBalance(
      dailyServings: toServings(dailyG),
      weeklyServings: toServings(weeklyG),
    );
  }

  Future<FoodData?> _lookup(String label, Map<String, FoodData?> cache) async {
    final key = label.toLowerCase();
    if (cache.containsKey(key)) return cache[key];
    final fd = await DatabaseService.instance.getFoodByLabel(label);
    cache[key] = fd;
    return fd;
  }
}

final foodGroupProvider =
    StateNotifierProvider<FoodGroupNotifier, FoodGroupBalance>(
  (ref) => FoodGroupNotifier(),
);
