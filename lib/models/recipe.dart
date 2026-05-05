import 'package:flutter/foundation.dart';

import 'nutrition_goal.dart';

enum RecipeMealType { breakfast, lunch, dinner, snack, dessert }

extension RecipeMealTypeX on RecipeMealType {
  String get jsonKey {
    switch (this) {
      case RecipeMealType.breakfast: return 'breakfast';
      case RecipeMealType.lunch:     return 'lunch';
      case RecipeMealType.dinner:    return 'dinner';
      case RecipeMealType.snack:     return 'snack';
      case RecipeMealType.dessert:   return 'dessert';
    }
  }

  String get label {
    switch (this) {
      case RecipeMealType.breakfast: return 'Breakfast';
      case RecipeMealType.lunch:     return 'Lunch';
      case RecipeMealType.dinner:    return 'Dinner';
      case RecipeMealType.snack:     return 'Snack';
      case RecipeMealType.dessert:   return 'Dessert';
    }
  }

  String get emoji {
    switch (this) {
      case RecipeMealType.breakfast: return '🍳';
      case RecipeMealType.lunch:     return '🥗';
      case RecipeMealType.dinner:    return '🍽️';
      case RecipeMealType.snack:     return '🍎';
      case RecipeMealType.dessert:   return '🍰';
    }
  }

  static RecipeMealType fromJson(String? key) {
    switch (key) {
      case 'breakfast': return RecipeMealType.breakfast;
      case 'lunch':     return RecipeMealType.lunch;
      case 'snack':     return RecipeMealType.snack;
      case 'dessert':   return RecipeMealType.dessert;
      default:          return RecipeMealType.dinner;
    }
  }
}

@immutable
class RecipeIngredient {
  const RecipeIngredient({required this.name, required this.amount});
  final String name;
  final String amount;

  factory RecipeIngredient.fromJson(Map<String, dynamic> j) =>
      RecipeIngredient(
        name: (j['name'] as String?)?.trim() ?? '',
        amount: (j['amount'] as String?)?.trim() ?? '',
      );
}

@immutable
class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.image,
    required this.mealType,
    required this.goals,
    required this.minutes,
    required this.servings,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.sugarG,
    required this.tags,
    required this.ingredients,
    required this.steps,
    required this.source,
  });

  final String id;
  final String name;
  final String? image;
  final RecipeMealType mealType;
  final Set<NutritionGoalType> goals;
  final int minutes;
  final int servings;
  final int calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final double sugarG;
  final List<String> tags;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;
  final String source;

  bool get hasMacros => calories > 0;

  /// Per-serving values.
  int caloriesPerServing(int s) => (calories / s).round();
  double proteinPerServing(int s) => proteinG / s;
  double carbsPerServing(int s) => carbsG / s;
  double fatPerServing(int s) => fatG / s;
  double fiberPerServing(int s) => fiberG / s;
  double sugarPerServing(int s) => sugarG / s;

  factory Recipe.fromJson(Map<String, dynamic> j) {
    final goalsRaw = (j['goals'] as List?)?.cast<String>() ?? const [];
    return Recipe(
      id: j['id'] as String,
      name: (j['name'] as String?)?.trim() ?? '',
      image: (j['image'] as String?)?.trim().isEmpty ?? true
          ? null
          : (j['image'] as String).trim(),
      mealType: RecipeMealTypeX.fromJson(j['meal_type'] as String?),
      goals: goalsRaw.map(_goalFromKey).whereType<NutritionGoalType>().toSet(),
      minutes: (j['minutes'] as num?)?.toInt() ?? 30,
      servings: (j['servings'] as num?)?.toInt() ?? 1,
      calories: (j['calories'] as num?)?.toInt() ?? 0,
      proteinG: (j['protein_g'] as num?)?.toDouble() ?? 0,
      carbsG: (j['carbs_g'] as num?)?.toDouble() ?? 0,
      fatG: (j['fat_g'] as num?)?.toDouble() ?? 0,
      fiberG: (j['fiber_g'] as num?)?.toDouble() ?? 0,
      sugarG: (j['sugar_g'] as num?)?.toDouble() ?? 0,
      tags: ((j['tags'] as List?) ?? const [])
          .cast<dynamic>()
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList(),
      ingredients: ((j['ingredients'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(RecipeIngredient.fromJson)
          .where((i) => i.name.isNotEmpty)
          .toList(),
      steps: ((j['steps'] as List?) ?? const [])
          .cast<dynamic>()
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      source: (j['source'] as String?) ?? 'Unknown',
    );
  }

  static NutritionGoalType? _goalFromKey(String k) {
    switch (k) {
      case 'muscle':       return NutritionGoalType.muscleGrowth;
      case 'diabetes':     return NutritionGoalType.diabetes;
      case 'vegan':        return NutritionGoalType.vegan;
      case 'weight_loss':  return NutritionGoalType.weightLoss;
      case 'keto':         return NutritionGoalType.keto;
      case 'maintain':     return NutritionGoalType.maintain;
    }
    return null;
  }
}
