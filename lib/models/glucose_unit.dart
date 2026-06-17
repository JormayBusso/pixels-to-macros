/// Blood-glucose measurement unit. The app stores all glucose values
/// canonically in mg/dL and converts to mmol/L only for display/input.
enum GlucoseUnit { mgdl, mmoll }

/// Standard clinical conversion factor between mg/dL and mmol/L.
/// 1 mmol/L = 18.0182 mg/dL (rounded to 18.0 as used by most diabetes tools).
const double kMgdlPerMmol = 18.0;

extension GlucoseUnitX on GlucoseUnit {
  String get label => switch (this) {
        GlucoseUnit.mgdl => 'mg/dL',
        GlucoseUnit.mmoll => 'mmol/L',
      };

  /// Persisted string value.
  String get dbValue => switch (this) {
        GlucoseUnit.mgdl => 'mgdl',
        GlucoseUnit.mmoll => 'mmoll',
      };

  static GlucoseUnit fromDbValue(String? v) =>
      v == 'mmoll' ? GlucoseUnit.mmoll : GlucoseUnit.mgdl;

  /// Convert a canonical mg/dL value into this unit (for display/input).
  double fromMgdl(double mgdl) =>
      this == GlucoseUnit.mmoll ? mgdl / kMgdlPerMmol : mgdl;

  /// Convert a value expressed in this unit back into canonical mg/dL.
  double toMgdl(double value) =>
      this == GlucoseUnit.mmoll ? value * kMgdlPerMmol : value;

  /// Sensible number of decimal places for input/display in this unit.
  int get decimals => this == GlucoseUnit.mmoll ? 1 : 0;

  /// Format a canonical mg/dL value for display in this unit, without the unit
  /// suffix (e.g. "120" for mg/dL, "6.7" for mmol/L).
  String formatValue(double mgdl) =>
      fromMgdl(mgdl).toStringAsFixed(decimals);

  /// Format a canonical mg/dL value with the unit suffix (e.g. "120 mg/dL").
  String formatWithUnit(double mgdl) => '${formatValue(mgdl)} $label';
}
