#!/usr/bin/env python3
"""Reclassify recipe `meal_type` in assets/bundled_recipes.json.

The scraped dataset labels ~69% of recipes as "dinner", so the breakfast and
lunch tabs are starved and show dinner dishes. This re-derives meal_type from
the recipe NAME (highest precision) with multilingual EN/DE/NL keywords.

Priority per recipe:
  1. Keep explicit `dessert` / `snack` labels (those are reliable).
  2. Name contains a breakfast term -> breakfast.
  3. Name contains a lunch term      -> lunch.
  4. Otherwise keep the existing label.

We only ever PROMOTE the starved breakfast/lunch buckets and never demote an
existing label to dinner, so the change can't introduce new "dinner under
breakfast" style regressions.

Run with --write to persist; default is a dry-run preview.
"""
import json
import re
import sys
import collections
from pathlib import Path

ASSET = Path(__file__).resolve().parents[1] / "assets" / "bundled_recipes.json"

# High-precision, mostly multi-word so we avoid false positives like bare "egg".
BREAKFAST = [
    "breakfast", "brunch", "pancake", "pancakes", "waffle", "waffles",
    "omelet", "omelette", "scrambled egg", "fried egg", "poached egg",
    "eggs benedict", "oatmeal", "porridge", "overnight oats", "granola",
    "muesli", "french toast", "avocado toast", "bagel", "croissant", "muffin",
    "scone", "crumpet", "frittata", "shakshuka", "hash brown", "chia pudding",
    "smoothie bowl", "acai bowl", "breakfast burrito", "bircher",
    # DE
    "fruhstuck", "frühstück", "pfannkuchen", "pfannekuchen", "ruhrei", "rührei",
    "haferbrei", "haferflocken", "musli", "müsli", "eierkuchen", "porridge",
    # NL
    "ontbijt", "pannenkoek", "pannenkoeken", "wentelteefjes", "havermout",
    "beschuit", "roerei",
]

LUNCH = [
    "sandwich", "wrap", "panini", "toastie", "salad", "soup",
    "quesadilla", "bruschetta", "quiche", "gazpacho",
    "chowder", "bisque", "club sandwich", "blt",
    "hummus bowl", "grain bowl", "poke bowl",
    # DE
    "salat", "suppe", "flammkuchen",
    # NL
    "salade", "soep", "broodje", "tosti",
]

DINNER = [
    "roast", "roasted", "casserole", "curry", "stew", "lasagne", "lasagna",
    "risotto", "steak", "schnitzel", "stir fry", "stir-fry", "spaghetti",
    "bolognese", "pie", "gratin", "paella", "biryani", "tagine", "goulash",
    "meatball", "meatballs", "burger", "pizza", "taco", "tacos", "enchilada",
    "ramen", "noodles", "casserole", "pot roast", "wellington", "kebab",
    "fajita", "fajitas", "carbonara", "moussaka", "jambalaya",
    # DE
    "auflauf", "braten", "eintopf", "gulasch", "rouladen", "frikadellen",
    # NL
    "stamppot", "ovenschotel", "hachee", "hutspot", "draadjesvlees",
]


def _has(name: str, terms) -> bool:
    for t in terms:
        # word-boundary-ish match to avoid substrings inside other words
        if re.search(r"(^|[^a-z])" + re.escape(t) + r"([^a-z]|$)", name):
            return True
    return False


def classify(recipe: dict) -> str:
    current = (recipe.get("meal_type") or "dinner").lower()
    if current in ("dessert", "snack"):
        return current
    name = (recipe.get("name") or "").lower()
    if _has(name, BREAKFAST):
        return "breakfast"
    if _has(name, LUNCH):
        return "lunch"
    return current


def main() -> int:
    write = "--write" in sys.argv
    data = json.loads(ASSET.read_text())
    before = collections.Counter(r.get("meal_type") for r in data)
    changes = collections.Counter()
    samples = collections.defaultdict(list)
    for r in data:
        old = (r.get("meal_type") or "dinner").lower()
        new = classify(r)
        if new != old:
            changes[f"{old}->{new}"] += 1
            if len(samples[f"{old}->{new}"]) < 6:
                samples[f"{old}->{new}"].append(r.get("name"))
        r["meal_type"] = new
        # Keep the meal-word tag consistent with the (possibly new) meal_type so
        # tags don't still say "dinner" on a reclassified lunch/breakfast.
        meal_words = {"breakfast", "lunch", "dinner", "snack", "dessert"}
        tags = [t for t in (r.get("tags") or []) if t.lower() not in meal_words]
        if new not in tags:
            tags.insert(0, new)
        r["tags"] = tags
    after = collections.Counter(r.get("meal_type") for r in data)
    print("BEFORE:", dict(before))
    print("AFTER :", dict(after))
    print("\nCHANGES:")
    for k, v in changes.most_common():
        print(f"  {k}: {v}")
        for s in samples[k]:
            print(f"      - {s}")
    if write:
        ASSET.write_text(json.dumps(data, ensure_ascii=False, indent=2))
        print(f"\nWROTE {ASSET}")
    else:
        print("\n(dry-run; pass --write to persist)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
