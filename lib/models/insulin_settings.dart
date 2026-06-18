import '../core/diabetes/diabetes_constants.dart';

/// Diabetes type for the safety survey. Reference/context only — never used in
/// dose math.
enum DiabetesType {
  type1,
  type2,
  gestational,
  other,
  preferNotToSay;

  String get dbValue => name;
  String get label => switch (this) {
        DiabetesType.type1 => 'Type 1',
        DiabetesType.type2 => 'Type 2',
        DiabetesType.gestational => 'Gestational',
        DiabetesType.other => 'Other',
        DiabetesType.preferNotToSay => 'Prefer not to say',
      };

  static DiabetesType fromDbValue(String? v) => values.firstWhere(
        (e) => e.name == v,
        orElse: () => DiabetesType.preferNotToSay,
      );
}

/// Blood-glucose unit the user works in. Glucose is stored canonically in
/// mg/dL; this only affects what the user enters/sees.
enum BgUnit {
  mgdl,
  mmol;

  bool get isMmol => this == BgUnit.mmol;
  String get dbValue => name;
  String get label => this == BgUnit.mmol ? 'mmol/L' : 'mg/dL';

  static BgUnit fromDbValue(String? v) => values.firstWhere(
        (e) => e.name == v,
        orElse: () => BgUnit.mgdl,
      );
}

/// How the user delivers insulin. Reference/context only.
enum InsulinDeliveryMethod {
  pump,
  pen,
  syringe,
  other;

  String get dbValue => name;
  String get label => switch (this) {
        InsulinDeliveryMethod.pump => 'Insulin pump',
        InsulinDeliveryMethod.pen => 'Insulin pen',
        InsulinDeliveryMethod.syringe => 'Syringe',
        InsulinDeliveryMethod.other => 'Other',
      };

  static InsulinDeliveryMethod fromDbValue(String? v) => values.firstWhere(
        (e) => e.name == v,
        orElse: () => InsulinDeliveryMethod.pen,
      );
}

/// A time-of-day block holding a single insulin parameter (ICR or ISF).
///
/// Times are minutes-since-midnight in local time, inclusive [startMinute] to
/// inclusive [endMinute] (e.g. 00:00–10:59 = 0..659). [value] is interpreted
/// by the owning list (grams/unit for ICR, glucose-lowered/unit for ISF).
class InsulinTimeBlock {
  const InsulinTimeBlock({
    required this.startMinute,
    required this.endMinute,
    required this.value,
  });

  final int startMinute;
  final int endMinute;
  final double value;

  /// Whether a given minute-of-day falls inside this (inclusive) block.
  bool contains(int minuteOfDay) =>
      minuteOfDay >= startMinute && minuteOfDay <= endMinute;

  /// Whether this block's time range overlaps [other].
  bool overlaps(InsulinTimeBlock other) =>
      startMinute <= other.endMinute && other.startMinute <= endMinute;

  String get startLabel => _fmt(startMinute);
  String get endLabel => _fmt(endMinute);

  static String _fmt(int m) {
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$h:$mm';
  }

  Map<String, dynamic> toMap() => {
        'startMinute': startMinute,
        'endMinute': endMinute,
        'value': value,
      };

  factory InsulinTimeBlock.fromMap(Map<String, dynamic> m) => InsulinTimeBlock(
        startMinute: (m['startMinute'] as num).toInt(),
        endMinute: (m['endMinute'] as num).toInt(),
        value: (m['value'] as num).toDouble(),
      );

  /// Parse from a "HH:mm" pair (used by the survey UI / spec examples).
  factory InsulinTimeBlock.fromClock({
    required String startTime,
    required String endTime,
    required double value,
  }) =>
      InsulinTimeBlock(
        startMinute: _parseClock(startTime),
        endMinute: _parseClock(endTime),
        value: value,
      );

  static int _parseClock(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}

/// All persisted diabetes/insulin settings backing Bolus Calculator Mode.
///
/// ⚠️ The app NEVER invents any of these values. Every insulin parameter is
/// entered manually by the user and confirmed to come from their clinician,
/// pump, diabetes educator, or official care plan. See [userConfirmedAt].
///
/// Glucose values ([targetGlucoseMgdl], thresholds, ISF) are stored canonically
/// in mg/dL regardless of [glucoseUnit].
class InsulinSettings {
  const InsulinSettings({
    this.diabetesEnabled = false,
    this.usesInsulin = false,
    this.bolusCalculatorEnabled = false,
    this.diabetesType = DiabetesType.preferNotToSay,
    this.glucoseUnit = BgUnit.mgdl,
    this.usesCgm = false,
    this.usesPump = false,
    this.insulinDeliveryMethod = InsulinDeliveryMethod.pen,
    // Safety review
    this.surveyLastCompletedAt,
    this.surveyNextDueAt,
    this.surveySnoozedUntil,
    this.userConfirmedAt,
    this.settingsVersion = DiabetesConstants.settingsVersion,
    this.createdAt,
    this.updatedAt,
    // Glucose targets (mg/dL canonical)
    this.targetGlucoseMgdl,
    this.targetGlucoseMinMgdl,
    this.targetGlucoseMaxMgdl,
    this.hypoThresholdMgdl,
    this.hyperThresholdMgdl,
    // Insulin settings
    this.icrBlocks = const [],
    this.isfBlocks = const [],
    this.insulinActionDurationHours,
    this.insulinName,
    this.maxSingleBolusUnits,
    this.minBolusIncrement,
    this.correctionEnabled = false,
    this.mealBolusEnabled = false,
    this.iobEnabled = false,
    // Reference only — NEVER used to prescribe ICR/ISF.
    this.totalDailyInsulinDoseOptional,
  });

  // General
  final bool diabetesEnabled;
  final bool usesInsulin;
  final bool bolusCalculatorEnabled;
  final DiabetesType diabetesType;
  final BgUnit glucoseUnit;
  final bool usesCgm;
  final bool usesPump;
  final InsulinDeliveryMethod insulinDeliveryMethod;

  // Safety review
  final DateTime? surveyLastCompletedAt;
  final DateTime? surveyNextDueAt;
  final DateTime? surveySnoozedUntil;

  /// Timestamp the user accepted the confirmation checkbox attesting the
  /// settings came from a clinical source. Required before any calculation.
  final DateTime? userConfirmedAt;
  final int settingsVersion;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Glucose targets (mg/dL)
  final double? targetGlucoseMgdl;
  final double? targetGlucoseMinMgdl;
  final double? targetGlucoseMaxMgdl;
  final double? hypoThresholdMgdl;
  final double? hyperThresholdMgdl;

  // Insulin settings
  final List<InsulinTimeBlock> icrBlocks;
  final List<InsulinTimeBlock> isfBlocks;
  final double? insulinActionDurationHours;
  final String? insulinName;
  final double? maxSingleBolusUnits;
  final double? minBolusIncrement;
  final bool correctionEnabled;
  final bool mealBolusEnabled;
  final bool iobEnabled;

  /// Total daily insulin dose. Stored for the user's reference ONLY. It is
  /// intentionally never read by the bolus math, because deriving a personal
  /// ICR/ISF from TDD (e.g. the "500"/"1800" rules) is a population estimate,
  /// not a prescription. See [InsulinSettings] doc and tests.
  /// TODO(clinical-review): if a TDD-based educational helper is ever added,
  /// it must be clearly labelled as an estimate and require clinician
  /// confirmation before any value is saved as a real setting.
  final double? totalDailyInsulinDoseOptional;

  /// Active ICR (grams of carb per unit) for [minuteOfDay], or null if no block
  /// covers that time.
  double? icrForMinute(int minuteOfDay) => _valueForMinute(icrBlocks, minuteOfDay);

  /// Active ISF (mg/dL lowered per unit) for [minuteOfDay], or null.
  double? isfForMinute(int minuteOfDay) => _valueForMinute(isfBlocks, minuteOfDay);

  static double? _valueForMinute(List<InsulinTimeBlock> blocks, int minute) {
    for (final b in blocks) {
      if (b.contains(minute)) return b.value;
    }
    return null;
  }

  InsulinSettings copyWith({
    bool? diabetesEnabled,
    bool? usesInsulin,
    bool? bolusCalculatorEnabled,
    DiabetesType? diabetesType,
    BgUnit? glucoseUnit,
    bool? usesCgm,
    bool? usesPump,
    InsulinDeliveryMethod? insulinDeliveryMethod,
    DateTime? surveyLastCompletedAt,
    DateTime? surveyNextDueAt,
    DateTime? surveySnoozedUntil,
    DateTime? userConfirmedAt,
    int? settingsVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? targetGlucoseMgdl,
    double? targetGlucoseMinMgdl,
    double? targetGlucoseMaxMgdl,
    double? hypoThresholdMgdl,
    double? hyperThresholdMgdl,
    List<InsulinTimeBlock>? icrBlocks,
    List<InsulinTimeBlock>? isfBlocks,
    double? insulinActionDurationHours,
    String? insulinName,
    double? maxSingleBolusUnits,
    double? minBolusIncrement,
    bool? correctionEnabled,
    bool? mealBolusEnabled,
    bool? iobEnabled,
    double? totalDailyInsulinDoseOptional,
    bool clearSnooze = false,
  }) {
    return InsulinSettings(
      diabetesEnabled: diabetesEnabled ?? this.diabetesEnabled,
      usesInsulin: usesInsulin ?? this.usesInsulin,
      bolusCalculatorEnabled:
          bolusCalculatorEnabled ?? this.bolusCalculatorEnabled,
      diabetesType: diabetesType ?? this.diabetesType,
      glucoseUnit: glucoseUnit ?? this.glucoseUnit,
      usesCgm: usesCgm ?? this.usesCgm,
      usesPump: usesPump ?? this.usesPump,
      insulinDeliveryMethod:
          insulinDeliveryMethod ?? this.insulinDeliveryMethod,
      surveyLastCompletedAt:
          surveyLastCompletedAt ?? this.surveyLastCompletedAt,
      surveyNextDueAt: surveyNextDueAt ?? this.surveyNextDueAt,
      surveySnoozedUntil:
          clearSnooze ? null : (surveySnoozedUntil ?? this.surveySnoozedUntil),
      userConfirmedAt: userConfirmedAt ?? this.userConfirmedAt,
      settingsVersion: settingsVersion ?? this.settingsVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      targetGlucoseMgdl: targetGlucoseMgdl ?? this.targetGlucoseMgdl,
      targetGlucoseMinMgdl: targetGlucoseMinMgdl ?? this.targetGlucoseMinMgdl,
      targetGlucoseMaxMgdl: targetGlucoseMaxMgdl ?? this.targetGlucoseMaxMgdl,
      hypoThresholdMgdl: hypoThresholdMgdl ?? this.hypoThresholdMgdl,
      hyperThresholdMgdl: hyperThresholdMgdl ?? this.hyperThresholdMgdl,
      icrBlocks: icrBlocks ?? this.icrBlocks,
      isfBlocks: isfBlocks ?? this.isfBlocks,
      insulinActionDurationHours:
          insulinActionDurationHours ?? this.insulinActionDurationHours,
      insulinName: insulinName ?? this.insulinName,
      maxSingleBolusUnits: maxSingleBolusUnits ?? this.maxSingleBolusUnits,
      minBolusIncrement: minBolusIncrement ?? this.minBolusIncrement,
      correctionEnabled: correctionEnabled ?? this.correctionEnabled,
      mealBolusEnabled: mealBolusEnabled ?? this.mealBolusEnabled,
      iobEnabled: iobEnabled ?? this.iobEnabled,
      totalDailyInsulinDoseOptional:
          totalDailyInsulinDoseOptional ?? this.totalDailyInsulinDoseOptional,
    );
  }
}
