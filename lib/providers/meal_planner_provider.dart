import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custom_meal.dart';
import '../models/food_data.dart';
import '../models/nutrition_goal.dart';
import '../models/recipe.dart';
import '../services/database_service.dart';
import '../services/recipe_repository.dart';

/// Key: (dayOfWeek, mealType) → Recipe or null.
typedef SlotMap = Map<String, Recipe?>;

/// State for the weekly meal planner.
class MealPlanState {
  final int weekNumber;
  final int year;

  /// Which (day, mealType) slots the user has enabled (wants a recipe for).
  final Set<String> enabledSlots;

  /// Assigned recipes per slot.
  final Map<String, Recipe> assignments;

  final bool loading;

  const MealPlanState({
    required this.weekNumber,
    required this.year,
    this.enabledSlots = const {},
    this.assignments = const {},
    this.loading = false,
  });

  /// Slot key: "${dayOfWeek}_${mealType.jsonKey}"
  static String slotKey(int dayOfWeek, RecipeMealType mealType) =>
      '${dayOfWeek}_${mealType.jsonKey}';

  bool isEnabled(int dayOfWeek, RecipeMealType mealType) =>
      enabledSlots.contains(slotKey(dayOfWeek, mealType));

  Recipe? recipeFor(int dayOfWeek, RecipeMealType mealType) =>
      assignments[slotKey(dayOfWeek, mealType)];

  MealPlanState copyWith({
    Set<String>? enabledSlots,
    Map<String, Recipe>? assignments,
    bool? loading,
  }) =>
      MealPlanState(
        weekNumber: weekNumber,
        year: year,
        enabledSlots: enabledSlots ?? this.enabledSlots,
        assignments: assignments ?? this.assignments,
        loading: loading ?? this.loading,
      );
}

class MealPlanNotifier extends StateNotifier<MealPlanState> {
  MealPlanNotifier(int weekNumber, int year)
      : super(MealPlanState(weekNumber: weekNumber, year: year));

  /// Load saved plan from DB.
  Future<void> load(NutritionGoalType goal) async {
    state = state.copyWith(loading: true);
    final rows = await DatabaseService.instance.getMealPlanEntries(
      weekNumber: state.weekNumber,
      year: state.year,
    );

    if (rows.isEmpty) {
      state = state.copyWith(loading: false);
      return;
    }

    final allRecipes = await RecipeRepository.instance.all();
    final recipeById = {for (final r in allRecipes) r.id: r};

    // Also load custom meals so we can restore 'custom:N' plan entries
    final allCustomMeals = await DatabaseService.instance.getCustomMeals();
    final allFoods = await DatabaseService.instance.getAllFoods();
    final customById = <String, Recipe>{
      for (final m in allCustomMeals)
        if (m.id != null) 'custom:${m.id}': _customMealToRecipe(m, allFoods),
    };

    final enabled = <String>{};
    final assignments = <String, Recipe>{};
    for (final row in rows) {
      final mealType = RecipeMealTypeX.fromJson(row['meal_type'] as String?);
      final key = MealPlanState.slotKey(row['day_of_week'] as int, mealType);
      enabled.add(key);
      final id = row['recipe_id'] as String;
      final recipe = recipeById[id] ?? customById[id];
      if (recipe != null) assignments[key] = recipe;
    }

    state = state.copyWith(
      loading: false,
      enabledSlots: enabled,
      assignments: assignments,
    );
  }

  /// Toggle a slot on/off. When turned on, auto-assigns a recipe.
  Future<void> toggleSlot(
    int dayOfWeek,
    RecipeMealType mealType,
    NutritionGoalType goal,
  ) async {
    final key = MealPlanState.slotKey(dayOfWeek, mealType);
    final nowEnabled = state.enabledSlots.contains(key);

    if (nowEnabled) {
      // Turn off — remove from DB and state
      final newEnabled = {...state.enabledSlots}..remove(key);
      final newAssignments = {...state.assignments}..remove(key);
      state = state.copyWith(
        enabledSlots: newEnabled,
        assignments: newAssignments,
      );
      await DatabaseService.instance.deleteMealPlanEntry(
        weekNumber: state.weekNumber,
        year: state.year,
        dayOfWeek: dayOfWeek,
        mealType: mealType.jsonKey,
      );
    } else {
      // Turn on — pick a recipe and save
      final newEnabled = {...state.enabledSlots}..add(key);
      state = state.copyWith(enabledSlots: newEnabled);
      await _assignRecipe(dayOfWeek, mealType, goal, forceNew: false);
    }
  }

  /// Re-roll the recipe for an already-enabled slot.
  Future<void> shuffleSlot(
    int dayOfWeek,
    RecipeMealType mealType,
    NutritionGoalType goal,
  ) async {
    await _assignRecipe(dayOfWeek, mealType, goal, forceNew: true);
  }

  /// Replace the recipe for a slot with the given recipe.
  Future<void> assignRecipe(
    int dayOfWeek,
    RecipeMealType mealType,
    Recipe recipe,
  ) async {
    final key = MealPlanState.slotKey(dayOfWeek, mealType);
    final newEnabled = {...state.enabledSlots}..add(key);
    final newAssignments = {...state.assignments}..[key] = recipe;
    state = state.copyWith(
      enabledSlots: newEnabled,
      assignments: newAssignments,
    );
    await DatabaseService.instance.upsertMealPlanEntry(
      weekNumber: state.weekNumber,
      year: state.year,
      dayOfWeek: dayOfWeek,
      mealType: mealType.jsonKey,
      recipeId: recipe.id,
      recipeName: recipe.name,
    );
  }

  Future<void> _assignRecipe(
    int dayOfWeek,
    RecipeMealType mealType,
    NutritionGoalType goal, {
    required bool forceNew,
  }) async {
    final key = MealPlanState.slotKey(dayOfWeek, mealType);
    final currentId = state.assignments[key]?.id;

    final candidates = await RecipeRepository.instance.query(
      goal: goal,
      mealType: mealType,
      limit: 1000,
    );

    if (candidates.isEmpty) return;

    // Avoid already-assigned recipes across the whole week when possible
    final usedIds = state.assignments.values.map((r) => r.id).toSet();
    final fresh = candidates.where((r) => !usedIds.contains(r.id)).toList();
    final pool = (fresh.isNotEmpty && (forceNew || currentId == null))
        ? fresh
        : candidates;

    // Pick deterministically but varied — seed from day + mealType + current assignments count
    final rng = Random(dayOfWeek * 100 + mealType.index + state.assignments.length);
    final recipe = pool[rng.nextInt(pool.length)];

    final newAssignments = {...state.assignments}..[key] = recipe;
    state = state.copyWith(assignments: newAssignments);

    await DatabaseService.instance.upsertMealPlanEntry(
      weekNumber: state.weekNumber,
      year: state.year,
      dayOfWeek: dayOfWeek,
      mealType: mealType.jsonKey,
      recipeId: recipe.id,
      recipeName: recipe.name,
    );
  }

  Future<void> clearWeek() async {
    await DatabaseService.instance.clearMealPlanWeek(
      weekNumber: state.weekNumber,
      year: state.year,
    );
    state = state.copyWith(
      enabledSlots: {},
      assignments: {},
    );
  }
}

// ── Current ISO week helpers ──────────────────────────────────────────────

int _isoWeekNumber(DateTime date) {
  final startOfYear = DateTime(date.year, 1, 1);
  final firstMonday = startOfYear.weekday <= 4
      ? startOfYear.subtract(Duration(days: startOfYear.weekday - 1))
      : startOfYear.add(Duration(days: 8 - startOfYear.weekday));
  return ((date.difference(firstMonday).inDays) / 7).floor() + 1;
}

final _now = DateTime.now();

final mealPlanProvider =
    StateNotifierProvider<MealPlanNotifier, MealPlanState>(
  (ref) => MealPlanNotifier(_isoWeekNumber(_now), _now.year),
);

/// Converts a [CustomMeal] to a [Recipe] for use in the meal planner.
/// The recipe id uses the prefix 'custom:' to distinguish from JSON recipes.
Recipe _customMealToRecipe(CustomMeal meal, List<FoodData> foods) {
  final kcalMap = {for (final f in foods) f.label: f.kcalPer100g};
  final proteinMap = {for (final f in foods) f.label: f.proteinPer100g};
  final carbsMap = {for (final f in foods) f.label: f.carbsPer100g};
  final fatMap = {for (final f in foods) f.label: f.fatPer100g};

  double totalKcal = 0;
  double totalProtein = 0;
  double totalCarbs = 0;
  double totalFat = 0;

  for (final ing in meal.ingredients) {
    final g = ing.grams / 100.0;
    totalKcal += (kcalMap[ing.foodLabel] ?? 0) * g;
    totalProtein += (proteinMap[ing.foodLabel] ?? 0) * g;
    totalCarbs += (carbsMap[ing.foodLabel] ?? 0) * g;
    totalFat += (fatMap[ing.foodLabel] ?? 0) * g;
  }

  final mealType = switch (meal.mealType) {
    MealType.breakfast => RecipeMealType.breakfast,
    MealType.lunch => RecipeMealType.lunch,
    MealType.dinner => RecipeMealType.dinner,
  };

  return Recipe(
    id: 'custom:${meal.id ?? 0}',
    name: meal.name,
    image: meal.imagePath,
    mealType: mealType,
    goals: const {},
    minutes: 0,
    servings: 1,
    calories: totalKcal.round(),
    proteinG: totalProtein,
    carbsG: totalCarbs,
    fatG: totalFat,
    fiberG: 0,
    sugarG: 0,
    tags: const ['custom'],
    ingredients: meal.ingredients
        .map((i) => RecipeIngredient(
              name: i.foodLabel,
              amount: '${i.grams.round()}g',
              grams: i.grams,
            ))
        .toList(),
    steps: const [],
    source: 'custom',
  );
}
