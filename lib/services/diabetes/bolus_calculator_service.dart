import '../../core/diabetes/diabetes_constants.dart';
import '../../models/bolus_models.dart';
import '../../models/insulin_settings.dart';
import 'diabetes_safety_validator.dart';
import 'diabetes_survey_scheduler.dart';
import 'insulin_on_board_service.dart';

/// Safety-first meal-time insulin bolus calculator.
///
/// ⚠️ MEDICAL-DEVICE WARNING — see [DiabetesConstants]. This produces an
/// *estimate* from user-confirmed settings. It is not medical advice and must
/// not be released to real users without clinical validation, risk management,
/// and regulatory/legal review.
///
/// Design rules enforced here:
///  • OFF unless [InsulinSettings.bolusCalculatorEnabled] is true.
///  • Requires a completed survey + accepted consent + a current 90-day review.
///  • Uses ONLY user-confirmed settings; never invents values.
///  • NEVER reads total-daily-dose to derive ICR/ISF.
///  • Returns a hard block (no estimate) on any unsafe/missing condition.
///  • Hard-blocks (does not silently clamp) when the result exceeds max bolus.
///
/// All glucose values are mg/dL canonical. The function is pure: pass [now] for
/// deterministic behaviour.
class BolusCalculatorService {
  BolusCalculatorService._();

  static BolusResult calculate({
    required InsulinSettings settings,
    required BolusInput input,
  }) {
    final now = input.now ?? DateTime.now();
    final version = settings.settingsVersion;
    final blockers = <BolusBlockReason>[];

    // ── Gate 1: feature/consent/review state ────────────────────────────────
    if (!settings.bolusCalculatorEnabled) {
      blockers.add(BolusBlockReason.calculatorDisabled);
    }
    if (settings.surveyLastCompletedAt == null) {
      blockers.add(BolusBlockReason.surveyIncomplete);
    }
    if (settings.userConfirmedAt == null) {
      blockers.add(BolusBlockReason.consentMissing);
    }
    if (settings.surveyLastCompletedAt != null &&
        !DiabetesSurveyScheduler.allowsCalculation(settings, now)) {
      // Distinguish overdue vs stale for clearer messaging.
      final status = DiabetesSurveyScheduler.statusAt(settings, now);
      blockers.add(status == ReviewStatus.overdue
          ? BolusBlockReason.surveyOverdue
          : BolusBlockReason.settingsStale);
    }

    // ── Gate 2: stored-settings validity ────────────────────────────────────
    final settingsValidation =
        DiabetesSafetyValidator.validateSettings(settings);
    if (settingsValidation.hasErrors) {
      blockers.add(BolusBlockReason.settingInvalid);
    }

    // Required common settings.
    final maxBolus = settings.maxSingleBolusUnits;
    final increment = settings.minBolusIncrement;
    if (maxBolus == null) blockers.add(BolusBlockReason.maxBolusMissing);
    if (increment == null) blockers.add(BolusBlockReason.minIncrementMissing);

    // ── Gate 3: meal carbs ──────────────────────────────────────────────────
    final carbsValidation =
        DiabetesSafetyValidator.validateMealCarbs(input.mealCarbsG);
    if (carbsValidation.hasErrors) {
      // Distinguish "implausible" from "missing/invalid" for messaging.
      final implausible = input.mealCarbsG.isFinite &&
          input.mealCarbsG > DiabetesConstants.maxPlausibleMealCarbsG;
      blockers.add(implausible
          ? BolusBlockReason.carbsImplausible
          : BolusBlockReason.mealCarbsMissingOrInvalid);
    }

    // Active ICR for the current time block (required for a meal bolus).
    final minuteOfDay = now.hour * 60 + now.minute;
    final icr = settings.icrForMinute(minuteOfDay);
    if (icr == null || icr <= 0) {
      blockers.add(BolusBlockReason.icrMissingForTimeBlock);
    }

    // ── Gate 4: correction (optional) ───────────────────────────────────────
    final warnings = <BolusWarning>[];
    double correction = 0;
    double? isf;
    final wantsCorrection =
        input.requestCorrection && settings.correctionEnabled;
    if (wantsCorrection) {
      final glucose = input.currentGlucoseMgdl;
      final readingAt = input.glucoseReadingAt;
      final target = settings.targetGlucoseMgdl;
      isf = settings.isfForMinute(minuteOfDay);

      if (glucose == null) {
        blockers.add(BolusBlockReason.currentGlucoseMissing);
      } else {
        final gv = DiabetesSafetyValidator.validateGlucoseReading(glucose);
        if (gv.hasErrors) blockers.add(BolusBlockReason.glucoseImplausible);

        // Low-glucose safety: never recommend insulin below the hypo threshold.
        final hypo = settings.hypoThresholdMgdl;
        if (hypo != null && glucose < hypo) {
          blockers.add(BolusBlockReason.glucoseBelowHypoThreshold);
        }
        // High-glucose advisory (non-blocking).
        final hyper = settings.hyperThresholdMgdl;
        if (hyper != null && glucose > hyper) {
          warnings.add(BolusWarning.glucoseAboveHyperThreshold);
        }
      }

      if (readingAt == null ||
          !DiabetesSafetyValidator.isGlucoseFresh(readingAt, now)) {
        blockers.add(BolusBlockReason.glucoseReadingStale);
      }
      if (target == null) blockers.add(BolusBlockReason.targetGlucoseMissing);
      if (isf == null || isf <= 0) {
        blockers.add(BolusBlockReason.isfMissingForTimeBlock);
      }

      // Compute correction only if everything needed is present & safe so far.
      if (glucose != null && target != null && isf != null && isf > 0) {
        if (glucose <= target) {
          // Below/at target → no extra insulin for a low.
          correction = 0;
          warnings.add(BolusWarning.glucoseBelowTargetNoCorrection);
        } else {
          correction = (glucose - target) / isf;
        }
      }
    }

    // ── Gate 5: IOB (optional / possibly required) ──────────────────────────
    double iob = 0;
    final wantsIob = input.requestIob && settings.iobEnabled;
    if (wantsIob || settings.iobEnabled) {
      final dia = settings.insulinActionDurationHours;
      if (dia == null || dia <= 0) {
        blockers.add(BolusBlockReason.actionDurationMissing);
        if (settings.iobEnabled) {
          blockers.add(BolusBlockReason.iobRequiredButUnavailable);
        }
      } else {
        iob = InsulinOnBoardService.calculateIob(
          doses: input.recentDoses,
          actionDurationHours: dia,
          now: now,
        );
        if (iob > 0) warnings.add(BolusWarning.iobMayBeInaccurate);
      }
    }

    // If anything blocked, stop here — never show a partial estimate.
    if (blockers.isNotEmpty) {
      return BolusResult.blocked(blockers,
          warnings: warnings, settingsVersion: version);
    }

    // ── Compute (all gates passed) ──────────────────────────────────────────
    // Safe to use ! here: each was checked above.
    final mealBolus = input.mealCarbsG / icr!;
    final rawBolus = mealBolus + correction - iob;

    // Safety clamp at zero (display), with advisory.
    var displayRaw = rawBolus;
    if (displayRaw < 0) {
      displayRaw = 0;
      warnings.add(BolusWarning.estimateZeroOrNegative);
    }

    // Hard block (NOT silent clamp) if over the configured maximum.
    if (displayRaw > maxBolus!) {
      return BolusResult.blocked(
        [BolusBlockReason.maxBolusExceeded],
        warnings: warnings,
        settingsVersion: version,
      );
    }

    final rounded = _roundToIncrement(displayRaw, increment!);

    if (input.mealCarbsG > DiabetesConstants.suspiciousMealCarbsG) {
      warnings.add(BolusWarning.carbsUnusuallyHigh);
    }

    final breakdown = BolusBreakdown(
      mealCarbsG: input.mealCarbsG,
      icrUsed: icr,
      mealBolusUnits: mealBolus,
      currentGlucoseMgdl: input.currentGlucoseMgdl,
      targetGlucoseMgdl: settings.targetGlucoseMgdl,
      isfUsed: isf,
      correctionUnits: correction,
      iobUnits: iob,
      rawBolusUnits: displayRaw,
      roundedBolusUnits: rounded,
      maxSingleBolusUnits: maxBolus,
      minIncrement: increment,
      timeBlockLabel: _timeBlockLabel(minuteOfDay),
    );

    return BolusResult.estimate(breakdown,
        warnings: warnings, settingsVersion: version);
  }

  /// Round [value] DOWN-to-nearest is unsafe for insulin overshoot, but the
  /// spec asks to round to the configured increment. We round to nearest, which
  /// matches typical pump/pen behaviour; the unrounded value is always shown too.
  static double _roundToIncrement(double value, double increment) {
    if (increment <= 0) return value;
    final steps = (value / increment).round();
    final rounded = steps * increment;
    // Avoid floating-point artefacts like 1.5000000002.
    return double.parse(rounded.toStringAsFixed(3));
  }

  static String _timeBlockLabel(int minuteOfDay) {
    if (minuteOfDay < 5 * 60) return 'Overnight';
    if (minuteOfDay < 11 * 60) return 'Breakfast';
    if (minuteOfDay < 17 * 60) return 'Lunch';
    if (minuteOfDay < 21 * 60) return 'Dinner';
    return 'Evening';
  }
}
