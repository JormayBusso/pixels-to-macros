import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrition_goal.dart';
import '../models/user_preferences.dart';
import '../services/health_service.dart';
import 'user_prefs_provider.dart';

/// Snapshot of the last Apple Health sync + the adaptive target it produced.
class HealthSyncState {
  const HealthSyncState({
    this.enabled = false,
    this.syncing = false,
    this.lastSyncAt,
    this.latestWeightKg,
    this.todayActiveKcal = 0,
    this.habitualActiveKcal = 0,
    this.activityBonusKcal = 0,
    this.adaptiveTargetKcal = 0,
    this.error,
  });

  final bool enabled;
  final bool syncing;
  final DateTime? lastSyncAt;
  final double? latestWeightKg;
  final double todayActiveKcal;
  final double habitualActiveKcal;
  final int activityBonusKcal;
  final int adaptiveTargetKcal;

  /// Localization key for the last error, or null.
  final String? error;

  bool get hasSynced => lastSyncAt != null;

  HealthSyncState copyWith({
    bool? enabled,
    bool? syncing,
    DateTime? lastSyncAt,
    double? latestWeightKg,
    double? todayActiveKcal,
    double? habitualActiveKcal,
    int? activityBonusKcal,
    int? adaptiveTargetKcal,
    Object? error = _sentinel,
  }) {
    return HealthSyncState(
      enabled: enabled ?? this.enabled,
      syncing: syncing ?? this.syncing,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      latestWeightKg: latestWeightKg ?? this.latestWeightKg,
      todayActiveKcal: todayActiveKcal ?? this.todayActiveKcal,
      habitualActiveKcal: habitualActiveKcal ?? this.habitualActiveKcal,
      activityBonusKcal: activityBonusKcal ?? this.activityBonusKcal,
      adaptiveTargetKcal: adaptiveTargetKcal ?? this.adaptiveTargetKcal,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  static const Object _sentinel = Object();
}

/// Pulls weight + active energy from Apple Health and turns the fixed daily
/// calorie target into an adaptive one:
///
///   target = maintenance(weight, goal) + activityBonus
///
/// where `activityBonus` eats back ~50% of the active energy burned ABOVE the
/// user's habitual level. Using the delta above habitual avoids double-counting
/// the everyday activity already inside the maintenance estimate, and the 50%
/// factor hedges the well-documented ~20–40% overestimate wearables/HealthKit
/// make on active energy. The bonus is never negative (a quiet day simply keeps
/// the base target) and is capped so a single big workout can't blow the day
/// wide open. The result is written to `UserPreferences.dailyCalorieGoal`, so
/// every existing calorie display becomes adaptive with no further wiring.
class HealthSyncNotifier extends StateNotifier<HealthSyncState> {
  HealthSyncNotifier(this.ref) : super(const HealthSyncState());

  final Ref ref;

  /// Fraction of above-habitual active energy added back to the target.
  static const double _eatBackFraction = 0.5;

  /// Ceiling on the daily activity bonus (kcal).
  static const int _maxActivityBonus = 500;

  /// Mirror the persisted enable flag into provider state (call at startup).
  void loadFromPrefs() {
    state = state.copyWith(enabled: ref.read(userPrefsProvider).healthSyncEnabled);
  }

  int _baseGoalFor(UserPreferences prefs, double weightKg) {
    return GoalDefaults.caloriesForProfile(
      prefs.nutritionGoal,
      weightKg: weightKg,
      heightCm: prefs.heightCm,
      muscleMassLevel: prefs.muscleMassLevel,
      male: prefs.gender == UserGender.male,
    );
  }

  /// Turn Apple Health sync on or off. Enabling requests read access and runs a
  /// first sync; disabling restores the clean profile-based target.
  Future<bool> setEnabled(bool value) async {
    if (!HealthService.instance.isSupported) {
      state = state.copyWith(enabled: false, error: 'healthSyncUnavailable');
      return false;
    }
    if (value) {
      final granted = await HealthService.instance.requestAuthorization();
      if (!granted) {
        state = state.copyWith(enabled: false, error: 'healthSyncPermissionDenied');
        await _persistEnabled(false);
        return false;
      }
      state = state.copyWith(enabled: true, error: null);
      await _persistEnabled(true);
      await syncNow();
      return true;
    }

    state = state.copyWith(enabled: false, activityBonusKcal: 0, error: null);
    await _persistEnabled(false);
    // Drop the activity bonus: reset the stored target to the clean base.
    final prefs = ref.read(userPrefsProvider);
    await ref.read(userPrefsProvider.notifier).update(
          prefs.copyWith(dailyCalorieGoal: _baseGoalFor(prefs, prefs.weightKg)),
        );
    return true;
  }

  Future<void> _persistEnabled(bool enabled) async {
    final prefs = ref.read(userPrefsProvider);
    await ref
        .read(userPrefsProvider.notifier)
        .update(prefs.copyWith(healthSyncEnabled: enabled));
  }

  /// Pull the latest Health data and recompute the adaptive daily target.
  /// No-op (and never throws) when sync is disabled or unsupported.
  Future<void> syncNow() async {
    final prefs = ref.read(userPrefsProvider);
    if (!prefs.healthSyncEnabled || !HealthService.instance.isSupported) return;
    if (state.syncing) return;
    state = state.copyWith(syncing: true, error: null);
    try {
      final svc = HealthService.instance;
      final weight = await svc.latestWeightKg();
      final todayActive = await svc.todayActiveEnergyKcal();
      final habitual = await svc.habitualDailyActiveEnergyKcal(days: 7);

      var effectiveWeight = prefs.weightKg;
      if (weight != null && (weight - prefs.weightKg).abs() >= 0.3) {
        effectiveWeight = GoalDefaults.clampWeightKg(weight);
      }

      final base = _baseGoalFor(prefs, effectiveWeight);
      final aboveHabitual = habitual > 0 ? (todayActive - habitual) : 0.0;
      final bonus =
          (aboveHabitual * _eatBackFraction).round().clamp(0, _maxActivityBonus).toInt();
      final target = (base + bonus).clamp(1200, 6000).toInt();

      await ref.read(userPrefsProvider.notifier).update(
            prefs.copyWith(weightKg: effectiveWeight, dailyCalorieGoal: target),
          );

      state = state.copyWith(
        syncing: false,
        lastSyncAt: DateTime.now(),
        latestWeightKg: weight,
        todayActiveKcal: todayActive,
        habitualActiveKcal: habitual,
        activityBonusKcal: bonus,
        adaptiveTargetKcal: target,
        error: null,
      );
    } catch (e) {
      debugPrint('[HealthSync] syncNow failed: $e');
      state = state.copyWith(syncing: false, error: 'healthSyncFailed');
    }
  }
}

final healthSyncProvider =
    StateNotifierProvider<HealthSyncNotifier, HealthSyncState>(
  (ref) => HealthSyncNotifier(ref),
);
