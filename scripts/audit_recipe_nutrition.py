#!/usr/bin/env python3
"""Audit recipe ingredient coverage against the app's nutrition database.

For every ingredient used by the bundled recipes this script decides whether the
ingredient can be resolved to a nutrition-database entry (the seeded `FoodData`
list in lib/services/database_service.dart). It reports:

  • total unique ingredients
  • how many resolve to a known food
  • the most common UNRESOLVED ingredient head-words (candidates to add)

Read-only: it never modifies any file. Use the printed candidate list to extend
the FoodData seed, then re-run to confirm coverage improved.
"""
import json
import os
import re
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "lib", "services", "database_service.dart")
RECIPES = os.path.join(ROOT, "assets", "bundled_recipes.json")
LOCALIZER = os.path.join(ROOT, "lib", "services", "ingredient_localizer.dart")

# Words that are quantities, units, or preparation descriptors — never foods.
STOPWORDS = {
    "a", "an", "the", "of", "to", "for", "with", "and", "or", "plus", "extra",
    "taste", "serve", "serving", "optional", "about", "approx", "each", "into",
    "cut", "finely", "roughly", "freshly", "fresh", "dried", "frozen", "canned",
    "tinned", "chopped", "sliced", "diced", "minced", "grated", "ground",
    "crushed", "peeled", "deseeded", "trimmed", "halved", "quartered", "cubed",
    "shredded", "beaten", "softened", "melted", "cooked", "raw", "ripe",
    "small", "medium", "large", "big", "thin", "thick", "whole", "half",
    "quarter", "boneless", "skinless", "lean", "low", "fat", "free", "reduced",
    "good", "quality", "warm", "cold", "hot", "room", "temperature", "fine",
    "coarse", "level", "heaped", "rounded", "generous", "knob", "splash",
    "drizzle", "handful", "bunch", "sprig", "sprigs", "stick", "sticks",
    "clove", "cloves", "can", "cans", "tin", "tins", "jar", "jars", "packet",
    "pack", "bag", "box", "piece", "pieces", "slice", "slices", "wedge",
    "pinch", "dash", "few", "some", "any", "your", "favourite", "favorite",
    # units
    "g", "kg", "mg", "ml", "l", "cl", "dl", "tbsp", "tbsps", "tablespoon",
    "tablespoons", "tsp", "tsps", "teaspoon", "teaspoons", "cup", "cups",
    "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "pint", "pints",
    "quart", "gallon", "gram", "grams", "kilogram", "litre", "liter", "litres",
    "x", "cm", "inch", "inches",
}

NUMBER_RE = re.compile(r"^[\d¼½¾⅓⅔⅛/.,\-–]+$")
WORD_RE = re.compile(r"[a-z\u00c0-\u024f]+", re.IGNORECASE)


def load_food_tokens():
    """Return the set of food words known to the nutrition database."""
    text = open(DB, encoding="utf-8").read()
    # FoodData entries use both single-line (`FoodData(label: 'X'`) and
    # multi-line (`label: 'X',` on its own line) styles, so match any label
    # assignment in the seed file.
    labels = re.findall(r"label:\s*'([^']+)'", text)
    tokens = set()
    for label in labels:
        # Drop parenthetical qualifiers e.g. "Basil (dried)".
        base = re.sub(r"\(.*?\)", " ", label).lower()
        for w in WORD_RE.findall(base):
            if w not in STOPWORDS and len(w) > 2:
                tokens.add(w)
        tokens.add(base.strip())
    return labels, tokens


def load_localizer_terms():
    """Return the set of multilingual ingredient words the IngredientLocalizer
    can bridge to an English nutrition entry (P2 + P3 working together)."""
    terms = set()
    if not os.path.exists(LOCALIZER):
        return terms
    text = open(LOCALIZER, encoding="utf-8").read()
    for forms in re.findall(r"\[([^\[\]]*?)\],", text):
        for form in re.findall(r"'([^']+)'", forms):
            for w in WORD_RE.findall(form.lower()):
                if len(w) > 2:
                    terms.add(w)
    return terms


def singular(word):
    """Cheap English singularisation for plural ingredient nouns."""
    if word.endswith("ies") and len(word) > 4:
        return word[:-3] + "y"
    if word.endswith("es") and len(word) > 4:
        return word[:-2]
    if word.endswith("s") and not word.endswith("ss") and len(word) > 3:
        return word[:-1]
    return word


def content_words(name):
    words = []
    for raw in name.lower().replace("-", " ").split():
        if NUMBER_RE.match(raw):
            continue
        for w in WORD_RE.findall(raw):
            if w in STOPWORDS or len(w) <= 2:
                continue
            words.append(w)
    return words


def main():
    labels, food_tokens = load_food_tokens()
    localizer_terms = load_localizer_terms()
    recipes = json.load(open(RECIPES, encoding="utf-8"))

    def resolves(word):
        return (
            word in food_tokens
            or singular(word) in food_tokens
            or word in localizer_terms
            or singular(word) in localizer_terms
        )

    ingredient_counter = Counter()
    for r in recipes:
        for ing in r.get("ingredients", []) or []:
            name = (ing.get("name") or "").strip()
            if name:
                ingredient_counter[name.lower()] += 1

    resolved = 0
    unresolved = Counter()
    unresolved_heads = Counter()
    for name, freq in ingredient_counter.items():
        words = content_words(name)
        if not words:
            # purely descriptive / water-like; treat as resolved (no nutrition)
            resolved += freq
            continue
        if any(resolves(w) for w in words):
            resolved += freq
        else:
            unresolved[name] += freq
            # head word = last content word (usually the noun in EN)
            unresolved_heads[words[-1]] += freq

    total_unique = len(ingredient_counter)
    total_uses = sum(ingredient_counter.values())
    resolved_unique = total_unique - len(unresolved)

    print("=" * 64)
    print("RECIPE INGREDIENT NUTRITION AUDIT")
    print("=" * 64)
    print(f"Nutrition DB foods (FoodData entries): {len(labels)}")
    print(f"Localizer bridge terms (multilingual): {len(localizer_terms)}")
    print(f"Unique ingredient strings in recipes:  {total_unique}")
    print(f"Total ingredient uses:                 {total_uses}")
    print(
        f"Resolved unique:   {resolved_unique} "
        f"({resolved_unique * 100 // max(total_unique,1)}%)"
    )
    print(f"Unresolved unique: {len(unresolved)}")
    print()
    print("Top 40 UNRESOLVED head-words (candidates to add to FoodData):")
    for word, freq in unresolved_heads.most_common(40):
        print(f"  {freq:5d}  {word}")
    print()
    print("Sample unresolved ingredient strings (top 30 by frequency):")
    for name, freq in unresolved.most_common(30):
        print(f"  {freq:4d}  {name}")


if __name__ == "__main__":
    main()
