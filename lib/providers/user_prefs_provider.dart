import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrition_goal.dart';
import '../models/user_preferences.dart';
import '../services/database_service.dart';

/// Provides the user's preferences (name, calorie goal, onboarding status, nutrition goal).
class UserPrefsNotifier extends StateNotifier<UserPreferences> {
  UserPrefsNotifier() : super(const UserPreferences());

  Future<void> load() async {
    final prefs = await DatabaseService.instance.getUserPreferences();
    state = prefs;
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
    final prefs = state.copyWith(dailyWaterGoalMl: ml);
    await update(prefs);
  }

  Future<void> addWater(int ml) async {
    final prefs = state.copyWith(waterIntakeMl: state.waterIntakeMl + ml);
    await update(prefs);
  }

  Future<void> resetWaterIntake() async {
    final prefs = state.copyWith(waterIntakeMl: 0);
    await update(prefs);
  }
}

final userPrefsProvider =
    StateNotifierProvider<UserPrefsNotifier, UserPreferences>(
  (ref) => UserPrefsNotifier(),
);

/// Transient flag: when set to true, [MainShell] shows the tour overlay.
/// Reset to false after the tour is dismissed.
final showTourProvider = StateProvider<bool>((ref) => false);
