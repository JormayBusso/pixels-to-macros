#!/usr/bin/env python3
"""Reclassify snack recipes that are actually sauces, gravies, dressings, or marinades.

Run with --write to persist; default is a dry-run preview.
"""
import collections
import json
import re
import sys
from pathlib import Path

ASSET = Path(__file__).resolve().parents[1] / "assets" / "bundled_recipes.json"
CONDIMENT_WORDS = ("sauce", "gravy", "dressing", "marinade")
MEAL_WORDS = {"breakfast", "lunch", "dinner", "snack", "dessert"}


def _has_word(name: str, words) -> bool:
    return any(
        re.search(r"\b" + re.escape(word) + r"\b", name, flags=re.IGNORECASE)
        for word in words
    )


def is_snack_condiment(recipe: dict) -> bool:
    name = recipe.get("name") or ""
    return _has_word(name, CONDIMENT_WORDS) and not _has_word(name, ("dip",))


def main() -> int:
    write = "--write" in sys.argv
    data = json.loads(ASSET.read_text())
    before = collections.Counter(r.get("meal_type") for r in data)
    changes = []

    for recipe in data:
        old = (recipe.get("meal_type") or "dinner").lower()
        if old != "snack" or not is_snack_condiment(recipe):
            continue
        new = "dinner"
        tags = [
            tag for tag in (recipe.get("tags") or []) if tag.lower() not in MEAL_WORDS
        ]
        tags.insert(0, new)
        recipe["meal_type"] = new
        recipe["tags"] = tags
        changes.append((recipe.get("name"), old, new))

    after = collections.Counter(r.get("meal_type") for r in data)
    print("BEFORE:", dict(before))
    print("AFTER :", dict(after))
    print("\nCHANGES:")
    if changes:
        for name, old, new in changes:
            print(f"  - {name}: {old}->{new}")
    else:
        print("  (none)")
    if write:
        ASSET.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        print(f"\nWROTE {ASSET}")
    else:
        print("\n(dry-run; pass --write to persist)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
