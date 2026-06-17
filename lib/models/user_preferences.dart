import 'glucose_unit.dart';
import 'mascot_type.dart';
import 'nutrition_goal.dart';

/// User preferences stored in SQLite.
class UserPreferences {
  final int? id;
  final String name;
  final int dailyCalorieGoal;
  final bool onboardingComplete;
  final bool hasSeenScanTutorial;
  final NutritionGoalType nutritionGoal;
  final int dailyCarbLimitG;
  final int dailyProteinTargetG;
  final int dailyFatTargetG;
  final MascotType mascotType;
  final AppColorSeed themeColorSeed;

  /// Insulin-to-Carbohydrate Ratio (ICR): grams of carbohydrate covered by
  /// 1 unit of rapid-acting insulin. 0 means "not set" (used only for the
  /// diabetes nutrition goal). A meal bolus = meal carbs ÷ this value.
  final double insulinCarbRatio;

  /// Insulin Sensitivity Factor (ISF) / correction factor: how much 1 unit of
  /// rapid-acting insulin lowers blood glucose, stored canonically in mg/dL
  /// per unit. 0 means "not set". Correction dose = (current BG − target) ÷ ISF.
  final double insulinSensitivityFactor;

  /// Target blood glucose used for correction dosing, stored in mg/dL.
  final double targetBloodGlucoseMgdl;

  /// Preferred blood-glucose unit for display and input.
  final GlucoseUnit glucoseUnit;

  const UserPreferences({
    this.id,
    this.name = '',
    this.dailyCalorieGoal = 2000,
    this.onboardingComplete = false,
    this.hasSeenScanTutorial = false,
    this.nutritionGoal = NutritionGoalType.maintain,
    this.dailyCarbLimitG = 250,
    this.dailyProteinTargetG = 80,
    this.dailyFatTargetG = 65,
    this.mascotType = MascotType.auto,
    this.themeColorSeed = AppColorSeed.green,
    this.insulinCarbRatio = 0,
    this.insulinSensitivityFactor = 0,
    this.targetBloodGlucoseMgdl = 120,
    this.glucoseUnit = GlucoseUnit.mgdl,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'daily_calorie_goal': dailyCalorieGoal,
      'onboarding_complete': onboardingComplete ? 1 : 0,
      'has_seen_scan_tutorial': hasSeenScanTutorial ? 1 : 0,
      'nutrition_goal': nutritionGoal.dbValue,
      'daily_carb_limit_g': dailyCarbLimitG,
      'daily_protein_target_g': dailyProteinTargetG,
      'daily_fat_target_g': dailyFatTargetG,
      'mascot_type': mascotType.dbValue,
      'theme_color_seed': themeColorSeed.dbValue,
      'insulin_carb_ratio': insulinCarbRatio,
      'insulin_sensitivity_factor': insulinSensitivityFactor,
      'target_blood_glucose_mgdl': targetBloodGlucoseMgdl,
      'glucose_unit': glucoseUnit.dbValue,
    };
  }

  factory UserPreferences.fromMap(Map<String, dynamic> map) {
    return UserPreferences(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      dailyCalorieGoal: (map['daily_calorie_goal'] as int?) ?? 2000,
      onboardingComplete: (map['onboarding_complete'] as int?) == 1,
      hasSeenScanTutorial: (map['has_seen_scan_tutorial'] as int?) == 1,
      nutritionGoal: NutritionGoalTypeX.fromDbValue(
          map['nutrition_goal'] as String?),
      dailyCarbLimitG: (map['daily_carb_limit_g'] as int?) ?? 250,
      dailyProteinTargetG: (map['daily_protein_target_g'] as int?) ?? 80,
      dailyFatTargetG: (map['daily_fat_target_g'] as int?) ?? 65,
      mascotType: MascotTypeX.fromDbValue(map['mascot_type'] as String?),
      themeColorSeed: AppColorSeedX.fromDbValue(map['theme_color_seed'] as String?),
      insulinCarbRatio: (map['insulin_carb_ratio'] as num?)?.toDouble() ?? 0,
      insulinSensitivityFactor:
          (map['insulin_sensitivity_factor'] as num?)?.toDouble() ?? 0,
      targetBloodGlucoseMgdl:
          (map['target_blood_glucose_mgdl'] as num?)?.toDouble() ?? 120,
      glucoseUnit: GlucoseUnitX.fromDbValue(map['glucose_unit'] as String?),
    );
  }

  UserPreferences copyWith({
    String? name,
    int? dailyCalorieGoal,
    bool? onboardingComplete,
    bool? hasSeenScanTutorial,
    NutritionGoalType? nutritionGoal,
    int? dailyCarbLimitG,
    int? dailyProteinTargetG,
    int? dailyFatTargetG,
    MascotType? mascotType,
    AppColorSeed? themeColorSeed,
    double? insulinCarbRatio,
    double? insulinSensitivityFactor,
    double? targetBloodGlucoseMgdl,
    GlucoseUnit? glucoseUnit,
  }) {
    return UserPreferences(
      id: id,
      name: name ?? this.name,
      dailyCalorieGoal: dailyCalorieGoal ?? this.dailyCalorieGoal,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      hasSeenScanTutorial: hasSeenScanTutorial ?? this.hasSeenScanTutorial,
      nutritionGoal: nutritionGoal ?? this.nutritionGoal,
      dailyCarbLimitG: dailyCarbLimitG ?? this.dailyCarbLimitG,
      dailyProteinTargetG: dailyProteinTargetG ?? this.dailyProteinTargetG,
      dailyFatTargetG: dailyFatTargetG ?? this.dailyFatTargetG,
      mascotType: mascotType ?? this.mascotType,
      themeColorSeed: themeColorSeed ?? this.themeColorSeed,
      insulinCarbRatio: insulinCarbRatio ?? this.insulinCarbRatio,
      insulinSensitivityFactor:
          insulinSensitivityFactor ?? this.insulinSensitivityFactor,
      targetBloodGlucoseMgdl:
          targetBloodGlucoseMgdl ?? this.targetBloodGlucoseMgdl,
      glucoseUnit: glucoseUnit ?? this.glucoseUnit,
    );
  }
}
