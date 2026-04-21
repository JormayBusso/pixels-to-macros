import 'package:flutter/material.dart';

/// The six supported nutrition goals.
enum NutritionGoalType {
  muscleGrowth,
  diabetes,
  vegan,
  weightLoss,
  keto,
  maintain,
}

extension NutritionGoalTypeX on NutritionGoalType {
  String get label {
    switch (this) {
      case NutritionGoalType.muscleGrowth: return 'Muscle Growth';
      case NutritionGoalType.diabetes:     return 'Diabetes';
      case NutritionGoalType.vegan:        return 'Vegan Diet';
      case NutritionGoalType.weightLoss:   return 'Weight Loss';
      case NutritionGoalType.keto:         return 'Keto';
      case NutritionGoalType.maintain:     return 'Maintain Weight';
    }
  }

  String get description {
    switch (this) {
      case NutritionGoalType.muscleGrowth:
        return 'Build muscle with a calorie surplus and high protein intake.';
      case NutritionGoalType.diabetes:
        return 'Keep blood sugar stable by managing your daily carbohydrate intake.';
      case NutritionGoalType.vegan:
        return 'Track nutrients often missing from plant-based diets: protein, B12, iron, vitamin D.';
      case NutritionGoalType.weightLoss:
        return 'Lose weight sustainably with a moderate calorie deficit and high protein.';
      case NutritionGoalType.keto:
        return 'Enter and stay in ketosis. Keep daily carbs under 25 g while eating healthy fats.';
      case NutritionGoalType.maintain:
        return 'Maintain your current weight with balanced macros.';
    }
  }

  String get emoji {
    switch (this) {
      case NutritionGoalType.muscleGrowth: return '🦍';
      case NutritionGoalType.diabetes:     return '🩺';
      case NutritionGoalType.vegan:        return '🌱';
      case NutritionGoalType.weightLoss:   return '⚖️';
      case NutritionGoalType.keto:         return '🔥';
      case NutritionGoalType.maintain:     return '🎯';
    }
  }

  Color get color {
    switch (this) {
      case NutritionGoalType.muscleGrowth: return const Color(0xFF388E3C);
      case NutritionGoalType.diabetes:     return const Color(0xFF1976D2);
      case NutritionGoalType.vegan:        return const Color(0xFF2E7D32);
      case NutritionGoalType.weightLoss:   return const Color(0xFFF57C00);
      case NutritionGoalType.keto:         return const Color(0xFFE64A19);
      case NutritionGoalType.maintain:     return const Color(0xFF6A1B9A);
    }
  }

  Color get lightColor {
    switch (this) {
      case NutritionGoalType.muscleGrowth: return const Color(0xFFE8F5E9);
      case NutritionGoalType.diabetes:     return const Color(0xFFE3F2FD);
      case NutritionGoalType.vegan:        return const Color(0xFFF1F8E9);
      case NutritionGoalType.weightLoss:   return const Color(0xFFFFF3E0);
      case NutritionGoalType.keto:         return const Color(0xFFFBE9E7);
      case NutritionGoalType.maintain:     return const Color(0xFFF3E5F5);
    }
  }

  /// Persisted string value.
  String get dbValue => name;

  static NutritionGoalType fromDbValue(String? v) {
    return NutritionGoalType.values.firstWhere(
      (e) => e.name == v,
      orElse: () => NutritionGoalType.maintain,
    );
  }
}

/// Default macro targets per goal.
abstract final class GoalDefaults {
  static int calories(NutritionGoalType t) {
    switch (t) {
      case NutritionGoalType.muscleGrowth: return 3000;
      case NutritionGoalType.diabetes:     return 1800;
      case NutritionGoalType.vegan:        return 2000;
      case NutritionGoalType.weightLoss:   return 1600;
      case NutritionGoalType.keto:         return 2000;
      case NutritionGoalType.maintain:     return 2000;
    }
  }

  static int carbLimitG(NutritionGoalType t) {
    switch (t) {
      case NutritionGoalType.muscleGrowth: return 375;
      case NutritionGoalType.diabetes:     return 130;
      case NutritionGoalType.vegan:        return 250;
      case NutritionGoalType.weightLoss:   return 130;
      case NutritionGoalType.keto:         return 25;
      case NutritionGoalType.maintain:     return 250;
    }
  }

  static int proteinTargetG(NutritionGoalType t) {
    switch (t) {
      case NutritionGoalType.muscleGrowth: return 180;
      case NutritionGoalType.diabetes:     return 90;
      case NutritionGoalType.vegan:        return 80;
      case NutritionGoalType.weightLoss:   return 120;
      case NutritionGoalType.keto:         return 120;
      case NutritionGoalType.maintain:     return 80;
    }
  }

  static int fatTargetG(NutritionGoalType t) {
    switch (t) {
      case NutritionGoalType.muscleGrowth: return 100;
      case NutritionGoalType.diabetes:     return 60;
      case NutritionGoalType.vegan:        return 65;
      case NutritionGoalType.weightLoss:   return 55;
      case NutritionGoalType.keto:         return 155;
      case NutritionGoalType.maintain:     return 65;
    }
  }

  /// Mascot stage name for progress percentage [0.0–1.0+].
  static String mascotStageName(NutritionGoalType t, double progress) {
    switch (t) {
      case NutritionGoalType.muscleGrowth:
        if (progress < 0.33) return 'Baby Gorilla';
        if (progress < 0.66) return 'Growing Strong';
        if (progress < 1.00) return 'Mighty Gorilla';
        return 'Champion! 💪';
      case NutritionGoalType.diabetes:
        if (progress < 0.50) return 'Pancreas Healthy';
        if (progress < 0.80) return 'Slightly Stressed';
        if (progress < 1.00) return 'Under Pressure';
        return 'Overloaded!';
      case NutritionGoalType.vegan:
        if (progress < 0.33) return 'Seed Stage';
        if (progress < 0.66) return 'Sprouting';
        if (progress < 1.00) return 'Growing Well';
        return 'In Full Bloom 🌸';
      case NutritionGoalType.weightLoss:
        if (progress < 0.33) return 'Just Started';
        if (progress < 0.66) return 'Making Progress';
        if (progress < 1.00) return 'Almost There!';
        return 'Goal Reached! 🎉';
      case NutritionGoalType.keto:
        if (progress < 0.40) return '🔥 Deep Ketosis';
        if (progress < 0.70) return '🔥 In Ketosis';
        if (progress < 1.00) return '⚠️ Near Limit';
        return '❌ Ketosis Broken';
      case NutritionGoalType.maintain:
        if (progress < 0.50) return 'Under Target';
        if (progress < 0.90) return 'On Track';
        if (progress < 1.10) return 'Balanced ✅';
        return 'Over Target';
    }
  }
}
