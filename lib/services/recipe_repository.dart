import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrition_goal.dart';
import '../models/dietary_restriction.dart';
import '../models/recipe.dart';
import '../providers/locale_provider.dart';
import '../providers/user_prefs_provider.dart';

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
    final scraped = await _loadAssetRecipes('assets/bundled_recipes.json');
    final byId = <String, Recipe>{};
    for (final recipe in scraped) {
      if (recipe.id.isEmpty) continue;
      byId[recipe.id] = recipe;
    }
    final list = byId.values.toList(growable: false);
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
    } catch (e) {
      debugPrint('RecipeRepository: failed to load "$assetPath": $e');
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
    Set<DietaryRestriction> dietaryRestrictions = const <DietaryRestriction>{},
  }) async {
    final q = (search ?? '').trim().toLowerCase();
    final list = await all();
    final filtered = <Recipe>[];
    for (final r in list) {
      if (!includeGenerated && r.source.toLowerCase() == 'generated') continue;
      if (goal != null && !_matchesGoal(r, goal)) continue;
      if (!_hasProfessionalRecipeQuality(r)) continue;
      if (goal != null &&
          strictGoalRules &&
          !_isRecipeEligibleForGoal(r, goal)) {
        continue;
      }
      if (mealType != null && r.mealType != mealType) continue;
      if (!_isMealQualityMatch(r, mealType, allowFallbackFillers: false)) {
        continue;
      }
      if (!isAllowedByRestrictions(r, dietaryRestrictions)) continue;
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
        if (!includeGenerated && r.source.toLowerCase() == 'generated') {
          continue;
        }
        if (goal != null && !_matchesGoal(r, goal)) continue;
        if (!_hasProfessionalRecipeQuality(r)) continue;
        if (mealType != null && r.mealType != mealType) continue;
        if (!_isMealQualityMatch(r, mealType, allowFallbackFillers: true)) {
          continue;
        }
        if (!isAllowedByRestrictions(r, dietaryRestrictions)) continue;
        if (maxMinutes > 0 && r.minutes > maxMinutes) continue;
        if (q.isNotEmpty) {
          final ingredientMatch =
              r.ingredients.any((i) => i.name.toLowerCase().contains(q));
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
    if (limit > 0 && localized.length > limit) {
      return localized.sublist(0, limit);
    }
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

    final primary =
        recipes.where((recipe) => recipe.language == language).toList();
    if (!_needsLanguageTopUp(primary, goal: goal, mealType: mealType)) {
      return primary;
    }

    final fallbackLanguages = {
      for (final recipe in recipes)
        if (recipe.language != language && recipe.language != 'en')
          recipe.language,
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
      NutritionGoalType.pescatarian => true,
      NutritionGoalType.mediterranean => true,
      _ => false,
    };
    return isFocusGoal &&
        (mealType == RecipeMealType.breakfast ||
            mealType == RecipeMealType.lunch);
  }

  static const int _focusBucketFallbackLimit = 40;

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
      case NutritionGoalType.pescatarian:
        return _isPescatarianRecipe(recipe);
      case NutritionGoalType.mediterranean:
        return _isMediterraneanRecipe(recipe);
      case NutritionGoalType.maintain:
        return true;
    }
  }

  bool _matchesGoal(Recipe recipe, NutritionGoalType goal) {
    if (recipe.goals.contains(goal)) return true;
    switch (goal) {
      case NutritionGoalType.pescatarian:
      case NutritionGoalType.mediterranean:
        return _isRecipeEligibleForGoal(recipe, goal);
      case NutritionGoalType.muscleGrowth:
      case NutritionGoalType.diabetes:
      case NutritionGoalType.vegan:
      case NutritionGoalType.vegetarian:
      case NutritionGoalType.weightLoss:
      case NutritionGoalType.keto:
      case NutritionGoalType.maintain:
        return false;
    }
  }

  bool _isVeganRecipe(Recipe recipe) {
    final text = _recipeRuleText(recipe);
    return !_containsAnyTerm(text, _meatTerms) &&
        !_containsAnyTerm(text, _seafoodTerms) &&
        !_containsAnyTerm(text, _dairyEggHoneyTerms);
  }

  bool _isVegetarianRecipe(Recipe recipe) {
    final text = _recipeRuleText(recipe);
    return !_containsAnyTerm(text, _meatTerms) &&
        !_containsAnyTerm(text, _seafoodTerms);
  }

  bool _isPescatarianRecipe(Recipe recipe) {
    final text = _recipeRuleText(recipe);
    return !_containsAnyTerm(text, _meatTerms);
  }

  bool _isMediterraneanRecipe(Recipe recipe) {
    final sugarPerServing = recipe.sugarPerServing(recipe.servings);
    final fiberPerServing = recipe.fiberPerServing(recipe.servings);
    final caloriesPerServing = recipe.caloriesPerServing(recipe.servings);
    final text = _recipeRuleText(recipe);
    if (_containsAnyTerm(text, _processedMeatTerms)) return false;
    if (sugarPerServing > 24) return false;
    if (caloriesPerServing > 900) return false;
    return fiberPerServing >= 3 ||
        _containsAnyTerm(text, _mediterraneanAnchorTerms);
  }

  bool _isMealQualityMatch(
    Recipe recipe,
    RecipeMealType? requestedMealType, {
    required bool allowFallbackFillers,
  }) {
    final mealType = requestedMealType ?? recipe.mealType;
    final text = _recipeRuleText(recipe);
    if (allowFallbackFillers && recipe.name.contains('(Breakfast)')) {
      return true;
    }
    switch (mealType) {
      case RecipeMealType.breakfast:
        final dinnerLike = _containsAnyTerm(text, _dinnerLikeBreakfastTerms);
        final explicitBreakfast =
            recipe.name.toLowerCase().contains('breakfast');
        if (dinnerLike && !explicitBreakfast) return false;
        if (_containsAnyTerm(text, _breakfastAnchorTerms)) return true;
        return !dinnerLike;
      case RecipeMealType.lunch:
        if (recipe.caloriesPerServing(recipe.servings) > 950) return false;
        if (_containsAnyTerm(text, _heavyDinnerTerms) &&
            !_containsAnyTerm(text, _lunchAnchorTerms)) {
          return false;
        }
        return true;
      case RecipeMealType.dinner:
      case RecipeMealType.snack:
      case RecipeMealType.dessert:
        return true;
    }
  }

  bool _hasProfessionalRecipeQuality(Recipe recipe) {
    final caloriesPerServing = recipe.caloriesPerServing(recipe.servings);
    final proteinPerServing = recipe.proteinPerServing(recipe.servings);
    final carbsPerServing = recipe.carbsPerServing(recipe.servings);
    final fatPerServing = recipe.fatPerServing(recipe.servings);
    final hasUsableIngredients =
        recipe.ingredients.where((ingredient) => ingredient.grams > 0).length >=
            3;
    final hasInstructions = recipe.steps.isNotEmpty;
    final hasImage = (recipe.image ?? '').trim().isNotEmpty;

    if (!hasUsableIngredients || !hasInstructions || !hasImage) return false;
    if (recipe.servings <= 0 || recipe.servings > 12) return false;
    if (caloriesPerServing < 120 || caloriesPerServing > 1200) return false;
    if (proteinPerServing < 2 || carbsPerServing < 0 || fatPerServing < 0) {
      return false;
    }

    switch (recipe.mealType) {
      case RecipeMealType.breakfast:
        return caloriesPerServing >= 180 && caloriesPerServing <= 900;
      case RecipeMealType.lunch:
        // Light salad/bowl lunches (180-250 kcal/serving) are legitimate and
        // were previously hidden by an over-strict floor; allow them through.
        return caloriesPerServing >= 180 && caloriesPerServing <= 950;
      case RecipeMealType.snack:
        return caloriesPerServing >= 120 && caloriesPerServing <= 550;
      case RecipeMealType.dinner:
        return caloriesPerServing >= 250 && caloriesPerServing <= 1200;
      case RecipeMealType.dessert:
        return caloriesPerServing >= 120 && caloriesPerServing <= 900;
    }
  }

  bool isAllowedByRestrictions(
    Recipe recipe,
    Set<DietaryRestriction> dietaryRestrictions,
  ) {
    if (dietaryRestrictions.isEmpty) return true;
    final text = [
      recipe.name,
      recipe.tags.join(' '),
      _recipeIngredientText(recipe),
    ].join(' ');
    return !dietaryRestrictions
        .any((restriction) => restriction.matchesText(text));
  }

  String _recipeIngredientText(Recipe recipe) {
    return recipe.ingredients
        .map((ingredient) => '${ingredient.name} ${ingredient.amount}')
        .join(' ')
        .toLowerCase();
  }

  String _recipeRuleText(Recipe recipe) {
    return [
      recipe.name,
      recipe.tags.join(' '),
      _recipeIngredientText(recipe),
    ].join(' ').toLowerCase();
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

  static const _meatTerms = [
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

  static const _seafoodTerms = [
    'fish',
    'salmon',
    'tuna',
    'shrimp',
    'prawn',
    'anchovy',
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
    'garnalen',
    'zalm',
    'makreel',
    'mosselen',
  ];

  static const _processedMeatTerms = [
    'bacon',
    'ham',
    'salami',
    'sausage',
    'prosciutto',
    'chorizo',
    'pancetta',
    'spek',
    'speck',
    'schinken',
    'wurst',
    'jamón',
    'jamon',
  ];

  static const _mediterraneanAnchorTerms = [
    'olive oil',
    'olives',
    'tomato',
    'lentil',
    'bean',
    'chickpea',
    'hummus',
    'fish',
    'salmon',
    'tuna',
    'sardine',
    'whole grain',
    'vegetable',
    'spinach',
    'eggplant',
    'zucchini',
  ];

  static const _breakfastAnchorTerms = [
    'breakfast',
    'oat',
    'porridge',
    'granola',
    'muesli',
    'yogurt',
    'yoghurt',
    'smoothie',
    'toast',
    'egg',
    'omelette',
    'omelet',
    'pancake',
    'pancakes',
    'waffle',
    'waffles',
    'cereal',
    'fruit bowl',
    'bagel',
    'bagels',
    'muffin',
    'muffins',
    'pastry',
    'pastries',
    'crepe',
    'crepes',
    'shakshuka',
    'frittata',
    'hash brown',
    'brunch',
    'ontbijt',
    'frühstück',
    'fruehstueck',
    'śniadanie',
    'sniadanie',
    'desayuno',
    'bagietka',
    'bułka',
    'bulka',
    'jajecznica',
    'tortilla española',
  ];

  static const _lunchAnchorTerms = [
    'salad',
    'wrap',
    'sandwich',
    'bowl',
    'soup',
    'toast',
    'pita',
    'flatbread',
    'poke',
    'sushi',
    'burrito',
    'taco',
    'tacos',
    'quesadilla',
    'quiche',
    'frittata',
    'mezze',
    'lunch',
    'brunch',
    'mittagessen',
    'lunchgerecht',
    'almuerzo',
    'obiad',
    'wrapy',
    'kanapka',
    'kanapki',
  ];

  static const _dinnerLikeBreakfastTerms = [
    'curry',
    'stew',
    'roast',
    'steak',
    'burger',
    'pasta',
    'noodle',
    'risotto',
    'stir fry',
    'stir-fry',
    'casserole',
    'lasagne',
    'lasagna',
    'ragu',
    'ragout',
    'chili',
  ];

  static const _heavyDinnerTerms = [
    'roast',
    'braised',
    'casserole',
    'lasagne',
    'lasagna',
    'stew',
    'ragu',
    'ragout',
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
  final includeGenerated = q.goal != null ||
      q.mealType == RecipeMealType.breakfast ||
      q.mealType == RecipeMealType.lunch;
  return RecipeRepository.instance.query(
    goal: q.goal,
    mealType: q.mealType,
    search: q.search,
    maxMinutes: q.maxMinutes,
    includeGenerated: includeGenerated,
    language: lang.code,
    dietaryRestrictions: ref.watch(userPrefsProvider).dietaryRestrictions,
  );
});
