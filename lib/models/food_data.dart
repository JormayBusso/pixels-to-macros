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
  /// True when nutrients are expressed per 100 ml (drinks) rather than per 100 g.
  final bool perMl;

  // Extended nutrients (barcode scan sources)
  final double fiberPer100g;
  final double sugarsPer100g;
  final double saturatedFatPer100g;
  final double sodiumMgPer100g;
  final double cholesterolMgPer100g;
  // Vitamins
  final double vitaminAUgPer100g;
  final double vitaminCMgPer100g;
  final double vitaminDUgPer100g;
  final double vitaminEMgPer100g;
  final double vitaminKUgPer100g;
  final double vitaminB12UgPer100g;
  final double folateUgPer100g;
  // Minerals
  final double calciumMgPer100g;
  final double ironMgPer100g;
  final double magnesiumMgPer100g;
  final double potassiumMgPer100g;
  final double zincMgPer100g;

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
    this.perMl = false,
    this.fiberPer100g = 0,
    this.sugarsPer100g = 0,
    this.saturatedFatPer100g = 0,
    this.sodiumMgPer100g = 0,
    this.cholesterolMgPer100g = 0,
    this.vitaminAUgPer100g = 0,
    this.vitaminCMgPer100g = 0,
    this.vitaminDUgPer100g = 0,
    this.vitaminEMgPer100g = 0,
    this.vitaminKUgPer100g = 0,
    this.vitaminB12UgPer100g = 0,
    this.folateUgPer100g = 0,
    this.calciumMgPer100g = 0,
    this.ironMgPer100g = 0,
    this.magnesiumMgPer100g = 0,
    this.potassiumMgPer100g = 0,
    this.zincMgPer100g = 0,
  });

  /// Unit label used for display ("100 ml" for drinks, "100 g" otherwise).
  String get unitLabel => perMl ? '100 ml' : '100 g';

  /// Meal bolus (insulin units) per 100 g/ml of this food.
  /// Formula: carbs / ICR.  Returns null when carbs == 0 (no bolus needed).
  double? bolusPer100(double icrGramsPerUnit) {
    if (carbsPer100g <= 0 || icrGramsPerUnit <= 0) return null;
    return carbsPer100g / icrGramsPerUnit;
  }

  /// Meal bolus for a given serving weight [grams] (or ml for drinks).
  double? bolusForGrams(double grams, double icrGramsPerUnit) {
    if (carbsPer100g <= 0 || icrGramsPerUnit <= 0) return null;
    final totalCarbs = carbsPer100g * grams / 100.0;
    return totalCarbs / icrGramsPerUnit;
  }

  /// Create a [FoodData] from a SQLite row map.
  factory FoodData.fromMap(Map<String, dynamic> map) {
    double d(String k) => (map[k] as num? ?? 0).toDouble();
    return FoodData(
      id: map['id'] as int?,
      label: map['label'] as String,
      densityMin: (map['density_min'] as num).toDouble(),
      densityMax: (map['density_max'] as num).toDouble(),
      kcalPer100g: (map['kcal_per_100g'] as num).toDouble(),
      category: map['category'] as String,
      proteinPer100g: d('protein_per_100g'),
      carbsPer100g: d('carbs_per_100g'),
      fatPer100g: d('fat_per_100g'),
      perMl: (map['per_ml'] as int? ?? 0) == 1,
      fiberPer100g: d('fiber_per_100g'),
      sugarsPer100g: d('sugars_per_100g'),
      saturatedFatPer100g: d('saturated_fat_per_100g'),
      sodiumMgPer100g: d('sodium_mg_per_100g'),
      cholesterolMgPer100g: d('cholesterol_mg_per_100g'),
      vitaminAUgPer100g: d('vitamin_a_ug_per_100g'),
      vitaminCMgPer100g: d('vitamin_c_mg_per_100g'),
      vitaminDUgPer100g: d('vitamin_d_ug_per_100g'),
      vitaminEMgPer100g: d('vitamin_e_mg_per_100g'),
      vitaminKUgPer100g: d('vitamin_k_ug_per_100g'),
      vitaminB12UgPer100g: d('vitamin_b12_ug_per_100g'),
      folateUgPer100g: d('folate_ug_per_100g'),
      calciumMgPer100g: d('calcium_mg_per_100g'),
      ironMgPer100g: d('iron_mg_per_100g'),
      magnesiumMgPer100g: d('magnesium_mg_per_100g'),
      potassiumMgPer100g: d('potassium_mg_per_100g'),
      zincMgPer100g: d('zinc_mg_per_100g'),
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
      'per_ml': perMl ? 1 : 0,
      'fiber_per_100g': fiberPer100g,
      'sugars_per_100g': sugarsPer100g,
      'saturated_fat_per_100g': saturatedFatPer100g,
      'sodium_mg_per_100g': sodiumMgPer100g,
      'cholesterol_mg_per_100g': cholesterolMgPer100g,
      'vitamin_a_ug_per_100g': vitaminAUgPer100g,
      'vitamin_c_mg_per_100g': vitaminCMgPer100g,
      'vitamin_d_ug_per_100g': vitaminDUgPer100g,
      'vitamin_e_mg_per_100g': vitaminEMgPer100g,
      'vitamin_k_ug_per_100g': vitaminKUgPer100g,
      'vitamin_b12_ug_per_100g': vitaminB12UgPer100g,
      'folate_ug_per_100g': folateUgPer100g,
      'calcium_mg_per_100g': calciumMgPer100g,
      'iron_mg_per_100g': ironMgPer100g,
      'magnesium_mg_per_100g': magnesiumMgPer100g,
      'potassium_mg_per_100g': potassiumMgPer100g,
      'zinc_mg_per_100g': zincMgPer100g,
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
