import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrition_goal.dart';
import '../models/user_preferences.dart';
import 'daily_intake_provider.dart';
import 'user_prefs_provider.dart';

/// A single smart recommendation shown on the dashboard.
class Recommendation {
  final String message;
  final String? suggestion; // e.g. "Try: chicken, eggs, tofu"
  final IconData icon;
  final Color color;

  const Recommendation({
    required this.message,
    this.suggestion,
    required this.icon,
    required this.color,
  });
}

class RecommendationsState {
  final List<Recommendation> recs;
  final bool loading;

  const RecommendationsState({this.recs = const [], this.loading = false});
}

class RecommendationsNotifier
    extends StateNotifier<RecommendationsState> {
  RecommendationsNotifier() : super(const RecommendationsState());

  void generate(UserPreferences prefs, DailyIntake intake) {
    final recs = <Recommendation>[];
    final goal    = prefs.nutritionGoal;
    final kcal    = intake.caloriesAvg;
    final protein = intake.proteinG;
    final carbs   = intake.carbsG;
    final fat     = intake.fatG;
    final kcalTarget   = prefs.dailyCalorieGoal.toDouble();
    final carbLimit    = prefs.dailyCarbLimitG.toDouble();
    final proteinTarget = prefs.dailyProteinTargetG.toDouble();
    final fatTarget    = prefs.dailyFatTargetG.toDouble();

    switch (goal) {
      // ── Muscle Growth ──────────────────────────────────────────────────────
      case NutritionGoalType.muscleGrowth:
        if (protein < proteinTarget * 0.5) {
          recs.add(Recommendation(
            message: 'Protein is low — ${protein.round()}g of ${proteinTarget.round()}g goal.',
            suggestion: 'Add: chicken breast (31g/100g), eggs (13g/egg), Greek yogurt.',
            icon: Icons.fitness_center,
            color: Colors.red.shade600,
          ));
        } else if (protein < proteinTarget * 0.8) {
          recs.add(Recommendation(
            message: 'Almost at protein goal — ${protein.round()}g / ${proteinTarget.round()}g.',
            suggestion: 'Try a protein shake or cottage cheese to top up.',
            icon: Icons.fitness_center,
            color: Colors.orange.shade700,
          ));
        } else {
          recs.add(Recommendation(
            message: 'Great protein intake! ${protein.round()}g / ${proteinTarget.round()}g ✅',
            icon: Icons.fitness_center,
            color: Colors.green.shade600,
          ));
        }
        if (kcal < kcalTarget * 0.6) {
          recs.add(Recommendation(
            message: 'Need more calories to grow — only ${kcal.round()} of ${kcalTarget.round()} kcal.',
            suggestion: 'Add a calorie-dense meal: rice + chicken, pasta, or peanut butter.',
            icon: Icons.local_fire_department,
            color: Colors.orange.shade600,
          ));
        } else if (kcal >= kcalTarget) {
          recs.add(Recommendation(
            message: 'Calorie goal reached! 🎉 ${kcal.round()} kcal.',
            icon: Icons.emoji_events,
            color: Colors.green.shade700,
          ));
        }
        recs.add(Recommendation(
          message: 'Drink at least 3 litres of water on training days.',
          icon: Icons.water_drop_outlined,
          color: Colors.blue.shade600,
        ));

      // ── Diabetes ───────────────────────────────────────────────────────────
      case NutritionGoalType.diabetes:
        final carbRatio = carbLimit > 0 ? carbs / carbLimit : 0.0;
        if (carbRatio > 1.0) {
          final over = (carbs - carbLimit).round();
          recs.add(Recommendation(
            message: '⚠️ ${over}g over your carb limit (${carbs.round()}g / ${carbLimit.round()}g).',
            suggestion: 'Skip high-carb foods. Try salad, eggs, chicken, or fish.',
            icon: Icons.warning_amber_rounded,
            color: Colors.red.shade700,
          ));
        } else if (carbRatio > 0.8) {
          final left = (carbLimit - carbs).round();
          recs.add(Recommendation(
            message: 'Only ${left}g of carbs left today — choose carefully.',
            suggestion: 'Low-carb options: leafy greens, tofu, eggs, fish.',
            icon: Icons.warning_outlined,
            color: Colors.orange.shade700,
          ));
        } else {
          recs.add(Recommendation(
            message: 'Carbs on track! ${carbs.round()}g / ${carbLimit.round()}g. 🩺',
            icon: Icons.check_circle_outline,
            color: Colors.green.shade600,
          ));
        }
        recs.add(Recommendation(
          message: 'Pair carbs with protein or fat to slow glucose absorption.',
          icon: Icons.lightbulb_outline,
          color: Colors.blue.shade600,
        ));
        recs.add(Recommendation(
          message: 'Fibre helps control blood sugar. Eat broccoli, spinach, or legumes.',
          icon: Icons.eco_outlined,
          color: Colors.green.shade700,
        ));

      // ── Vegan ──────────────────────────────────────────────────────────────
      case NutritionGoalType.vegan:
        if (protein < proteinTarget * 0.6) {
          recs.add(Recommendation(
            message: 'Protein low for a vegan diet — ${protein.round()}g / ${proteinTarget.round()}g.',
            suggestion: 'Add: lentils (9g/100g), tofu (8g/100g), tempeh, edamame.',
            icon: Icons.energy_savings_leaf,
            color: Colors.red.shade600,
          ));
        } else {
          recs.add(Recommendation(
            message: 'Good plant protein intake! ${protein.round()}g ✅',
            icon: Icons.energy_savings_leaf,
            color: Colors.green.shade600,
          ));
        }
        recs.add(Recommendation(
          message: 'Vitamin B12 is only in animal products — take a supplement or eat fortified foods.',
          suggestion: 'Fortified plant milk, nutritional yeast, or a B12 supplement.',
          icon: Icons.medication_outlined,
          color: Colors.purple.shade600,
        ));
        recs.add(Recommendation(
          message: 'Iron: eat spinach, lentils, pumpkin seeds. Pair with vitamin C to boost absorption.',
          icon: Icons.bloodtype_outlined,
          color: Colors.red.shade400,
        ));
        recs.add(Recommendation(
          message: 'Calcium: try fortified plant milk, tofu, broccoli, or almonds.',
          icon: Icons.science_outlined,
          color: Colors.lightBlue.shade600,
        ));
        recs.add(Recommendation(
          message: 'Vitamin D: get 15 min of sunlight or take a D3 supplement.',
          icon: Icons.wb_sunny_outlined,
          color: Colors.yellow.shade700,
        ));

      // ── Weight Loss ────────────────────────────────────────────────────────
      case NutritionGoalType.weightLoss:
        if (kcal > kcalTarget * 1.05) {
          final over = (kcal - kcalTarget).round();
          recs.add(Recommendation(
            message: '⚠️ ${over} kcal over target today.',
            suggestion: 'Choose lighter options: salad, lean protein, vegetables.',
            icon: Icons.warning_amber_rounded,
            color: Colors.red.shade600,
          ));
        } else {
          final left = (kcalTarget - kcal).round().clamp(0, 9999);
          recs.add(Recommendation(
            message: left > 0
                ? '$left kcal remaining today. Keep it up! ⚖️'
                : 'Daily calorie goal reached! 🎉',
            icon: left > 0 ? Icons.trending_down : Icons.emoji_events,
            color: Colors.green.shade600,
          ));
        }
        if (protein < proteinTarget * 0.7) {
          recs.add(Recommendation(
            message: 'Low protein (${protein.round()}g) can cause muscle loss during weight loss.',
            suggestion: 'Add lean protein: chicken, fish, eggs, Greek yogurt.',
            icon: Icons.fitness_center,
            color: Colors.orange.shade700,
          ));
        }
        recs.add(Recommendation(
          message: 'Eat slowly and stop when 80% full — your brain needs 20 min to register fullness.',
          icon: Icons.access_time,
          color: Colors.blueGrey.shade600,
        ));

      // ── Keto ───────────────────────────────────────────────────────────────
      case NutritionGoalType.keto:
        if (carbs > carbLimit) {
          final over = (carbs - carbLimit).round();
          recs.add(Recommendation(
            message: '❌ ${over}g over carb limit — ketosis likely broken!',
            suggestion: 'Fast for 16–18 hours or do light exercise to re-enter ketosis.',
            icon: Icons.block,
            color: Colors.red.shade700,
          ));
        } else if (carbs > carbLimit * 0.7) {
          final left = (carbLimit - carbs).round();
          recs.add(Recommendation(
            message: 'Only ${left}g of carbs left — avoid starchy foods.',
            suggestion: 'Safe options: avocado, cheese, eggs, meat, leafy greens.',
            icon: Icons.warning_outlined,
            color: Colors.orange.shade700,
          ));
        } else {
          recs.add(Recommendation(
            message: '🔥 Excellent! ${carbs.round()}g carbs — you\'re in ketosis range.',
            icon: Icons.local_fire_department,
            color: Colors.deepOrange.shade600,
          ));
        }
        if (fat < fatTarget * 0.5) {
          recs.add(Recommendation(
            message: 'Low fat intake (${fat.round()}g / ${fatTarget.round()}g). Fat is your fuel on keto.',
            suggestion: 'Add: avocado, olive oil, nuts, fatty fish, butter.',
            icon: Icons.opacity,
            color: Colors.amber.shade700,
          ));
        }
        recs.add(Recommendation(
          message: 'Drink plenty of water and add electrolytes (sodium, potassium, magnesium) on keto.',
          icon: Icons.water_drop_outlined,
          color: Colors.blue.shade600,
        ));

      // ── Maintain ───────────────────────────────────────────────────────────
      case NutritionGoalType.maintain:
        final kcalRatio = kcalTarget > 0 ? kcal / kcalTarget : 0.0;
        if (kcalRatio < 0.85) {
          recs.add(Recommendation(
            message: 'Under-eating slightly — ${kcal.round()} / ${kcalTarget.round()} kcal.',
            icon: Icons.trending_up,
            color: Colors.orange.shade600,
          ));
        } else if (kcalRatio > 1.1) {
          recs.add(Recommendation(
            message: 'Slightly over target — ${kcal.round()} kcal today.',
            suggestion: 'A short walk after dinner can burn 100–200 kcal.',
            icon: Icons.directions_walk,
            color: Colors.orange.shade700,
          ));
        } else {
          recs.add(Recommendation(
            message: 'Perfectly balanced today! ${kcal.round()} kcal 🎯',
            icon: Icons.check_circle,
            color: Colors.green.shade600,
          ));
        }
        recs.add(Recommendation(
          message: 'Eat a variety of colours — each colour group provides different micronutrients.',
          icon: Icons.palette_outlined,
          color: Colors.teal.shade600,
        ));
    }

    // Universal reminders
    recs.add(Recommendation(
      message: 'Stay hydrated — aim for 2 litres of water per day.',
      icon: Icons.water_drop_outlined,
      color: Colors.blue.shade500,
    ));

    // Keep at most 4 recommendations
    state = RecommendationsState(recs: recs.take(4).toList());
  }
}

final recommendationsProvider =
    StateNotifierProvider<RecommendationsNotifier, RecommendationsState>(
  (ref) {
    final notifier = RecommendationsNotifier();
    // Auto-generate when prefs or intake changes
    final prefs  = ref.watch(userPrefsProvider);
    final intake = ref.watch(dailyIntakeProvider);
    notifier.generate(prefs, intake);
    return notifier;
  },
);
