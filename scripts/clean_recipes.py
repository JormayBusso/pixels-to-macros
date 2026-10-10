#!/usr/bin/env python3
"""
Clean recipes.json:
1. Remove exact/near-duplicate recipes
2. Limit to max 2 variations per core dish per (meal_type, goal-set) combo
3. Prefer original (no #N suffix) over numbered variants
4. Re-assign sequential IDs
"""

import json
import re
import hashlib
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INPUT = ROOT / "assets" / "recipes.json"
OUTPUT = ROOT / "assets" / "recipes.json"
BACKUP = ROOT / "assets" / "recipes_backup.json"

MAX_VARIATIONS = 2  # per core dish per (meal_type, goals) group


def core_dish(name: str) -> str:
    """Extract the core dish name, removing adjectives, numbering, parentheticals."""
    n = name.lower().strip()
    # Remove #N numbering
    n = re.sub(r"\s*#\d+\s*", " ", n)
    # Remove parenthetical like (variation), (No Muffin), (Fathead Dough)
    n = re.sub(r"\s*\(.*?\)\s*", " ", n)
    # Remove leading adjectives
    prefixes = [
        "herbed", "quick", "garlic", "roasted", "baked", "simple", "rustic",
        "spicy", "home-style", "zesty", "smoky", "grilled", "italian",
        "loaded", "classic", "pan-seared", "lemon", "herb", "fresh",
        "creamy", "mediterranean", "one-pot", "hearty", "light",
        "sheet-pan", "crispy", "tangy", "savory", "asian-style",
    ]
    words = n.split()
    while len(words) > 1 and words[0] in prefixes:
        words.pop(0)
    n = " ".join(words)
    # Normalize whitespace
    n = re.sub(r"\s+", " ", n).strip()
    return n


def ingredient_fingerprint(recipe: dict) -> str:
    """Create a fingerprint from sorted ingredient names."""
    ings = sorted(i["name"].lower() for i in recipe.get("ingredients", []))
    return "|".join(ings)


def macro_fingerprint(recipe: dict) -> str:
    """Round macros to nearest 5 for similarity check."""
    cal = round(recipe.get("calories", 0) / 10) * 10
    pro = round(recipe.get("protein_g", 0) / 5) * 5
    carb = round(recipe.get("carbs_g", 0) / 5) * 5
    fat = round(recipe.get("fat_g", 0) / 5) * 5
    return f"{cal}|{pro}|{carb}|{fat}"


def is_numbered_variant(name: str) -> bool:
    """Check if recipe name has a #N suffix."""
    return bool(re.search(r"#\d+", name))


def has_variation_tag(name: str) -> bool:
    """Check if recipe name has (variation) in it."""
    return bool(re.search(r"\(variation", name, re.I))


def priority_score(recipe: dict) -> int:
    """Lower = better priority. Prefer original names."""
    score = 0
    name = recipe.get("name", "")
    if is_numbered_variant(name):
        # Extract number, higher = worse
        m = re.search(r"#(\d+)", name)
        score += 100 + int(m.group(1)) if m else 200
    if has_variation_tag(name):
        score += 50
    # Prefer recipes with more goals (more versatile)
    score -= len(recipe.get("goals", [])) * 10
    # Prefer recipes with more ingredients (more interesting)
    score -= min(len(recipe.get("ingredients", [])), 8)
    return score


def main():
    with open(INPUT, "r") as f:
        recipes = json.load(f)

    print(f"Input: {len(recipes)} recipes")

    # Step 1: Remove exact duplicates (same name, same ingredients, same macros)
    seen_fingerprints = set()
    deduped = []
    exact_dupes = 0
    for r in recipes:
        fp = f"{r['name'].lower()}|{ingredient_fingerprint(r)}|{macro_fingerprint(r)}"
        if fp in seen_fingerprints:
            exact_dupes += 1
            continue
        seen_fingerprints.add(fp)
        deduped.append(r)
    print(f"Removed {exact_dupes} exact duplicates -> {len(deduped)} recipes")

    # Step 2: Remove near-duplicates (same core dish + same ingredients + similar macros)
    seen_near = set()
    no_near_dupes = []
    near_dupes = 0
    for r in deduped:
        fp = f"{core_dish(r['name'])}|{r['meal_type']}|{ingredient_fingerprint(r)}|{macro_fingerprint(r)}"
        if fp in seen_near:
            near_dupes += 1
            continue
        seen_near.add(fp)
        no_near_dupes.append(r)
    print(f"Removed {near_dupes} near-duplicates -> {len(no_near_dupes)} recipes")

    # Step 3: Group by (core_dish, meal_type) and keep max 2
    groups = defaultdict(list)
    for r in no_near_dupes:
        key = (core_dish(r["name"]), r.get("meal_type", ""))
        groups[key].append(r)

    kept = []
    trimmed = 0
    for key, group in groups.items():
        # Sort by priority (lower = better)
        group.sort(key=priority_score)
        keep = group[:MAX_VARIATIONS]
        kept.extend(keep)
        trimmed += len(group) - len(keep)

    print(f"Trimmed {trimmed} excess variations -> {len(kept)} recipes")

    # Step 4: Sort by meal_type order, then by name
    meal_order = {"breakfast": 0, "lunch": 1, "dinner": 2, "snack": 3, "dessert": 4}
    kept.sort(key=lambda r: (meal_order.get(r.get("meal_type", ""), 9), r.get("name", "")))

    # Step 5: Re-assign sequential IDs
    for i, r in enumerate(kept, 1):
        r["id"] = f"r{i:04d}"

    # Step 6: Stats
    from collections import Counter
    goal_counts = Counter()
    meal_counts = Counter()
    for r in kept:
        meal_counts[r.get("meal_type", "")] += 1
        for g in r.get("goals", []):
            goal_counts[g] += 1

    print(f"\nFinal: {len(kept)} recipes")
    print("By meal type:")
    for mt, c in sorted(meal_counts.items()):
        print(f"  {mt}: {c}")
    print("By goal:")
    for g, c in goal_counts.most_common():
        print(f"  {g}: {c}")

    # Verify coverage: every (meal_type, goal) combo should have some recipes
    for mt in ["breakfast", "lunch", "dinner", "snack"]:
        for g in ["diabetes", "weight_loss", "muscle", "keto", "vegan", "maintain"]:
            count = sum(1 for r in kept if r.get("meal_type") == mt and g in r.get("goals", []))
            if count < 3:
                print(f"  WARNING: {mt}/{g} only has {count} recipes!")

    # Check for remaining dishes with >2 variations
    core_counts = defaultdict(int)
    for r in kept:
        core_counts[core_dish(r["name"])] += 1
    over2 = {k: v for k, v in core_counts.items() if v > 4}
    if over2:
        print(f"\nDishes still with >4 total (across all meal_type/goal combos):")
        for k, v in sorted(over2.items(), key=lambda x: -x[1])[:15]:
            print(f"  {v}x: {k}")

    # Backup and save
    import shutil
    shutil.copy2(INPUT, BACKUP)
    print(f"\nBacked up original to {BACKUP}")

    with open(OUTPUT, "w") as f:
        json.dump(kept, f, indent=2, ensure_ascii=False)
    print(f"Saved {len(kept)} cleaned recipes to {OUTPUT}")


if __name__ == "__main__":
    main()
