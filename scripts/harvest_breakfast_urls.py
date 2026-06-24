#!/usr/bin/env python3
"""Harvest breakfast/brunch recipe URLs from bbcgoodfood collection pages and
append the new ones to recipe_urls.txt (EN). bbcgoodfood publishes real
nutrition, so these stay real-nutrition recipes (no estimation).

Usage:
    python3 scripts/harvest_breakfast_urls.py
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
URLS_FILE = ROOT / "recipe_urls.txt"
BASE = "https://www.bbcgoodfood.com"
UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/125.0 Safari/537.36"
)

COLLECTIONS = (
    "breakfast-recipes",
    "brunch-recipes",
    "healthy-breakfast-recipes",
    "vegetarian-breakfast-recipes",
    "vegan-breakfast-recipes",
    "pancake-recipes",
    "healthy-pancake-recipes",
    "porridge-recipes",
    "overnight-oats-recipes",
    "smoothie-recipes",
    "healthy-smoothie-recipes",
    "granola-recipes",
    "egg-recipes",
    "breakfast-egg-recipes",
    "omelette-recipes",
    "scrambled-egg-recipes",
    "french-toast-recipes",
    "muffin-recipes",
    "breakfast-muffin-recipes",
    "shakshuka-recipes",
    "easy-breakfast-recipes",
    "breakfast-bar-recipes",
    "avocado-recipes",
    "bagel-recipes",
    "crumpet-recipes",
    "waffle-recipes",
    "frittata-recipes",
    "kedgeree-recipes",
)

# Skip obvious non-breakfast slugs that sometimes appear in mixed collections.
SKIP_SLUG = re.compile(
    r"(curry|stew|roast|steak|burger|pasta|noodle|risotto|casserole|lasagn|"
    r"ragu|ragout|chili|chilli|dinner|paella|biryani|tagine)"
)


def curl(url: str) -> str:
    try:
        out = subprocess.run(
            ["curl", "-s", "-A", UA, "--max-time", "30", url],
            capture_output=True,
            timeout=40,
        )
        return out.stdout.decode("utf-8", "ignore")
    except Exception:
        return ""


def harvest() -> list[str]:
    found: set[str] = set()
    for slug in COLLECTIONS:
        html = curl(f"{BASE}/recipes/collection/{slug}")
        links = set(re.findall(r"/recipes/[a-z0-9-]+", html))
        keep = 0
        for link in links:
            tail = link.split("/recipes/", 1)[1]
            if tail in {"collection", "category", "guide", "how-to"}:
                continue
            if SKIP_SLUG.search(tail):
                continue
            found.add(BASE + link)
            keep += 1
        print(f"[harvest] {slug}: {keep} recipe links")
    return sorted(found)


def main() -> int:
    existing_lines = (
        URLS_FILE.read_text(encoding="utf-8").splitlines() if URLS_FILE.exists() else []
    )
    existing_urls = set()
    for line in existing_lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        url = line.split("\t", 1)[1] if "\t" in line else line
        existing_urls.add(url.strip())

    harvested = harvest()
    new_urls = [u for u in harvested if u not in existing_urls]
    print(f"[harvest] total unique harvested={len(harvested)} new (not in pool)={len(new_urls)}")
    if new_urls:
        with URLS_FILE.open("a", encoding="utf-8") as fh:
            for url in new_urls:
                fh.write(f"EN\t{url}\n")
        print(f"[harvest] appended {len(new_urls)} EN breakfast URLs to {URLS_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
