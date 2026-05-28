import 'package:flutter_test/flutter_test.dart';

import 'package:pixels_to_macros/models/nutrition_goal.dart';
import 'package:pixels_to_macros/models/recipe.dart';
import 'package:pixels_to_macros/services/recipe_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Goal-specific recipe filtering', () {
    test('Every goal returns only goal-tagged recipes', () async {
      for (final goal in NutritionGoalType.values) {
        final recipes = await RecipeRepository.instance.query(
          goal: goal,
          limit: 2000,
        );

        expect(recipes, isNotEmpty,
            reason: 'No recipes found for ${goal.name}');
        for (final recipe in recipes) {
          expect(
            recipe.goals.contains(goal),
            isTrue,
            reason: '${recipe.id} is not tagged for ${goal.name}',
          );
        }
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
          final recipes = await RecipeRepository.instance.query(
            goal: goal,
            mealType: meal,
            language: 'es',
            limit: 2000,
          );

          expect(
            recipes.length,
            greaterThanOrEqualTo(8),
            reason:
                'Expected at least 8 fallback recipes for ${goal.name} ${meal.name}',
          );
          for (final recipe in recipes) {
            expect(recipe.goals.contains(goal), isTrue);
            expect(recipe.mealType, meal);
          }
        }
      }
    });
  });
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
