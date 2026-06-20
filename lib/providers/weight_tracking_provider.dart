import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrition_goal.dart';
import '../models/user_preferences.dart';
import '../models/weight_entry.dart';
import '../services/database_service.dart';
import 'user_prefs_provider.dart';

class WeightTrackingState {
  const WeightTrackingState({
    this.entries = const [],
    this.loading = false,
    this.lastCalibration,
  });

  final List<WeightEntry> entries;
  final bool loading;
  final CalorieCalibrationResult? lastCalibration;

  WeightEntry? get latest => entries.isEmpty ? null : entries.first;
  bool get hasEnoughForTrend => entries.length >= 2;
}

class WeightTrackingNotifier extends StateNotifier<WeightTrackingState> {
  WeightTrackingNotifier(this.ref) : super(const WeightTrackingState());

  final Ref ref;

  Future<void> load() async {
    state = WeightTrackingState(
      loading: true,
      entries: state.entries,
      lastCalibration: state.lastCalibration,
    );
    final entries = await DatabaseService.instance.getWeightHistory();
    state = WeightTrackingState(
      entries: entries,
      lastCalibration: state.lastCalibration,
    );
  }

  Future<CalorieCalibrationResult> logMonthlyWeight(double weightKg) async {
    final prefs = ref.read(userPrefsProvider);
    final snappedWeight = GoalDefaults.snapWeightKg(weightKg);
    final entry = WeightEntry(
      recordedAt: DateTime.now(),
      weightKg: snappedWeight,
    );
    await DatabaseService.instance.upsertMonthlyWeight(entry);
    final entries = await DatabaseService.instance.getWeightHistory();
    final result = _calibrate(entries, prefs.copyWith(weightKg: snappedWeight));
    await ref.read(userPrefsProvider.notifier).update(
          prefs.copyWith(
            weightKg: snappedWeight,
            dailyCalorieGoal: result.recommendedCalories,
          ),
        );
    state = WeightTrackingState(
      entries: entries,
      lastCalibration: result,
    );
    return result;
  }

  Future<void> deleteEntry(WeightEntry entry) async {
    if (entry.id == null) return;
    await DatabaseService.instance.deleteWeightEntry(entry.id!);
    await load();
  }

  CalorieCalibrationResult _calibrate(
    List<WeightEntry> entries,
    UserPreferences prefs,
  ) {
    final baselineCalories = GoalDefaults.caloriesForProfile(
      prefs.nutritionGoal,
      weightKg: prefs.weightKg,
      heightCm: prefs.heightCm,
      muscleMassLevel: prefs.muscleMassLevel,
      male: prefs.gender == UserGender.male,
    );
    if (entries.length < 2) {
      return CalorieCalibrationResult(
        recommendedCalories: baselineCalories,
        deltaCalories: baselineCalories - prefs.dailyCalorieGoal,
        messageKey: 'firstMonthlyWeightSaved',
      );
    }

    final latest = entries[0];
    final previous = entries[1];
    final days = latest.recordedAt.difference(previous.recordedAt).inDays.abs();
    final monthFactor = days <= 0 ? 1.0 : 30 / days;
    final monthlyChangeKg = (latest.weightKg - previous.weightKg) * monthFactor;
    final monthlyChangePct = previous.weightKg <= 0
        ? 0.0
        : monthlyChangeKg / previous.weightKg * 100.0;

    var adjustment = 0;
    var messageKey = 'weightTrendAligned';
    switch (prefs.nutritionGoal) {
      case NutritionGoalType.weightLoss:
        if (monthlyChangePct > -0.4) {
          adjustment = -100;
          messageKey = 'weightLossSlow';
        } else if (monthlyChangePct < -3.0) {
          adjustment = 100;
          messageKey = 'weightLossFast';
        }
        break;
      case NutritionGoalType.muscleGrowth:
        if (monthlyChangePct < 0.4) {
          adjustment = 120;
          messageKey = 'weightGainSlow';
        } else if (monthlyChangePct > 2.5) {
          adjustment = -100;
          messageKey = 'weightGainFast';
        }
        break;
      case NutritionGoalType.maintain:
      case NutritionGoalType.diabetes:
      case NutritionGoalType.vegan:
      case NutritionGoalType.vegetarian:
      case NutritionGoalType.pescatarian:
      case NutritionGoalType.mediterranean:
      case NutritionGoalType.keto:
        if (monthlyChangePct > 1.5) {
          adjustment = -100;
          messageKey = 'weightTrendingUp';
        } else if (monthlyChangePct < -1.5) {
          adjustment = 100;
          messageKey = 'weightTrendingDown';
        }
        break;
    }

    final recommended = (baselineCalories + adjustment).clamp(1000, 5000);
    return CalorieCalibrationResult(
      recommendedCalories: recommended,
      deltaCalories: recommended - prefs.dailyCalorieGoal,
      messageKey: messageKey,
    );
  }
}

final weightTrackingProvider =
    StateNotifierProvider<WeightTrackingNotifier, WeightTrackingState>(
  (ref) => WeightTrackingNotifier(ref),
);
