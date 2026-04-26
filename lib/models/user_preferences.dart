import 'mascot_type.dart';
import 'nutrition_goal.dart';

/// Biological sex for gender-specific DRV calculations.
enum UserGender {
  male,
  female,
  preferNotToSay;

  String get dbValue => name;
  String get label {
    switch (this) {
      case UserGender.male:           return 'Male';
      case UserGender.female:         return 'Female';
      case UserGender.preferNotToSay: return 'Prefer not to say';
    }
  }
  static UserGender fromDbValue(String? v) {
    return UserGender.values.firstWhere(
      (e) => e.name == v,
      orElse: () => UserGender.preferNotToSay,
    );
  }
}

/// User preferences stored in SQLite.
class UserPreferences {
  final int? id;
  final String name;
  final int dailyCalorieGoal;
  final bool onboardingComplete;
  final bool hasSeenScanTutorial;
  final bool hasSeenAppTutorial;
  final NutritionGoalType nutritionGoal;
  final int dailyCarbLimitG;
  final int dailyProteinTargetG;
  final int dailyFatTargetG;
  final MascotType mascotType;
  final AppColorSeed themeColorSeed;
  final UserGender gender;
  final double fontScale;
  /// Insulin-to-Carb Ratio: grams of carbs covered by 1 unit of insulin.
  /// Used only when [nutritionGoal] == [NutritionGoalType.diabetes].
  final double icrGramsPerUnit;
  /// When true, streaks are not broken by missed days. Persisted across app restarts.
  final bool vacationMode;

  const UserPreferences({
    this.id,
    this.name = '',
    this.dailyCalorieGoal = 2000,
    this.onboardingComplete = false,
    this.hasSeenScanTutorial = false,
    this.hasSeenAppTutorial = false,
    this.nutritionGoal = NutritionGoalType.maintain,
    this.dailyCarbLimitG = 250,
    this.dailyProteinTargetG = 80,
    this.dailyFatTargetG = 65,
    this.mascotType = MascotType.auto,
    this.themeColorSeed = AppColorSeed.green,
    this.gender = UserGender.preferNotToSay,
    this.fontScale = 1.0,
    this.icrGramsPerUnit = 15.0,
    this.vacationMode = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'daily_calorie_goal': dailyCalorieGoal,
      'onboarding_complete': onboardingComplete ? 1 : 0,
      'has_seen_scan_tutorial': hasSeenScanTutorial ? 1 : 0,
      'has_seen_app_tutorial': hasSeenAppTutorial ? 1 : 0,
      'nutrition_goal': nutritionGoal.dbValue,
      'daily_carb_limit_g': dailyCarbLimitG,
      'daily_protein_target_g': dailyProteinTargetG,
      'daily_fat_target_g': dailyFatTargetG,
      'mascot_type': mascotType.dbValue,
      'theme_color_seed': themeColorSeed.dbValue,
      'gender': gender.dbValue,
      'font_scale': fontScale,
      'icr_grams_per_unit': icrGramsPerUnit,
      'vacation_mode': vacationMode ? 1 : 0,
    };
  }

  factory UserPreferences.fromMap(Map<String, dynamic> map) {
    return UserPreferences(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      dailyCalorieGoal: (map['daily_calorie_goal'] as int?) ?? 2000,
      onboardingComplete: (map['onboarding_complete'] as int?) == 1,
      hasSeenScanTutorial: (map['has_seen_scan_tutorial'] as int?) == 1,
      hasSeenAppTutorial: (map['has_seen_app_tutorial'] as int?) == 1,
      nutritionGoal: NutritionGoalTypeX.fromDbValue(
          map['nutrition_goal'] as String?),
      dailyCarbLimitG: (map['daily_carb_limit_g'] as int?) ?? 250,
      dailyProteinTargetG: (map['daily_protein_target_g'] as int?) ?? 80,
      dailyFatTargetG: (map['daily_fat_target_g'] as int?) ?? 65,
      mascotType: MascotTypeX.fromDbValue(map['mascot_type'] as String?),
      themeColorSeed: AppColorSeedX.fromDbValue(map['theme_color_seed'] as String?),
      gender: UserGender.fromDbValue(map['gender'] as String?),
      fontScale: (map['font_scale'] as num?)?.toDouble() ?? 1.0,
      icrGramsPerUnit: (map['icr_grams_per_unit'] as num?)?.toDouble() ?? 15.0,
      vacationMode: (map['vacation_mode'] as int?) == 1,
    );
  }

  UserPreferences copyWith({
    String? name,
    int? dailyCalorieGoal,
    bool? onboardingComplete,
    bool? hasSeenScanTutorial,
    bool? hasSeenAppTutorial,
    NutritionGoalType? nutritionGoal,
    int? dailyCarbLimitG,
    int? dailyProteinTargetG,
    int? dailyFatTargetG,
    MascotType? mascotType,
    AppColorSeed? themeColorSeed,
    UserGender? gender,
    double? fontScale,
    double? icrGramsPerUnit,
    bool? vacationMode,
  }) {
    return UserPreferences(
      id: id,
      name: name ?? this.name,
      dailyCalorieGoal: dailyCalorieGoal ?? this.dailyCalorieGoal,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      hasSeenScanTutorial: hasSeenScanTutorial ?? this.hasSeenScanTutorial,
      hasSeenAppTutorial: hasSeenAppTutorial ?? this.hasSeenAppTutorial,
      nutritionGoal: nutritionGoal ?? this.nutritionGoal,
      dailyCarbLimitG: dailyCarbLimitG ?? this.dailyCarbLimitG,
      dailyProteinTargetG: dailyProteinTargetG ?? this.dailyProteinTargetG,
      dailyFatTargetG: dailyFatTargetG ?? this.dailyFatTargetG,
      mascotType: mascotType ?? this.mascotType,
      themeColorSeed: themeColorSeed ?? this.themeColorSeed,
      gender: gender ?? this.gender,
      fontScale: fontScale ?? this.fontScale,
      icrGramsPerUnit: icrGramsPerUnit ?? this.icrGramsPerUnit,
      vacationMode: vacationMode ?? this.vacationMode,
    );
  }
}
