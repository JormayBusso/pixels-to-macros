import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bolus_audit_record.dart';
import '../models/insulin_dose_log.dart';
import '../models/insulin_settings.dart';
import '../services/database_service.dart';
import '../services/diabetes/diabetes_survey_scheduler.dart';

/// State + persistence for Bolus Calculator Mode insulin settings.
///
/// Keeps the in-memory [InsulinSettings] in sync with the local SQLite store.
/// All mutations go through here so persistence and state never diverge.
class InsulinSettingsNotifier extends StateNotifier<InsulinSettings> {
  InsulinSettingsNotifier() : super(const InsulinSettings());

  Future<void> load() async {
    state = await DatabaseService.instance.getInsulinSettings();
  }

  /// Persist [next] and update state. Stamps [updatedAt]/[createdAt].
  Future<void> _save(InsulinSettings next) async {
    final now = DateTime.now();
    final stamped = next.copyWith(
      createdAt: next.createdAt ?? now,
      updatedAt: now,
    );
    await DatabaseService.instance.saveInsulinSettings(stamped);
    state = stamped;
  }

  // ── General toggles ──────────────────────────────────────────────────────

  Future<void> setDiabetesEnabled(bool enabled) =>
      _save(state.copyWith(diabetesEnabled: enabled));

  Future<void> setUsesInsulin(bool uses) =>
      _save(state.copyWith(usesInsulin: uses));

  /// Enable Bolus Calculator Mode. The caller (consent screen) must already
  /// have collected explicit consent — this also records [userConfirmedAt].
  Future<void> enableBolusCalculatorWithConsent() async {
    final now = DateTime.now();
    await _save(state.copyWith(
      bolusCalculatorEnabled: true,
      userConfirmedAt: now,
    ));
  }

  Future<void> disableBolusCalculator() =>
      _save(state.copyWith(bolusCalculatorEnabled: false));

  // ── Survey completion / review ───────────────────────────────────────────

  /// Save the full survey result and mark the review as completed now (which
  /// also re-records consent and sets the next 90-day due date).
  Future<void> completeSurvey(InsulinSettings surveyed) async {
    final now = DateTime.now();
    final marked = DiabetesSurveyScheduler.markCompleted(surveyed, now);
    await _save(marked);
  }

  /// Re-confirm existing settings during a 90-day review (no field changes).
  Future<void> markReviewed() async {
    final now = DateTime.now();
    await _save(DiabetesSurveyScheduler.markCompleted(state, now));
  }

  Future<void> snooze(Duration duration) async {
    final now = DateTime.now();
    await _save(DiabetesSurveyScheduler.snooze(state, duration, now));
  }
}

final insulinSettingsProvider =
    StateNotifierProvider<InsulinSettingsNotifier, InsulinSettings>(
  (ref) => InsulinSettingsNotifier(),
);

/// Whether the review reminder banner should be shown right now.
final diabetesReviewReminderProvider = Provider<bool>((ref) {
  final s = ref.watch(insulinSettingsProvider);
  if (!s.bolusCalculatorEnabled) return false;
  return DiabetesSurveyScheduler.shouldShowReminder(s, DateTime.now());
});

/// Whether the bolus calculator is currently available (enabled + reviewed).
final bolusCalculatorAvailableProvider = Provider<bool>((ref) {
  final s = ref.watch(insulinSettingsProvider);
  if (!s.bolusCalculatorEnabled) return false;
  if (s.surveyLastCompletedAt == null) return false;
  if (s.userConfirmedAt == null) return false;
  return DiabetesSurveyScheduler.allowsCalculation(s, DateTime.now());
});

/// Confirmed insulin dose logs from the recent past (for IOB + history).
class InsulinDoseLogNotifier extends StateNotifier<List<InsulinDoseLog>> {
  InsulinDoseLogNotifier() : super(const []);

  /// Load confirmed doses from the last [lookback] (defaults to 12h, which
  /// safely covers any rapid-acting insulin action duration).
  Future<void> load({Duration lookback = const Duration(hours: 12)}) async {
    final since = DateTime.now().subtract(lookback);
    state = await DatabaseService.instance.getRecentInsulinDoses(since);
  }

  /// Persist a user-confirmed dose, then reload. The UI guarantees [dose]
  /// carries an explicit confirmation.
  Future<void> addConfirmedDose(InsulinDoseLog dose) async {
    await DatabaseService.instance.insertInsulinDose(dose);
    if (dose.calculationId != null) {
      await DatabaseService.instance.updateBolusAuditActualDose(
        calculationId: dose.calculationId!,
        actualDoseUnits: dose.units,
        actualDoseTimestamp: dose.timestamp,
      );
    }
    await load();
  }
}

final insulinDoseLogProvider =
    StateNotifierProvider<InsulinDoseLogNotifier, List<InsulinDoseLog>>(
  (ref) => InsulinDoseLogNotifier(),
);

/// Records a calculation in the audit log.
final bolusAuditProvider = Provider<Future<void> Function(BolusAuditRecord)>(
  (ref) => (record) => DatabaseService.instance.insertBolusAudit(record),
);
