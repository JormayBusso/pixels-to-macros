import '../../core/diabetes/diabetes_constants.dart';
import '../../models/insulin_settings.dart';

/// Status of the 90-day insulin-settings review.
enum ReviewStatus {
  /// No survey completed yet.
  neverCompleted,

  /// Reviewed within the interval — calculator allowed.
  current,

  /// Reminder is currently snoozed (still within snooze window).
  snoozed,

  /// Past due — calculator must be disabled until reviewed.
  overdue,
}

/// Pure scheduling logic for the periodic insulin-settings safety review.
///
/// All methods take an explicit [now] so they are deterministic and testable.
class DiabetesSurveyScheduler {
  DiabetesSurveyScheduler._();

  /// Compute the next-due timestamp from the last-completed timestamp.
  static DateTime nextDue(DateTime lastCompleted) =>
      lastCompleted.add(DiabetesConstants.reviewInterval);

  /// True if the survey is due (or overdue) at [now].
  static bool isDue(InsulinSettings s, DateTime now) {
    final next = s.surveyNextDueAt;
    if (next == null) return true; // never completed
    return !now.isBefore(next); // now >= next
  }

  /// True if a reminder is currently snoozed at [now].
  static bool isSnoozed(InsulinSettings s, DateTime now) {
    final until = s.surveySnoozedUntil;
    return until != null && now.isBefore(until);
  }

  /// Overall review status used to gate the calculator and show banners.
  static ReviewStatus statusAt(InsulinSettings s, DateTime now) {
    if (s.surveyLastCompletedAt == null) return ReviewStatus.neverCompleted;
    if (!isDue(s, now)) return ReviewStatus.current;
    // Due or overdue:
    if (isSnoozed(s, now)) return ReviewStatus.snoozed;
    return ReviewStatus.overdue;
  }

  /// Whether the review state permits running the bolus calculator.
  ///
  /// Snoozing only postpones the *reminder*, not the safety gate: once the
  /// review interval has elapsed the calculator is disabled regardless of
  /// snooze. (Snooze affects whether we nag, not whether we allow dosing.)
  static bool allowsCalculation(InsulinSettings s, DateTime now) {
    return statusAt(s, now) == ReviewStatus.current;
  }

  /// Whether the reminder banner should be shown at [now].
  static bool shouldShowReminder(InsulinSettings s, DateTime now) {
    final status = statusAt(s, now);
    if (status == ReviewStatus.current) return false;
    if (status == ReviewStatus.snoozed) return false;
    return true; // neverCompleted or overdue
  }

  /// Apply a "completed now" review, returning updated settings with the next
  /// due date set and any snooze cleared.
  static InsulinSettings markCompleted(InsulinSettings s, DateTime now) {
    return s.copyWith(
      surveyLastCompletedAt: now,
      surveyNextDueAt: nextDue(now),
      userConfirmedAt: now,
      updatedAt: now,
      clearSnooze: true,
    );
  }

  /// Apply a snooze of [duration] from [now].
  static InsulinSettings snooze(
    InsulinSettings s,
    Duration duration,
    DateTime now,
  ) {
    return s.copyWith(
      surveySnoozedUntil: now.add(duration),
      updatedAt: now,
    );
  }
}
