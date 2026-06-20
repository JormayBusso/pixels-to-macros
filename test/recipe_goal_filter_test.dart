import 'package:flutter_test/flutter_test.dart';

import 'package:pixels_to_macros/models/dietary_restriction.dart';
import 'package:pixels_to_macros/models/nutrition_goal.dart';
import 'package:pixels_to_macros/models/recipe.dart';
import 'package:pixels_to_macros/services/recipe_repository.dart';
import 'package:pixels_to_macros/services/recipe_swap_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Goal-specific recipe filtering', () {
    test('Every goal returns recipes eligible for that goal', () async {
      for (final goal in NutritionGoalType.values) {
        final recipes = await RecipeRepository.instance.query(
          goal: goal,
          limit: 2000,
        );

        expect(recipes, isNotEmpty,
            reason: 'No recipes found for ${goal.name}');
        for (final recipe in recipes) {
          if (goal == NutritionGoalType.pescatarian) {
            expect(
              recipe.goals.contains(goal) || _isDerivedPescatarian(recipe),
              isTrue,
              reason: '${recipe.id} is not pescatarian eligible',
            );
            continue;
          }
          if (goal == NutritionGoalType.mediterranean) {
            expect(
              recipe.goals.contains(goal) || _isDerivedMediterranean(recipe),
              isTrue,
              reason: '${recipe.id} is not Mediterranean eligible',
            );
            continue;
          }
          expect(
            recipe.goals.contains(goal),
            isTrue,
            reason: '${recipe.id} is not tagged for ${goal.name}',
          );
        }
      }
    });

    test('Pescatarian derived recipes reject meat terms', () async {
      final recipes = await RecipeRepository.instance.query(
        goal: NutritionGoalType.pescatarian,
        limit: 2000,
      );

      expect(recipes, isNotEmpty, reason: 'No pescatarian recipes found');
      for (final recipe in recipes) {
        expect(
          _containsAnyTerm(recipe, _meatTerms),
          isFalse,
          reason: '${recipe.name} contains meat terms',
        );
      }
    });

    test('Mediterranean derived recipes avoid processed meat and excess sugar',
        () async {
      final recipes = await RecipeRepository.instance.query(
        goal: NutritionGoalType.mediterranean,
        limit: 2000,
      );

      expect(recipes, isNotEmpty, reason: 'No Mediterranean recipes found');
      for (final recipe in recipes) {
        expect(
          _containsAnyTerm(recipe, _processedMeatTerms),
          isFalse,
          reason: '${recipe.name} contains processed meat terms',
        );
        expect(
          recipe.sugarPerServing(recipe.servings) <= 24,
          isTrue,
          reason: '${recipe.name} has too much sugar per serving',
        );
      }
    });

    test('Breakfast and lunch filters avoid dinner-like mismatches', () async {
      final breakfasts = await RecipeRepository.instance.query(
        mealType: RecipeMealType.breakfast,
        limit: 2000,
      );
      final lunches = await RecipeRepository.instance.query(
        mealType: RecipeMealType.lunch,
        limit: 2000,
      );

      expect(breakfasts, isNotEmpty, reason: 'No breakfast recipes found');
      expect(lunches, isNotEmpty, reason: 'No lunch recipes found');

      for (final recipe in breakfasts) {
        expect(
          _containsAnyTerm(recipe, _dinnerLikeBreakfastTerms),
          isFalse,
          reason: '${recipe.name} looks dinner-like for breakfast',
        );
      }
      for (final recipe in lunches) {
        expect(recipe.caloriesPerServing(recipe.servings) <= 950, isTrue);
        if (_containsAnyTerm(recipe, _heavyDinnerTerms)) {
          expect(
            _containsAnyTerm(recipe, _lunchAnchorTerms),
            isTrue,
            reason:
                '${recipe.name} is a heavy dinner-like lunch without a lunch anchor',
          );
        }
      }
    });

    test('Dietary restriction filters remove matching recipes', () async {
      final dairyFree = await RecipeRepository.instance.query(
        dietaryRestrictions: {DietaryRestriction.dairyFree},
        limit: 2000,
      );
      final nutFree = await RecipeRepository.instance.query(
        dietaryRestrictions: {DietaryRestriction.nutFree},
        limit: 2000,
      );

      expect(dairyFree, isNotEmpty, reason: 'No dairy-free recipes returned');
      expect(nutFree, isNotEmpty, reason: 'No nut-free recipes returned');

      for (final recipe in dairyFree) {
        expect(
          _containsAnyTerm(recipe, DietaryRestriction.dairyFree.triggerTerms),
          isFalse,
          reason: '${recipe.name} contains dairy terms',
        );
      }
      for (final recipe in nutFree) {
        expect(
          _containsAnyTerm(recipe, DietaryRestriction.nutFree.triggerTerms),
          isFalse,
          reason: '${recipe.name} contains nut terms',
        );
      }
    });

    test('Diabetes breakfast stays very low-carb', () async {
      final recipes = await RecipeRepository.instance.query(
        goal: NutritionGoalType.diabetes,
        limit: 2000,
      );

      final breakfasts =
          recipes.where((r) => r.mealType == RecipeMealType.breakfast).toList();

      expect(breakfasts, isNotEmpty,
          reason: 'No diabetes breakfast recipes found');
      for (final recipe in breakfasts) {
        final carbsPerServing = recipe.carbsPerServing(recipe.servings);
        expect(
          carbsPerServing <= 20,
          isTrue,
          reason:
              '${recipe.name} has ${carbsPerServing.toStringAsFixed(1)}g carbs',
        );
      }
    });

    test('Diabetes non-breakfast avoids high-carb spikes', () async {
      final recipes = await RecipeRepository.instance.query(
        goal: NutritionGoalType.diabetes,
        limit: 2000,
      );

      final nonBreakfast =
          recipes.where((r) => r.mealType != RecipeMealType.breakfast).toList();

      expect(nonBreakfast, isNotEmpty,
          reason: 'No diabetes non-breakfast recipes found');
      for (final recipe in nonBreakfast) {
        final carbsPerServing = recipe.carbsPerServing(recipe.servings);
        expect(
          carbsPerServing <= 35,
          isTrue,
          reason:
              '${recipe.name} has ${carbsPerServing.toStringAsFixed(1)}g carbs',
        );

        if (recipe.glycemicIndex > 0) {
          expect(
            recipe.glycemicIndex <= 55,
            isTrue,
            reason: '${recipe.name} has GI ${recipe.glycemicIndex}',
          );
        }
      }
    });

    test('Muscle growth recipes are high-protein focused', () async {
      final recipes = await RecipeRepository.instance.query(
        goal: NutritionGoalType.muscleGrowth,
        limit: 2000,
      );

      expect(recipes, isNotEmpty, reason: 'No muscle growth recipes found');
      for (final recipe in recipes) {
        final proteinPerServing = recipe.proteinPerServing(recipe.servings);
        final caloriesPerServing = recipe.caloriesPerServing(recipe.servings);

        expect(
          proteinPerServing >= 25,
          isTrue,
          reason:
              '${recipe.name} has only ${proteinPerServing.toStringAsFixed(1)}g protein',
        );
        expect(
          caloriesPerServing >= 300,
          isTrue,
          reason: '${recipe.name} has only ${caloriesPerServing} kcal',
        );
      }
    });

    test('Vegan and vegetarian filters reject animal category mistakes',
        () async {
      final veganRecipes = await RecipeRepository.instance.query(
        goal: NutritionGoalType.vegan,
        limit: 2000,
      );
      final vegetarianRecipes = await RecipeRepository.instance.query(
        goal: NutritionGoalType.vegetarian,
        limit: 2000,
      );

      expect(veganRecipes, isNotEmpty, reason: 'No vegan recipes found');
      expect(vegetarianRecipes, isNotEmpty,
          reason: 'No vegetarian recipes found');

      for (final recipe in vegetarianRecipes) {
        expect(
          _containsAnyTerm(recipe, _meatSeafoodTerms),
          isFalse,
          reason:
              '${recipe.name} is tagged vegetarian but contains meat or seafood terms',
        );
      }

      for (final recipe in veganRecipes) {
        expect(
          _containsAnyTerm(recipe, _meatSeafoodTerms),
          isFalse,
          reason:
              '${recipe.name} is tagged vegan but contains meat or seafood terms',
        );
        expect(
          _containsAnyTerm(recipe, _dairyEggHoneyTerms),
          isFalse,
          reason:
              '${recipe.name} is tagged vegan but contains dairy, egg, or honey terms',
        );
      }
    });

    test('Bundled recipe meal types stay in the supported app buckets',
        () async {
      final recipes = await RecipeRepository.instance.all();
      final seenMealTypes = recipes.map((recipe) => recipe.mealType).toSet();

      expect(seenMealTypes, isNotEmpty);
      expect(
        seenMealTypes.difference(RecipeMealType.values.toSet()),
        isEmpty,
      );
      expect(
        RecipeMealType.values,
        containsAll(<RecipeMealType>[
          RecipeMealType.breakfast,
          RecipeMealType.lunch,
          RecipeMealType.dinner,
          RecipeMealType.dessert,
          RecipeMealType.snack,
        ]),
      );
    });

    test('All-recipe browsing falls back when locale has no bundled recipes',
        () async {
      final recipes = await RecipeRepository.instance.query(
        language: 'es',
        limit: 2000,
      );

      expect(recipes, isNotEmpty, reason: 'Expected fallback recipes for es');
      expect(
        recipes.any((recipe) => recipe.language != 'es'),
        isTrue,
        reason: 'Expected fallback languages when es has no bundled recipes',
      );
    });

    test('Focus breakfast and lunch buckets top up for empty locales',
        () async {
      const focusGoals = <NutritionGoalType>[
        NutritionGoalType.muscleGrowth,
        NutritionGoalType.vegan,
        NutritionGoalType.diabetes,
        NutritionGoalType.keto,
      ];
      const focusMeals = <RecipeMealType>[
        RecipeMealType.breakfast,
        RecipeMealType.lunch,
      ];

      for (final goal in focusGoals) {
        for (final meal in focusMeals) {
          final expectedMinimum = switch ((goal, meal)) {
            (NutritionGoalType.vegan, RecipeMealType.breakfast) => 9,
            (NutritionGoalType.muscleGrowth, RecipeMealType.breakfast) => 15,
            _ => 16,
          };
          final recipes = await RecipeRepository.instance.query(
            goal: goal,
            mealType: meal,
            language: 'es',
            includeGenerated: true,
            limit: 2000,
          );

          expect(
            recipes.length,
            greaterThanOrEqualTo(expectedMinimum),
            reason:
                'Expected at least $expectedMinimum fallback recipes for ${goal.name} ${meal.name}',
          );
          for (final recipe in recipes) {
            expect(recipe.goals.contains(goal), isTrue);
            expect(recipe.mealType, meal);
          }
        }
      }
    });
  });

  group('Smart Swap', () {
    test('pantry-first intent prefers recipes using available ingredients', () {
      final current = _recipe(id: 'current', name: 'Current Bowl');
      final pantryRecipe = _recipe(
        id: 'pantry',
        name: 'Lentil Pantry Bowl',
        ingredients: const ['lentils', 'tomato', 'spinach'],
        healthScore: 70,
      );
      final otherRecipe = _recipe(
        id: 'other',
        name: 'Good Rice Bowl',
        ingredients: const ['rice', 'pepper'],
        healthScore: 82,
      );

      final picked = RecipeSwapService.pickBestSwap(
        current: current,
        candidates: [current, pantryRecipe, otherRecipe],
        intent: SmartSwapIntent.pantryFirst,
        goal: NutritionGoalType.maintain,
        pantryNames: {'lentils'},
      );

      expect(picked?.id, 'pantry');
    });

    test('lower-carb intent prefers lower carb candidates', () {
      final highCarb = _recipe(
        id: 'high-carb',
        name: 'Rice Plate',
        carbsG: 90,
        fiberG: 2,
        glycemicLoad: 28,
      );
      final lowerCarb = _recipe(
        id: 'lower-carb',
        name: 'Egg Salad',
        carbsG: 14,
        fiberG: 5,
        glycemicLoad: 4,
      );

      final picked = RecipeSwapService.pickBestSwap(
        current: null,
        candidates: [highCarb, lowerCarb],
        intent: SmartSwapIntent.lowerCarb,
        goal: NutritionGoalType.diabetes,
        pantryNames: const {},
      );

      expect(picked?.id, 'lower-carb');
    });

    test('higher-protein intent does not let one macro dominate scoring', () {
      final extremeProtein = _recipe(
        id: 'extreme-protein',
        name: 'Extreme Protein Plate',
        proteinG: 120,
        healthScore: 45,
      );
      final balancedHighProtein = _recipe(
        id: 'balanced-high-protein',
        name: 'Balanced High Protein Plate',
        proteinG: 35,
        healthScore: 70,
      );

      final picked = RecipeSwapService.pickBestSwap(
        current: null,
        candidates: [extremeProtein, balancedHighProtein],
        intent: SmartSwapIntent.higherProtein,
        goal: NutritionGoalType.maintain,
        pantryNames: const {},
      );

      expect(picked?.id, 'balanced-high-protein');
    });
  });
}

Recipe _recipe({
  required String id,
  required String name,
  List<String> ingredients = const ['tomato', 'spinach'],
  int calories = 500,
  double proteinG = 30,
  double carbsG = 45,
  double fatG = 18,
  double fiberG = 6,
  double sugarG = 5,
  int healthScore = 60,
  int minutes = 25,
  double glycemicLoad = 8,
}) {
  return Recipe(
    id: id,
    name: name,
    image: null,
    mealType: RecipeMealType.lunch,
    goals: const {NutritionGoalType.maintain},
    minutes: minutes,
    servings: 1,
    calories: calories,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
    fiberG: fiberG,
    sugarG: sugarG,
    tags: const [],
    ingredients: ingredients
        .map((name) => RecipeIngredient(name: name, amount: name, grams: 100))
        .toList(),
    steps: const ['Mix and serve.'],
    source: 'test',
    healthScore: healthScore,
    glycemicLoad: glycemicLoad,
  );
}

const _meatSeafoodTerms = <String>[
  'beef',
  'steak',
  'pork',
  'bacon',
  'ham',
  'chicken',
  'turkey',
  'duck',
  'lamb',
  'veal',
  'sausage',
  'salami',
  'prosciutto',
  'fish',
  'salmon',
  'tuna',
  'cod',
  'shrimp',
  'prawn',
  'crab',
  'lobster',
  'clam',
  'mussel',
  'anchovy',
  'gelatin',
  'gelatine',
  'schinken',
  'wurst',
];

const _meatTerms = <String>[
  'beef',
  'steak',
  'pork',
  'bacon',
  'ham',
  'chicken',
  'turkey',
  'duck',
  'lamb',
  'veal',
  'sausage',
  'salami',
  'prosciutto',
  'chorizo',
  'pancetta',
  'gelatin',
  'gelatine',
  'schinken',
  'wurst',
];

const _processedMeatTerms = <String>[
  'bacon',
  'ham',
  'salami',
  'sausage',
  'prosciutto',
  'chorizo',
  'pancetta',
  'schinken',
  'wurst',
  'jamón',
  'jamon',
];

const _mediterraneanAnchorTerms = <String>[
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

const _dinnerLikeBreakfastTerms = <String>[
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

const _heavyDinnerTerms = <String>[
  'roast',
  'braised',
  'casserole',
  'lasagne',
  'lasagna',
  'stew',
  'ragu',
  'ragout',
];

const _lunchAnchorTerms = <String>[
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

const _dairyEggHoneyTerms = <String>[
  'milk',
  'cheese',
  'butter',
  'cream',
  'yogurt',
  'yoghurt',
  'egg',
  'eggs',
  'honey',
  'whey',
  'ghee',
  'parmesan',
  'mozzarella',
  'feta',
];

bool _containsAnyTerm(Recipe recipe, List<String> terms) {
  final text = <String>[
    recipe.name,
    recipe.source,
    ...recipe.tags,
    ...recipe.ingredients.map((ingredient) => ingredient.name),
    ...recipe.ingredients.map((ingredient) => ingredient.amount),
  ].join(' ').toLowerCase();

  return terms.any((term) {
    final pattern = RegExp('(^|[^a-z])${RegExp.escape(term)}([^a-z]|\u{0000})');
    return pattern.hasMatch('$text\u{0000}');
  });
}

bool _isDerivedPescatarian(Recipe recipe) =>
    !_containsAnyTerm(recipe, _meatTerms);

bool _isDerivedMediterranean(Recipe recipe) {
  final sugarPerServing = recipe.sugarPerServing(recipe.servings);
  final fiberPerServing = recipe.fiberPerServing(recipe.servings);
  final caloriesPerServing = recipe.caloriesPerServing(recipe.servings);
  return !_containsAnyTerm(recipe, _processedMeatTerms) &&
      sugarPerServing <= 24 &&
      caloriesPerServing <= 900 &&
      (fiberPerServing >= 3 ||
          _containsAnyTerm(recipe, _mediterraneanAnchorTerms));
}
