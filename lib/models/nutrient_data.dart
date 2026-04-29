import 'food_data.dart';

/// Micronutrient totals accumulated across a day's scanned foods.
class NutrientTotals {
  final double fiberG;
  final double vitaminAUg; // μg RAE
  final double vitaminCMg; // mg
  final double vitaminDUg; // μg
  final double vitaminEMg; // mg
  final double vitaminKUg; // μg
  final double folateMcg; // μg
  final double b12Mcg; // μg
  final double calciumMg; // mg
  final double ironMg; // mg
  final double magnesiumMg; // mg
  final double potassiumMg; // mg
  final double sodiumMg; // mg
  final double zincMg; // mg

  const NutrientTotals({
    this.fiberG = 0,
    this.vitaminAUg = 0,
    this.vitaminCMg = 0,
    this.vitaminDUg = 0,
    this.vitaminEMg = 0,
    this.vitaminKUg = 0,
    this.folateMcg = 0,
    this.b12Mcg = 0,
    this.calciumMg = 0,
    this.ironMg = 0,
    this.magnesiumMg = 0,
    this.potassiumMg = 0,
    this.sodiumMg = 0,
    this.zincMg = 0,
  });

  bool get hasAnyValue => [
        fiberG,
        vitaminAUg,
        vitaminCMg,
        vitaminDUg,
        vitaminEMg,
        vitaminKUg,
        folateMcg,
        b12Mcg,
        calciumMg,
        ironMg,
        magnesiumMg,
        potassiumMg,
        sodiumMg,
        zincMg,
      ].any((value) => value > 0);

  NutrientTotals operator +(NutrientTotals o) => NutrientTotals(
        fiberG: fiberG + o.fiberG,
        vitaminAUg: vitaminAUg + o.vitaminAUg,
        vitaminCMg: vitaminCMg + o.vitaminCMg,
        vitaminDUg: vitaminDUg + o.vitaminDUg,
        vitaminEMg: vitaminEMg + o.vitaminEMg,
        vitaminKUg: vitaminKUg + o.vitaminKUg,
        folateMcg: folateMcg + o.folateMcg,
        b12Mcg: b12Mcg + o.b12Mcg,
        calciumMg: calciumMg + o.calciumMg,
        ironMg: ironMg + o.ironMg,
        magnesiumMg: magnesiumMg + o.magnesiumMg,
        potassiumMg: potassiumMg + o.potassiumMg,
        sodiumMg: sodiumMg + o.sodiumMg,
        zincMg: zincMg + o.zincMg,
      );

  NutrientTotals operator *(double factor) => NutrientTotals(
        fiberG: fiberG * factor,
        vitaminAUg: vitaminAUg * factor,
        vitaminCMg: vitaminCMg * factor,
        vitaminDUg: vitaminDUg * factor,
        vitaminEMg: vitaminEMg * factor,
        vitaminKUg: vitaminKUg * factor,
        folateMcg: folateMcg * factor,
        b12Mcg: b12Mcg * factor,
        calciumMg: calciumMg * factor,
        ironMg: ironMg * factor,
        magnesiumMg: magnesiumMg * factor,
        potassiumMg: potassiumMg * factor,
        sodiumMg: sodiumMg * factor,
        zincMg: zincMg * factor,
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
  static const double fiberG = 28.0; // general recommendation
  static const double b12Mcg = 2.4; // same for both
  static const double folateMcg = 400.0; // same for both
  static const double vitaminDUg = 15.0; // same for both
  static const double vitaminEMg = 15.0; // same for both (15,000 µg = 15 mg)
  static const double sodiumMaxMg = 1500.0; // DRI upper limit (NIH 2026)

  // Male DRVs
  static const double vitaminAUg_male = 900.0;
  static const double vitaminCMg_male = 90.0; // 90,000 µg = 90 mg
  static const double vitaminKUg_male = 120.0;
  static const double calciumMg_male = 1000.0;
  static const double ironMg_male = 8.0;
  static const double magnesiumMg_male = 420.0;
  static const double potassiumMg_male = 3400.0;
  static const double zincMg_male = 11.0;

  // Female DRVs
  static const double vitaminAUg_female = 700.0;
  static const double vitaminCMg_female = 75.0; // 75,000 µg = 75 mg
  static const double vitaminKUg_female = 90.0;
  static const double calciumMg_female = 1000.0;
  static const double ironMg_female = 18.0;
  static const double magnesiumMg_female = 320.0;
  static const double potassiumMg_female = 2600.0;
  static const double zincMg_female = 8.0;

  // Legacy ungendered accessors (used by code that hasn't been updated yet,
  // default to male values which were the old defaults).
  static const double vitaminAUg = vitaminAUg_male;
  static const double vitaminCMg = vitaminCMg_male;
  static const double vitaminKUg = vitaminKUg_male;
  static const double calciumMg = calciumMg_male;
  static const double ironMg = ironMg_male;
  static const double magnesiumMg = magnesiumMg_male;
  static const double potassiumMg = potassiumMg_male;
  static const double zincMg = zincMg_male;
}

/// Approximate nutrient content per 100 g by food category
/// (based on USDA FoodData Central category averages).
const Map<String, NutrientTotals> _categoryPer100g = {
  'fruit': NutrientTotals(
    fiberG: 2.0,
    vitaminCMg: 40.0,
    vitaminAUg: 20.0,
    potassiumMg: 180.0,
    folateMcg: 10.0,
    vitaminKUg: 5.0,
  ),
  'vegetable': NutrientTotals(
    fiberG: 2.5,
    vitaminCMg: 25.0,
    vitaminAUg: 100.0,
    vitaminKUg: 80.0,
    potassiumMg: 200.0,
    folateMcg: 50.0,
    magnesiumMg: 20.0,
    ironMg: 0.8,
  ),
  'protein': NutrientTotals(
    ironMg: 2.0,
    zincMg: 3.0,
    b12Mcg: 1.5,
    potassiumMg: 320.0,
    sodiumMg: 70.0,
  ),
  'grain': NutrientTotals(
    fiberG: 1.5,
    folateMcg: 20.0,
    ironMg: 0.8,
    magnesiumMg: 15.0,
    potassiumMg: 90.0,
  ),
  'dairy': NutrientTotals(
    calciumMg: 250.0,
    vitaminDUg: 1.2,
    b12Mcg: 0.5,
    vitaminAUg: 50.0,
    potassiumMg: 150.0,
  ),
  'legume': NutrientTotals(
    fiberG: 6.0,
    ironMg: 3.0,
    magnesiumMg: 80.0,
    zincMg: 1.5,
    folateMcg: 100.0,
    potassiumMg: 400.0,
  ),
  'nut': NutrientTotals(
    fiberG: 3.0,
    vitaminEMg: 5.0,
    magnesiumMg: 70.0,
    zincMg: 2.0,
    ironMg: 1.5,
    vitaminKUg: 5.0,
  ),
  'snack': NutrientTotals(fiberG: 0.5, sodiumMg: 200.0),
  'mixed': NutrientTotals(
    fiberG: 1.5,
    sodiumMg: 300.0,
    ironMg: 1.0,
    potassiumMg: 150.0,
    calciumMg: 50.0,
  ),
  'drink': NutrientTotals(),
};

const Map<String, NutrientTotals> _labelPer100g = {
  'apple': NutrientTotals(
    fiberG: 2.4,
    vitaminAUg: 3,
    vitaminCMg: 4.6,
    vitaminEMg: 0.2,
    vitaminKUg: 2.2,
    folateMcg: 3,
    calciumMg: 6,
    ironMg: 0.1,
    magnesiumMg: 5,
    potassiumMg: 107,
    sodiumMg: 1,
    zincMg: 0.04,
  ),
  'banana': NutrientTotals(
    fiberG: 2.6,
    vitaminAUg: 3,
    vitaminCMg: 8.7,
    vitaminEMg: 0.1,
    vitaminKUg: 0.5,
    folateMcg: 20,
    calciumMg: 5,
    ironMg: 0.3,
    magnesiumMg: 27,
    potassiumMg: 358,
    sodiumMg: 1,
    zincMg: 0.15,
  ),
  'orange': NutrientTotals(
    fiberG: 2.4,
    vitaminAUg: 11,
    vitaminCMg: 53.2,
    vitaminEMg: 0.2,
    vitaminKUg: 0,
    folateMcg: 30,
    calciumMg: 40,
    ironMg: 0.1,
    magnesiumMg: 10,
    potassiumMg: 181,
    sodiumMg: 0,
    zincMg: 0.07,
  ),
  'strawberry': NutrientTotals(
    fiberG: 2,
    vitaminAUg: 1,
    vitaminCMg: 58.8,
    vitaminEMg: 0.3,
    vitaminKUg: 2.2,
    folateMcg: 24,
    calciumMg: 16,
    ironMg: 0.4,
    magnesiumMg: 13,
    potassiumMg: 153,
    sodiumMg: 1,
    zincMg: 0.14,
  ),
  'grape': NutrientTotals(
    fiberG: 0.9,
    vitaminAUg: 3,
    vitaminCMg: 3.2,
    vitaminEMg: 0.2,
    vitaminKUg: 14.6,
    folateMcg: 2,
    calciumMg: 10,
    ironMg: 0.4,
    magnesiumMg: 7,
    potassiumMg: 191,
    sodiumMg: 2,
    zincMg: 0.07,
  ),
  'watermelon': NutrientTotals(
    fiberG: 0.4,
    vitaminAUg: 28,
    vitaminCMg: 8.1,
    vitaminEMg: 0.1,
    vitaminKUg: 0.1,
    folateMcg: 3,
    calciumMg: 7,
    ironMg: 0.2,
    magnesiumMg: 10,
    potassiumMg: 112,
    sodiumMg: 1,
    zincMg: 0.1,
  ),
  'mango': NutrientTotals(
    fiberG: 1.6,
    vitaminAUg: 54,
    vitaminCMg: 36.4,
    vitaminEMg: 0.9,
    vitaminKUg: 4.2,
    folateMcg: 43,
    calciumMg: 11,
    ironMg: 0.2,
    magnesiumMg: 10,
    potassiumMg: 168,
    sodiumMg: 1,
    zincMg: 0.09,
  ),
  'pineapple': NutrientTotals(
    fiberG: 1.4,
    vitaminAUg: 3,
    vitaminCMg: 47.8,
    vitaminEMg: 0,
    vitaminKUg: 0.7,
    folateMcg: 18,
    calciumMg: 13,
    ironMg: 0.3,
    magnesiumMg: 12,
    potassiumMg: 109,
    sodiumMg: 1,
    zincMg: 0.12,
  ),
  'broccoli': NutrientTotals(
    fiberG: 2.6,
    vitaminAUg: 31,
    vitaminCMg: 89.2,
    vitaminEMg: 0.8,
    vitaminKUg: 101.6,
    folateMcg: 63,
    calciumMg: 47,
    ironMg: 0.7,
    magnesiumMg: 21,
    potassiumMg: 316,
    sodiumMg: 33,
    zincMg: 0.4,
  ),
  'carrot': NutrientTotals(
    fiberG: 2.8,
    vitaminAUg: 835,
    vitaminCMg: 5.9,
    vitaminEMg: 0.7,
    vitaminKUg: 13.2,
    folateMcg: 19,
    calciumMg: 33,
    ironMg: 0.3,
    magnesiumMg: 12,
    potassiumMg: 320,
    sodiumMg: 69,
    zincMg: 0.2,
  ),
  'tomato': NutrientTotals(
    fiberG: 1.2,
    vitaminAUg: 42,
    vitaminCMg: 13.7,
    vitaminEMg: 0.5,
    vitaminKUg: 7.9,
    folateMcg: 15,
    calciumMg: 10,
    ironMg: 0.3,
    magnesiumMg: 11,
    potassiumMg: 237,
    sodiumMg: 5,
    zincMg: 0.2,
  ),
  'cucumber': NutrientTotals(
    fiberG: 0.5,
    vitaminAUg: 5,
    vitaminCMg: 2.8,
    vitaminEMg: 0,
    vitaminKUg: 16.4,
    folateMcg: 7,
    calciumMg: 16,
    ironMg: 0.3,
    magnesiumMg: 13,
    potassiumMg: 147,
    sodiumMg: 2,
    zincMg: 0.2,
  ),
  'lettuce': NutrientTotals(
    fiberG: 1.3,
    vitaminAUg: 370,
    vitaminCMg: 9.2,
    vitaminEMg: 0.2,
    vitaminKUg: 126.3,
    folateMcg: 38,
    calciumMg: 36,
    ironMg: 0.9,
    magnesiumMg: 13,
    potassiumMg: 194,
    sodiumMg: 28,
    zincMg: 0.2,
  ),
  'potato': NutrientTotals(
    fiberG: 2.2,
    vitaminCMg: 19.7,
    vitaminEMg: 0,
    vitaminKUg: 2,
    folateMcg: 16,
    calciumMg: 12,
    ironMg: 0.8,
    magnesiumMg: 23,
    potassiumMg: 421,
    sodiumMg: 6,
    zincMg: 0.3,
  ),
  'sweet potato': NutrientTotals(
    fiberG: 3,
    vitaminAUg: 709,
    vitaminCMg: 2.4,
    vitaminEMg: 0.3,
    vitaminKUg: 1.8,
    folateMcg: 11,
    calciumMg: 30,
    ironMg: 0.6,
    magnesiumMg: 25,
    potassiumMg: 337,
    sodiumMg: 55,
    zincMg: 0.3,
  ),
  'spinach': NutrientTotals(
    fiberG: 2.2,
    vitaminAUg: 469,
    vitaminCMg: 28.1,
    vitaminEMg: 2,
    vitaminKUg: 482.9,
    folateMcg: 194,
    calciumMg: 99,
    ironMg: 2.7,
    magnesiumMg: 79,
    potassiumMg: 558,
    sodiumMg: 79,
    zincMg: 0.5,
  ),
  'pepper': NutrientTotals(
    fiberG: 1.7,
    vitaminAUg: 157,
    vitaminCMg: 127.7,
    vitaminEMg: 1.6,
    vitaminKUg: 4.9,
    folateMcg: 46,
    calciumMg: 7,
    ironMg: 0.4,
    magnesiumMg: 12,
    potassiumMg: 211,
    sodiumMg: 4,
    zincMg: 0.3,
  ),
  'onion': NutrientTotals(
    fiberG: 1.7,
    vitaminCMg: 7.4,
    vitaminEMg: 0,
    vitaminKUg: 0.4,
    folateMcg: 19,
    calciumMg: 23,
    ironMg: 0.2,
    magnesiumMg: 10,
    potassiumMg: 146,
    sodiumMg: 4,
    zincMg: 0.2,
  ),
  'rice': NutrientTotals(
    fiberG: 0.4,
    folateMcg: 58,
    calciumMg: 10,
    ironMg: 1.2,
    magnesiumMg: 12,
    potassiumMg: 35,
    sodiumMg: 1,
    zincMg: 0.5,
  ),
  'pasta': NutrientTotals(
    fiberG: 1.8,
    folateMcg: 18,
    calciumMg: 7,
    ironMg: 1.3,
    magnesiumMg: 18,
    potassiumMg: 44,
    sodiumMg: 1,
    zincMg: 0.5,
  ),
  'bread': NutrientTotals(
    fiberG: 2.7,
    vitaminEMg: 0.2,
    vitaminKUg: 1.4,
    folateMcg: 85,
    calciumMg: 144,
    ironMg: 3.6,
    magnesiumMg: 25,
    potassiumMg: 115,
    sodiumMg: 491,
    zincMg: 0.8,
  ),
  'noodles': NutrientTotals(
    fiberG: 1.2,
    folateMcg: 12,
    calciumMg: 8,
    ironMg: 1,
    magnesiumMg: 20,
    potassiumMg: 38,
    sodiumMg: 3,
    zincMg: 0.4,
  ),
  'oatmeal': NutrientTotals(
    fiberG: 1.7,
    folateMcg: 6,
    calciumMg: 9,
    ironMg: 0.9,
    magnesiumMg: 27,
    potassiumMg: 70,
    sodiumMg: 49,
    zincMg: 0.8,
  ),
  'corn': NutrientTotals(
    fiberG: 2.7,
    vitaminAUg: 9,
    vitaminCMg: 6.8,
    vitaminEMg: 0.1,
    vitaminKUg: 0.3,
    folateMcg: 42,
    calciumMg: 2,
    ironMg: 0.5,
    magnesiumMg: 37,
    potassiumMg: 270,
    sodiumMg: 15,
    zincMg: 0.5,
  ),
  'chicken': NutrientTotals(
    b12Mcg: 0.3,
    ironMg: 1,
    magnesiumMg: 29,
    potassiumMg: 256,
    sodiumMg: 74,
    zincMg: 1,
  ),
  'beef': NutrientTotals(
    b12Mcg: 2.4,
    ironMg: 2.6,
    magnesiumMg: 21,
    potassiumMg: 318,
    sodiumMg: 72,
    zincMg: 4.8,
  ),
  'pork': NutrientTotals(
    b12Mcg: 0.7,
    ironMg: 0.9,
    magnesiumMg: 25,
    potassiumMg: 362,
    sodiumMg: 62,
    zincMg: 2.4,
  ),
  'fish': NutrientTotals(
    vitaminDUg: 5,
    b12Mcg: 2.5,
    calciumMg: 15,
    ironMg: 0.5,
    magnesiumMg: 30,
    potassiumMg: 350,
    sodiumMg: 60,
    zincMg: 0.5,
  ),
  'salmon': NutrientTotals(
    vitaminAUg: 40,
    vitaminDUg: 10.9,
    vitaminEMg: 1.1,
    b12Mcg: 3.2,
    calciumMg: 9,
    ironMg: 0.3,
    magnesiumMg: 27,
    potassiumMg: 363,
    sodiumMg: 59,
    zincMg: 0.4,
  ),
  'shrimp': NutrientTotals(
    b12Mcg: 1.1,
    calciumMg: 70,
    ironMg: 0.5,
    magnesiumMg: 39,
    potassiumMg: 259,
    sodiumMg: 111,
    zincMg: 1.3,
  ),
  'egg': NutrientTotals(
    vitaminAUg: 140,
    vitaminDUg: 2,
    vitaminEMg: 1.1,
    vitaminKUg: 0.3,
    folateMcg: 47,
    b12Mcg: 1.1,
    calciumMg: 50,
    ironMg: 1.2,
    magnesiumMg: 10,
    potassiumMg: 126,
    sodiumMg: 124,
    zincMg: 1,
  ),
  'tofu': NutrientTotals(
    fiberG: 0.3,
    folateMcg: 15,
    calciumMg: 350,
    ironMg: 5.4,
    magnesiumMg: 30,
    potassiumMg: 121,
    sodiumMg: 7,
    zincMg: 0.8,
  ),
  'cheese': NutrientTotals(
    vitaminAUg: 265,
    vitaminDUg: 0.6,
    vitaminEMg: 0.3,
    vitaminKUg: 2.4,
    folateMcg: 27,
    b12Mcg: 1.5,
    calciumMg: 721,
    ironMg: 0.7,
    magnesiumMg: 28,
    potassiumMg: 98,
    sodiumMg: 621,
    zincMg: 3.1,
  ),
  'yogurt': NutrientTotals(
    vitaminAUg: 27,
    vitaminDUg: 0.1,
    folateMcg: 7,
    b12Mcg: 0.8,
    calciumMg: 121,
    ironMg: 0.1,
    magnesiumMg: 12,
    potassiumMg: 155,
    sodiumMg: 46,
    zincMg: 0.6,
  ),
  'salad': NutrientTotals(
    fiberG: 2,
    vitaminAUg: 200,
    vitaminCMg: 15,
    vitaminEMg: 0.8,
    vitaminKUg: 90,
    folateMcg: 40,
    calciumMg: 40,
    ironMg: 1,
    magnesiumMg: 20,
    potassiumMg: 250,
    sodiumMg: 50,
    zincMg: 0.3,
  ),
  'pizza': NutrientTotals(
    fiberG: 2.3,
    vitaminAUg: 55,
    vitaminCMg: 1.5,
    vitaminEMg: 0.8,
    vitaminKUg: 6,
    folateMcg: 39,
    b12Mcg: 0.7,
    calciumMg: 188,
    ironMg: 2.5,
    magnesiumMg: 24,
    potassiumMg: 184,
    sodiumMg: 598,
    zincMg: 1.4,
  ),
  'french fries': NutrientTotals(
    fiberG: 3.8,
    vitaminCMg: 4.7,
    vitaminEMg: 1.7,
    vitaminKUg: 16.3,
    folateMcg: 30,
    calciumMg: 18,
    ironMg: 0.8,
    magnesiumMg: 35,
    potassiumMg: 579,
    sodiumMg: 210,
    zincMg: 0.4,
  ),
  'cake': NutrientTotals(
    fiberG: 1,
    vitaminAUg: 60,
    vitaminCMg: 0.2,
    vitaminEMg: 0.3,
    vitaminKUg: 2,
    folateMcg: 25,
    calciumMg: 50,
    ironMg: 1.2,
    magnesiumMg: 15,
    potassiumMg: 100,
    sodiumMg: 315,
    zincMg: 0.3,
  ),
  'chocolate': NutrientTotals(
    fiberG: 7,
    vitaminEMg: 0.6,
    vitaminKUg: 7,
    folateMcg: 18,
    calciumMg: 73,
    ironMg: 11.9,
    magnesiumMg: 228,
    potassiumMg: 715,
    sodiumMg: 20,
    zincMg: 3.3,
  ),
  'milk': NutrientTotals(
    vitaminAUg: 46,
    vitaminDUg: 1.2,
    folateMcg: 5,
    b12Mcg: 0.45,
    calciumMg: 120,
    ironMg: 0,
    magnesiumMg: 11,
    potassiumMg: 150,
    sodiumMg: 43,
    zincMg: 0.4,
  ),
  'coffee': NutrientTotals(
    magnesiumMg: 3,
    potassiumMg: 49,
    sodiumMg: 2,
  ),
  'tea': NutrientTotals(
    magnesiumMg: 3,
    potassiumMg: 18,
    sodiumMg: 1,
  ),
  'orange juice': NutrientTotals(
    vitaminAUg: 10,
    vitaminCMg: 50,
    folateMcg: 30,
    calciumMg: 11,
    ironMg: 0.2,
    magnesiumMg: 11,
    potassiumMg: 200,
    sodiumMg: 1,
    zincMg: 0.1,
  ),
  'apple juice': NutrientTotals(
    vitaminCMg: 1,
    calciumMg: 7,
    ironMg: 0.1,
    magnesiumMg: 5,
    potassiumMg: 101,
    sodiumMg: 4,
  ),
  'soda': NutrientTotals(sodiumMg: 5),
  'beer': NutrientTotals(
    folateMcg: 6,
    magnesiumMg: 6,
    potassiumMg: 27,
    sodiumMg: 4,
  ),
  'protein shake': NutrientTotals(
    vitaminDUg: 0.8,
    b12Mcg: 0.4,
    calciumMg: 130,
    ironMg: 0.4,
    magnesiumMg: 20,
    potassiumMg: 200,
    sodiumMg: 70,
    zincMg: 0.8,
  ),
  'coconut water': NutrientTotals(
    fiberG: 1.1,
    vitaminCMg: 2.4,
    folateMcg: 3,
    calciumMg: 24,
    ironMg: 0.3,
    magnesiumMg: 25,
    potassiumMg: 250,
    sodiumMg: 105,
    zincMg: 0.1,
  ),
};

NutrientTotals categoryNutrientsPer100g(String category) {
  final key = category.toLowerCase().trim();
  return _categoryPer100g[key] ?? _categoryPer100g['mixed']!;
}

NutrientTotals storedNutrientsPer100g(FoodData food) {
  return NutrientTotals(
    fiberG: food.fiberPer100g,
    vitaminAUg: food.vitaminAUgPer100g,
    vitaminCMg: food.vitaminCMgPer100g,
    vitaminDUg: food.vitaminDUgPer100g,
    vitaminEMg: food.vitaminEMgPer100g,
    vitaminKUg: food.vitaminKUgPer100g,
    folateMcg: food.folateUgPer100g,
    b12Mcg: food.vitaminB12UgPer100g,
    calciumMg: food.calciumMgPer100g,
    ironMg: food.ironMgPer100g,
    magnesiumMg: food.magnesiumMgPer100g,
    potassiumMg: food.potassiumMgPer100g,
    sodiumMg: food.sodiumMgPer100g,
    zincMg: food.zincMgPer100g,
  );
}

NutrientTotals nutrientsPer100gForFood(FoodData food) {
  final stored = storedNutrientsPer100g(food);
  if (stored.hasAnyValue) return stored;

  final labelEstimate = _labelPer100g[_normalisedFoodLabel(food.label)];
  if (labelEstimate != null) return labelEstimate;

  return categoryNutrientsPer100g(food.category);
}

NutrientTotals nutrientsForFood({
  required FoodData food,
  required double weightG,
}) {
  return nutrientsPer100gForFood(food) * (weightG / 100.0);
}

String _normalisedFoodLabel(String label) {
  final lower = label.toLowerCase().trim();
  const aliases = {
    'grapes': 'grape',
    'bell pepper': 'pepper',
    'chicken duck': 'chicken',
    'fries': 'french fries',
    'white rice': 'rice',
    'brown rice': 'rice',
    'whole wheat bread': 'bread',
    'yoghurt': 'yogurt',
  };
  return aliases[lower] ?? lower;
}

/// Returns estimated [NutrientTotals] for [weightG] grams of a food item
/// with the given [category].
NutrientTotals estimateNutrientsForFood({
  required String category,
  required double weightG,
}) {
  return categoryNutrientsPer100g(category) * (weightG / 100.0);
}
