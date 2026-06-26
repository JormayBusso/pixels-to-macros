#!/usr/bin/env python3
"""Enrich assets/bundled_recipes.json with computed vitamins & minerals.

The Flutter app's Recipe model already parses per-recipe micronutrient fields
(`vitamin_a_ug`, `vitamin_c_mg`, `vitamin_d_ug`, `vitamin_e_mg`, `vitamin_k_ug`,
`vitamin_b12_ug`, `folate_ug`, `calcium_mg`, `iron_mg`, `magnesium_mg`,
`potassium_mg`, `zinc_mg`, `sodium_mg`) and the recipe detail screen renders a
"Vitamins & minerals" section for any value > 0. The bundled recipes simply did
not carry those fields yet.

This script estimates each recipe's TOTAL micronutrients (across the whole
recipe yield — the app divides by `servings` for display, exactly like macros)
by matching every ingredient name to a curated USDA-derived per-100g nutrient
table and summing `per_100g * grams / 100`.

It is idempotent: re-running recomputes the fields from the ingredient list.

Usage:
    python3 scripts/enrich_recipe_micros.py            # dry-run summary
    python3 scripts/enrich_recipe_micros.py --write    # write back to JSON
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

RECIPES = Path(__file__).resolve().parent.parent / "assets" / "bundled_recipes.json"

# Micronutrient keys in the order the Flutter model expects (snake_case).
# Tuple order for the table values below:
#   vitamin_a_ug, vitamin_c_mg, vitamin_d_ug, vitamin_e_mg, vitamin_k_ug,
#   vitamin_b12_ug, folate_ug, calcium_mg, iron_mg, magnesium_mg,
#   potassium_mg, zinc_mg, sodium_mg
KEYS = [
    "vitamin_a_ug", "vitamin_c_mg", "vitamin_d_ug", "vitamin_e_mg",
    "vitamin_k_ug", "vitamin_b12_ug", "folate_ug", "calcium_mg", "iron_mg",
    "magnesium_mg", "potassium_mg", "zinc_mg", "sodium_mg",
]


def n(*vals: float) -> dict:
    """Build a per-100g nutrient dict from a value tuple in KEYS order."""
    return dict(zip(KEYS, vals))


# Curated per-100g micronutrient table (USDA FoodData Central approximations,
# edible portion). Keys are lowercase keyword fragments matched against
# ingredient names; longer keys are tried first so "sweet potato" beats
# "potato" and "peanut butter" beats "butter".
#                       A     C    D    E     K    B12  Fol   Ca    Fe    Mg    K     Zn   Na
TABLE: dict[str, dict] = {
    # ── Oils & fats ──
    "olive oil":        n(0,   0,   0,  14.4, 60.2, 0,   0,    1,    0.6,  0,    1,    0,   2),
    "vegetable oil":    n(0,   0,   0,  15,   24,   0,   0,    0,    0,    0,    0,    0,   0),
    "sunflower oil":    n(0,   0,   0,  41,   5.4,  0,   0,    0,    0,    0,    0,    0,   0),
    "coconut oil":      n(0,   0,   0,  0.1,  0.6,  0,   0,    1,    0.1,  0,    0,    0,   0),
    "sesame oil":       n(0,   0,   0,  1.4,  13.6, 0,   0,    0,    0,    0,    0,    0,   0),
    "butter":           n(684, 0,   1.5, 2.3, 7,    0.2, 3,    24,   0,    2,    24,   0.1, 643),
    "margarine":        n(817, 0.2, 0,   9,   93,   0.1, 1,    3,    0,    3,    18,   0,   751),
    "lard":             n(0,   0,   1.3, 0.6, 0,    0,   0,    0,    0,    0,    0,    0.1, 0),
    # ── Dairy & eggs ──
    "egg":              n(160, 0,   2,   1.1, 0.3,  0.9, 47,   56,   1.8,  12,   138,  1.3, 142),
    "milk":             n(46,  0,   1.3, 0.1, 0.3,  0.5, 5,    113,  0,    10,   143,  0.4, 43),
    "skimmed milk":     n(61,  0,   0,   0,   0,    0.5, 5,    122,  0,    11,   156,  0.4, 42),
    "cream":            n(411, 0.6, 1.3, 1.1, 3.3, 0.3, 7,    65,   0,    7,    97,   0.3, 38),
    "sour cream":       n(193, 0.9, 0,   0.4, 1.7, 0.4, 11,   101,  0,    10,   125,  0.3, 61),
    "yogurt":           n(27,  0.5, 0,   0,   0.2, 0.4, 7,    110,  0.1,  11,   141,  0.5, 46),
    "greek yogurt":     n(27,  0,   0,   0,   0,    0.5, 7,    100,  0.1,  11,   141,  0.5, 36),
    "cheddar":          n(265, 0,   0.6, 0.7, 2.4, 0.8, 27,   710,  0.7,  28,   98,   3.1, 653),
    "parmesan":         n(207, 0,   0.5, 0.2, 1.7, 1.2, 7,    1184, 0.8,  44,   125,  2.8, 1602),
    "mozzarella":       n(179, 0,   0.4, 0.2, 2.3, 2.3, 7,    505,  0.4,  20,   76,   2.9, 627),
    "feta":             n(125, 0,   0.4, 0.2, 1.8, 1.7, 32,   493,  0.7,  19,   62,   2.9, 1116),
    "cream cheese":     n(308, 0,   0.2, 1.3, 2.9, 0.4, 11,   97,   0.4,  9,    138,  0.5, 321),
    "cheese":           n(265, 0,   0.5, 0.6, 2.4, 0.9, 18,   700,  0.7,  28,   98,   3,   650),
    # ── Poultry, meat, fish ──
    "chicken breast":   n(9,   0,   0.1, 0.3, 0,    0.3, 4,    5,    0.7,  29,   391,  0.8, 65),
    "chicken thigh":    n(20,  0,   0.1, 0.3, 2.6, 0.6, 6,    8,    0.9,  22,   230,  1.5, 86),
    "chicken":          n(16,  0,   0.1, 0.3, 1.5, 0.3, 5,    11,   0.9,  25,   256,  1,   82),
    "turkey":           n(0,   0,   0.3, 0.1, 0,    1.2, 7,    13,   1.2,  24,   239,  1.7, 103),
    "beef":             n(0,   0,   0.1, 0.4, 1.5, 2.6, 6,    18,   2.6,  21,   318,  4.8, 72),
    "ground beef":      n(0,   0,   0.1, 0.4, 1.6, 2.5, 7,    18,   2.4,  19,   270,  4.6, 75),
    "steak":            n(0,   0,   0.1, 0.4, 1.5, 2.6, 6,    18,   2.6,  21,   318,  4.8, 55),
    "pork":             n(2,   0.7, 0.7, 0.2, 0,    0.7, 0,    19,   0.9,  28,   423,  1.9, 62),
    "bacon":            n(11,  0,   0.4, 0.4, 0,    0.7, 1,    6,    0.6,  19,   304,  2,   1717),
    "ham":              n(0,   0,   0.6, 0.2, 0,    0.6, 3,    7,    0.9,  18,   287,  1.9, 1203),
    "sausage":          n(0,   1.2, 0.5, 0.2, 1.5, 1,   3,    18,   1.3,  17,   258,  1.9, 760),
    "lamb":             n(0,   0,   0.1, 0.2, 0,    2.6, 18,   17,   1.6,  23,   310,  3.4, 72),
    "salmon":           n(58,  0,   11,  3.5, 0.5, 3.2, 26,   12,   0.8,  29,   363,  0.6, 59),
    "tuna":             n(655, 0,   1.7, 1,   0.1, 9.4, 2,    8,    1,    50,   252,  0.6, 39),
    "cod":              n(12,  1,   0.9, 0.6, 0.1, 0.9, 7,    16,   0.4,  32,   413,  0.5, 54),
    "white fish":       n(15,  1,   1,   0.6, 0.1, 1.5, 8,    20,   0.4,  30,   400,  0.5, 70),
    "fish":             n(30,  0,   5,   1.2, 0.1, 2.5, 12,   15,   0.5,  30,   380,  0.5, 60),
    "prawn":            n(54,  0,   0.1, 1.1, 0.3, 1.1, 18,   70,   0.5,  39,   259,  1.6, 566),
    "shrimp":           n(54,  0,   0.1, 1.1, 0.3, 1.1, 18,   70,   0.5,  39,   259,  1.6, 566),
    "mussels":          n(48,  8,   0,   0,   0,   24,  76,   33,   6.7,  37,   320,  2.7, 286),
    # ── Legumes, tofu, nuts, seeds ──
    "tofu":             n(0,   0.1, 0,   0,   2.4, 0,   15,   350,  5.4,  30,   121,  0.8, 7),
    "chickpeas":        n(1,   1.3, 0,   0.4, 4,   0,   172,  49,   2.9,  48,   291,  1.5, 24),
    "lentils":          n(1,   1.5, 0,   0.1, 1.7, 0,   181,  19,   3.3,  36,   369,  1.3, 2),
    "black beans":      n(0,   0,   0,   0.9, 5.6, 0,   149,  27,   2.1,  70,   355,  1.1, 1),
    "kidney beans":     n(0,   1.2, 0,   0,   8.4, 0,   130,  35,   2.9,  45,   405,  1,   1),
    "white beans":      n(0,   0,   0,   0,   5.6, 0,   140,  90,   3.7,  53,   561,  1.4, 6),
    "beans":            n(0,   1,   0,   0.3, 6,   0,   140,  40,   2.5,  50,   400,  1.1, 4),
    "peas":             n(38,  40,  0,   0.1, 24.8, 0,  65,   25,   1.5,  33,   244,  1.2, 5),
    "edamame":          n(15,  6.1, 0,   0.7, 26.7, 0,  311,  63,   2.3,  64,   436,  1.3, 6),
    "peanut butter":    n(0,   0,   0,   9,   0.3, 0,   87,   49,   1.9,  168,  649,  2.5, 426),
    "peanut":           n(0,   0,   0,   8.3, 0,   0,   240,  92,   4.6,  168,  705,  3.3, 18),
    "almond":           n(0,   0,   0,   25.6, 0,  0,   44,   269,  3.7,  270,  733,  3.1, 1),
    "walnut":           n(1,   1.3, 0,   0.7, 2.7, 0,   98,   98,   2.9,  158,  441,  3.1, 2),
    "cashew":           n(0,   0.5, 0,   0.9, 34.1, 0,  25,   37,   6.7,  292,  660,  5.8, 12),
    "pecan":            n(3,   1.1, 0,   1.4, 3.5, 0,   22,   70,   2.5,  121,  410,  4.5, 0),
    "pistachio":        n(26,  5.6, 0,   2.9, 0,   0,   51,   105,  3.9,  121,  1025, 2.2, 1),
    "hazelnut":         n(1,   6.3, 0,   15,  14.2, 0,  113,  114,  4.7,  163,  680,  2.5, 0),
    "chia":             n(3,   1.6, 0,   0.5, 0,   0,   49,   631,  7.7,  335,  407,  4.6, 16),
    "flax":             n(0,   0.6, 0,   0.3, 4.3, 0,   87,   255,  5.7,  392,  813,  4.3, 30),
    "sunflower seed":   n(3,   1.4, 0,   35,  0,   0,   227,  78,   5.3,  325,  645,  5,   9),
    "pumpkin seed":     n(1,   1.9, 0,   2.2, 7.3, 0,   58,   46,   8.8,  592,  809,  7.8, 7),
    "sesame":           n(0,   0,   0,   0.2, 0,   0,   97,   975,  14.6, 351,  468,  7.8, 11),
    # ── Grains, bread, pasta ──
    "rice":             n(0,   0,   0,   0,   0,   0,   3,    10,   1.2,  12,   35,   0.5, 1),
    "brown rice":       n(0,   0,   0,   0.2, 0.6, 0,  4,    10,   0.6,  44,   86,   0.7, 4),
    "pasta":            n(0,   0,   0,   0.1, 0,   0,   18,   7,    0.5,  18,   44,   0.5, 1),
    "spaghetti":        n(0,   0,   0,   0.1, 0,   0,   18,   7,    0.5,  18,   44,   0.5, 1),
    "noodle":           n(0,   0,   0,   0.1, 0,   0,   18,   9,    1.3,  25,   38,   0.5, 5),
    "bread":            n(0,   0,   0,   0.2, 0.4, 0,  85,   144,  3.6,  26,   115,  1,   491),
    "flour":            n(0,   0,   0,   0.1, 0.3, 0,  26,   15,   1.2,  22,   107,  0.7, 2),
    "oats":             n(0,   0,   0,   0.4, 2,   0,  56,   54,   4.7,  177,  429,  4,   2),
    "couscous":         n(0,   0,   0,   0.2, 0,   0,  20,   24,   1.1,  44,   166,  0.8, 8),
    "quinoa":           n(0,   0,   0,   0.6, 0,   0,  42,   17,   1.5,  64,   172,  1.1, 5),
    "tortilla":         n(0,   0,   0,   0.1, 0,   0,  31,   140,  3.1,  25,   110,  0.6, 400),
    "barley":           n(1,   0,   0,   0,   2.2, 0,  19,   29,   2.5,  79,   280,  2.1, 9),
    "cornflour":        n(0,   0,   0,   0,   0,   0,  0,    2,    0.5,  4,    3,    0.1, 9),
    # ── Vegetables ──
    "onion":            n(0,   7.4, 0,   0,   0.4, 0,  19,   23,   0.2,  10,   146,  0.2, 4),
    "spring onion":     n(50,  18.8, 0,  0.6, 207, 0,  64,   72,   1.5,  20,   276,  0.4, 16),
    "garlic":           n(0,   31.2, 0,  0,   1.7, 0,  3,    181,  1.7,  25,   401,  1.2, 17),
    "leek":             n(83,  12,  0,   0.9, 47,  0,  64,   59,   2.1,  28,   180,  0.1, 20),
    "tomato":           n(42,  14,  0,   0.5, 7.9, 0,  15,   10,   0.3,  11,   237,  0.2, 5),
    "carrot":           n(835, 5.9, 0,   0.7, 13.2, 0, 19,   33,   0.3,  12,   320,  0.2, 69),
    "potato":           n(0,   19.7, 0,  0,   2,   0,  16,   12,   0.8,  23,   421,  0.3, 6),
    "sweet potato":     n(709, 2.4, 0,   0.3, 1.8, 0,  11,   30,   0.6,  25,   337,  0.3, 55),
    "bell pepper":      n(157, 128, 0,   1.6, 4.9, 0,  46,   10,   0.4,  12,   211,  0.3, 4),
    "pepper":           n(157, 128, 0,   1.6, 4.9, 0,  46,   10,   0.4,  12,   211,  0.3, 4),
    "chili":            n(48,  144, 0,   0.7, 14,  0,  23,   14,   1,    23,   322,  0.3, 9),
    "spinach":          n(469, 28,  0,   2,   483, 0,  194,  99,   2.7,  79,   558,  0.5, 79),
    "kale":             n(500, 120, 0,   1.5, 705, 0,  141,  150,  1.5,  47,   491,  0.6, 38),
    "broccoli":         n(31,  89,  0,   0.8, 102, 0,  63,   47,   0.7,  21,   316,  0.4, 33),
    "cauliflower":      n(0,   48,  0,   0.1, 15.5, 0, 57,   22,   0.4,  15,   299,  0.3, 30),
    "cabbage":          n(5,   37,  0,   0.2, 76,  0,  43,   40,   0.5,  12,   170,  0.2, 18),
    "lettuce":          n(370, 9.2, 0,   0.3, 126, 0,  38,   36,   0.9,  13,   194,  0.2, 28),
    "cucumber":         n(5,   2.8, 0,   0,   16.4, 0, 7,    16,   0.3,  13,   147,  0.2, 2),
    "zucchini":         n(10,  17.9, 0,  0.1, 4.3, 0,  24,   16,   0.4,  18,   261,  0.3, 8),
    "courgette":        n(10,  17.9, 0,  0.1, 4.3, 0,  24,   16,   0.4,  18,   261,  0.3, 8),
    "eggplant":         n(1,   2.2, 0,   0.3, 3.5, 0,  22,   9,    0.2,  14,   229,  0.2, 2),
    "aubergine":        n(1,   2.2, 0,   0.3, 3.5, 0,  22,   9,    0.2,  14,   229,  0.2, 2),
    "mushroom":         n(0,   2.1, 0.2, 0,   0,   0,  17,   3,    0.5,  9,    318,  0.5, 5),
    "celery":           n(22,  3.1, 0,   0.3, 29.3, 0, 36,   40,   0.2,  11,   260,  0.1, 80),
    "corn":             n(9,   6.8, 0,   0.1, 0.3, 0,  42,   2,    0.5,  37,   270,  0.5, 15),
    "pumpkin":          n(426, 9,   0,   1.1, 1.1, 0,  16,   21,   0.8,  12,   340,  0.3, 1),
    "beetroot":         n(2,   4.9, 0,   0,   0.2, 0,  109,  16,   0.8,  23,   325,  0.4, 78),
    "asparagus":        n(38,  5.6, 0,   1.1, 41.6, 0, 52,   24,   2.1,  14,   202,  0.5, 2),
    "green bean":       n(35,  12.2, 0,  0.4, 43,  0,  33,   37,   1,    25,   211,  0.2, 6),
    "avocado":          n(7,   10,  0,   2.1, 21,  0,  81,   12,   0.6,  29,   485,  0.6, 7),
    "ginger":           n(0,   5,   0,   0.3, 0.1, 0,  11,   16,   0.6,  43,   415,  0.3, 13),
    # ── Fruit ──
    "apple":            n(3,   4.6, 0,   0.2, 2.2, 0,  3,    6,    0.1,  5,    107,  0,   1),
    "banana":           n(3,   8.7, 0,   0.1, 0.5, 0,  20,   5,    0.3,  27,   358,  0.2, 1),
    "orange":           n(11,  53,  0,   0.2, 0,   0,  30,   40,   0.1,  10,   181,  0.1, 0),
    "lemon":            n(1,   53,  0,   0.2, 0,   0,  11,   26,   0.6,  8,    138,  0.1, 2),
    "lime":             n(2,   29,  0,   0.2, 0.6, 0,  8,    33,   0.6,  6,    102,  0.1, 2),
    "strawberry":       n(1,   59,  0,   0.3, 2.2, 0,  24,   16,   0.4,  13,   153,  0.1, 1),
    "blueberry":        n(3,   9.7, 0,   0.6, 19.3, 0, 6,    6,    0.3,  6,    77,   0.2, 1),
    "raspberry":        n(2,   26,  0,   0.9, 7.8, 0,  21,   25,   0.7,  22,   151,  0.4, 1),
    "grape":            n(3,   3.2, 0,   0.2, 14.6, 0, 2,    10,   0.4,  7,    191,  0.1, 2),
    "mango":            n(54,  36,  0,   0.9, 4.2, 0,  43,   11,   0.2,  10,   168,  0.1, 1),
    "pineapple":        n(3,   48,  0,   0,   0.1, 0,  18,   13,   0.3,  12,   109,  0.1, 1),
    "peach":            n(16,  6.6, 0,   0.7, 2.6, 0,  4,    6,    0.3,  9,    190,  0.2, 0),
    "pear":             n(1,   4.3, 0,   0.1, 4.4, 0,  7,    9,    0.2,  7,    116,  0.1, 1),
    "raisin":           n(0,   2.3, 0,   0.1, 3.5, 0,  5,    50,   1.9,  32,   749,  0.2, 11),
    "date":             n(0,   0,   0,   0,   2.7, 0,  15,   64,   0.9,  54,   696,  0.4, 1),
    "coconut":          n(0,   3.3, 0,   0.2, 0.2, 0,  26,   14,   2.4,  32,   356,  1.1, 20),
    # ── Condiments, sweeteners, misc ──
    "sugar":            n(0,   0,   0,   0,   0,   0,  0,    1,    0.1,  0,    2,    0,   1),
    "honey":            n(0,   0.5, 0,   0,   0,   0,  2,    6,    0.4,  2,    52,   0.2, 4),
    "maple syrup":      n(0,   0,   0,   0,   0,   0,  0,    102,  0.1,  21,   212,  1.5, 12),
    "chocolate":        n(2,   0,   0,   0.6, 7.3, 0,  12,   73,   8,    228,  715,  3.3, 24),
    "cocoa":            n(0,   0,   0,   0.1, 2.5, 0,  32,   128,  13.9, 499,  1524, 6.8, 21),
    "soy sauce":        n(0,   0,   0,   0,   0,   0,  14,   20,   1.5,  40,   212,  0.4, 5493),
    "tomato sauce":     n(24,  9.6, 0,   1.4, 2.9, 0,  9,    14,   1,    18,   297,  0.2, 421),
    "tomato paste":     n(75,  21,  0,   4.3, 8.6, 0,  21,   36,   2.9,  42,   1014, 0.6, 59),
    "stock":            n(0,   0,   0,   0,   0,   0,  2,    9,    0.3,  3,    51,   0,   363),
    "vinegar":          n(0,   0,   0,   0,   0,   0,  0,    6,    0.2,  2,    73,   0,   5),
    "wine":             n(0,   0,   0,   0,   0,   0,  1,    8,    0.5,  10,   71,   0.1, 4),
    "salt":             n(0,   0,   0,   0,   0,   0,  0,    24,   0.3,  1,    8,    0.1, 38758),
    "parsley":          n(421, 133, 0,   0.8, 1640, 0, 152,  138,  6.2,  50,   554,  1.1, 56),
    "coriander":        n(337, 27,  0,   2.5, 310, 0,  62,   67,   1.8,  26,   521,  0.5, 46),
    "cilantro":         n(337, 27,  0,   2.5, 310, 0,  62,   67,   1.8,  26,   521,  0.5, 46),
    "basil":            n(264, 18,  0,   0.8, 415, 0,  68,   177,  3.2,  64,   295,  0.8, 4),
    "cumin":            n(64,  7.7, 0,   3.3, 5.4, 0,  10,   931,  66.4, 366,  1788, 4.8, 168),
    "paprika":          n(2463, 0.9, 0,  29.1, 80.3, 0, 49,  229,  21.1, 178,  2280, 4.3, 68),
    "cinnamon":         n(15,  3.8, 0,   2.3, 31.2, 0, 6,    1002, 8.3,  60,   431,  1.8, 10),
    "ginger ground":    n(2,   0.7, 0,   0,   0.8, 0,  13,   114,  19.8, 214,  1320, 3.6, 27),
    "mustard":          n(4,   1.5, 0,   0,   1.5, 0,  7,    58,   1.5,  48,   138,  0.6, 1135),
    "mayonnaise":       n(30,  0,   0,   3.3, 73,  0.4, 6,   8,    0.2,  1,    20,   0.1, 635),
    "ricotta":          n(120, 0,   0.1, 0.1, 1.1, 0.3, 12, 207,  0.4,  11,   105,  1.2, 84),
    "capers":           n(7,   4.3, 0,   0.9, 24.6, 0, 23,   40,   1.7,  33,   40,   0.3, 2348),
    "oregano":          n(85,  2.3, 0,   18.3, 622, 0,  237, 1597, 36.8, 270,  1260, 2.7, 25),
    "mint":             n(212, 31.8, 0,  0,   0,   0,  114,  243,  5.1,  80,   569,  1.1, 31),
    "arugula":          n(119, 15,  0,   0.4, 109, 0,  97,   160,  1.5,  47,   369,  0.5, 27),
    "rocket":           n(119, 15,  0,   0.4, 109, 0,  97,   160,  1.5,  47,   369,  0.5, 27),
    "baking powder":    n(0,   0,   0,   0,   0,   0,  0,    2000, 5,    30,   30,   0.1, 9000),
    "black pepper":     n(27,  0,   0,   1,   163, 0,  17,   443,  9.7,  171,  1329, 1.2, 20),
    "water":            n(0,   0,   0,   0,   0,   0,  0,    0,    0,    0,    0,    0,   0),
    "rapeseed oil":     n(0,   0,   0,   17.5, 71.3, 0, 0,   0,    0,    0,    0,    0,   0),
}

# Multilingual / variant synonyms → canonical English table key. The app's
# bundled recipes include EN/PL/NL/ES/DE ingredient names, so we map common
# localized terms to the same per-100g nutrient profile.
SYNONYMS: dict[str, str] = {
    # olive oil
    "olijfolie": "olive oil", "oliven": "olive oil", "oliwa": "olive oil",
    "oliwy": "olive oil", "aceite": "olive oil",
    # other oils
    "zonnebloemolie": "sunflower oil", "arachideolie": "peanut",
    "koolzaadolie": "rapeseed oil", "rapsol": "rapeseed oil",
    # garlic
    "knoflook": "garlic", "knoblauch": "garlic", "czosnek": "garlic",
    "czosnku": "garlic", "ajo": "garlic",
    # egg
    "ei": "egg", "eier": "egg", "eieren": "egg", "jajka": "egg",
    "jajko": "egg", "huevo": "egg", "scharreleieren": "egg",
    # salt / pepper (spice)
    "salz": "salt", "zout": "salt", "sol": "salt", "soli": "salt",
    "sal": "salt", "pfeffer": "black pepper", "peper": "black pepper",
    "pieprz": "black pepper", "pimienta": "black pepper",
    # sugar
    "zucker": "sugar", "suiker": "sugar", "kristalsuiker": "sugar",
    "cukier": "sugar", "cukru": "sugar", "azucar": "sugar",
    # flour
    "mehl": "flour", "bloem": "flour", "tarwebloem": "flour",
    "harina": "flour",
    # milk
    "milch": "milk", "melk": "milk", "mleko": "milk", "mleka": "milk",
    "leche": "milk",
    # butter / cream
    "boter": "butter", "roomboter": "butter", "maslo": "butter",
    "masla": "butter", "mantequilla": "butter", "sahne": "cream",
    "slagroom": "cream", "room": "cream", "nata": "cream",
    "smietana": "cream",
    # onion
    "zwiebel": "onion", "ui": "onion", "uien": "onion", "cebula": "onion",
    "cebuli": "onion", "cebolla": "onion",
    # lemon / lime
    "citroen": "lemon", "zitrone": "lemon", "cytryna": "lemon",
    "cytryny": "lemon", "limon": "lemon", "limoen": "lime",
    "limette": "lime", "limonka": "lime",
    # cucumber / avocado / tomato / carrot
    "komkommer": "cucumber", "gurke": "cucumber", "ogorek": "cucumber",
    "pepino": "cucumber", "awokado": "avocado", "tomaten": "tomato",
    "pomidor": "tomato", "tomate": "tomato", "wortel": "carrot",
    "mohre": "carrot", "karotte": "carrot", "marchew": "carrot",
    "zanahoria": "carrot", "tomatenmark": "tomato paste",
    "tomatenpuree": "tomato paste",
    # herbs
    "peterselie": "parsley", "petersilie": "parsley",
    "pietruszka": "parsley", "perejil": "parsley",
    "basilicum": "basil", "basilikum": "basil", "bazylia": "basil",
    "albahaca": "basil", "koriander": "coriander", "kolendra": "coriander",
    "munt": "mint", "minze": "mint", "mieta": "mint", "menta": "mint",
    "rucola": "arugula", "kaneel": "cinnamon", "zimt": "cinnamon",
    "cynamon": "cinnamon", "canela": "cinnamon",
    # condiments
    "mosterd": "mustard", "senf": "mustard", "musztarda": "mustard",
    "mostaza": "mustard", "mayonaise": "mayonnaise", "majonez": "mayonnaise",
    "majonezu": "mayonnaise",
    # water / variants
    "wasser": "water", "woda": "water", "wody": "water",
    "kraanwater": "water", "agua": "water", "chilli": "chili",
}

for _syn, _canon in SYNONYMS.items():
    if _canon in TABLE:
        TABLE[_syn] = TABLE[_canon]

# Short/ambiguous keys must match as a WHOLE word (no inflectional suffix) to
# avoid false positives, e.g. "sal"→"salade"/"salami", "sol"→"sole" (fish),
# "ui"→"uitsmijter". Salt's extreme sodium makes such mismatches very harmful.
EXACT_ONLY = {"sal", "sol", "soli", "ui", "ei", "room", "ajo", "nata", "mint"}

# Pre-sort keys by length (descending) so multi-word keys win over short ones.
SORTED_KEYS = sorted(TABLE.keys(), key=len, reverse=True)

# Records the keyword matched by the most recent match_ingredient() call so the
# caller can apply a key-specific gram cap.
LAST_MATCH_KEY: list[str | None] = [None]

# Maximum grams a single ingredient may contribute, to neutralise mis-parsed
# source amounts. Seasonings/spices are used in tiny amounts; a generous
# default covers legitimately large mains (e.g. 800g potatoes).
DEFAULT_GRAM_CAP = 1200.0
GRAM_CAP: dict[str, float] = {
    "salt": 15, "sal": 15, "sol": 15, "soli": 15, "salz": 15, "zout": 15,
    "black pepper": 15, "pfeffer": 15, "peper": 15, "pieprz": 15,
    "pimienta": 15, "paprika": 20, "cumin": 20, "cinnamon": 20,
    "ginger ground": 20, "baking powder": 20, "cocoa": 100,
    "parsley": 40, "peterselie": 40, "petersilie": 40, "pietruszka": 40,
    "perejil": 40, "basil": 40, "basilicum": 40, "basilikum": 40,
    "bazylia": 40, "albahaca": 40, "coriander": 40, "koriander": 40,
    "kolendra": 40, "cilantro": 40, "oregano": 30, "mint": 40, "menta": 40,
    "minze": 40, "mieta": 40, "chili": 60, "chilli": 60, "ginger": 60,
}

# Words to strip from ingredient names before matching (prep / packaging noise).
PREP_NOISE = re.compile(
    r"\b(finely|roughly|freshly|coarsely|thinly|chopped|sliced|diced|minced|"
    r"grated|peeled|crushed|ground|cut|into|cubes|chunks|pieces|strips|"
    r"to\s+serve|to\s+taste|optional|fresh|dried|frozen|canned|tinned|cooked|"
    r"raw|large|medium|small|ripe|boneless|skinless|extra|plus|halved|"
    r"quartered|drained|rinsed|trimmed|of|a|an|the|for|and|or)\b"
)


def match_ingredient(name: str) -> dict | None:
    """Return the per-100g nutrient dict for the best keyword match, or None."""
    text = name.lower()
    text = re.sub(r"\([^)]*\)", " ", text)        # drop parentheticals
    text = re.sub(r"[^a-z\s]", " ", text)          # keep letters only
    text = PREP_NOISE.sub(" ", text)
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return None
    for key in SORTED_KEYS:
        # Match the keyword at a word start, allowing inflectional suffixes
        # (plurals like egg→eggs, tomato→tomatoes) since the text is a-z only.
        # EXACT_ONLY keys require a whole-word match (no suffix).
        suffix = "" if key in EXACT_ONLY else "[a-z]*"
        if re.search(rf"(?:^|\s){re.escape(key)}{suffix}(?:\s|$)", text):
            LAST_MATCH_KEY[0] = key
            return TABLE[key]
    return None


# Rough gram fallbacks for ingredients that have no `grams` but a parseable
# unit/count, so they still contribute to the micronutrient totals.
UNIT_GRAMS = {
    "clove": 5, "cloves": 5, "tsp": 5, "teaspoon": 5, "teaspoons": 5,
    "tbsp": 15, "tablespoon": 15, "tablespoons": 15, "pinch": 0.5,
    "handful": 25, "slice": 25, "slices": 25, "sprig": 2, "sprigs": 2,
    "stick": 60, "sticks": 60, "can": 400, "cup": 200, "cups": 200,
}


def estimate_grams(amount: str) -> float:
    """Best-effort grams from an amount string when `grams` is missing/zero."""
    a = amount.lower()
    m = re.search(r"(\d+(?:\.\d+)?)\s*(g|grams?|kg|ml|l)\b", a)
    if m:
        val = float(m.group(1))
        unit = m.group(2)
        if unit == "kg":
            return val * 1000
        if unit == "l":
            return val * 1000
        return val  # g / ml / grams
    for unit, grams in UNIT_GRAMS.items():
        if re.search(rf"\b{unit}\b", a):
            count = re.search(r"(\d+(?:\.\d+)?)", a)
            mult = float(count.group(1)) if count else 1.0
            return mult * grams
    count = re.search(r"^(\d+(?:\.\d+)?)\b", a.strip())
    if count:
        return float(count.group(1)) * 80  # bare count → ~one medium item
    return 0.0


def compute_recipe_micros(recipe: dict) -> tuple[dict, int, int]:
    """Return (totals dict in KEYS order, matched_count, ingredient_count)."""
    totals = {k: 0.0 for k in KEYS}
    matched = 0
    ingredients = recipe.get("ingredients") or []
    for ing in ingredients:
        grams = float(ing.get("grams") or 0)
        if grams <= 0:
            grams = estimate_grams(str(ing.get("amount") or ""))
        if grams <= 0:
            continue
        nutr = match_ingredient(str(ing.get("name") or ""))
        if nutr is None:
            continue
        matched += 1
        key = LAST_MATCH_KEY[0]
        # Clamp implausible source grams (some scraped amounts mis-parse, e.g.
        # "a pinch of salt" → 200g, "60g parmesan plus extra" → 2500g) so a
        # single bad value can't dominate the recipe totals.
        grams = min(grams, GRAM_CAP.get(key, DEFAULT_GRAM_CAP))
        factor = grams / 100.0
        for k in KEYS:
            totals[k] += nutr[k] * factor
    return totals, matched, len(ingredients)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true",
                    help="write the enriched recipes back to the JSON file")
    args = ap.parse_args()

    data = json.loads(RECIPES.read_text())
    total_ing = matched_ing = recipes_with_micros = 0

    for recipe in data:
        totals, matched, n_ing = compute_recipe_micros(recipe)
        total_ing += n_ing
        matched_ing += matched
        if any(v > 0 for v in totals.values()):
            recipes_with_micros += 1
        for k in KEYS:
            # Round to a sensible precision; keep small values meaningful.
            recipe[k] = round(totals[k], 2)

    print(f"recipes:                 {len(data)}")
    print(f"recipes with micros >0:  {recipes_with_micros}")
    print(f"ingredients total:       {total_ing}")
    print(f"ingredients matched:     {matched_ing} "
          f"({100 * matched_ing / max(total_ing, 1):.1f}%)")

    if args.write:
        RECIPES.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        )
        print(f"\nWROTE {RECIPES}")
    else:
        print("\n(dry run — pass --write to save)")


if __name__ == "__main__":
    main()
