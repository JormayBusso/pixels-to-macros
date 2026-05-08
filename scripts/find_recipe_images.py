#!/usr/bin/env python3
"""
Find real food images for each recipe using DuckDuckGo image search.
Uses curated keyword mapping + web search fallback.
"""

import json
import re
import time
import sys
from pathlib import Path
from typing import Optional

ROOT = Path(__file__).resolve().parent.parent
RECIPES_FILE = ROOT / "assets" / "recipes.json"

try:
    from duckduckgo_search import DDGS
except ImportError:
    print("Install: pip3 install duckduckgo_search")
    sys.exit(1)


def search_food_image(query: str, retries: int = 2) -> Optional[str]:
    """Search for a food image URL using DuckDuckGo."""
    search_query = f"{query} food dish recipe photo"
    for attempt in range(retries):
        try:
            with DDGS() as ddgs:
                results = list(ddgs.images(
                    keywords=search_query,
                    max_results=3,
                    safesearch="moderate",
                    size="Medium",
                    type_image="photo",
                ))
            if results:
                # Prefer images from reputable food sites
                preferred_domains = [
                    "upload.wikimedia.org",
                    "images.unsplash.com",
                    "img.sndimg.com",  # Food Network
                    "www.simplyrecipes.com",
                    "www.budgetbytes.com",
                    "cookieandkate.com",
                    "pinchofyum.com",
                    "www.seriouseats.com",
                    "assets.bonappetit.com",
                    "food.fnr.sndimg.com",
                    "www.allrecipes.com",
                    "imagesvc.meredithcorp.io",
                    "www.eatingwell.com",
                    "static01.nyt.com",
                    "hips.hearstapps.com",
                ]
                for r in results:
                    url = r.get("image", "")
                    if any(d in url for d in preferred_domains):
                        return url
                # Fallback to first result
                url = results[0].get("image", "")
                if url and url.startswith("http"):
                    return url
        except Exception as e:
            if "Ratelimit" in str(e) or "429" in str(e):
                wait = 5 * (attempt + 1)
                print(f"  Rate limited, waiting {wait}s...")
                time.sleep(wait)
            else:
                print(f"  Search error for '{query}': {e}")
                break
    return None


def clean_recipe_name_for_search(name: str) -> str:
    """Clean recipe name for better search results."""
    # Remove prefixes that won't help image search
    n = name
    prefixes = [
        "Asian-style", "Mediterranean", "Italian", "Home-style",
        "Herbed", "Quick", "Garlic", "Roasted", "Baked", "Simple",
        "Rustic", "Spicy", "Zesty", "Smoky", "Grilled", "Loaded",
        "Classic", "Pan-seared", "Lemon", "Herb", "Fresh", "Creamy",
        "One-pot", "Hearty", "Light", "Sheet-pan", "Crispy", "Tangy",
        "Savory", "Double",
    ]
    for p in prefixes:
        if n.startswith(p + " "):
            n = n[len(p):].strip()
            break
    # Remove parenthetical clarifications
    n = re.sub(r"\s*\(.*?\)\s*", " ", n).strip()
    return n


def main():
    with open(RECIPES_FILE, "r") as f:
        recipes = json.load(f)

    total = len(recipes)
    found = 0
    failed = 0

    print(f"Searching images for {total} recipes...")

    for i, recipe in enumerate(recipes):
        name = recipe["name"]
        search_name = clean_recipe_name_for_search(name)

        print(f"[{i+1}/{total}] {name} -> searching '{search_name}'...", end=" ")

        url = search_food_image(search_name)
        if url:
            recipe["image"] = url
            found += 1
            print(f"OK")
        else:
            recipe["image"] = None
            failed += 1
            print(f"NOT FOUND")

        # Be polite with rate limits
        if (i + 1) % 10 == 0:
            time.sleep(1)

    print(f"\nDone! Found: {found}/{total}, Failed: {failed}")

    with open(RECIPES_FILE, "w") as f:
        json.dump(recipes, f, indent=2, ensure_ascii=False)
    print(f"Saved to {RECIPES_FILE}")


if __name__ == "__main__":
    main()
