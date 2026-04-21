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
    );
  }
}
