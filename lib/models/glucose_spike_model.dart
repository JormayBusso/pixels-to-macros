import 'dart:math' as math;

/// Educational glucose-spike risk estimate.
///
/// Estimates a plausible post-prandial glucose-rise shape for a meal based on:
/// - Net carbohydrates (total carbs − fiber)
/// - Glycemic index (GI) of each food item
/// - Protein (slows gastric emptying)
/// - Fat (slows gastric emptying)
/// - Fiber (slows absorption)
///
/// Returns a list of (minute, mg/dL delta) points from t=0..180 min.
///
/// This is not a validated clinical prediction model. Individual responses vary
/// by diabetes type, medication, insulin timing, exercise, illness, stress,
/// menstrual cycle, gastroparesis, sleep, and many other factors. Treat it as a
/// meal-quality warning aid only; CGM/fingerstick data and clinician-set insulin
/// settings remain the source of truth.
class GlucoseSpikeModel {
  GlucoseSpikeModel._();

  /// Estimate the glucose delta curve for a meal.
  ///
  /// [mealItems] — list of (netCarbsG, gi, proteinG, fatG, fiberG) tuples.
  /// Returns 181 points (minute 0 to 180), each an estimated mg/dL rise above
  /// fasting baseline.
  static List<double> predict(List<MealItemInput> mealItems) {
    if (mealItems.isEmpty) return List.filled(181, 0);

    // Aggregate meal-level values.
    double totalNetCarbs = 0;
    double weightedGI = 0;
    double totalProtein = 0;
    double totalFat = 0;
    double totalFiber = 0;

    for (final item in mealItems) {
      totalNetCarbs += item.netCarbsG;
      weightedGI += item.netCarbsG * item.gi;
      totalProtein += item.proteinG;
      totalFat += item.fatG;
      totalFiber += item.fiberG;
    }

    if (totalNetCarbs <= 0) return List.filled(181, 0);

    final mealGI = weightedGI / totalNetCarbs;

    // ── Peak time estimation ──
    // Base peak: 30-45 min for pure glucose. High GI → earlier, low GI → later.
    double basePeakMin = 30 + (100 - mealGI) * 0.4; // GI=70→42min, GI=30→58min

    // Fat/protein/fiber each slow gastric emptying.
    final fatDelay = math.min(totalFat * 0.5, 20.0); // up to +20 min
    final proteinDelay = math.min(totalProtein * 0.3, 15.0); // up to +15 min
    final fiberDelay = math.min(totalFiber * 0.8, 15.0); // up to +15 min
    final peakMin = basePeakMin + fatDelay + proteinDelay + fiberDelay;

    // ── Peak magnitude estimation ──
    // Simple educational heuristic: Δglucose ≈ netCarbs × GI / 100 × sensitivity.
    // This is intentionally capped and should not be used for dosing decisions.
    const sensitivity = 3.5;
    final glycemicCarbs = totalNetCarbs * mealGI / 100;
    double rawPeak = glycemicCarbs * sensitivity;

    // Damping from protein/fat (second meal effect).
    final dampFactor = 1.0 / (1.0 + totalProtein * 0.008 + totalFat * 0.006);
    rawPeak *= dampFactor;

    // Cap to physiological range (non-diabetic: max ~60-80, T2D: up to ~140).
    final peakMgDl = rawPeak.clamp(0.0, 160.0);

    // ── Curve shape: modified gamma function ──
    // glucose(t) = A × (t/tPeak)^α × exp(α × (1 - t/tPeak))
    // α controls sharpness: higher GI → sharper peak (higher α).
    final alpha = 2.0 + (mealGI - 30) / 40; // ~2 for GI=30, ~3.75 for GI=70.

    final curve = List<double>.generate(181, (t) {
      if (t == 0) return 0;
      final ratio = t / peakMin;
      final value =
          peakMgDl * math.pow(ratio, alpha) * math.exp(alpha * (1 - ratio));
      return value.clamp(0.0, 160.0);
    });

    return curve;
  }

  /// Returns a human-friendly spike summary.
  static SpikeSummary summarize(List<double> curve) {
    double peak = 0;
    int peakMin = 0;
    for (int t = 0; t < curve.length; t++) {
      if (curve[t] > peak) {
        peak = curve[t];
        peakMin = t;
      }
    }

    // Time to return to <10% of peak.
    int returnMin = 180;
    for (int t = peakMin; t < curve.length; t++) {
      if (curve[t] < peak * 0.1) {
        returnMin = t;
        break;
      }
    }

    final severity = peak < 30
        ? SpikeSeverity.low
        : peak < 60
            ? SpikeSeverity.moderate
            : SpikeSeverity.high;

    return SpikeSummary(
      peakDeltaMgDl: peak,
      peakAtMinute: peakMin,
      returnToBaselineMinute: returnMin,
      severity: severity,
    );
  }
}

class MealItemInput {
  const MealItemInput({
    required this.netCarbsG,
    required this.gi,
    this.proteinG = 0,
    this.fatG = 0,
    this.fiberG = 0,
  });
  final double netCarbsG;
  final double gi; // 0–100
  final double proteinG;
  final double fatG;
  final double fiberG;
}

enum SpikeSeverity { low, moderate, high }

class SpikeSummary {
  const SpikeSummary({
    required this.peakDeltaMgDl,
    required this.peakAtMinute,
    required this.returnToBaselineMinute,
    required this.severity,
  });
  final double peakDeltaMgDl;
  final int peakAtMinute;
  final int returnToBaselineMinute;
  final SpikeSeverity severity;

  String get peakTimeLabel => '~$peakAtMinute min after eating';
  String get durationLabel =>
      '~${returnToBaselineMinute - peakAtMinute} min elevated';
}
