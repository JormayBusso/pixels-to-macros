import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/models/food_data.dart';
import 'package:pixels_to_macros/models/nutrition_goal.dart';
import 'package:pixels_to_macros/services/food_scoring_service.dart';

void main() {
  const almondButter = FoodData(
    label: 'Almond butter',
    densityMin: 0.9,
    densityMax: 1.0,
    kcalPer100g: 614,
    category: 'nut',
    proteinPer100g: 21,
    fiberPer100g: 10,
    fatPer100g: 56,
  );

  test('keeps a realistic almond butter serving above the healthy threshold',
      () {
    final score = FoodScoringService.scoreFood(
      almondButter,
      goal: NutritionGoalType.maintain,
      loggedGrams: 30,
    );

    expect(score.score, greaterThanOrEqualTo(70));
  });

  test('penalizes an exceptionally high-energy single entry', () {
    final score = FoodScoringService.scoreFood(
      almondButter,
      goal: NutritionGoalType.maintain,
      loggedGrams: 3000 / 614 * 100,
    );

    expect(score.score, lessThan(40));
    expect(score.reasons, contains('excessiveEntryEnergy'));
  });
}
