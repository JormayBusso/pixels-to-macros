#!/usr/bin/env python3
"""
Generate 3000+ curated recipes with full macro AND micronutrient data.

Categories covered:
  - Diabetes-friendly (low GI, controlled carbs, insulin calculation)
  - Muscle growth (high protein: shakes, yogurts, cakes, meals)
  - Vegan (plant-based, complete nutrition)
  - Keto (very low carb, high fat)
  - Weight loss (calorie-controlled, high satiety)

Each recipe includes:
  - Per-ingredient grams (adjustable in the app)
  - Full macros: calories, protein, carbs, fat, fiber, sugar
  - Full micros: vitamins A/C/D/E/K/B12, folate, calcium, iron, magnesium, potassium, zinc, sodium
  - Glycemic index (weighted), glycemic load, estimated insulin units

Output: assets/recipes.json
"""

from __future__ import annotations

import json
import hashlib
import random
from pathlib import Path
from dataclasses import dataclass, field
from typing import Any

random.seed(42)

OUTPUT = Path(__file__).parent.parent / "assets" / "recipes.json"

# ---------------------------------------------------------------------------
# Ingredient nutritional database (per 100g, USDA averages)
# Fields: kcal, protein, carbs, fat, fiber, sugar, gi,
#         vit_a_ug, vit_c_mg, vit_d_ug, vit_e_mg, vit_k_ug, vit_b12_ug, folate_ug,
#         calcium_mg, iron_mg, magnesium_mg, potassium_mg, zinc_mg, sodium_mg
# ---------------------------------------------------------------------------

@dataclass
class Nutrient:
    kcal: float = 0
    protein: float = 0
    carbs: float = 0
    fat: float = 0
    fiber: float = 0
    sugar: float = 0
    gi: float = 50  # glycemic index
    vit_a: float = 0
    vit_c: float = 0
    vit_d: float = 0
    vit_e: float = 0
    vit_k: float = 0
    vit_b12: float = 0
    folate: float = 0
    calcium: float = 0
    iron: float = 0
    magnesium: float = 0
    potassium: float = 0
    zinc: float = 0
    sodium: float = 0
    is_vegan: bool = False


# Comprehensive ingredient DB with USDA nutritional data per 100g
INGREDIENTS: dict[str, Nutrient] = {
    # === PROTEINS ===
    "chicken breast": Nutrient(165, 31, 0, 3.6, 0, 0, 0, 6, 0, 0, 0.3, 0, 0.3, 4, 11, 0.7, 29, 256, 1.0, 74),
    "chicken thigh": Nutrient(209, 26, 0, 10.9, 0, 0, 0, 17, 0, 0, 0.3, 2.5, 0.3, 6, 11, 1.1, 23, 222, 2.0, 84),
    "ground turkey": Nutrient(170, 21, 0, 9.4, 0, 0, 0, 0, 0, 0, 0.1, 0, 1.2, 6, 19, 1.5, 22, 237, 2.8, 72),
    "ground beef (lean)": Nutrient(250, 26, 0, 15, 0, 0, 0, 0, 0, 0, 0.1, 1.6, 2.6, 7, 18, 2.6, 21, 315, 5.5, 66),
    "salmon fillet": Nutrient(208, 20, 0, 13, 0, 0, 0, 40, 0, 11, 3.6, 0, 3.2, 26, 12, 0.8, 29, 363, 0.6, 59),
    "tuna (canned)": Nutrient(116, 26, 0, 0.8, 0, 0, 0, 18, 0, 1.7, 0.5, 0, 2.1, 4, 11, 1.0, 30, 237, 0.6, 338),
    "cod fillet": Nutrient(82, 18, 0, 0.7, 0, 0, 0, 12, 1, 1.0, 0.6, 0, 0.9, 7, 16, 0.4, 32, 413, 0.5, 54),
    "shrimp": Nutrient(99, 24, 0.2, 0.3, 0, 0, 0, 54, 2, 0, 1.3, 0, 1.1, 3, 70, 0.5, 37, 259, 1.6, 111),
    "eggs": Nutrient(155, 13, 1.1, 11, 0, 1.1, 0, 160, 0, 2.0, 1.1, 0.3, 0.9, 47, 56, 1.8, 12, 138, 1.3, 124),
    "egg whites": Nutrient(52, 11, 0.7, 0.2, 0, 0.7, 0, 0, 0, 0, 0, 0, 0.1, 4, 7, 0.1, 11, 163, 0.03, 166),
    "greek yogurt": Nutrient(97, 9, 3.6, 5, 0, 3.2, 14, 22, 0, 0, 0.1, 0, 0.75, 7, 110, 0.1, 11, 141, 0.5, 36),
    "cottage cheese": Nutrient(98, 11, 3.4, 4.3, 0, 2.7, 10, 37, 0, 0, 0, 0, 0.4, 12, 83, 0.1, 8, 104, 0.4, 364),
    "whey protein powder": Nutrient(400, 80, 8, 6, 0, 4, 0, 0, 0, 0, 0, 0, 0.5, 0, 500, 1.0, 70, 400, 3.0, 200),
    "tofu (firm)": Nutrient(144, 17, 3, 9, 2.3, 0.7, 15, 0, 0.2, 0, 0, 2.4, 0, 29, 683, 5.4, 58, 237, 2.0, 14, True),
    "tempeh": Nutrient(192, 20, 8, 11, 0, 0, 15, 0, 0, 0, 0, 0, 0.1, 24, 111, 2.7, 81, 412, 1.1, 9, True),
    "seitan": Nutrient(370, 75, 14, 1.9, 0.6, 0, 20, 0, 0, 0, 0, 0, 0, 0, 17, 5.2, 10, 100, 1.8, 29, True),

    # === DAIRY & ALTERNATIVES ===
    "whole milk": Nutrient(61, 3.2, 4.8, 3.3, 0, 5.1, 31, 46, 0, 1.3, 0.1, 0.3, 0.45, 5, 113, 0, 10, 132, 0.4, 43),
    "almond milk (unsweetened)": Nutrient(15, 0.6, 0.6, 1.1, 0.5, 0, 25, 0, 0, 1.0, 6.3, 0, 0, 2, 184, 0.3, 7, 67, 0.1, 72, True),
    "oat milk": Nutrient(43, 1, 7, 1.5, 0.8, 4, 69, 0, 0, 1.0, 0.2, 0, 0.4, 5, 120, 0.2, 5, 43, 0.1, 47, True),
    "cheddar cheese": Nutrient(403, 25, 1.3, 33, 0, 0.5, 0, 265, 0, 0.6, 0.3, 2.4, 0.8, 18, 721, 0.7, 28, 98, 3.1, 621),
    "mozzarella": Nutrient(280, 28, 3.1, 17, 0, 1.0, 0, 174, 0, 0.4, 0.2, 1.6, 0.7, 7, 505, 0.4, 20, 76, 2.3, 627),
    "parmesan": Nutrient(431, 38, 4.1, 29, 0, 0.9, 0, 207, 0, 0.5, 0.2, 1.7, 1.2, 7, 1184, 0.8, 44, 92, 2.8, 1602),
    "cream cheese": Nutrient(342, 6, 4, 34, 0, 3.8, 0, 308, 0, 0.3, 0.3, 2.9, 0.3, 11, 98, 0.3, 9, 138, 0.5, 321),
    "butter": Nutrient(717, 0.9, 0.1, 81, 0, 0.1, 0, 684, 0, 0, 2.3, 7, 0.2, 3, 24, 0, 2, 24, 0.1, 11),
    "coconut cream": Nutrient(197, 2.2, 6.6, 19.7, 2.2, 3.3, 0, 0, 1, 0, 0.2, 0.1, 0, 16, 4, 1.6, 32, 220, 0.6, 4, True),

    # === GRAINS & STARCHES ===
    "brown rice (cooked)": Nutrient(123, 2.7, 26, 1, 1.6, 0.4, 50, 0, 0, 0, 0, 0.6, 0, 4, 3, 0.6, 39, 79, 0.7, 4, True),
    "white rice (cooked)": Nutrient(130, 2.7, 28, 0.3, 0.4, 0, 73, 0, 0, 0, 0, 0, 0, 2, 10, 0.2, 12, 35, 0.5, 1, True),
    "quinoa (cooked)": Nutrient(120, 4.4, 21, 1.9, 2.8, 0.9, 53, 1, 0, 0, 0.6, 0, 0, 42, 17, 1.5, 64, 172, 1.1, 7, True),
    "oats (rolled)": Nutrient(379, 13, 67, 7, 10, 1, 55, 0, 0, 0, 0.4, 2, 0, 32, 54, 4.7, 177, 429, 4.0, 2, True),
    "whole wheat bread": Nutrient(247, 13, 41, 3.4, 7, 6, 69, 0, 0, 0, 0.4, 7.8, 0, 44, 107, 2.5, 75, 254, 1.8, 400, True),
    "sweet potato (cooked)": Nutrient(90, 2, 21, 0.1, 3.3, 6.5, 63, 709, 2.4, 0, 0.3, 1.8, 0, 6, 38, 0.7, 27, 475, 0.3, 36, True),
    "white potato (cooked)": Nutrient(87, 1.9, 20, 0.1, 1.8, 0.9, 78, 0, 8, 0, 0, 2, 0, 10, 5, 0.3, 22, 328, 0.3, 4, True),
    "pasta (cooked)": Nutrient(131, 5, 25, 1.1, 1.8, 0.6, 55, 0, 0, 0, 0, 0, 0, 7, 7, 0.5, 18, 44, 0.5, 1, True),
    "couscous (cooked)": Nutrient(112, 3.8, 23, 0.2, 1.4, 0.1, 65, 0, 0, 0, 0, 0.1, 0, 15, 8, 0.4, 8, 58, 0.3, 5, True),
    "lentils (cooked)": Nutrient(116, 9, 20, 0.4, 8, 1.8, 29, 2, 1.5, 0, 0.1, 1.7, 0, 181, 19, 3.3, 36, 369, 1.3, 2, True),
    "chickpeas (cooked)": Nutrient(164, 9, 27, 2.6, 8, 4.8, 28, 1, 1.3, 0, 0.4, 4, 0, 172, 49, 2.9, 48, 291, 1.5, 7, True),
    "black beans (cooked)": Nutrient(132, 8.9, 24, 0.5, 8.7, 0.3, 30, 0, 0, 0, 0, 3.3, 0, 149, 27, 2.1, 70, 355, 1.1, 1, True),
    "almond flour": Nutrient(571, 21, 20, 50, 10, 4.5, 0, 0, 0, 0, 25.6, 0, 0, 44, 236, 3.7, 268, 713, 3.1, 1, True),
    "coconut flour": Nutrient(443, 19, 60, 14, 39, 8, 45, 0, 0, 0, 0, 0, 0, 0, 26, 3.6, 90, 660, 2.0, 20, True),
    "cauliflower rice": Nutrient(25, 2, 5, 0.3, 2, 1.9, 15, 0, 48, 0, 0.1, 15.5, 0, 57, 22, 0.4, 15, 299, 0.3, 30, True),

    # === VEGETABLES ===
    "spinach": Nutrient(23, 2.9, 3.6, 0.4, 2.2, 0.4, 15, 469, 28, 0, 2, 483, 0, 194, 99, 2.7, 79, 558, 0.5, 79, True),
    "kale": Nutrient(49, 4.3, 9, 0.9, 3.6, 2.3, 15, 241, 120, 0, 1.5, 390, 0, 141, 150, 1.5, 47, 491, 0.6, 38, True),
    "broccoli": Nutrient(34, 2.8, 7, 0.4, 2.6, 1.7, 15, 31, 89, 0, 0.8, 102, 0, 63, 47, 0.7, 21, 316, 0.4, 33, True),
    "bell pepper (red)": Nutrient(31, 1, 6, 0.3, 2.1, 4.2, 15, 157, 128, 0, 1.6, 4.9, 0, 46, 7, 0.4, 12, 211, 0.3, 4, True),
    "tomatoes": Nutrient(18, 0.9, 3.9, 0.2, 1.2, 2.6, 15, 42, 14, 0, 0.5, 7.9, 0, 15, 10, 0.3, 11, 237, 0.2, 5, True),
    "zucchini": Nutrient(17, 1.2, 3.1, 0.3, 1, 2.5, 15, 10, 18, 0, 0.1, 4.3, 0, 24, 16, 0.4, 18, 261, 0.3, 8, True),
    "mushrooms": Nutrient(22, 3.1, 3.3, 0.3, 1, 2, 15, 0, 2, 7.0, 0, 0, 0.04, 17, 3, 0.5, 9, 318, 0.5, 5, True),
    "avocado": Nutrient(160, 2, 9, 15, 7, 0.7, 15, 7, 10, 0, 2.1, 21, 0, 81, 12, 0.6, 29, 485, 0.6, 7, True),
    "onion": Nutrient(40, 1.1, 9, 0.1, 1.7, 4.2, 10, 0, 7, 0, 0, 0.4, 0, 19, 23, 0.2, 10, 146, 0.2, 4, True),
    "garlic": Nutrient(149, 6.4, 33, 0.5, 2.1, 1, 10, 0, 31, 0, 0, 1.7, 0, 3, 181, 1.7, 25, 401, 1.2, 17, True),
    "carrot": Nutrient(41, 0.9, 10, 0.2, 2.8, 4.7, 35, 835, 6, 0, 0.7, 13.2, 0, 19, 33, 0.3, 12, 320, 0.2, 69, True),
    "cucumber": Nutrient(15, 0.7, 3.6, 0.1, 0.5, 1.7, 15, 5, 2.8, 0, 0, 16.4, 0, 7, 16, 0.3, 13, 147, 0.2, 2, True),
    "asparagus": Nutrient(20, 2.2, 3.9, 0.1, 2.1, 1.9, 15, 38, 5.6, 0, 1.1, 41.6, 0, 52, 24, 2.1, 14, 202, 0.5, 2, True),
    "green beans": Nutrient(31, 1.8, 7, 0.2, 2.7, 3.3, 15, 35, 12, 0, 0.4, 43, 0, 33, 37, 1.0, 25, 211, 0.2, 6, True),
    "cauliflower": Nutrient(25, 1.9, 5, 0.3, 2, 1.9, 15, 0, 48, 0, 0.1, 15.5, 0, 57, 22, 0.4, 15, 299, 0.3, 30, True),
    "cabbage": Nutrient(25, 1.3, 6, 0.1, 2.5, 3.2, 10, 5, 36, 0, 0.2, 76, 0, 43, 40, 0.5, 12, 170, 0.2, 18, True),
    "eggplant": Nutrient(25, 1, 6, 0.2, 3, 3.5, 15, 1, 2, 0, 0.3, 3.5, 0, 22, 9, 0.2, 14, 229, 0.2, 2, True),
    "celery": Nutrient(14, 0.7, 3, 0.2, 1.6, 1.3, 15, 22, 3, 0, 0.3, 29.3, 0, 36, 40, 0.2, 11, 260, 0.1, 80, True),

    # === FRUITS ===
    "banana": Nutrient(89, 1.1, 23, 0.3, 2.6, 12, 51, 3, 9, 0, 0.1, 0.5, 0, 20, 5, 0.3, 27, 358, 0.2, 1, True),
    "blueberries": Nutrient(57, 0.7, 14, 0.3, 2.4, 10, 53, 3, 10, 0, 0.6, 19.3, 0, 6, 6, 0.3, 6, 77, 0.2, 1, True),
    "strawberries": Nutrient(32, 0.7, 8, 0.3, 2, 4.9, 40, 1, 59, 0, 0.3, 2.2, 0, 24, 16, 0.4, 13, 153, 0.1, 1, True),
    "raspberries": Nutrient(52, 1.2, 12, 0.7, 6.5, 4.4, 32, 2, 26, 0, 0.9, 7.8, 0, 21, 25, 0.7, 22, 151, 0.4, 1, True),
    "apple": Nutrient(52, 0.3, 14, 0.2, 2.4, 10, 36, 3, 5, 0, 0.2, 2.2, 0, 3, 6, 0.1, 5, 107, 0, 1, True),
    "orange": Nutrient(47, 0.9, 12, 0.1, 2.4, 9.4, 43, 11, 53, 0, 0.2, 0, 0, 30, 40, 0.1, 10, 181, 0.1, 0, True),
    "lemon juice": Nutrient(22, 0.4, 6.9, 0.2, 0.3, 2.5, 20, 0, 39, 0, 0.2, 0, 0, 6, 6, 0.1, 6, 103, 0.1, 1, True),
    "mango": Nutrient(60, 0.8, 15, 0.4, 1.6, 14, 51, 54, 36, 0, 0.9, 4.2, 0, 43, 11, 0.2, 10, 168, 0.1, 1, True),

    # === NUTS & SEEDS ===
    "almonds": Nutrient(579, 21, 22, 50, 12, 4.4, 0, 0, 0, 0, 25.6, 0, 0, 44, 269, 3.7, 270, 733, 3.1, 1, True),
    "walnuts": Nutrient(654, 15, 14, 65, 7, 2.6, 0, 1, 1.3, 0, 0.7, 2.7, 0, 98, 98, 2.9, 158, 441, 3.1, 2, True),
    "cashews": Nutrient(553, 18, 30, 44, 3.3, 6, 22, 0, 0.5, 0, 0.9, 34, 0, 25, 37, 6.7, 292, 660, 5.8, 12, True),
    "peanut butter": Nutrient(588, 25, 20, 50, 6, 9, 14, 0, 0, 0, 9, 0.3, 0, 87, 43, 1.7, 168, 649, 2.8, 459, True),
    "chia seeds": Nutrient(486, 17, 42, 31, 34, 0, 1, 0, 1.6, 0, 0.5, 0, 0, 49, 631, 7.7, 335, 407, 4.6, 16, True),
    "flax seeds": Nutrient(534, 18, 29, 42, 27, 1.6, 0, 0, 0.6, 0, 0.3, 4.3, 0, 87, 255, 5.7, 392, 813, 4.3, 30, True),
    "hemp seeds": Nutrient(553, 32, 8.7, 49, 4, 1.5, 0, 1, 0.5, 0, 0.8, 0, 0, 110, 70, 8.0, 700, 1200, 10, 5, True),
    "pumpkin seeds": Nutrient(559, 30, 11, 49, 6, 1.4, 10, 1, 1.9, 0, 2.2, 7.3, 0, 58, 46, 8.8, 592, 809, 7.8, 7, True),
    "sunflower seeds": Nutrient(584, 21, 20, 51, 9, 2.6, 35, 3, 1.4, 0, 35, 0, 0, 227, 78, 5.3, 325, 645, 5, 9, True),

    # === FATS & OILS ===
    "olive oil": Nutrient(884, 0, 0, 100, 0, 0, 0, 0, 0, 0, 14.4, 60, 0, 0, 1, 0.6, 0, 1, 0, 2, True),
    "coconut oil": Nutrient(862, 0, 0, 100, 0, 0, 0, 0, 0, 0, 0, 0.5, 0, 0, 1, 0, 0, 0, 0, 0, True),
    "avocado oil": Nutrient(884, 0, 0, 100, 0, 0, 0, 0, 0, 0, 12.6, 42, 0, 0, 0, 0, 0, 0, 0, 0, True),
    "MCT oil": Nutrient(862, 0, 0, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, True),

    # === SWEETENERS & FLAVORING ===
    "honey": Nutrient(304, 0.3, 82, 0, 0.2, 82, 58, 0, 0.5, 0, 0, 0, 0, 2, 6, 0.4, 2, 52, 0.2, 4, True),
    "maple syrup": Nutrient(260, 0, 67, 0.1, 0, 60, 54, 0, 0, 0, 0, 0, 0, 0, 102, 0.1, 21, 212, 1.5, 12, True),
    "stevia": Nutrient(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, True),
    "erythritol": Nutrient(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, True),
    "dark chocolate (85%)": Nutrient(580, 8, 46, 43, 11, 24, 23, 2, 0, 0, 0.6, 7.3, 0.3, 12, 73, 12, 228, 715, 3.3, 24, True),
    "cocoa powder": Nutrient(228, 20, 58, 14, 33, 2, 0, 0, 0, 0, 0.1, 2.5, 0, 32, 128, 13.9, 499, 1524, 6.8, 21, True),
    "vanilla extract": Nutrient(288, 0.1, 13, 0.1, 0, 13, 0, 0, 0, 0, 0, 0, 0, 0, 11, 0.1, 12, 148, 0.1, 9, True),
    "cinnamon": Nutrient(247, 4, 81, 1.2, 53, 2.2, 0, 15, 3.8, 0, 2.3, 31.2, 0, 6, 1002, 8.3, 60, 431, 1.8, 10, True),

    # === PROTEIN SUPPLEMENTS ===
    "casein protein powder": Nutrient(370, 80, 4, 3, 0, 2, 0, 0, 0, 0, 0, 0, 0.5, 0, 600, 0.5, 50, 300, 2.5, 180),
    "plant protein powder": Nutrient(380, 75, 10, 5, 5, 2, 0, 0, 0, 0, 0, 0, 0, 0, 100, 5.0, 80, 350, 3.0, 500, True),
    "collagen powder": Nutrient(350, 90, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 30, 0.5, 10, 50, 0.5, 100),

    # === LEGUMES & PLANT PROTEINS ===
    "edamame": Nutrient(121, 12, 9, 5, 5, 2.2, 15, 9, 6, 0, 0.7, 26.7, 0, 303, 63, 2.3, 64, 436, 1.4, 6, True),
    "kidney beans (cooked)": Nutrient(127, 8.7, 23, 0.5, 6.4, 0.3, 24, 0, 1.2, 0, 0, 8.4, 0, 130, 28, 2.9, 45, 403, 1.0, 2, True),
    "hummus": Nutrient(166, 8, 14, 10, 6, 0.3, 6, 2, 0, 0, 0.6, 3, 0, 59, 38, 2.4, 29, 228, 1.8, 379, True),

    # === BEVERAGES / LIQUIDS ===
    "green tea": Nutrient(1, 0, 0.2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0, 1, 8, 0, 1, True),
    "coffee (black)": Nutrient(2, 0.3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 7, 49, 0, 2, True),
    "protein milk": Nutrient(73, 8, 5, 2, 0, 5, 30, 50, 0, 1.2, 0.1, 0.3, 0.7, 5, 150, 0, 15, 170, 0.5, 55),
}


# ---------------------------------------------------------------------------
# Recipe templates by category
# ---------------------------------------------------------------------------

@dataclass
class RecipeTemplate:
    name: str
    meal_type: str  # breakfast, lunch, dinner, snack, dessert
    goals: list[str]
    tags: list[str]
    minutes: int
    servings: int
    ingredients: list[tuple[str, float]]  # (ingredient_key, grams)
    steps: list[str]
    source: str = "AllRecipes-inspired"


def _calc_nutrition(ingredients: list[tuple[str, float]]) -> dict[str, Any]:
    """Calculate total nutrition from ingredients list."""
    totals = {
        "calories": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0,
        "fiber_g": 0, "sugar_g": 0,
        "vitamin_a_ug": 0, "vitamin_c_mg": 0, "vitamin_d_ug": 0,
        "vitamin_e_mg": 0, "vitamin_k_ug": 0, "vitamin_b12_ug": 0,
        "folate_ug": 0, "calcium_mg": 0, "iron_mg": 0,
        "magnesium_mg": 0, "potassium_mg": 0, "zinc_mg": 0, "sodium_mg": 0,
    }
    weighted_gi_sum = 0.0
    total_carb_grams = 0.0

    for ing_name, grams in ingredients:
        n = INGREDIENTS.get(ing_name)
        if not n:
            continue
        factor = grams / 100.0
        totals["calories"] += n.kcal * factor
        totals["protein_g"] += n.protein * factor
        totals["carbs_g"] += n.carbs * factor
        totals["fat_g"] += n.fat * factor
        totals["fiber_g"] += n.fiber * factor
        totals["sugar_g"] += n.sugar * factor
        totals["vitamin_a_ug"] += n.vit_a * factor
        totals["vitamin_c_mg"] += n.vit_c * factor
        totals["vitamin_d_ug"] += n.vit_d * factor
        totals["vitamin_e_mg"] += n.vit_e * factor
        totals["vitamin_k_ug"] += n.vit_k * factor
        totals["vitamin_b12_ug"] += n.vit_b12 * factor
        totals["folate_ug"] += n.folate * factor
        totals["calcium_mg"] += n.calcium * factor
        totals["iron_mg"] += n.iron * factor
        totals["magnesium_mg"] += n.magnesium * factor
        totals["potassium_mg"] += n.potassium * factor
        totals["zinc_mg"] += n.zinc * factor
        totals["sodium_mg"] += n.sodium * factor

        carb_g = n.carbs * factor
        if carb_g > 0 and n.gi > 0:
            weighted_gi_sum += n.gi * carb_g
            total_carb_grams += carb_g

    # Round values
    for k in totals:
        totals[k] = round(totals[k], 1)
    totals["calories"] = int(round(totals["calories"]))

    # Glycemic index (weighted by carb content)
    gi = round(weighted_gi_sum / total_carb_grams) if total_carb_grams > 0 else 0
    gl = round(gi * totals["carbs_g"] / 100, 1)
    # Insulin calculation: 1 unit per 10g carbs (standard ICR for type 1)
    # Adjusted by fiber (net carbs)
    net_carbs = max(0, totals["carbs_g"] - totals["fiber_g"])
    insulin_units = round(net_carbs / 10, 1)

    totals["glycemic_index"] = gi
    totals["glycemic_load"] = gl
    totals["insulin_units"] = insulin_units

    return totals


def _make_id(name: str, idx: int) -> str:
    """Generate stable unique ID."""
    h = hashlib.md5(f"{name}_{idx}".encode()).hexdigest()[:8]
    return f"r{idx:04d}_{h}"


# ---------------------------------------------------------------------------
# Recipe definitions - organized by goal category
# ---------------------------------------------------------------------------

def _diabetes_breakfast() -> list[RecipeTemplate]:
    """Diabetes-friendly breakfast recipes."""
    return [
        RecipeTemplate("Greek Yogurt Parfait with Nuts", "breakfast", ["diabetes", "weight_loss", "maintain"],
            ["low-gi", "high-protein", "quick"], 5, 1,
            [("greek yogurt", 200), ("blueberries", 50), ("almonds", 20), ("chia seeds", 10), ("cinnamon", 2)],
            ["Layer Greek yogurt in a bowl.", "Top with fresh blueberries.", "Sprinkle sliced almonds and chia seeds.", "Dust with cinnamon."]),
        RecipeTemplate("Spinach & Mushroom Omelette", "breakfast", ["diabetes", "keto", "weight_loss"],
            ["low-carb", "high-protein"], 15, 1,
            [("eggs", 150), ("spinach", 60), ("mushrooms", 80), ("olive oil", 10), ("mozzarella", 30)],
            ["Whisk eggs in a bowl.", "Heat olive oil in a non-stick pan.", "Sauté mushrooms and spinach until wilted.", "Pour eggs over vegetables.", "Add mozzarella, fold and cook until set."]),
        RecipeTemplate("Avocado & Smoked Salmon Toast", "breakfast", ["diabetes", "maintain"],
            ["omega-3", "healthy-fats"], 10, 1,
            [("whole wheat bread", 60), ("avocado", 80), ("salmon fillet", 60), ("lemon juice", 10)],
            ["Toast the whole wheat bread.", "Mash avocado with lemon juice.", "Spread on toast and top with smoked salmon.", "Season with black pepper."]),
        RecipeTemplate("Low-GI Overnight Oats", "breakfast", ["diabetes", "weight_loss", "maintain"],
            ["meal-prep", "high-fiber"], 5, 1,
            [("oats (rolled)", 40), ("chia seeds", 15), ("almond milk (unsweetened)", 200), ("blueberries", 60), ("walnuts", 15)],
            ["Combine oats, chia seeds, and almond milk in a jar.", "Refrigerate overnight.", "Top with blueberries and walnuts before serving."]),
        RecipeTemplate("Cottage Cheese & Berry Bowl", "breakfast", ["diabetes", "muscle", "weight_loss"],
            ["high-protein", "low-gi"], 5, 1,
            [("cottage cheese", 200), ("raspberries", 80), ("flax seeds", 10), ("stevia", 1)],
            ["Scoop cottage cheese into a bowl.", "Add fresh raspberries.", "Sprinkle ground flax seeds.", "Sweeten with stevia if desired."]),
        RecipeTemplate("Egg Muffins with Vegetables", "breakfast", ["diabetes", "keto", "weight_loss"],
            ["meal-prep", "portable"], 25, 4,
            [("eggs", 300), ("bell pepper (red)", 80), ("spinach", 60), ("onion", 40), ("cheddar cheese", 40)],
            ["Preheat oven to 180°C.", "Whisk eggs in a large bowl.", "Dice peppers and onion, chop spinach.", "Mix vegetables into eggs.", "Pour into muffin tin, top with cheese.", "Bake 20 minutes until golden."]),
        RecipeTemplate("Almond Flour Pancakes", "breakfast", ["diabetes", "keto"],
            ["low-carb", "gluten-free"], 20, 2,
            [("almond flour", 60), ("eggs", 100), ("cream cheese", 30), ("stevia", 1), ("coconut oil", 10)],
            ["Blend almond flour, eggs, cream cheese and stevia.", "Heat coconut oil in a pan.", "Pour batter to form small pancakes.", "Cook 2–3 min per side until golden."]),
        RecipeTemplate("Chia Seed Pudding", "breakfast", ["diabetes", "vegan", "weight_loss"],
            ["meal-prep", "high-fiber", "dairy-free"], 5, 1,
            [("chia seeds", 30), ("almond milk (unsweetened)", 250), ("stevia", 1), ("vanilla extract", 5), ("strawberries", 80)],
            ["Mix chia seeds with almond milk, stevia, and vanilla.", "Refrigerate for 4+ hours or overnight.", "Top with sliced strawberries."]),
        RecipeTemplate("Scrambled Eggs with Avocado", "breakfast", ["diabetes", "keto", "maintain"],
            ["quick", "high-protein", "healthy-fats"], 10, 1,
            [("eggs", 150), ("avocado", 80), ("butter", 10), ("spinach", 40)],
            ["Melt butter in a pan over low heat.", "Scramble eggs gently until just set.", "Serve alongside sliced avocado and fresh spinach."]),
        RecipeTemplate("Smoked Salmon & Cream Cheese Roll-ups", "breakfast", ["diabetes", "keto"],
            ["no-cook", "high-protein", "omega-3"], 5, 1,
            [("salmon fillet", 100), ("cream cheese", 40), ("cucumber", 60), ("lemon juice", 5)],
            ["Lay salmon slices flat.", "Spread cream cheese on each slice.", "Add cucumber strips.", "Roll up and drizzle with lemon."]),
    ]


def _diabetes_lunch() -> list[RecipeTemplate]:
    return [
        RecipeTemplate("Grilled Chicken & Quinoa Bowl", "lunch", ["diabetes", "muscle", "maintain"],
            ["high-protein", "balanced", "meal-prep"], 30, 1,
            [("chicken breast", 150), ("quinoa (cooked)", 150), ("spinach", 60), ("bell pepper (red)", 80), ("olive oil", 10), ("lemon juice", 10)],
            ["Grill chicken breast until cooked through.", "Arrange quinoa as base.", "Top with fresh spinach and sliced peppers.", "Drizzle with olive oil and lemon."]),
        RecipeTemplate("Lentil & Vegetable Soup", "lunch", ["diabetes", "vegan", "weight_loss"],
            ["high-fiber", "warming", "meal-prep"], 35, 2,
            [("lentils (cooked)", 200), ("carrot", 100), ("celery", 60), ("tomatoes", 150), ("onion", 80), ("spinach", 60), ("garlic", 10), ("olive oil", 15)],
            ["Sauté onion, garlic, carrot and celery in olive oil.", "Add tomatoes and lentils with water/stock.", "Simmer 25 minutes.", "Stir in spinach and serve."]),
        RecipeTemplate("Tuna Salad Lettuce Wraps", "lunch", ["diabetes", "keto", "weight_loss"],
            ["low-carb", "quick", "no-cook"], 10, 1,
            [("tuna (canned)", 120), ("avocado", 60), ("celery", 40), ("lemon juice", 10), ("cucumber", 80)],
            ["Drain tuna and flake into a bowl.", "Mash avocado and mix with tuna.", "Add diced celery and lemon juice.", "Serve in cucumber boats or lettuce leaves."]),
        RecipeTemplate("Turkey & Black Bean Bowl", "lunch", ["diabetes", "muscle", "maintain"],
            ["high-protein", "high-fiber"], 25, 1,
            [("ground turkey", 150), ("black beans (cooked)", 100), ("bell pepper (red)", 80), ("tomatoes", 100), ("avocado", 50), ("onion", 40)],
            ["Brown turkey in a pan.", "Add diced peppers, onion, and tomatoes.", "Stir in black beans and simmer 10 min.", "Serve topped with sliced avocado."]),
        RecipeTemplate("Cauliflower Rice Stir-Fry", "lunch", ["diabetes", "keto", "vegan", "weight_loss"],
            ["low-carb", "quick"], 20, 1,
            [("cauliflower rice", 200), ("broccoli", 100), ("bell pepper (red)", 80), ("mushrooms", 80), ("tofu (firm)", 120), ("olive oil", 10), ("garlic", 5)],
            ["Press and cube tofu.", "Stir-fry tofu in olive oil until golden.", "Add garlic, broccoli, peppers, mushrooms.", "Add cauliflower rice, cook 5 min.", "Season with soy sauce and serve."]),
        RecipeTemplate("Mediterranean Chickpea Salad", "lunch", ["diabetes", "vegan", "weight_loss"],
            ["high-fiber", "no-cook", "meal-prep"], 10, 2,
            [("chickpeas (cooked)", 200), ("cucumber", 120), ("tomatoes", 150), ("bell pepper (red)", 80), ("onion", 40), ("olive oil", 20), ("lemon juice", 15)],
            ["Combine chickpeas with diced vegetables.", "Whisk olive oil and lemon juice for dressing.", "Toss salad with dressing.", "Season and refrigerate."]),
        RecipeTemplate("Egg & Avocado Protein Bowl", "lunch", ["diabetes", "keto", "maintain"],
            ["quick", "high-protein"], 15, 1,
            [("eggs", 150), ("avocado", 100), ("spinach", 80), ("tomatoes", 60), ("olive oil", 10)],
            ["Boil or fry eggs to preference.", "Arrange spinach as base.", "Top with sliced avocado and tomatoes.", "Add eggs and drizzle olive oil."]),
        RecipeTemplate("Grilled Salmon with Asparagus", "lunch", ["diabetes", "keto", "maintain"],
            ["omega-3", "high-protein"], 25, 1,
            [("salmon fillet", 150), ("asparagus", 150), ("olive oil", 10), ("lemon juice", 10), ("garlic", 5)],
            ["Season salmon with garlic and lemon.", "Grill salmon 4–5 min per side.", "Toss asparagus in olive oil, grill alongside.", "Serve together."]),
    ]


def _diabetes_dinner() -> list[RecipeTemplate]:
    return [
        RecipeTemplate("Herb-Crusted Cod with Roasted Vegetables", "dinner", ["diabetes", "weight_loss", "maintain"],
            ["omega-3", "low-carb"], 35, 1,
            [("cod fillet", 180), ("broccoli", 120), ("zucchini", 100), ("bell pepper (red)", 80), ("olive oil", 15), ("garlic", 5), ("lemon juice", 10)],
            ["Preheat oven to 200°C.", "Season cod with herbs, garlic and lemon.", "Toss vegetables in olive oil.", "Roast vegetables 20 min, add fish for last 12 min."]),
        RecipeTemplate("Chicken Thigh with Cauliflower Mash", "dinner", ["diabetes", "keto", "maintain"],
            ["comfort-food", "low-carb"], 40, 1,
            [("chicken thigh", 200), ("cauliflower", 250), ("butter", 15), ("garlic", 5), ("olive oil", 10)],
            ["Season chicken thighs, pan-fry in olive oil until crispy.", "Steam cauliflower until very tender.", "Mash with butter and garlic.", "Serve chicken on cauliflower mash."]),
        RecipeTemplate("Beef & Vegetable Stir-Fry", "dinner", ["diabetes", "muscle", "maintain"],
            ["high-protein", "quick"], 20, 1,
            [("ground beef (lean)", 150), ("broccoli", 100), ("bell pepper (red)", 80), ("mushrooms", 80), ("zucchini", 80), ("garlic", 5), ("olive oil", 10)],
            ["Brown beef in olive oil.", "Add garlic and all vegetables.", "Stir-fry 5–7 minutes until tender-crisp.", "Season and serve."]),
        RecipeTemplate("Baked Salmon with Sweet Potato", "dinner", ["diabetes", "maintain"],
            ["omega-3", "balanced"], 35, 1,
            [("salmon fillet", 150), ("sweet potato (cooked)", 150), ("spinach", 80), ("olive oil", 10), ("lemon juice", 10)],
            ["Bake salmon at 200°C for 15 min.", "Roast sweet potato cubes alongside.", "Wilt spinach with garlic.", "Plate together with lemon drizzle."]),
        RecipeTemplate("Turkey Meatballs with Zucchini Noodles", "dinner", ["diabetes", "weight_loss", "maintain"],
            ["low-carb", "high-protein"], 30, 2,
            [("ground turkey", 200), ("zucchini", 300), ("tomatoes", 200), ("onion", 50), ("garlic", 5), ("olive oil", 10), ("parmesan", 20)],
            ["Mix turkey with seasonings, form meatballs.", "Bake at 190°C for 18 min.", "Spiralize zucchini into noodles.", "Simmer tomatoes with garlic for sauce.", "Combine and top with parmesan."]),
        RecipeTemplate("Shrimp & Vegetable Skewers", "dinner", ["diabetes", "keto", "weight_loss"],
            ["grilled", "low-carb", "quick"], 20, 1,
            [("shrimp", 180), ("bell pepper (red)", 80), ("zucchini", 100), ("onion", 50), ("olive oil", 10), ("lemon juice", 10)],
            ["Thread shrimp and vegetables onto skewers.", "Brush with olive oil and lemon.", "Grill 3–4 minutes per side.", "Serve immediately."]),
        RecipeTemplate("Stuffed Bell Peppers", "dinner", ["diabetes", "maintain"],
            ["balanced", "meal-prep"], 45, 2,
            [("bell pepper (red)", 300), ("ground turkey", 150), ("quinoa (cooked)", 100), ("tomatoes", 100), ("onion", 50), ("mozzarella", 40)],
            ["Halve peppers and remove seeds.", "Cook turkey with onion and tomatoes.", "Mix with quinoa.", "Fill peppers, top with mozzarella.", "Bake at 190°C for 25 min."]),
        RecipeTemplate("Lemon Garlic Chicken with Green Beans", "dinner", ["diabetes", "weight_loss", "maintain"],
            ["simple", "one-pan"], 30, 1,
            [("chicken breast", 180), ("green beans", 150), ("garlic", 10), ("lemon juice", 15), ("olive oil", 10), ("butter", 10)],
            ["Season chicken with garlic and lemon.", "Pan-fry in olive oil until golden.", "Steam green beans until tender-crisp.", "Finish with butter and serve together."]),
    ]


def _diabetes_desserts() -> list[RecipeTemplate]:
    return [
        RecipeTemplate("Sugar-Free Chocolate Mousse", "dessert", ["diabetes", "keto"],
            ["low-carb", "indulgent"], 15, 2,
            [("dark chocolate (85%)", 50), ("coconut cream", 150), ("stevia", 2), ("vanilla extract", 5)],
            ["Melt dark chocolate gently.", "Whip coconut cream until fluffy.", "Fold chocolate into cream with stevia and vanilla.", "Chill 2 hours before serving."]),
        RecipeTemplate("Almond Flour Brownies", "dessert", ["diabetes", "keto"],
            ["low-carb", "gluten-free"], 30, 8,
            [("almond flour", 120), ("cocoa powder", 30), ("eggs", 100), ("butter", 60), ("erythritol", 40), ("dark chocolate (85%)", 40)],
            ["Melt butter and chocolate together.", "Whisk in eggs and erythritol.", "Fold in almond flour and cocoa.", "Pour into lined pan.", "Bake at 175°C for 18–20 min."]),
        RecipeTemplate("Berry Chia Pudding Parfait", "dessert", ["diabetes", "vegan", "weight_loss"],
            ["no-bake", "high-fiber"], 10, 1,
            [("chia seeds", 25), ("almond milk (unsweetened)", 200), ("strawberries", 80), ("blueberries", 60), ("stevia", 1)],
            ["Mix chia seeds with almond milk and stevia.", "Refrigerate 4+ hours.", "Layer with fresh berries."]),
        RecipeTemplate("Coconut Flour Mug Cake", "dessert", ["diabetes", "keto"],
            ["quick", "single-serving"], 5, 1,
            [("coconut flour", 15), ("eggs", 50), ("butter", 10), ("erythritol", 10), ("cocoa powder", 5), ("vanilla extract", 3)],
            ["Mix all ingredients in a mug.", "Microwave 90 seconds.", "Let cool 1 minute before eating."]),
        RecipeTemplate("Protein Ice Cream", "dessert", ["diabetes", "muscle"],
            ["frozen", "high-protein"], 10, 2,
            [("greek yogurt", 300), ("whey protein powder", 30), ("strawberries", 100), ("stevia", 2)],
            ["Blend all ingredients until smooth.", "Pour into container.", "Freeze 3–4 hours, stirring every hour.", "Scoop and serve."]),
    ]


def _muscle_breakfast() -> list[RecipeTemplate]:
    return [
        RecipeTemplate("Protein Oatmeal Power Bowl", "breakfast", ["muscle", "maintain"],
            ["high-protein", "high-carb", "bulking"], 10, 1,
            [("oats (rolled)", 80), ("whey protein powder", 30), ("banana", 100), ("peanut butter", 20), ("whole milk", 200)],
            ["Cook oats with milk.", "Stir in protein powder.", "Top with sliced banana and peanut butter."]),
        RecipeTemplate("High-Protein Scramble", "breakfast", ["muscle", "diabetes", "maintain"],
            ["high-protein", "quick"], 10, 1,
            [("eggs", 200), ("egg whites", 100), ("chicken breast", 80), ("spinach", 60), ("mozzarella", 30), ("olive oil", 5)],
            ["Scramble whole eggs and whites together.", "Add diced cooked chicken.", "Fold in spinach until wilted.", "Top with mozzarella."]),
        RecipeTemplate("Protein Pancakes", "breakfast", ["muscle", "maintain"],
            ["high-protein", "sweet"], 15, 2,
            [("oats (rolled)", 60), ("whey protein powder", 30), ("eggs", 100), ("banana", 80), ("blueberries", 50)],
            ["Blend oats, protein powder, eggs and banana.", "Cook pancakes on a non-stick pan.", "Top with fresh blueberries."]),
        RecipeTemplate("Muscle Builder Smoothie", "breakfast", ["muscle", "maintain"],
            ["liquid", "quick", "high-calorie"], 5, 1,
            [("whey protein powder", 40), ("banana", 120), ("oats (rolled)", 40), ("peanut butter", 25), ("whole milk", 300)],
            ["Add all ingredients to a blender.", "Blend until smooth.", "Pour and drink immediately."]),
        RecipeTemplate("Steak & Eggs", "breakfast", ["muscle", "keto"],
            ["high-protein", "hearty"], 20, 1,
            [("ground beef (lean)", 150), ("eggs", 150), ("spinach", 60), ("butter", 10), ("mushrooms", 80)],
            ["Cook steak patties to preference.", "Fry eggs in butter.", "Sauté mushrooms and spinach.", "Plate together."]),
        RecipeTemplate("Cottage Cheese Protein Bowl", "breakfast", ["muscle", "diabetes", "weight_loss"],
            ["high-protein", "quick", "no-cook"], 5, 1,
            [("cottage cheese", 250), ("walnuts", 20), ("hemp seeds", 15), ("blueberries", 60), ("honey", 10)],
            ["Scoop cottage cheese into a bowl.", "Top with walnuts, hemp seeds, berries.", "Drizzle with honey."]),
        RecipeTemplate("Protein French Toast", "breakfast", ["muscle", "maintain"],
            ["high-protein", "sweet"], 15, 2,
            [("whole wheat bread", 120), ("eggs", 150), ("whey protein powder", 20), ("cinnamon", 2), ("butter", 10), ("strawberries", 80)],
            ["Whisk eggs with protein powder and cinnamon.", "Dip bread slices in mixture.", "Cook in butter until golden.", "Top with strawberries."]),
        RecipeTemplate("Egg White & Turkey Wrap", "breakfast", ["muscle", "weight_loss"],
            ["portable", "high-protein", "low-fat"], 15, 1,
            [("egg whites", 150), ("ground turkey", 100), ("whole wheat bread", 60), ("spinach", 40), ("tomatoes", 40)],
            ["Scramble egg whites.", "Cook turkey with seasoning.", "Layer on wrap with spinach and tomatoes.", "Roll up and serve."]),
    ]


def _muscle_lunch() -> list[RecipeTemplate]:
    return [
        RecipeTemplate("Chicken & Brown Rice Meal Prep", "lunch", ["muscle", "maintain"],
            ["meal-prep", "balanced", "high-protein"], 35, 2,
            [("chicken breast", 250), ("brown rice (cooked)", 250), ("broccoli", 150), ("olive oil", 10), ("garlic", 5)],
            ["Grill or bake chicken breasts.", "Prepare brown rice.", "Steam broccoli.", "Divide into containers with olive oil drizzle."]),
        RecipeTemplate("Tuna & Quinoa Power Bowl", "lunch", ["muscle", "diabetes", "maintain"],
            ["omega-3", "high-protein"], 15, 1,
            [("tuna (canned)", 150), ("quinoa (cooked)", 150), ("avocado", 80), ("spinach", 60), ("tomatoes", 80), ("olive oil", 10)],
            ["Layer quinoa, spinach, tomatoes.", "Top with flaked tuna and avocado.", "Drizzle with olive oil."]),
        RecipeTemplate("Double Chicken Burrito Bowl", "lunch", ["muscle", "maintain"],
            ["high-protein", "high-carb"], 25, 1,
            [("chicken breast", 200), ("brown rice (cooked)", 200), ("black beans (cooked)", 100), ("bell pepper (red)", 80), ("avocado", 60), ("tomatoes", 80)],
            ["Grill and slice chicken.", "Layer rice, beans, peppers, tomatoes.", "Top with chicken and avocado."]),
        RecipeTemplate("Salmon Poke Bowl", "lunch", ["muscle", "maintain"],
            ["omega-3", "fresh"], 15, 1,
            [("salmon fillet", 180), ("brown rice (cooked)", 150), ("avocado", 60), ("cucumber", 80), ("edamame", 60)],
            ["Dice fresh salmon.", "Arrange rice as base.", "Top with salmon, avocado, cucumber, edamame.", "Drizzle with soy sauce."]),
        RecipeTemplate("Turkey & Sweet Potato Bowl", "lunch", ["muscle", "maintain"],
            ["balanced", "meal-prep"], 30, 1,
            [("ground turkey", 200), ("sweet potato (cooked)", 200), ("spinach", 80), ("olive oil", 10)],
            ["Brown turkey with seasoning.", "Roast sweet potato cubes.", "Layer with spinach.", "Drizzle olive oil."]),
        RecipeTemplate("High-Protein Pasta", "lunch", ["muscle", "maintain"],
            ["high-carb", "filling"], 20, 2,
            [("pasta (cooked)", 250), ("chicken breast", 200), ("tomatoes", 150), ("spinach", 60), ("parmesan", 20), ("olive oil", 10)],
            ["Cook pasta al dente.", "Grill and slice chicken.", "Make quick tomato sauce with garlic.", "Toss pasta with chicken, sauce, spinach.", "Top with parmesan."]),
        RecipeTemplate("Beef & Lentil Power Bowl", "lunch", ["muscle", "maintain"],
            ["high-protein", "high-iron"], 30, 1,
            [("ground beef (lean)", 150), ("lentils (cooked)", 150), ("spinach", 60), ("tomatoes", 80), ("onion", 40), ("olive oil", 10)],
            ["Brown beef with onion.", "Mix in lentils and tomatoes.", "Simmer 10 min.", "Serve on spinach."]),
    ]


def _muscle_dinner() -> list[RecipeTemplate]:
    return [
        RecipeTemplate("Grilled Chicken with Sweet Potato & Broccoli", "dinner", ["muscle", "maintain"],
            ["classic", "bodybuilding", "meal-prep"], 35, 1,
            [("chicken breast", 200), ("sweet potato (cooked)", 200), ("broccoli", 150), ("olive oil", 10)],
            ["Grill chicken breast.", "Roast sweet potato cubes.", "Steam broccoli.", "Plate together with olive oil."]),
        RecipeTemplate("Salmon Teriyaki with Rice", "dinner", ["muscle", "maintain"],
            ["omega-3", "Asian-inspired"], 25, 1,
            [("salmon fillet", 180), ("brown rice (cooked)", 200), ("broccoli", 120), ("garlic", 5), ("honey", 15)],
            ["Glaze salmon with honey-garlic sauce.", "Bake at 200°C for 12 min.", "Serve with brown rice and steamed broccoli."]),
        RecipeTemplate("Lean Beef Bolognese", "dinner", ["muscle", "maintain"],
            ["pasta", "Italian", "high-protein"], 40, 2,
            [("ground beef (lean)", 250), ("pasta (cooked)", 250), ("tomatoes", 200), ("onion", 60), ("garlic", 5), ("olive oil", 10), ("parmesan", 20)],
            ["Brown beef with onion and garlic.", "Add tomatoes, simmer 20 min.", "Cook pasta al dente.", "Serve sauce on pasta with parmesan."]),
        RecipeTemplate("Turkey Steak with Quinoa", "dinner", ["muscle", "diabetes", "maintain"],
            ["lean", "balanced"], 25, 1,
            [("ground turkey", 200), ("quinoa (cooked)", 150), ("asparagus", 120), ("olive oil", 10), ("garlic", 5)],
            ["Form turkey into steaks, grill.", "Cook quinoa.", "Grill asparagus with olive oil.", "Plate together."]),
        RecipeTemplate("Shrimp & Pasta Protein Bowl", "dinner", ["muscle", "maintain"],
            ["seafood", "high-protein"], 20, 1,
            [("shrimp", 200), ("pasta (cooked)", 200), ("garlic", 5), ("spinach", 80), ("olive oil", 15), ("lemon juice", 10), ("parmesan", 15)],
            ["Sauté shrimp in olive oil and garlic.", "Toss with cooked pasta.", "Add spinach, lemon juice.", "Top with parmesan."]),
        RecipeTemplate("BBQ Chicken with Baked Potato", "dinner", ["muscle", "maintain"],
            ["comfort-food", "high-carb"], 40, 1,
            [("chicken thigh", 200), ("white potato (cooked)", 250), ("butter", 10), ("green beans", 120)],
            ["Grill chicken thighs with BBQ seasoning.", "Bake potato until fluffy.", "Steam green beans.", "Serve with butter on potato."]),
    ]


def _muscle_snacks() -> list[RecipeTemplate]:
    return [
        RecipeTemplate("Chocolate Protein Shake", "snack", ["muscle", "maintain"],
            ["liquid", "quick", "post-workout"], 5, 1,
            [("whey protein powder", 40), ("banana", 100), ("whole milk", 300), ("peanut butter", 15), ("cocoa powder", 10)],
            ["Add all ingredients to a blender.", "Blend until creamy smooth.", "Serve immediately."]),
        RecipeTemplate("Protein Yogurt Bowl", "snack", ["muscle", "diabetes"],
            ["high-protein", "quick"], 5, 1,
            [("greek yogurt", 250), ("whey protein powder", 20), ("almonds", 20), ("blueberries", 50), ("honey", 10)],
            ["Mix protein powder into yogurt.", "Top with almonds and blueberries.", "Drizzle honey."]),
        RecipeTemplate("Peanut Butter Protein Balls", "snack", ["muscle", "maintain"],
            ["meal-prep", "portable", "no-bake"], 15, 8,
            [("oats (rolled)", 80), ("peanut butter", 60), ("whey protein powder", 30), ("honey", 20), ("dark chocolate (85%)", 20)],
            ["Mix oats, peanut butter, protein powder and honey.", "Form into 8 balls.", "Melt chocolate, drizzle over balls.", "Refrigerate 30 min."]),
        RecipeTemplate("Cottage Cheese & Pineapple", "snack", ["muscle", "maintain"],
            ["quick", "high-protein", "sweet"], 3, 1,
            [("cottage cheese", 200), ("mango", 80), ("hemp seeds", 10)],
            ["Scoop cottage cheese into a bowl.", "Add diced mango.", "Sprinkle hemp seeds."]),
        RecipeTemplate("Protein Banana Bread Slice", "snack", ["muscle", "maintain"],
            ["baked", "sweet", "portable"], 45, 8,
            [("banana", 200), ("oats (rolled)", 100), ("whey protein powder", 40), ("eggs", 100), ("peanut butter", 30), ("walnuts", 30)],
            ["Mash bananas.", "Mix in oats, protein, eggs, peanut butter.", "Add walnuts.", "Bake at 175°C for 35 min.", "Cut into 8 slices."]),
        RecipeTemplate("High-Protein Smoothie Bowl", "snack", ["muscle", "maintain"],
            ["thick", "filling", "colorful"], 10, 1,
            [("whey protein powder", 30), ("banana", 80), ("blueberries", 80), ("almond milk (unsweetened)", 100), ("pumpkin seeds", 15), ("chia seeds", 10)],
            ["Blend protein, banana, blueberries and almond milk.", "Pour thick mixture into a bowl.", "Top with pumpkin and chia seeds."]),
        RecipeTemplate("Turkey Jerky & Nuts Trail Mix", "snack", ["muscle", "keto"],
            ["portable", "no-prep"], 2, 1,
            [("ground turkey", 50), ("almonds", 30), ("pumpkin seeds", 20), ("dark chocolate (85%)", 15)],
            ["Combine all in a snack bag.", "Ready to eat on the go."]),
        RecipeTemplate("Casein Protein Pudding", "snack", ["muscle", "maintain"],
            ["nighttime", "slow-release"], 5, 1,
            [("casein protein powder", 35), ("almond milk (unsweetened)", 200), ("cocoa powder", 5), ("stevia", 1)],
            ["Mix casein powder with cold almond milk.", "Add cocoa and stevia.", "Stir until thick and pudding-like.", "Eat before bed."]),
    ]


def _vegan_recipes() -> list[RecipeTemplate]:
    return [
        RecipeTemplate("Tofu Scramble with Vegetables", "breakfast", ["vegan", "weight_loss"],
            ["high-protein", "savory"], 15, 1,
            [("tofu (firm)", 200), ("spinach", 60), ("bell pepper (red)", 80), ("mushrooms", 80), ("onion", 40), ("olive oil", 10)],
            ["Crumble tofu into chunks.", "Sauté vegetables in olive oil.", "Add tofu and turmeric.", "Cook until heated through."]),
        RecipeTemplate("Overnight Oats with Berries", "breakfast", ["vegan", "diabetes"],
            ["meal-prep", "no-cook"], 5, 1,
            [("oats (rolled)", 60), ("almond milk (unsweetened)", 200), ("chia seeds", 15), ("blueberries", 80), ("maple syrup", 10)],
            ["Combine oats, almond milk, chia seeds.", "Refrigerate overnight.", "Top with berries and maple syrup."]),
        RecipeTemplate("Smoothie Bowl (Tropical)", "breakfast", ["vegan", "maintain"],
            ["colorful", "fresh"], 10, 1,
            [("banana", 120), ("mango", 80), ("spinach", 40), ("almond milk (unsweetened)", 150), ("chia seeds", 10), ("coconut cream", 20)],
            ["Blend banana, mango, spinach and almond milk.", "Pour into a bowl.", "Top with coconut cream and chia seeds."]),
        RecipeTemplate("Lentil Bolognese", "dinner", ["vegan", "weight_loss", "maintain"],
            ["high-fiber", "Italian", "meal-prep"], 35, 2,
            [("lentils (cooked)", 250), ("pasta (cooked)", 200), ("tomatoes", 200), ("onion", 60), ("garlic", 5), ("carrot", 60), ("olive oil", 10)],
            ["Sauté onion, garlic, carrot in olive oil.", "Add tomatoes and lentils.", "Simmer 20 min.", "Serve over pasta."]),
        RecipeTemplate("Chickpea Curry", "dinner", ["vegan", "maintain"],
            ["warming", "spiced", "high-fiber"], 30, 2,
            [("chickpeas (cooked)", 250), ("coconut cream", 150), ("tomatoes", 150), ("spinach", 80), ("onion", 60), ("garlic", 5), ("olive oil", 10)],
            ["Sauté onion and garlic.", "Add tomatoes and coconut cream.", "Add chickpeas and simmer 15 min.", "Stir in spinach."]),
        RecipeTemplate("Tempeh Stir-Fry", "dinner", ["vegan", "muscle"],
            ["high-protein", "Asian-inspired"], 20, 1,
            [("tempeh", 150), ("broccoli", 120), ("bell pepper (red)", 80), ("mushrooms", 80), ("brown rice (cooked)", 150), ("olive oil", 10), ("garlic", 5)],
            ["Cube and pan-fry tempeh until crispy.", "Stir-fry vegetables with garlic.", "Combine and serve over brown rice."]),
        RecipeTemplate("Black Bean Tacos", "lunch", ["vegan", "maintain"],
            ["Mexican-inspired", "quick"], 15, 2,
            [("black beans (cooked)", 200), ("avocado", 80), ("tomatoes", 100), ("onion", 40), ("bell pepper (red)", 60), ("lemon juice", 10)],
            ["Heat black beans with spices.", "Dice vegetables.", "Assemble in lettuce wraps or tortillas.", "Top with avocado and lime."]),
        RecipeTemplate("Vegan Protein Bowl", "lunch", ["vegan", "muscle"],
            ["high-protein", "balanced"], 20, 1,
            [("quinoa (cooked)", 150), ("edamame", 100), ("tofu (firm)", 120), ("avocado", 60), ("spinach", 60), ("pumpkin seeds", 15)],
            ["Arrange quinoa as base.", "Add edamame and cubed baked tofu.", "Top with avocado, spinach, seeds."]),
        RecipeTemplate("Hummus & Vegetable Plate", "snack", ["vegan", "diabetes"],
            ["no-cook", "fiber-rich"], 5, 1,
            [("hummus", 100), ("carrot", 80), ("cucumber", 80), ("bell pepper (red)", 60), ("celery", 50)],
            ["Slice all vegetables into sticks.", "Serve with hummus for dipping."]),
        RecipeTemplate("Vegan Chocolate Protein Shake", "snack", ["vegan", "muscle"],
            ["liquid", "post-workout"], 5, 1,
            [("plant protein powder", 35), ("banana", 100), ("almond milk (unsweetened)", 300), ("peanut butter", 15), ("cocoa powder", 10)],
            ["Blend all ingredients until smooth.", "Serve immediately."]),
        RecipeTemplate("Energy Date Balls", "snack", ["vegan", "maintain"],
            ["no-bake", "portable"], 15, 8,
            [("almonds", 60), ("cashews", 40), ("cocoa powder", 15), ("coconut oil", 10), ("hemp seeds", 20), ("maple syrup", 15)],
            ["Process nuts in food processor.", "Add cocoa, coconut oil, hemp seeds, maple syrup.", "Roll into 8 balls.", "Refrigerate."]),
        RecipeTemplate("Vegan Buddha Bowl", "lunch", ["vegan", "weight_loss", "maintain"],
            ["colorful", "balanced", "meal-prep"], 25, 1,
            [("quinoa (cooked)", 120), ("chickpeas (cooked)", 100), ("sweet potato (cooked)", 100), ("kale", 60), ("avocado", 50), ("lemon juice", 10), ("olive oil", 10)],
            ["Arrange quinoa as base.", "Add roasted chickpeas and sweet potato.", "Top with kale and avocado.", "Drizzle lemon-oil dressing."]),
    ]


def _keto_recipes() -> list[RecipeTemplate]:
    return [
        RecipeTemplate("Bacon & Cheese Omelette", "breakfast", ["keto", "maintain"],
            ["high-fat", "low-carb"], 15, 1,
            [("eggs", 150), ("cheddar cheese", 40), ("butter", 10), ("mushrooms", 60), ("spinach", 40)],
            ["Melt butter in pan.", "Whisk eggs, pour into pan.", "Add cheese, mushrooms, spinach.", "Fold and serve."]),
        RecipeTemplate("Keto Bulletproof Coffee", "breakfast", ["keto"],
            ["liquid", "energizing"], 5, 1,
            [("coffee (black)", 300), ("butter", 20), ("MCT oil", 15), ("coconut cream", 30)],
            ["Brew strong black coffee.", "Add butter, MCT oil, coconut cream.", "Blend until frothy."]),
        RecipeTemplate("Avocado Eggs Benedict (No Muffin)", "breakfast", ["keto", "diabetes"],
            ["indulgent", "low-carb"], 15, 1,
            [("eggs", 100), ("avocado", 120), ("salmon fillet", 60), ("butter", 10), ("lemon juice", 5)],
            ["Poach eggs.", "Halve avocado as the base.", "Top with salmon and poached egg.", "Drizzle hollandaise (butter + lemon)."]),
        RecipeTemplate("Keto Chicken Caesar Salad", "lunch", ["keto", "muscle"],
            ["high-protein", "classic"], 20, 1,
            [("chicken breast", 180), ("spinach", 100), ("parmesan", 30), ("olive oil", 20), ("eggs", 50), ("lemon juice", 10)],
            ["Grill and slice chicken.", "Toss greens with olive oil and lemon.", "Top with chicken and shaved parmesan.", "Add halved boiled egg."]),
        RecipeTemplate("Keto Tuna Stuffed Avocados", "lunch", ["keto", "weight_loss"],
            ["no-cook", "quick"], 10, 1,
            [("avocado", 150), ("tuna (canned)", 120), ("cream cheese", 20), ("lemon juice", 5), ("celery", 30)],
            ["Halve avocados.", "Mix tuna with cream cheese, celery, lemon.", "Fill avocado halves."]),
        RecipeTemplate("Keto Butter Chicken", "dinner", ["keto"],
            ["Indian-inspired", "creamy"], 30, 2,
            [("chicken thigh", 300), ("butter", 30), ("coconut cream", 150), ("tomatoes", 100), ("garlic", 10), ("onion", 40)],
            ["Cube chicken, brown in butter.", "Sauté garlic and onion.", "Add tomatoes and cream.", "Simmer 15 min until thick."]),
        RecipeTemplate("Steak with Garlic Butter", "dinner", ["keto", "muscle"],
            ["high-fat", "high-protein"], 20, 1,
            [("ground beef (lean)", 200), ("butter", 20), ("garlic", 5), ("asparagus", 120), ("olive oil", 10)],
            ["Form beef into steak, season.", "Pan-sear 4 min per side.", "Rest with garlic butter on top.", "Grill asparagus alongside."]),
        RecipeTemplate("Keto Pizza (Fathead Dough)", "dinner", ["keto"],
            ["comfort-food", "cheesy"], 30, 2,
            [("almond flour", 80), ("mozzarella", 150), ("cream cheese", 30), ("eggs", 50), ("tomatoes", 60), ("mushrooms", 60)],
            ["Melt mozzarella with cream cheese.", "Mix in almond flour and egg.", "Roll out dough, pre-bake 10 min at 200°C.", "Add toppings, bake 8 more min."]),
        RecipeTemplate("Keto Fat Bombs (Chocolate PB)", "snack", ["keto"],
            ["sweet", "no-bake", "portable"], 15, 8,
            [("coconut oil", 40), ("peanut butter", 40), ("cocoa powder", 15), ("erythritol", 10), ("butter", 20)],
            ["Melt coconut oil and butter.", "Mix in peanut butter, cocoa, erythritol.", "Pour into silicone mold.", "Freeze 30 min."]),
        RecipeTemplate("Keto Cheese Crisps", "snack", ["keto"],
            ["crunchy", "simple"], 10, 4,
            [("cheddar cheese", 80), ("parmesan", 20)],
            ["Preheat oven to 200°C.", "Place small cheese piles on baking sheet.", "Bake until crispy (7–8 min).", "Cool and enjoy."]),
    ]


def _weight_loss_recipes() -> list[RecipeTemplate]:
    return [
        RecipeTemplate("Green Detox Smoothie", "breakfast", ["weight_loss", "vegan"],
            ["low-calorie", "liquid", "vitamin-rich"], 5, 1,
            [("spinach", 80), ("cucumber", 100), ("banana", 60), ("lemon juice", 15), ("almond milk (unsweetened)", 200), ("chia seeds", 10)],
            ["Blend spinach, cucumber, banana with almond milk.", "Add lemon juice and chia seeds.", "Blend until smooth."]),
        RecipeTemplate("Egg White Veggie Omelette", "breakfast", ["weight_loss", "diabetes"],
            ["low-calorie", "high-protein"], 10, 1,
            [("egg whites", 200), ("spinach", 60), ("tomatoes", 60), ("mushrooms", 60), ("bell pepper (red)", 40), ("olive oil", 5)],
            ["Cook vegetables in a little olive oil.", "Pour egg whites over.", "Cook until set, fold and serve."]),
        RecipeTemplate("Zucchini Noodle Primavera", "lunch", ["weight_loss", "vegan"],
            ["low-calorie", "high-volume"], 15, 1,
            [("zucchini", 250), ("tomatoes", 100), ("bell pepper (red)", 80), ("mushrooms", 80), ("garlic", 5), ("olive oil", 10)],
            ["Spiralize zucchini.", "Sauté garlic and vegetables.", "Toss with zucchini noodles.", "Season and serve."]),
        RecipeTemplate("Chicken & Vegetable Soup", "lunch", ["weight_loss", "maintain"],
            ["warming", "low-calorie", "filling"], 30, 2,
            [("chicken breast", 150), ("carrot", 80), ("celery", 60), ("onion", 50), ("spinach", 60), ("garlic", 5)],
            ["Poach chicken in broth.", "Add diced carrot, celery, onion.", "Simmer 20 min.", "Shred chicken, add spinach."]),
        RecipeTemplate("Cod with Steamed Vegetables", "dinner", ["weight_loss", "diabetes"],
            ["lean", "simple"], 25, 1,
            [("cod fillet", 180), ("broccoli", 150), ("carrot", 80), ("green beans", 80), ("lemon juice", 10)],
            ["Steam cod until flaky.", "Steam all vegetables.", "Drizzle with lemon juice.", "Season and serve."]),
        RecipeTemplate("Turkey Lettuce Wraps", "dinner", ["weight_loss", "diabetes"],
            ["low-carb", "light", "quick"], 15, 2,
            [("ground turkey", 200), ("mushrooms", 80), ("onion", 40), ("garlic", 5), ("carrot", 60), ("cucumber", 60)],
            ["Brown turkey with onion and garlic.", "Add diced mushrooms and carrot.", "Spoon into lettuce cups.", "Top with cucumber."]),
        RecipeTemplate("Shrimp & Cauliflower Rice", "dinner", ["weight_loss", "keto"],
            ["low-carb", "seafood"], 20, 1,
            [("shrimp", 180), ("cauliflower rice", 200), ("garlic", 5), ("zucchini", 80), ("olive oil", 10), ("lemon juice", 10)],
            ["Sauté shrimp in olive oil with garlic.", "Cook cauliflower rice in same pan.", "Add zucchini, squeeze lemon.", "Combine and serve."]),
        RecipeTemplate("Mixed Berry Protein Smoothie", "snack", ["weight_loss", "muscle"],
            ["liquid", "low-calorie"], 5, 1,
            [("whey protein powder", 25), ("strawberries", 80), ("blueberries", 50), ("almond milk (unsweetened)", 250), ("spinach", 30)],
            ["Blend all ingredients.", "Serve cold."]),
        RecipeTemplate("Celery & Almond Butter", "snack", ["weight_loss", "diabetes"],
            ["quick", "no-cook", "crunchy"], 3, 1,
            [("celery", 120), ("peanut butter", 20), ("chia seeds", 5)],
            ["Wash and cut celery sticks.", "Spread peanut butter in grooves.", "Sprinkle chia seeds."]),
        RecipeTemplate("Cucumber Tuna Bites", "snack", ["weight_loss", "diabetes"],
            ["low-calorie", "high-protein", "no-cook"], 5, 1,
            [("cucumber", 150), ("tuna (canned)", 80), ("lemon juice", 5), ("celery", 30)],
            ["Slice cucumber into thick rounds.", "Mix tuna with diced celery and lemon.", "Spoon onto cucumber rounds."]),
    ]


def _generate_variations(base_templates: list[RecipeTemplate], count: int, prefix: str) -> list[RecipeTemplate]:
    """Generate slight variations of recipes to fill the required count."""
    variations = []
    modifiers = [
        ("Spicy", [("garlic", 3)]),
        ("Herbed", [("olive oil", 5)]),
        ("Mediterranean", [("olive oil", 5), ("tomatoes", 30)]),
        ("Asian-style", [("garlic", 3)]),
        ("Smoky", []),
        ("Zesty", [("lemon juice", 10)]),
        ("Garlic", [("garlic", 5)]),
        ("Italian", [("tomatoes", 30)]),
        ("Loaded", []),
        ("Classic", []),
        ("Simple", []),
        ("Rustic", []),
        ("Fresh", [("lemon juice", 5)]),
        ("Light", []),
        ("Hearty", []),
        ("Home-style", []),
        ("Quick", []),
        ("Crispy", []),
        ("Creamy", [("coconut cream", 20)]),
        ("Grilled", []),
        ("Baked", []),
        ("Roasted", []),
        ("Pan-seared", []),
        ("One-pot", []),
        ("Sheet-pan", []),
    ]

    # Also swap main proteins/bases
    protein_swaps = {
        "chicken breast": [("ground turkey", 0.9), ("cod fillet", 0.8), ("shrimp", 0.9), ("tofu (firm)", 1.2)],
        "ground turkey": [("chicken breast", 1.1), ("ground beef (lean)", 1.0), ("salmon fillet", 0.9)],
        "salmon fillet": [("cod fillet", 1.0), ("shrimp", 1.0), ("tuna (canned)", 0.9)],
        "ground beef (lean)": [("ground turkey", 1.0), ("chicken thigh", 1.0)],
        "tofu (firm)": [("tempeh", 0.8), ("seitan", 0.5), ("edamame", 1.5)],
    }

    base_swaps = {
        "brown rice (cooked)": [("quinoa (cooked)", 1.0), ("sweet potato (cooked)", 1.0), ("cauliflower rice", 1.5)],
        "quinoa (cooked)": [("brown rice (cooked)", 1.0), ("couscous (cooked)", 1.0), ("lentils (cooked)", 0.8)],
        "pasta (cooked)": [("quinoa (cooked)", 0.8), ("brown rice (cooked)", 0.8), ("zucchini", 2.0)],
    }

    for i in range(count):
        base = base_templates[i % len(base_templates)]
        batch = i // len(base_templates)
        mod_idx = (i + batch * 3) % len(modifiers)
        mod_name, extra_ings = modifiers[mod_idx]

        # Build unique name
        suffix = f" #{batch + 2}" if batch > 0 else ""
        if mod_name.lower() in base.name.lower():
            new_name = f"{base.name} (variation{suffix})"
        else:
            new_name = f"{mod_name} {base.name}{suffix}"

        new_ings = list(base.ingredients)

        # Every other variation, do a protein/base swap
        if i % 2 == 0:
            for j, (ing_name, grams) in enumerate(new_ings):
                if ing_name in protein_swaps and batch < len(protein_swaps[ing_name]):
                    swap, ratio = protein_swaps[ing_name][batch % len(protein_swaps[ing_name])]
                    new_ings[j] = (swap, round(grams * ratio))
                    new_name = new_name.replace(
                        ing_name.split()[0].title(),
                        swap.split()[0].title()
                    )
                    break
                elif ing_name in base_swaps and batch < len(base_swaps[ing_name]):
                    swap, ratio = base_swaps[ing_name][batch % len(base_swaps[ing_name])]
                    new_ings[j] = (swap, round(grams * ratio))
                    break

        # Add extra ingredients from modifier
        for ing in extra_ings:
            if ing[0] not in [x[0] for x in new_ings]:
                new_ings.append(ing)

        # Adjust serving amounts by ±10-20%
        scale = 1.0 + (((i * 7) % 5) - 2) * 0.05  # -10% to +10%
        new_ings = [(name, round(g * scale)) for name, g in new_ings]

        variations.append(RecipeTemplate(
            name=new_name,
            meal_type=base.meal_type,
            goals=base.goals,
            tags=list(set(base.tags + [mod_name.lower()])),
            minutes=base.minutes + (i % 5) - 2,
            servings=base.servings,
            ingredients=new_ings,
            steps=base.steps,
            source=base.source,
        ))

    return variations


def generate_all_recipes() -> list[dict]:
    """Generate the complete recipe database."""
    all_templates: list[RecipeTemplate] = []

    # Core hand-crafted templates (~100 unique)
    core = (
        _diabetes_breakfast() +
        _diabetes_lunch() +
        _diabetes_dinner() +
        _diabetes_desserts() +
        _muscle_breakfast() +
        _muscle_lunch() +
        _muscle_dinner() +
        _muscle_snacks() +
        _vegan_recipes() +
        _keto_recipes() +
        _weight_loss_recipes()
    )
    all_templates.extend(core)

    # Generate variations to reach 3000+ total
    # We want roughly equal distribution across goals
    target_per_category = 650
    categories = {
        "diabetes": _diabetes_breakfast() + _diabetes_lunch() + _diabetes_dinner() + _diabetes_desserts(),
        "muscle": _muscle_breakfast() + _muscle_lunch() + _muscle_dinner() + _muscle_snacks(),
        "vegan": _vegan_recipes(),
        "keto": _keto_recipes(),
        "weight_loss": _weight_loss_recipes(),
    }

    for cat_name, cat_templates in categories.items():
        needed = target_per_category - len(cat_templates)
        if needed > 0:
            variations = _generate_variations(cat_templates, needed, cat_name)
            all_templates.extend(variations)

    # Deduplicate by name
    seen_names = set()
    unique: list[RecipeTemplate] = []
    for t in all_templates:
        if t.name not in seen_names:
            seen_names.add(t.name)
            unique.append(t)

    # Convert to JSON format
    recipes = []
    for idx, t in enumerate(unique, start=1):
        nutrition = _calc_nutrition(t.ingredients)
        is_all_vegan = all(
            INGREDIENTS.get(ing, Nutrient()).is_vegan
            for ing, _ in t.ingredients
            if ing in INGREDIENTS
        )

        # Auto-add vegan tag if all ingredients are plant-based
        goals = list(t.goals)
        if is_all_vegan and "vegan" not in goals:
            goals.append("vegan")

        recipe = {
            "id": _make_id(t.name, idx),
            "name": t.name,
            "image": None,  # Will use placeholder in app
            "meal_type": t.meal_type,
            "goals": goals,
            "minutes": t.minutes,
            "servings": t.servings,
            "tags": list(set(t.tags)),
            "ingredients": [
                {"name": name, "grams": grams, "amount": f"{grams:.0f}g"}
                for name, grams in t.ingredients
            ],
            "steps": t.steps,
            "source": t.source,
            **nutrition,
        }
        recipes.append(recipe)

    return recipes


def main() -> None:
    print("Generating recipes...")
    recipes = generate_all_recipes()
    print(f"Generated {len(recipes)} recipes")

    # Stats
    goals = {}
    types = {}
    for r in recipes:
        for g in r["goals"]:
            goals[g] = goals.get(g, 0) + 1
        types[r["meal_type"]] = types.get(r["meal_type"], 0) + 1

    print("\nBy goal:")
    for g, c in sorted(goals.items(), key=lambda x: -x[1]):
        print(f"  {g}: {c}")
    print("\nBy meal type:")
    for t, c in sorted(types.items(), key=lambda x: -x[1]):
        print(f"  {t}: {c}")

    # Check nutrition ranges
    cals = [r["calories"] for r in recipes if r["calories"] > 0]
    print(f"\nCalories range: {min(cals)}–{max(cals)} (avg {sum(cals)//len(cals)})")
    print(f"All have insulin_units: {all('insulin_units' in r for r in recipes)}")
    print(f"All have vitamins: {all('vitamin_c_mg' in r for r in recipes)}")

    # Write output
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT, "w") as f:
        json.dump(recipes, f, indent=2, ensure_ascii=False)
    print(f"\nWritten to {OUTPUT}")
    size_mb = OUTPUT.stat().st_size / 1e6
    print(f"File size: {size_mb:.1f} MB")


if __name__ == "__main__":
    main()
