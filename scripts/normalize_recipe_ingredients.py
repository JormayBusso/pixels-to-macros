#!/usr/bin/env python3
"""Normalise every recipe ingredient in assets/bundled_recipes.json into a
structured *raw* form.

For each ingredient we rewrite two fields (keeping `grams` untouched for the
nutrition/grocery maths):

  • name   → the clean, shoppable raw ingredient in the recipe's own language
             ("small ripe tomatoes, sliced" → "tomatoes",
              "milde olijfolie" → "olijfolie",
              "fein gehackte Zwiebel" → "Zwiebel").
  • amount → a structured raw amount with a language-correct decimal mark:
               - a piece COUNT when the source amount was a bare number
                 ("2" garlic cloves → "2", "1.5 tomato" → "1,5" in NL/DE/PL),
               - a WEIGHT ("800 g") for bulk items,
               - empty for trace seasonings (salt, pepper, a pinch…).

The conversion is deliberately conservative: a piece count is only produced
when the *original* amount was already a bare number (so the recipe itself
counted pieces). This avoids turning "400 g chopped tomatoes (can)" into a
piece count. If cleaning would empty a name we keep the original.

Run:  python3 scripts/normalize_recipe_ingredients.py
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RECIPES = ROOT / "assets" / "bundled_recipes.json"

# Languages that write decimals with a comma.
COMMA_DECIMAL_LANGS = {"NL", "DE", "PL"}

# ── Multilingual descriptor / preparation noise words ──────────────────────
NOISE = {
    # English
    "warm", "cold", "hot", "fresh", "freshly", "ripe", "large", "small",
    "medium", "big", "extra", "organic", "raw", "cooked", "boiled", "baked",
    "roasted", "grilled", "fried", "toasted", "chopped", "sliced", "diced",
    "minced", "grated", "shredded", "crushed", "ground", "peeled", "halved",
    "quartered", "cubed", "crumbled", "melted", "softened", "drained",
    "rinsed", "dried", "frozen", "canned", "jarred", "smoked", "lean",
    "boneless", "skinless", "virgin", "unsalted", "salted", "plain", "whole",
    "light", "optional", "taste", "finely", "roughly", "thinly", "thickly",
    "good", "quality", "your", "favourite", "favorite", "some", "few",
    "little", "pinch", "of", "a", "an", "the", "for", "and", "with", "into",
    "about", "approximately", "to", "or", "plus", "pieces", "piece", "slices",
    "slice", "beaten", "warmed", "room", "temperature", "packed", "level",
    "heaped", "zested", "juiced", "serve", "extra", "cut", "stoned",
    "bunch", "trimmed", "broken", "chunky", "can", "tin", "tinned",
    "tbsp", "tsp", "bourbon", "stick", "sticks", "bag", "pack",
    "trimmed", "halves", "wedges", "sprig", "sprigs", "handful",
    # Dutch
    "milde", "traditionele", "verse", "gemalen", "gehakte", "gesnipperde",
    "fijngesneden", "fijngehakte", "grof", "grove", "geraspte", "geraspt",
    "gepelde", "ongezouten", "gezouten", "halfvolle", "volle", "magere",
    "vierge", "biologische", "gedroogde", "gerookte", "middelgrote", "grote",
    "kleine", "rijpe", "een", "van", "met", "en", "of", "naar", "smaak",
    "snufje", "optioneel", "in", "stukjes", "reepjes", "plakjes", "blokjes",
    "partjes", "el", "tl", "liter", "ml", "bosje", "teen", "tenen",
    "stuks", "stuk",
    # German
    "fein", "gehackte", "gehackt", "gewürfelte", "gewürfelt", "geriebene",
    "gerieben", "frische", "frisch", "getrocknete", "getrocknet",
    "geräucherte", "geräuchert", "gemahlene", "gemahlen", "große",
    "mittelgroße", "reife", "ungesalzene", "gesalzene", "fettarme", "natives",
    "bio", "eine", "ein", "von", "mit", "und", "oder", "nach", "geschmack",
    "prise", "stücke", "streifen", "scheiben", "würfel", "pck", "stange",
    "stück", "liter", "el", "tl", "bund", "zehe", "zehen",
    # Polish
    "drobno", "posiekany", "posiekana", "posiekane", "starty", "starta",
    "starte", "świeży", "świeża", "świeże", "suszony", "suszona", "wędzony",
    "mielony", "mielona", "mały", "mała", "duży", "duża", "średni", "średnia",
    "dojrzały", "niesolone", "solone", "ze", "lub", "do", "smaku", "szczypta",
    "opcjonalnie", "kostkę", "plasterki", "paski", "z", "łyżka", "łyżki",
    "łyżeczka", "łyżeczki", "szklanka", "szklanki", "ząbek", "ząbki",
    "ząbków", "pęczek", "garść",
}

# Items everyone owns / not bought as a recipe ingredient -> no amount shown.
SEASONING_TOKENS = {
    "salt", "zout", "salz", "sól", "soli",
    "pepper", "peper", "pfeffer", "pieprz",
}

PREP_SPLIT = re.compile(r"[,(\u2013\u2014]")
NON_NAME = re.compile(r"[^a-z\u00c0-\u017f\s-]", re.IGNORECASE)
PURE_NUMBER = re.compile(r"^\s*(\d+(?:[.,]\d+)?)\s*$")
LEADING_NUMBER = re.compile(r"^\s*\d+(?:[.,]\d+)?\s+")


def clean_name(name: str) -> str:
    core = PREP_SPLIT.split(name.lower(), 1)[0]
    core = LEADING_NUMBER.sub("", core)
    core = NON_NAME.sub(" ", core)
    tokens = [t for t in core.split() if t and t not in NOISE]
    cleaned = " ".join(tokens).strip()
    return cleaned if cleaned else name.lower().strip()


def title_preserving(original: str, cleaned: str) -> str:
    """Return the cleaned name, capitalising like the original first word."""
    if not cleaned:
        return cleaned
    # German nouns are capitalised; mirror the original's first-letter case.
    first = original.strip()[:1]
    if first.isupper():
        return cleaned[:1].upper() + cleaned[1:]
    return cleaned


def is_seasoning(cleaned: str) -> bool:
    tokens = cleaned.split()
    return bool(tokens) and all(t in SEASONING_TOKENS for t in tokens)


def fmt_count(value: float, lang: str) -> str:
    if value == int(value):
        text = str(int(value))
    else:
        text = ("%.2f" % value).rstrip("0").rstrip(".")
    if lang in COMMA_DECIMAL_LANGS:
        text = text.replace(".", ",")
    return text


def round_weight(grams: float) -> int:
    if grams < 50:
        return max(5, round(grams / 5) * 5)
    if grams < 500:
        return round(grams / 10) * 10
    return round(grams / 25) * 25


def normalise_amount(amount: str, grams: float, cleaned: str, lang: str) -> str:
    if is_seasoning(cleaned):
        return ""
    m = PURE_NUMBER.match(amount or "")
    if m:
        # Source already counted pieces — keep the count, localise decimals.
        raw = m.group(1).replace(",", ".")
        try:
            value = float(raw)
        except ValueError:
            value = 0.0
        if value > 0:
            return fmt_count(value, lang)
    if grams and grams >= 5:
        return f"{round_weight(grams)} g"
    return ""


def main() -> None:
    data = json.loads(RECIPES.read_text(encoding="utf-8"))
    changed_names = 0
    changed_amounts = 0
    total = 0
    for recipe in data:
        lang = (recipe.get("language") or "EN").upper()
        for ing in recipe.get("ingredients", []):
            total += 1
            original_name = ing.get("name", "")
            grams = float(ing.get("grams") or 0)
            cleaned = clean_name(original_name)
            display_name = title_preserving(original_name, cleaned)
            new_amount = normalise_amount(
                ing.get("amount", ""), grams, cleaned, lang
            )
            if display_name and display_name != original_name:
                ing["name"] = display_name
                changed_names += 1
            if new_amount != ing.get("amount", ""):
                ing["amount"] = new_amount
                changed_amounts += 1
    RECIPES.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"recipes: {len(data)}  ingredients: {total}")
    print(f"names rewritten:   {changed_names}")
    print(f"amounts rewritten: {changed_amounts}")


if __name__ == "__main__":
    main()
