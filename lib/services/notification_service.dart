import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/user_preferences.dart';

/// Smart water & food reminder notifications.
///
/// - Water: at most 2 reminders per day, only when intake is >30% behind pace.
/// - Food:  one reminder at 13:00 if calorie intake is >30% behind daily goal.
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

    final now      = DateTime.now();
    const wakeHour = 8;
    const sleepHour = 21;
    const windowH  = sleepHour - wakeHour; // 13 hours

    // ── Water reminders ───────────────────────────────────────────────
    final goalMl    = prefs.dailyWaterGoalMl;
    final intakeMl  = prefs.waterIntakeMl;
    final hoursSinceWake = now.hour - wakeHour;

    if (goalMl > 0 && hoursSinceWake > 0 && now.hour < sleepHour) {
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

    // ── Food reminder at 13:00 ────────────────────────────────────────
    final calorieGoal = prefs.dailyCalorieGoal;
    // Food reminder is always scheduled for 13:00 if user hasn't consumed
    // enough by then. We schedule it here and cancel on app open if met.
    final lunchTime = _today(13);
    if (lunchTime.isAfter(now) && calorieGoal > 0) {
      await _scheduleOnce(
        id: 200,
        title: 'Don\'t forget lunch! 🍽️',
        body: 'Check in on your nutrition — log today\'s meals.',
        scheduledDate: lunchTime,
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

