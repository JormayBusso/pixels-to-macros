#!/usr/bin/env python3
"""
Fetch ALL meals from TheMealDB (free tier) by letter search,
merge with existing diabetic-friendly curated recipes, write assets/recipes.json.
"""
import json
import time
import urllib.request
import urllib.error
import sys
import os

BASE = "https://www.themealdb.com/api/json/v1/1"

# ── Category → meal_type ──────────────────────────────────────────────────────
CAT_TO_TYPE = {
    "Breakfast": "breakfast",
    "Dessert": "dessert",
    "Starter": "lunch",
    "Side": "lunch",
    "Beef": "dinner",
    "Chicken": "dinner",
    "Lamb": "dinner",
    "Pork": "dinner",
    "Seafood": "dinner",
    "Pasta": "dinner",
    "Goat": "dinner",
    "Vegetarian": "dinner",
    "Vegan": "dinner",
    "Miscellaneous": "dinner",
    "Unknown": "dinner",
}

# ── Category → estimated macros (cal, prot, carb, fat, fiber, sugar) ─────────
# These are per-serving estimates for the typical portion of that category.
CAT_MACROS = {
    "Breakfast":   (360, 16, 36, 18, 4, 9),
    "Beef":        (480, 36, 14, 30, 2, 4),
    "Chicken":     (380, 38, 14, 20, 2, 4),
    "Lamb":        (440, 32, 12, 28, 2, 4),
    "Pork":        (410, 30, 15, 25, 2, 4),
    "Seafood":     (320, 34, 12, 14, 2, 3),
    "Pasta":       (480, 20, 58, 16, 4, 6),
    "Goat":        (380, 30, 10, 22, 1, 3),
    "Vegetarian":  (290, 12, 36, 12, 5, 6),
    "Vegan":       (260, 10, 38, 8,  6, 6),
    "Dessert":     (320, 5,  44, 14, 2, 28),
    "Miscellaneous": (380, 20, 30, 18, 3, 5),
    "Side":        (200, 5,  28, 8,  3, 4),
    "Starter":     (180, 10, 14, 10, 2, 3),
}

# ── Category → goals ──────────────────────────────────────────────────────────
CAT_GOALS = {
    "Breakfast":   ["maintain"],
    "Beef":        ["muscle", "maintain"],
    "Chicken":     ["muscle", "weight_loss", "maintain"],
    "Lamb":        ["muscle", "maintain"],
    "Pork":        ["muscle", "maintain"],
    "Seafood":     ["diabetes", "muscle", "maintain"],
    "Pasta":       ["muscle", "maintain"],
    "Goat":        ["maintain"],
    "Vegetarian":  ["diabetes", "vegan", "maintain"],
    "Vegan":       ["diabetes", "vegan", "maintain"],
    "Dessert":     ["maintain"],
    "Miscellaneous": ["maintain"],
    "Side":        ["diabetes", "maintain"],
    "Starter":     ["diabetes", "maintain"],
}

# ── Servings hint per category ────────────────────────────────────────────────
CAT_SERVINGS = {
    "Breakfast": 1,
    "Starter": 2,
    "Side": 2,
    "Dessert": 4,
}

def fetch_json(url, retries=3):
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=12) as r:
                return json.loads(r.read())
        except urllib.error.URLError as e:
            if attempt == retries - 1:
                return None
            time.sleep(1.5)
    return None

def get_all_meals():
    meals = {}
    letters = "abcdefghijklmnopqrstuvwxyz0123456789"
    for i, letter in enumerate(letters):
        data = fetch_json(f"{BASE}/search.php?f={letter}")
        if data and data.get("meals"):
            for m in data["meals"]:
                meals[m["idMeal"]] = m
        count = len(meals)
        print(f"  [{letter}] running total: {count} meals", flush=True)
        time.sleep(0.4)  # be polite to the free API
    return list(meals.values())

def parse_meal(m):
    cat = (m.get("strCategory") or "Miscellaneous").strip()
    meal_type = CAT_TO_TYPE.get(cat, "dinner")
    cal, prot, carb, fat, fib, sug = CAT_MACROS.get(cat, (380, 20, 30, 18, 3, 5))
    goals = list(CAT_GOALS.get(cat, ["maintain"]))
    servings = CAT_SERVINGS.get(cat, 4)

    # Ingredients
    ingredients = []
    for i in range(1, 21):
        name = (m.get(f"strIngredient{i}") or "").strip()
        amount = (m.get(f"strMeasure{i}") or "").strip()
        if name:
            ingredients.append({"name": name, "amount": amount})

    # Estimate minutes from step count
    raw_steps = (m.get("strInstructions") or "")
    lines = [s.strip() for s in raw_steps.replace("\r\n", "\n").replace("\r", "\n").split("\n") if s.strip()]
    # Filter out very short lines (likely step numbers or headers)
    steps = [s for s in lines if len(s) > 10]
    if not steps:
        steps = [raw_steps.strip()] if raw_steps.strip() else ["Follow the recipe instructions."]
    minutes = max(10, min(150, len(steps) * 8))

    # Tags
    tags_raw = (m.get("strTags") or "")
    tags = [t.strip().lower() for t in tags_raw.split(",") if t.strip()]

    # Add area as a tag if present
    area = (m.get("strArea") or "").strip()
    if area and area.lower() not in ("unknown", ""):
        tags.append(area.lower())

    # Heuristic: low-carb meals get diabetes tag
    low_carb_categories = {"Beef", "Chicken", "Lamb", "Pork", "Seafood", "Goat"}
    if cat in low_carb_categories and carb < 20:
        if "diabetes" not in goals:
            goals.append("diabetes")

    image = (m.get("strMealThumb") or "").strip()

    return {
        "id": f"mdb_{m['idMeal']}",
        "name": m["strMeal"],
        "image": image,
        "meal_type": meal_type,
        "goals": goals,
        "minutes": minutes,
        "servings": servings,
        "tags": tags,
        "ingredients": ingredients,
        "steps": steps,
        "source": "TheMealDB",
        "calories": cal,
        "protein_g": prot,
        "carbs_g": carb,
        "fat_g": fat,
        "fiber_g": fib,
        "sugar_g": sug,
    }


def main():
    recipes_path = os.path.join(os.path.dirname(__file__), "..", "assets", "recipes.json")
    recipes_path = os.path.normpath(recipes_path)

    # Load existing curated recipes (keep ALL of them)
    with open(recipes_path) as f:
        existing = json.load(f)

    # Track existing names to avoid duplication (TheMealDB may overlap by name)
    existing_names_lower = {r["name"].lower() for r in existing}
    existing_ids = {r["id"] for r in existing}

    print(f"Loaded {len(existing)} existing curated recipes")
    print("Fetching all meals from TheMealDB (a→z + 0→9)...")

    all_meals = get_all_meals()
    print(f"\nFetched {len(all_meals)} unique meals from TheMealDB")

    new_recipes = []
    skipped_dup = 0
    for m in all_meals:
        r = parse_meal(m)
        if r["id"] in existing_ids:
            skipped_dup += 1
            continue
        if r["name"].lower() in existing_names_lower:
            skipped_dup += 1
            continue
        new_recipes.append(r)

    combined = existing + new_recipes
    print(f"Skipped {skipped_dup} duplicates")
    print(f"Added {len(new_recipes)} new TheMealDB recipes")
    print(f"Total combined: {len(combined)} recipes")

    # Stats
    from collections import Counter
    by_type = Counter(r["meal_type"] for r in combined)
    print(f"By type: {dict(by_type)}")
    muscle = sum(1 for r in combined if "muscle" in r.get("goals", []))
    diabetes = sum(1 for r in combined if "diabetes" in r.get("goals", []))
    print(f"Muscle-tagged: {muscle}, Diabetes-tagged: {diabetes}")

    with open(recipes_path, "w") as f:
        json.dump(combined, f, indent=2, ensure_ascii=False)

    print(f"\nWritten to {recipes_path}")
    print("Done!")


if __name__ == "__main__":
    main()
