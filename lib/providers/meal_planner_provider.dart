import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custom_meal.dart';
import '../models/dietary_restriction.dart';
import '../models/food_data.dart';
import '../models/nutrition_goal.dart';
import '../models/recipe.dart';
import '../services/database_service.dart';
import '../services/recipe_repository.dart';
import '../services/recipe_swap_service.dart';

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

  /// Per-slot portion multipliers (1.0 = normal serving).
  final Map<String, double> portionMultipliers;

  final bool loading;

  const MealPlanState({
    required this.weekNumber,
    required this.year,
    this.enabledSlots = const {},
    this.assignments = const {},
    this.portionMultipliers = const {},
    this.loading = false,
  });

  /// Slot key: "${dayOfWeek}_${mealType.jsonKey}"
  static String slotKey(int dayOfWeek, RecipeMealType mealType) =>
      '${dayOfWeek}_${mealType.jsonKey}';

  bool isEnabled(int dayOfWeek, RecipeMealType mealType) =>
      enabledSlots.contains(slotKey(dayOfWeek, mealType));

  Recipe? recipeFor(int dayOfWeek, RecipeMealType mealType) =>
      assignments[slotKey(dayOfWeek, mealType)];

  double portionMultiplierFor(int dayOfWeek, RecipeMealType mealType) =>
      portionMultipliers[slotKey(dayOfWeek, mealType)] ?? 1.0;

  MealPlanState copyWith({
    Set<String>? enabledSlots,
    Map<String, Recipe>? assignments,
    Map<String, double>? portionMultipliers,
    bool? loading,
  }) =>
      MealPlanState(
        weekNumber: weekNumber,
        year: year,
        enabledSlots: enabledSlots ?? this.enabledSlots,
        assignments: assignments ?? this.assignments,
        portionMultipliers: portionMultipliers ?? this.portionMultipliers,
        loading: loading ?? this.loading,
      );
}

class MealPlanNotifier extends StateNotifier<MealPlanState> {
  MealPlanNotifier(int weekNumber, int year)
      : super(MealPlanState(weekNumber: weekNumber, year: year));

  /// The user's selected language code (en, de, nl). Set by the UI.
  String? languageCode;
  final Map<String, int> _shuffleCounts = <String, int>{};

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
    final portionMultipliers = <String, double>{};
    for (final row in rows) {
      final mealType = RecipeMealTypeX.fromJson(row['meal_type'] as String?);
      final key = MealPlanState.slotKey(row['day_of_week'] as int, mealType);
      enabled.add(key);
      portionMultipliers[key] = 1.0;
      final id = row['recipe_id'] as String;
      final recipe = recipeById[id] ?? customById[id];
      if (recipe != null) assignments[key] = recipe;
    }

    state = state.copyWith(
      loading: false,
      enabledSlots: enabled,
      assignments: assignments,
      portionMultipliers: portionMultipliers,
    );
  }

  /// Toggle a slot on/off. When turned on, auto-assigns a recipe.
  Future<void> toggleSlot(
    int dayOfWeek,
    RecipeMealType mealType,
    NutritionGoalType goal, {
    int dailyCalorieGoal = 0,
    Set<DietaryRestriction> dietaryRestrictions = const <DietaryRestriction>{},
    Set<String> pantryNames = const <String>{},
  }) async {
    final key = MealPlanState.slotKey(dayOfWeek, mealType);
    final nowEnabled = state.enabledSlots.contains(key);

    if (nowEnabled) {
      // Turn off — remove from DB and state
      final newEnabled = {...state.enabledSlots}..remove(key);
      final newAssignments = {...state.assignments}..remove(key);
      final newPortions = {...state.portionMultipliers}..remove(key);
      state = state.copyWith(
        enabledSlots: newEnabled,
        assignments: newAssignments,
        portionMultipliers: newPortions,
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
      final newPortions = {...state.portionMultipliers}
        ..putIfAbsent(key, () => 1.0);
      state = state.copyWith(
          enabledSlots: newEnabled, portionMultipliers: newPortions);
      await _assignRecipe(dayOfWeek, mealType, goal,
          forceNew: false,
          dailyCalorieGoal: dailyCalorieGoal,
          dietaryRestrictions: dietaryRestrictions,
          pantryNames: pantryNames,
          swapIntent: pantryNames.isEmpty ? null : SmartSwapIntent.pantryFirst);
      await _autoTuneDayCalories(dayOfWeek, goal, dailyCalorieGoal);
    }
  }

  /// Re-roll the recipe for an already-enabled slot.
  Future<void> shuffleSlot(
    int dayOfWeek,
    RecipeMealType mealType,
    NutritionGoalType goal, {
    int dailyCalorieGoal = 0,
    Set<DietaryRestriction> dietaryRestrictions = const <DietaryRestriction>{},
    Set<String> pantryNames = const <String>{},
  }) async {
    await _assignRecipe(dayOfWeek, mealType, goal,
        forceNew: true,
        dailyCalorieGoal: dailyCalorieGoal,
        dietaryRestrictions: dietaryRestrictions,
        pantryNames: pantryNames,
        swapIntent: pantryNames.isEmpty
            ? SmartSwapIntent.balanced
            : SmartSwapIntent.pantryFirst);
    await _autoTuneDayCalories(dayOfWeek, goal, dailyCalorieGoal);
  }

  Future<void> smartSwapSlot(
    int dayOfWeek,
    RecipeMealType mealType,
    NutritionGoalType goal, {
    required SmartSwapIntent intent,
    int dailyCalorieGoal = 0,
    Set<DietaryRestriction> dietaryRestrictions = const <DietaryRestriction>{},
    Set<String> pantryNames = const <String>{},
  }) async {
    await _assignRecipe(
      dayOfWeek,
      mealType,
      goal,
      forceNew: true,
      dailyCalorieGoal: dailyCalorieGoal,
      dietaryRestrictions: dietaryRestrictions,
      pantryNames: pantryNames,
      swapIntent: intent,
    );
    await _autoTuneDayCalories(dayOfWeek, goal, dailyCalorieGoal);
  }

  Future<void> autoFillWeek({
    required NutritionGoalType goal,
    required int dailyCalorieGoal,
    Set<DietaryRestriction> dietaryRestrictions = const <DietaryRestriction>{},
    Set<String> pantryNames = const <String>{},
    bool replaceExisting = false,
  }) async {
    state = state.copyWith(loading: true);
    if (replaceExisting) {
      await clearWeek();
    }
    const defaultMeals = <RecipeMealType>[
      RecipeMealType.breakfast,
      RecipeMealType.lunch,
      RecipeMealType.dinner,
      RecipeMealType.snack,
    ];
    final enabled = {...state.enabledSlots};
    final portions = {...state.portionMultipliers};
    for (var day = 1; day <= 7; day++) {
      for (final mealType in defaultMeals) {
        final key = MealPlanState.slotKey(day, mealType);
        if (!replaceExisting && state.assignments.containsKey(key)) continue;
        enabled.add(key);
        portions.putIfAbsent(key, () => 1.0);
      }
    }
    state = state.copyWith(
      enabledSlots: enabled,
      portionMultipliers: portions,
      loading: false,
    );
    for (var day = 1; day <= 7; day++) {
      for (final mealType in defaultMeals) {
        final key = MealPlanState.slotKey(day, mealType);
        if (!replaceExisting && state.assignments.containsKey(key)) continue;
        await _assignRecipe(
          day,
          mealType,
          goal,
          forceNew: true,
          dailyCalorieGoal: dailyCalorieGoal,
          dietaryRestrictions: dietaryRestrictions,
          pantryNames: pantryNames,
          swapIntent: pantryNames.isEmpty
              ? SmartSwapIntent.balanced
              : SmartSwapIntent.pantryFirst,
        );
      }
      await _autoTuneDayCalories(day, goal, dailyCalorieGoal);
    }
  }

  /// Replace the recipe for a slot with the given recipe.
  Future<void> assignRecipe(
    int dayOfWeek,
    RecipeMealType mealType,
    Recipe recipe, {
    NutritionGoalType goal = NutritionGoalType.maintain,
    int dailyCalorieGoal = 0,
  }) async {
    final key = MealPlanState.slotKey(dayOfWeek, mealType);
    final newEnabled = {...state.enabledSlots}..add(key);
    final newAssignments = {...state.assignments}..[key] = recipe;
    final newPortions = {...state.portionMultipliers}
      ..putIfAbsent(key, () => 1.0);
    state = state.copyWith(
      enabledSlots: newEnabled,
      assignments: newAssignments,
      portionMultipliers: newPortions,
    );
    await DatabaseService.instance.upsertMealPlanEntry(
      weekNumber: state.weekNumber,
      year: state.year,
      dayOfWeek: dayOfWeek,
      mealType: mealType.jsonKey,
      recipeId: recipe.id,
      recipeName: recipe.name,
    );
    // Recalculate portions for the whole day after swapping a recipe.
    if (dailyCalorieGoal > 0) {
      await _autoTuneDayCalories(dayOfWeek, goal, dailyCalorieGoal);
    }
  }

  Future<void> _assignRecipe(
    int dayOfWeek,
    RecipeMealType mealType,
    NutritionGoalType goal, {
    required bool forceNew,
    int dailyCalorieGoal = 0,
    Set<DietaryRestriction> dietaryRestrictions = const <DietaryRestriction>{},
    Set<String> pantryNames = const <String>{},
    SmartSwapIntent? swapIntent,
  }) async {
    final key = MealPlanState.slotKey(dayOfWeek, mealType);
    final currentId = state.assignments[key]?.id;

    final candidates = await RecipeRepository.instance.query(
      goal: goal,
      mealType: mealType,
      limit: 1000,
      language: languageCode,
      dietaryRestrictions: dietaryRestrictions,
    );

    if (candidates.isEmpty) return;

    // Avoid already-assigned recipes across the whole week when possible
    final usedIds = state.assignments.values.map((r) => r.id).toSet();
    final fresh = candidates.where((r) => !usedIds.contains(r.id)).toList();
    var pool = (fresh.isNotEmpty && (forceNew || currentId == null))
        ? fresh
        : candidates;
    if (forceNew && currentId != null) {
      final withoutCurrent = pool.where((r) => r.id != currentId).toList();
      if (withoutCurrent.isNotEmpty) pool = withoutCurrent;
    }

    // ── Calorie-budget filtering ──────────────────────────────────────────
    // If the caller provided a daily calorie goal, pick a recipe that keeps
    // the day's total close to the target.
    if (dailyCalorieGoal > 0) {
      // Sum calories already assigned for this day
      int usedCalories = 0;
      for (final mt in RecipeMealType.values) {
        final dayKey = MealPlanState.slotKey(dayOfWeek, mt);
        if (dayKey == key) continue; // skip the slot we're filling
        final r = state.assignments[dayKey];
        if (r != null) usedCalories += r.caloriesPerServing(r.servings);
      }
      final remaining = dailyCalorieGoal - usedCalories;

      // Prefer recipes within ±30% of a fair share of the remaining budget
      final targetCal = remaining.clamp(100, dailyCalorieGoal);
      final lo = (targetCal * 0.5).round();
      final hi = (targetCal * 1.3).round();
      final calorieFiltered = pool
          .where((r) =>
              r.caloriesPerServing(r.servings) >= lo &&
              r.caloriesPerServing(r.servings) <= hi)
          .toList();
      if (calorieFiltered.isNotEmpty) pool = calorieFiltered;
    }

    final recipe = swapIntent == null
        ? _pickRandomRecipe(pool, key, dayOfWeek, mealType)
        : (RecipeSwapService.pickBestSwap(
              current: state.assignments[key],
              candidates: pool,
              intent: swapIntent,
              goal: goal,
              pantryNames: pantryNames,
              usedRecipeIds: usedIds,
            ) ??
            _pickRandomRecipe(pool, key, dayOfWeek, mealType));

    final newAssignments = {...state.assignments}..[key] = recipe;
    final newPortions = {...state.portionMultipliers}
      ..putIfAbsent(key, () => 1.0);
    state = state.copyWith(
        assignments: newAssignments, portionMultipliers: newPortions);

    await DatabaseService.instance.upsertMealPlanEntry(
      weekNumber: state.weekNumber,
      year: state.year,
      dayOfWeek: dayOfWeek,
      mealType: mealType.jsonKey,
      recipeId: recipe.id,
      recipeName: recipe.name,
    );
  }

  Recipe _pickRandomRecipe(
    List<Recipe> pool,
    String key,
    int dayOfWeek,
    RecipeMealType mealType,
  ) {
    final shuffleCount = (_shuffleCounts[key] ?? 0) + 1;
    _shuffleCounts[key] = shuffleCount;
    final rng = Random(Object.hash(
      state.year,
      state.weekNumber,
      dayOfWeek,
      mealType.index,
      shuffleCount,
      DateTime.now().microsecondsSinceEpoch,
    ));
    pool.shuffle(rng);
    return pool[rng.nextInt(pool.length)];
  }

  int _dayCalories(int dayOfWeek) {
    int total = 0;
    for (final mt in RecipeMealType.values) {
      final key = MealPlanState.slotKey(dayOfWeek, mt);
      if (!state.enabledSlots.contains(key)) continue;
      final recipe = state.assignments[key];
      if (recipe == null) continue;
      final mult = state.portionMultipliers[key] ?? 1.0;
      total += (recipe.caloriesPerServing(recipe.servings) * mult).round();
    }
    return total;
  }

  Future<void> _autoTuneDayCalories(
    int dayOfWeek,
    NutritionGoalType goal,
    int dailyCalorieGoal,
  ) async {
    if (dailyCalorieGoal <= 0) return;

    // Reset all portion multipliers to 1.0 for this day first, then recalculate.
    final newPortions = {...state.portionMultipliers};
    for (final mt in RecipeMealType.values) {
      final key = MealPlanState.slotKey(dayOfWeek, mt);
      if (state.enabledSlots.contains(key) && state.assignments[key] != null) {
        newPortions[key] = 1.0;
      }
    }
    state = state.copyWith(portionMultipliers: newPortions);

    // Recompute deficit after resetting to base portions.
    final deficit = dailyCalorieGoal - _dayCalories(dayOfWeek);

    // Scale portions proportionally to fill the remaining budget.
    if (deficit.abs() > 50) {
      final adjustable = <String>[];
      for (final mt in RecipeMealType.values) {
        final key = MealPlanState.slotKey(dayOfWeek, mt);
        if (state.enabledSlots.contains(key) &&
            state.assignments[key] != null) {
          adjustable.add(key);
        }
      }
      if (adjustable.isNotEmpty) {
        // Calculate total base calories for the day.
        int baseCal = 0;
        for (final key in adjustable) {
          baseCal += state.assignments[key]!
              .caloriesPerServing(state.assignments[key]!.servings);
        }
        if (baseCal > 0) {
          // Single uniform multiplier that brings the total to the target.
          final multiplier = (dailyCalorieGoal / baseCal).clamp(0.8, 1.5);
          final updated = {...state.portionMultipliers};
          for (final key in adjustable) {
            updated[key] = multiplier;
          }
          state = state.copyWith(portionMultipliers: updated);
        }
      }
    }
  }

  Future<void> clearWeek() async {
    await DatabaseService.instance.clearMealPlanWeek(
      weekNumber: state.weekNumber,
      year: state.year,
    );
    state = state.copyWith(
      enabledSlots: {},
      assignments: {},
      portionMultipliers: {},
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

final mealPlanProvider = StateNotifierProvider<MealPlanNotifier, MealPlanState>(
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
