import 'diabetes_constants.dart';

/// Safe, lossless-as-possible conversions between blood-glucose units.
///
/// The whole bolus subsystem stores and computes in **mg/dL** internally and
/// only converts at the UI boundary. Rounding here is for *display only*;
/// callers that need precision should keep the raw double.
///
/// mg/dL → mmol/L: divide by 18.0182
/// mmol/L → mg/dL: multiply by 18.0182
class GlucoseConversion {
  GlucoseConversion._();

  /// Convert a millimoles-per-litre value to milligrams-per-decilitre.
  static double mmolToMgdl(double mmol) =>
      mmol * DiabetesConstants.mgdlPerMmol;

  /// Convert a milligrams-per-decilitre value to millimoles-per-litre.
  static double mgdlToMmol(double mgdl) =>
      mgdl / DiabetesConstants.mgdlPerMmol;

  /// Format a canonical mg/dL value for display in [unitIsMmol]'s unit.
  /// mmol/L is shown with 1 decimal; mg/dL as a whole number. Display only.
  static String formatForDisplay(double mgdl, {required bool unitIsMmol}) {
    if (unitIsMmol) {
      return mgdlToMmol(mgdl).toStringAsFixed(1);
    }
    return mgdl.round().toString();
  }
}
