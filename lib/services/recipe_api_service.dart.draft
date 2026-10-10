import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/nutrition_goal.dart';
import '../models/recipe.dart';

/// Spoonacular API client for fetching real recipes.
///
/// Free tier: 150 API points/day.
/// Get your key at https://spoonacular.com/food-api
class RecipeApiService {
  RecipeApiService._();
  static final RecipeApiService instance = RecipeApiService._();

  static const _baseUrl = 'https://api.spoonacular.com';
  static const _apiKeyPref = 'spoonacular_api_key';

  String? _apiKey;

  /// Load the stored API key from shared preferences.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_apiKeyPref);
  }

  /// Store a new API key.
  Future<void> setApiKey(String key) async {
    _apiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPref, _apiKey!);
  }

  /// Whether an API key is configured.
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  /// Search recipes with optional diet/type filters.
  ///
  /// Returns up to [number] results (default 20, max 100).
  Future<List<Recipe>> searchRecipes({
    String query = '',
    NutritionGoalType? goal,
    RecipeMealType? mealType,
    int number = 20,
    int offset = 0,
  }) async {
    if (!hasApiKey) return const [];

    final params = <String, String>{
      'apiKey': _apiKey!,
      'addRecipeNutrition': 'true',
      'addRecipeInstructions': 'true',
      'fillIngredients': 'true',
      'number': number.toString(),
      'offset': offset.toString(),
      'instructionsRequired': 'true',
    };

    if (query.isNotEmpty) params['query'] = query;

    // Map nutrition goals to Spoonacular diet filters
    final diet = _dietForGoal(goal);
    if (diet != null) params['diet'] = diet;

    // Map meal type
    final type = _typeForMeal(mealType);
    if (type != null) params['type'] = type;

    // Goal-specific nutrition constraints
    _addNutritionConstraints(params, goal);

    final uri = Uri.parse('$_baseUrl/recipes/complexSearch')
        .replace(queryParameters: params);

    try {
      final response = await http.get(uri).timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode != 200) {
        return const [];
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (body['results'] as List?) ?? [];

      return results
          .cast<Map<String, dynamic>>()
          .map(_parseSpoonacularRecipe)
          .whereType<Recipe>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetch a single recipe by Spoonacular ID with full details.
  Future<Recipe?> getRecipe(int id) async {
    if (!hasApiKey) return null;

    final uri = Uri.parse('$_baseUrl/recipes/$id/information').replace(
      queryParameters: {
        'apiKey': _apiKey!,
        'includeNutrition': 'true',
      },
    );

    try {
      final response = await http.get(uri).timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseSpoonacularRecipe(body);
    } catch (_) {
      return null;
    }
  }

  Recipe? _parseSpoonacularRecipe(Map<String, dynamic> j) {
    try {
      final id = j['id']?.toString() ?? '';
      final name = (j['title'] as String?)?.trim() ?? '';
      if (name.isEmpty) return null;

      final image = j['image'] as String?;
      final minutes = (j['readyInMinutes'] as num?)?.toInt() ?? 30;
      final servings = (j['servings'] as num?)?.toInt() ?? 1;

      // Parse nutrition from the nested nutrition object
      final nutrition = j['nutrition'] as Map<String, dynamic>?;
      final nutrients = (nutrition?['nutrients'] as List?) ?? [];

      double findNutrient(String name) {
        for (final n in nutrients) {
          if (n is Map && (n['name'] as String?)?.toLowerCase() == name.toLowerCase()) {
            return (n['amount'] as num?)?.toDouble() ?? 0;
          }
        }
        return 0;
      }

      // Parse ingredients
      final extIngredients =
          (j['extendedIngredients'] as List?) ?? (j['missedIngredients'] as List?) ?? [];
      final ingredients = extIngredients.map<RecipeIngredient>((i) {
        final m = i as Map<String, dynamic>;
        final iName = (m['name'] as String?)?.trim() ?? (m['originalName'] as String?)?.trim() ?? '';
        final amount = (m['original'] as String?)?.trim() ?? '${(m['amount'] as num?)?.toDouble() ?? 0} ${m['unit'] ?? ''}';
        final grams = (m['amount'] as num?)?.toDouble() ?? 0;
        return RecipeIngredient(name: iName, amount: amount, grams: grams);
      }).where((i) => i.name.isNotEmpty).toList();

      // Parse steps from analyzedInstructions
      final instructions = (j['analyzedInstructions'] as List?) ?? [];
      final steps = <String>[];
      for (final inst in instructions) {
        if (inst is Map) {
          for (final step in (inst['steps'] as List?) ?? []) {
            if (step is Map) {
              final s = (step['step'] as String?)?.trim() ?? '';
              if (s.isNotEmpty) steps.add(s);
            }
          }
        }
      }

      // Map diets/tags to goals
      final diets = ((j['diets'] as List?) ?? []).cast<String>();
      final dishTypes = ((j['dishTypes'] as List?) ?? []).cast<String>();
      final goals = <NutritionGoalType>{};
      if (diets.any((d) => d.contains('keto'))) goals.add(NutritionGoalType.keto);
      if (diets.any((d) => d.contains('vegan'))) goals.add(NutritionGoalType.vegan);
      if (_nutrient('Carbohydrates') < 30) goals.add(NutritionGoalType.diabetes);
      if (_nutrient('Protein') > 30) goals.add(NutritionGoalType.muscleGrowth);
      if (_nutrient('Calories') < 500) goals.add(NutritionGoalType.weightLoss);
      goals.add(NutritionGoalType.maintain);

      // Map dish types to meal type
      final mealType = _parseMealType(dishTypes);

      final tags = [
        ...diets,
        if (j['veryHealthy'] == true) 'healthy',
        if (j['glutenFree'] == true) 'gluten-free',
        if (j['dairyFree'] == true) 'dairy-free',
      ];

      return Recipe(
        id: 'sp_$id',
        name: name,
        image: image,
        mealType: mealType,
        goals: goals,
        minutes: minutes,
        servings: servings,
        calories: _nutrient('Calories').round(),
        proteinG: _nutrient('Protein'),
        carbsG: _nutrient('Carbohydrates'),
        fatG: _nutrient('Fat'),
        fiberG: _nutrient('Fiber'),
        sugarG: _nutrient('Sugar'),
        vitaminAUg: _nutrient('Vitamin A') ,
        vitaminCMg: _nutrient('Vitamin C'),
        vitaminDUg: _nutrient('Vitamin D'),
        vitaminEMg: _nutrient('Vitamin E'),
        vitaminKUg: _nutrient('Vitamin K'),
        vitaminB12Ug: _nutrient('Vitamin B12'),
        folateUg: _nutrient('Folate'),
        calciumMg: _nutrient('Calcium'),
        ironMg: _nutrient('Iron'),
        magnesiumMg: _nutrient('Magnesium'),
        potassiumMg: _nutrient('Potassium'),
        zincMg: _nutrient('Zinc'),
        sodiumMg: _nutrient('Sodium'),
        tags: tags,
        ingredients: ingredients,
        steps: steps,
        source: 'Spoonacular',
        healthScore: (j['healthScore'] as num?)?.toInt().clamp(0, 100) ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  RecipeMealType _parseMealType(List<String> dishTypes) {
    for (final t in dishTypes) {
      final lower = t.toLowerCase();
      if (lower.contains('breakfast') || lower.contains('morning')) {
        return RecipeMealType.breakfast;
      }
      if (lower.contains('lunch')) return RecipeMealType.lunch;
      if (lower.contains('dinner') || lower.contains('main')) {
        return RecipeMealType.dinner;
      }
      if (lower.contains('snack') || lower.contains('appetizer')) {
        return RecipeMealType.snack;
      }
      if (lower.contains('dessert')) return RecipeMealType.dessert;
    }
    return RecipeMealType.dinner;
  }

  String? _dietForGoal(NutritionGoalType? goal) {
    switch (goal) {
      case NutritionGoalType.vegan:
        return 'vegan';
      case NutritionGoalType.keto:
        return 'ketogenic';
      default:
        return null;
    }
  }

  String? _typeForMeal(RecipeMealType? meal) {
    switch (meal) {
      case RecipeMealType.breakfast:
        return 'breakfast';
      case RecipeMealType.lunch:
        return 'main course';
      case RecipeMealType.dinner:
        return 'main course';
      case RecipeMealType.snack:
        return 'snack';
      case RecipeMealType.dessert:
        return 'dessert';
      default:
        return null;
    }
  }

  void _addNutritionConstraints(
      Map<String, String> params, NutritionGoalType? goal) {
    switch (goal) {
      case NutritionGoalType.diabetes:
        params['maxCarbs'] = '30';
        break;
      case NutritionGoalType.keto:
        params['maxCarbs'] = '20';
        break;
      case NutritionGoalType.weightLoss:
        params['maxCalories'] = '500';
        params['minProtein'] = '15';
        break;
      case NutritionGoalType.muscleGrowth:
        params['minProtein'] = '30';
        params['minCalories'] = '400';
        break;
      default:
        break;
    }
  }
}
