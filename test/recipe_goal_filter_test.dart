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

        expect(recipes, isNotEmpty, reason: 'No recipes found for ${goal.name}');
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

      final breakfasts = recipes
          .where((r) => r.mealType == RecipeMealType.breakfast)
          .toList();

      expect(breakfasts, isNotEmpty, reason: 'No diabetes breakfast recipes found');
      for (final recipe in breakfasts) {
        final carbsPerServing = recipe.carbsPerServing(recipe.servings);
        expect(
          carbsPerServing <= 20,
          isTrue,
          reason: '${recipe.name} has ${carbsPerServing.toStringAsFixed(1)}g carbs',
        );
      }
    });

    test('Diabetes non-breakfast avoids high-carb spikes', () async {
      final recipes = await RecipeRepository.instance.query(
        goal: NutritionGoalType.diabetes,
        limit: 2000,
      );

      final nonBreakfast = recipes
          .where((r) => r.mealType != RecipeMealType.breakfast)
          .toList();

      expect(nonBreakfast, isNotEmpty, reason: 'No diabetes non-breakfast recipes found');
      for (final recipe in nonBreakfast) {
        final carbsPerServing = recipe.carbsPerServing(recipe.servings);
        expect(
          carbsPerServing <= 35,
          isTrue,
          reason: '${recipe.name} has ${carbsPerServing.toStringAsFixed(1)}g carbs',
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
          reason: '${recipe.name} has only ${proteinPerServing.toStringAsFixed(1)}g protein',
        );
        expect(
          caloriesPerServing >= 300,
          isTrue,
          reason: '${recipe.name} has only ${caloriesPerServing} kcal',
        );
      }
    });
  });
}
