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

/// Daily Reference Values — 2026 DRI (NIH / NASEM).
/// Gender-specific values based on the Dietary Reference Intakes.
/// Note: vitaminCMg stored in mg, vitaminEMg stored in mg, etc.
/// The user-provided numbers for Vitamin C are in µg in the spec but
/// standard DRI for Vitamin C is expressed in mg — the µg figures given
/// (90,000 µg male, 75,000 µg female) equal 90 mg and 75 mg respectively,
/// which matches the standard DRI.  We store everything in the same units
/// as [NutrientTotals] (mg for Vitamin C, mg for Vitamin E).
class NutrientDRV {
  // Gender-neutral / shared
  static const double fiberG   = 28.0;  // general recommendation
  static const double b12Mcg   = 2.4;   // same for both
  static const double folateMcg = 400.0; // same for both
  static const double vitaminDUg = 15.0; // same for both
  static const double vitaminEMg = 15.0; // same for both (15,000 µg = 15 mg)
  static const double sodiumMaxMg = 1500.0; // DRI upper limit (NIH 2026)

  // Male DRVs
  static const double vitaminAUg_male  = 900.0;
  static const double vitaminCMg_male  = 90.0;   // 90,000 µg = 90 mg
  static const double vitaminKUg_male  = 120.0;
  static const double calciumMg_male   = 1000.0;
  static const double ironMg_male      = 8.0;
  static const double magnesiumMg_male = 420.0;
  static const double potassiumMg_male = 3400.0;
  static const double zincMg_male      = 11.0;

  // Female DRVs
  static const double vitaminAUg_female  = 700.0;
  static const double vitaminCMg_female  = 75.0;   // 75,000 µg = 75 mg
  static const double vitaminKUg_female  = 90.0;
  static const double calciumMg_female   = 1000.0;
  static const double ironMg_female      = 18.0;
  static const double magnesiumMg_female = 320.0;
  static const double potassiumMg_female = 2600.0;
  static const double zincMg_female      = 8.0;

  // Legacy ungendered accessors (used by code that hasn't been updated yet,
  // default to male values which were the old defaults).
  static const double vitaminAUg  = vitaminAUg_male;
  static const double vitaminCMg  = vitaminCMg_male;
  static const double vitaminKUg  = vitaminKUg_male;
  static const double calciumMg   = calciumMg_male;
  static const double ironMg      = ironMg_male;
  static const double magnesiumMg = magnesiumMg_male;
  static const double potassiumMg = potassiumMg_male;
  static const double zincMg      = zincMg_male;
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
