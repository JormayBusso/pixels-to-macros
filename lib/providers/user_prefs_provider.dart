import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrition_goal.dart';
import '../models/user_preferences.dart';
import '../services/database_service.dart';

/// Provides the user's preferences (name, calorie goal, onboarding status, nutrition goal).
class UserPrefsNotifier extends StateNotifier<UserPreferences> {
  UserPrefsNotifier() : super(const UserPreferences());

  Future<void> load() async {
    final prefs = await DatabaseService.instance.getUserPreferences();
    state = await _normaliseDailyHydration(prefs);
  }

  Future<void> update(UserPreferences prefs) async {
    await DatabaseService.instance.saveUserPreferences(prefs);
    state = prefs;
  }

  Future<void> completeOnboarding({
    required String name,
    required int dailyCalorieGoal,
    required NutritionGoalType nutritionGoal,
    required int dailyCarbLimitG,
    required int dailyProteinTargetG,
    required int dailyFatTargetG,
    UserGender gender = UserGender.preferNotToSay,
  }) async {
    final prefs = state.copyWith(
      name: name,
      dailyCalorieGoal: dailyCalorieGoal,
      onboardingComplete: true,
      nutritionGoal: nutritionGoal,
      dailyCarbLimitG: dailyCarbLimitG,
      dailyProteinTargetG: dailyProteinTargetG,
      dailyFatTargetG: dailyFatTargetG,
      gender: gender,
    );
    await update(prefs);
  }

  Future<void> setGoal({
    required NutritionGoalType nutritionGoal,
    required int dailyCalorieGoal,
    required int dailyCarbLimitG,
    required int dailyProteinTargetG,
    required int dailyFatTargetG,
  }) async {
    final prefs = state.copyWith(
      nutritionGoal: nutritionGoal,
      dailyCalorieGoal: dailyCalorieGoal,
      dailyCarbLimitG: dailyCarbLimitG,
      dailyProteinTargetG: dailyProteinTargetG,
      dailyFatTargetG: dailyFatTargetG,
    );
    await update(prefs);
  }

  Future<void> dismissScanTutorial() async {
    final prefs = state.copyWith(hasSeenScanTutorial: true);
    await update(prefs);
  }

  Future<void> dismissAppTutorial() async {
    final prefs = state.copyWith(hasSeenAppTutorial: true);
    await update(prefs);
  }

  /// Resets the tutorial flag so it shows again on next launch.
  Future<void> replayAppTutorial() async {
    final prefs = state.copyWith(hasSeenAppTutorial: false);
    await update(prefs);
  }

  Future<void> setGender(UserGender gender) async {
    final prefs = state.copyWith(gender: gender);
    await update(prefs);
  }

  Future<void> setFontScale(double scale) async {
    final prefs = state.copyWith(fontScale: scale);
    await update(prefs);
  }

  Future<void> setIcr(double icrGramsPerUnit) async {
    final prefs = state.copyWith(icrGramsPerUnit: icrGramsPerUnit);
    await update(prefs);
  }

  Future<void> setVacationMode(bool enabled) async {
    final prefs = state.copyWith(vacationMode: enabled);
    await update(prefs);
  }

  Future<void> setDailyWaterGoal(int ml) async {
    final current = await _normaliseDailyHydration(state);
    final prefs = current.copyWith(dailyWaterGoalMl: ml);
    await update(prefs);
  }

  Future<void> addWater(int ml) async {
    await changeWater(ml);
  }

  Future<void> removeWater(int ml) async {
    await changeWater(-ml);
  }

  Future<void> changeWater(int deltaMl) async {
    final current = await _normaliseDailyHydration(state);
    final nextMl = (current.waterIntakeMl + deltaMl).clamp(0, 20000).toInt();
    final prefs = current.copyWith(
      waterIntakeMl: nextMl,
      waterIntakeDate: _todayKey(),
    );
    await update(prefs);
  }

  Future<void> resetWaterIntake() async {
    final prefs = state.copyWith(
      waterIntakeMl: 0,
      waterIntakeDate: _todayKey(),
    );
    await update(prefs);
  }

  Future<void> markHistorySeen(int newestScanId) async {
    if (newestScanId <= state.lastSeenHistoryScanId) return;
    final prefs = state.copyWith(lastSeenHistoryScanId: newestScanId);
    await update(prefs);
  }

  Future<void> setWeeklyBadgeRecapEnabled(bool enabled) async {
    final prefs = state.copyWith(weeklyBadgeRecapEnabled: enabled);
    await update(prefs);
  }

  Future<void> markWeeklyBadgeRecapSeen(String weekKey) async {
    if (weekKey == state.lastWeeklyBadgeRecapWeek) return;
    final prefs = state.copyWith(lastWeeklyBadgeRecapWeek: weekKey);
    await update(prefs);
  }

  Future<UserPreferences> _normaliseDailyHydration(
    UserPreferences prefs,
  ) async {
    final today = _todayKey();
    if (prefs.waterIntakeDate == today) return prefs;

    final reset = prefs.copyWith(waterIntakeMl: 0, waterIntakeDate: today);
    await DatabaseService.instance.saveUserPreferences(reset);
    return reset;
  }

  static String _todayKey() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }
}

final userPrefsProvider =
    StateNotifierProvider<UserPrefsNotifier, UserPreferences>(
  (ref) => UserPrefsNotifier(),
);

/// Transient flag: when set to true, [MainShell] shows the tour overlay.
/// Reset to false after the tour is dismissed.
final showTourProvider = StateProvider<bool>((ref) => false);
