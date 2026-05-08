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
  const RecipeIngredient({
    required this.name,
    required this.amount,
    required this.grams,
  });
  final String name;
  final String amount;
  final double grams;

  factory RecipeIngredient.fromJson(Map<String, dynamic> j) =>
      RecipeIngredient(
        name: (j['name'] as String?)?.trim() ?? '',
        amount: (j['amount'] as String?)?.trim() ?? '',
        grams: (j['grams'] as num?)?.toDouble() ?? 0,
      );

  RecipeIngredient copyWithGrams(double newGrams) => RecipeIngredient(
        name: name,
        amount: '${newGrams.round()}g',
        grams: newGrams,
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
    this.vitaminAUg = 0,
    this.vitaminCMg = 0,
    this.vitaminDUg = 0,
    this.vitaminEMg = 0,
    this.vitaminKUg = 0,
    this.vitaminB12Ug = 0,
    this.folateUg = 0,
    this.calciumMg = 0,
    this.ironMg = 0,
    this.magnesiumMg = 0,
    this.potassiumMg = 0,
    this.zincMg = 0,
    this.sodiumMg = 0,
    this.glycemicIndex = 0,
    this.glycemicLoad = 0,
    this.insulinUnits = 0,
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

  // Micronutrients
  final double vitaminAUg;
  final double vitaminCMg;
  final double vitaminDUg;
  final double vitaminEMg;
  final double vitaminKUg;
  final double vitaminB12Ug;
  final double folateUg;
  final double calciumMg;
  final double ironMg;
  final double magnesiumMg;
  final double potassiumMg;
  final double zincMg;
  final double sodiumMg;

  // Glycemic & insulin
  final int glycemicIndex;
  final double glycemicLoad;
  final double insulinUnits;

  bool get hasMacros => calories > 0;

  /// Per-serving values.
  int caloriesPerServing(int s) => (calories / s).round();
  double proteinPerServing(int s) => proteinG / s;
  double carbsPerServing(int s) => carbsG / s;
  double fatPerServing(int s) => fatG / s;
  double fiberPerServing(int s) => fiberG / s;
  double sugarPerServing(int s) => sugarG / s;

  /// Insulin units for a given number of servings.
  /// Uses standard ICR (Insulin-to-Carb Ratio) of 1:10 by default.
  double insulinForServings(int s, {double icr = 10}) {
    final netCarbs = (carbsG - fiberG).clamp(0, double.infinity) / s;
    return netCarbs / icr;
  }

  /// Recalculate nutrition when ingredient grams are adjusted.
  /// [scale] is the ratio newGrams/originalGrams for proportional scaling.
  Recipe scaledBy(double scale) => Recipe(
        id: id,
        name: name,
        image: image,
        mealType: mealType,
        goals: goals,
        minutes: minutes,
        servings: servings,
        calories: (calories * scale).round(),
        proteinG: proteinG * scale,
        carbsG: carbsG * scale,
        fatG: fatG * scale,
        fiberG: fiberG * scale,
        sugarG: sugarG * scale,
        vitaminAUg: vitaminAUg * scale,
        vitaminCMg: vitaminCMg * scale,
        vitaminDUg: vitaminDUg * scale,
        vitaminEMg: vitaminEMg * scale,
        vitaminKUg: vitaminKUg * scale,
        vitaminB12Ug: vitaminB12Ug * scale,
        folateUg: folateUg * scale,
        calciumMg: calciumMg * scale,
        ironMg: ironMg * scale,
        magnesiumMg: magnesiumMg * scale,
        potassiumMg: potassiumMg * scale,
        zincMg: zincMg * scale,
        sodiumMg: sodiumMg * scale,
        glycemicIndex: glycemicIndex,
        glycemicLoad: glycemicLoad * scale,
        insulinUnits: insulinUnits * scale,
        tags: tags,
        ingredients: ingredients
            .map((i) => i.copyWithGrams(i.grams * scale))
            .toList(),
        steps: steps,
        source: source,
      );

  factory Recipe.fromJson(Map<String, dynamic> j) {
    final goalsRaw = (j['goals'] as List?)?.cast<String>() ?? const [];
    final id = (j['id'] as String?)?.trim() ?? '';
    final name = (j['name'] as String?)?.trim() ?? '';
    final rawImage = (j['image'] as String?)?.trim() ?? '';
    return Recipe(
      id: id,
      name: name,
      image: rawImage.isNotEmpty ? rawImage : _internetImageForRecipe(name, id),
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
      vitaminAUg: (j['vitamin_a_ug'] as num?)?.toDouble() ?? 0,
      vitaminCMg: (j['vitamin_c_mg'] as num?)?.toDouble() ?? 0,
      vitaminDUg: (j['vitamin_d_ug'] as num?)?.toDouble() ?? 0,
      vitaminEMg: (j['vitamin_e_mg'] as num?)?.toDouble() ?? 0,
      vitaminKUg: (j['vitamin_k_ug'] as num?)?.toDouble() ?? 0,
      vitaminB12Ug: (j['vitamin_b12_ug'] as num?)?.toDouble() ?? 0,
      folateUg: (j['folate_ug'] as num?)?.toDouble() ?? 0,
      calciumMg: (j['calcium_mg'] as num?)?.toDouble() ?? 0,
      ironMg: (j['iron_mg'] as num?)?.toDouble() ?? 0,
      magnesiumMg: (j['magnesium_mg'] as num?)?.toDouble() ?? 0,
      potassiumMg: (j['potassium_mg'] as num?)?.toDouble() ?? 0,
      zincMg: (j['zinc_mg'] as num?)?.toDouble() ?? 0,
      sodiumMg: (j['sodium_mg'] as num?)?.toDouble() ?? 0,
      glycemicIndex: (j['glycemic_index'] as num?)?.toInt() ?? 0,
      glycemicLoad: (j['glycemic_load'] as num?)?.toDouble() ?? 0,
      insulinUnits: (j['insulin_units'] as num?)?.toDouble() ?? 0,
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

  static String _internetImageForRecipe(String name, String id) {
    final normalized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final query = Uri.encodeComponent(
      normalized.isEmpty ? 'healthy food recipe' : '$normalized food dish',
    );
    final seed = _stableSeed(id.isNotEmpty ? id : name);
    return 'https://source.unsplash.com/900x900/?$query&sig=$seed';
  }

  static int _stableSeed(String input) {
    var hash = 7;
    for (final code in input.codeUnits) {
      hash = (hash * 31 + code) % 100000;
    }
    return hash.abs();
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
