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

/// Default macro targets per goal — gender-aware.
/// Males generally need ~200–300 kcal more per day than females.
abstract final class GoalDefaults {
  static int calories(NutritionGoalType t, {bool male = false}) {
    switch (t) {
      case NutritionGoalType.muscleGrowth: return male ? 3300 : 2800;
      case NutritionGoalType.diabetes:     return male ? 2000 : 1800;
      case NutritionGoalType.vegan:        return male ? 2200 : 2000;
      case NutritionGoalType.weightLoss:   return male ? 1800 : 1600;
      case NutritionGoalType.keto:         return male ? 2200 : 2000;
      case NutritionGoalType.maintain:     return male ? 2500 : 2000;
    }
  }

  /// Evidence-based macro percentage distributions per goal.
  ///
  /// Fractions of total daily kcal.  Carbs and protein = 4 kcal/g; fat = 9 kcal/g.
  ///
  /// Sources: AHA, ADA, WHO dietary guidelines.
  static ({double carb, double protein, double fat}) macroRatios(
      NutritionGoalType t) {
    switch (t) {
      case NutritionGoalType.muscleGrowth:
        // High carbs for training energy, high protein for hypertrophy (AHA/ISSN).
        return (carb: 0.46, protein: 0.22, fat: 0.27);
      case NutritionGoalType.diabetes:
        // ADA 2024: low carb (<130 g/day), moderate-high protein, unsaturated fats.
        return (carb: 0.26, protein: 0.26, fat: 0.44);
      case NutritionGoalType.vegan:
        // Higher complex carbs, adequate plant protein, moderate fat (PMID 31728500).
        return (carb: 0.52, protein: 0.16, fat: 0.30);
      case NutritionGoalType.weightLoss:
        // High protein preserves muscle & improves satiety (NEJM 2009); reduced carbs.
        return (carb: 0.30, protein: 0.35, fat: 0.35);
      case NutritionGoalType.keto:
        // Classic ketogenic: very low carb, moderate protein, high fat (AJCN).
        return (carb: 0.05, protein: 0.22, fat: 0.73);
      case NutritionGoalType.maintain:
        // Balanced AMDR ranges (DRI/IOM): carbs 45–65 %, protein 10–35 %, fat 20–35 %.
        return (carb: 0.50, protein: 0.20, fat: 0.30);
    }
  }

  /// Gram targets derived from [macroRatios] × the female (lower) reference
  /// calorie for the goal.  Ensures macros always add up to ~95–100 % of kcal.
  static int carbLimitG(NutritionGoalType t) {
    final r = macroRatios(t);
    final kcal = calories(t, male: false).toDouble();
    return (kcal * r.carb / 4).round();
  }

  static int proteinTargetG(NutritionGoalType t) {
    final r = macroRatios(t);
    final kcal = calories(t, male: false).toDouble();
    return (kcal * r.protein / 4).round();
  }

  static int fatTargetG(NutritionGoalType t) {
    final r = macroRatios(t);
    final kcal = calories(t, male: false).toDouble();
    return (kcal * r.fat / 9).round();
  }

  /// Mascot stage name for progress percentage [0.0–1.0+].
  static String mascotStageName(NutritionGoalType t, double progress) {
    switch (t) {
      case NutritionGoalType.muscleGrowth:
        if (progress < 0.33) return 'Baby Gorilla';
        if (progress < 0.66) return 'Growing Strong';
        if (progress < 1.00) return 'Mighty Gorilla';
        return 'Champion';
      case NutritionGoalType.diabetes:
        // diabetesStress: 0 = nothing eaten yet (excellent), rises with unhealthy eating.
        if (progress < 0.30) return 'Excellent Control';
        if (progress < 0.60) return 'Under Control';
        if (progress < 0.90) return 'Too Much Sugar';
        return 'Sugar Overload';
      case NutritionGoalType.vegan:
        if (progress < 0.33) return 'Seed Stage';
        if (progress < 0.66) return 'Sprouting';
        if (progress < 1.00) return 'Growing Well';
        return 'In Full Bloom';
      case NutritionGoalType.weightLoss:
        if (progress < 0.33) return 'Just Started';
        if (progress < 0.66) return 'Making Progress';
        if (progress < 1.00) return 'Almost There';
        return 'Goal Reached';
      case NutritionGoalType.keto:
        if (progress < 0.40) return 'Deep Ketosis';
        if (progress < 0.70) return 'In Ketosis';
        if (progress < 1.00) return 'Near Limit';
        return 'Ketosis Broken';
      case NutritionGoalType.maintain:
        if (progress < 0.50) return 'Under Target';
        if (progress < 0.90) return 'On Track';
        if (progress < 1.10) return 'Balanced';
        return 'Over Target';
    }
  }
}
