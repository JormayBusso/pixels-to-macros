import 'insulin_dose_log.dart';

/// Why a bolus calculation is blocked. Each maps to a precise, user-facing
/// safety message. The presence of ANY blocker means no estimate is shown.
enum BolusBlockReason {
  calculatorDisabled,
  surveyIncomplete,
  consentMissing,
  settingsStale, // > review interval and not reviewed
  surveyOverdue,
  glucoseUnitMissing,
  icrMissingForTimeBlock,
  isfMissingForTimeBlock,
  targetGlucoseMissing,
  actionDurationMissing,
  maxBolusMissing,
  minIncrementMissing,
  currentGlucoseMissing,
  glucoseReadingStale,
  mealCarbsMissingOrInvalid,
  iobRequiredButUnavailable,
  glucoseBelowHypoThreshold,
  glucoseImplausible,
  carbsImplausible,
  settingInvalid, // a stored setting failed validation
  maxBolusExceeded, // calculated dose exceeds configured max — hard block
}

extension BolusBlockReasonMessage on BolusBlockReason {
  /// User-facing, safety-first copy. Never reveals raw insulin settings.
  String get message => switch (this) {
        BolusBlockReason.calculatorDisabled =>
          'Bolus Calculator Mode is turned off. Enable it in diabetes settings.',
        BolusBlockReason.surveyIncomplete =>
          'Complete the Diabetes Insulin Settings Survey before using the calculator.',
        BolusBlockReason.consentMissing =>
          'You must accept the safety confirmation before using the calculator.',
        BolusBlockReason.settingsStale =>
          'Your insulin settings have not been reviewed in over 90 days. For '
              'safety, bolus calculations are disabled until you review and '
              'confirm your settings.',
        BolusBlockReason.surveyOverdue =>
          'Your insulin settings review is overdue. For safety, bolus '
              'calculations are disabled until you review and confirm them.',
        BolusBlockReason.glucoseUnitMissing =>
          'Your blood-glucose unit is not set. Set mg/dL or mmol/L in settings.',
        BolusBlockReason.icrMissingForTimeBlock =>
          'No insulin-to-carb ratio is configured for the current time. Meal '
              'bolus cannot be calculated.',
        BolusBlockReason.isfMissingForTimeBlock =>
          'No correction factor is configured for the current time. Correction '
              'bolus cannot be calculated.',
        BolusBlockReason.targetGlucoseMissing =>
          'No target glucose is configured. Correction bolus cannot be calculated.',
        BolusBlockReason.actionDurationMissing =>
          'Insulin action duration is not set, so insulin-on-board cannot be '
              'calculated.',
        BolusBlockReason.maxBolusMissing =>
          'No maximum single bolus is configured. Calculation is disabled for safety.',
        BolusBlockReason.minIncrementMissing =>
          'No bolus rounding increment is configured. Calculation is disabled.',
        BolusBlockReason.currentGlucoseMissing =>
          'A current glucose reading is required for a correction bolus.',
        BolusBlockReason.glucoseReadingStale =>
          'Your glucose reading is too old. Enter a fresh reading for a '
              'correction bolus.',
        BolusBlockReason.mealCarbsMissingOrInvalid =>
          'Enter a valid carbohydrate amount for this meal.',
        BolusBlockReason.iobRequiredButUnavailable =>
          'Insulin-on-board is required by your settings but cannot be '
              'calculated. Calculation is disabled.',
        BolusBlockReason.glucoseBelowHypoThreshold =>
          'Your glucose is below your configured low threshold. This app '
              'cannot recommend insulin. Follow your hypoglycemia care plan.',
        BolusBlockReason.glucoseImplausible =>
          'The glucose value looks out of range. Calculation is disabled for safety.',
        BolusBlockReason.carbsImplausible =>
          'The carbohydrate amount looks out of range. Calculation is disabled '
              'for safety.',
        BolusBlockReason.settingInvalid =>
          'One of your saved insulin settings is invalid. Review your settings.',
        BolusBlockReason.maxBolusExceeded =>
          'The calculated amount exceeds your configured maximum single bolus. '
              'This calculation is blocked. Follow your care plan or contact '
              'your clinician.',
      };
}

/// Non-blocking but important advisories shown alongside an estimate.
enum BolusWarning {
  glucoseBelowTargetNoCorrection,
  glucoseAboveHyperThreshold,
  iobMayBeInaccurate,
  carbsUnusuallyHigh,
  estimateZeroOrNegative,
}

extension BolusWarningMessage on BolusWarning {
  String get message => switch (this) {
        BolusWarning.glucoseBelowTargetNoCorrection =>
          'Your glucose is below target, so no correction insulin was added.',
        BolusWarning.glucoseAboveHyperThreshold =>
          'Your glucose is above your configured high threshold. Follow your '
              'diabetes care plan and consider checking ketones or contacting '
              'a clinician if instructed by your care plan.',
        BolusWarning.iobMayBeInaccurate =>
          'You logged recent insulin. This estimate subtracts calculated '
              'insulin-on-board, but IOB may be inaccurate. Be careful about '
              'insulin stacking and follow your care plan.',
        BolusWarning.carbsUnusuallyHigh =>
          'The carbohydrate amount is unusually high. Please double-check it '
              'before relying on this estimate.',
        BolusWarning.estimateZeroOrNegative =>
          'Calculated insulin need is zero or negative after considering '
              'current glucose and insulin-on-board. Follow your care plan.',
      };
}

/// Immutable inputs to a single meal-time bolus calculation. All glucose
/// values are mg/dL canonical; conversion happens before this object is built.
class BolusInput {
  const BolusInput({
    required this.mealCarbsG,
    this.requestCorrection = false,
    this.currentGlucoseMgdl,
    this.glucoseReadingAt,
    this.requestIob = false,
    this.recentDoses = const [],
    this.now,
  });

  final double mealCarbsG;

  // Correction
  final bool requestCorrection;
  final double? currentGlucoseMgdl;
  final DateTime? glucoseReadingAt;

  // IOB
  final bool requestIob;
  final List<InsulinDoseLog> recentDoses;

  /// Injected "current time" for deterministic testing. Defaults to now.
  final DateTime? now;
}

/// A transparent component breakdown of a calculated bolus (all in units).
class BolusBreakdown {
  const BolusBreakdown({
    required this.mealCarbsG,
    required this.icrUsed,
    required this.mealBolusUnits,
    this.currentGlucoseMgdl,
    this.targetGlucoseMgdl,
    this.isfUsed,
    required this.correctionUnits,
    required this.iobUnits,
    required this.rawBolusUnits,
    required this.roundedBolusUnits,
    required this.maxSingleBolusUnits,
    required this.minIncrement,
    required this.timeBlockLabel,
  });

  final double mealCarbsG;
  final double? icrUsed;
  final double mealBolusUnits;

  final double? currentGlucoseMgdl;
  final double? targetGlucoseMgdl;
  final double? isfUsed;
  final double correctionUnits;

  final double iobUnits;

  final double rawBolusUnits;
  final double roundedBolusUnits;
  final double maxSingleBolusUnits;
  final double minIncrement;

  final String timeBlockLabel;
}

/// Result of a bolus calculation: either blocked (with reasons) or an estimate
/// (with breakdown, warnings, and the settings version used).
class BolusResult {
  const BolusResult._({
    required this.blocked,
    required this.blockReasons,
    required this.warnings,
    required this.breakdown,
    required this.settingsVersion,
  });

  factory BolusResult.blocked(
    List<BolusBlockReason> reasons, {
    List<BolusWarning> warnings = const [],
    required int settingsVersion,
  }) =>
      BolusResult._(
        blocked: true,
        blockReasons: List.unmodifiable(reasons),
        warnings: List.unmodifiable(warnings),
        breakdown: null,
        settingsVersion: settingsVersion,
      );

  factory BolusResult.estimate(
    BolusBreakdown breakdown, {
    List<BolusWarning> warnings = const [],
    required int settingsVersion,
  }) =>
      BolusResult._(
        blocked: false,
        blockReasons: const [],
        warnings: List.unmodifiable(warnings),
        breakdown: breakdown,
        settingsVersion: settingsVersion,
      );

  final bool blocked;
  final List<BolusBlockReason> blockReasons;
  final List<BolusWarning> warnings;
  final BolusBreakdown? breakdown;
  final int settingsVersion;

  /// First/most-relevant blocking message, if any.
  String? get primaryBlockMessage =>
      blockReasons.isEmpty ? null : blockReasons.first.message;
}
