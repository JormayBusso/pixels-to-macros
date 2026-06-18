/// An immutable audit record of one bolus calculation, for user review.
///
/// Privacy: this is sensitive health data. It is stored using the app's
/// existing local SQLite database and is never written to logs/console. Error
/// messages elsewhere must not expose insulin settings.
class BolusAuditRecord {
  const BolusAuditRecord({
    this.id,
    required this.calculationId,
    required this.timestamp,
    this.mealId,
    required this.carbsG,
    this.currentGlucoseMgdl,
    required this.glucoseUnit,
    this.targetGlucoseMgdl,
    this.icrUsed,
    this.isfUsed,
    required this.mealBolusComponent,
    required this.correctionComponent,
    required this.iobComponent,
    required this.rawBolus,
    required this.roundedBolus,
    required this.maxBolus,
    required this.warnings,
    required this.settingsVersion,
    required this.userConfirmed,
    this.actualDoseLogged = false,
    this.actualDoseUnits,
    this.actualDoseTimestamp,
  });

  final int? id;

  /// Stable unique id for this calculation (UUID-like string).
  final String calculationId;
  final DateTime timestamp;
  final int? mealId;

  final double carbsG;
  final double? currentGlucoseMgdl;

  /// 'mgdl' or 'mmol' — the unit the user was working in.
  final String glucoseUnit;
  final double? targetGlucoseMgdl;
  final double? icrUsed;
  final double? isfUsed;

  final double mealBolusComponent;
  final double correctionComponent;
  final double iobComponent;
  final double rawBolus;
  final double roundedBolus;
  final double maxBolus;

  /// Semicolon-joined warning identifiers (no sensitive values).
  final String warnings;
  final int settingsVersion;

  /// Whether the user accepted the final "I am responsible" confirmation.
  final bool userConfirmed;

  final bool actualDoseLogged;
  final double? actualDoseUnits;
  final DateTime? actualDoseTimestamp;

  BolusAuditRecord copyWith({
    int? id,
    bool? actualDoseLogged,
    double? actualDoseUnits,
    DateTime? actualDoseTimestamp,
  }) =>
      BolusAuditRecord(
        id: id ?? this.id,
        calculationId: calculationId,
        timestamp: timestamp,
        mealId: mealId,
        carbsG: carbsG,
        currentGlucoseMgdl: currentGlucoseMgdl,
        glucoseUnit: glucoseUnit,
        targetGlucoseMgdl: targetGlucoseMgdl,
        icrUsed: icrUsed,
        isfUsed: isfUsed,
        mealBolusComponent: mealBolusComponent,
        correctionComponent: correctionComponent,
        iobComponent: iobComponent,
        rawBolus: rawBolus,
        roundedBolus: roundedBolus,
        maxBolus: maxBolus,
        warnings: warnings,
        settingsVersion: settingsVersion,
        userConfirmed: userConfirmed,
        actualDoseLogged: actualDoseLogged ?? this.actualDoseLogged,
        actualDoseUnits: actualDoseUnits ?? this.actualDoseUnits,
        actualDoseTimestamp: actualDoseTimestamp ?? this.actualDoseTimestamp,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'calculation_id': calculationId,
        'timestamp': timestamp.toIso8601String(),
        'meal_id': mealId,
        'carbs_g': carbsG,
        'current_glucose_mgdl': currentGlucoseMgdl,
        'glucose_unit': glucoseUnit,
        'target_glucose_mgdl': targetGlucoseMgdl,
        'icr_used': icrUsed,
        'isf_used': isfUsed,
        'meal_bolus_component': mealBolusComponent,
        'correction_component': correctionComponent,
        'iob_component': iobComponent,
        'raw_bolus': rawBolus,
        'rounded_bolus': roundedBolus,
        'max_bolus': maxBolus,
        'warnings': warnings,
        'settings_version': settingsVersion,
        'user_confirmed': userConfirmed ? 1 : 0,
        'actual_dose_logged': actualDoseLogged ? 1 : 0,
        'actual_dose_units': actualDoseUnits,
        'actual_dose_timestamp': actualDoseTimestamp?.toIso8601String(),
      };

  factory BolusAuditRecord.fromMap(Map<String, dynamic> m) => BolusAuditRecord(
        id: m['id'] as int?,
        calculationId: m['calculation_id'] as String,
        timestamp: DateTime.parse(m['timestamp'] as String),
        mealId: m['meal_id'] as int?,
        carbsG: (m['carbs_g'] as num).toDouble(),
        currentGlucoseMgdl: (m['current_glucose_mgdl'] as num?)?.toDouble(),
        glucoseUnit: m['glucose_unit'] as String,
        targetGlucoseMgdl: (m['target_glucose_mgdl'] as num?)?.toDouble(),
        icrUsed: (m['icr_used'] as num?)?.toDouble(),
        isfUsed: (m['isf_used'] as num?)?.toDouble(),
        mealBolusComponent: (m['meal_bolus_component'] as num).toDouble(),
        correctionComponent: (m['correction_component'] as num).toDouble(),
        iobComponent: (m['iob_component'] as num).toDouble(),
        rawBolus: (m['raw_bolus'] as num).toDouble(),
        roundedBolus: (m['rounded_bolus'] as num).toDouble(),
        maxBolus: (m['max_bolus'] as num).toDouble(),
        warnings: m['warnings'] as String? ?? '',
        settingsVersion: (m['settings_version'] as num).toInt(),
        userConfirmed: (m['user_confirmed'] as int?) == 1,
        actualDoseLogged: (m['actual_dose_logged'] as int?) == 1,
        actualDoseUnits: (m['actual_dose_units'] as num?)?.toDouble(),
        actualDoseTimestamp: m['actual_dose_timestamp'] == null
            ? null
            : DateTime.parse(m['actual_dose_timestamp'] as String),
      );
}
