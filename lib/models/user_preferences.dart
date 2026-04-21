/// User preferences stored in SQLite.
class UserPreferences {
  final int? id;
  final String name;
  final int dailyCalorieGoal;
  final bool onboardingComplete;
  final bool hasSeenScanTutorial;

  const UserPreferences({
    this.id,
    this.name = '',
    this.dailyCalorieGoal = 2000,
    this.onboardingComplete = false,
    this.hasSeenScanTutorial = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'daily_calorie_goal': dailyCalorieGoal,
      'onboarding_complete': onboardingComplete ? 1 : 0,
      'has_seen_scan_tutorial': hasSeenScanTutorial ? 1 : 0,
    };
  }

  factory UserPreferences.fromMap(Map<String, dynamic> map) {
    return UserPreferences(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      dailyCalorieGoal: (map['daily_calorie_goal'] as int?) ?? 2000,
      onboardingComplete: (map['onboarding_complete'] as int?) == 1,
      hasSeenScanTutorial: (map['has_seen_scan_tutorial'] as int?) == 1,
    );
  }

  UserPreferences copyWith({
    String? name,
    int? dailyCalorieGoal,
    bool? onboardingComplete,
    bool? hasSeenScanTutorial,
  }) {
    return UserPreferences(
      id: id,
      name: name ?? this.name,
      dailyCalorieGoal: dailyCalorieGoal ?? this.dailyCalorieGoal,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      hasSeenScanTutorial: hasSeenScanTutorial ?? this.hasSeenScanTutorial,
    );
  }
}
