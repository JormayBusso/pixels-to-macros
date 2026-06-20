import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/weight_entry.dart';
import '../services/database_service.dart';

class ProgressStoryState {
  const ProgressStoryState({
    this.loading = false,
    this.totalScans = 0,
    this.loggedDays30 = 0,
    this.averageCalories30 = 0,
    this.plannedMealsThisWeek = 0,
    this.availablePantryItems = 0,
    this.weightEntries = const [],
    this.error,
  });

  final bool loading;
  final String? error;
  final int totalScans;
  final int loggedDays30;
  final double averageCalories30;
  final int plannedMealsThisWeek;
  final int availablePantryItems;
  final List<WeightEntry> weightEntries;

  double? get monthlyWeightChangeKg {
    if (weightEntries.length < 2) return null;
    return weightEntries.first.weightKg - weightEntries[1].weightKg;
  }
}

class ProgressStoryNotifier extends StateNotifier<ProgressStoryState> {
  ProgressStoryNotifier() : super(const ProgressStoryState());

  Future<void> load() async {
    state = const ProgressStoryState(loading: true);
    try {
      final db = DatabaseService.instance;
      final scans = await db.getAllScanResults();
      final weights = await db.getWeightHistory();
      final pantryItems = await db.getPantryItems();
      final now = DateTime.now();
      final start30 = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 29));
      final recentScans =
          scans.where((scan) => !scan.timestamp.isBefore(start30));
      final days = <String>{};
      var calories = 0.0;
      for (final scan in recentScans) {
        days.add(
            '${scan.timestamp.year}-${scan.timestamp.month}-${scan.timestamp.day}');
        calories += (scan.totalCaloriesMin + scan.totalCaloriesMax) / 2;
      }

      final week = _isoWeekNumber(now);
      final entries =
          await db.getMealPlanEntries(weekNumber: week, year: now.year);
      state = ProgressStoryState(
        totalScans: scans.length,
        loggedDays30: days.length,
        averageCalories30: days.isEmpty ? 0 : calories / days.length,
        plannedMealsThisWeek: entries.length,
        availablePantryItems:
            pantryItems.where((item) => item.available).length,
        weightEntries: weights,
      );
    } catch (e) {
      state = ProgressStoryState(error: e.toString());
    }
  }
}

int _isoWeekNumber(DateTime date) {
  final startOfYear = DateTime(date.year, 1, 1);
  final firstMonday = startOfYear.weekday <= 4
      ? startOfYear.subtract(Duration(days: startOfYear.weekday - 1))
      : startOfYear.add(Duration(days: 8 - startOfYear.weekday));
  return ((date.difference(firstMonday).inDays) / 7).floor() + 1;
}

final progressStoryProvider =
    StateNotifierProvider<ProgressStoryNotifier, ProgressStoryState>(
  (ref) => ProgressStoryNotifier(),
);
