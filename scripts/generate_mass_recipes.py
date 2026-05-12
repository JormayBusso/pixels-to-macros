#!/usr/bin/env python3
"""Generate ~3500 recipes across all goals and meal types.

Each recipe has realistic nutrition data computed from ingredient composition,
appropriate goal tags, and curated image URLs from free/open sources.

Usage:
    python scripts/generate_mass_recipes.py
"""
import json, hashlib, math, random, pathlib, copy

ROOT = pathlib.Path(__file__).resolve().parent.parent
RECIPES_PATH = ROOT / "assets" / "recipes.json"

random.seed(42)  # reproducible

# ─── Ingredient database (per 100 g) ─────────────────────────────────────────

INGREDIENTS = {
    # Proteins
    "chicken breast": {"cal": 165, "p": 31, "c": 0, "f": 3.6, "fiber": 0, "sugar": 0, "gi": 0},
    "chicken thigh": {"cal": 209, "p": 26, "c": 0, "f": 10.9, "fiber": 0, "sugar": 0, "gi": 0},
    "ground chicken": {"cal": 170, "p": 20, "c": 0, "f": 9.3, "fiber": 0, "sugar": 0, "gi": 0},
    "turkey breast": {"cal": 135, "p": 30, "c": 0, "f": 1, "fiber": 0, "sugar": 0, "gi": 0},
    "ground turkey": {"cal": 170, "p": 21, "c": 0, "f": 9.4, "fiber": 0, "sugar": 0, "gi": 0},
    "beef steak": {"cal": 271, "p": 26, "c": 0, "f": 18, "fiber": 0, "sugar": 0, "gi": 0},
    "ground beef": {"cal": 250, "p": 26, "c": 0, "f": 15, "fiber": 0, "sugar": 0, "gi": 0},
    "beef sirloin": {"cal": 207, "p": 28, "c": 0, "f": 10, "fiber": 0, "sugar": 0, "gi": 0},
    "pork tenderloin": {"cal": 143, "p": 26, "c": 0, "f": 3.5, "fiber": 0, "sugar": 0, "gi": 0},
    "pork chop": {"cal": 231, "p": 25, "c": 0, "f": 14, "fiber": 0, "sugar": 0, "gi": 0},
    "bacon": {"cal": 541, "p": 37, "c": 1.4, "f": 42, "fiber": 0, "sugar": 0, "gi": 0},
    "salmon": {"cal": 208, "p": 20, "c": 0, "f": 13, "fiber": 0, "sugar": 0, "gi": 0},
    "tuna": {"cal": 130, "p": 29, "c": 0, "f": 1, "fiber": 0, "sugar": 0, "gi": 0},
    "shrimp": {"cal": 99, "p": 24, "c": 0.2, "f": 0.3, "fiber": 0, "sugar": 0, "gi": 0},
    "cod": {"cal": 82, "p": 18, "c": 0, "f": 0.7, "fiber": 0, "sugar": 0, "gi": 0},
    "tilapia": {"cal": 96, "p": 20, "c": 0, "f": 1.7, "fiber": 0, "sugar": 0, "gi": 0},
    "sardines": {"cal": 208, "p": 25, "c": 0, "f": 11, "fiber": 0, "sugar": 0, "gi": 0},
    "eggs": {"cal": 155, "p": 13, "c": 1.1, "f": 11, "fiber": 0, "sugar": 1.1, "gi": 0},
    "egg whites": {"cal": 52, "p": 11, "c": 0.7, "f": 0.2, "fiber": 0, "sugar": 0.7, "gi": 0},
    "tofu": {"cal": 76, "p": 8, "c": 1.9, "f": 4.8, "fiber": 0.3, "sugar": 0.6, "gi": 15},
    "tempeh": {"cal": 192, "p": 20, "c": 7.6, "f": 11, "fiber": 0, "sugar": 0, "gi": 15},
    "seitan": {"cal": 370, "p": 75, "c": 14, "f": 2, "fiber": 1, "sugar": 0, "gi": 25},
    "cottage cheese": {"cal": 98, "p": 11, "c": 3.4, "f": 4.3, "fiber": 0, "sugar": 2.7, "gi": 10},
    "greek yogurt": {"cal": 59, "p": 10, "c": 3.6, "f": 0.7, "fiber": 0, "sugar": 3.2, "gi": 11},
    "whey protein": {"cal": 400, "p": 80, "c": 8, "f": 3, "fiber": 0, "sugar": 3, "gi": 10},
    "plant protein powder": {"cal": 380, "p": 70, "c": 12, "f": 5, "fiber": 3, "sugar": 2, "gi": 15},
    # Dairy & fats
    "cheddar cheese": {"cal": 403, "p": 25, "c": 1.3, "f": 33, "fiber": 0, "sugar": 0.5, "gi": 0},
    "mozzarella": {"cal": 280, "p": 28, "c": 2.2, "f": 17, "fiber": 0, "sugar": 1, "gi": 0},
    "parmesan": {"cal": 431, "p": 38, "c": 4.1, "f": 29, "fiber": 0, "sugar": 0.9, "gi": 0},
    "feta cheese": {"cal": 264, "p": 14, "c": 4, "f": 21, "fiber": 0, "sugar": 4, "gi": 0},
    "cream cheese": {"cal": 342, "p": 6, "c": 4, "f": 34, "fiber": 0, "sugar": 3.8, "gi": 0},
    "butter": {"cal": 717, "p": 0.9, "c": 0.1, "f": 81, "fiber": 0, "sugar": 0.1, "gi": 0},
    "olive oil": {"cal": 884, "p": 0, "c": 0, "f": 100, "fiber": 0, "sugar": 0, "gi": 0},
    "coconut oil": {"cal": 862, "p": 0, "c": 0, "f": 100, "fiber": 0, "sugar": 0, "gi": 0},
    "avocado oil": {"cal": 884, "p": 0, "c": 0, "f": 100, "fiber": 0, "sugar": 0, "gi": 0},
    "whole milk": {"cal": 61, "p": 3.2, "c": 4.8, "f": 3.3, "fiber": 0, "sugar": 5, "gi": 27},
    "almond milk": {"cal": 17, "p": 0.6, "c": 0.6, "f": 1.5, "fiber": 0, "sugar": 0, "gi": 25},
    "coconut milk": {"cal": 230, "p": 2.3, "c": 5.5, "f": 24, "fiber": 0, "sugar": 3.3, "gi": 0},
    "heavy cream": {"cal": 340, "p": 2, "c": 3, "f": 36, "fiber": 0, "sugar": 3, "gi": 0},
    "sour cream": {"cal": 198, "p": 2.4, "c": 4.6, "f": 19.4, "fiber": 0, "sugar": 3.4, "gi": 0},
    # Grains & carbs
    "white rice": {"cal": 130, "p": 2.7, "c": 28, "f": 0.3, "fiber": 0.4, "sugar": 0, "gi": 73},
    "brown rice": {"cal": 123, "p": 2.6, "c": 26, "f": 1, "fiber": 1.8, "sugar": 0.4, "gi": 50},
    "quinoa": {"cal": 120, "p": 4.4, "c": 21, "f": 1.9, "fiber": 2.8, "sugar": 0.9, "gi": 53},
    "oats": {"cal": 389, "p": 17, "c": 66, "f": 7, "fiber": 11, "sugar": 1, "gi": 55},
    "whole wheat bread": {"cal": 247, "p": 13, "c": 41, "f": 3.4, "fiber": 7, "sugar": 6, "gi": 54},
    "white bread": {"cal": 265, "p": 9, "c": 49, "f": 3.2, "fiber": 2.7, "sugar": 5, "gi": 75},
    "whole wheat pasta": {"cal": 124, "p": 5.3, "c": 27, "f": 0.5, "fiber": 3.9, "sugar": 0.6, "gi": 42},
    "white pasta": {"cal": 131, "p": 5, "c": 25, "f": 1.1, "fiber": 1.8, "sugar": 0.6, "gi": 55},
    "sweet potato": {"cal": 86, "p": 1.6, "c": 20, "f": 0.1, "fiber": 3, "sugar": 4.2, "gi": 44},
    "potato": {"cal": 77, "p": 2, "c": 17, "f": 0.1, "fiber": 2.2, "sugar": 0.8, "gi": 78},
    "tortilla (whole wheat)": {"cal": 306, "p": 10, "c": 50, "f": 8, "fiber": 5, "sugar": 3, "gi": 45},
    "tortilla (corn)": {"cal": 218, "p": 5.7, "c": 44, "f": 2.9, "fiber": 5.4, "sugar": 0.8, "gi": 52},
    "couscous": {"cal": 112, "p": 3.8, "c": 23, "f": 0.2, "fiber": 1.4, "sugar": 0.1, "gi": 65},
    "bulgur": {"cal": 83, "p": 3, "c": 19, "f": 0.2, "fiber": 4.5, "sugar": 0.1, "gi": 48},
    "lentils": {"cal": 116, "p": 9, "c": 20, "f": 0.4, "fiber": 7.9, "sugar": 1.8, "gi": 32},
    "chickpeas": {"cal": 164, "p": 9, "c": 27, "f": 2.6, "fiber": 7.6, "sugar": 4.8, "gi": 28},
    "black beans": {"cal": 132, "p": 8.9, "c": 24, "f": 0.5, "fiber": 8.7, "sugar": 0.3, "gi": 30},
    "kidney beans": {"cal": 127, "p": 9, "c": 22, "f": 0.5, "fiber": 6.4, "sugar": 0.3, "gi": 24},
    "edamame": {"cal": 121, "p": 12, "c": 8.9, "f": 5.2, "fiber": 5.2, "sugar": 2.2, "gi": 18},
    # Vegetables
    "broccoli": {"cal": 34, "p": 2.8, "c": 7, "f": 0.4, "fiber": 2.6, "sugar": 1.7, "gi": 15},
    "spinach": {"cal": 23, "p": 2.9, "c": 3.6, "f": 0.4, "fiber": 2.2, "sugar": 0.4, "gi": 15},
    "kale": {"cal": 49, "p": 4.3, "c": 9, "f": 0.9, "fiber": 3.6, "sugar": 2.3, "gi": 15},
    "bell pepper": {"cal": 31, "p": 1, "c": 6, "f": 0.3, "fiber": 2.1, "sugar": 4.2, "gi": 15},
    "tomato": {"cal": 18, "p": 0.9, "c": 3.9, "f": 0.2, "fiber": 1.2, "sugar": 2.6, "gi": 15},
    "cucumber": {"cal": 15, "p": 0.7, "c": 3.6, "f": 0.1, "fiber": 0.5, "sugar": 1.7, "gi": 15},
    "zucchini": {"cal": 17, "p": 1.2, "c": 3.1, "f": 0.3, "fiber": 1, "sugar": 2.5, "gi": 15},
    "cauliflower": {"cal": 25, "p": 1.9, "c": 5, "f": 0.3, "fiber": 2, "sugar": 1.9, "gi": 15},
    "asparagus": {"cal": 20, "p": 2.2, "c": 3.9, "f": 0.1, "fiber": 2.1, "sugar": 1.9, "gi": 15},
    "green beans": {"cal": 31, "p": 1.8, "c": 7, "f": 0.2, "fiber": 2.7, "sugar": 3.3, "gi": 15},
    "mushrooms": {"cal": 22, "p": 3.1, "c": 3.3, "f": 0.3, "fiber": 1, "sugar": 2, "gi": 15},
    "onion": {"cal": 40, "p": 1.1, "c": 9.3, "f": 0.1, "fiber": 1.7, "sugar": 4.2, "gi": 10},
    "garlic": {"cal": 149, "p": 6.4, "c": 33, "f": 0.5, "fiber": 2.1, "sugar": 1, "gi": 10},
    "carrots": {"cal": 41, "p": 0.9, "c": 10, "f": 0.2, "fiber": 2.8, "sugar": 4.7, "gi": 39},
    "celery": {"cal": 14, "p": 0.7, "c": 3, "f": 0.2, "fiber": 1.6, "sugar": 1.3, "gi": 15},
    "cabbage": {"cal": 25, "p": 1.3, "c": 5.8, "f": 0.1, "fiber": 2.5, "sugar": 3.2, "gi": 10},
    "brussels sprouts": {"cal": 43, "p": 3.4, "c": 9, "f": 0.3, "fiber": 3.8, "sugar": 2.2, "gi": 15},
    "eggplant": {"cal": 25, "p": 1, "c": 6, "f": 0.2, "fiber": 3, "sugar": 3.6, "gi": 15},
    "lettuce": {"cal": 15, "p": 1.4, "c": 2.9, "f": 0.2, "fiber": 1.3, "sugar": 0.8, "gi": 15},
    "arugula": {"cal": 25, "p": 2.6, "c": 3.7, "f": 0.7, "fiber": 1.6, "sugar": 2, "gi": 15},
    "corn": {"cal": 86, "p": 3.3, "c": 19, "f": 1.2, "fiber": 2.7, "sugar": 6.3, "gi": 52},
    "peas": {"cal": 81, "p": 5.4, "c": 14, "f": 0.4, "fiber": 5.7, "sugar": 5.7, "gi": 48},
    "avocado": {"cal": 160, "p": 2, "c": 9, "f": 15, "fiber": 7, "sugar": 0.7, "gi": 15},
    # Fruits
    "banana": {"cal": 89, "p": 1.1, "c": 23, "f": 0.3, "fiber": 2.6, "sugar": 12, "gi": 51},
    "apple": {"cal": 52, "p": 0.3, "c": 14, "f": 0.2, "fiber": 2.4, "sugar": 10, "gi": 36},
    "blueberries": {"cal": 57, "p": 0.7, "c": 14, "f": 0.3, "fiber": 2.4, "sugar": 10, "gi": 53},
    "strawberries": {"cal": 32, "p": 0.7, "c": 7.7, "f": 0.3, "fiber": 2, "sugar": 4.9, "gi": 41},
    "raspberries": {"cal": 52, "p": 1.2, "c": 12, "f": 0.7, "fiber": 6.5, "sugar": 4.4, "gi": 32},
    "orange": {"cal": 47, "p": 0.9, "c": 12, "f": 0.1, "fiber": 2.4, "sugar": 9.4, "gi": 43},
    "mango": {"cal": 60, "p": 0.8, "c": 15, "f": 0.4, "fiber": 1.6, "sugar": 14, "gi": 51},
    "pineapple": {"cal": 50, "p": 0.5, "c": 13, "f": 0.1, "fiber": 1.4, "sugar": 10, "gi": 59},
    "grapes": {"cal": 69, "p": 0.7, "c": 18, "f": 0.2, "fiber": 0.9, "sugar": 16, "gi": 46},
    "watermelon": {"cal": 30, "p": 0.6, "c": 8, "f": 0.2, "fiber": 0.4, "sugar": 6.2, "gi": 76},
    "peach": {"cal": 39, "p": 0.9, "c": 10, "f": 0.3, "fiber": 1.5, "sugar": 8.4, "gi": 42},
    "pear": {"cal": 57, "p": 0.4, "c": 15, "f": 0.1, "fiber": 3.1, "sugar": 10, "gi": 38},
    "lemon juice": {"cal": 22, "p": 0.4, "c": 6.9, "f": 0.2, "fiber": 0.3, "sugar": 2.5, "gi": 0},
    "lime juice": {"cal": 25, "p": 0.4, "c": 8.4, "f": 0.1, "fiber": 0.4, "sugar": 1.7, "gi": 0},
    "dates": {"cal": 277, "p": 1.8, "c": 75, "f": 0.2, "fiber": 7, "sugar": 63, "gi": 42},
    # Nuts & seeds
    "almonds": {"cal": 579, "p": 21, "c": 22, "f": 50, "fiber": 12, "sugar": 4.4, "gi": 15},
    "walnuts": {"cal": 654, "p": 15, "c": 14, "f": 65, "fiber": 6.7, "sugar": 2.6, "gi": 15},
    "peanuts": {"cal": 567, "p": 26, "c": 16, "f": 49, "fiber": 8.5, "sugar": 4, "gi": 14},
    "cashews": {"cal": 553, "p": 18, "c": 30, "f": 44, "fiber": 3.3, "sugar": 5.9, "gi": 22},
    "peanut butter": {"cal": 588, "p": 25, "c": 20, "f": 50, "fiber": 6, "sugar": 9, "gi": 14},
    "almond butter": {"cal": 614, "p": 21, "c": 19, "f": 56, "fiber": 10, "sugar": 4.4, "gi": 15},
    "chia seeds": {"cal": 486, "p": 17, "c": 42, "f": 31, "fiber": 34, "sugar": 0, "gi": 1},
    "flax seeds": {"cal": 534, "p": 18, "c": 29, "f": 42, "fiber": 27, "sugar": 1.6, "gi": 0},
    "hemp seeds": {"cal": 553, "p": 32, "c": 8.7, "f": 49, "fiber": 4, "sugar": 1.5, "gi": 0},
    "pumpkin seeds": {"cal": 559, "p": 30, "c": 11, "f": 49, "fiber": 6, "sugar": 1.4, "gi": 10},
    "sunflower seeds": {"cal": 584, "p": 21, "c": 20, "f": 51, "fiber": 9, "sugar": 2.6, "gi": 35},
    "coconut flakes": {"cal": 660, "p": 7, "c": 24, "f": 64, "fiber": 16, "sugar": 6, "gi": 45},
    "almond flour": {"cal": 590, "p": 21, "c": 20, "f": 52, "fiber": 10, "sugar": 4, "gi": 15},
    "coconut flour": {"cal": 440, "p": 19, "c": 60, "f": 14, "fiber": 39, "sugar": 9, "gi": 45},
    # Condiments & extras
    "honey": {"cal": 304, "p": 0.3, "c": 82, "f": 0, "fiber": 0.2, "sugar": 82, "gi": 58},
    "maple syrup": {"cal": 260, "p": 0, "c": 67, "f": 0.1, "fiber": 0, "sugar": 60, "gi": 54},
    "soy sauce": {"cal": 53, "p": 8, "c": 4.9, "f": 0.6, "fiber": 0.8, "sugar": 0.4, "gi": 0},
    "tahini": {"cal": 595, "p": 17, "c": 21, "f": 54, "fiber": 9.3, "sugar": 0.5, "gi": 0},
    "hummus": {"cal": 166, "p": 8, "c": 14, "f": 10, "fiber": 6, "sugar": 0.3, "gi": 6},
    "salsa": {"cal": 36, "p": 2, "c": 7, "f": 0.2, "fiber": 2, "sugar": 4, "gi": 15},
    "guacamole": {"cal": 160, "p": 2, "c": 9, "f": 15, "fiber": 7, "sugar": 0.7, "gi": 15},
    "tomato sauce": {"cal": 29, "p": 1.3, "c": 5.3, "f": 0.6, "fiber": 1.5, "sugar": 3.6, "gi": 15},
    "pesto": {"cal": 385, "p": 5, "c": 6, "f": 38, "fiber": 1, "sugar": 1.6, "gi": 15},
    "mustard": {"cal": 66, "p": 4, "c": 6, "f": 3.3, "fiber": 3.3, "sugar": 2.5, "gi": 0},
    "balsamic vinegar": {"cal": 88, "p": 0.5, "c": 17, "f": 0, "fiber": 0, "sugar": 15, "gi": 0},
    "hot sauce": {"cal": 11, "p": 0.5, "c": 2, "f": 0.1, "fiber": 0.5, "sugar": 1, "gi": 0},
    "nutritional yeast": {"cal": 325, "p": 50, "c": 35, "f": 4.5, "fiber": 18, "sugar": 0, "gi": 0},
    "dark chocolate": {"cal": 546, "p": 5, "c": 60, "f": 31, "fiber": 7, "sugar": 48, "gi": 23},
    "cocoa powder": {"cal": 228, "p": 20, "c": 58, "f": 14, "fiber": 33, "sugar": 2, "gi": 20},
    "stevia": {"cal": 0, "p": 0, "c": 0, "f": 0, "fiber": 0, "sugar": 0, "gi": 0},
    "erythritol": {"cal": 0, "p": 0, "c": 0, "f": 0, "fiber": 0, "sugar": 0, "gi": 0},
}

# ─── Recipe templates per goal × meal_type ───────────────────────────────────

# Each template: (name_pattern, ingredient_list with grams, tags, minutes)
# ingredient_list entries: (ingredient_name, grams)

def _template(name, ings, tags, mins=20, servings=1):
    return {"name": name, "ings": ings, "tags": tags, "mins": mins, "servings": servings}

# === BREAKFAST templates ===
BREAKFAST_BASE = [
    _template("{protein} Scramble with {veg}", [("{protein}", 120), ("{veg}", 80), ("olive oil", 5)], ["high-protein"]),
    _template("{protein} & {veg} Omelette", [("{protein}", 100), ("eggs", 100), ("{veg}", 60), ("olive oil", 5)], ["high-protein"]),
    _template("Egg White {veg} Frittata", [("egg whites", 150), ("{veg}", 100), ("olive oil", 5)], ["high-protein", "low-fat"]),
    _template("{grain} Bowl with {fruit} & {nut}", [("{grain}", 50), ("{fruit}", 80), ("{nut}", 15), ("almond milk", 150)], ["fiber-rich"]),
    _template("{fruit} {dairy} Parfait", [("{dairy}", 150), ("{fruit}", 100), ("{nut}", 10)], ["high-protein"]),
    _template("{grain} Pancakes with {fruit}", [("{grain}", 40), ("eggs", 50), ("{fruit}", 60), ("olive oil", 5)], ["whole-grain"]),
    _template("{nut} Butter {bread} Toast", [("{bread}", 60), ("{nut}", 20), ("{fruit}", 50)], ["balanced"]),
    _template("{fruit} Smoothie with {dairy}", [("{fruit}", 120), ("{dairy}", 100), ("{nut}", 10), ("chia seeds", 8)], ["quick"]),
    _template("Overnight {grain} with {fruit}", [("{grain}", 50), ("{dairy}", 120), ("{fruit}", 80), ("chia seeds", 10)], ["meal-prep"]),
    _template("{protein} Breakfast Burrito", [("{protein}", 80), ("eggs", 60), ("tortilla (whole wheat)", 40), ("{veg}", 50), ("salsa", 20)], ["high-protein"]),
    _template("{veg} & Cheese Egg Muffins", [("eggs", 120), ("{veg}", 80), ("cheddar cheese", 20)], ["meal-prep", "high-protein"]),
    _template("{dairy} with {nut} & Honey", [("{dairy}", 200), ("{nut}", 20), ("honey", 10)], ["quick"]),
    _template("Protein {grain} with {fruit}", [("{grain}", 50), ("whey protein", 25), ("{fruit}", 80), ("almond milk", 150)], ["high-protein"]),
    _template("{veg} Hash with Eggs", [("{veg}", 150), ("potato", 80), ("eggs", 60), ("olive oil", 8)], ["hearty"]),
    _template("Smoked Salmon on {bread}", [("salmon", 60), ("{bread}", 50), ("cream cheese", 15), ("cucumber", 30)], ["omega-3"]),
]

LUNCH_BASE = [
    _template("{protein} {grain} Bowl", [("{protein}", 140), ("{grain}", 100), ("{veg}", 80), ("olive oil", 8)], ["balanced"]),
    _template("Grilled {protein} Salad", [("{protein}", 130), ("lettuce", 80), ("{veg}", 60), ("{veg2}", 50), ("olive oil", 10), ("lemon juice", 10)], ["low-carb"]),
    _template("{protein} & {veg} Stir-Fry", [("{protein}", 130), ("{veg}", 100), ("{veg2}", 60), ("soy sauce", 10), ("olive oil", 8)], ["quick"]),
    _template("{protein} Wrap with {veg}", [("{protein}", 110), ("tortilla (whole wheat)", 50), ("{veg}", 70), ("hummus", 30)], ["portable"]),
    _template("{protein} {veg} Soup", [("{protein}", 100), ("{veg}", 120), ("{veg2}", 60), ("onion", 30), ("olive oil", 5)], ["comfort", "low-calorie"], 35),
    _template("{grain} Salad with {protein}", [("{grain}", 80), ("{protein}", 100), ("{veg}", 70), ("{veg2}", 50), ("olive oil", 10), ("lemon juice", 10)], ["meal-prep"]),
    _template("{protein} Stuffed {veg}", [("{protein}", 120), ("{veg}", 150), ("tomato sauce", 40), ("mozzarella", 20)], ["creative"]),
    _template("{protein} & {legume} Bowl", [("{protein}", 100), ("{legume}", 80), ("{veg}", 70), ("olive oil", 8)], ["high-fiber"]),
    _template("{protein} Tacos", [("{protein}", 120), ("tortilla (corn)", 40), ("{veg}", 60), ("salsa", 30), ("avocado", 30)], ["Mexican-inspired"]),
    _template("Mediterranean {protein} Plate", [("{protein}", 120), ("hummus", 40), ("{veg}", 80), ("whole wheat bread", 40), ("olive oil", 8)], ["Mediterranean"]),
    _template("{protein} & {veg} Quesadilla", [("{protein}", 100), ("tortilla (whole wheat)", 50), ("{veg}", 60), ("cheddar cheese", 25)], ["quick"]),
    _template("{protein} Poke Bowl", [("{protein}", 130), ("white rice", 80), ("cucumber", 40), ("avocado", 30), ("soy sauce", 8)], ["Japanese-inspired"]),
    _template("Loaded {grain} with {protein}", [("{grain}", 100), ("{protein}", 120), ("{veg}", 70), ("sour cream", 15)], ["hearty"]),
    _template("{protein} & Avocado {bread}", [("{protein}", 100), ("avocado", 50), ("{bread}", 50), ("tomato", 40), ("lemon juice", 5)], ["quick"]),
    _template("{protein} Lettuce Wraps", [("{protein}", 130), ("lettuce", 60), ("{veg}", 50), ("soy sauce", 8), ("lime juice", 5)], ["low-carb"]),
]

DINNER_BASE = [
    _template("Pan-Seared {protein} with {veg}", [("{protein}", 160), ("{veg}", 120), ("{veg2}", 80), ("olive oil", 10), ("garlic", 5)], ["gourmet"], 30),
    _template("Baked {protein} with {grain}", [("{protein}", 150), ("{grain}", 100), ("{veg}", 100), ("olive oil", 8)], ["balanced"], 40),
    _template("{protein} & {veg} Curry", [("{protein}", 140), ("{veg}", 100), ("coconut milk", 50), ("onion", 30), ("garlic", 5)], ["spicy"], 35),
    _template("Herb-Crusted {protein} with {veg}", [("{protein}", 160), ("{veg}", 120), ("olive oil", 10), ("garlic", 5)], ["gourmet"], 35),
    _template("{protein} Pasta with {veg}", [("{protein}", 120), ("{pasta}", 80), ("{veg}", 80), ("tomato sauce", 50), ("olive oil", 8)], ["Italian-inspired"], 25),
    _template("{protein} & {veg} Sheet Pan", [("{protein}", 150), ("{veg}", 100), ("{veg2}", 80), ("olive oil", 12)], ["easy-cleanup"], 35),
    _template("Stuffed {veg} with {protein}", [("{veg}", 200), ("{protein}", 120), ("tomato sauce", 40), ("mozzarella", 25)], ["creative"], 40),
    _template("{protein} Stew with {veg}", [("{protein}", 140), ("{veg}", 100), ("{veg2}", 80), ("potato", 60), ("onion", 30)], ["comfort"], 45),
    _template("Grilled {protein} with {grain} Pilaf", [("{protein}", 150), ("{grain}", 80), ("{veg}", 70), ("olive oil", 8)], ["Mediterranean"], 30),
    _template("{protein} & {legume} Chili", [("{protein}", 120), ("{legume}", 80), ("tomato sauce", 60), ("onion", 30), ("bell pepper", 40)], ["hearty"], 40),
    _template("{protein} Teriyaki with {grain}", [("{protein}", 140), ("{grain}", 80), ("{veg}", 70), ("soy sauce", 15)], ["Asian-inspired"], 25),
    _template("Lemon Garlic {protein} with {veg}", [("{protein}", 150), ("{veg}", 120), ("lemon juice", 15), ("garlic", 5), ("olive oil", 10)], ["light"], 30),
    _template("{protein} Casserole with {veg}", [("{protein}", 130), ("{veg}", 100), ("{grain}", 60), ("cheddar cheese", 20)], ["comfort"], 45),
    _template("Blackened {protein} with {veg} Slaw", [("{protein}", 150), ("cabbage", 80), ("{veg}", 60), ("lime juice", 10), ("olive oil", 8)], ["Cajun-inspired"], 25),
    _template("{protein} Meatballs with {grain}", [("{protein}", 140), ("{grain}", 80), ("tomato sauce", 60), ("onion", 20), ("garlic", 5)], ["Italian-inspired"], 35),
]

SNACK_BASE = [
    _template("{nut} Butter {fruit} Bites", [("{nut}", 20), ("{fruit}", 80)], ["quick"], 5),
    _template("{dairy} with {fruit}", [("{dairy}", 120), ("{fruit}", 60)], ["high-protein"], 5),
    _template("Trail Mix with {nut} & {fruit}", [("{nut}", 25), ("{fruit}", 20), ("dark chocolate", 10)], ["portable"], 5),
    _template("{veg} Sticks with Hummus", [("{veg}", 100), ("hummus", 40)], ["fiber-rich"], 5),
    _template("Protein {fruit} Shake", [("whey protein", 25), ("{fruit}", 100), ("almond milk", 150)], ["high-protein"], 5),
    _template("{nut} & Seed Energy Balls", [("{nut}", 20), ("oats", 20), ("dates", 15), ("chia seeds", 5)], ["meal-prep"], 10),
    _template("Stuffed {veg} with {dairy}", [("{veg}", 80), ("{dairy}", 40), ("{nut}", 10)], ["creative"], 10),
    _template("{fruit} & {nut} Smoothie Bowl", [("{fruit}", 120), ("{dairy}", 80), ("{nut}", 10), ("chia seeds", 5)], ["trendy"], 10),
]

# ─── Fill-in options per goal ──────────────────────────────────────────────────

PROTEINS_GENERAL = ["chicken breast", "turkey breast", "salmon", "tuna", "shrimp", "cod", "tilapia", "beef steak", "beef sirloin", "pork tenderloin", "eggs"]
PROTEINS_VEGAN = ["tofu", "tempeh", "seitan", "edamame", "chickpeas", "lentils", "black beans"]

GRAINS_LOW_GI = ["quinoa", "brown rice", "oats", "bulgur", "sweet potato", "whole wheat pasta", "lentils"]
GRAINS_GENERAL = ["white rice", "brown rice", "quinoa", "oats", "couscous", "sweet potato", "whole wheat pasta", "bulgur"]
GRAINS_KETO = ["cauliflower"]  # cauliflower rice substitute

VEGS = ["broccoli", "spinach", "bell pepper", "zucchini", "asparagus", "mushrooms", "kale", "brussels sprouts", "green beans", "cauliflower", "eggplant", "cabbage", "carrots", "tomato", "cucumber", "celery", "peas", "arugula"]

FRUITS = ["banana", "apple", "blueberries", "strawberries", "raspberries", "mango", "pineapple", "orange", "peach", "pear", "grapes"]
FRUITS_LOW_GI = ["blueberries", "strawberries", "raspberries", "apple", "pear", "peach", "orange"]

NUTS = ["almonds", "walnuts", "peanuts", "cashews", "peanut butter", "almond butter", "pumpkin seeds", "sunflower seeds"]
DAIRY = ["greek yogurt", "cottage cheese"]
DAIRY_VEGAN = ["almond milk", "coconut milk"]
LEGUMES = ["chickpeas", "lentils", "black beans", "kidney beans", "edamame"]
BREADS = ["whole wheat bread"]
BREADS_KETO = ["almond flour"]
PASTAS = ["whole wheat pasta"]
PASTAS_KETO = ["zucchini"]  # zoodles

# ─── Goal-specific configurations ─────────────────────────────────────────────

GOAL_CONFIGS = {
    "muscle": {
        "goals_tag": ["muscle"],
        "proteins": PROTEINS_GENERAL,
        "grains": GRAINS_GENERAL,
        "vegs": VEGS,
        "fruits": FRUITS,
        "nuts": NUTS,
        "dairy": DAIRY,
        "legumes": LEGUMES,
        "breads": BREADS,
        "pastas": PASTAS,
        "portion_mult": 1.3,  # bigger portions
    },
    "diabetes": {
        "goals_tag": ["diabetes"],
        "proteins": PROTEINS_GENERAL,
        "grains": GRAINS_LOW_GI,
        "vegs": VEGS,
        "fruits": FRUITS_LOW_GI,
        "nuts": NUTS,
        "dairy": DAIRY,
        "legumes": LEGUMES,
        "breads": BREADS,
        "pastas": ["whole wheat pasta"],
        "portion_mult": 0.9,
    },
    "weight_loss": {
        "goals_tag": ["weight_loss"],
        "proteins": PROTEINS_GENERAL,
        "grains": GRAINS_LOW_GI,
        "vegs": VEGS,
        "fruits": FRUITS_LOW_GI,
        "nuts": NUTS,
        "dairy": DAIRY,
        "legumes": LEGUMES,
        "breads": BREADS,
        "pastas": PASTAS,
        "portion_mult": 0.8,  # smaller portions
    },
    "keto": {
        "goals_tag": ["keto"],
        "proteins": PROTEINS_GENERAL,
        "grains": GRAINS_KETO,
        "vegs": [v for v in VEGS if v not in ("carrots", "corn", "peas")],
        "fruits": ["blueberries", "strawberries", "raspberries", "avocado"],
        "nuts": NUTS,
        "dairy": DAIRY + ["heavy cream", "cream cheese"],
        "legumes": [],
        "breads": BREADS_KETO,
        "pastas": PASTAS_KETO,
        "portion_mult": 1.0,
    },
    "vegan": {
        "goals_tag": ["vegan"],
        "proteins": PROTEINS_VEGAN,
        "grains": GRAINS_GENERAL,
        "vegs": VEGS,
        "fruits": FRUITS,
        "nuts": NUTS,
        "dairy": DAIRY_VEGAN + ["coconut milk"],
        "legumes": LEGUMES,
        "breads": BREADS,
        "pastas": PASTAS,
        "portion_mult": 1.0,
    },
    "maintain": {
        "goals_tag": ["maintain"],
        "proteins": PROTEINS_GENERAL,
        "grains": GRAINS_GENERAL,
        "vegs": VEGS,
        "fruits": FRUITS,
        "nuts": NUTS,
        "dairy": DAIRY,
        "legumes": LEGUMES,
        "breads": BREADS,
        "pastas": PASTAS,
        "portion_mult": 1.0,
    },
}

# ─── Image URLs (curated from Unsplash — free, no key needed) ───────────────

IMG_BREAKFAST = [
    "https://images.unsplash.com/photo-1525351484163-7529414344d8?w=480&q=80",
    "https://images.unsplash.com/photo-1484723091739-30a097e8f929?w=480&q=80",
    "https://images.unsplash.com/photo-1528207776546-365bb710ee93?w=480&q=80",
    "https://images.unsplash.com/photo-1533089860892-a7c6f0a88666?w=480&q=80",
    "https://images.unsplash.com/photo-1504754524776-8f4f37790ca0?w=480&q=80",
    "https://images.unsplash.com/photo-1490474418585-ba9bad8fd0ea?w=480&q=80",
    "https://images.unsplash.com/photo-1551024506-0bccd828d307?w=480&q=80",
    "https://images.unsplash.com/photo-1517093602195-b40af9688b96?w=480&q=80",
    "https://images.unsplash.com/photo-1482049016688-2d3e1b311543?w=480&q=80",
    "https://images.unsplash.com/photo-1495214783159-3503fd1b572d?w=480&q=80",
    "https://images.unsplash.com/photo-1493770348161-369560ae357d?w=480&q=80",
    "https://images.unsplash.com/photo-1506084868230-bb9d95c24759?w=480&q=80",
    "https://images.unsplash.com/photo-1499636136210-6f4ee915583e?w=480&q=80",
    "https://images.unsplash.com/photo-1509440159596-0249088772ff?w=480&q=80",
    "https://images.unsplash.com/photo-1541519227354-08fa5d50c44d?w=480&q=80",
    "https://images.unsplash.com/photo-1494390248081-4e521a5940db?w=480&q=80",
    "https://images.unsplash.com/photo-1565958011703-44f9829ba187?w=480&q=80",
    "https://images.unsplash.com/photo-1432139555190-58524dae6a55?w=480&q=80",
    "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=480&q=80",
    "https://images.unsplash.com/photo-1476718406336-bb5a9690ee2a?w=480&q=80",
    "https://images.unsplash.com/photo-1497888329096-51c27beff665?w=480&q=80",
    "https://images.unsplash.com/photo-1464454709131-ffd692591ee5?w=480&q=80",
    "https://images.unsplash.com/photo-1511690743698-d9d18f7e20f1?w=480&q=80",
    "https://images.unsplash.com/photo-1498837167922-ddd27525d352?w=480&q=80",
    "https://images.unsplash.com/photo-1542691457-cbe4df43fc42?w=480&q=80",
    "https://images.unsplash.com/photo-1473093295043-cdd812d0e601?w=480&q=80",
    "https://images.unsplash.com/photo-1478145046317-39f10e56b5e9?w=480&q=80",
    "https://images.unsplash.com/photo-1459789034005-ba29c5783491?w=480&q=80",
    "https://images.unsplash.com/photo-1505253716362-afaea1d3d1af?w=480&q=80",
    "https://images.unsplash.com/photo-1467003909585-2f8a72700288?w=480&q=80",
]
IMG_LUNCH = [
    "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=480&q=80",
    "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=480&q=80",
    "https://images.unsplash.com/photo-1547592180-85f173990554?w=480&q=80",
    "https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=480&q=80",
    "https://images.unsplash.com/photo-1473093295043-cdd812d0e601?w=480&q=80",
    "https://images.unsplash.com/photo-1543339308-d595b7a4b8c0?w=480&q=80",
    "https://images.unsplash.com/photo-1551248429-40975aa4de74?w=480&q=80",
    "https://images.unsplash.com/photo-1505253716362-afaea1d3d1af?w=480&q=80",
    "https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=480&q=80",
    "https://images.unsplash.com/photo-1498837167922-ddd27525d352?w=480&q=80",
    "https://images.unsplash.com/photo-1467003909585-2f8a72700288?w=480&q=80",
    "https://images.unsplash.com/photo-1529692236671-f1f6cf9683ba?w=480&q=80",
    "https://images.unsplash.com/photo-1490645935967-10de6ba17061?w=480&q=80",
    "https://images.unsplash.com/photo-1455619452474-d2be8b1e70cd?w=480&q=80",
    "https://images.unsplash.com/photo-1476224203421-9ac39bcb3327?w=480&q=80",
    "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=480&q=80",
    "https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=480&q=80",
    "https://images.unsplash.com/photo-1560717789-0ac7c58ac90a?w=480&q=80",
    "https://images.unsplash.com/photo-1484980972926-edee96e0960d?w=480&q=80",
    "https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?w=480&q=80",
    "https://images.unsplash.com/photo-1432139555190-58524dae6a55?w=480&q=80",
    "https://images.unsplash.com/photo-1478145046317-39f10e56b5e9?w=480&q=80",
    "https://images.unsplash.com/photo-1459789034005-ba29c5783491?w=480&q=80",
    "https://images.unsplash.com/photo-1476718406336-bb5a9690ee2a?w=480&q=80",
    "https://images.unsplash.com/photo-1497888329096-51c27beff665?w=480&q=80",
    "https://images.unsplash.com/photo-1464454709131-ffd692591ee5?w=480&q=80",
    "https://images.unsplash.com/photo-1511690743698-d9d18f7e20f1?w=480&q=80",
    "https://images.unsplash.com/photo-1542691457-cbe4df43fc42?w=480&q=80",
    "https://images.unsplash.com/photo-1506354666786-959d6d497f1a?w=480&q=80",
    "https://images.unsplash.com/photo-1544025162-d76694265947?w=480&q=80",
]
IMG_DINNER = [
    "https://images.unsplash.com/photo-1432139509613-5c4255a1d873?w=480&q=80",
    "https://images.unsplash.com/photo-1467003909585-2f8a72700288?w=480&q=80",
    "https://images.unsplash.com/photo-1476718406336-bb5a9690ee2a?w=480&q=80",
    "https://images.unsplash.com/photo-1455619452474-d2be8b1e70cd?w=480&q=80",
    "https://images.unsplash.com/photo-1485963631004-f2f00b1d6571?w=480&q=80",
    "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=480&q=80",
    "https://images.unsplash.com/photo-1559847844-5315695dadae?w=480&q=80",
    "https://images.unsplash.com/photo-1574484284002-952d92456975?w=480&q=80",
    "https://images.unsplash.com/photo-1569058242567-93de6f36f8e6?w=480&q=80",
    "https://images.unsplash.com/photo-1544025162-d76694265947?w=480&q=80",
    "https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=480&q=80",
    "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=480&q=80",
    "https://images.unsplash.com/photo-1490645935967-10de6ba17061?w=480&q=80",
    "https://images.unsplash.com/photo-1476224203421-9ac39bcb3327?w=480&q=80",
    "https://images.unsplash.com/photo-1460306855393-0410f61241c7?w=480&q=80",
    "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=480&q=80",
    "https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?w=480&q=80",
    "https://images.unsplash.com/photo-1547592180-85f173990554?w=480&q=80",
    "https://images.unsplash.com/photo-1543339308-d595b7a4b8c0?w=480&q=80",
    "https://images.unsplash.com/photo-1560717789-0ac7c58ac90a?w=480&q=80",
    "https://images.unsplash.com/photo-1529692236671-f1f6cf9683ba?w=480&q=80",
    "https://images.unsplash.com/photo-1484980972926-edee96e0960d?w=480&q=80",
    "https://images.unsplash.com/photo-1506354666786-959d6d497f1a?w=480&q=80",
    "https://images.unsplash.com/photo-1542691457-cbe4df43fc42?w=480&q=80",
    "https://images.unsplash.com/photo-1493770348161-369560ae357d?w=480&q=80",
    "https://images.unsplash.com/photo-1506084868230-bb9d95c24759?w=480&q=80",
    "https://images.unsplash.com/photo-1499636136210-6f4ee915583e?w=480&q=80",
    "https://images.unsplash.com/photo-1509440159596-0249088772ff?w=480&q=80",
    "https://images.unsplash.com/photo-1541519227354-08fa5d50c44d?w=480&q=80",
    "https://images.unsplash.com/photo-1565958011703-44f9829ba187?w=480&q=80",
]
IMG_SNACK = [
    "https://images.unsplash.com/photo-1604908177453-7462950a6a3b?w=480&q=80",
    "https://images.unsplash.com/photo-1488477181946-6428a0291777?w=480&q=80",
    "https://images.unsplash.com/photo-1563805042-7684c019e1cb?w=480&q=80",
    "https://images.unsplash.com/photo-1505576399279-0d06b8d0f2ea?w=480&q=80",
    "https://images.unsplash.com/photo-1571091718767-18b5b1457add?w=480&q=80",
    "https://images.unsplash.com/photo-1490474418585-ba9bad8fd0ea?w=480&q=80",
    "https://images.unsplash.com/photo-1495214783159-3503fd1b572d?w=480&q=80",
    "https://images.unsplash.com/photo-1587049352846-4a222e784d38?w=480&q=80",
    "https://images.unsplash.com/photo-1494390248081-4e521a5940db?w=480&q=80",
    "https://images.unsplash.com/photo-1565958011703-44f9829ba187?w=480&q=80",
    "https://images.unsplash.com/photo-1551024506-0bccd828d307?w=480&q=80",
    "https://images.unsplash.com/photo-1517093602195-b40af9688b96?w=480&q=80",
    "https://images.unsplash.com/photo-1499636136210-6f4ee915583e?w=480&q=80",
    "https://images.unsplash.com/photo-1478145046317-39f10e56b5e9?w=480&q=80",
    "https://images.unsplash.com/photo-1509440159596-0249088772ff?w=480&q=80",
    "https://images.unsplash.com/photo-1541519227354-08fa5d50c44d?w=480&q=80",
    "https://images.unsplash.com/photo-1497888329096-51c27beff665?w=480&q=80",
    "https://images.unsplash.com/photo-1506354666786-959d6d497f1a?w=480&q=80",
    "https://images.unsplash.com/photo-1464454709131-ffd692591ee5?w=480&q=80",
    "https://images.unsplash.com/photo-1432139555190-58524dae6a55?w=480&q=80",
    "https://images.unsplash.com/photo-1459789034005-ba29c5783491?w=480&q=80",
    "https://images.unsplash.com/photo-1493770348161-369560ae357d?w=480&q=80",
    "https://images.unsplash.com/photo-1542691457-cbe4df43fc42?w=480&q=80",
    "https://images.unsplash.com/photo-1511690743698-d9d18f7e20f1?w=480&q=80",
    "https://images.unsplash.com/photo-1506084868230-bb9d95c24759?w=480&q=80",
    "https://images.unsplash.com/photo-1504754524776-8f4f37790ca0?w=480&q=80",
    "https://images.unsplash.com/photo-1533089860892-a7c6f0a88666?w=480&q=80",
    "https://images.unsplash.com/photo-1460306855393-0410f61241c7?w=480&q=80",
    "https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?w=480&q=80",
    "https://images.unsplash.com/photo-1484980972926-edee96e0960d?w=480&q=80",
]

IMG_MAP = {"breakfast": IMG_BREAKFAST, "lunch": IMG_LUNCH, "dinner": IMG_DINNER, "snack": IMG_SNACK}

# ─── Step generation ──────────────────────────────────────────────────────────

def generate_steps(name, ings_with_grams, meal_type, goal):
    """Generate 4-6 preparation steps based on recipe name and ingredients."""
    ing_names = [i[0] for i in ings_with_grams]
    protein_ings = [i for i in ing_names if i in INGREDIENTS and INGREDIENTS[i]["p"] > 15]
    veg_ings = [i for i in ing_names if i in INGREDIENTS and INGREDIENTS[i]["cal"] < 50 and INGREDIENTS[i]["c"] < 15]
    grain_ings = [i for i in ing_names if i in INGREDIENTS and INGREDIENTS[i]["c"] > 15 and i not in ("banana", "apple", "mango", "pineapple", "orange", "dates", "honey")]

    steps = []

    # Step 1: Prep
    if veg_ings:
        steps.append(f"Wash and prepare your vegetables: dice the {', '.join(veg_ings[:3])} into bite-sized pieces. Pat dry any protein ({', '.join(protein_ings[:2])}) and season with salt, pepper, and your preferred spices.")
    else:
        steps.append(f"Gather all ingredients and prepare your workspace. Season {protein_ings[0] if protein_ings else ing_names[0]} with salt, pepper, and your preferred herbs.")

    # Step 2: Cook protein or main component
    if protein_ings:
        p = protein_ings[0]
        if "scramble" in name.lower() or "omelette" in name.lower():
            steps.append(f"Heat a non-stick pan over medium heat with a drizzle of oil. Add the {p} and cook, stirring frequently, until fully cooked through and lightly golden.")
        elif "baked" in name.lower() or "casserole" in name.lower():
            steps.append(f"Preheat oven to 200°C (400°F). Place {p} on a lined baking sheet, drizzle with oil, and bake for 20-25 minutes until internal temperature reaches 74°C (165°F).")
        elif "grilled" in name.lower() or "pan-seared" in name.lower():
            steps.append(f"Heat a grill pan or skillet over medium-high heat. Sear {p} for 4-5 minutes per side until golden brown and cooked through. Rest for 3 minutes before slicing.")
        elif "stir" in name.lower():
            steps.append(f"Heat oil in a wok or large skillet over high heat. Add {p} and stir-fry for 3-4 minutes until cooked through. Remove and set aside.")
        elif "soup" in name.lower() or "stew" in name.lower() or "curry" in name.lower():
            steps.append(f"In a large pot, heat oil over medium heat. Brown {p} on all sides, about 5-6 minutes. Remove and set aside.")
        else:
            steps.append(f"Cook {p} in a pan over medium heat with oil, turning occasionally, until fully cooked and golden — about 5-7 minutes depending on thickness.")

    # Step 3: Cook vegs / grains
    if grain_ings:
        g = grain_ings[0]
        if g in ("oats",):
            steps.append(f"Prepare the {g}: combine with liquid in a saucepan, bring to a simmer, and cook for 5-7 minutes until creamy and tender.")
        elif g in ("quinoa", "brown rice", "white rice", "couscous", "bulgur"):
            steps.append(f"Cook {g} according to package directions. For extra flavour, use low-sodium broth instead of water. Fluff with a fork when done.")
        elif g in ("whole wheat pasta", "white pasta"):
            steps.append(f"Boil {g} in salted water until al dente. Drain and toss with a small drizzle of olive oil to prevent sticking.")
        else:
            steps.append(f"Prepare {g} according to package directions and set aside.")

    if veg_ings:
        if "stir" in name.lower():
            steps.append(f"Return the pan to high heat. Add {', '.join(veg_ings[:3])} and stir-fry for 2-3 minutes until tender-crisp. Add the protein back to the pan and toss to combine.")
        elif "soup" in name.lower() or "stew" in name.lower() or "curry" in name.lower():
            steps.append(f"Add onion and garlic to the pot and sauté for 2 minutes. Add {', '.join(veg_ings[:3])} and cook for 5 minutes. Return protein to the pot, add liquid, and simmer for 15-20 minutes.")
        else:
            steps.append(f"Meanwhile, sauté {', '.join(veg_ings[:3])} in a separate pan with a bit of oil over medium heat for 4-5 minutes until tender but still vibrant in colour.")

    # Step 4: Combine
    if meal_type in ("lunch", "dinner"):
        steps.append("Combine all components in a serving bowl or plate. Drizzle with any remaining sauce or dressing and season to taste with salt and pepper.")
    elif meal_type == "breakfast":
        steps.append("Assemble everything on your plate while still warm. Add any toppings and serve immediately for the best texture and flavour.")
    else:
        steps.append("Combine all ingredients, mix gently, and portion into a serving container. Store in the fridge for up to 3 days if meal-prepping.")

    # Diabetes-specific tip
    if goal == "diabetes":
        if veg_ings:
            steps.append("💡 Diabetes tip: Eat the vegetables first to slow glucose absorption, then the protein, and finish with any carbohydrates to minimize blood sugar spikes.")
        else:
            steps.append("💡 Diabetes tip: Pair this meal with a side of non-starchy vegetables to slow glucose absorption and reduce blood sugar spikes.")

    return steps


# ─── Nutrition calculation ────────────────────────────────────────────────────

def calc_nutrition(ings_with_grams):
    """Calculate nutrition from ingredients list [(name, grams), ...]."""
    totals = {"cal": 0, "p": 0, "c": 0, "f": 0, "fiber": 0, "sugar": 0, "gl": 0}
    for name, grams in ings_with_grams:
        if name not in INGREDIENTS:
            continue
        info = INGREDIENTS[name]
        mult = grams / 100
        totals["cal"] += info["cal"] * mult
        totals["p"] += info["p"] * mult
        totals["c"] += info["c"] * mult
        totals["f"] += info["f"] * mult
        totals["fiber"] += info["fiber"] * mult
        totals["sugar"] += info["sugar"] * mult
        # GL = GI × available_carbs / 100
        avail_carbs = max(0, (info["c"] - info["fiber"]) * mult)
        totals["gl"] += info["gi"] * avail_carbs / 100
    return totals


def make_recipe(idx, name, ings_with_grams, meal_type, goals, tags, mins, servings, goal_key):
    """Build a recipe dict."""
    nutr = calc_nutrition(ings_with_grams)

    # Estimate micronutrients (simplified but reasonable)
    has_leafy = any(n in ("spinach", "kale", "broccoli", "arugula", "lettuce", "cabbage", "brussels sprouts") for n, _ in ings_with_grams)
    has_citrus = any(n in ("orange", "lemon juice", "lime juice", "strawberries", "bell pepper", "tomato") for n, _ in ings_with_grams)
    has_fish = any(n in ("salmon", "tuna", "sardines", "cod", "tilapia", "shrimp") for n, _ in ings_with_grams)
    has_eggs = any(n in ("eggs", "egg whites") for n, _ in ings_with_grams)
    has_dairy = any(n in ("greek yogurt", "cottage cheese", "cheddar cheese", "mozzarella", "whole milk", "cream cheese", "feta cheese", "parmesan") for n, _ in ings_with_grams)
    has_nuts = any(n in ("almonds", "walnuts", "peanuts", "cashews", "pumpkin seeds", "sunflower seeds", "chia seeds", "flax seeds", "hemp seeds") for n, _ in ings_with_grams)

    vit_a = 80 + (400 if has_leafy else 0) + (100 if has_eggs else 0) + (50 if has_dairy else 0)
    vit_c = 5 + (40 if has_citrus else 0) + (20 if has_leafy else 0)
    vit_d = 0.5 + (8 if has_fish else 0) + (1 if has_eggs else 0) + (0.5 if has_dairy else 0)
    vit_e = 1 + (5 if has_nuts else 0) + (2 if has_leafy else 0)
    vit_k = 5 + (80 if has_leafy else 0)
    vit_b12 = 0.3 + (3 if has_fish else 0) + (1 if has_eggs else 0) + (0.5 if has_dairy else 0)
    folate = 20 + (100 if has_leafy else 0) + (30 if has_eggs else 0)
    calcium = 30 + (150 if has_dairy else 0) + (80 if has_leafy else 0)
    iron = 1 + (3 if has_leafy else 0) + (2 if any(n in ("beef steak", "beef sirloin", "ground beef") for n, _ in ings_with_grams) else 0)
    magnesium = 30 + (40 if has_nuts else 0) + (30 if has_leafy else 0)
    potassium = 150 + (200 if has_leafy else 0) + (150 if any(n in ("banana", "potato", "sweet potato", "avocado") for n, _ in ings_with_grams) else 0)
    zinc = 1 + (3 if any(n in ("beef steak", "beef sirloin", "ground beef", "pork tenderloin", "pork chop") for n, _ in ings_with_grams) else 0)
    sodium = 100 + (200 if any(n in ("soy sauce", "bacon") for n, _ in ings_with_grams) else 0) + (50 if has_dairy else 0)

    gi = 0
    total_carbs = nutr["c"]
    if total_carbs > 5:
        # Weighted average GI
        gi_sum = 0
        carb_sum = 0
        for n, g in ings_with_grams:
            if n in INGREDIENTS and INGREDIENTS[n]["gi"] > 0:
                c = INGREDIENTS[n]["c"] * g / 100
                gi_sum += INGREDIENTS[n]["gi"] * c
                carb_sum += c
        if carb_sum > 0:
            gi = round(gi_sum / carb_sum)

    gl = nutr["gl"]
    icr = 10  # default ICR
    insulin = round(total_carbs / icr, 1) if total_carbs > 0 else 0

    imgs = IMG_MAP.get(meal_type, IMG_LUNCH)
    # Use a hash of the recipe name to pick a unique image and avoid
    # obvious duplicates within the same visible list.
    name_hash = int(hashlib.md5(name.encode()).hexdigest(), 16)
    img = imgs[name_hash % len(imgs)]

    recipe_id = f"r{idx:04d}"

    # Compute a more realistic cooking time based on the recipe name.
    estimated_mins = mins  # default from template
    name_lower = name.lower()
    if any(kw in name_lower for kw in ("smoothie", "shake", "trail mix")):
        estimated_mins = 5
    elif any(kw in name_lower for kw in ("parfait", "overnight", "energy ball", "bites")):
        estimated_mins = random.choice([5, 10])
    elif any(kw in name_lower for kw in ("salad", "wrap", "toast", "sandwich")):
        estimated_mins = random.choice([10, 15])
    elif any(kw in name_lower for kw in ("scramble", "omelette", "frittata", "stir-fry", "stir fry", "tacos", "quesadilla", "lettuce wrap")):
        estimated_mins = random.choice([15, 20])
    elif any(kw in name_lower for kw in ("pan-seared", "grilled", "teriyaki", "blackened", "slaw")):
        estimated_mins = random.choice([20, 25])
    elif any(kw in name_lower for kw in ("pasta", "pilaf", "bowl", "curry")):
        estimated_mins = random.choice([25, 30])
    elif any(kw in name_lower for kw in ("baked", "herb-crusted", "sheet pan", "meatball", "casserole")):
        estimated_mins = random.choice([30, 35, 40])
    elif any(kw in name_lower for kw in ("stew", "chili", "soup")):
        estimated_mins = random.choice([35, 40, 45])
    elif any(kw in name_lower for kw in ("stuffed",)):
        estimated_mins = random.choice([30, 40])

    return {
        "id": recipe_id,
        "name": name,
        "image": img,
        "meal_type": meal_type,
        "goals": goals,
        "minutes": estimated_mins,
        "servings": servings,
        "tags": tags,
        "ingredients": [
            {"name": n, "grams": round(g), "amount": f"{round(g)}g"}
            for n, g in ings_with_grams if n in INGREDIENTS
        ],
        "steps": generate_steps(name, ings_with_grams, meal_type, goal_key),
        "source": "Generated",
        "calories": round(nutr["cal"]),
        "protein_g": round(nutr["p"], 1),
        "carbs_g": round(nutr["c"], 1),
        "fat_g": round(nutr["f"], 1),
        "fiber_g": round(nutr["fiber"], 1),
        "sugar_g": round(nutr["sugar"], 1),
        "vitamin_a_ug": round(vit_a, 1),
        "vitamin_c_mg": round(vit_c, 1),
        "vitamin_d_ug": round(vit_d, 1),
        "vitamin_e_mg": round(vit_e, 1),
        "vitamin_k_ug": round(vit_k, 1),
        "vitamin_b12_ug": round(vit_b12, 1),
        "folate_ug": round(folate, 1),
        "calcium_mg": round(calcium, 1),
        "iron_mg": round(iron, 1),
        "magnesium_mg": round(magnesium, 1),
        "potassium_mg": round(potassium, 1),
        "zinc_mg": round(zinc, 1),
        "sodium_mg": round(sodium, 1),
        "glycemic_index": gi,
        "glycemic_load": round(gl, 1),
        "insulin_units": insulin,
    }


# ─── Recipe generation engine ─────────────────────────────────────────────────

def fill_template(template, config, used_combos, goal_key):
    """Generate multiple recipes from a template by filling placeholders."""
    recipes = []
    proteins = config["proteins"]
    grains = config["grains"]
    vegs = config["vegs"]
    fruits = config["fruits"]
    nuts = config["nuts"]
    dairy = config["dairy"]
    legumes = config["legumes"]
    breads = config["breads"]
    pastas = config["pastas"]
    mult = config["portion_mult"]

    attempts = 0
    max_recipes = 30  # per template per goal

    for protein in proteins:
        for grain in (grains or [None]):
            for veg in vegs:
                if len(recipes) >= max_recipes:
                    break

                # Build name
                name = template["name"]
                name = name.replace("{protein}", protein.title())
                name = name.replace("{grain}", (grain or "quinoa").title())

                veg2_options = [v for v in vegs if v != veg]
                veg2 = random.choice(veg2_options) if veg2_options else veg
                name = name.replace("{veg}", veg.title())
                name = name.replace("{veg2}", veg2.title())

                fruit = random.choice(fruits) if fruits else "banana"
                name = name.replace("{fruit}", fruit.title())

                nut = random.choice(nuts) if nuts else "almonds"
                name = name.replace("{nut}", nut.title())

                d = random.choice(dairy) if dairy else "greek yogurt"
                name = name.replace("{dairy}", d.title())

                leg = random.choice(legumes) if legumes else "lentils"
                name = name.replace("{legume}", leg.title())

                bread = random.choice(breads) if breads else "whole wheat bread"
                name = name.replace("{bread}", bread.title())

                pasta = random.choice(pastas) if pastas else "whole wheat pasta"
                name = name.replace("{pasta}", pasta.title())

                # Deduplicate
                combo_key = f"{goal_key}:{name}"
                if combo_key in used_combos:
                    continue
                used_combos.add(combo_key)

                # Build ingredients
                ings = []
                for ing_name, grams in template["ings"]:
                    actual_name = ing_name
                    actual_name = actual_name.replace("{protein}", protein)
                    actual_name = actual_name.replace("{grain}", grain or "quinoa")
                    actual_name = actual_name.replace("{veg}", veg)
                    actual_name = actual_name.replace("{veg2}", veg2)
                    actual_name = actual_name.replace("{fruit}", fruit)
                    actual_name = actual_name.replace("{nut}", nut)
                    actual_name = actual_name.replace("{dairy}", d)
                    actual_name = actual_name.replace("{legume}", leg)
                    actual_name = actual_name.replace("{bread}", bread)
                    actual_name = actual_name.replace("{pasta}", pasta)

                    if actual_name in INGREDIENTS:
                        ings.append((actual_name, round(grams * mult)))

                if not ings:
                    continue

                # Calculate nutrition to determine additional goal eligibility
                nutr = calc_nutrition(ings)
                cal = nutr["cal"]
                prot = nutr["p"]
                carbs = nutr["c"]
                fat = nutr["f"]

                goals = list(config["goals_tag"])

                # Cross-tag: also eligible for other goals?
                if carbs <= 20 and "keto" not in goals:
                    goals.append("keto")
                if carbs <= 35 and cal < 600 and "diabetes" not in goals:
                    # Check GI
                    gi_ok = all(INGREDIENTS.get(n, {}).get("gi", 0) <= 55 for n, _ in ings)
                    if gi_ok:
                        goals.append("diabetes")
                if cal <= 600 and prot >= 15 and "weight_loss" not in goals:
                    goals.append("weight_loss")
                if prot >= 25 and cal >= 300 and "muscle" not in goals:
                    goals.append("muscle")
                if cal <= 2800 and "maintain" not in goals:
                    goals.append("maintain")

                recipes.append({
                    "name": name,
                    "ings": ings,
                    "tags": template["tags"],
                    "mins": template["mins"],
                    "servings": template["servings"],
                    "goals": goals,
                })

            if len(recipes) >= max_recipes:
                break
        if len(recipes) >= max_recipes:
            break

    return recipes


def main():
    # Load existing recipes
    with open(RECIPES_PATH, "r") as f:
        existing = json.load(f)

    print(f"Existing recipes: {len(existing)}")

    # Track used names to avoid duplicates with existing
    existing_names = {r["name"].lower() for r in existing}
    used_combos = set()

    new_recipes = []
    idx = len(existing) + 1

    templates_map = {
        "breakfast": BREAKFAST_BASE,
        "lunch": LUNCH_BASE,
        "dinner": DINNER_BASE,
        "snack": SNACK_BASE,
    }

    for goal_key, config in GOAL_CONFIGS.items():
        for meal_type, templates in templates_map.items():
            for tmpl in templates:
                generated = fill_template(tmpl, config, used_combos, goal_key)
                for g in generated:
                    if g["name"].lower() in existing_names:
                        continue
                    existing_names.add(g["name"].lower())

                    recipe = make_recipe(
                        idx, g["name"], g["ings"], meal_type,
                        g["goals"], g["tags"], g["mins"], g["servings"], goal_key
                    )
                    new_recipes.append(recipe)
                    idx += 1

    print(f"Generated {len(new_recipes)} new recipes")

    # Combine and save
    all_recipes = existing + new_recipes
    print(f"Total recipes: {len(all_recipes)}")

    # Stats
    by_goal = {}
    by_meal = {}
    by_goal_meal = {}
    for r in all_recipes:
        for g in r["goals"]:
            by_goal[g] = by_goal.get(g, 0) + 1
            key = f"{g}/{r['meal_type']}"
            by_goal_meal[key] = by_goal_meal.get(key, 0) + 1
        by_meal[r["meal_type"]] = by_meal.get(r["meal_type"], 0) + 1

    print("\nBy goal:")
    for g, c in sorted(by_goal.items()):
        print(f"  {g}: {c}")
    print("\nBy meal type:")
    for m, c in sorted(by_meal.items()):
        print(f"  {m}: {c}")
    print("\nBy goal × meal:")
    for k, c in sorted(by_goal_meal.items()):
        print(f"  {k}: {c}")

    with open(RECIPES_PATH, "w") as f:
        json.dump(all_recipes, f, indent=2, ensure_ascii=False)
    print(f"\n✅ Saved to {RECIPES_PATH}")


if __name__ == "__main__":
    main()
