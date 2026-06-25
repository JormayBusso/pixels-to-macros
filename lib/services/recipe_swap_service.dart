import '../models/nutrition_goal.dart';
import '../models/recipe.dart';

enum SmartSwapIntent {
  balanced,
  higherProtein,
  lowerCarb,
  faster,
  pantryFirst,
}

extension SmartSwapIntentX on SmartSwapIntent {
  String get label {
    switch (this) {
      case SmartSwapIntent.balanced:
        return 'Balanced';
      case SmartSwapIntent.higherProtein:
        return 'Higher protein';
      case SmartSwapIntent.lowerCarb:
        return 'Lower carbs';
      case SmartSwapIntent.faster:
        return 'Faster';
      case SmartSwapIntent.pantryFirst:
        return 'Pantry first';
    }
  }

  String get description {
    switch (this) {
      case SmartSwapIntent.balanced:
        return 'Closest macros and calories with fresh variety.';
      case SmartSwapIntent.higherProtein:
        return 'Prioritises more protein without blowing up calories.';
      case SmartSwapIntent.lowerCarb:
        return 'Prioritises fewer carbs and lower glycemic load.';
      case SmartSwapIntent.faster:
        return 'Prioritises shorter prep time.';
      case SmartSwapIntent.pantryFirst:
        return 'Prioritises ingredients you already have.';
    }
  }
}

class RecipeSwapService {
  RecipeSwapService._();

  static Recipe? pickBestSwap({
    required Recipe? current,
    required List<Recipe> candidates,
    required SmartSwapIntent intent,
    required NutritionGoalType goal,
    required Set<String> pantryNames,
    Set<String> usedRecipeIds = const <String>{},
  }) {
    final ranked = rankSwaps(
      current: current,
      candidates: candidates,
      intent: intent,
      goal: goal,
      pantryNames: pantryNames,
      usedRecipeIds: usedRecipeIds,
      limit: 1,
    );
    return ranked.isEmpty ? null : ranked.first;
  }

  /// Full ranked list of swap alternatives (best first), so the UI can let the
  /// user browse the WHOLE valid selection for a slot instead of a single pick.
  static List<Recipe> rankSwaps({
    required Recipe? current,
    required List<Recipe> candidates,
    required SmartSwapIntent intent,
    required NutritionGoalType goal,
    required Set<String> pantryNames,
    Set<String> usedRecipeIds = const <String>{},
    int limit = 24,
  }) {
    final pool = candidates
        .where((recipe) => recipe.id != current?.id)
        .where((recipe) => !usedRecipeIds.contains(recipe.id))
        .toList();
    final usable = pool.isNotEmpty
        ? pool
        : candidates.where((recipe) => recipe.id != current?.id).toList();
    if (usable.isEmpty) return const <Recipe>[];

    usable.sort((a, b) {
      final scoreB = _score(
        recipe: b,
        current: current,
        intent: intent,
        goal: goal,
        pantryNames: pantryNames,
      );
      final scoreA = _score(
        recipe: a,
        current: current,
        intent: intent,
        goal: goal,
        pantryNames: pantryNames,
      );
      return scoreB.compareTo(scoreA);
    });
    return usable.take(limit).toList();
  }

  static double pantryMatchRatio(Recipe recipe, Set<String> pantryNames) {
    if (pantryNames.isEmpty || recipe.ingredients.isEmpty) return 0;
    var matches = 0;
    for (final ingredient in recipe.ingredients) {
      final name = _normalise(ingredient.name);
      if (pantryNames.any((pantry) =>
          pantry.length >= 3 &&
          (name.contains(pantry) || pantry.contains(name)))) {
        matches++;
      }
    }
    return matches / recipe.ingredients.length;
  }

  static double _score({
    required Recipe recipe,
    required Recipe? current,
    required SmartSwapIntent intent,
    required NutritionGoalType goal,
    required Set<String> pantryNames,
  }) {
    final servings = recipe.servings <= 0 ? 1 : recipe.servings;
    final calories = recipe.caloriesPerServing(servings).toDouble();
    final protein = recipe.proteinPerServing(servings);
    final carbs = recipe.carbsPerServing(servings);
    final fiber = recipe.fiberPerServing(servings);
    final sugar = recipe.sugarPerServing(servings);
    final pantryScore = pantryMatchRatio(recipe, pantryNames);

    var score = recipe.healthScore.toDouble();
    score += pantryScore * (intent == SmartSwapIntent.pantryFirst ? 55 : 18);
    score += fiber.clamp(0, 12) * 1.5;
    score -= sugar.clamp(0, 35) * 0.35;

    if (current != null) {
      final currentServings = current.servings <= 0 ? 1 : current.servings;
      final currentCalories =
          current.caloriesPerServing(currentServings).toDouble();
      final currentProtein = current.proteinPerServing(currentServings);
      final currentCarbs = current.carbsPerServing(currentServings);
      score -= ((calories - currentCalories).abs() / 40).clamp(0, 12);
      score -= ((protein - currentProtein).abs() / 8).clamp(0, 5);
      score -= ((carbs - currentCarbs).abs() / 12).clamp(0, 5);
    }

    switch (intent) {
      case SmartSwapIntent.balanced:
        score += protein.clamp(0, 35) * 0.25;
        break;
      case SmartSwapIntent.higherProtein:
        score += _cappedScoreImpact(protein.clamp(0, 60) * 1.2, 36);
        score -= (calories / 180).clamp(0, 6);
        break;
      case SmartSwapIntent.lowerCarb:
        score -= _cappedScoreImpact(carbs.clamp(0, 100) * 0.75, 45);
        score -= recipe.glycemicLoad.clamp(0, 40) * 0.35;
        score += _cappedScoreImpact(fiber.clamp(0, 14) * 1.8, 20);
        break;
      case SmartSwapIntent.faster:
        score -= recipe.minutes.clamp(0, 180) * 0.45;
        score += recipe.minutes <= 20 ? 20 : 0;
        break;
      case SmartSwapIntent.pantryFirst:
        score += pantryScore > 0 ? 15 : -12;
        break;
    }

    switch (goal) {
      case NutritionGoalType.diabetes:
        score -= _cappedScoreImpact(carbs.clamp(0, 80) * 0.45, 28);
        score += _cappedScoreImpact(fiber.clamp(0, 12) * 1.5, 16);
        break;
      case NutritionGoalType.muscleGrowth:
        score += _cappedScoreImpact(protein.clamp(0, 60) * 0.8, 30);
        break;
      case NutritionGoalType.weightLoss:
        score += protein.clamp(0, 45) * 0.45;
        score -= (calories / 160).clamp(0, 8);
        break;
      case NutritionGoalType.mediterranean:
      case NutritionGoalType.vegan:
      case NutritionGoalType.vegetarian:
      case NutritionGoalType.pescatarian:
        score += fiber.clamp(0, 14) * 1.0;
        break;
      case NutritionGoalType.keto:
        score -= carbs.clamp(0, 80) * 1.0;
        break;
      case NutritionGoalType.maintain:
        break;
    }

    return score;
  }

  static double _cappedScoreImpact(num value, double maxAbs) {
    return value.toDouble().clamp(-maxAbs, maxAbs).toDouble();
  }

  static String _normalise(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
