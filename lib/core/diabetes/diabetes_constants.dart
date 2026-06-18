/// Safety-critical constants for the Bolus Calculator Mode.
///
/// ⚠️ MEDICAL-DEVICE WARNING ⚠️
/// This feature performs insulin-dose calculations from user-provided settings.
/// Depending on jurisdiction it may be regulated as medical-device software
/// (e.g. EU MDR, US FDA). It MUST NOT be shipped to real users until it has
/// undergone clinical validation by a licensed diabetes clinician, formal risk
/// management (e.g. ISO 14971), and regulatory/legal review.
///
/// TODO(clinical-review): Every numeric bound below is a conservative
/// engineering default and MUST be reviewed and signed off by a licensed
/// diabetes clinician before any production release.
/// TODO(regulatory-review): Confirm whether this feature is classified as a
/// medical device in each target market and complete the required process.
library;

/// Central place for all bolus-calculator safety numbers. No other file should
/// hard-code these values (avoid magic numbers).
class DiabetesConstants {
  DiabetesConstants._();

  // ── Schema / audit ────────────────────────────────────────────────────────

  /// Bumped whenever the meaning of a stored insulin setting changes. Recorded
  /// on every audit record so a calculation can be tied to the settings schema
  /// that produced it.
  static const int settingsVersion = 1;

  // ── Review scheduling ─────────────────────────────────────────────────────

  /// Insulin settings must be reviewed/confirmed at least this often. If the
  /// last review is older than this, bolus calculation is disabled.
  static const Duration reviewInterval = Duration(days: 90);

  /// Snooze options offered for the review reminder.
  static const Duration snoozeOneDay = Duration(days: 1);
  static const Duration snoozeTwoDays = Duration(days: 2);
  static const Duration snoozeOneWeek = Duration(days: 7);

  // ── Glucose reading freshness ─────────────────────────────────────────────

  /// A manually entered glucose reading older than this is considered stale and
  /// blocks correction dosing. Configurable per call; this is the default.
  static const Duration maxManualGlucoseAge = Duration(minutes: 15);

  // ── Glucose unit conversion ───────────────────────────────────────────────

  /// Exact molar conversion factor for glucose: mg/dL = mmol/L × this.
  static const double mgdlPerMmol = 18.0182;

  // ── Validation bounds (mg/dL canonical) ───────────────────────────────────
  // TODO(clinical-review): confirm all of the following ranges.

  /// Plausible blood-glucose reading range (mg/dL). Outside → blocking error.
  static const double minPlausibleGlucoseMgdl = 20.0;
  static const double maxPlausibleGlucoseMgdl = 600.0;

  /// Plausible correction target range (mg/dL).
  static const double minTargetGlucoseMgdl = 70.0;
  static const double maxTargetGlucoseMgdl = 200.0;

  /// Insulin-to-Carb Ratio plausible range (grams of carb per unit).
  static const double minIcrGramsPerUnit = 1.0;
  static const double maxIcrGramsPerUnit = 150.0;

  /// Insulin Sensitivity Factor plausible range (mg/dL lowered per unit).
  static const double minIsfMgdlPerUnit = 5.0;
  static const double maxIsfMgdlPerUnit = 400.0;

  /// Insulin action duration (a.k.a. DIA) plausible range, in hours.
  static const double minActionDurationHours = 2.0;
  static const double maxActionDurationHours = 8.0;

  /// Maximum single bolus plausible range, in units.
  static const double minMaxSingleBolusUnits = 0.5;
  static const double maxMaxSingleBolusUnits = 50.0;

  /// Allowed minimum bolus increments (units). Anything else is rejected.
  static const List<double> allowedBolusIncrements = [0.1, 0.5, 1.0];

  /// Plausible meal-carbohydrate range, in grams. Above the max requires extra
  /// confirmation (suspiciously large); negative/zero is rejected for a bolus.
  static const double maxPlausibleMealCarbsG = 400.0;

  /// A carb amount above this is unusual and triggers a confirm-first warning.
  static const double suspiciousMealCarbsG = 250.0;
}
