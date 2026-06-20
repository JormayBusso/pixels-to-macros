import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrition_goal.dart';
import '../models/recipe.dart';
import '../providers/locale_provider.dart';

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
    String? language,
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
    final localized = _applyLanguagePreference(
      filtered,
      requestedLanguage: language,
      goal: goal,
      mealType: mealType,
    );
    // If strict rules removed too many focus-bucket recipes, try a relaxed
    // second pass: include recipes that have the goal tag but failed the
    // strict eligibility check. This helps top-up empty locales for
    // muscle/vegan/diabetes/keto breakfast and lunch.
    if (strictGoalRules &&
        _isFocusMealBucket(goal, mealType) &&
        localized.length < _focusBucketFallbackLimit) {
      final relaxed = <Recipe>[];
      for (final r in list) {
        if (!includeGenerated && r.source.toLowerCase() == 'generated') continue;
        if (goal != null && !r.goals.contains(goal)) continue;
        if (mealType != null && r.mealType != mealType) continue;
        if (maxMinutes > 0 && r.minutes > maxMinutes) continue;
        if (q.isNotEmpty) {
          final ingredientMatch = r.ingredients
              .any((i) => i.name.toLowerCase().contains(q));
          final nameMatch = r.name.toLowerCase().contains(q);
          if (!ingredientMatch && !nameMatch) continue;
        }
        // Only include recipes that were excluded by the strict goal check.
        if (goal != null && !_isRecipeEligibleForGoal(r, goal)) {
          relaxed.add(r);
        }
      }
      final relaxedLocalized = _applyLanguagePreference(
        relaxed,
        requestedLanguage: language,
        goal: goal,
        mealType: mealType,
      );
      final seen = {for (final r in localized) r.id};
      for (final r in relaxedLocalized) {
        if (seen.add(r.id)) localized.add(r);
        if (localized.length >= _focusBucketFallbackLimit) break;
      }
    }
    if (limit > 0 && localized.length > limit) return localized.sublist(0, limit);
    return localized;
  }

  List<Recipe> _applyLanguagePreference(
    List<Recipe> recipes, {
    required String? requestedLanguage,
    required NutritionGoalType? goal,
    required RecipeMealType? mealType,
  }) {
    final language = requestedLanguage?.trim().toLowerCase();
    if (language == null || language.isEmpty) return recipes;

    final primary = recipes.where((recipe) => recipe.language == language).toList();
    if (!_needsLanguageTopUp(primary, goal: goal, mealType: mealType)) {
      return primary;
    }

    final fallbackLanguages = {
      for (final recipe in recipes)
        if (recipe.language != language && recipe.language != 'en') recipe.language,
    }.toList()
      ..sort();

    final fallbackOrder = <String>[
      language,
      if (language != 'en') 'en',
      ...fallbackLanguages,
    ];

    final merged = <Recipe>[];
    final seenIds = <String>{};
    for (final code in fallbackOrder) {
      for (final recipe in recipes) {
        if (recipe.language != code) continue;
        if (seenIds.add(recipe.id)) {
          merged.add(recipe);
        }
      }
      if (_isFocusMealBucket(goal, mealType) &&
          merged.length >= _focusBucketFallbackLimit) {
        break;
      }
    }

    return merged.isEmpty ? recipes : merged;
  }

  bool _needsLanguageTopUp(
    List<Recipe> primary, {
    required NutritionGoalType? goal,
    required RecipeMealType? mealType,
  }) {
    if (primary.isEmpty) return true;
    if (goal == null) return true;
    if (_isFocusMealBucket(goal, mealType)) {
      return primary.length < _focusBucketFallbackLimit;
    }
    return false;
  }

  bool _isFocusMealBucket(
    NutritionGoalType? goal,
    RecipeMealType? mealType,
  ) {
    if (goal == null || mealType == null) return false;
    final isFocusGoal = switch (goal) {
      NutritionGoalType.muscleGrowth => true,
      NutritionGoalType.vegan => true,
      NutritionGoalType.diabetes => true,
      NutritionGoalType.keto => true,
      _ => false,
    };
    return isFocusGoal &&
        (mealType == RecipeMealType.breakfast ||
            mealType == RecipeMealType.lunch);
  }

  static const int _focusBucketFallbackLimit = 8;

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
        // Keto is governed by NET carbs (total carbs minus fibre), which is the
        // standard way ketogenic diets are counted. A high-fibre dish with 25g
        // total but 8g fibre is 17g net and legitimately keto-eligible.
        final netCarbsPerServing =
            carbsPerServing - recipe.fiberPerServing(recipe.servings);
        return netCarbsPerServing <= 20;

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
    'crab',
    'lobster',
    'mussel',
    'oyster',
    'clam',
    'squid',
    'octopus',
    'scallop',
    'cod',
    'haddock',
    'mackerel',
    'sardine',
    'kip',
    'rund',
    'varken',
    'spek',
    'garnalen',
    'zalm',
    'makreel',
    'mosselen',
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
  final lang = ref.watch(localeProvider);
  return RecipeRepository.instance.query(
    goal: q.goal,
    mealType: q.mealType,
    search: q.search,
    maxMinutes: q.maxMinutes,
    language: lang.code,
  );
});
