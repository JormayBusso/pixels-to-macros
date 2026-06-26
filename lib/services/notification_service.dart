import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../core/app_localizations.dart';
import '../models/custom_meal.dart';
import '../models/user_preferences.dart';
import 'database_service.dart';

/// Smart water & meal reminder notifications.
///
/// - Water: at most 2 reminders per day, only when intake is >30% behind pace.
/// - Meals: breakfast ~09:00, lunch ~13:00, dinner ~19:00 — each only fires if
///   that meal has not been logged yet today.
///
/// Wake window assumed 08:00–21:00 (13 hours).
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Notification channel IDs
  static const _waterChannelId   = 'water_reminders';
  static const _waterChannelName = 'Water Reminders';
  static const _foodChannelId    = 'food_reminders';
  static const _foodChannelName  = 'Food Reminders';

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    tz.initializeTimeZones();

    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(iOS: ios);
    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// Schedule daily water + food reminders based on current user state.
  ///
  /// Call this once per app start (and after the user logs water/food).
  Future<void> scheduleReminders({
    required UserPreferences prefs,
  }) async {
    if (!_initialized) await initialize();

    // Cancel previous reminders so we don't accumulate stale ones.
    await _plugin.cancelAll();

    final toggles = await _loadReminderToggles();
    final mealReminderEnabled = toggles.$1;
    final waterReminderEnabled = toggles.$2;

    final now      = DateTime.now();
    const wakeHour = 8;
    const sleepHour = 21;
    const windowH  = sleepHour - wakeHour; // 13 hours

    // ── Water reminders ───────────────────────────────────────────────
    final goalMl    = prefs.dailyWaterGoalMl;
    final intakeMl  = prefs.waterIntakeMl;
    final hoursSinceWake = now.hour - wakeHour;

    if (waterReminderEnabled &&
      goalMl > 0 &&
      hoursSinceWake > 0 &&
      now.hour < sleepHour) {
      final targetByNow = (goalMl * hoursSinceWake / windowH).round();
      final deficit      = targetByNow - intakeMl;
      final pct          = targetByNow > 0 ? deficit / targetByNow : 0.0;

      if (pct > 0.30) {
        // Schedule up to 2 reminders spread across remaining wake hours
        final remainingH = sleepHour - now.hour;
        if (remainingH >= 2) {
          final r1 = _today(now.hour + remainingH ~/ 3);
          final r2 = _today(now.hour + (remainingH * 2) ~/ 3);
          await _scheduleOnce(
            id: 100,
            title: 'Time to hydrate 💧',
            body: 'You\'ve had ${intakeMl}ml — aim for ${goalMl}ml today.',
            scheduledDate: r1,
            channelId: _waterChannelId,
            channelName: _waterChannelName,
          );
          await _scheduleOnce(
            id: 101,
            title: 'Stay hydrated 💧',
            body: 'Keep drinking! Goal: ${goalMl}ml.',
            scheduledDate: r2,
            channelId: _waterChannelId,
            channelName: _waterChannelName,
          );
        }
      }
    }

    // ── Meal reminders ────────────────────────────────────────────────
    // Breakfast (09:00), lunch (13:00), dinner (19:00). Each reminder is only
    // scheduled if its time is still in the future today AND that meal has not
    // already been logged. Reminders are rescheduled on app start, on app
    // resume, and whenever a meal is logged, so already-logged meals get their
    // reminder cancelled.
    await _scheduleMealReminders(now: now, enabled: mealReminderEnabled);
  }

  /// IDs for the breakfast / lunch / dinner reminders.
  static const _mealReminderIds = [200, 201, 202];

  /// Re-evaluate just the meal reminders (without touching water/insight ones).
  ///
  /// Call after a meal is logged so the corresponding reminder is cancelled.
  Future<void> refreshMealReminders() async {
    if (!_initialized) await initialize();
    for (final id in _mealReminderIds) {
      await _plugin.cancel(id);
    }
    final toggles = await _loadReminderToggles();
    await _scheduleMealReminders(now: DateTime.now(), enabled: toggles.$1);
  }

  /// Schedule breakfast/lunch/dinner reminders for meals that are not yet
  /// logged today and whose time is still in the future.
  Future<void> _scheduleMealReminders({
    required DateTime now,
    required bool enabled,
  }) async {
    if (!enabled) return;

    final l10n = await _localizations();
    final logged = await _loggedMealsToday();

    final plan = <(MealType, int, int, String, String)>[
      (
        MealType.breakfast,
        9,
        200,
        l10n.mealReminderBreakfastTitle,
        l10n.mealReminderBreakfastBody,
      ),
      (
        MealType.lunch,
        13,
        201,
        l10n.mealReminderLunchTitle,
        l10n.mealReminderLunchBody,
      ),
      (
        MealType.dinner,
        19,
        202,
        l10n.mealReminderDinnerTitle,
        l10n.mealReminderDinnerBody,
      ),
    ];

    for (final item in plan) {
      final mealType = item.$1;
      final hour = item.$2;
      final id = item.$3;
      final time = _today(hour);
      if (logged.contains(mealType)) continue;
      if (!time.isAfter(now)) continue;
      await _scheduleOnce(
        id: id,
        title: item.$4,
        body: item.$5,
        scheduledDate: time,
        channelId: _foodChannelId,
        channelName: _foodChannelName,
      );
    }
  }

  Future<void> _scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String channelId,
    required String channelName,
  }) async {
    if (scheduledDate.isBefore(DateTime.now())) return;

    final details = const NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: false,
      ),
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
    );
  }

  static DateTime _today(int hour) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, hour.clamp(0, 23));
  }

  Future<(bool, bool)> _loadReminderToggles() async {
    try {
      final db = await DatabaseService.instance.database;
      final rows = await db.query('user_preferences', limit: 1);
      if (rows.isEmpty) return (true, true);
      final row = rows.first;
      final meal = (row['meal_reminder_enabled'] as int? ?? 1) == 1;
      final water = (row['water_reminder_enabled'] as int? ?? 1) == 1;
      return (meal, water);
    } catch (_) {
      return (true, true);
    }
  }

  /// Build localizations from the user's saved language (defaults to English).
  Future<AppLocalizations> _localizations() async {
    var code = 'en';
    try {
      final sp = await SharedPreferences.getInstance();
      code = sp.getString('app_language_code') ?? 'en';
    } catch (_) {}
    return AppLocalizations(Locale(code));
  }

  /// Which meal a timestamp falls into, by hour-of-day window.
  static MealType _mealForHour(int hour) {
    if (hour < 11) return MealType.breakfast;
    if (hour < 16) return MealType.lunch;
    return MealType.dinner;
  }

  /// Set of meals that already have a logged item today.
  ///
  /// Scans carry only a timestamp (no meal type) so they are bucketed by
  /// hour-of-day window. Custom meals carry an explicit meal type.
  Future<Set<MealType>> _loggedMealsToday() async {
    final logged = <MealType>{};
    try {
      final db = await DatabaseService.instance.database;
      final now = DateTime.now();
      final todayStart =
          DateTime(now.year, now.month, now.day).toIso8601String();

      final scanRows = await db.query(
        'scan_results',
        columns: ['timestamp'],
        where: 'timestamp >= ?',
        whereArgs: [todayStart],
      );
      for (final r in scanRows) {
        final dt = DateTime.tryParse(r['timestamp'] as String? ?? '');
        if (dt != null) logged.add(_mealForHour(dt.hour));
      }

      final mealRows = await db.query(
        'custom_meals',
        columns: ['meal_type', 'created_at'],
        where: 'created_at >= ?',
        whereArgs: [todayStart],
      );
      for (final r in mealRows) {
        final mt = r['meal_type'] as String?;
        if (mt != null && mt.isNotEmpty) {
          logged.add(MealType.fromDbValue(mt));
        } else {
          final dt = DateTime.tryParse(r['created_at'] as String? ?? '');
          if (dt != null) logged.add(_mealForHour(dt.hour));
        }
      }
    } catch (_) {}
    return logged;
  }

  // ── Smart Personalized Notification (1/day max) ──────────────────────────

  static const _insightChannelId = 'daily_insight';
  static const _insightChannelName = 'Daily Insight';

  /// Schedule a single personalized insight notification at 9 AM tomorrow.
  ///
  /// Call after scan or at end of day. Only sends 1 notification/day.
  /// [yesterdayCalories] and [yesterdayProteinG] come from the analytics
  /// provider; pass 0 if unknown (notification will be generic).
  Future<void> scheduleSmartInsight({
    required int calorieGoal,
    required int proteinGoal,
    required double yesterdayCalories,
    required double yesterdayProteinG,
    required int currentStreak,
  }) async {
    if (!_initialized) await initialize();

    // Cancel any previous insight notification.
    await _plugin.cancel(300);

    final title = _pickInsightTitle(
      calorieGoal: calorieGoal,
      proteinGoal: proteinGoal,
      yesterdayCalories: yesterdayCalories,
      yesterdayProteinG: yesterdayProteinG,
      currentStreak: currentStreak,
    );
    final body = _pickInsightBody(
      calorieGoal: calorieGoal,
      proteinGoal: proteinGoal,
      yesterdayCalories: yesterdayCalories,
      yesterdayProteinG: yesterdayProteinG,
      currentStreak: currentStreak,
    );

    // Schedule for 9 AM tomorrow.
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final scheduledDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);

    await _scheduleOnce(
      id: 300,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      channelId: _insightChannelId,
      channelName: _insightChannelName,
    );
  }

  String _pickInsightTitle({
    required int calorieGoal,
    required int proteinGoal,
    required double yesterdayCalories,
    required double yesterdayProteinG,
    required int currentStreak,
  }) {
    if (currentStreak >= 7) return '🔥 $currentStreak-day streak!';
    if (yesterdayCalories > 0 && (yesterdayCalories - calorieGoal).abs() < calorieGoal * 0.05) {
      return '🎯 Perfect day yesterday!';
    }
    if (yesterdayProteinG > 0 && yesterdayProteinG < proteinGoal * 0.7) {
      return '💪 Protein tip';
    }
    if (yesterdayCalories > calorieGoal * 1.15) {
      return '📊 Quick check-in';
    }
    return '👋 Good morning!';
  }

  String _pickInsightBody({
    required int calorieGoal,
    required int proteinGoal,
    required double yesterdayCalories,
    required double yesterdayProteinG,
    required int currentStreak,
  }) {
    if (currentStreak >= 7) {
      return 'Keep it up! Scan your first meal to extend your streak.';
    }
    if (yesterdayCalories > 0 && (yesterdayCalories - calorieGoal).abs() < calorieGoal * 0.05) {
      return 'You nailed your ${calorieGoal} kcal goal yesterday. Let\'s repeat today!';
    }
    if (yesterdayProteinG > 0 && yesterdayProteinG < proteinGoal * 0.7) {
      return 'Yesterday you got ${yesterdayProteinG.round()}g protein (goal: ${proteinGoal}g). Try adding eggs or Greek yogurt today.';
    }
    if (yesterdayCalories > calorieGoal * 1.15) {
      return 'Yesterday was ${yesterdayCalories.round()} kcal (${((yesterdayCalories / calorieGoal - 1) * 100).round()}% over). A lighter breakfast can balance things out.';
    }
    return 'Ready to log today\'s meals? Your streak is $currentStreak days.';
  }
}

