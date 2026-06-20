import 'package:flutter/material.dart';

/// The supported nutrition goals.
enum NutritionGoalType {
  muscleGrowth,
  diabetes,
  vegan,
  vegetarian,
  pescatarian,
  mediterranean,
  weightLoss,
  keto,
  maintain,
}

enum MuscleMassLevel {
  low,
  average,
  high,
  veryHigh;

  String get dbValue => name;

  String get label {
    switch (this) {
      case MuscleMassLevel.low:
        return 'Low';
      case MuscleMassLevel.average:
        return 'Average';
      case MuscleMassLevel.high:
        return 'High';
      case MuscleMassLevel.veryHigh:
        return 'Very high';
    }
  }

  String get description {
    switch (this) {
      case MuscleMassLevel.low:
        return 'Lower lean mass or mostly sedentary right now.';
      case MuscleMassLevel.average:
        return 'Typical lean mass for your weight and height.';
      case MuscleMassLevel.high:
        return 'Clearly muscular or strength training regularly.';
      case MuscleMassLevel.veryHigh:
        return 'Very muscular athlete/bodybuilding profile.';
    }
  }

  double get kcalPerKgAdjustment {
    switch (this) {
      case MuscleMassLevel.low:
        return -2.0;
      case MuscleMassLevel.average:
        return 0.0;
      case MuscleMassLevel.high:
        return 2.5;
      case MuscleMassLevel.veryHigh:
        return 4.0;
    }
  }

  double get weightLossDeficitFraction {
    switch (this) {
      case MuscleMassLevel.low:
        return 0.20;
      case MuscleMassLevel.average:
        return 0.18;
      case MuscleMassLevel.high:
        return 0.16;
      case MuscleMassLevel.veryHigh:
        return 0.15;
    }
  }

  static MuscleMassLevel fromDbValue(String? value) {
    return MuscleMassLevel.values.firstWhere(
      (level) => level.name == value,
      orElse: () => MuscleMassLevel.average,
    );
  }
}

extension NutritionGoalTypeX on NutritionGoalType {
  String get label {
    switch (this) {
      case NutritionGoalType.muscleGrowth:
        return 'Muscle Growth';
      case NutritionGoalType.diabetes:
        return 'Diabetes';
      case NutritionGoalType.vegan:
        return 'Vegan Diet';
      case NutritionGoalType.vegetarian:
        return 'Vegetarian Diet';
      case NutritionGoalType.pescatarian:
        return 'Pescatarian';
      case NutritionGoalType.mediterranean:
        return 'Mediterranean';
      case NutritionGoalType.weightLoss:
        return 'Weight Loss';
      case NutritionGoalType.keto:
        return 'Keto';
      case NutritionGoalType.maintain:
        return 'Maintain Weight';
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
      case NutritionGoalType.vegetarian:
        return 'Avoid meat and seafood while allowing dairy, eggs, and honey when they fit your plan.';
      case NutritionGoalType.pescatarian:
        return 'Vegetarian-style eating that includes fish and seafood for omega-3 fats, iodine, selenium, and complete protein.';
      case NutritionGoalType.mediterranean:
        return 'A cardiometabolic pattern built around vegetables, legumes, whole grains, fruit, olive oil, nuts, fish, and modest dairy.';
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
      case NutritionGoalType.muscleGrowth:
        return '🦍';
      case NutritionGoalType.diabetes:
        return '🩺';
      case NutritionGoalType.vegan:
        return '🌱';
      case NutritionGoalType.vegetarian:
        return '🥬';
      case NutritionGoalType.pescatarian:
        return '🐟';
      case NutritionGoalType.mediterranean:
        return '🫒';
      case NutritionGoalType.weightLoss:
        return '⚖️';
      case NutritionGoalType.keto:
        return '🔥';
      case NutritionGoalType.maintain:
        return '🎯';
    }
  }

  Color get color {
    switch (this) {
      case NutritionGoalType.muscleGrowth:
        return const Color(0xFF388E3C);
      case NutritionGoalType.diabetes:
        return const Color(0xFF1976D2);
      case NutritionGoalType.vegan:
        return const Color(0xFF2E7D32);
      case NutritionGoalType.vegetarian:
        return const Color(0xFF558B2F);
      case NutritionGoalType.pescatarian:
        return const Color(0xFF00796B);
      case NutritionGoalType.mediterranean:
        return const Color(0xFF5D8A38);
      case NutritionGoalType.weightLoss:
        return const Color(0xFFF57C00);
      case NutritionGoalType.keto:
        return const Color(0xFFE64A19);
      case NutritionGoalType.maintain:
        return const Color(0xFF6A1B9A);
    }
  }

  Color get lightColor {
    switch (this) {
      case NutritionGoalType.muscleGrowth:
        return const Color(0xFFE8F5E9);
      case NutritionGoalType.diabetes:
        return const Color(0xFFE3F2FD);
      case NutritionGoalType.vegan:
        return const Color(0xFFF1F8E9);
      case NutritionGoalType.vegetarian:
        return const Color(0xFFF0F4C3);
      case NutritionGoalType.pescatarian:
        return const Color(0xFFE0F2F1);
      case NutritionGoalType.mediterranean:
        return const Color(0xFFF1F8E9);
      case NutritionGoalType.weightLoss:
        return const Color(0xFFFFF3E0);
      case NutritionGoalType.keto:
        return const Color(0xFFFBE9E7);
      case NutritionGoalType.maintain:
        return const Color(0xFFF3E5F5);
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
  static const double minWeightKg = 40.0;
  static const double maxWeightKg = 180.0;
  static const double weightStepKg = 1.0;
  static const double minHeightCm = 120.0;
  static const double maxHeightCm = 230.0;
  static const double heightStepCm = 1.0;

  static double clampWeightKg(double weightKg) =>
      weightKg.clamp(minWeightKg, maxWeightKg).toDouble();

  static double snapWeightKg(double weightKg) =>
      (clampWeightKg(weightKg) / weightStepKg).round() * weightStepKg;

  static String formatWeightKg(double weightKg) =>
      snapWeightKg(weightKg).round().toString();

  static double clampHeightCm(double heightCm) =>
      heightCm.clamp(minHeightCm, maxHeightCm).toDouble();

  static double snapHeightCm(double heightCm) =>
      (clampHeightCm(heightCm) / heightStepCm).round() * heightStepCm;

  static String formatHeightCm(double heightCm) =>
      snapHeightCm(heightCm).round().toString();

  /// Fallback calorie targets when no weight is provided.
  static int calories(NutritionGoalType t, {bool male = false}) {
    switch (t) {
      case NutritionGoalType.muscleGrowth:
        return male ? 3300 : 2800;
      case NutritionGoalType.diabetes:
        return male ? 2000 : 1800;
      case NutritionGoalType.vegan:
        return male ? 2200 : 2000;
      case NutritionGoalType.vegetarian:
        return male ? 2300 : 2000;
      case NutritionGoalType.pescatarian:
        return male ? 2400 : 2000;
      case NutritionGoalType.mediterranean:
        return male ? 2400 : 2000;
      case NutritionGoalType.weightLoss:
        return male ? 1800 : 1600;
      case NutritionGoalType.keto:
        return male ? 2200 : 2000;
      case NutritionGoalType.maintain:
        return male ? 2500 : 2000;
    }
  }

  /// Profile-based maintenance starting estimate.
  ///
  /// This intentionally avoids BMI-category logic and avoids equations that
  /// need age. It starts from guideline-style kcal/kg/day, then adjusts for
  /// height/frame and self-reported muscle amount so muscular users are not
  /// pushed into an overly aggressive deficit from weight alone.
  static int _maintenance({
    required double weightKg,
    required double heightCm,
    required MuscleMassLevel muscleMassLevel,
    required bool male,
  }) {
    final kg = clampWeightKg(weightKg);
    final height = snapHeightCm(heightCm);
    final referenceHeight = male ? 175.0 : 165.0;
    final heightAdjustment =
        ((height - referenceHeight) / 10.0 * 0.6).clamp(-3.0, 3.0).toDouble();
    final kcalPerKg = (male ? 33.0 : 30.0) +
        heightAdjustment +
        muscleMassLevel.kcalPerKgAdjustment;
    return (kg * kcalPerKg).round().clamp(1200, 5000);
  }

  static int caloriesForProfile(
    NutritionGoalType t, {
    required double weightKg,
    required double heightCm,
    required MuscleMassLevel muscleMassLevel,
    required bool male,
  }) {
    final maint = _maintenance(
      weightKg: weightKg,
      heightCm: heightCm,
      muscleMassLevel: muscleMassLevel,
      male: male,
    );
    switch (t) {
      case NutritionGoalType.muscleGrowth:
        final surplus = (maint * 0.12).round().clamp(250, 500);
        return (maint + surplus).clamp(1200, 5000);
      case NutritionGoalType.weightLoss:
        final deficit = (maint * muscleMassLevel.weightLossDeficitFraction)
            .round()
            .clamp(250, 650);
        final floor = male ? 1500 : 1200;
        return (maint - deficit).clamp(floor, 5000);
      case NutritionGoalType.diabetes:
      case NutritionGoalType.keto:
      case NutritionGoalType.vegan:
      case NutritionGoalType.vegetarian:
      case NutritionGoalType.pescatarian:
      case NutritionGoalType.mediterranean:
      case NutritionGoalType.maintain:
        return maint;
    }
  }

  /// Weight-aware calorie target for a goal.
  /// Applies surplus/deficit on top of estimated maintenance.
  static int caloriesForWeight(
    NutritionGoalType t, {
    required double weightKg,
    required bool male,
  }) {
    return caloriesForProfile(
      t,
      weightKg: weightKg,
      heightCm: male ? 175.0 : 165.0,
      muscleMassLevel: MuscleMassLevel.average,
      male: male,
    );
  }

  /// Evidence-based macro percentage distributions per goal.
  ///
  /// Fractions of total daily kcal.  Carbs and protein = 4 kcal/g; fat = 9 kcal/g.
  static ({double carb, double protein, double fat}) macroRatios(
      NutritionGoalType t) {
    switch (t) {
      case NutritionGoalType.muscleGrowth:
        // 25P / 50C / 25F — high carbs for training, solid protein.
        return (carb: 0.50, protein: 0.25, fat: 0.25);
      case NutritionGoalType.diabetes:
        // 30P / 35C / 35F — lower carbs for glucose management.
        return (carb: 0.35, protein: 0.30, fat: 0.35);
      case NutritionGoalType.vegan:
        // 25P / 50C / 25F — plant diets naturally higher in carbs.
        return (carb: 0.50, protein: 0.25, fat: 0.25);
      case NutritionGoalType.vegetarian:
        // 25P / 45C / 30F — balanced vegetarian pattern with solid protein.
        return (carb: 0.45, protein: 0.25, fat: 0.30);
      case NutritionGoalType.pescatarian:
        // 25P / 45C / 30F — fish/seafood plus plant-forward carbs and fats.
        return (carb: 0.45, protein: 0.25, fat: 0.30);
      case NutritionGoalType.mediterranean:
        // 20P / 45C / 35F — Mediterranean-style AMDR with olive oil and nuts.
        return (carb: 0.45, protein: 0.20, fat: 0.35);
      case NutritionGoalType.weightLoss:
        // 40P / 30C / 30F — high protein for satiety + muscle preservation.
        return (carb: 0.30, protein: 0.40, fat: 0.30);
      case NutritionGoalType.keto:
        // 20P / 5C / 75F — strict keto; carbs capped at 50g net.
        return (carb: 0.05, protein: 0.20, fat: 0.75);
      case NutritionGoalType.maintain:
        // Balanced AMDR: 50C / 20P / 30F.
        return (carb: 0.50, protein: 0.20, fat: 0.30);
    }
  }

  /// Compute macro grams from calories and goal ratios.
  /// For keto, carbs are capped at 50g net regardless of calories.
  static ({int carbG, int proteinG, int fatG}) macroGrams(
    NutritionGoalType t,
    int kcal,
  ) {
    final r = macroRatios(t);
    int carbG = (kcal * r.carb / 4).round();
    final proteinG = (kcal * r.protein / 4).round();
    final fatG = (kcal * r.fat / 9).round();
    if (t == NutritionGoalType.keto && carbG > 50) carbG = 50;
    return (carbG: carbG, proteinG: proteinG, fatG: fatG);
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
      case NutritionGoalType.vegetarian:
        if (progress < 0.33) return 'Fresh Start';
        if (progress < 0.66) return 'Balanced Plate';
        if (progress < 1.00) return 'Well Nourished';
        return 'Thriving';
      case NutritionGoalType.pescatarian:
        if (progress < 0.33) return 'Fresh Catch';
        if (progress < 0.66) return 'Balanced Plate';
        if (progress < 1.00) return 'Well Nourished';
        return 'Thriving';
      case NutritionGoalType.mediterranean:
        if (progress < 0.33) return 'Fresh Start';
        if (progress < 0.66) return 'Colorful Plate';
        if (progress < 1.00) return 'Heart Smart';
        return 'Thriving';
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
