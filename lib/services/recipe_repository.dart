import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrition_goal.dart';
import '../models/recipe.dart';

/// Loads real scraped recipes from the bundled offline JSON asset.
class RecipeRepository {
  RecipeRepository._();
  static final RecipeRepository instance = RecipeRepository._();

  List<Recipe>? _cache;
  Future<List<Recipe>>? _inFlight;

  /// Clear cached results after the bundled recipe asset changes.
  void clearCache() {
    _cache = null;
    _inFlight = null;
  }

  Future<List<Recipe>> all() {
    if (_cache != null) return Future.value(_cache);
    return _inFlight ??= _load();
  }

  Future<List<Recipe>> _load() async {
    final list = await _loadAssetRecipes('assets/bundled_recipes.json');
    _cache = list;
    _inFlight = null;
    return list;
  }

  Future<List<Recipe>> _loadAssetRecipes(String assetPath) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      return (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(Recipe.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <Recipe>[];
    }
  }

  /// Filter + score for ranking. Recipes matching all selected facets win.
  Future<List<Recipe>> query({
    NutritionGoalType? goal,
    RecipeMealType? mealType,
    String? search,
    int maxMinutes = 0,
    int limit = 0,
    bool strictGoalRules = true,
    bool includeGenerated = false,
  }) async {
    final q = (search ?? '').trim().toLowerCase();
    final list = await all();
    final filtered = <Recipe>[];
    for (final r in list) {
      if (!includeGenerated && r.source.toLowerCase() == 'generated') continue;
      if (goal != null && !r.goals.contains(goal)) continue;
      if (goal != null &&
          strictGoalRules &&
          !_isRecipeEligibleForGoal(r, goal)) {
        continue;
      }
      if (mealType != null && r.mealType != mealType) continue;
      if (maxMinutes > 0 && r.minutes > maxMinutes) continue;
      if (q.isNotEmpty) {
        // Match against individual ingredient names so searching "bread"
        // only returns recipes that have bread in their ingredient list,
        // not recipes whose name or other ingredients accidentally contain
        // the substring. Also allow recipe name match for category queries.
        final ingredientMatch =
            r.ingredients.any((i) => i.name.toLowerCase().contains(q));
        final nameMatch = r.name.toLowerCase().contains(q);
        if (!ingredientMatch && !nameMatch) continue;
      }
      filtered.add(r);
    }
    // Sort alphabetically by name.
    filtered
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (limit > 0 && filtered.length > limit) return filtered.sublist(0, limit);
    return filtered;
  }

  bool _isRecipeEligibleForGoal(Recipe recipe, NutritionGoalType goal) {
    final carbsPerServing = recipe.carbsPerServing(recipe.servings);
    final proteinPerServing = recipe.proteinPerServing(recipe.servings);
    final caloriesPerServing = recipe.caloriesPerServing(recipe.servings);
    final gi = recipe.glycemicIndex;

    switch (goal) {
      case NutritionGoalType.diabetes:
        // Strong diabetes safety rule: breakfast must stay very low-carb.
        if (recipe.mealType == RecipeMealType.breakfast &&
            carbsPerServing > 20) {
          return false;
        }
        // Other meals should still avoid large carb spikes.
        if (recipe.mealType != RecipeMealType.breakfast &&
            carbsPerServing > 35) {
          return false;
        }
        if (gi > 0 && gi > 55) return false;
        return true;

      case NutritionGoalType.keto:
        return carbsPerServing <= 20;

      case NutritionGoalType.weightLoss:
        return caloriesPerServing <= 600 && proteinPerServing >= 15;

      case NutritionGoalType.muscleGrowth:
        final minCalories = switch (recipe.mealType) {
          RecipeMealType.breakfast => 450,
          RecipeMealType.lunch => 550,
          RecipeMealType.dinner => 650,
          RecipeMealType.snack => 250,
          RecipeMealType.dessert => 350,
        };
        return proteinPerServing >= 30 && caloriesPerServing >= minCalories;

      case NutritionGoalType.vegan:
        return _isVeganRecipe(recipe);
      case NutritionGoalType.vegetarian:
        return _isVegetarianRecipe(recipe);
      case NutritionGoalType.maintain:
        return true;
    }
  }

  bool _isVeganRecipe(Recipe recipe) {
    final text = _recipeIngredientText(recipe);
    return !_containsAnyTerm(text, _meatSeafoodTerms) &&
        !_containsAnyTerm(text, _dairyEggHoneyTerms);
  }

  bool _isVegetarianRecipe(Recipe recipe) {
    final text = _recipeIngredientText(recipe);
    return !_containsAnyTerm(text, _meatSeafoodTerms);
  }

  String _recipeIngredientText(Recipe recipe) {
    return recipe.ingredients
        .map((ingredient) => '${ingredient.name} ${ingredient.amount}')
        .join(' ')
        .toLowerCase();
  }

  bool _containsAnyTerm(String text, List<String> terms) {
    for (final term in terms) {
      final escaped = RegExp.escape(term.toLowerCase());
      if (RegExp('(^|[^a-z])$escaped([^a-z]|\u{0000})')
          .hasMatch('$text\u{0000}')) {
        return true;
      }
    }
    return false;
  }

  static const _meatSeafoodTerms = [
    'beef',
    'steak',
    'chicken',
    'pork',
    'bacon',
    'ham',
    'turkey',
    'lamb',
    'veal',
    'duck',
    'fish',
    'salmon',
    'tuna',
    'shrimp',
    'prawn',
    'anchovy',
    'gelatin',
    'gelatine',
    'salami',
    'sausage',
    'prosciutto',
    'chorizo',
    'pancetta',
    'kip',
    'rund',
    'varken',
    'spek',
    'hähnchen',
    'haehnchen',
    'huhn',
    'rind',
    'schwein',
    'speck',
    'schinken',
    'wurst',
    'kurczak',
    'wołow',
    'wolow',
    'wieprz',
    'pollo',
    'ternera',
    'cerdo',
    'jamón',
    'jamon',
  ];

  static const _dairyEggHoneyTerms = [
    'egg',
    'milk',
    'cream',
    'butter',
    'cheese',
    'cheddar',
    'feta',
    'mozzarella',
    'parmesan',
    'ricotta',
    'goat cheese',
    'cream cheese',
    'yogurt',
    'yoghurt',
    'honey',
    'mayonnaise',
    'whey',
    'ghee',
    'ei',
    'melk',
    'kaas',
    'boter',
    'milch',
    'käse',
    'kaese',
    'jaj',
    'mleko',
    'ser',
    'masło',
    'maslo',
    'huevo',
    'leche',
    'queso',
    'mantequilla',
    'miel',
  ];
}

final recipeRepositoryProvider = Provider<RecipeRepository>(
  (ref) => RecipeRepository.instance,
);

class RecipeQueryState {
  const RecipeQueryState({
    this.goal,
    this.mealType,
    this.search = '',
    this.maxMinutes = 0,
  });
  final NutritionGoalType? goal;
  final RecipeMealType? mealType;
  final String search;
  final int maxMinutes;

  RecipeQueryState copyWith({
    NutritionGoalType? goal,
    RecipeMealType? mealType,
    String? search,
    int? maxMinutes,
    bool clearGoal = false,
    bool clearMealType = false,
  }) =>
      RecipeQueryState(
        goal: clearGoal ? null : (goal ?? this.goal),
        mealType: clearMealType ? null : (mealType ?? this.mealType),
        search: search ?? this.search,
        maxMinutes: maxMinutes ?? this.maxMinutes,
      );
}

class RecipeQueryNotifier extends StateNotifier<RecipeQueryState> {
  RecipeQueryNotifier() : super(const RecipeQueryState());

  void setGoal(NutritionGoalType? g) =>
      state = state.copyWith(goal: g, clearGoal: g == null);
  void setMealType(RecipeMealType? m) =>
      state = state.copyWith(mealType: m, clearMealType: m == null);
  void setSearch(String s) => state = state.copyWith(search: s);
  void setMaxMinutes(int m) => state = state.copyWith(maxMinutes: m);
  void clear() => state = const RecipeQueryState();
}

final recipeQueryProvider =
    StateNotifierProvider<RecipeQueryNotifier, RecipeQueryState>(
  (_) => RecipeQueryNotifier(),
);

final recipeResultsProvider = FutureProvider<List<Recipe>>((ref) async {
  final q = ref.watch(recipeQueryProvider);
  return RecipeRepository.instance.query(
    goal: q.goal,
    mealType: q.mealType,
    search: q.search,
    maxMinutes: q.maxMinutes,
  );
});
