/// Micronutrient totals accumulated across a day's scanned foods.
class NutrientTotals {
  final double fiberG;
  final double vitaminAUg;   // μg RAE
  final double vitaminCMg;   // mg
  final double vitaminDUg;   // μg
  final double vitaminEMg;   // mg
  final double vitaminKUg;   // μg
  final double folateMcg;    // μg
  final double b12Mcg;       // μg
  final double calciumMg;    // mg
  final double ironMg;       // mg
  final double magnesiumMg;  // mg
  final double potassiumMg;  // mg
  final double sodiumMg;     // mg
  final double zincMg;       // mg

  const NutrientTotals({
    this.fiberG      = 0,
    this.vitaminAUg  = 0,
    this.vitaminCMg  = 0,
    this.vitaminDUg  = 0,
    this.vitaminEMg  = 0,
    this.vitaminKUg  = 0,
    this.folateMcg   = 0,
    this.b12Mcg      = 0,
    this.calciumMg   = 0,
    this.ironMg      = 0,
    this.magnesiumMg = 0,
    this.potassiumMg = 0,
    this.sodiumMg    = 0,
    this.zincMg      = 0,
  });

  NutrientTotals operator +(NutrientTotals o) => NutrientTotals(
        fiberG:      fiberG      + o.fiberG,
        vitaminAUg:  vitaminAUg  + o.vitaminAUg,
        vitaminCMg:  vitaminCMg  + o.vitaminCMg,
        vitaminDUg:  vitaminDUg  + o.vitaminDUg,
        vitaminEMg:  vitaminEMg  + o.vitaminEMg,
        vitaminKUg:  vitaminKUg  + o.vitaminKUg,
        folateMcg:   folateMcg   + o.folateMcg,
        b12Mcg:      b12Mcg      + o.b12Mcg,
        calciumMg:   calciumMg   + o.calciumMg,
        ironMg:      ironMg      + o.ironMg,
        magnesiumMg: magnesiumMg + o.magnesiumMg,
        potassiumMg: potassiumMg + o.potassiumMg,
        sodiumMg:    sodiumMg    + o.sodiumMg,
        zincMg:      zincMg      + o.zincMg,
      );

  NutrientTotals operator *(double factor) => NutrientTotals(
        fiberG:      fiberG      * factor,
        vitaminAUg:  vitaminAUg  * factor,
        vitaminCMg:  vitaminCMg  * factor,
        vitaminDUg:  vitaminDUg  * factor,
        vitaminEMg:  vitaminEMg  * factor,
        vitaminKUg:  vitaminKUg  * factor,
        folateMcg:   folateMcg   * factor,
        b12Mcg:      b12Mcg      * factor,
        calciumMg:   calciumMg   * factor,
        ironMg:      ironMg      * factor,
        magnesiumMg: magnesiumMg * factor,
        potassiumMg: potassiumMg * factor,
        sodiumMg:    sodiumMg    * factor,
        zincMg:      zincMg      * factor,
      );
}

/// Daily Reference Values (FDA / NIH) for adults.
class NutrientDRV {
  static const double fiberG      = 28.0;
  static const double vitaminAUg  = 900.0;
  static const double vitaminCMg  = 90.0;
  static const double vitaminDUg  = 15.0;
  static const double vitaminEMg  = 15.0;
  static const double vitaminKUg  = 120.0;
  static const double folateMcg   = 400.0;
  static const double b12Mcg      = 2.4;
  static const double calciumMg   = 1300.0;
  static const double ironMg      = 18.0;
  static const double magnesiumMg = 420.0;
  static const double potassiumMg = 4700.0;
  static const double sodiumMaxMg = 2300.0; // upper limit
  static const double zincMg      = 11.0;
}

/// Approximate nutrient content per 100 g by food category
/// (based on USDA FoodData Central category averages).
const Map<String, NutrientTotals> _categoryPer100g = {
  'fruit': NutrientTotals(
    fiberG: 2.0, vitaminCMg: 40.0, vitaminAUg: 20.0,
    potassiumMg: 180.0, folateMcg: 10.0, vitaminKUg: 5.0,
  ),
  'vegetable': NutrientTotals(
    fiberG: 2.5, vitaminCMg: 25.0, vitaminAUg: 100.0, vitaminKUg: 80.0,
    potassiumMg: 200.0, folateMcg: 50.0, magnesiumMg: 20.0, ironMg: 0.8,
  ),
  'protein': NutrientTotals(
    ironMg: 2.0, zincMg: 3.0, b12Mcg: 1.5,
    potassiumMg: 320.0, sodiumMg: 70.0,
  ),
  'grain': NutrientTotals(
    fiberG: 1.5, folateMcg: 20.0, ironMg: 0.8,
    magnesiumMg: 15.0, potassiumMg: 90.0,
  ),
  'dairy': NutrientTotals(
    calciumMg: 250.0, vitaminDUg: 1.2, b12Mcg: 0.5,
    vitaminAUg: 50.0, potassiumMg: 150.0,
  ),
  'legume': NutrientTotals(
    fiberG: 6.0, ironMg: 3.0, magnesiumMg: 80.0,
    zincMg: 1.5, folateMcg: 100.0, potassiumMg: 400.0,
  ),
  'nut': NutrientTotals(
    fiberG: 3.0, vitaminEMg: 5.0, magnesiumMg: 70.0,
    zincMg: 2.0, ironMg: 1.5, vitaminKUg: 5.0,
  ),
  'snack': NutrientTotals(fiberG: 0.5, sodiumMg: 200.0),
  'mixed': NutrientTotals(
    fiberG: 1.5, sodiumMg: 300.0, ironMg: 1.0,
    potassiumMg: 150.0, calciumMg: 50.0,
  ),
  'drink': NutrientTotals(),
};

/// Returns estimated [NutrientTotals] for [weightG] grams of a food item
/// with the given [category].
NutrientTotals estimateNutrientsForFood({
  required String category,
  required double weightG,
}) {
  final per100g = _categoryPer100g[category] ?? _categoryPer100g['mixed']!;
  return per100g * (weightG / 100.0);
}
