/// Represents one row in the `food_data` SQLite table.
class FoodData {
  final int? id;
  final String label;
  final double densityMin; // g/cm³
  final double densityMax; // g/cm³
  final double kcalPer100g;
  final String category;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;

  const FoodData({
    this.id,
    required this.label,
    required this.densityMin,
    required this.densityMax,
    required this.kcalPer100g,
    required this.category,
    this.proteinPer100g = 0,
    this.carbsPer100g = 0,
    this.fatPer100g = 0,
  });

  /// Create a [FoodData] from a SQLite row map.
  factory FoodData.fromMap(Map<String, dynamic> map) {
    return FoodData(
      id: map['id'] as int?,
      label: map['label'] as String,
      densityMin: (map['density_min'] as num).toDouble(),
      densityMax: (map['density_max'] as num).toDouble(),
      kcalPer100g: (map['kcal_per_100g'] as num).toDouble(),
      category: map['category'] as String,
      proteinPer100g: (map['protein_per_100g'] as num? ?? 0).toDouble(),
      carbsPer100g: (map['carbs_per_100g'] as num? ?? 0).toDouble(),
      fatPer100g: (map['fat_per_100g'] as num? ?? 0).toDouble(),
    );
  }

  /// Convert to a map suitable for SQLite insert.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'label': label,
      'density_min': densityMin,
      'density_max': densityMax,
      'kcal_per_100g': kcalPer100g,
      'category': category,
      'protein_per_100g': proteinPer100g,
      'carbs_per_100g': carbsPer100g,
      'fat_per_100g': fatPer100g,
    };
  }

  // ── Calorie estimation helpers (Part 12 — uncertainty model) ──────────────

  /// Minimum estimated weight for a given volume in cm³.
  double weightMinGrams(double volumeCm3) => volumeCm3 * densityMin;

  /// Maximum estimated weight for a given volume in cm³.
  double weightMaxGrams(double volumeCm3) => volumeCm3 * densityMax;

  /// Calorie range for a given volume.
  ({double min, double max}) calorieRange(double volumeCm3) {
    final wMin = weightMinGrams(volumeCm3);
    final wMax = weightMaxGrams(volumeCm3);
    return (
      min: wMin / 100.0 * kcalPer100g,
      max: wMax / 100.0 * kcalPer100g,
    );
  }

  @override
  String toString() => 'FoodData($label, $kcalPer100g kcal/100 g)';
}
