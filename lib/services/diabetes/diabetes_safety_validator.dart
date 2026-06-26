import '../../core/diabetes/diabetes_constants.dart';
import '../../models/insulin_settings.dart';

/// Severity of a validation finding.
enum ValidationSeverity {
  /// Dangerous/impossible — blocks the calculation.
  error,

  /// Unusual but possible — allowed only after extra user confirmation.
  warning,
}

/// A single validation finding with a human-readable, non-sensitive message.
class ValidationIssue {
  const ValidationIssue(this.severity, this.message,
      {this.field, this.code, this.labelKey});
  final ValidationSeverity severity;
  final String message;
  final String? field;

  /// Stable code for localization (maps to AppLocalizations.validatorMessage).
  final String? code;

  /// Optional label key ('icr'/'isf') for messages that interpolate a label.
  final String? labelKey;

  bool get isError => severity == ValidationSeverity.error;
  bool get isWarning => severity == ValidationSeverity.warning;
}

/// Outcome of validating settings or inputs.
class ValidationResult {
  ValidationResult(this.issues);
  final List<ValidationIssue> issues;

  bool get hasErrors => issues.any((i) => i.isError);
  bool get hasWarnings => issues.any((i) => i.isWarning);
  List<ValidationIssue> get errors => issues.where((i) => i.isError).toList();
  List<ValidationIssue> get warnings =>
      issues.where((i) => i.isWarning).toList();

  static ValidationResult ok() => ValidationResult(const []);
}

/// Pure validation of stored insulin settings and per-meal inputs.
///
/// ⚠️ Safety assumption: this validator is the single source of truth for what
/// counts as a *dangerous* (blocking) value vs an *unusual* (confirm-first)
/// value. All bounds come from [DiabetesConstants].
///
/// TODO(clinical-review): all bounds and the error/warning split below must be
/// reviewed by a licensed diabetes clinician before production.
class DiabetesSafetyValidator {
  DiabetesSafetyValidator._();

  /// Validate the stored insulin settings (independent of any meal). Used to
  /// gate enabling the calculator and on every calculation.
  static ValidationResult validateSettings(InsulinSettings s) {
    final issues = <ValidationIssue>[];

    // Glucose unit must be unambiguous.
    // (enum is always set, but guard against a future nullable refactor)

    // ICR blocks: each value in range, no overlaps.
    issues.addAll(_validateBlocks(
      s.icrBlocks,
      label: 'insulin-to-carb ratio',
      min: DiabetesConstants.minIcrGramsPerUnit,
      max: DiabetesConstants.maxIcrGramsPerUnit,
      field: 'icr',
    ));

    // ISF blocks (only required if correction enabled, but validate if present).
    issues.addAll(_validateBlocks(
      s.isfBlocks,
      label: 'correction factor',
      min: DiabetesConstants.minIsfMgdlPerUnit,
      max: DiabetesConstants.maxIsfMgdlPerUnit,
      field: 'isf',
    ));

    // Target glucose.
    final target = s.targetGlucoseMgdl;
    if (target != null) {
      if (target < DiabetesConstants.minTargetGlucoseMgdl ||
          target > DiabetesConstants.maxTargetGlucoseMgdl) {
        issues.add(const ValidationIssue(ValidationSeverity.error,
            'Target glucose is outside a safe range.',
            field: 'target', code: 'targetOutOfRange'));
      }
    }

    // Action duration.
    final dia = s.insulinActionDurationHours;
    if (dia != null) {
      if (dia < DiabetesConstants.minActionDurationHours ||
          dia > DiabetesConstants.maxActionDurationHours) {
        issues.add(const ValidationIssue(ValidationSeverity.error,
            'Insulin action duration is outside a safe range.',
            field: 'actionDuration', code: 'actionDurationOutOfRange'));
      }
    }

    // Max single bolus.
    final maxBolus = s.maxSingleBolusUnits;
    if (maxBolus != null) {
      if (maxBolus < DiabetesConstants.minMaxSingleBolusUnits ||
          maxBolus > DiabetesConstants.maxMaxSingleBolusUnits) {
        issues.add(const ValidationIssue(ValidationSeverity.error,
            'Maximum single bolus is outside a safe range.',
            field: 'maxBolus', code: 'maxBolusOutOfRange'));
      }
    }

    // Minimum bolus increment.
    final inc = s.minBolusIncrement;
    if (inc != null && !DiabetesConstants.allowedBolusIncrements.contains(inc)) {
      issues.add(const ValidationIssue(ValidationSeverity.error,
          'Bolus rounding increment is not a supported value.',
          field: 'increment', code: 'incrementUnsupported'));
    }

    // Hypo/hyper thresholds sanity (hypo below hyper).
    final hypo = s.hypoThresholdMgdl;
    final hyper = s.hyperThresholdMgdl;
    if (hypo != null && hyper != null && hypo >= hyper) {
      issues.add(const ValidationIssue(ValidationSeverity.error,
          'Low threshold must be below the high threshold.',
          field: 'thresholds', code: 'thresholdsInverted'));
    }

    return ValidationResult(issues);
  }

  static List<ValidationIssue> _validateBlocks(
    List<InsulinTimeBlock> blocks, {
    required String label,
    required double min,
    required double max,
    required String field,
  }) {
    final issues = <ValidationIssue>[];
    for (final b in blocks) {
      // No divide-by-zero / negatives.
      if (b.value <= 0) {
        issues.add(ValidationIssue(ValidationSeverity.error,
            'A $label value must be greater than zero.',
            field: field, code: 'valueNotPositive', labelKey: field));
      } else if (b.value < min || b.value > max) {
        issues.add(ValidationIssue(ValidationSeverity.error,
            'A $label value is outside a safe range.',
            field: field, code: 'valueOutOfRange', labelKey: field));
      }
      if (b.startMinute < 0 || b.endMinute > 1439 || b.startMinute > b.endMinute) {
        issues.add(ValidationIssue(ValidationSeverity.error,
            'A $label time block has an invalid time range.',
            field: field, code: 'invalidTimeRange', labelKey: field));
      }
    }
    // Overlap detection (O(n^2) — block counts are tiny).
    for (var i = 0; i < blocks.length; i++) {
      for (var j = i + 1; j < blocks.length; j++) {
        if (blocks[i].overlaps(blocks[j])) {
          issues.add(ValidationIssue(ValidationSeverity.error,
              'Your $label time blocks overlap. Fix them before continuing.',
              field: field, code: 'blocksOverlap', labelKey: field));
        }
      }
    }
    return issues;
  }

  /// Validate a current glucose reading value (mg/dL canonical).
  static ValidationResult validateGlucoseReading(double mgdl) {
    if (mgdl < DiabetesConstants.minPlausibleGlucoseMgdl ||
        mgdl > DiabetesConstants.maxPlausibleGlucoseMgdl) {
      return ValidationResult([
        const ValidationIssue(ValidationSeverity.error,
            'The glucose value looks out of range.',
            field: 'glucose', code: 'glucoseOutOfRange'),
      ]);
    }
    return ValidationResult.ok();
  }

  /// Validate a meal carbohydrate amount (grams).
  static ValidationResult validateMealCarbs(double carbsG) {
    if (carbsG <= 0 || carbsG.isNaN || carbsG.isInfinite) {
      return ValidationResult([
        const ValidationIssue(ValidationSeverity.error,
            'Enter a carbohydrate amount greater than zero.',
            field: 'carbs', code: 'carbsNotPositive'),
      ]);
    }
    if (carbsG > DiabetesConstants.maxPlausibleMealCarbsG) {
      return ValidationResult([
        const ValidationIssue(ValidationSeverity.error,
            'The carbohydrate amount looks out of range.',
            field: 'carbs', code: 'carbsOutOfRange'),
      ]);
    }
    if (carbsG > DiabetesConstants.suspiciousMealCarbsG) {
      return ValidationResult([
        const ValidationIssue(ValidationSeverity.warning,
            'The carbohydrate amount is unusually high. Please double-check it.',
            field: 'carbs', code: 'carbsUnusuallyHigh'),
      ]);
    }
    return ValidationResult.ok();
  }

  /// Whether a glucose reading taken at [readingAt] is fresh enough at [now].
  static bool isGlucoseFresh(
    DateTime readingAt,
    DateTime now, {
    Duration maxAge = DiabetesConstants.maxManualGlucoseAge,
  }) {
    final age = now.difference(readingAt);
    return !age.isNegative && age <= maxAge;
  }
}
