#!/usr/bin/env python3
"""
fix_nutrition.py
────────────────
• Fixes incorrect image URLs for curated recipes
• Recomputes kcal / protein_g / carbs_g / fat_g / fiber_g / sugar_g for
  EVERY recipe by parsing ingredient amounts and looking up a built-in
  nutrition table (USDA-based values per 100 g of edible food).

Run:
    python3 scripts/fix_nutrition.py
"""

import json
import re
import sys
from pathlib import Path

ROOT  = Path(__file__).resolve().parent.parent
JSON  = ROOT / "assets" / "recipes.json"

# ── Nutrition table: kcal / protein_g / carbs_g / fat_g / fiber_g / sugar_g
# ─────────────────────────────────────────────────────────────────────────────
# All values per 100 g (or 100 ml for liquids, density ≈ 1.0).
# Format: (kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g)
NUTRIENTS = {
    # ── Proteins / Meat / Fish ──────────────────────────────────────────────
    "chicken breast": (165, 31, 0, 3.6, 0, 0),
    "chicken":        (165, 31, 0, 3.6, 0, 0),
    "chicken thigh":  (177, 24, 0, 8.5, 0, 0),
    "ground chicken": (143, 17, 0, 8.1, 0, 0),
    "ground beef":    (254, 17, 0, 20, 0, 0),
    "lean minced beef": (174, 21, 0, 9.5, 0, 0),
    "lean ground beef": (174, 21, 0, 9.5, 0, 0),
    "minced beef":    (254, 17, 0, 20, 0, 0),
    "beef mince":     (254, 17, 0, 20, 0, 0),
    "beef":           (250, 26, 0, 15, 0, 0),
    "steak":          (271, 26, 0, 18, 0, 0),
    "pork":           (242, 21, 0, 17, 0, 0),
    "pork tenderloin":(143, 22, 0, 5.5, 0, 0),
    "bacon":          (541, 37, 1.4, 42, 0, 0),
    "ham":            (145, 21, 1.5, 6, 0, 1.5),
    "sausage":        (301, 12, 2, 27, 0, 1),
    "turkey":         (189, 29, 0, 7.4, 0, 0),
    "ground turkey":  (148, 19, 0, 8.3, 0, 0),
    "lamb":           (294, 25, 0, 21, 0, 0),
    "salmon":         (208, 20, 0, 13, 0, 0),
    "tuna":           (116, 26, 0, 1, 0, 0),
    "shrimp":         (99, 24, 0.2, 0.3, 0, 0),
    "cod":            (82, 18, 0, 0.7, 0, 0),
    "tilapia":        (96, 20, 0, 1.7, 0, 0),
    "sardines":       (208, 25, 0, 11, 0, 0),
    "crab":           (97, 19, 0, 1.5, 0, 0),
    "lobster":        (89, 19, 0, 0.9, 0, 0),
    "scallops":       (88, 17, 2.4, 0.8, 0, 0),
    "mussels":        (86, 12, 3.7, 2.2, 0, 0),
    "egg":            (155, 13, 1.1, 11, 0, 1.1),
    "eggs":           (155, 13, 1.1, 11, 0, 1.1),
    "egg white":      (52, 11, 0.7, 0.2, 0, 0.7),
    "egg yolk":       (322, 16, 3.6, 27, 0, 0.6),

    # ── Dairy ───────────────────────────────────────────────────────────────
    "greek yogurt":         (97, 10, 4, 5, 0, 4),
    "greek yogurt (full-fat)": (97, 10, 4, 5, 0, 4),
    "greek yogurt (low-fat)":  (59, 10, 3.6, 0.4, 0, 3.6),
    "plain yogurt":         (61, 3.5, 4.7, 3.3, 0, 4.7),
    "yogurt":               (61, 3.5, 4.7, 3.3, 0, 4.7),
    "milk":                 (61, 3.2, 4.8, 3.3, 0, 4.8),
    "whole milk":           (61, 3.2, 4.8, 3.3, 0, 4.8),
    "skimmed milk":         (34, 3.4, 4.9, 0.1, 0, 4.9),
    "skim milk":            (34, 3.4, 4.9, 0.1, 0, 4.9),
    "heavy cream":          (340, 2.8, 2.8, 36, 0, 2.8),
    "heavy whipping cream": (340, 2.8, 2.8, 36, 0, 2.8),
    "sour cream":           (193, 2.1, 4.6, 20, 0, 4),
    "cream cheese":         (342, 6, 4, 34, 0, 3.5),
    "cheddar cheese":       (403, 25, 1.3, 33, 0, 0.5),
    "cheddar":              (403, 25, 1.3, 33, 0, 0.5),
    "mozzarella":           (280, 28, 2.2, 17, 0, 1),
    "parmesan":             (431, 38, 4, 29, 0, 0.9),
    "feta":                 (264, 14, 4, 21, 0, 4),
    "cottage cheese":       (98, 11, 3.4, 4.3, 0, 2.7),
    "ricotta":              (174, 11, 3, 13, 0, 0.3),
    "butter":               (717, 0.9, 0.1, 81, 0, 0.1),
    "ghee":                 (900, 0, 0, 100, 0, 0),
    "almond milk":          (15, 0.6, 0.6, 1.2, 0, 0.4),
    "unsweetened almond milk": (15, 0.6, 0.6, 1.2, 0, 0.4),
    "oat milk":             (45, 1, 7, 1, 0.5, 5),
    "soy milk":             (43, 3.3, 3.8, 2.3, 0.3, 2.4),
    "coconut milk":         (197, 2, 6, 21, 0, 3),
    "condensed milk":       (321, 7.9, 54, 8.7, 0, 54),
    "evaporated milk":      (134, 6.8, 10, 7.6, 0, 10),
    "whipped cream":        (257, 1.9, 20, 19, 0, 20),

    # ── Grains / Carbs ───────────────────────────────────────────────────────
    "rolled oats":          (389, 17, 66, 7, 10, 1),
    "oats":                 (389, 17, 66, 7, 10, 1),
    "white rice":           (365, 7, 80, 0.7, 1.3, 0),
    "brown rice":           (370, 8, 77, 3, 3.5, 0),
    "rice":                 (365, 7, 80, 0.7, 1.3, 0),
    "pasta":                (371, 13, 74, 1.5, 2.7, 2.5),
    "spaghetti":            (371, 13, 74, 1.5, 2.7, 2.5),
    "penne":                (371, 13, 74, 1.5, 2.7, 2.5),
    "macaroni":             (371, 13, 74, 1.5, 2.7, 2.5),
    "noodles":              (138, 4.5, 25, 2, 1, 0),
    "bread":                (265, 9, 49, 3.2, 2.7, 5),
    "white bread":          (265, 9, 49, 3.2, 2.7, 5),
    "whole wheat bread":    (247, 13, 41, 4.2, 6, 6),
    "tortilla":             (299, 7.3, 52, 7.3, 2.7, 1.5),
    "whole wheat tortilla": (290, 10, 50, 7, 5, 1),
    "pita bread":           (275, 9, 55, 1.2, 2.2, 0.5),
    "quinoa":               (368, 14, 64, 6, 7, 0),
    "quinoa (cooked)":      (120, 4.4, 22, 1.9, 2.8, 0),
    "couscous":             (376, 13, 77, 0.6, 5, 0),
    "barley":               (354, 12, 73, 2.3, 17, 0.8),
    "bread crumbs":         (395, 13, 72, 5, 3.5, 6),
    "cornstarch":           (381, 0.3, 91, 0.1, 0.9, 0),
    "corn flour":           (361, 6.9, 76, 3.9, 7.3, 0.6),
    "flour":                (364, 10, 76, 1, 2.7, 0.3),
    "all-purpose flour":    (364, 10, 76, 1, 2.7, 0.3),
    "whole wheat flour":    (340, 13, 72, 2.5, 10.7, 0.4),
    "baking powder":        (53, 0, 28, 0, 0, 0),
    "baking soda":          (0, 0, 0, 0, 0, 0),

    # ── Vegetables ──────────────────────────────────────────────────────────
    "broccoli":             (34, 2.8, 7, 0.4, 2.6, 1.7),
    "spinach":              (23, 2.9, 3.6, 0.4, 2.2, 0.4),
    "kale":                 (49, 4.3, 9, 0.9, 2, 2.3),
    "lettuce":              (15, 1.4, 2.9, 0.2, 1.3, 1.2),
    "romaine lettuce":      (17, 1.2, 3.3, 0.3, 2.1, 1.2),
    "cabbage":              (25, 1.3, 5.8, 0.1, 2.5, 3.2),
    "red cabbage":          (31, 1.4, 7, 0.2, 2.1, 3.8),
    "bok choy":             (13, 1.5, 2.2, 0.2, 1, 1.2),
    "carrots":              (41, 0.9, 10, 0.2, 2.8, 4.7),
    "tomatoes":             (18, 0.9, 3.9, 0.2, 1.2, 2.6),
    "tomato":               (18, 0.9, 3.9, 0.2, 1.2, 2.6),
    "cherry tomatoes":      (18, 0.9, 3.9, 0.2, 1.2, 2.6),
    "onion":                (40, 1.1, 9.3, 0.1, 1.7, 4.2),
    "red onion":            (40, 1.1, 9.3, 0.1, 1.7, 4.2),
    "garlic":               (149, 6.4, 33, 0.5, 2.1, 1),
    "bell pepper":          (31, 1, 6, 0.3, 2.1, 4.2),
    "red pepper":           (31, 1, 6, 0.3, 2.1, 4.2),
    "green pepper":         (20, 0.9, 4.6, 0.2, 1.7, 2.4),
    "cucumber":             (15, 0.65, 3.6, 0.1, 0.5, 1.7),
    "zucchini":             (17, 1.2, 3.1, 0.3, 1, 2.5),
    "eggplant":             (25, 1, 6, 0.2, 3, 3.5),
    "mushroom":             (22, 3.1, 3.3, 0.3, 1, 2),
    "mushrooms":            (22, 3.1, 3.3, 0.3, 1, 2),
    "portobello mushroom":  (22, 3.1, 3.3, 0.3, 1, 2),
    "celery":               (16, 0.7, 3, 0.2, 1.6, 1.3),
    "avocado":              (160, 2, 9, 15, 6.7, 0.7),
    "sweet potato":         (86, 1.6, 20, 0.1, 3, 4.2),
    "potato":               (77, 2, 17, 0.1, 2.2, 0.8),
    "white potato":         (77, 2, 17, 0.1, 2.2, 0.8),
    "corn":                 (86, 3.3, 19, 1.4, 2.7, 3.2),
    "peas":                 (81, 5.4, 14, 0.4, 5.5, 5.7),
    "green beans":          (31, 1.8, 7, 0.1, 2.7, 3.3),
    "asparagus":            (20, 2.2, 3.9, 0.1, 2.1, 1.9),
    "artichoke":            (53, 3, 12, 0.2, 5.4, 1),
    "beets":                (43, 1.6, 10, 0.2, 2.8, 6.8),
    "leek":                 (61, 1.5, 14, 0.3, 1.8, 3.9),
    "cauliflower":          (25, 1.9, 5, 0.3, 2, 1.9),
    "butternut squash":     (45, 1, 12, 0.1, 2, 2.2),
    "pumpkin":              (26, 1, 6.5, 0.1, 0.5, 2.8),
    "jalapeno":             (29, 0.9, 6.5, 0.4, 2.5, 4.1),
    "chili pepper":         (40, 1.9, 8.8, 0.4, 1.5, 5.3),

    # ── Legumes / Beans ─────────────────────────────────────────────────────
    "lentils":              (116, 9, 20, 0.4, 7.9, 1.8),
    "red lentils":          (116, 9, 20, 0.4, 7.9, 1.8),
    "chickpeas":            (164, 8.9, 27, 2.6, 7.6, 4.8),
    "black beans":          (132, 8.9, 24, 0.5, 8.7, 0.3),
    "kidney beans":         (127, 8.7, 23, 0.5, 6.4, 0.3),
    "pinto beans":          (143, 9, 26, 0.7, 9, 0.3),
    "white beans":          (139, 9.7, 25, 0.4, 6.3, 0.3),
    "edamame":              (122, 11, 9.9, 5.2, 5.2, 2.2),
    "tofu":                 (76, 8, 1.9, 4.8, 0.3, 0.7),
    "tofu (firm)":          (76, 8, 1.9, 4.8, 0.3, 0.7),
    "tempeh":               (193, 19, 9.4, 11, 0, 0),

    # ── Fruits ──────────────────────────────────────────────────────────────
    "apple":                (52, 0.3, 14, 0.2, 2.4, 10),
    "banana":               (89, 1.1, 23, 0.3, 2.6, 12),
    "blueberry":            (57, 0.7, 14, 0.3, 2.4, 10),
    "blueberries":          (57, 0.7, 14, 0.3, 2.4, 10),
    "strawberry":           (32, 0.7, 7.7, 0.3, 2, 4.9),
    "strawberries":         (32, 0.7, 7.7, 0.3, 2, 4.9),
    "mixed berries":        (50, 0.5, 12, 0.4, 2.5, 7),
    "raspberry":            (52, 1.2, 12, 0.7, 6.5, 4.4),
    "raspberries":          (52, 1.2, 12, 0.7, 6.5, 4.4),
    "blackberry":           (43, 1.4, 10, 0.5, 5.3, 4.9),
    "blackberries":         (43, 1.4, 10, 0.5, 5.3, 4.9),
    "mango":                (60, 0.8, 15, 0.4, 1.6, 13.7),
    "pineapple":            (50, 0.5, 13, 0.1, 1.4, 10),
    "orange":               (47, 0.9, 12, 0.1, 2.4, 9.4),
    "lemon":                (29, 1.1, 9.3, 0.3, 2.8, 2.5),
    "lime":                 (30, 0.7, 10, 0.2, 2.8, 1.7),
    "grape":                (69, 0.7, 18, 0.2, 0.9, 15.5),
    "grapes":               (69, 0.7, 18, 0.2, 0.9, 15.5),
    "peach":                (39, 0.9, 10, 0.3, 1.5, 8.4),
    "pear":                 (57, 0.4, 15, 0.1, 3.1, 9.8),
    "kiwi":                 (61, 1.1, 15, 0.5, 3, 9),
    "watermelon":           (30, 0.6, 7.6, 0.2, 0.4, 6.2),
    "melon":                (34, 0.8, 8, 0.2, 0.9, 7.9),
    "cherry":               (63, 1.1, 16, 0.2, 2.1, 12.8),
    "cherries":             (63, 1.1, 16, 0.2, 2.1, 12.8),
    "pomegranate":          (83, 1.7, 19, 1.2, 4, 13.7),
    "dates":                (282, 2.5, 75, 0.4, 8, 63),
    "dried cranberries":    (308, 0.1, 82, 1.4, 5.3, 72),
    "raisins":              (299, 3.1, 79, 0.5, 3.7, 59),

    # ── Nuts / Seeds ────────────────────────────────────────────────────────
    "almonds":              (579, 21, 22, 50, 12.5, 4.4),
    "almond":               (579, 21, 22, 50, 12.5, 4.4),
    "walnuts":              (654, 15, 14, 65, 6.7, 2.6),
    "walnut":               (654, 15, 14, 65, 6.7, 2.6),
    "cashews":              (553, 18, 30, 44, 3.3, 5.9),
    "pecans":               (691, 9.2, 14, 72, 9.6, 3.97),
    "peanuts":              (567, 26, 16, 49, 8.5, 4),
    "peanut butter":        (588, 25, 20, 50, 6, 9.2),
    "almond butter":        (614, 21, 19, 56, 10, 3.8),
    "hazelnuts":            (628, 15, 17, 61, 9.7, 4.3),
    "macadamia nuts":       (718, 7.9, 14, 76, 8.6, 4.6),
    "pine nuts":            (673, 14, 13, 68, 3.7, 3.6),
    "pistachios":           (562, 20, 28, 45, 10.3, 7.7),
    "sunflower seeds":      (584, 21, 20, 51, 8.6, 2.6),
    "pumpkin seeds":        (559, 30, 11, 49, 6, 1.4),
    "chia seeds":           (486, 17, 42, 31, 34, 0),
    "flaxseeds":            (534, 18, 29, 42, 27, 1.5),
    "sesame seeds":         (573, 17, 23, 50, 11.8, 0.3),
    "hemp seeds":           (553, 32, 8.7, 49, 4, 1.5),

    # ── Oils / Fats ─────────────────────────────────────────────────────────
    "olive oil":            (884, 0, 0, 100, 0, 0),
    "vegetable oil":        (884, 0, 0, 100, 0, 0),
    "canola oil":           (884, 0, 0, 100, 0, 0),
    "coconut oil":          (862, 0, 0, 100, 0, 0),
    "sesame oil":           (884, 0, 0, 100, 0, 0),
    "avocado oil":          (884, 0, 0, 100, 0, 0),

    # ── Sweeteners ──────────────────────────────────────────────────────────
    "honey":                (304, 0.3, 82, 0, 0.2, 82),
    "maple syrup":          (260, 0, 67, 0.1, 0, 60),
    "sugar":                (387, 0, 100, 0, 0, 100),
    "brown sugar":          (380, 0, 98, 0, 0, 97),
    "powdered sugar":       (389, 0, 100, 0, 0, 98),
    "agave":                (310, 0.1, 76, 0.1, 0, 68),
    "stevia":               (0, 0, 0, 0, 0, 0),

    # ── Sauces / Condiments ──────────────────────────────────────────────────
    "soy sauce":            (60, 10, 7, 0, 0.8, 1.7),
    "tomato sauce":         (29, 1.4, 7, 0.3, 1.5, 4),
    "tomato paste":         (82, 4.5, 18, 0.5, 4.1, 12),
    "ketchup":              (112, 1.5, 27, 0.1, 0.7, 22),
    "mustard":              (66, 4.4, 6, 3.7, 3.3, 0.9),
    "mayonnaise":           (680, 1, 0.6, 75, 0, 0.4),
    "worcestershire sauce": (78, 0, 20, 0, 0, 19),
    "hot sauce":            (11, 0.5, 2, 0, 0, 0.5),
    "fish sauce":           (35, 5, 3.6, 0, 0, 3.6),
    "oyster sauce":         (104, 3.5, 24, 0.1, 0.6, 10),
    "teriyaki sauce":       (89, 5.3, 17, 0, 0.1, 13),
    "hoisin sauce":         (220, 4, 42, 4.5, 2, 25),
    "balsamic vinegar":     (88, 0.5, 17, 0, 0, 15),
    "apple cider vinegar":  (21, 0, 0.9, 0, 0, 0.4),
    "white wine vinegar":   (18, 0, 0.04, 0, 0, 0),
    "red wine":             (85, 0.1, 2.6, 0, 0, 0.6),
    "white wine":           (82, 0.1, 2.6, 0, 0, 0.8),

    # ── Spices / Herbs (small amounts, low impact) ───────────────────────────
    "salt":                 (0, 0, 0, 0, 0, 0),
    "pepper":               (251, 10, 64, 3.3, 26, 0.6),
    "black pepper":         (251, 10, 64, 3.3, 26, 0.6),
    "cumin":                (375, 18, 44, 22, 10.5, 2.3),
    "paprika":              (282, 14, 54, 13, 34, 10),
    "turmeric":             (312, 9.7, 67, 3.3, 21, 3.2),
    "cinnamon":             (247, 4, 81, 1.2, 53, 2.2),
    "oregano":              (265, 9, 69, 4.3, 42, 4.1),
    "basil":                (23, 3.2, 2.7, 0.6, 1.6, 0.3),
    "thyme":                (101, 5.6, 24, 1.7, 14, 0),
    "rosemary":             (131, 3.3, 21, 5.9, 14, 0),
    "ginger":               (80, 1.8, 18, 0.8, 2, 1.7),
    "chili powder":         (282, 13, 50, 14, 34, 7.7),
    "cayenne":              (318, 12, 57, 17, 27, 10),
    "nutmeg":               (525, 5.8, 49, 36, 20, 28),
    "vanilla extract":      (288, 0.1, 13, 0.1, 0, 12.7),
    "bay leaf":             (313, 7.6, 75, 8.4, 26, 2),
    "parsley":              (36, 3, 6.3, 0.8, 3.3, 0.9),
    "cilantro":             (23, 2.1, 3.7, 0.5, 2.8, 0.9),
    "dill":                 (43, 3.5, 7, 1.1, 2.1, 0),
    "mint":                 (70, 3.8, 15, 0.9, 8, 0),
    "chives":               (30, 3.3, 4.4, 0.7, 2.5, 1.9),

    # ── Bakery / Misc ────────────────────────────────────────────────────────
    "cocoa powder":         (228, 20, 58, 14, 37, 1.8),
    "unsweetened cocoa":    (228, 20, 58, 14, 37, 1.8),
    "dark chocolate":       (579, 5, 46, 43, 11, 24),
    "chocolate chips":      (478, 5.5, 63, 27, 6, 57),
    "white chocolate":      (539, 5.9, 59, 30, 0, 59),
    "yeast":                (325, 45, 38, 7.6, 26, 0),
    "gelatin":              (335, 86, 0, 0, 0, 0),
    "corn syrup":           (282, 0, 76, 0, 0, 30),
    "miso":                 (199, 12, 26, 6, 5.4, 6.2),
    "tahini":               (595, 17, 26, 54, 9.3, 0.5),
    "nutritional yeast":    (325, 50, 38, 7.5, 20, 0),

    # ── Stocks / Broths ──────────────────────────────────────────────────────
    "chicken broth":        (7, 1.2, 0.5, 0.1, 0, 0),
    "beef broth":           (7, 1.2, 0.5, 0.1, 0, 0),
    "vegetable broth":      (7, 0.5, 1, 0, 0, 0.5),
    "chicken stock":        (7, 1.2, 0.5, 0.1, 0, 0),
    "beef stock":           (7, 1.2, 0.5, 0.1, 0, 0),
    "water":                (0, 0, 0, 0, 0, 0),

    # ── Misc ─────────────────────────────────────────────────────────────────
    "lemon juice":          (22, 0.4, 6.9, 0.2, 0.3, 2.5),
    "lime juice":           (25, 0.4, 8.4, 0.1, 0.4, 1.7),
    "orange juice":         (45, 0.7, 10.4, 0.2, 0.2, 8.4),
    "apple juice":          (46, 0.1, 11.3, 0.1, 0.2, 9.6),
    "protein powder":       (380, 75, 15, 5, 2, 5),
    "whey protein":         (380, 75, 10, 5, 0, 5),
    "beef jerky":           (410, 35, 20, 25, 1, 12),
}

# ── Unit → grams conversion ───────────────────────────────────────────────────
# Volume measures use approximate densities for common foods.
UNIT_TO_G = {
    "g": 1.0, "gram": 1.0, "grams": 1.0,
    "kg": 1000.0, "kilogram": 1000.0,
    "oz": 28.35, "ounce": 28.35, "ounces": 28.35,
    "lb": 453.6, "pound": 453.6, "pounds": 453.6,
    "ml": 1.0, "milliliter": 1.0, "millilitre": 1.0, "milliliters": 1.0,
    "l": 1000.0, "liter": 1000.0, "litre": 1000.0,
    "cup": 240.0, "cups": 240.0,
    "tbsp": 15.0, "tablespoon": 15.0, "tablespoons": 15.0,
    "tsp": 5.0, "teaspoon": 5.0, "teaspoons": 5.0,
    "clove": 5.0, "cloves": 5.0,   # garlic clove ≈ 5g
    "slice": 30.0, "slices": 30.0,
    "piece": 100.0, "pieces": 100.0,
    "strip": 20.0, "strips": 20.0,
    "stalk": 40.0, "stalks": 40.0,
    "sprig": 2.0, "sprigs": 2.0,
    "bunch": 100.0, "handful": 30.0,
    "can": 400.0, "cans": 400.0,
    "jar": 300.0, "jars": 300.0,
    "packet": 30.0, "sachet": 10.0,
    "pinch": 0.5, "dash": 1.0,
}

# Per-ingredient cup-weight overrides (dense/light solids deviate from 240g)
CUP_WEIGHTS = {
    "flour": 125, "all-purpose flour": 125, "whole wheat flour": 125,
    "sugar": 200, "brown sugar": 200, "powdered sugar": 120,
    "rolled oats": 90, "oats": 90,
    "rice": 185, "white rice": 185, "brown rice": 195, "quinoa": 170,
    "almonds": 100, "walnuts": 100, "cashews": 130, "peanuts": 145,
    "raisins": 165, "dates": 178, "blueberries": 148, "strawberries": 150,
    "mixed berries": 150, "raspberries": 123, "blackberries": 150,
    "spinach": 30, "kale": 67, "lettuce": 47, "romaine lettuce": 47,
    "lentils": 200, "chickpeas": 200, "black beans": 180,
    "kidney beans": 185, "pinto beans": 195,
    "bread crumbs": 115, "cocoa powder": 85, "coconut": 80,
    "chocolate chips": 170, "butternut squash": 140,
    "tomatoes": 180, "cherry tomatoes": 149, "corn": 154,
    "peas": 160, "broccoli": 91,
}

# ── Helpers ───────────────────────────────────────────────────────────────────

_NUMBER = re.compile(
    r'(\d+)\s*/\s*(\d+)'          # fraction like 1/2
    r'|(\d+\.?\d*)'               # decimal / int
)

def _parse_number(s: str) -> float:
    """Return numeric value of s, or 1.0 if not parseable."""
    m = _NUMBER.search(s)
    if not m:
        return 1.0
    if m.group(1) and m.group(2):
        return int(m.group(1)) / int(m.group(2))
    return float(m.group(3))

def _ingredient_key(name: str):  # -> str | None
    """Find the best NUTRIENTS key for a given ingredient name."""
    n = name.lower().strip()
    # Exact match
    if n in NUTRIENTS:
        return n
    # Try stripping parenthetical e.g. "Greek yogurt (full-fat)"
    no_paren = re.sub(r'\s*\(.*?\)', '', n).strip()
    if no_paren in NUTRIENTS:
        return no_paren
    # Partial match: find key that appears inside the ingredient string
    # (longest match first to prefer "chicken breast" over "chicken")
    candidates = sorted(
        (k for k in NUTRIENTS if k in n),
        key=lambda k: -len(k),
    )
    if candidates:
        return candidates[0]
    # Reverse: ingredient string inside key
    candidates = sorted(
        (k for k in NUTRIENTS if n in k),
        key=lambda k: len(k),
    )
    if candidates:
        return candidates[0]
    return None

_MASS_VOL = {
    "g", "gram", "grams", "kg", "kilogram",
    "oz", "ounce", "ounces", "lb", "pound", "pounds",
    "ml", "milliliter", "millilitre", "milliliters", "l", "liter", "litre",
}
_COOKING = {
    "cup", "cups", "tbsp", "tablespoon", "tablespoons",
    "tsp", "teaspoon", "teaspoons",
}
_SKIP_WORDS = {
    "topping", "garnish", "to taste", "as needed", "optional",
    "for serving", "for garnish", "as required", "to serve",
}

def _amount_to_grams(amount: str, ingredient_name: str) -> float:
    """Convert an ingredient amount string to approximate grams.

    Parsing priority:
      1. Explicit mass/volume (g, kg, ml, oz, lb…) – overrides any container
         suffix like "400g can".
      2. Cooking measures (cup, tbsp, tsp).
      3. Container / count units (can, slice, clove…).
      4. Bare number > 5 → treat as grams; bare number ≤ 5 → whole items × 150g.
    """
    if not amount:
        return 100.0
    a = amount.lower().strip()

    # Non-numeric qualifiers → garnish-level amount
    if any(w in a for w in _SKIP_WORDS):
        return 10.0
    if "pinch" in a:
        return 0.5
    if "dash" in a:
        return 1.0

    # ── Strip dual-unit notation like "75g/3oz" or "200g/7oz" ────────────────
    # TheMealDB often provides both metric and imperial separated by /.
    # Keep only the first unit specification.
    dual = re.match(r'^([\d./\s]+\s*[a-z]+)\s*/\s*[\d./\s]+\s*[a-z¾½¼]+', a)
    if dual:
        a = dual.group(1).strip()

    qty = _parse_number(a)

    # ── Priority 1: mass / volume units ──────────────────────────────────────
    for unit in sorted(_MASS_VOL, key=lambda u: -len(u)):
        # Accept "400g" (no space) or "400 g"
        if re.search(r'[\d]\s*' + re.escape(unit) + r'(\b|$)', a):
            return min(qty * UNIT_TO_G[unit], 2000.0)

    # ── Priority 2: cooking volume measures ──────────────────────────────────
    for unit in sorted(_COOKING, key=lambda u: -len(u)):
        if re.search(r'\b' + re.escape(unit) + r'\b', a):
            grams_per_unit = UNIT_TO_G[unit]
            if unit in ("cup", "cups"):
                ikey = _ingredient_key(ingredient_name) or ""
                for key, w in CUP_WEIGHTS.items():
                    if key in ingredient_name.lower() or key == ikey:
                        grams_per_unit = w
                        break
            return min(qty * grams_per_unit, 2000.0)

    # ── Priority 3: container / count units ──────────────────────────────────
    remaining = {k: v for k, v in UNIT_TO_G.items()
                 if k not in _MASS_VOL and k not in _COOKING}
    for unit in sorted(remaining, key=lambda u: -len(u)):
        if re.search(r'\b' + re.escape(unit) + r'\b', a):
            return min(qty * remaining[unit], 2000.0)

    # ── No unit found ─────────────────────────────────────────────────────────
    if qty > 5:
        return min(qty, 2000.0)   # likely already in grams
    elif qty > 0:
        return qty * 150.0        # whole items (onion, egg, etc.)
    return 100.0

def compute_macros(ingredients) -> dict:
    """Return {calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g} for a
    recipe (total for all servings)."""
    kcal = prot = carb = fat = fiber = sugar = 0.0
    for ing in ingredients:
        name   = ing.get("name", "")
        amount = ing.get("amount", "")
        key    = _ingredient_key(name)
        if key is None:
            continue
        grams = _amount_to_grams(amount, name)
        k, p, c, f, fi, s = NUTRIENTS[key]
        factor = grams / 100.0
        kcal  += k  * factor
        prot  += p  * factor
        carb  += c  * factor
        fat   += f  * factor
        fiber += fi * factor
        sugar += s  * factor
    return {
        "calories":  round(kcal),
        "protein_g": round(prot, 1),
        "carbs_g":   round(carb, 1),
        "fat_g":     round(fat, 1),
        "fiber_g":   round(fiber, 1),
        "sugar_g":   round(sugar, 1),
    }

# ── Known-bad images → cleared (will show emoji placeholder in app) ───────────
# Keys are recipe names that have wrong/mismatched images.
CLEAR_IMAGES = {
    "Greek Yogurt with Berries & Walnuts",
    "Overnight Oats with Apple & Cinnamon",
}

# Good replacement images from TheMealDB for curated recipes where we know
# the correct meal ID.  Format: "Recipe Name": "https://…"
REPLACE_IMAGES = {
    "Greek Yogurt with Berries & Walnuts":
        "https://images.unsplash.com/photo-1488477181946-6428a0291777?w=400&fit=crop",
    "Overnight Oats with Apple & Cinnamon":
        "https://images.unsplash.com/photo-1517673408408-2b7a8c5e9a77?w=400&fit=crop",
}

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    if not JSON.exists():
        print(f"ERROR: {JSON} not found", file=sys.stderr)
        sys.exit(1)

    with open(JSON, encoding="utf-8") as fh:
        recipes = json.load(fh)

    updated_images   = 0
    updated_macros   = 0
    skipped_no_ingr  = 0
    zero_cal_count   = 0
    low_cal_count    = 0

    for r in recipes:
        name = r.get("name", "")

        # ── Fix images ────────────────────────────────────────────────────
        if name in REPLACE_IMAGES:
            r["image"] = REPLACE_IMAGES[name]
            updated_images += 1

        # ── Recompute nutrition from ingredients ──────────────────────────
        ingredients = r.get("ingredients", [])
        if not ingredients:
            skipped_no_ingr += 1
            continue

        macros = compute_macros(ingredients)

        # Sanity checks: if computed calories are too low it usually means
        # most ingredients weren't found or have very small amounts.
        # In that case keep old values if they were reasonable.
        old_kcal = r.get("calories", 0)
        new_kcal = macros["calories"]

        if new_kcal < 50:
            zero_cal_count += 1
            # Keep old value if it was non-zero and reasonable
            if old_kcal >= 50:
                continue
        elif new_kcal < 150 and old_kcal > 200:
            # Suspiciously low – probably too many ingredients not found.
            # Keep old value.
            low_cal_count += 1
            continue
        else:
            r.update(macros)
            updated_macros += 1

    with open(JSON, "w", encoding="utf-8") as fh:
        json.dump(recipes, fh, ensure_ascii=False, indent=2)

    print(f"Done.")
    print(f"  Images updated  : {updated_images}")
    print(f"  Macros updated  : {updated_macros}/{len(recipes)}")
    print(f"  No ingredients  : {skipped_no_ingr}")
    print(f"  Kept old (low)  : {zero_cal_count + low_cal_count}")

    # Show a few spot checks
    names_to_check = [
        "Greek Yogurt with Berries & Walnuts",
        "Overnight Oats with Apple & Cinnamon",
        "Grilled Chicken Breast",
        "Spaghetti Bolognese",
    ]
    print("\nSpot checks:")
    for r in recipes:
        if r["name"] in names_to_check:
            print(f"  {r['name']}: {r['calories']} kcal | P{r['protein_g']} C{r['carbs_g']} F{r['fat_g']}")
            print(f"    image: {r.get('image', 'null')[:80] if r.get('image') else 'null'}")

if __name__ == "__main__":
    main()
