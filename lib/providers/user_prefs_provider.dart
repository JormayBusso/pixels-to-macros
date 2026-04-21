import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_preferences.dart';
import '../services/database_service.dart';

/// Provides the user's preferences (name, calorie goal, onboarding status).
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
  }) async {
    final prefs = state.copyWith(
      name: name,
      dailyCalorieGoal: dailyCalorieGoal,
      onboardingComplete: true,
    );
    await update(prefs);
  }

  Future<void> dismissScanTutorial() async {
    final prefs = state.copyWith(hasSeenScanTutorial: true);
    await update(prefs);
  }
}

final userPrefsProvider =
    StateNotifierProvider<UserPrefsNotifier, UserPreferences>(
  (ref) => UserPrefsNotifier(),
);
