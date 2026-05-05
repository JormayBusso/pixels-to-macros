#!/usr/bin/env python3
"""
Post-process assets/recipes.json:
  1. Fix dessert-type meals that ended up in dinner/lunch
  2. Split single-paragraph steps into sentence-level steps
"""
import json
import re
import os

DESSERT_MACROS = (320, 5, 44, 14, 2, 28)  # cal, prot, carb, fat, fib, sug

# Keywords that strongly indicate a dessert (applied to lowercase name)
DESSERT_KEYWORDS = [
    "cake", "cheesecake", "cupcake",
    "brownie", "cookie", "biscuit", "shortbread",
    "tart", "eclair", "profiterole",
    "muffin",
    "ice cream", "gelato", "sorbet", "frozen yogurt",
    "mousse", "parfait",
    "meringue", "pavlova",
    "pudding", "custard", "crème brûlée", "creme brulee",
    "tiramisu", "baklava", "flan",
    "cobbler", "crumble", "crisp",
    "doughnut", "donut",
    "macaroon", "macaron",
    "zabaglione", "syllabub",
    "chocolate truffle",
    "churros",
]

# Savory overrides — if name contains these, don't reclassify to dessert
SAVORY_OVERRIDES = [
    "sweet potato", "sweet corn", "sweet pepper", "sweet chilli", "sweet and sour",
    "biscuit gravy", "pudding sausage",
    "pie" ,  # many savory pies — we'll handle "pie" separately below
]

# Specific meal names (exact, lowercase) that are definitely desserts even with "pie"
SWEET_PIE_WORDS = ["apple pie", "cherry pie", "pumpkin pie", "lemon pie",
                   "key lime pie", "pecan pie", "blueberry pie", "strawberry pie",
                   "chocolate pie", "custard pie", "cream pie", "chess pie",
                   "banoffee pie", "sweet potato pie", "sugar pie"]


def is_dessert_name(name: str) -> bool:
    n = name.lower()

    # Check savory overrides first (but not for sweet pies)
    if any(s in n for s in SAVORY_OVERRIDES):
        if not any(sp in n for sp in SWEET_PIE_WORDS):
            return False

    # Match any dessert keyword
    for kw in DESSERT_KEYWORDS:
        if kw in n:
            return True

    # Sweet pie variants
    if any(sp in n for sp in SWEET_PIE_WORDS):
        return True

    return False


def split_steps(raw: str) -> list:
    """Split a block of text into clean step-level sentences."""
    # Normalize whitespace
    raw = raw.strip()
    if not raw:
        return []

    # Split on \n first (some recipes already have line breaks)
    lines = [l.strip() for l in re.split(r'\r?\n+', raw) if l.strip()]

    # If we already have multiple lines, return them (filtered for length)
    if len(lines) > 1:
        return [l for l in lines if len(l) > 8]

    # Otherwise split the single paragraph into sentences.
    # Strategy: split on ". " followed by capital letter or digit.
    sentences = re.split(r'\. (?=[A-Z0-9])', raw)

    steps = []
    for s in sentences:
        s = s.strip()
        if not s.endswith('.') and not s.endswith('!') and not s.endswith('?'):
            s = s + '.'
        if len(s) > 10:
            steps.append(s)

    return steps if steps else [raw]


def fix_recipes(recipes: list) -> list:
    dessert_fixed = 0
    steps_fixed = 0
    dessert_macros_fixed = 0

    for r in recipes:
        # ── Fix 1: dessert categorisation ──────────────────────────────────
        if r["meal_type"] != "dessert" and r["source"] == "TheMealDB":
            if is_dessert_name(r["name"]):
                r["meal_type"] = "dessert"
                # Update macros to dessert estimates
                r["calories"], r["protein_g"], r["carbs_g"], r["fat_g"], r["fiber_g"], r["sugar_g"] = DESSERT_MACROS
                # Fix goals — desserts are maintain
                if "diabetes" in r.get("goals", []) and "vegan" not in r.get("goals", []):
                    r["goals"] = ["maintain"]
                dessert_fixed += 1

        # ── Fix 2: step splitting ──────────────────────────────────────────
        steps = r.get("steps", [])
        # Only process if there's 1 step OR if any single step is very long (>300 chars)
        needs_split = (len(steps) == 1) or any(len(s) > 350 for s in steps)
        if needs_split and r["source"] == "TheMealDB":
            new_steps = []
            # Lower threshold for single-step recipes (try to split even shorter paragraphs)
            threshold = 80 if len(steps) == 1 else 350
            for step in steps:
                if len(step) > threshold:
                    split = split_steps(step)
                    new_steps.extend(split)
                else:
                    new_steps.append(step)
            if len(new_steps) > len(steps):
                r["steps"] = new_steps
                steps_fixed += 1

    print(f"Reclassified to dessert: {dessert_fixed}")
    print(f"Steps split improved: {steps_fixed}")
    return recipes


def main():
    path = os.path.join(os.path.dirname(__file__), "..", "assets", "recipes.json")
    path = os.path.normpath(path)

    with open(path) as f:
        recipes = json.load(f)

    print(f"Loaded {len(recipes)} recipes")

    from collections import Counter
    before = Counter(r["meal_type"] for r in recipes)
    print(f"Before: {dict(before)}")

    recipes = fix_recipes(recipes)

    after = Counter(r["meal_type"] for r in recipes)
    print(f"After:  {dict(after)}")

    # Sanity check steps
    one_step = sum(1 for r in recipes if len(r.get("steps", [])) == 1)
    print(f"Recipes still with 1 step: {one_step}")

    with open(path, "w") as f:
        json.dump(recipes, f, ensure_ascii=False, separators=(",", ":"))

    import os as _os
    size = _os.path.getsize(path)
    print(f"Written {path} ({size//1024} KB)")


if __name__ == "__main__":
    main()
