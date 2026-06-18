/// Blood-glucose measurement unit.
///
/// Blood glucose is reported in two units worldwide:
///   • mg/dL  — United States, Germany, France, Japan, …
///   • mmol/L — UK, Canada, Australia, most of Europe, …
///
/// Conversion is a fixed molar factor for glucose:
///   mmol/L = mg/dL ÷ 18.0182   (1 mmol/L ≈ 18.0182 mg/dL)
///
/// The app stores every glucose value canonically in **mg/dL** and only
/// converts at the UI boundary, so the clinical formulas never have to care
/// which unit the user prefers.
enum GlucoseUnit {
  mgdl,
  mmoll;

  /// Exact molar conversion factor for glucose (g/mol based).
  static const double mgdlPerMmol = 18.0182;

  String get dbValue => name;

  String get label => switch (this) {
        GlucoseUnit.mgdl => 'mg/dL',
        GlucoseUnit.mmoll => 'mmol/L',
      };

  /// Number of decimal places typically shown for this unit.
  int get decimals => this == GlucoseUnit.mmoll ? 1 : 0;

  /// A sensible step for stepper/slow-typed entry.
  double get inputStep => this == GlucoseUnit.mmoll ? 0.1 : 1.0;

  /// Convert a value expressed in THIS unit into canonical mg/dL.
  double toMgdl(double value) =>
      this == GlucoseUnit.mmoll ? value * mgdlPerMmol : value;

  /// Convert a canonical mg/dL value into THIS unit.
  double fromMgdl(double mgdl) =>
      this == GlucoseUnit.mmoll ? mgdl / mgdlPerMmol : mgdl;

  /// Format a canonical mg/dL value as a plain number in THIS unit.
  String formatValue(double mgdl) {
    final v = fromMgdl(mgdl);
    return this == GlucoseUnit.mmoll
        ? v.toStringAsFixed(1)
        : v.round().toString();
  }

  /// Format a canonical mg/dL value with the unit suffix, e.g. "120 mg/dL".
  String formatWithUnit(double mgdl) => '${formatValue(mgdl)} $label';

  static GlucoseUnit fromDbValue(String? v) => GlucoseUnit.values.firstWhere(
        (e) => e.name == v,
        orElse: () => GlucoseUnit.mgdl,
      );
}
