import '../models/food_data.dart';
import '../models/nutrition_goal.dart';

class FoodScoreExplanation {
  const FoodScoreExplanation({
    required this.score,
    required this.titleKey,
    required this.reasons,
  });

  final int score;
  final String titleKey;
  final List<String> reasons;
}

class FoodScoringService {
  FoodScoringService._();

  static FoodScoreExplanation scoreFood(
    FoodData food, {
    required NutritionGoalType goal,
  }) {
    var score = 55.0;
    final reasons = <String>[];

    final proteinDensity = food.proteinPer100g;
    final fiberDensity = food.fiberPer100g;
    final sugarDensity = food.sugarsPer100g;
    final satFatDensity = food.saturatedFatPer100g;
    final sodiumDensity = food.sodiumMgPer100g;
    final calorieDensity = food.kcalPer100g;

    if (proteinDensity >= 20) {
      score += 16;
      reasons.add('highProtein');
    } else if (proteinDensity >= 10) {
      score += 8;
      reasons.add('usefulProtein');
    }

    if (fiberDensity >= 6) {
      score += 14;
      reasons.add('highFiber');
    } else if (fiberDensity >= 3) {
      score += 8;
      reasons.add('meaningfulFiber');
    }

    if (sugarDensity > 20) {
      score -= 18;
      reasons.add('highSugar');
    } else if (sugarDensity > 10) {
      score -= 8;
      reasons.add('moderateSugar');
    }

    if (satFatDensity > 8) {
      score -= 12;
      reasons.add('highSaturatedFat');
    }
    if (sodiumDensity > 600) {
      score -= 10;
      reasons.add('highSodium');
    }
    if (calorieDensity > 450 && proteinDensity < 12 && fiberDensity < 3) {
      score -= 12;
      reasons.add('energyDenseLowSatiety');
    }

    switch (goal) {
      case NutritionGoalType.diabetes:
        if (food.carbsPer100g > 35 && fiberDensity < 4) {
          score -= 14;
          reasons.add('diabetesCarbFiber');
        }
        break;
      case NutritionGoalType.keto:
        if (food.carbsPer100g > 10) {
          score -= 18;
          reasons.add('ketoHighCarb');
        }
        break;
      case NutritionGoalType.weightLoss:
        if (proteinDensity >= 15 || fiberDensity >= 5) {
          score += 8;
          reasons.add('weightLossSatiety');
        }
        break;
      case NutritionGoalType.muscleGrowth:
        if (proteinDensity >= 18) {
          score += 10;
          reasons.add('muscleProteinFit');
        }
        break;
      case NutritionGoalType.mediterranean:
      case NutritionGoalType.vegan:
      case NutritionGoalType.vegetarian:
      case NutritionGoalType.pescatarian:
      case NutritionGoalType.maintain:
        break;
    }

    if (reasons.isEmpty) {
      reasons.add('balancedContext');
    }

    final clamped = score.round().clamp(0, 100);
    return FoodScoreExplanation(
      score: clamped,
      titleKey: _titleKeyFor(clamped),
      reasons: reasons.take(3).toList(growable: false),
    );
  }

  static String _titleKeyFor(int score) {
    if (score >= 85) return 'excellentFit';
    if (score >= 70) return 'strongChoice';
    if (score >= 50) return 'usefulWithBalance';
    return 'needsBalancing';
  }
}
