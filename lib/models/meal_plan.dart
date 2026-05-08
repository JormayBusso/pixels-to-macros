import 'recipe.dart';

/// A single assigned recipe slot within the weekly meal plan.
class MealPlanEntry {
  final int? id;
  final int weekNumber; // ISO week number
  final int year;
  final int dayOfWeek; // 1 = Monday … 7 = Sunday
  final RecipeMealType mealType;
  final String recipeId;
  final String recipeName;

  const MealPlanEntry({
    this.id,
    required this.weekNumber,
    required this.year,
    required this.dayOfWeek,
    required this.mealType,
    required this.recipeId,
    required this.recipeName,
  });

  factory MealPlanEntry.fromMap(Map<String, dynamic> m) => MealPlanEntry(
        id: m['id'] as int?,
        weekNumber: m['week_number'] as int,
        year: m['year'] as int,
        dayOfWeek: m['day_of_week'] as int,
        mealType: RecipeMealTypeX.fromJson(m['meal_type'] as String?),
        recipeId: m['recipe_id'] as String,
        recipeName: m['recipe_name'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'week_number': weekNumber,
        'year': year,
        'day_of_week': dayOfWeek,
        'meal_type': mealType.jsonKey,
        'recipe_id': recipeId,
        'recipe_name': recipeName,
      };
}

/// Days available to configure in the planner.
const List<String> kWeekDays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
