import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrition_goal.dart';
import '../models/nutrient_data.dart';
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

    // Micronutrient-aware recommendations based on today's intake.
    recs.addAll(
      _buildMicronutrientRecommendations(
        goal: goal,
        gender: prefs.gender,
        totals: intake.nutrientTotals,
      ),
    );

    // Universal reminders — time-aware hydration
    final hour = DateTime.now().hour;
    if (hour >= 13 && kcal < kcalTarget * 0.3) {
      recs.add(Recommendation(
        message: 'It\'s past 1 PM and you\'ve only eaten ${kcal.round()} kcal. Don\'t skip meals!',
        suggestion: 'Have a balanced meal with protein, carbs, and healthy fats.',
        icon: Icons.access_time,
        color: Colors.orange.shade700,
      ));
    }
    if (hour >= 13) {
      recs.add(Recommendation(
        message: 'It\'s afternoon — make sure you\'ve had enough water. Aim for at least 4-6 glasses by now.',
        suggestion: 'Carry a water bottle and sip regularly. Add lemon for flavour.',
        icon: Icons.water_drop_outlined,
        color: Colors.blue.shade500,
      ));
    } else if (hour >= 10) {
      recs.add(Recommendation(
        message: 'Mid-morning — have you had 2-3 glasses of water? Stay ahead of thirst.',
        icon: Icons.water_drop_outlined,
        color: Colors.blue.shade500,
      ));
    } else {
      recs.add(Recommendation(
        message: 'Start your day with a glass of water — aim for 2 litres today.',
        icon: Icons.water_drop_outlined,
        color: Colors.blue.shade500,
      ));
    }

    // Keep at most 8 recommendations
    state = RecommendationsState(recs: recs.take(8).toList());
  }

  List<Recommendation> _buildMicronutrientRecommendations({
    required NutritionGoalType goal,
    required UserGender gender,
    required NutrientTotals totals,
  }) {
    final recs = <Recommendation>[];
    final plantOnly = goal == NutritionGoalType.vegan;

    final vitaminCGoal =
        gender == UserGender.female ? NutrientDRV.vitaminCMg_female : NutrientDRV.vitaminCMg_male;
    final vitaminAGoal =
        gender == UserGender.female ? NutrientDRV.vitaminAUg_female : NutrientDRV.vitaminAUg_male;
    final calciumGoal =
        gender == UserGender.female ? NutrientDRV.calciumMg_female : NutrientDRV.calciumMg_male;
    final ironGoal =
        gender == UserGender.female ? NutrientDRV.ironMg_female : NutrientDRV.ironMg_male;
    final potassiumGoal =
        gender == UserGender.female ? NutrientDRV.potassiumMg_female : NutrientDRV.potassiumMg_male;

    if (totals.vitaminDUg < NutrientDRV.vitaminDUg * 0.45) {
      recs.add(Recommendation(
        message:
            'Vitamin D looks low (${totals.vitaminDUg.toStringAsFixed(1)} µg / ${NutrientDRV.vitaminDUg.toStringAsFixed(0)} µg).',
        suggestion: plantOnly
            ? 'Try fortified plant milk, UV-exposed mushrooms, and a vitamin D supplement.'
            : 'Add fatty fish (salmon, sardines, trout), eggs, or fortified dairy.',
        icon: Icons.wb_sunny_outlined,
        color: Colors.amber.shade700,
      ));
    }

    if (totals.b12Mcg < NutrientDRV.b12Mcg * 0.55) {
      recs.add(Recommendation(
        message:
            'Vitamin B12 may be low (${totals.b12Mcg.toStringAsFixed(1)} µg / ${NutrientDRV.b12Mcg.toStringAsFixed(1)} µg).',
        suggestion: plantOnly
            ? 'Use B12-fortified foods (plant milk, nutritional yeast) or a B12 supplement.'
            : 'Add fish, eggs, dairy, or lean meat to support B12 intake.',
        icon: Icons.medication_outlined,
        color: Colors.deepPurple.shade400,
      ));
    }

    if (totals.ironMg < ironGoal * 0.5) {
      recs.add(Recommendation(
        message:
            'Iron is on the low side (${totals.ironMg.toStringAsFixed(1)} mg / ${ironGoal.toStringAsFixed(0)} mg).',
        suggestion: plantOnly
            ? 'Try lentils, tofu, spinach, pumpkin seeds, and pair with vitamin C foods.'
            : 'Try fish, lean red meat, legumes, and pair with vitamin C foods.',
        icon: Icons.bloodtype_outlined,
        color: Colors.red.shade500,
      ));
    }

    if (totals.calciumMg < calciumGoal * 0.45) {
      recs.add(Recommendation(
        message:
            'Calcium is low (${totals.calciumMg.toStringAsFixed(0)} mg / ${calciumGoal.toStringAsFixed(0)} mg).',
        suggestion: plantOnly
            ? 'Add fortified soy milk, calcium-set tofu, tahini, and leafy greens.'
            : 'Add yogurt, milk, cheese, sardines, or calcium-fortified alternatives.',
        icon: Icons.science_outlined,
        color: Colors.lightBlue.shade600,
      ));
    }

    if (totals.potassiumMg < potassiumGoal * 0.45) {
      recs.add(Recommendation(
        message:
            'Potassium intake is low (${totals.potassiumMg.toStringAsFixed(0)} mg / ${potassiumGoal.toStringAsFixed(0)} mg).',
        suggestion:
            'Add potatoes, beans, avocado, spinach, bananas, or yogurt for recovery and blood pressure support.',
        icon: Icons.bolt_outlined,
        color: Colors.teal.shade600,
      ));
    }

    if (totals.fiberG < NutrientDRV.fiberG * 0.5) {
      recs.add(Recommendation(
        message:
            'Fiber is low (${totals.fiberG.toStringAsFixed(1)} g / ${NutrientDRV.fiberG.toStringAsFixed(0)} g).',
        suggestion:
            'Add oats, lentils, berries, chia seeds, and vegetables to improve satiety and glucose control.',
        icon: Icons.eco_outlined,
        color: Colors.green.shade700,
      ));
    }

    if (totals.vitaminCMg < vitaminCGoal * 0.45) {
      recs.add(Recommendation(
        message:
            'Vitamin C may be low (${totals.vitaminCMg.toStringAsFixed(0)} mg / ${vitaminCGoal.toStringAsFixed(0)} mg).',
        suggestion: 'Try bell peppers, kiwi, citrus, strawberries, or broccoli.',
        icon: Icons.local_florist_outlined,
        color: Colors.orange.shade500,
      ));
    }

    if (totals.vitaminAUg < vitaminAGoal * 0.4) {
      recs.add(Recommendation(
        message:
            'Vitamin A looks low (${totals.vitaminAUg.toStringAsFixed(0)} µg / ${vitaminAGoal.toStringAsFixed(0)} µg).',
        suggestion: plantOnly
            ? 'Try carrots, sweet potato, kale, and spinach.'
            : 'Try carrots, sweet potato, spinach, eggs, and dairy.',
        icon: Icons.visibility_outlined,
        color: Colors.deepOrange.shade400,
      ));
    }

    return recs.take(4).toList();
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
