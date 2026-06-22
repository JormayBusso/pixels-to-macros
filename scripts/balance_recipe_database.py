#!/usr/bin/env python3
"""Balance and clean assets/bundled_recipes.json.

The scraped dataset is heavily skewed toward "dinner" because
`infer_meal_type` in scrape_real_recipes.py falls back to "dinner" for anything
it can't confidently bucket. This script runs three independent passes to make
the meal tabs cleaner and more balanced:

  1. cleanse-tags  - Demote recipes mislabeled breakfast/lunch when the title or
                     ingredients clearly describe a dinner dish (roast, steak,
                     pasta bake, ...). Keeps `meal_type` and the meal-word `tag`
                     in sync so the UI never shows a roast under "Breakfast".

  2. filter-snacks - Reclassify "snacks" that are really multi-step cooked meals
                     (lots of ingredients / long cook time / oven|simmer steps)
                     into lunch/dinner, and keep only genuinely simple snacks
                     (fruit, yogurt, nuts, shakes, dips, bars, ...).

  3. prune-dinner  - Optionally cap the dinner bucket at --dinner-cap, keeping the
                     simplest + most "common" dishes (lowest complexity score).

Dry-run by default. Pass --write to persist. Each pass can be toggled; with no
pass flags, all three run.

    # preview everything
    python scripts/balance_recipe_database.py

    # only fix mislabels, then persist
    python scripts/balance_recipe_database.py --cleanse-tags --write

    # cap dinner at 800 and persist
    python scripts/balance_recipe_database.py --prune-dinner --dinner-cap 800 --write
"""
from __future__ import annotations

import argparse
import collections
import json
import re
from pathlib import Path

ASSET = Path(__file__).resolve().parents[1] / "assets" / "bundled_recipes.json"
MEAL_WORDS = {"breakfast", "lunch", "dinner", "snack", "dessert"}

# Strong dinner signals. Multi-word where possible to avoid false positives.
DINNER_TERMS = [
    "roast", "roasted", "pot roast", "casserole", "curry", "stew", "lasagne",
    "lasagna", "risotto", "steak", "schnitzel", "stir fry", "stir-fry",
    "bolognese", "gratin", "paella", "biryani", "tagine", "goulash", "meatball",
    "meatballs", "pasta bake", "pasta-bake", "wellington", "moussaka",
    "carbonara", "jambalaya", "pot pie", "braise", "braised", "slow cooker",
    "slow-cooked", "ragu", "ragout", "tenderloin", "brisket", "pork chop",
    "lamb shank", "chicken thigh", "drumstick", "fillet", "filet",
    # DE / NL
    "auflauf", "braten", "eintopf", "gulasch", "rouladen", "frikadellen",
    "stamppot", "ovenschotel", "hachee", "hutspot", "draadjesvlees",
]

# Snacks that are genuinely simple grab-and-eat items.
SIMPLE_SNACK_TERMS = [
    "fruit", "apple", "banana", "berries", "berry", "grapes", "orange",
    "yogurt", "yoghurt", "greek yogurt", "nuts", "almond", "almonds", "cashew",
    "walnut", "trail mix", "shake", "smoothie", "protein shake", "protein bar",
    "energy ball", "energy balls", "energy bites", "bliss balls", "granola bar",
    "popcorn", "crackers", "rice cake", "rice cakes", "hummus", "guacamole",
    "dip", "edamame", "olives", "cheese stick", "string cheese", "jerky",
    "dark chocolate", "chia pudding", "overnight oats",
]

# Strong breakfast / dessert signals that VETO a dinner demotion. A dinner
# keyword inside one of these titles is incidental (e.g. "steak and eggs",
# "honey-roasted apricots", "yogurt cheesecake").
BREAKFAST_GUARD = [
    "pancake", "pancakes", "waffle", "waffles", "omelet", "omelette", "omelett",
    "scrambled egg", "scrambled eggs", "fried egg", "poached egg", "rührei",
    "ruhrei", "frittata", "shakshuka", "porridge", "oatmeal", "oats", "muesli",
    "granola", "french toast", "bircher", "haferflocken", "haferbrei",
    "pfannkuchen", "eierkuchen", "ontbijt", "pannenkoek", "smoothie", "bagel",
    "croissant", "crepe", "crêpe", "breakfast", "brunch", "frühstück",
    "fruhstuck",
]
DESSERT_GUARD = [
    "cake", "cheesecake", "cookie", "brownie", "pudding", "ice cream", "tart",
    "pie", "muffin", "dessert", "kuchen", "torte", "ciasto", "deser", "postre",
]

# Cooking-process words that mark a "snack" as actually a real cooked dish.
COOKED_PROCESS_TERMS = [
    "bake", "baked", "oven", "preheat", "roast", "simmer", "sauté", "saute",
    "fry", "deep fry", "boil", "braise", "grill", "broil", "knead", "marinate",
    "sear", "caramelize", "caramelise", "reduce the heat", "bring to a boil",
]

# Main-dish proteins. A snack whose TITLE names one of these is a composed meal,
# never a simple snack — even if it also mentions a dip/hummus/nut component
# (e.g. "Hummus with pistachio lamb meatballs", "Almond-crusted fish").
SNACK_PROTEIN_TERMS = [
    "chicken", "beef", "steak", "lamb", "pork", "bacon", "ham", "turkey",
    "fish", "salmon", "tuna", "cod", "shrimp", "prawn", "meatball", "meatballs",
    "pastrami", "chorizo", "sausage", "skewer", "skewers", "wings", "fillet",
    "filet",
]


def _has(text: str, terms) -> bool:
    for t in terms:
        if re.search(r"(^|[^a-z])" + re.escape(t) + r"([^a-z]|$)", text):
            return True
    return False


def _title(r: dict) -> str:
    return str(r.get("title") or r.get("name") or "").lower()


def _ingredient_blob(r: dict) -> str:
    parts = []
    for item in r.get("ingredients") or []:
        if isinstance(item, dict):
            parts.append(str(item.get("name") or ""))
        else:
            parts.append(str(item))
    return " ".join(parts).lower()


def _instructions_blob(r: dict) -> str:
    instr = r.get("instructions")
    if isinstance(instr, list):
        instr = " ".join(str(s) for s in instr)
    steps = r.get("steps") or []
    return (str(instr or "") + " " + " ".join(str(s) for s in steps)).lower()


def _step_count(r: dict) -> int:
    steps = r.get("steps")
    if isinstance(steps, list) and steps:
        return len(steps)
    instr = r.get("instructions") or ""
    if isinstance(instr, list):
        return len(instr)
    return len([ln for ln in str(instr).split("\n") if ln.strip()])


def _ingredient_count(r: dict) -> int:
    return len(r.get("ingredients") or [])


def _minutes(r: dict) -> int:
    for key in ("minutes", "time"):
        v = r.get(key)
        try:
            if v is not None:
                return int(float(v))
        except (TypeError, ValueError):
            continue
    return 0


def _set_meal_type(r: dict, meal: str) -> None:
    """Set meal_type and keep the meal-word tag consistent."""
    r["meal_type"] = meal
    tags = [t for t in (r.get("tags") or []) if str(t).lower() not in MEAL_WORDS]
    tags.insert(0, meal)
    r["tags"] = tags


def complexity_score(r: dict) -> float:
    """Higher = more elaborate dish. Used to prune dinner to the simplest/common."""
    return (
        _ingredient_count(r) * 1.0
        + _step_count(r) * 1.5
        + _minutes(r) * 0.10
    )


# --------------------------------------------------------------------------- #
# Pass 1: tag cleansing
# --------------------------------------------------------------------------- #
def cleanse_tags(recipes: list[dict]) -> collections.Counter:
    changes: collections.Counter = collections.Counter()
    for r in recipes:
        meal = (r.get("meal_type") or "dinner").lower()
        if meal not in ("breakfast", "lunch"):
            continue
        title = _title(r)
        # Veto: an incidental dinner word inside a clear breakfast/dessert title
        # (e.g. "steak and eggs", "honey-roasted apricots") must not be demoted.
        if _has(title, BREAKFAST_GUARD) or _has(title, DESSERT_GUARD):
            continue
        # Match the TITLE only. Ingredient-blob matching is too noisy — a
        # breakfast hash listing "leftover roast" would be wrongly demoted.
        if _has(title, DINNER_TERMS):
            _set_meal_type(r, "dinner")
            changes[f"{meal}->dinner"] += 1
    return changes


# --------------------------------------------------------------------------- #
# Pass 2: snack filtering
# --------------------------------------------------------------------------- #
def is_complex_snack(r: dict) -> bool:
    title = _title(r)
    # A named main-dish protein in the title -> always a meal, never a snack.
    if _has(title, SNACK_PROTEIN_TERMS) or _has(title, DINNER_TERMS):
        return True
    # A clearly simple snack stays a snack regardless of step count.
    if _has(title, SIMPLE_SNACK_TERMS) and _ingredient_count(r) <= 6:
        return False
    if _ingredient_count(r) >= 8:
        return True
    if _step_count(r) >= 4:
        return True
    if _minutes(r) >= 25:
        return True
    if _has(_instructions_blob(r), COOKED_PROCESS_TERMS) and not _has(title, SIMPLE_SNACK_TERMS):
        return True
    return False


def filter_snacks(recipes: list[dict]) -> collections.Counter:
    changes: collections.Counter = collections.Counter()
    for r in recipes:
        meal = (r.get("meal_type") or "dinner").lower()
        if meal != "snack":
            continue
        if is_complex_snack(r):
            # Has a dinner signal -> dinner, otherwise treat as a light meal -> lunch.
            blob = _title(r) + " " + _ingredient_blob(r)
            target = "dinner" if _has(blob, DINNER_TERMS) else "lunch"
            _set_meal_type(r, target)
            changes[f"snack->{target}"] += 1
    return changes


# --------------------------------------------------------------------------- #
# Pass 3: dinner pruning
# --------------------------------------------------------------------------- #
def prune_dinner(recipes: list[dict], cap: int) -> tuple[list[dict], int]:
    dinners = [r for r in recipes if (r.get("meal_type") or "dinner").lower() == "dinner"]
    if len(dinners) <= cap:
        return recipes, 0
    # Keep the `cap` simplest/most-common dishes (lowest complexity score).
    dinners_sorted = sorted(dinners, key=complexity_score)
    keep = set(id(r) for r in dinners_sorted[:cap])
    dropped = len(dinners) - cap
    kept = [
        r for r in recipes
        if (r.get("meal_type") or "dinner").lower() != "dinner" or id(r) in keep
    ]
    return kept, dropped


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cleanse-tags", action="store_true", help="demote mislabeled breakfast/lunch dinner dishes")
    ap.add_argument("--filter-snacks", action="store_true", help="reclassify complex multi-step snacks")
    ap.add_argument("--prune-dinner", action="store_true", help="cap the dinner bucket at --dinner-cap")
    ap.add_argument("--dinner-cap", type=int, default=2000, help="max dinner recipes to keep (default 2000)")
    ap.add_argument("--write", action="store_true", help="persist changes (default: dry-run)")
    args = ap.parse_args()

    run_all = not (args.cleanse_tags or args.filter_snacks or args.prune_dinner)

    recipes = json.loads(ASSET.read_text())
    before = collections.Counter((r.get("meal_type") or "dinner").lower() for r in recipes)

    if args.cleanse_tags or run_all:
        ch = cleanse_tags(recipes)
        print("PASS 1 cleanse-tags:", dict(ch) or "no changes")

    if args.filter_snacks or run_all:
        ch = filter_snacks(recipes)
        print("PASS 2 filter-snacks:", dict(ch) or "no changes")

    if args.prune_dinner or run_all:
        dinner_now = sum(1 for r in recipes if (r.get("meal_type") or "dinner").lower() == "dinner")
        if dinner_now <= args.dinner_cap:
            print(f"PASS 3 prune-dinner: dinner={dinner_now} <= cap={args.dinner_cap}, nothing to prune")
        else:
            recipes, dropped = prune_dinner(recipes, args.dinner_cap)
            print(f"PASS 3 prune-dinner: dropped {dropped} dinners (cap {args.dinner_cap})")

    after = collections.Counter((r.get("meal_type") or "dinner").lower() for r in recipes)
    print("\nBEFORE:", dict(before.most_common()))
    print("AFTER :", dict(after.most_common()))
    print("TOTAL :", len(recipes))

    if args.write:
        ASSET.write_text(json.dumps(recipes, ensure_ascii=False, indent=2))
        print(f"\nWROTE {ASSET}")
    else:
        print("\n(dry-run; pass --write to persist)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
