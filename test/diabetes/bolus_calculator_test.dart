// Unit tests for the Bolus Calculator Mode safety core.
//
// These tests exercise the PURE calculation/validation/scheduling logic only —
// no database or UI. The 27 required scenarios from the feature spec are each
// labelled with a `spec #N` comment.
//
// ⚠️ These tests check that the CODE behaves as specified. They do NOT
// constitute clinical validation. A licensed diabetes clinician must still
// validate the formulas, bounds and IOB model before any production release.

import 'package:flutter_test/flutter_test.dart';

import 'package:pixels_to_macros/core/diabetes/diabetes_constants.dart';
import 'package:pixels_to_macros/core/diabetes/glucose_conversion.dart';
import 'package:pixels_to_macros/models/bolus_models.dart';
import 'package:pixels_to_macros/models/insulin_dose_log.dart';
import 'package:pixels_to_macros/models/insulin_settings.dart';
import 'package:pixels_to_macros/services/diabetes/bolus_calculator_service.dart';
import 'package:pixels_to_macros/services/diabetes/diabetes_safety_validator.dart';
import 'package:pixels_to_macros/services/diabetes/diabetes_survey_scheduler.dart';
import 'package:pixels_to_macros/services/diabetes/insulin_on_board_service.dart';

/// A fixed "now" used so time-block lookups and review math are deterministic.
/// 2025-06-01 12:00 local → falls in the lunch ICR/ISF block below.
final DateTime kNow = DateTime(2025, 6, 1, 12, 0);

/// All-day ICR/ISF blocks covering 00:00–23:59 so time-of-day never blocks
/// tests that aren't specifically about time blocks.
const _icrAllDay = InsulinTimeBlock(startMinute: 0, endMinute: 1439, value: 10);
const _isfAllDay = InsulinTimeBlock(startMinute: 0, endMinute: 1439, value: 50);

/// A fully-configured, review-current, consented settings object.
InsulinSettings validSettings({
  List<InsulinTimeBlock>? icr,
  List<InsulinTimeBlock>? isf,
  double? target = 100,
  double? hypo = 70,
  double? hyper = 250,
  double? dia = 4,
  double? maxBolus = 15,
  double? increment = 0.5,
  bool correctionEnabled = true,
  bool iobEnabled = false,
  DateTime? lastCompleted,
}) {
  final completed = lastCompleted ?? kNow.subtract(const Duration(days: 1));
  return InsulinSettings(
    diabetesEnabled: true,
    usesInsulin: true,
    bolusCalculatorEnabled: true,
    glucoseUnit: BgUnit.mgdl,
    surveyLastCompletedAt: completed,
    surveyNextDueAt: DiabetesSurveyScheduler.nextDue(completed),
    userConfirmedAt: completed,
    targetGlucoseMgdl: target,
    hypoThresholdMgdl: hypo,
    hyperThresholdMgdl: hyper,
    icrBlocks: icr ?? const [_icrAllDay],
    isfBlocks: isf ?? const [_isfAllDay],
    insulinActionDurationHours: dia,
    maxSingleBolusUnits: maxBolus,
    minBolusIncrement: increment,
    correctionEnabled: correctionEnabled,
    mealBolusEnabled: true,
    iobEnabled: iobEnabled,
  );
}

void main() {
  group('Meal bolus', () {
    test('spec #1: meal bolus = carbs / ICR', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(correctionEnabled: false),
        input: BolusInput(mealCarbsG: 60, now: kNow),
      );
      expect(r.blocked, isFalse);
      // 60 / 10 = 6.0 units
      expect(r.breakdown!.mealBolusUnits, closeTo(6.0, 1e-9));
    });

    test('spec #11: missing ICR for time block blocks meal bolus', () {
      // ICR block only covers the morning; kNow is noon → no active ICR.
      final r = BolusCalculatorService.calculate(
        settings: validSettings(
          icr: const [InsulinTimeBlock(startMinute: 0, endMinute: 600, value: 10)],
          correctionEnabled: false,
        ),
        input: BolusInput(mealCarbsG: 60, now: kNow),
      );
      expect(r.blocked, isTrue);
      expect(r.blockReasons, contains(BolusBlockReason.icrMissingForTimeBlock));
    });

    test('spec #22: zero/negative ICR rejected by validator', () {
      final res = DiabetesSafetyValidator.validateSettings(
        validSettings(icr: const [
          InsulinTimeBlock(startMinute: 0, endMinute: 1439, value: 0),
        ]),
      );
      expect(res.hasErrors, isTrue);
    });
  });

  group('Correction bolus', () {
    test('spec #2: correction for mg/dL = (BG - target) / ISF', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(),
        input: BolusInput(
          mealCarbsG: 0.01, // negligible carbs, focus on correction
          requestCorrection: true,
          currentGlucoseMgdl: 200,
          glucoseReadingAt: kNow,
          now: kNow,
        ),
      );
      expect(r.blocked, isFalse);
      // (200 - 100) / 50 = 2.0
      expect(r.breakdown!.correctionUnits, closeTo(2.0, 1e-9));
    });

    test('spec #3: correction for mmol/L via conversion', () {
      // Work in mmol/L: BG 11.1 mmol/L, target 5.6, ISF 2.8 mmol/L per unit.
      final bgMgdl = GlucoseConversion.mmolToMgdl(11.1);
      final targetMgdl = GlucoseConversion.mmolToMgdl(5.6);
      final isfMgdl = 2.8 * DiabetesConstants.mgdlPerMmol;
      final r = BolusCalculatorService.calculate(
        settings: validSettings(
          target: targetMgdl,
          isf: [InsulinTimeBlock(startMinute: 0, endMinute: 1439, value: isfMgdl)],
        ).copyWith(glucoseUnit: BgUnit.mmol),
        input: BolusInput(
          mealCarbsG: 0.01,
          requestCorrection: true,
          currentGlucoseMgdl: bgMgdl,
          glucoseReadingAt: kNow,
          now: kNow,
        ),
      );
      expect(r.blocked, isFalse);
      // (11.1 - 5.6) / 2.8 ≈ 1.964 units (computed in mmol equivalently)
      expect(r.breakdown!.correctionUnits, closeTo((11.1 - 5.6) / 2.8, 1e-6));
    });

    test('spec #4a: glucose below target → no correction added', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(),
        input: BolusInput(
          mealCarbsG: 30,
          requestCorrection: true,
          currentGlucoseMgdl: 90, // below target 100, above hypo 70
          glucoseReadingAt: kNow,
          now: kNow,
        ),
      );
      expect(r.blocked, isFalse);
      expect(r.breakdown!.correctionUnits, 0);
      expect(r.warnings, contains(BolusWarning.glucoseBelowTargetNoCorrection));
    });

    test('spec #4b: glucose below hypo threshold blocks calculation', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(),
        input: BolusInput(
          mealCarbsG: 30,
          requestCorrection: true,
          currentGlucoseMgdl: 60, // below hypo 70
          glucoseReadingAt: kNow,
          now: kNow,
        ),
      );
      expect(r.blocked, isTrue);
      expect(r.blockReasons,
          contains(BolusBlockReason.glucoseBelowHypoThreshold));
    });

    test('spec #12: missing ISF blocks correction', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(isf: const []),
        input: BolusInput(
          mealCarbsG: 30,
          requestCorrection: true,
          currentGlucoseMgdl: 200,
          glucoseReadingAt: kNow,
          now: kNow,
        ),
      );
      expect(r.blocked, isTrue);
      expect(r.blockReasons, contains(BolusBlockReason.isfMissingForTimeBlock));
    });

    test('spec #13: missing target blocks correction', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(target: null),
        input: BolusInput(
          mealCarbsG: 30,
          requestCorrection: true,
          currentGlucoseMgdl: 200,
          glucoseReadingAt: kNow,
          now: kNow,
        ),
      );
      expect(r.blocked, isTrue);
      expect(r.blockReasons, contains(BolusBlockReason.targetGlucoseMissing));
    });

    test('spec #14: stale glucose reading blocks correction', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(),
        input: BolusInput(
          mealCarbsG: 30,
          requestCorrection: true,
          currentGlucoseMgdl: 200,
          glucoseReadingAt: kNow.subtract(const Duration(minutes: 30)),
          now: kNow,
        ),
      );
      expect(r.blocked, isTrue);
      expect(r.blockReasons, contains(BolusBlockReason.glucoseReadingStale));
    });

    test('spec #23: zero/negative ISF rejected by validator', () {
      final res = DiabetesSafetyValidator.validateSettings(
        validSettings(isf: const [
          InsulinTimeBlock(startMinute: 0, endMinute: 1439, value: -5),
        ]),
      );
      expect(res.hasErrors, isTrue);
    });
  });

  group('Insulin on board', () {
    test('spec #5: linear decay IOB', () {
      // 4u taken 2h ago, DIA 4h → remaining 50% → 2u.
      final iob = InsulinOnBoardService.calculateIob(
        doses: [
          InsulinDoseLog(
            units: 4,
            timestamp: kNow.subtract(const Duration(hours: 2)),
            confirmed: true,
          ),
        ],
        actionDurationHours: 4,
        now: kNow,
      );
      expect(iob, closeTo(2.0, 1e-9));
    });

    test('fully decayed dose contributes zero IOB', () {
      final iob = InsulinOnBoardService.calculateIob(
        doses: [
          InsulinDoseLog(
            units: 5,
            timestamp: kNow.subtract(const Duration(hours: 5)),
            confirmed: true,
          ),
        ],
        actionDurationHours: 4,
        now: kNow,
      );
      expect(iob, 0);
    });

    test('spec #6: total = meal + correction - IOB', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(iobEnabled: true),
        input: BolusInput(
          mealCarbsG: 60, // meal 6.0
          requestCorrection: true,
          currentGlucoseMgdl: 200, // correction 2.0
          glucoseReadingAt: kNow,
          requestIob: true,
          recentDoses: [
            InsulinDoseLog(
              units: 4, // IOB 2.0 at 2h / DIA 4h
              timestamp: kNow.subtract(const Duration(hours: 2)),
              confirmed: true,
            ),
          ],
          now: kNow,
        ),
      );
      expect(r.blocked, isFalse);
      // 6 + 2 - 2 = 6.0
      expect(r.breakdown!.rawBolusUnits, closeTo(6.0, 1e-9));
    });

    test('spec #7: total cannot go below zero', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(iobEnabled: true),
        input: BolusInput(
          mealCarbsG: 10, // meal 1.0
          requestCorrection: false,
          requestIob: true,
          recentDoses: [
            InsulinDoseLog(
              units: 8, // IOB 4.0 at 2h / DIA 4h
              timestamp: kNow.subtract(const Duration(hours: 2)),
              confirmed: true,
            ),
          ],
          now: kNow,
        ),
      );
      expect(r.blocked, isFalse);
      expect(r.breakdown!.rawBolusUnits, 0);
      expect(r.warnings, contains(BolusWarning.estimateZeroOrNegative));
    });
  });

  group('Max bolus + rounding', () {
    test('spec #8: bolus over max is hard-blocked (not clamped)', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(maxBolus: 5, correctionEnabled: false),
        input: BolusInput(mealCarbsG: 100, now: kNow), // 10u > 5u max
      );
      expect(r.blocked, isTrue);
      expect(r.blockReasons, contains(BolusBlockReason.maxBolusExceeded));
      expect(r.breakdown, isNull);
    });

    test('spec #9: rounding to 0.5 units', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(increment: 0.5, correctionEnabled: false),
        input: BolusInput(mealCarbsG: 62, now: kNow), // 6.2 → 6.0
      );
      expect(r.breakdown!.roundedBolusUnits, 6.0);
    });

    test('spec #10: rounding to 1.0 unit', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(increment: 1.0, correctionEnabled: false),
        input: BolusInput(mealCarbsG: 67, now: kNow), // 6.7 → 7.0
      );
      expect(r.breakdown!.roundedBolusUnits, 7.0);
    });

    test('unrounded estimate is always preserved alongside rounded', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(increment: 0.5, correctionEnabled: false),
        input: BolusInput(mealCarbsG: 62, now: kNow),
      );
      expect(r.breakdown!.rawBolusUnits, closeTo(6.2, 1e-9));
      expect(r.breakdown!.roundedBolusUnits, 6.0);
    });
  });

  group('Survey scheduling', () {
    test('spec #15: overdue 90-day survey disables calculator', () {
      final old = kNow.subtract(const Duration(days: 100));
      final r = BolusCalculatorService.calculate(
        settings: validSettings(lastCompleted: old),
        input: BolusInput(mealCarbsG: 30, now: kNow),
      );
      expect(r.blocked, isTrue);
      expect(
        r.blockReasons.any((b) =>
            b == BolusBlockReason.surveyOverdue ||
            b == BolusBlockReason.settingsStale),
        isTrue,
      );
    });

    test('spec #16: snooze 1 day', () {
      final s = DiabetesSurveyScheduler.snooze(
          validSettings(), DiabetesConstants.snoozeOneDay, kNow);
      expect(s.surveySnoozedUntil,
          kNow.add(const Duration(days: 1)));
      expect(DiabetesSurveyScheduler.isSnoozed(s, kNow), isTrue);
    });

    test('spec #17: snooze 2 days', () {
      final s = DiabetesSurveyScheduler.snooze(
          validSettings(), DiabetesConstants.snoozeTwoDays, kNow);
      expect(s.surveySnoozedUntil, kNow.add(const Duration(days: 2)));
    });

    test('spec #18: snooze 7 days', () {
      final s = DiabetesSurveyScheduler.snooze(
          validSettings(), DiabetesConstants.snoozeOneWeek, kNow);
      expect(s.surveySnoozedUntil, kNow.add(const Duration(days: 7)));
    });

    test('snooze suppresses reminder but does NOT re-enable an overdue calc',
        () {
      final overdue = validSettings(
          lastCompleted: kNow.subtract(const Duration(days: 100)));
      final snoozed =
          DiabetesSurveyScheduler.snooze(overdue, const Duration(days: 1), kNow);
      // Reminder hidden during snooze…
      expect(DiabetesSurveyScheduler.shouldShowReminder(snoozed, kNow), isFalse);
      // …but calculation still disabled because the review is overdue.
      expect(DiabetesSurveyScheduler.allowsCalculation(snoozed, kNow), isFalse);
    });
  });

  group('Glucose unit conversion', () {
    test('spec #19: mg/dL → mmol/L', () {
      expect(GlucoseConversion.mgdlToMmol(180), closeTo(180 / 18.0182, 1e-9));
    });

    test('spec #20: mmol/L → mg/dL', () {
      expect(GlucoseConversion.mmolToMgdl(10), closeTo(10 * 18.0182, 1e-9));
    });

    test('round-trip conversion is stable', () {
      const original = 137.0;
      final back =
          GlucoseConversion.mmolToMgdl(GlucoseConversion.mgdlToMmol(original));
      expect(back, closeTo(original, 1e-9));
    });
  });

  group('Validation', () {
    test('spec #21: overlapping time blocks are invalid', () {
      final res = DiabetesSafetyValidator.validateSettings(
        validSettings(icr: const [
          InsulinTimeBlock(startMinute: 0, endMinute: 700, value: 10),
          InsulinTimeBlock(startMinute: 600, endMinute: 1439, value: 12),
        ]),
      );
      expect(res.hasErrors, isTrue);
    });

    test('spec #24: invalid insulin action duration rejected', () {
      final res = DiabetesSafetyValidator.validateSettings(
        validSettings(dia: 0.5), // below min 2h
      );
      expect(res.hasErrors, isTrue);
    });

    test('implausible glucose blocks calculation', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(),
        input: BolusInput(
          mealCarbsG: 30,
          requestCorrection: true,
          currentGlucoseMgdl: 5, // below plausible floor
          glucoseReadingAt: kNow,
          now: kNow,
        ),
      );
      expect(r.blocked, isTrue);
    });

    test('invalid meal carbs blocks meal bolus', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(correctionEnabled: false),
        input: BolusInput(mealCarbsG: 0, now: kNow),
      );
      expect(r.blocked, isTrue);
      expect(r.blockReasons,
          contains(BolusBlockReason.mealCarbsMissingOrInvalid));
    });
  });

  group('Anti-TDD guarantee + audit', () {
    test('spec #25: TDD is never used to prescribe ICR/ISF', () {
      // Two identical settings except one has a large TDD set. The calculated
      // bolus must be IDENTICAL — proving TDD never feeds the math.
      final withoutTdd = validSettings(correctionEnabled: false);
      final withTdd =
          withoutTdd.copyWith(totalDailyInsulinDoseOptional: 60);
      final input = BolusInput(mealCarbsG: 50, now: kNow);

      final a = BolusCalculatorService.calculate(
          settings: withoutTdd, input: input);
      final b =
          BolusCalculatorService.calculate(settings: withTdd, input: input);

      expect(a.breakdown!.mealBolusUnits, b.breakdown!.mealBolusUnits);
      expect(a.breakdown!.roundedBolusUnits, b.breakdown!.roundedBolusUnits);
    });

    test('spec #26: result carries settings_version + full breakdown', () {
      final r = BolusCalculatorService.calculate(
        settings: validSettings(),
        input: BolusInput(
          mealCarbsG: 60,
          requestCorrection: true,
          currentGlucoseMgdl: 200,
          glucoseReadingAt: kNow,
          now: kNow,
        ),
      );
      expect(r.settingsVersion, DiabetesConstants.settingsVersion);
      final b = r.breakdown!;
      expect(b.icrUsed, isNotNull);
      expect(b.isfUsed, isNotNull);
      expect(b.mealBolusUnits, greaterThan(0));
      expect(b.correctionUnits, greaterThan(0));
      expect(b.timeBlockLabel, isNotEmpty);
    });
  });

  group('Dose-log confirmation', () {
    test('spec #27: unconfirmed doses do not contribute to IOB', () {
      final iob = InsulinOnBoardService.calculateIob(
        doses: [
          InsulinDoseLog(
            units: 4,
            timestamp: kNow.subtract(const Duration(hours: 1)),
            confirmed: false, // NOT confirmed → ignored
          ),
        ],
        actionDurationHours: 4,
        now: kNow,
      );
      expect(iob, 0);
    });
  });

  group('Gating', () {
    test('calculator disabled by default blocks everything', () {
      final r = BolusCalculatorService.calculate(
        settings: const InsulinSettings(), // all defaults: disabled
        input: BolusInput(mealCarbsG: 30, now: kNow),
      );
      expect(r.blocked, isTrue);
      expect(r.blockReasons, contains(BolusBlockReason.calculatorDisabled));
    });

    test('missing consent blocks calculation', () {
      final s = validSettings().copyWith();
      final noConsent = InsulinSettings(
        diabetesEnabled: s.diabetesEnabled,
        usesInsulin: s.usesInsulin,
        bolusCalculatorEnabled: true,
        surveyLastCompletedAt: s.surveyLastCompletedAt,
        surveyNextDueAt: s.surveyNextDueAt,
        userConfirmedAt: null, // consent missing
        icrBlocks: s.icrBlocks,
        isfBlocks: s.isfBlocks,
        targetGlucoseMgdl: s.targetGlucoseMgdl,
        hypoThresholdMgdl: s.hypoThresholdMgdl,
        insulinActionDurationHours: s.insulinActionDurationHours,
        maxSingleBolusUnits: s.maxSingleBolusUnits,
        minBolusIncrement: s.minBolusIncrement,
      );
      final r = BolusCalculatorService.calculate(
        settings: noConsent,
        input: BolusInput(mealCarbsG: 30, now: kNow),
      );
      expect(r.blocked, isTrue);
      expect(r.blockReasons, contains(BolusBlockReason.consentMissing));
    });
  });
}
