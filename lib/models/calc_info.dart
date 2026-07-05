/// Identifies a calculation feature that has an explainer / provenance card.
enum CalcInfoId {
  dailyCalories,
  macroTargets,
  microTargets,
  plateScore,
  bodyMapScore,
  glycemicLoad,
  bolusEstimate,
  insulinOnBoard,
  insulinRatios,
  recommendations,
  streak,
  weeklyBadges,
  recipeGoalMatch,
}

/// Localised, sourced explanation for a calculation shown in the app.
///
/// Used by the reusable info card / ⓘ button so every number the app derives
/// can show: what formula produced it, a plain-language explanation, why the
/// method is legitimate, and a citation the user can verify.
class CalcInfo {
  const CalcInfo({
    required this.id,
    required this.title,
    required this.explanation,
    required this.legitimacy,
    required this.sourceLabel,
  });

  final CalcInfoId id;

  /// Short name of the formula / metric (e.g. "Daily calorie target").
  final String title;

  /// Plain-language description of how the number is produced.
  final String explanation;

  /// Why the method is trustworthy (standard / guideline it follows).
  final String legitimacy;

  /// Human-readable citation label (institution / publication).
  final String sourceLabel;

  /// Stable key used to persist the "already auto-shown" flag.
  String get seenPrefKey => 'calc_info_seen_${id.name}';
}
