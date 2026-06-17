import '../models/nutrient_data.dart';
import '../models/scan_result.dart';
import 'database_service.dart';

/// Estimated macronutrient content of a single meal, used to drive the
/// diabetes insulin advisory.
class MealNutrition {
  final double carbsG;
  final double proteinG;
  final double fatG;
  final double fiberG;

  const MealNutrition({
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.fiberG = 0,
  });

  bool get isEmpty => carbsG <= 0 && proteinG <= 0 && fatG <= 0;
}

/// How quickly the meal is expected to raise blood glucose.
enum SpikeSpeed { fast, moderate, slow }

extension SpikeSpeedX on SpikeSpeed {
  String get label => switch (this) {
        SpikeSpeed.fast => 'Fast-acting meal',
        SpikeSpeed.moderate => 'Moderate meal',
        SpikeSpeed.slow => 'Slow-release meal',
      };
}

/// Clinical classification of a current blood-glucose reading (mg/dL).
enum BgStatus { low, inRange, elevated, high }

extension BgStatusX on BgStatus {
  String get label => switch (this) {
        BgStatus.low => 'Low (hypoglycaemia)',
        BgStatus.inRange => 'In range',
        BgStatus.elevated => 'Above target',
        BgStatus.high => 'High (hyperglycaemia)',
      };
}

/// A complete, clinically-grounded insulin advisory for ONE meal.
class DiabetesAdvice {
  /// Whether the user has configured an Insulin-to-Carb Ratio.
  final bool icrConfigured;

  /// Whether the user has configured an Insulin Sensitivity Factor (ISF).
  final bool isfConfigured;

  /// Grams of carbohydrate in the meal.
  final double mealCarbsG;

  /// Estimated rapid-acting meal (carb) bolus, in units. Null when no ICR.
  final double? bolusUnits;

  /// Correction dose in units from the current blood glucose, or null when a
  /// current reading / ISF is not available. May be negative (reduce dose).
  final double? correctionUnits;

  /// Total suggested dose = meal bolus + correction, clamped at ≥ 0.
  /// Null when no ICR is set.
  final double? totalBolusUnits;

  /// The ICR used for the calculation (g carb per 1 unit). 0 when unset.
  final double icr;

  /// Classification of the entered current blood glucose, or null if none.
  final BgStatus? bgStatus;

  /// A safety message about the current blood glucose (e.g. treat a low
  /// first), or null when no reading was entered.
  final String? bgWarning;

  /// Recommended minutes to inject BEFORE the first bite ("pre-bolus").
  final int prebolusMinutes;

  /// Estimated minutes after eating until blood glucose peaks.
  final int timeToPeakMinutes;

  /// How fast this meal is expected to act.
  final SpikeSpeed spikeSpeed;

  /// Plain-language timing guidance.
  final String timingMessage;

  /// Food-sequencing ("eat veg/protein before carbs") guidance.
  final String foodOrderTip;

  const DiabetesAdvice({
    required this.icrConfigured,
    required this.isfConfigured,
    required this.mealCarbsG,
    required this.bolusUnits,
    required this.correctionUnits,
    required this.totalBolusUnits,
    required this.icr,
    required this.bgStatus,
    required this.bgWarning,
    required this.prebolusMinutes,
    required this.timeToPeakMinutes,
    required this.spikeSpeed,
    required this.timingMessage,
    required this.foodOrderTip,
  });

  static double? _round05(double? v) =>
      v == null ? null : (v * 2).round() / 2;

  /// Meal bolus rounded to the nearest 0.5 unit (typical pen/pump increment).
  double? get bolusRounded => _round05(bolusUnits);

  /// Correction dose rounded to the nearest 0.5 unit.
  double? get correctionRounded => _round05(correctionUnits);

  /// Total dose rounded to the nearest 0.5 unit.
  double? get totalRounded => _round05(totalBolusUnits);

  /// True when a current blood-glucose reading was entered and is dangerously
  /// low — the user should treat the low before considering any insulin.
  bool get isLowGlucose => bgStatus == BgStatus.low;
}

/// Pure, side-effect-free engine for evidence-based diabetes meal guidance.
///
/// All formulas below come from established clinical practice. Sources:
///   • Carbohydrate counting / meal bolus = carbs ÷ ICR — American Diabetes
///     Association (ADA) Standards of Care; standard in insulin-pump therapy.
///   • Pre-bolus timing — rapid-acting analogues (insulin aspart/lispro/
///     glulisine) have an onset of ~15 min and a peak at ~60–90 min, while
///     post-meal glucose also peaks at ~60–90 min. Injecting ~15–20 min before
///     a high-glycaemic meal aligns insulin action with the glucose rise and
///     reduces the post-meal spike (Cobry et al., Diabetes Technol Ther 2010;
///     Slattery et al., Diabet Med 2018 review).
///   • Fat/protein/fibre slow gastric emptying, delaying and prolonging the
///     glucose rise; very high-fat/protein meals need a shorter or split bolus
///     (Bell et al., Diabetes Care 2015;38:1008–1015).
///   • Food order — eating vegetables and protein BEFORE carbohydrate lowers
///     post-meal glucose by up to ~37% and reduces insulin (Shukla et al.,
///     Diabetes Care 2015;38:e98–e99).
///   • Correction dose — the "1800 rule": for rapid-acting insulin the Insulin
///     Sensitivity Factor (ISF, mg/dL per unit) ≈ 1800 ÷ total daily dose;
///     correction = (current BG − target BG) ÷ ISF (the "100 rule" / ÷ 100
///     gives the equivalent mmol/L factor). ADA / AACE bolus-calculator
///     standard.
///
/// IMPORTANT: every output is a generic educational estimate for a single
/// meal. It does NOT account for insulin-on-board, activity, illness, or
/// individual insulin response, and must never replace a clinician's
/// personalised plan. Correction dosing requires an accurate, recent
/// fingerstick/CGM reading and an ISF kept up to date with the user's doctor.
abstract final class DiabetesAdvisor {
  /// Standard reference: a mixed meal in a person with diabetes peaks roughly
  /// 60–90 min after eating. We model 45–90 min based on how carb-dominant
  /// (fast) vs fat/protein/fibre-rich (slow) the meal is.
  static const int _peakFastMinutes = 45;
  static const int _peakSlowMinutes = 90;

  /// Recommended pre-bolus window: 0 min (slow meals — inject at the first
  /// bite or split the dose) up to 20 min (fast, high-GI meals).
  static const int _maxPrebolusMinutes = 20;

  /// Blood-glucose thresholds (mg/dL) from ADA guidance.
  static const double _hypoMgdl = 70.0;   // < 70 = hypoglycaemia
  static const double _inRangeMaxMgdl = 180.0; // post-meal upper range
  static const double _highMgdl = 250.0;  // ≥ 250 = check ketones

  static DiabetesAdvice compute({
    required MealNutrition meal,
    required double icr,
    double isf = 0,
    double targetBgMgdl = 120,
    double? currentBgMgdl,
  }) {
    final hasIcr = icr > 0;
    final hasIsf = isf > 0;
    final carbs = meal.carbsG;

    // ── 1. Meal bolus — standard carbohydrate counting ───────────────────
    final double? bolus = (hasIcr && carbs > 0) ? carbs / icr : (hasIcr ? 0 : null);

    // ── 1b. Correction dose — "1800 rule" / Insulin Sensitivity Factor ───
    // Correction (units) = (current BG − target BG) ÷ ISF. Requires both a
    // current reading and a configured ISF. May be negative (reduce dose) if
    // the reading is below target.
    BgStatus? bgStatus;
    String? bgWarning;
    double? correction;
    if (currentBgMgdl != null) {
      bgStatus = currentBgMgdl < _hypoMgdl
          ? BgStatus.low
          : currentBgMgdl <= _inRangeMaxMgdl
              ? BgStatus.inRange
              : currentBgMgdl < _highMgdl
                  ? BgStatus.elevated
                  : BgStatus.high;

      if (hasIsf) {
        correction = (currentBgMgdl - targetBgMgdl) / isf;
      }

      switch (bgStatus) {
        case BgStatus.low:
          bgWarning = 'Your blood glucose is LOW. Treat the low with fast-acting '
              'carbohydrate first and recheck before eating or dosing. Do NOT '
              'take a correction dose now.';
          // Never recommend a positive correction while low.
          if (correction != null && correction > 0) correction = 0;
        case BgStatus.high:
          bgWarning = 'Your blood glucose is HIGH. Follow your sick-day / ketone '
              'plan and check for ketones. Confirm this dose with your care team.';
        case BgStatus.elevated:
          bgWarning = 'Above target — a correction dose is included below.';
        case BgStatus.inRange:
          bgWarning = 'In range — little or no correction needed.';
      }
    }

    // ── 1c. Total dose = meal bolus + correction (never below zero) ──────
    double? total;
    if (hasIcr) {
      total = (bolus ?? 0) + (correction ?? 0);
      if (total < 0) total = 0;
    }

    // ── 2. How fast will glucose rise? ───────────────────────────────────
    // Fat, fibre and protein slow gastric emptying (fibre and fat most).
    // "speed" → 0 (very slow / no carbs) … 1 (pure fast carbohydrate).
    final slowing = meal.fatG * 2.0 + meal.fiberG * 3.0 + meal.proteinG * 1.0;
    final speed = carbs <= 0 ? 0.0 : (carbs / (carbs + slowing)).clamp(0.0, 1.0);

    final SpikeSpeed spikeSpeed = speed > 0.66
        ? SpikeSpeed.fast
        : (speed > 0.4 ? SpikeSpeed.moderate : SpikeSpeed.slow);

    // ── 3. Time to glucose peak (minutes after eating) ───────────────────
    // Faster meals peak sooner. Linear map between slow and fast bounds.
    final timeToPeak =
        (_peakSlowMinutes - (_peakSlowMinutes - _peakFastMinutes) * speed)
            .round();

    // ── 4. Pre-bolus timing ──────────────────────────────────────────────
    // Inject earlier for fast meals so insulin onset (~15 min) meets the
    // glucose rise; little or no pre-bolus for slow, fatty meals.
    int prebolus = (speed * _maxPrebolusMinutes).round();
    if (carbs < 5) prebolus = 0; // negligible carbs → no carb bolus needed
    prebolus = prebolus.clamp(0, _maxPrebolusMinutes);

    // ── 5. Plain-language timing message ─────────────────────────────────
    final String timing;
    if (bgStatus == BgStatus.low) {
      timing = 'Treat your low blood glucose first. Do not pre-bolus or inject '
          'until your glucose is back in range.';
    } else if (!hasIcr) {
      timing = 'Set your Insulin-to-Carb Ratio to get a personalised dose.';
    } else if (carbs < 5) {
      timing = 'Very low carbohydrate — typically no meal bolus is needed for '
          'this meal. Follow your own plan.';
    } else if (spikeSpeed == SpikeSpeed.slow) {
      timing = 'This meal is high in fat, protein or fibre, so glucose rises '
          'slowly. Inject at the first bite (or split the dose), as a long '
          'pre-bolus could cause a low before the food acts.';
    } else if (spikeSpeed == SpikeSpeed.moderate) {
      timing = 'Inject about $prebolus min before eating so the insulin starts '
          'working as your glucose begins to rise (~$timeToPeak min after the '
          'meal).';
    } else {
      timing = 'This is a fast, high-carb meal. Inject about $prebolus min '
          'before the first bite to blunt a sharp spike (expected ~$timeToPeak '
          'min after eating).';
    }

    // ── 6. Food-order ("preload") guidance ───────────────────────────────
    final foodOrder =
        'Eat vegetables and protein first and save the carbs for last. '
        'Finishing carbohydrate at the end of the meal can lower your '
        'post-meal glucose by up to ~30% (Shukla et al., Diabetes Care 2015).';

    return DiabetesAdvice(
      icrConfigured: hasIcr,
      isfConfigured: hasIsf,
      mealCarbsG: carbs,
      bolusUnits: bolus,
      correctionUnits: correction,
      totalBolusUnits: total,
      icr: icr,
      bgStatus: bgStatus,
      bgWarning: bgWarning,
      prebolusMinutes: prebolus,
      timeToPeakMinutes: timeToPeak,
      spikeSpeed: spikeSpeed,
      timingMessage: timing,
      foodOrderTip: foodOrder,
    );
  }

  /// Estimate the macronutrients of a meal from its detected foods by looking
  /// each item up in the local food database. Mirrors the logic used by the
  /// daily-intake aggregator so the numbers stay consistent.
  static Future<MealNutrition> estimateMealNutrition(
      List<DetectedFood> foods) async {
    double carbs = 0, protein = 0, fat = 0, fiber = 0;
    const aliases = {'chicken duck': 'chicken'};

    for (final food in foods) {
      var lookup = food.label;
      if (aliases.containsKey(lookup.toLowerCase())) {
        lookup = aliases[lookup.toLowerCase()]!;
      }
      final data = await DatabaseService.instance.getFoodByLabel(lookup);
      if (data != null && data.kcalPer100g > 0) {
        final avgCal = (food.caloriesMin + food.caloriesMax) / 2;
        final weightG = avgCal / (data.kcalPer100g / 100);
        carbs += weightG * data.carbsPer100g / 100;
        protein += weightG * data.proteinPer100g / 100;
        fat += weightG * data.fatPer100g / 100;
        fiber += estimateNutrientsForFood(
          category: data.category,
          weightG: weightG,
        ).fiberG;
      }
    }
    return MealNutrition(
      carbsG: carbs,
      proteinG: protein,
      fatG: fat,
      fiberG: fiber,
    );
  }
}
