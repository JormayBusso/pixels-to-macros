/// A user-created meal composed of one or more food ingredients.
enum MealType {
  breakfast,
  lunch,
  dinner;

  String get displayName => switch (this) {
        MealType.breakfast => 'Breakfast',
        MealType.lunch => 'Lunch',
        MealType.dinner => 'Dinner',
      };

  String get dbValue => name;

  static MealType fromDbValue(String v) =>
      MealType.values.firstWhere((e) => e.name == v,
          orElse: () => MealType.lunch);
}

/// One ingredient inside a [CustomMeal].
class MealIngredient {
  final int? id;
  final int mealId;
  final String foodLabel;
  final double grams;

  const MealIngredient({
    this.id,
    required this.mealId,
    required this.foodLabel,
    required this.grams,
  });

  factory MealIngredient.fromMap(Map<String, dynamic> m) => MealIngredient(
        id: m['id'] as int?,
        mealId: m['meal_id'] as int,
        foodLabel: m['food_label'] as String,
        grams: (m['grams'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'meal_id': mealId,
        'food_label': foodLabel,
        'grams': grams,
      };

  MealIngredient copyWith({double? grams}) => MealIngredient(
        id: id,
        mealId: mealId,
        foodLabel: foodLabel,
        grams: grams ?? this.grams,
      );
}

/// A saved user-defined meal (e.g. "My breakfast bowl").
class CustomMeal {
  final int? id;
  final String name;
  final MealType mealType;
  final DateTime createdAt;
  final List<MealIngredient> ingredients;

  const CustomMeal({
    this.id,
    required this.name,
    required this.mealType,
    required this.createdAt,
    this.ingredients = const [],
  });

  factory CustomMeal.fromMap(Map<String, dynamic> m,
      {List<MealIngredient> ingredients = const []}) =>
      CustomMeal(
        id: m['id'] as int?,
        name: m['name'] as String,
        mealType: MealType.fromDbValue(m['meal_type'] as String),
        createdAt: DateTime.parse(m['created_at'] as String),
        ingredients: ingredients,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'meal_type': mealType.dbValue,
        'created_at': createdAt.toIso8601String(),
      };

  CustomMeal copyWith({
    String? name,
    MealType? mealType,
    List<MealIngredient>? ingredients,
  }) =>
      CustomMeal(
        id: id,
        name: name ?? this.name,
        mealType: mealType ?? this.mealType,
        createdAt: createdAt,
        ingredients: ingredients ?? this.ingredients,
      );

  /// Total kcal for this meal, given a [Map<label → kcalPer100g>].
  double totalKcal(Map<String, double> kcalMap) => ingredients.fold(
      0,
      (sum, ing) =>
          sum + (kcalMap[ing.foodLabel] ?? 0) * ing.grams / 100.0);
}
