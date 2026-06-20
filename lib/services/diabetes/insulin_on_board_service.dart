import '../../models/insulin_dose_log.dart';

/// Insulin-on-board (IOB) estimation.
///
/// IOB is the amount of previously injected rapid-acting insulin still active
/// in the body. Subtracting it from a new dose helps avoid "insulin stacking".
///
/// ⚠️ This uses a deliberately CONSERVATIVE **linear decay** model:
///     remainingFraction = max(0, 1 - elapsedHours / insulinActionDurationHours)
///     iob = Σ doseUnits * remainingFraction
///
/// Real insulin action is a curved (bi-exponential) profile that peaks then
/// tails off; a linear model is a simplification.
/// TODO(clinical-review): validate the IOB model and replace with a clinically
/// validated insulin-action curve (e.g. Walsh/exponential models) before
/// production. Document the chosen DIA and curve with a clinician.
class InsulinOnBoardService {
  InsulinOnBoardService._();

  /// Compute total active insulin (units) at [now] from [doses], given the
  /// insulin action duration [actionDurationHours].
  ///
  /// Only confirmed doses contribute. Doses with non-positive units contribute
  /// zero, and doses already fully decayed contribute zero. A future-dated dose
  /// (device clock skew or a just-logged entry) is treated as taken now and
  /// counted at full strength — the safe, conservative direction.
  static double calculateIob({
    required List<InsulinDoseLog> doses,
    required double actionDurationHours,
    required DateTime now,
  }) {
    if (actionDurationHours <= 0) return 0; // guard divide-by-zero
    var iob = 0.0;
    for (final d in doses) {
      if (!d.confirmed || d.units <= 0) continue;
      final elapsedHours = now.difference(d.timestamp).inSeconds / 3600.0;
      // Clock-skew / just-logged safety guard: a future-dated dose would
      // otherwise be silently dropped, UNDER-counting IOB and risking insulin
      // stacking. Treat any future dose as if taken now (full strength) — the
      // conservative direction (more IOB -> less recommended insulin).
      final activeHours = elapsedHours < 0 ? 0.0 : elapsedHours;
      final remainingFraction = 1.0 - (activeHours / actionDurationHours);
      if (remainingFraction <= 0) continue; // fully decayed
      iob += d.units * remainingFraction;
    }
    return iob;
  }
}
