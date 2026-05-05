import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────── Streak Freeze ───────────────────────

/// Users get 2 streak freezes per week (resets Monday).
/// A freeze auto-activates when you miss a day, preserving your streak.
class StreakFreezeState {
  const StreakFreezeState({this.remaining = 2, this.lastResetWeek = ''});
  final int remaining;
  final String lastResetWeek;

  StreakFreezeState copyWith({int? remaining, String? lastResetWeek}) =>
      StreakFreezeState(
        remaining: remaining ?? this.remaining,
        lastResetWeek: lastResetWeek ?? this.lastResetWeek,
      );
}

class StreakFreezeNotifier extends StateNotifier<StreakFreezeState> {
  StreakFreezeNotifier() : super(const StreakFreezeState()) {
    _load();
  }

  static const _kRemaining = 'streak_freeze_remaining';
  static const _kWeek = 'streak_freeze_week';
  static const maxFreezes = 2;

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final week = _currentWeekKey();
    final storedWeek = sp.getString(_kWeek) ?? '';
    if (storedWeek != week) {
      // New week → reset freezes.
      await sp.setInt(_kRemaining, maxFreezes);
      await sp.setString(_kWeek, week);
      state = StreakFreezeState(remaining: maxFreezes, lastResetWeek: week);
    } else {
      state = StreakFreezeState(
        remaining: sp.getInt(_kRemaining) ?? maxFreezes,
        lastResetWeek: storedWeek,
      );
    }
  }

  /// Consume one freeze. Returns true if successful.
  Future<bool> useFreeze() async {
    if (state.remaining <= 0) return false;
    final sp = await SharedPreferences.getInstance();
    final newRemaining = state.remaining - 1;
    await sp.setInt(_kRemaining, newRemaining);
    state = state.copyWith(remaining: newRemaining);
    return true;
  }

  String _currentWeekKey() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }
}

final streakFreezeProvider =
    StateNotifierProvider<StreakFreezeNotifier, StreakFreezeState>(
  (_) => StreakFreezeNotifier(),
);

// ─────────────────────── Weekly Challenges ───────────────────────

enum ChallengeType {
  scanStreak3,
  hitGoal5Days,
  logProtein80,
  drinkWater7Days,
  scan10Foods,
  noSugarSpike,
}

class Challenge {
  const Challenge({
    required this.type,
    required this.title,
    required this.description,
    required this.target,
    required this.icon,
  });

  final ChallengeType type;
  final String title;
  final String description;
  final int target;
  final String icon;

  static const all = [
    Challenge(
      type: ChallengeType.scanStreak3,
      title: '3-Day Scan Streak',
      description: 'Scan at least one meal for 3 consecutive days',
      target: 3,
      icon: '🔥',
    ),
    Challenge(
      type: ChallengeType.hitGoal5Days,
      title: 'On Target',
      description: 'Stay within 10% of your calorie goal for 5 days',
      target: 5,
      icon: '🎯',
    ),
    Challenge(
      type: ChallengeType.logProtein80,
      title: 'Protein Power',
      description: 'Log at least 80g protein for 4 days',
      target: 4,
      icon: '💪',
    ),
    Challenge(
      type: ChallengeType.drinkWater7Days,
      title: 'Hydration Hero',
      description: 'Hit your water goal every day this week',
      target: 7,
      icon: '💧',
    ),
    Challenge(
      type: ChallengeType.scan10Foods,
      title: 'Food Explorer',
      description: 'Scan 10 different foods this week',
      target: 10,
      icon: '🔍',
    ),
    Challenge(
      type: ChallengeType.noSugarSpike,
      title: 'Steady Sugar',
      description: 'Keep all meals under GL 20 for 3 days',
      target: 3,
      icon: '🧊',
    ),
  ];
}

class WeeklyChallengeState {
  const WeeklyChallengeState({
    this.activeChallenges = const [],
    this.progress = const {},
    this.weekKey = '',
  });
  final List<Challenge> activeChallenges;
  final Map<ChallengeType, int> progress;
  final String weekKey;

  bool isCompleted(ChallengeType type) =>
      (progress[type] ?? 0) >=
      (activeChallenges
          .cast<Challenge?>()
          .firstWhere((c) => c?.type == type, orElse: () => null)
          ?.target ?? 999);

  int completedCount() =>
      activeChallenges.where((c) => isCompleted(c.type)).length;
}

class WeeklyChallengeNotifier extends StateNotifier<WeeklyChallengeState> {
  WeeklyChallengeNotifier() : super(const WeeklyChallengeState()) {
    _load();
  }

  static const _kWeek = 'challenge_week';
  static const _kChallenges = 'challenge_types';
  static const _kProgress = 'challenge_progress';

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final week = _currentWeekKey();
    final storedWeek = sp.getString(_kWeek) ?? '';

    if (storedWeek != week) {
      // New week → pick 3 random challenges.
      final rng = Random(week.hashCode);
      final shuffled = List<Challenge>.from(Challenge.all)..shuffle(rng);
      final picked = shuffled.take(3).toList();
      final typeKeys = picked.map((c) => c.type.index.toString()).join(',');
      await sp.setString(_kWeek, week);
      await sp.setString(_kChallenges, typeKeys);
      await sp.setString(_kProgress, '');
      state = WeeklyChallengeState(
        activeChallenges: picked,
        progress: {},
        weekKey: week,
      );
    } else {
      final typeKeys = (sp.getString(_kChallenges) ?? '')
          .split(',')
          .where((s) => s.isNotEmpty)
          .map(int.parse)
          .toList();
      final challenges = typeKeys
          .map((i) => Challenge.all.firstWhere((c) => c.type.index == i))
          .toList();
      final progressRaw = sp.getString(_kProgress) ?? '';
      final progress = <ChallengeType, int>{};
      if (progressRaw.isNotEmpty) {
        for (final entry in progressRaw.split(';')) {
          final parts = entry.split(':');
          if (parts.length == 2) {
            final idx = int.tryParse(parts[0]);
            final val = int.tryParse(parts[1]);
            if (idx != null && val != null && idx < ChallengeType.values.length) {
              progress[ChallengeType.values[idx]] = val;
            }
          }
        }
      }
      state = WeeklyChallengeState(
        activeChallenges: challenges,
        progress: progress,
        weekKey: week,
      );
    }
  }

  Future<void> incrementProgress(ChallengeType type, {int by = 1}) async {
    final newProgress = Map<ChallengeType, int>.from(state.progress);
    newProgress[type] = (newProgress[type] ?? 0) + by;
    state = WeeklyChallengeState(
      activeChallenges: state.activeChallenges,
      progress: newProgress,
      weekKey: state.weekKey,
    );
    await _saveProgress(newProgress);
  }

  Future<void> _saveProgress(Map<ChallengeType, int> progress) async {
    final sp = await SharedPreferences.getInstance();
    final encoded = progress.entries
        .map((e) => '${e.key.index}:${e.value}')
        .join(';');
    await sp.setString(_kProgress, encoded);
  }

  String _currentWeekKey() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }
}

final weeklyChallengeProvider =
    StateNotifierProvider<WeeklyChallengeNotifier, WeeklyChallengeState>(
  (_) => WeeklyChallengeNotifier(),
);
