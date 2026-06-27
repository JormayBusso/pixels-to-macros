#!/usr/bin/env python3
"""
Build a local offline recipe database for Pixels to Macros.

Phase 1 crawls recipe URLs from robots.txt/sitemap.xml (or recipe index pages).
Phase 2 extracts recipe content with recipe-scrapers, compresses images to WebP,
and progressively writes assets/bundled_recipes.json.

Install:
    pip install -r scripts/recipe_scraper_requirements.txt
    playwright install chromium

Examples:
    python scripts/scrape_real_recipes.py crawl --target-per-language 800
    python scripts/scrape_real_recipes.py extract --max-recipes 3000
    python scripts/scrape_real_recipes.py all --target-per-language 800 --max-recipes 3000

    # Balance the starved buckets WITHOUT touching the curated DB: scrape only
    # breakfast/lunch/snack into a staging file, then review + merge:
    python scripts/scrape_real_recipes.py extract-balanced --per-meal-target 140
    python scripts/scrape_real_recipes.py merge-staging
    python scripts/balance_recipe_database.py --write
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import io
import json
import random
import re
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from urllib.parse import urljoin, urlparse

try:
    import requests
except ModuleNotFoundError:  # pragma: no cover - handled at runtime
    requests = None

try:
    from bs4 import BeautifulSoup
except ModuleNotFoundError:  # pragma: no cover - handled at runtime
    BeautifulSoup = None

try:
    from PIL import Image, ImageOps
except ModuleNotFoundError:  # pragma: no cover - handled at runtime
    Image = None
    ImageOps = None

try:
    from recipe_scrapers import scrape_me
except ModuleNotFoundError:  # pragma: no cover - handled at runtime
    scrape_me = None

ROOT = Path(__file__).resolve().parents[1]
URLS_FILE = ROOT / "recipe_urls.txt"
OUTPUT_JSON = ROOT / "assets" / "bundled_recipes.json"
IMAGE_DIR = ROOT / "assets" / "images" / "recipes"

USER_AGENTS = [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/125.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/125.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
]

REQUEST_TIMEOUT = 25
IMAGE_MAX_BYTES = 50 * 1024
SAVE_EVERY = 10


def require_dependency(value: object, package_name: str) -> None:
    if value is None:
        raise RuntimeError(
            f"Missing dependency '{package_name}'. Install with: "
            "pip install -r scripts/recipe_scraper_requirements.txt"
        )


@dataclass(frozen=True)
class SiteConfig:
    language: str
    country: str
    base_url: str
    recipe_patterns: tuple[str, ...]
    sitemap_hints: tuple[str, ...] = ()
    index_pages: tuple[str, ...] = ()


SITES: tuple[SiteConfig, ...] = (
    SiteConfig(
        language="NL",
        country="Netherlands",
        base_url="https://www.ah.nl/",
        recipe_patterns=("/allerhande/recept/", "/allerhande/recepten/"),
        sitemap_hints=("https://www.ah.nl/sitemap.xml",),
        index_pages=("https://www.ah.nl/allerhande/recepten",),
    ),
    SiteConfig(
        language="DE",
        country="Germany",
        base_url="https://www.chefkoch.de/",
        recipe_patterns=("/rezepte/",),
        sitemap_hints=("https://www.chefkoch.de/sitemap.xml",),
        index_pages=("https://www.chefkoch.de/rezepte/",),
    ),
    SiteConfig(
        language="PL",
        country="Poland",
        base_url="https://www.kwestiasmaku.com/",
        recipe_patterns=("/przepis/", "/kuchnia_", "/zielony_srodek/"),
        sitemap_hints=("https://www.kwestiasmaku.com/sitemap.xml",),
        index_pages=("https://www.kwestiasmaku.com/przepisy",),
    ),
    SiteConfig(
        language="ES",
        country="Spain",
        base_url="https://www.hogarmania.com/",
        recipe_patterns=("/cocina/recetas/",),
        sitemap_hints=("https://www.hogarmania.com/sitemap.xml",),
        index_pages=("https://www.hogarmania.com/cocina/recetas/",),
    ),
    SiteConfig(
        language="EN",
        country="UK/US",
        base_url="https://www.bbcgoodfood.com/",
        recipe_patterns=("/recipes/",),
        sitemap_hints=("https://www.bbcgoodfood.com/sitemap.xml",),
        index_pages=("https://www.bbcgoodfood.com/recipes",),
    ),
    SiteConfig(
        language="EN",
        country="UK/US",
        base_url="https://www.allrecipes.com/",
        recipe_patterns=("/recipe/",),
        sitemap_hints=("https://www.allrecipes.com/sitemap.xml",),
        index_pages=("https://www.allrecipes.com/recipes/",),
    ),
    SiteConfig(
        language="EN",
        country="UK/US",
        base_url="https://www.eatingwell.com/",
        recipe_patterns=("/recipe/",),
        sitemap_hints=("https://www.eatingwell.com/sitemap.xml",),
        index_pages=("https://www.eatingwell.com/recipes/",),
    ),
    SiteConfig(
        language="EN",
        country="US",
        base_url="https://www.simplyrecipes.com/",
        recipe_patterns=("-recipe-", "/recipes/"),
        sitemap_hints=("https://www.simplyrecipes.com/sitemap_1.xml",),
        index_pages=("https://www.simplyrecipes.com/recipes/",),
    ),
    SiteConfig(
        language="EN",
        country="US",
        base_url="https://www.food.com/",
        recipe_patterns=("/recipe/",),
        sitemap_hints=("https://www.food.com/sitemap.xml",),
        index_pages=("https://www.food.com/recipe-finder/all",),
    ),
)


def build_session() -> requests.Session:
    require_dependency(requests, "requests")
    session = requests.Session()
    session.headers.update(
        {
            "User-Agent": random.choice(USER_AGENTS),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9,nl;q=0.8,de;q=0.8,pl;q=0.8,es;q=0.8",
            "Connection": "keep-alive",
        }
    )
    return session


def fetch_text(
    session: requests.Session,
    url: str,
    *,
    use_playwright_on_block: bool = False,
) -> str | None:
    try:
        response = session.get(url, timeout=REQUEST_TIMEOUT, allow_redirects=True)
        if response.status_code in {403, 429, 503}:
            print(f"[blocked] {response.status_code} {url}")
            if use_playwright_on_block:
                return fetch_text_playwright(url)
            return None
        response.raise_for_status()
        return response.text
    except Exception as exc:
        print(f"[fetch failed] {url}: {exc}")
        if use_playwright_on_block:
            return fetch_text_playwright(url)
        return None


def fetch_text_playwright(url: str) -> str | None:
    """Optional stealth fallback for Phase 1 when requests is blocked."""
    try:
        from playwright.sync_api import sync_playwright
        try:
            from playwright_stealth import stealth_sync
        except Exception:
            stealth_sync = None
    except Exception as exc:
        print(f"[playwright unavailable] {exc}")
        return None

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page(
                user_agent=random.choice(USER_AGENTS),
                viewport={"width": 1366, "height": 900},
                locale="en-US",
            )
            if stealth_sync is not None:
                stealth_sync(page)
            page.goto(url, wait_until="domcontentloaded", timeout=45000)
            page.wait_for_timeout(random.randint(1200, 2400))
            content = page.content()
            browser.close()
            return content
    except Exception as exc:
        print(f"[playwright failed] {url}: {exc}")
        return None


def robots_sitemaps(session: requests.Session, site: SiteConfig, use_playwright: bool) -> list[str]:
    robots_url = urljoin(site.base_url, "/robots.txt")
    text = fetch_text(session, robots_url, use_playwright_on_block=use_playwright)
    found: list[str] = []
    if text:
        for line in text.splitlines():
            if line.lower().startswith("sitemap:"):
                sitemap = line.split(":", 1)[1].strip()
                if sitemap:
                    found.append(sitemap)
    found.extend(site.sitemap_hints)
    return list(dict.fromkeys(found))


def parse_xml_locs(xml_text: str) -> list[str]:
    try:
        root = ET.fromstring(xml_text.encode("utf-8"))
    except ET.ParseError:
        return []
    locs: list[str] = []
    for elem in root.iter():
        if elem.tag.endswith("loc") and elem.text:
            locs.append(elem.text.strip())
    return locs


def looks_like_recipe(url: str, site: SiteConfig) -> bool:
    parsed = urlparse(url)
    if not parsed.scheme.startswith("http"):
        return False
    path = parsed.path.lower()
    if any(pattern.lower() in path for pattern in site.recipe_patterns):
        blocked_ext = (".xml", ".jpg", ".png", ".webp", ".pdf", ".json")
        return not path.endswith(blocked_ext)
    return False


def looks_like_sitemap(url: str) -> bool:
    lower = url.lower()
    return lower.endswith(".xml") or "sitemap" in lower


def crawl_sitemap_tree(
    session: requests.Session,
    site: SiteConfig,
    sitemap_url: str,
    *,
    use_playwright: bool,
    max_sitemaps: int,
) -> set[str]:
    queue = [sitemap_url]
    seen_sitemaps: set[str] = set()
    recipe_urls: set[str] = set()

    while queue and len(seen_sitemaps) < max_sitemaps:
        current = queue.pop(0)
        if current in seen_sitemaps:
            continue
        seen_sitemaps.add(current)

        text = fetch_text(session, current, use_playwright_on_block=use_playwright)
        if not text:
            continue

        locs = parse_xml_locs(text)
        if not locs and "<html" in text[:500].lower():
            locs = extract_links_from_html(text, current)

        for loc in locs:
            if looks_like_recipe(loc, site):
                recipe_urls.add(loc)
            elif looks_like_sitemap(loc) and len(seen_sitemaps) + len(queue) < max_sitemaps:
                if any(keyword in loc.lower() for keyword in ("recipe", "recept", "rezepte", "recetas", "allerhande", "przepis", "post")):
                    queue.append(loc)

        print(
            f"[sitemap] {site.language} {current} -> "
            f"{len(recipe_urls)} recipes, {len(queue)} queued"
        )

    return recipe_urls


def extract_links_from_html(html: str, base_url: str) -> list[str]:
    require_dependency(BeautifulSoup, "beautifulsoup4")
    soup = BeautifulSoup(html, "html.parser")
    links: list[str] = []
    for anchor in soup.select("a[href]"):
        href = anchor.get("href", "").strip()
        if href:
            links.append(urljoin(base_url, href))
    return links


def crawl_index_pages(
    session: requests.Session,
    site: SiteConfig,
    *,
    use_playwright: bool,
    max_pages: int = 25,
) -> set[str]:
    urls: set[str] = set()
    visited: set[str] = set()
    queue = list(site.index_pages)

    while queue and len(visited) < max_pages:
        page_url = queue.pop(0)
        if page_url in visited:
            continue
        visited.add(page_url)
        html = fetch_text(session, page_url, use_playwright_on_block=use_playwright)
        if not html:
            continue
        links = extract_links_from_html(html, page_url)
        for link in links:
            if looks_like_recipe(link, site):
                urls.add(link)
            elif urlparse(link).netloc == urlparse(site.base_url).netloc and len(queue) < max_pages:
                if any(pattern.strip("/") in link.lower() for pattern in site.recipe_patterns):
                    queue.append(link)
        print(f"[index] {site.language} {page_url} -> {len(urls)} recipes")
    return urls


def crawl_recipe_urls(
    target_per_language: int,
    *,
    use_playwright_on_block: bool,
    max_sitemaps_per_site: int,
) -> list[tuple[str, str]]:
    session = build_session()
    by_language: dict[str, set[str]] = {}

    for site in SITES:
        print(f"\n=== Crawling {site.country}: {site.base_url} ===")
        site_urls: set[str] = set()
        for sitemap in robots_sitemaps(session, site, use_playwright_on_block):
            site_urls.update(
                crawl_sitemap_tree(
                    session,
                    site,
                    sitemap,
                    use_playwright=use_playwright_on_block,
                    max_sitemaps=max_sitemaps_per_site,
                )
            )
            if len(site_urls) >= target_per_language:
                break

        if len(site_urls) < max(50, target_per_language // 10):
            site_urls.update(
                crawl_index_pages(session, site, use_playwright=use_playwright_on_block)
            )

        sampled = random.sample(list(site_urls), min(target_per_language, len(site_urls)))
        by_language.setdefault(site.language, set()).update(sampled)
        print(f"[done] {site.language} collected {len(sampled)} from {site.base_url}")

    rows: list[tuple[str, str]] = []
    for language, urls in sorted(by_language.items()):
        for url in sorted(urls):
            rows.append((language, url))

    random.shuffle(rows)
    save_urls(rows)
    return rows


def save_urls(rows: Iterable[tuple[str, str]]) -> None:
    URLS_FILE.write_text(
        "\n".join(f"{language}\t{url}" for language, url in rows) + "\n",
        encoding="utf-8",
    )
    print(f"[saved] {URLS_FILE}")


def read_urls() -> list[tuple[str, str]]:
    if not URLS_FILE.exists():
        raise FileNotFoundError(f"Missing {URLS_FILE}. Run crawl first.")
    rows: list[tuple[str, str]] = []
    for line in URLS_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "\t" in line:
            language, url = line.split("\t", 1)
        else:
            language, url = language_from_url(line), line
        rows.append((language.strip().upper(), url.strip()))
    return rows


def language_from_url(url: str) -> str:
    host = urlparse(url).netloc.lower()
    if "ah.nl" in host:
        return "NL"
    if "chefkoch" in host:
        return "DE"
    if "kwestiasmaku" in host:
        return "PL"
    if "hogarmania" in host:
        return "ES"
    return "EN"


def slugify(text: str, max_len: int = 56) -> str:
    text = text.lower().strip()
    text = re.sub(r"[^a-z0-9]+", "_", text)
    text = re.sub(r"_+", "_", text).strip("_")
    return (text[:max_len].strip("_") or "recipe")


def unique_id(language: str, title: str, url: str) -> str:
    digest = hashlib.sha1(url.encode("utf-8")).hexdigest()[:10]
    return f"{language.lower()}_{slugify(title)}_{digest}"


def parse_number(value: object) -> float | int | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(value) if float(value).is_integer() else float(value)
    text = str(value).replace(",", ".")
    match = re.search(r"\d+(?:\.\d+)?", text)
    if not match:
        return None
    number = float(match.group(0))
    return int(number) if number.is_integer() else number


def parse_time_minutes(value: object) -> int:
    if value is None:
        return 0
    if isinstance(value, (int, float)):
        return int(value)
    text = str(value).strip()
    iso_match = re.fullmatch(
        r"P(?:\d+D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?",
        text,
        flags=re.IGNORECASE,
    )
    if iso_match:
        hours = int(iso_match.group(1) or 0)
        minutes = int(iso_match.group(2) or 0)
        seconds = int(iso_match.group(3) or 0)
        return hours * 60 + minutes + (1 if seconds >= 30 else 0)
    parsed = parse_number(text)
    return int(parsed or 0)


def first_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, list):
        for item in value:
            text = first_text(item)
            if text:
                return text
        return ""
    if isinstance(value, dict):
        for key in ("url", "contentUrl", "text", "name", "@id"):
            text = first_text(value.get(key))
            if text:
                return text
    return str(value).strip()


def flatten_jsonld(value: object) -> Iterable[dict]:
    if isinstance(value, list):
        for item in value:
            yield from flatten_jsonld(item)
    elif isinstance(value, dict):
        yield value
        graph = value.get("@graph")
        if graph is not None:
            yield from flatten_jsonld(graph)


def is_recipe_node(node: dict) -> bool:
    node_type = node.get("@type")
    if isinstance(node_type, str):
        return node_type.lower() == "recipe"
    if isinstance(node_type, list):
        return any(str(item).lower() == "recipe" for item in node_type)
    return False


def jsonld_instruction_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, list):
        parts = [jsonld_instruction_text(item) for item in value]
        return "\n".join(part for part in parts if part)
    if isinstance(value, dict):
        if "itemListElement" in value:
            return jsonld_instruction_text(value.get("itemListElement"))
        return first_text(value.get("text") or value.get("name"))
    return str(value).strip()


class JsonLdRecipeScraper:
    def __init__(self, node: dict, url: str):
        self.node = node
        self.url = url

    def title(self) -> str:
        return first_text(self.node.get("name") or self.node.get("headline"))

    def ingredients(self) -> list[str]:
        raw = self.node.get("recipeIngredient") or self.node.get("ingredients") or []
        if isinstance(raw, str):
            return [raw]
        if isinstance(raw, list):
            return [first_text(item) for item in raw if first_text(item)]
        return []

    def instructions(self) -> str:
        return jsonld_instruction_text(self.node.get("recipeInstructions"))

    def image(self) -> str:
        return urljoin(self.url, first_text(self.node.get("image")))

    def nutrients(self) -> dict:
        nutrition = self.node.get("nutrition")
        return nutrition if isinstance(nutrition, dict) else {}

    def total_time(self) -> int:
        return parse_time_minutes(
            self.node.get("totalTime")
            or self.node.get("cookTime")
            or self.node.get("prepTime")
        )

    def yields(self) -> object:
        return self.node.get("recipeYield") or self.node.get("yield")


def create_json_ld_scraper(session: requests.Session, url: str) -> JsonLdRecipeScraper | None:
    html = fetch_text(session, url, use_playwright_on_block=False)
    if not html:
        return None
    require_dependency(BeautifulSoup, "beautifulsoup4")
    soup = BeautifulSoup(html, "html.parser")
    for script in soup.select('script[type="application/ld+json"]'):
        raw = script.string or script.get_text(" ", strip=True)
        if not raw:
            continue
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            continue
        for node in flatten_jsonld(data):
            if is_recipe_node(node):
                return JsonLdRecipeScraper(node, url)
    return None


def normalize_macros(nutrients: dict | None) -> dict[str, float | int]:
    nutrients = nutrients or {}
    aliases = {
        "calories": ("calories", "caloriesContent", "energy", "Energy"),
        "protein": ("protein", "proteinContent", "Protein"),
        "carbs": ("carbs", "carbohydrateContent", "carbohydrates", "Carbohydrate"),
        "fat": ("fat", "fatContent", "Fat"),
        "fiber": ("fiber", "fiberContent", "Fiber"),
        "sugar": ("sugar", "sugarContent", "Sugar"),
    }
    out: dict[str, float | int] = {}
    for target, keys in aliases.items():
        for key in keys:
            if key in nutrients:
                parsed = parse_number(nutrients[key])
                if parsed is not None:
                    out[target] = parsed
                    break
    return out


def parse_servings(yields_value: object) -> int:
    if yields_value is None:
        return 1
    if isinstance(yields_value, (int, float)):
        return max(1, min(24, int(round(float(yields_value)))))
    text = str(yields_value).lower().replace(",", ".")
    match = re.search(r"\d+(?:\.\d+)?", text)
    if not match:
        return 1
    return max(1, min(24, int(round(float(match.group(0))))))


def scale_macros_to_recipe_total(macros_per_serving: dict[str, float | int], servings: int) -> dict[str, float | int]:
    total: dict[str, float | int] = {}
    for key, value in macros_per_serving.items():
        scaled = float(value) * max(1, servings)
        total[key] = int(round(scaled)) if key == "calories" else round(scaled, 1)
    return total


def per_serving(macros_total: dict[str, float | int], key: str, servings: int) -> float:
    value = macros_total.get(key, 0)
    try:
        return float(value) / max(1, servings)
    except (TypeError, ValueError):
        return 0.0


def estimate_ingredient_grams(raw: str) -> tuple[str, str, float]:
    text = re.sub(r"\s+", " ", raw.strip())
    if not text:
        return "", "", 0.0

    amount_match = re.match(
        r"^((?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:[\.,]\d+)?)\s*"
        r"(?:kg|g|gram|grams|ml|l|liter|litre|cup|cups|tbsp|tablespoons?|tsp|teaspoons?|oz|ounce|ounces|lb|pound|pounds|stuk|stuks|el|tl|dag|kg\.|g\.|ml\.)?)\b",
        text,
        flags=re.IGNORECASE,
    )
    amount = amount_match.group(1).strip() if amount_match else ""
    name = text[amount_match.end():].strip(" ,.-") if amount_match else text
    name = re.sub(
        r"^(of|de|der|die|das|van|voor|do|de\s+la|del|of\s+the)\s+",
        "",
        name,
        flags=re.IGNORECASE,
    ).strip()

    value = 0.0
    value_match = re.match(r"(\d+\s+\d+/\d+|\d+/\d+|\d+(?:[\.,]\d+)?)", amount)
    if value_match:
        raw_value = value_match.group(1).replace(",", ".")
        if " " in raw_value and "/" in raw_value:
            whole, frac = raw_value.split(" ", 1)
            num, den = frac.split("/", 1)
            value = float(whole) + float(num) / max(1.0, float(den))
        elif "/" in raw_value:
            num, den = raw_value.split("/", 1)
            value = float(num) / max(1.0, float(den))
        else:
            value = float(raw_value)

    unit_text = amount.lower()
    grams = 0.0
    if value > 0:
        if re.search(r"(?:^|[^a-z])kg(?:\.|$)", unit_text):
            grams = value * 1000
        elif re.search(r"(?:^|[^a-z])g(?:\.|$)|gram", unit_text):
            grams = value
        elif re.search(r"(?:^|[^a-z])ml(?:\.|$)", unit_text):
            grams = value
        elif re.search(r"(?:^|[^a-z])l(?:\.|$)|liter|litre", unit_text):
            grams = value * 1000
        elif "tbsp" in unit_text or "tablespoon" in unit_text or " el" in f" {unit_text}":
            grams = value * 15
        elif "tsp" in unit_text or "teaspoon" in unit_text or " tl" in f" {unit_text}":
            grams = value * 5
        elif "cup" in unit_text:
            grams = value * 240
        elif "oz" in unit_text or "ounce" in unit_text:
            grams = value * 28.35
        elif "lb" in unit_text or "pound" in unit_text:
            grams = value * 453.6
        elif "stuk" in unit_text or "piece" in unit_text:
            grams = value * 100
        else:
            lowered_name = name.lower()
            if "egg" in lowered_name or "ei" in lowered_name or "jaj" in lowered_name or "huevo" in lowered_name:
                grams = value * 50
            elif "slice" in lowered_name or "snee" in lowered_name:
                grams = value * 30
            else:
                grams = value * 100

    grams = round(max(0.0, min(2500.0, grams)), 1)
    return name or text, amount or text, grams


def normalize_ingredients(raw_ingredients: list[str]) -> list[dict[str, object]]:
    parsed: list[dict[str, object]] = []
    for raw in raw_ingredients:
        name, amount, grams = estimate_ingredient_grams(raw)
        if not name:
            continue
        parsed.append({"name": name, "amount": amount, "grams": grams})
    return parsed


def infer_meal_type(title: str, url: str, ingredients: list[str]) -> str:
    blob = " ".join([title, url]).lower().replace("-", " ").replace("_", " ")
    keyword_groups = {
        "breakfast": (
            "breakfast", "brunch", "pancake", "waffle", "porridge", "granola", "overnight oats",
            "smoothie", "shake", "yogurt", "yoghurt", "muesli", "omelet", "omelette", "frittata",
            "scrambled egg", "scrambled eggs", "baked eggs", "fried egg", "poached egg", "boiled egg",
            "oats", "oatmeal", "rolled oats", "bircher", "chia pudding",
            "on toast", "french toast", "avocado toast", "smashed avocado",
            "bagel", "bagels", "crumpet", "crumpets", "english muffin", "breakfast muffin", "egg muffin",
            "eggs benedict", "eggs florentine", "eggs royale", "huevos rancheros",
            "shakshuka", "shakshouka", "hash brown", "hash browns", "kedgeree",
            "croissant", "crepe", "crepes", "breakfast bar", "granola bar",
            "ontbijt", "havermout", "frühstück", "fruehstueck", "śniadanie", "sniadanie", "desayuno",
        ),
        "dessert": (
            "dessert", "cake", "cookie", "brownie", "pudding", "ice cream", "tart", "pie", "muffin",
            "taart", "koek", "gebak", "toetje", "kuchen", "keks", "nachspeise", "ciasto", "deser",
            "postre", "flan", "bizcocho", "tarta", "chocolate", "cheesecake",
        ),
        "snack": (
            "snack", "smoothie", "shake", "juice", "tea", "coffee", "latte", "dip", "spread", "sauce",
            "bites", "bars", "energy balls", "popcorn", "nuts", "crackers", "hummus", "guacamole",
            "borrel", "tussendoor", "dip", "aufstrich", "snack", "przekąska", "przekaska", "merienda",
        ),
        "lunch": (
            "lunch", "sandwich", "wrap", "salad", "bowl", "toastie", "broodje", "mittag", "almuerzo",
        ),
    }
    for meal_type, keywords in keyword_groups.items():
        if any(keyword in blob for keyword in keywords):
            return meal_type
    return "dinner"


MEAT_SEAFOOD_TERMS = (
    "beef", "steak", "chicken", "pork", "bacon", "ham", "turkey", "lamb", "veal", "duck", "fish", "salmon",
    "tuna", "shrimp", "prawn", "anchovy", "gelatin", "gelatine", "salami", "sausage", "prosciutto", "chorizo", "pancetta",
    "crab", "lobster", "mussel", "oyster", "clam", "squid", "octopus", "scallop", "cod", "haddock", "mackerel", "sardine",
    "kip", "kipfilet", "kippen", "kippenpoten", "rund", "rundvlees", "varken", "varkenshaas", "varkensfilet",
    "varkensfiletlapjes", "vlees", "gehakt", "gehaktbal", "biefstuk", "bief", "spek", "spekjes", "garnalen",
    "zalm", "tonijn", "makreel", "mosselen", "vis", "vissticks", "kibbeling", "forel", "kabeljauw", "dorade",
    "zeebaars", "schol", "ree", "reebout", "wild", "haring", "vongole",
    "hähnchen", "haehnchen", "huhn", "pute", "rind", "rinder", "schwein", "fleisch", "fisch", "lachs",
    "thunfisch", "forelle", "kabeljau", "dorade", "hackfleisch", "speck", "schinken", "wurst",
    "kurczak", "wołow", "wolow", "wieprz",
    "pollo", "ternera", "cerdo", "jamón", "jamon",
)


DAIRY_EGG_HONEY_TERMS = (
    "egg", "eggs", "milk", "cream", "butter", "cheese", "cheddar", "feta", "mozzarella", "parmesan",
    "ricotta", "goat cheese", "cream cheese", "yogurt", "yoghurt", "halloumi", "paneer", "camembert", "brie",
    "mascarpone", "custard", "kefir", "honey", "mayonnaise", "whey", "ghee",
    "ei", "eieren", "eier", "eiern", "melk", "kaas", "geitenkaas", "roomkaas", "kwark", "boter", "milch",
    "käse", "kaese", "hüttenkäse", "huettenkaese", "schafskäse", "schafskaese", "quark",
    "jaj", "jajo", "jaja", "mleko", "ser", "masło", "maslo",
    "huevo", "huevos", "leche", "queso", "mantequilla", "miel",
)


VEGAN_POSITIVE_TERMS = (
    "vegan", "plant-based", "plant based", "wegań", "wegansk", "vegano", "vegana",
    "dairy-free", "dairy free", "tofu", "tempeh", "seitan", "lentil", "chickpea", "black bean", "kidney bean",
)


VEGETARIAN_POSITIVE_TERMS = (
    "vegetarian", "veggie", "meatless", "vega", "vegetarisch", "wegetariań", "wegetarians", "vegetariano", "vegetariana",
)


def contains_any_term(blob: str, terms: tuple[str, ...]) -> bool:
    padded = f" {blob.lower()} "
    for term in terms:
        escaped = re.escape(term.lower())
        if re.search(rf"(?<![a-z]){escaped}(?![a-z])", padded):
            return True
    return False


def is_probably_vegan(title: str, ingredients: list[str]) -> bool:
    blob = " ".join([title, *ingredients]).lower()
    if contains_any_term(blob, MEAT_SEAFOOD_TERMS) or contains_any_term(blob, DAIRY_EGG_HONEY_TERMS):
        return False
    return True


def is_probably_vegetarian(title: str, ingredients: list[str]) -> bool:
    blob = " ".join([title, *ingredients]).lower()
    if contains_any_term(blob, MEAT_SEAFOOD_TERMS):
        return False
    return True


def classify_goals(
    *,
    title: str,
    ingredients: list[str],
    macros_total: dict[str, float | int],
    servings: int,
    meal_type: str,
    nutrition_estimated: bool = False,
) -> list[str]:
    calories = per_serving(macros_total, "calories", servings)
    protein = per_serving(macros_total, "protein", servings)
    carbs = per_serving(macros_total, "carbs", servings)
    fiber = per_serving(macros_total, "fiber", servings)
    sugar = per_serving(macros_total, "sugar", servings)
    fat = per_serving(macros_total, "fat", servings)
    net_carbs = max(0.0, carbs - fiber)

    goals: set[str] = {"maintain"}
    # Macro-derived goals (diabetes/keto/weight_loss/muscle) require REAL published
    # nutrition. When macros were ESTIMATED from ingredients we skip them entirely
    # so estimated numbers never drive medical (diabetes/insulin) or fitness
    # recommendations. Ingredient-derived vegan/vegetarian tags stay valid.
    if not nutrition_estimated:
        if meal_type == "breakfast":
            diabetes_carb_limit = 20
        elif meal_type == "dessert":
            diabetes_carb_limit = 25
        else:
            diabetes_carb_limit = 35

        if calories > 0 and carbs <= diabetes_carb_limit and sugar <= 15:
            goals.add("diabetes")
        if calories > 0 and net_carbs <= 20 and fat >= protein * 0.7:
            goals.add("keto")
        if calories > 0 and calories <= 600 and protein >= 15:
            goals.add("weight_loss")

        muscle_min_calories = {
            "breakfast": 450,
            "lunch": 550,
            "dinner": 650,
            "snack": 300,
            "dessert": 350,
        }.get(meal_type, 450)
        if calories >= muscle_min_calories and protein >= 25:
            goals.add("muscle")
    if is_probably_vegan(title, ingredients):
        goals.add("vegan")
        goals.add("vegetarian")
    elif is_probably_vegetarian(title, ingredients):
        goals.add("vegetarian")
    return sorted(goals)


def compute_health_score(macros_total: dict[str, float | int], servings: int, goals: list[str]) -> tuple[int, str]:
    calories = per_serving(macros_total, "calories", servings)
    protein = per_serving(macros_total, "protein", servings)
    carbs = per_serving(macros_total, "carbs", servings)
    fiber = per_serving(macros_total, "fiber", servings)
    sugar = per_serving(macros_total, "sugar", servings)
    fat = per_serving(macros_total, "fat", servings)

    score = 55
    reasons: list[str] = []
    if calories <= 650:
        score += 8
    elif calories > 900:
        score -= 12
    if protein >= 25:
        score += 14
        reasons.append("high protein")
    elif protein >= 15:
        score += 8
    if fiber >= 6:
        score += 10
        reasons.append("high fiber")
    if sugar > 18:
        score -= 12
    if carbs > 70:
        score -= 6
    if fat > 45:
        score -= 5
    if "diabetes" in goals or "keto" in goals or "weight_loss" in goals:
        score += 5
    if "vegan" in goals:
        reasons.append("plant-based")
    elif "vegetarian" in goals:
        reasons.append("vegetarian")
    if "muscle" in goals:
        reasons.append("muscle-friendly macros")

    final_score = int(max(0, min(100, score)))
    if not reasons:
        reasons.append("balanced everyday macros")
    return final_score, "Recipe checked from scraped nutrition data: " + ", ".join(reasons) + "."


def validate_recipe_quality(
    *,
    title: str,
    ingredients: list[str],
    instructions: str,
    macros_total: dict[str, float | int],
    goals: list[str],
    meal_type: str,
) -> str | None:
    if len(title) < 3:
        return "missing title"
    if len(ingredients) < 3:
        return "too few ingredients"
    if len(instructions) < 40:
        return "instructions too short"
    required_macros = ("calories", "protein", "carbs", "fat")
    missing = [key for key in required_macros if key not in macros_total]
    if missing:
        return f"missing macros: {', '.join(missing)}"
    if not goals:
        return "no nutrition goal labels"
    if meal_type not in {"breakfast", "lunch", "dinner", "snack", "dessert"}:
        return "invalid meal type"
    return None


def ingredient_texts_from_recipe(recipe: dict) -> list[str]:
    texts: list[str] = []
    for item in recipe.get("ingredients", []):
        if isinstance(item, dict):
            amount = str(item.get("amount") or "").strip()
            name = str(item.get("name") or "").strip()
            text = f"{amount} {name}".strip()
        else:
            text = str(item).strip()
        if text:
            texts.append(text)
    return texts


def recompute_recipe_categories(recipe: dict) -> tuple[str, list[str], int, str]:
    title = str(recipe.get("title") or recipe.get("name") or "").strip()
    source_url = str(recipe.get("source_url") or "")
    ingredients = ingredient_texts_from_recipe(recipe)
    macros = recipe.get("macros") if isinstance(recipe.get("macros"), dict) else {}
    servings = parse_servings(recipe.get("servings"))
    nutrition_estimated = bool(recipe.get("nutrition_estimated"))
    # Index-sourced imports lock their meal_type: the source category page (e.g. the
    # site's "breakfast" listing) is a more authoritative signal than keyword
    # inference over a foreign-language title.
    if recipe.get("meal_locked") and recipe.get("meal_type"):
        meal_type = str(recipe.get("meal_type"))
    else:
        meal_type = infer_meal_type(title, source_url, ingredients)
    if recipe.get("goals_locked") and isinstance(recipe.get("goals"), list) and recipe.get("goals"):
        # Imported recipes may compute language-aware diet tags the generic
        # classifier can't (e.g. Polish inflections); trust the locked goals.
        goals = sorted({str(goal) for goal in recipe.get("goals")})
    else:
        goals = classify_goals(
            title=title,
            ingredients=ingredients,
            macros_total=macros,
            servings=servings,
            meal_type=meal_type,
            nutrition_estimated=nutrition_estimated,
        )
    health_score, health_score_reason = compute_health_score(macros, servings, goals)
    return meal_type, goals, health_score, health_score_reason


def clean_instructions(text: str) -> str:
    text = re.sub(r"\r\n?", "\n", text or "")
    lines = [re.sub(r"\s+", " ", line).strip() for line in text.split("\n")]
    lines = [line for line in lines if line]
    return "\n".join(lines)


def split_steps(instructions: str) -> list[str]:
    lines = [line.strip() for line in instructions.split("\n") if line.strip()]
    if len(lines) > 1:
        return lines
    return [
        part.strip()
        for part in re.split(r"(?<=\.)\s+(?=(?:Step\s+)?\d+\b|[A-ZÁÉÍÓÚÄÖÜÑ])", instructions)
        if part.strip()
    ]


def macro_number(macros: dict[str, float | int], key: str) -> float:
    value = macros.get(key, 0)
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def create_scraper(session: requests.Session, url: str):
    require_dependency(scrape_me, "recipe-scrapers")
    try:
        return scrape_me(url, wild_mode=True)
    except TypeError as exc:
        if "wild_mode" not in str(exc):
            raise
        try:
            return scrape_me(url)
        except Exception as fallback_exc:
            fallback = create_json_ld_scraper(session, url)
            if fallback is not None:
                return fallback
            raise fallback_exc
    except Exception as exc:
        fallback = create_json_ld_scraper(session, url)
        if fallback is not None:
            return fallback
        raise exc


def download_and_compress_image(
    session: requests.Session,
    image_url: str,
    recipe_id: str,
) -> str | None:
    try:
        require_dependency(Image, "Pillow")
        require_dependency(ImageOps, "Pillow")
        response = session.get(image_url, timeout=REQUEST_TIMEOUT, stream=True)
        response.raise_for_status()
        content_type = response.headers.get("content-type", "")
        if "image" not in content_type.lower():
            print(f"[image skipped] not an image: {image_url}")
            return None
        data = response.content
        with Image.open(io.BytesIO(data)) as im:
            im = ImageOps.exif_transpose(im).convert("RGB")
            width, height = im.size
            side = min(width, height)
            left = (width - side) // 2
            top = (height - side) // 2
            im = im.crop((left, top, left + side, top + side))

            IMAGE_DIR.mkdir(parents=True, exist_ok=True)
            output_path = IMAGE_DIR / f"{recipe_id}.webp"

            for size in (400, 360, 320, 280, 240):
                resized = im.resize((size, size), Image.Resampling.LANCZOS)
                for quality in (80, 74, 68, 62, 56, 50):
                    buffer = io.BytesIO()
                    resized.save(buffer, format="WEBP", quality=quality, optimize=True)
                    if buffer.tell() <= IMAGE_MAX_BYTES or (size == 240 and quality == 50):
                        output_path.write_bytes(buffer.getvalue())
                        return f"assets/images/recipes/{output_path.name}"
    except Exception as exc:
        print(f"[image failed] {image_url}: {exc}")
    return None


def load_existing_recipes() -> list[dict]:
    if not OUTPUT_JSON.exists():
        return []
    try:
        return json.loads(OUTPUT_JSON.read_text(encoding="utf-8"))
    except Exception:
        return []


def save_recipes(recipes: list[dict]) -> None:
    OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUTPUT_JSON.with_suffix(".tmp")
    tmp.write_text(json.dumps(recipes, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(OUTPUT_JSON)


def validate_bundled_recipes() -> bool:
    recipes = load_existing_recipes()
    errors: list[str] = []
    bucket_counts: dict[str, int] = {}
    goal_counts: dict[str, int] = {}
    allowed_meals = {"breakfast", "lunch", "dinner", "snack", "dessert"}
    allowed_goals = {"muscle", "diabetes", "vegan", "vegetarian", "weight_loss", "keto", "maintain"}

    for index, recipe in enumerate(recipes):
        prefix = f"recipe[{index}] {recipe.get('id', '<missing id>')}"
        for field in ("id", "language", "title", "meal_type", "goals", "time", "ingredients", "instructions", "macros"):
            if field not in recipe:
                errors.append(f"{prefix}: missing {field}")

        meal_type = recipe.get("meal_type")
        if meal_type not in allowed_meals:
            errors.append(f"{prefix}: invalid meal_type {meal_type!r}")
        else:
            bucket_counts[meal_type] = bucket_counts.get(meal_type, 0) + 1

        goals = recipe.get("goals") if isinstance(recipe.get("goals"), list) else []
        if not goals:
            errors.append(f"{prefix}: no goals")
        for goal in goals:
            if goal not in allowed_goals:
                errors.append(f"{prefix}: invalid goal {goal!r}")
            goal_counts[goal] = goal_counts.get(goal, 0) + 1

        expected_meal, expected_goals, _, _ = recompute_recipe_categories(recipe)
        if meal_type in allowed_meals and meal_type != expected_meal:
            errors.append(f"{prefix}: meal_type {meal_type!r} should be {expected_meal!r}")
        if set(goals) != set(expected_goals):
            errors.append(
                f"{prefix}: goals {sorted(goals)!r} should be {sorted(expected_goals)!r}"
            )

        macros = recipe.get("macros") if isinstance(recipe.get("macros"), dict) else {}
        for macro in ("calories", "protein", "carbs", "fat"):
            value = macros.get(macro)
            if not isinstance(value, (int, float)) or value <= 0:
                errors.append(f"{prefix}: invalid macro {macro}={value!r}")

        ingredients = recipe.get("ingredients") if isinstance(recipe.get("ingredients"), list) else []
        if len(ingredients) < 3:
            errors.append(f"{prefix}: fewer than 3 ingredients")
        for ingredient in ingredients:
            if not isinstance(ingredient, dict):
                errors.append(f"{prefix}: ingredient is not an object")
                continue
            if not ingredient.get("name"):
                errors.append(f"{prefix}: ingredient missing name")
            grams = ingredient.get("grams")
            if not isinstance(grams, (int, float)) or grams < 0:
                errors.append(f"{prefix}: ingredient invalid grams {grams!r}")

        image = str(recipe.get("image") or "").strip()
        if not image:
            errors.append(f"{prefix}: missing local image")
        else:
            image_path = ROOT / image
            if not image_path.exists():
                errors.append(f"{prefix}: missing local image {image}")
            elif image_path.stat().st_size > IMAGE_MAX_BYTES:
                errors.append(f"{prefix}: image >50KB {image_path.stat().st_size} bytes")

    print(f"[validate] recipes={len(recipes)}")
    print(f"[validate] meal buckets={dict(sorted(bucket_counts.items()))}")
    print(f"[validate] goal buckets={dict(sorted(goal_counts.items()))}")
    if errors:
        print(f"[validate] FAILED with {len(errors)} issues")
        for error in errors[:200]:
            print(f"  - {error}")
        if len(errors) > 200:
            print(f"  ... and {len(errors) - 200} more")
        return False
    print("[validate] OK")
    return True


def reclassify_bundled_recipes() -> bool:
    recipes = load_existing_recipes()
    for recipe in recipes:
        meal_type, goals, health_score, health_score_reason = recompute_recipe_categories(recipe)
        language = str(recipe.get("language") or "").lower()
        recipe["meal_type"] = meal_type
        recipe["goals"] = goals
        recipe["health_score"] = health_score
        recipe["health_score_reason"] = health_score_reason
        recipe["tags"] = sorted({tag for tag in [language, meal_type, *goals] if tag})
    save_recipes(recipes)
    print(f"[reclassify] updated {len(recipes)} recipes")
    return validate_bundled_recipes()


def scrape_recipe(
    session: requests.Session,
    language: str,
    url: str,
    forced_meal: str | None = None,
) -> dict | None:
    try:
        scraper = create_scraper(session, url)
        title = (scraper.title() or "").strip()
        if not title:
            print(f"[skip] no title: {url}")
            return None

        ingredients = [i.strip() for i in (scraper.ingredients() or []) if i.strip()]
        instructions = clean_instructions(scraper.instructions() or "")
        if len(ingredients) < 2 or len(instructions) < 20:
            print(f"[skip] incomplete recipe: {url}")
            return None

        recipe_id = unique_id(language, title, url)
        try:
            nutrients = scraper.nutrients()
        except Exception:
            nutrients = {}

        try:
            servings = parse_servings(scraper.yields())
        except Exception:
            servings = 1

        macros = scale_macros_to_recipe_total(normalize_macros(nutrients), servings)

        try:
            total_time = scraper.total_time()
        except Exception:
            total_time = None

        if forced_meal in {"breakfast", "lunch", "dinner", "snack", "dessert"}:
            # Meal-locked: the URL came from a breakfast/lunch listing page, so
            # trust that category instead of the unreliable keyword inference.
            meal_type = forced_meal
        else:
            meal_type = infer_meal_type(title, url, ingredients)
        goals = classify_goals(
            title=title,
            ingredients=ingredients,
            macros_total=macros,
            servings=servings,
            meal_type=meal_type,
        )
        health_score, health_score_reason = compute_health_score(macros, servings, goals)
        quality_error = validate_recipe_quality(
            title=title,
            ingredients=ingredients,
            instructions=instructions,
            macros_total=macros,
            goals=goals,
            meal_type=meal_type,
        )
        if quality_error is not None:
            print(f"[skip] quality check failed ({quality_error}): {url}")
            return None

        image_asset = None
        try:
            image_url = scraper.image()
            if image_url:
                image_asset = download_and_compress_image(session, image_url, recipe_id)
        except Exception as exc:
            print(f"[image URL failed] {url}: {exc}")
        if not image_asset:
            print(f"[skip] missing downloadable image: {url}")
            return None

        steps = split_steps(instructions)
        tags = sorted({language.lower(), meal_type, *goals})
        net_carbs = max(0.0, macro_number(macros, "carbs") - macro_number(macros, "fiber"))

        return {
            "id": recipe_id,
            "language": language,
            "title": title,
            "name": title,
            "image": image_asset or "",
            "meal_type": meal_type,
            "goals": goals,
            "time": int(total_time or 0),
            "minutes": int(total_time or 0),
            "servings": servings,
            "ingredients": normalize_ingredients(ingredients),
            "instructions": instructions,
            "steps": steps,
            "macros": macros,
            "calories": int(round(macro_number(macros, "calories"))),
            "protein_g": round(macro_number(macros, "protein"), 1),
            "carbs_g": round(macro_number(macros, "carbs"), 1),
            "fat_g": round(macro_number(macros, "fat"), 1),
            "fiber_g": round(macro_number(macros, "fiber"), 1),
            "sugar_g": round(macro_number(macros, "sugar"), 1),
            "glycemic_index": 0,
            "glycemic_load": 0,
            "insulin_units": round(net_carbs / 10, 1),
            "tags": tags,
            "health_score": health_score,
            "health_score_reason": health_score_reason,
            "meal_locked": bool(forced_meal),
            "source": urlparse(url).netloc,
            "source_url": url,
        }
    except Exception as exc:
        print(f"[scrape failed] {url}: {exc}")
        return None


def extract_recipes(max_recipes: int, delay_min: float, delay_max: float) -> list[dict]:
    rows = read_urls()
    random.shuffle(rows)
    session = build_session()

    recipes = load_existing_recipes()
    seen_ids = {r.get("id") for r in recipes}
    seen_urls = set()
    success_since_save = 0

    print(f"[start] existing={len(recipes)} target={max_recipes}")
    for idx, (language, url) in enumerate(rows, 1):
        if len(recipes) >= max_recipes:
            break
        if url in seen_urls:
            continue
        seen_urls.add(url)

        delay = random.uniform(delay_min, delay_max)
        print(f"\n[{idx}/{len(rows)}] {language} {url} (sleep {delay:.1f}s)")
        time.sleep(delay)

        recipe = scrape_recipe(session, language, url)
        if recipe is None:
            continue
        if recipe["id"] in seen_ids:
            print(f"[duplicate] {recipe['id']}")
            continue

        recipes.append(recipe)
        seen_ids.add(recipe["id"])
        success_since_save += 1
        print(f"[ok] {len(recipes)}/{max_recipes}: {recipe['title']}")

        if success_since_save >= SAVE_EVERY:
            save_recipes(recipes)
            success_since_save = 0
            print(f"[saved] {OUTPUT_JSON}")

    save_recipes(recipes)
    print(f"[complete] {len(recipes)} recipes saved to {OUTPUT_JSON}")
    return recipes


FOCUS_GOALS = ("muscle", "vegan", "diabetes", "keto")
FOCUS_MEALS = ("breakfast", "lunch")
FOCUS_URL_TERMS = {
    "breakfast": (
        "breakfast", "brunch", "pancake", "waffle", "porridge", "granola", "overnight-oats",
        "overnight_oats", "ontbijt", "havermout", "fruhstuck", "fruehstueck", "frühstück",
        "sniadanie", "śniadanie", "desayuno",
    ),
    "lunch": (
        "lunch", "sandwich", "wrap", "salad", "bowl", "toastie", "broodje", "mittag", "almuerzo",
    ),
    "vegan": (
        "vegan", "vegano", "vegana", "plant-based", "plant_based", "plantbased", "dairy-free", "dairy_free",
        "tofu", "tempeh", "lentil", "chickpea",
    ),
    "keto": (
        "keto", "low-carb", "low_carb", "lowcarb", "ketogenic",
    ),
    "diabetes": (
        "diabetes", "diabetic", "low-sugar", "low_sugar", "blood-sugar", "glycemic",
    ),
    "muscle": (
        "protein", "high-protein", "high_protein", "muscle", "fitness", "gym",
    ),
}


def focus_bucket_counts(recipes: list[dict]) -> Counter[tuple[str, str, str]]:
    counts: Counter[tuple[str, str, str]] = Counter()
    for recipe in recipes:
        language = str(recipe.get("language") or "").upper()
        meal_type = str(recipe.get("meal_type") or "").lower()
        if meal_type not in FOCUS_MEALS:
            continue
        goals = {str(goal).lower() for goal in recipe.get("goals") or []}
        for goal in FOCUS_GOALS:
            if goal in goals:
                counts[(language, goal, meal_type)] += 1
    return counts


def summarize_focus_counts(counts: Counter[tuple[str, str, str]], languages: list[str]) -> None:
    for language in languages:
        print(f"[focus] {language}")
        for goal in FOCUS_GOALS:
            breakfast = counts[(language, goal, "breakfast")]
            lunch = counts[(language, goal, "lunch")]
            print(f"  - {goal:9} breakfast={breakfast:2} lunch={lunch:2}")


def focus_target_reached(
    counts: Counter[tuple[str, str, str]],
    languages: list[str],
    target_per_bucket: int,
) -> bool:
    for language in languages:
        for goal in FOCUS_GOALS:
            for meal_type in FOCUS_MEALS:
                if counts[(language, goal, meal_type)] < target_per_bucket:
                    return False
    return True


def url_focus_score(url: str) -> int:
    lower = url.lower()
    score = 0
    if any(term in lower for term in FOCUS_URL_TERMS["breakfast"]):
        score += 12
    if any(term in lower for term in FOCUS_URL_TERMS["lunch"]):
        score += 10
    if any(term in lower for term in FOCUS_URL_TERMS["vegan"]):
        score += 8
    if any(term in lower for term in FOCUS_URL_TERMS["keto"]):
        score += 7
    if any(term in lower for term in FOCUS_URL_TERMS["diabetes"]):
        score += 5
    if any(term in lower for term in FOCUS_URL_TERMS["muscle"]):
        score += 4
    return score


def extract_focus_recipes(
    max_recipes: int,
    delay_min: float,
    delay_max: float,
    target_per_bucket: int,
) -> list[dict]:
    rows = sorted(read_urls(), key=lambda row: (-url_focus_score(row[1]), row[0], row[1]))
    languages = sorted({language for language, _ in rows})
    session = build_session()

    recipes = load_existing_recipes()
    seen_ids = {r.get("id") for r in recipes}
    seen_urls = {str(r.get("source_url") or "") for r in recipes if r.get("source_url")}
    counts = focus_bucket_counts(recipes)
    success_since_save = 0

    print(f"[focus-start] existing={len(recipes)} target={max_recipes} bucket_target={target_per_bucket}")
    summarize_focus_counts(counts, languages)

    for idx, (language, url) in enumerate(rows, 1):
        if len(recipes) >= max_recipes:
            break
        if focus_target_reached(counts, languages, target_per_bucket):
            break
        if url in seen_urls:
            continue

        delay = random.uniform(delay_min, delay_max)
        score = url_focus_score(url)
        print(f"\n[focus {idx}/{len(rows)}] {language} score={score} {url} (sleep {delay:.1f}s)")
        time.sleep(delay)

        recipe = scrape_recipe(session, language, url)
        if recipe is None:
            continue
        if recipe["id"] in seen_ids:
            print(f"[duplicate] {recipe['id']}")
            continue
        if recipe.get("meal_type") not in FOCUS_MEALS:
            print(f"[skip] non-focus meal {recipe.get('meal_type')}: {recipe['title']}")
            continue

        goals = {str(goal).lower() for goal in recipe.get("goals") or []}
        matched_goals = sorted(goals.intersection(FOCUS_GOALS))
        if not matched_goals:
            print(f"[skip] no focus goals: {recipe['title']}")
            continue

        recipes.append(recipe)
        seen_ids.add(recipe["id"])
        seen_urls.add(url)
        for goal in matched_goals:
            counts[(language, goal, recipe["meal_type"])] += 1
        success_since_save += 1
        print(
            f"[focus-ok] {len(recipes)}/{max_recipes}: {recipe['title']}"
            f" goals={matched_goals} meal={recipe['meal_type']}"
        )

        if success_since_save >= SAVE_EVERY:
            save_recipes(recipes)
            success_since_save = 0
            summarize_focus_counts(counts, languages)
            print(f"[saved] {OUTPUT_JSON}")

    save_recipes(recipes)
    summarize_focus_counts(counts, languages)
    print(f"[focus-complete] {len(recipes)} recipes saved to {OUTPUT_JSON}")
    return recipes


# ── Meal-balanced staging extraction (breakfast / lunch / optional snack) ─────
# Unlike `extract`/`all` (which fall back to "dinner" and would re-skew the DB),
# this keeps ONLY the requested starved buckets and writes to a SEPARATE staging
# file so assets/bundled_recipes.json is never mutated by a live crawl.
BALANCE_MEALS = ("breakfast", "lunch", "snack")
STAGING_JSON = ROOT / "assets" / "scraped_staging.json"

SNACK_URL_TERMS = (
    "snack", "smoothie", "shake", "energy-ball", "energy_balls", "energy-balls",
    "bliss-ball", "granola-bar", "protein-bar", "popcorn", "hummus", "dip",
    "trail-mix", "tussendoor", "przekaska", "merienda",
)

# Proteins / dinner words that disqualify a "snack" (mirror of balance script).
SNACK_DISQUALIFIERS = (
    "chicken", "beef", "steak", "lamb", "pork", "fish", "salmon", "shrimp",
    "prawn", "meatball", "pastrami", "chorizo", "sausage", "skewer", "casserole",
    "curry", "roast", "lasagne", "lasagna", "risotto",
)


def _is_simple_snack(recipe: dict) -> bool:
    """Keep only grab-and-eat snacks; reject composed/cooked meals."""
    title = str(recipe.get("title") or "").lower()
    if any(term in title for term in SNACK_DISQUALIFIERS):
        return False
    if len(recipe.get("ingredients") or []) > 7:
        return False
    minutes = int(recipe.get("minutes") or recipe.get("time") or 0)
    if minutes > 25:
        return False
    return True


def load_recipes_from(path: Path) -> list[dict]:
    if not path.exists():
        return []
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return []


def save_recipes_to(path: Path, recipes: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(recipes, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


def balance_url_score(url: str) -> int:
    score = url_focus_score(url)
    if any(term in url.lower() for term in SNACK_URL_TERMS):
        score += 9
    return score


def extract_meal_balanced(
    output_path: Path,
    per_meal_target: int,
    max_recipes: int,
    max_urls: int,
    delay_min: float,
    delay_max: float,
    allowed_meals: tuple[str, ...],
    allowed_hosts: tuple[str, ...] = (),
) -> list[dict]:
    rows = read_urls()
    if allowed_hosts:
        rows = [
            row
            for row in rows
            if any(host in urlparse(row[1]).netloc.lower() for host in allowed_hosts)
        ]
    rows = sorted(rows, key=lambda row: (-balance_url_score(row[1]), row[0], row[1]))
    if max_urls > 0:
        rows = rows[:max_urls]
    session = build_session()

    recipes = load_recipes_from(output_path)
    existing_recipes = load_existing_recipes()
    seen_ids = {r.get("id") for r in recipes}
    seen_ids.update(r.get("id") for r in existing_recipes)
    seen_urls = {str(r.get("source_url") or "") for r in recipes if r.get("source_url")}
    seen_urls.update(
        str(r.get("source_url") or "")
        for r in existing_recipes
        if r.get("source_url")
    )
    counts = Counter(str(r.get("meal_type") or "").lower() for r in recipes)
    success_since_save = 0

    def snapshot() -> dict:
        return {meal: counts[meal] for meal in allowed_meals}

    def target_reached() -> bool:
        return all(counts[meal] >= per_meal_target for meal in allowed_meals)

    print(
        f"[balance-start] staging={output_path} existing={len(recipes)} "
        f"meals={allowed_meals} hosts={allowed_hosts or 'all'} "
        f"per_meal_target={per_meal_target} max_urls={max_urls or 'all'} "
        f"counts={snapshot()}"
    )

    for idx, (language, url) in enumerate(rows, 1):
        if len(recipes) >= max_recipes or target_reached():
            break
        if url in seen_urls:
            continue
        seen_urls.add(url)

        delay = random.uniform(delay_min, delay_max)
        print(f"\n[balance {idx}/{len(rows)}] {language} score={balance_url_score(url)} {url} (sleep {delay:.1f}s)")
        time.sleep(delay)

        recipe = scrape_recipe(session, language, url)
        if recipe is None:
            continue
        if recipe["id"] in seen_ids:
            continue
        meal = str(recipe.get("meal_type") or "").lower()
        if meal not in allowed_meals:
            print(f"[skip] non-target meal {meal}: {recipe['title']}")
            continue
        if counts[meal] >= per_meal_target:
            print(f"[skip] {meal} quota full: {recipe['title']}")
            continue
        if meal == "snack" and not _is_simple_snack(recipe):
            print(f"[skip] complex snack: {recipe['title']}")
            continue

        recipes.append(recipe)
        seen_ids.add(recipe["id"])
        counts[meal] += 1
        success_since_save += 1
        print(f"[balance-ok] {recipe['title']} meal={meal} counts={snapshot()}")

        if success_since_save >= SAVE_EVERY:
            save_recipes_to(output_path, recipes)
            success_since_save = 0

    save_recipes_to(output_path, recipes)
    print(f"[balance-complete] {len(recipes)} saved to {output_path} counts={snapshot()}")
    return recipes


def parse_meal_filter(raw: str) -> tuple[str, ...]:
    meals = tuple(dict.fromkeys(part.strip().lower() for part in raw.split(",") if part.strip()))
    invalid = [meal for meal in meals if meal not in BALANCE_MEALS]
    if invalid:
        raise argparse.ArgumentTypeError(
            f"Invalid meal(s): {', '.join(invalid)}. Allowed: {', '.join(BALANCE_MEALS)}"
        )
    if not meals:
        raise argparse.ArgumentTypeError("At least one meal must be provided")
    return meals


def parse_host_filter(raw: str) -> tuple[str, ...]:
    return tuple(
        dict.fromkeys(part.strip().lower() for part in raw.split(",") if part.strip())
    )


# ── Meal-targeted discovery + meal-locked extraction ─────────────────────────
# infer_meal_type() is unreliable and defaults to "dinner", so to reliably ADD
# breakfast and lunch recipes we harvest URLs straight from each site's
# breakfast/lunch listing or search pages and LOCK the meal_type when scraping.
MEAL_URLS_FILE = ROOT / "recipe_urls_meal.txt"

# (meal, language, listing_url, render)
#   render="js"       -> Playwright + infinite-scroll (Albert Heijn search)
#   render="chefkoch" -> server HTML with /sNN/ path pagination
#   render="html"     -> server HTML with ?page=N pagination
MEAL_SEEDS: tuple[tuple[str, str, str, str], ...] = (
    # Albert Heijn Allerhande search (JS rendered) — the ONLY source per user request.
    ("breakfast", "NL", "https://www.ah.nl/allerhande/recepten-zoeken?query=Ontbijt", "js"),
    ("lunch", "NL", "https://www.ah.nl/allerhande/recepten-zoeken?query=Lunch", "js"),
)

# Listing/category/index paths that must never be treated as a recipe URL.
_LISTING_BLOCKLIST = (
    "/collection/", "/collections/", "/category/", "/categories/", "/cuisine/",
    "/recipes/courses", "/recipe-finder", "/recepten-zoeken", "/allerhande/recepten",
    "/ideas/", "/search", "/przepisy", "/rs/", "/howto", "/health/", "/author/",
)


def _site_for_url(url: str) -> SiteConfig | None:
    host = urlparse(url).netloc.lower()
    for site in SITES:
        site_host = urlparse(site.base_url).netloc.lower()
        if host == site_host or host.endswith("." + site_host) or site_host.endswith("." + host):
            return site
    return None


def _is_listing_url(url: str) -> bool:
    path = urlparse(url).path.lower()
    return any(token in path for token in _LISTING_BLOCKLIST)


def _with_page(url: str, page: int) -> str:
    sep = "&" if "?" in url else "?"
    return f"{url}{sep}page={page}"


def _clean_link(link: str) -> str:
    return link.split("#", 1)[0].split("?", 1)[0].rstrip("/")


def _harvest_html_listing(
    session: requests.Session,
    meal: str,
    lang: str,
    base_url: str,
    pages: int,
    max_links: int,
) -> list[tuple[str, str, str]]:
    site = _site_for_url(base_url)
    out: list[tuple[str, str, str]] = []
    seen: set[str] = set()
    for pg in range(1, pages + 1):
        page_url = base_url if pg == 1 else _with_page(base_url, pg)
        html = fetch_text(session, page_url, use_playwright_on_block=True)
        if not html:
            if pg > 1:
                break
            continue
        new = 0
        for raw in extract_links_from_html(html, page_url):
            link = _clean_link(raw)
            if link in seen or _is_listing_url(link):
                continue
            if site is not None and not looks_like_recipe(link, site):
                continue
            seen.add(link)
            out.append((meal, lang, link))
            new += 1
            if len(out) >= max_links:
                return out
        print(f"  [page {pg}] {page_url} -> +{new} (seed total {len(out)})")
        if new == 0 and pg > 1:
            break
    return out


def _harvest_chefkoch(
    session: requests.Session,
    meal: str,
    lang: str,
    base_url: str,
    pages: int,
    max_links: int,
) -> list[tuple[str, str, str]]:
    out: list[tuple[str, str, str]] = []
    seen: set[str] = set()
    for pg in range(pages):
        page_url = base_url.replace("/s0/", f"/s{pg * 30}/", 1)
        html = fetch_text(session, page_url, use_playwright_on_block=True)
        if not html:
            if pg > 0:
                break
            continue
        new = 0
        for raw in extract_links_from_html(html, page_url):
            link = _clean_link(raw)
            if link in seen:
                continue
            # Chefkoch recipe URLs look like /rezepte/<digits>/<slug>.html
            if not re.search(r"/rezepte/\d+/", urlparse(link).path):
                continue
            seen.add(link)
            out.append((meal, lang, link))
            new += 1
            if len(out) >= max_links:
                return out
        print(f"  [chefkoch s{pg * 30}] -> +{new} (seed total {len(out)})")
        if new == 0 and pg > 0:
            break
    return out


def _harvest_js_search(
    meal: str,
    lang: str,
    url: str,
    scrolls: int,
    max_links: int,
) -> list[tuple[str, str, str]]:
    try:
        from playwright.sync_api import sync_playwright
    except Exception as exc:  # pragma: no cover
        print(f"[playwright unavailable] {exc}")
        return []
    try:
        from playwright_stealth import Stealth
    except Exception as exc:  # pragma: no cover
        print(f"[playwright_stealth unavailable] {exc}")
        return []

    ua = (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
    )
    # ah.nl search shows ~36 results per page and paginates via &page=N.
    # `scrolls` is reused as the maximum page count to walk.
    max_pages = max(scrolls, 1)
    seen: set[str] = set()
    try:
        # Stealth() patches navigator.webdriver et al so ah.nl's bot wall
        # ("Access Denied") lets the search results render.
        with Stealth().use_sync(sync_playwright()) as p:
            browser = p.chromium.launch(
                headless=True,
                args=["--disable-blink-features=AutomationControlled"],
            )
            page = browser.new_page(
                user_agent=ua,
                viewport={"width": 1366, "height": 1000},
                locale="nl-NL",
            )
            page.goto(url, wait_until="domcontentloaded", timeout=60000)
            page.wait_for_timeout(3000)
            for sel in (
                "button:has-text('Accepteren')",
                "button:has-text('Alles accepteren')",
                "button:has-text('Akkoord')",
                "#accept-cookies",
                "[data-testhook='accept-cookies'] button",
            ):
                try:
                    page.click(sel, timeout=2500)
                    page.wait_for_timeout(800)
                    break
                except Exception:
                    pass
            empty_streak = 0
            for pg_num in range(1, max_pages + 1):
                page_url = _with_page(url, pg_num)
                try:
                    page.goto(page_url, wait_until="domcontentloaded", timeout=60000)
                except Exception as exc:
                    print(f"  [ah page {pg_num}] nav error: {exc}")
                    break
                page.wait_for_timeout(random.randint(1800, 2600))
                page.mouse.wheel(0, 40000)
                page.wait_for_timeout(random.randint(800, 1400))
                try:
                    hrefs = page.eval_on_selector_all(
                        "a[href*='/allerhande/recept/']",
                        "els => els.map(e => e.href)",
                    )
                except Exception:
                    hrefs = []
                before = len(seen)
                for h in hrefs:
                    if h:
                        seen.add(_clean_link(h))
                new = len(seen) - before
                print(f"  [ah page {pg_num}] {meal} +{new} (total {len(seen)})")
                if len(seen) >= max_links:
                    break
                if new == 0:
                    empty_streak += 1
                    if empty_streak >= 2:
                        print(f"  [ah] no new results after page {pg_num}; stopping")
                        break
                else:
                    empty_streak = 0
            browser.close()
    except Exception as exc:
        print(f"[ah-search failed] {url}: {exc}")
    return [(meal, lang, u) for u in list(seen)[:max_links]]


def discover_meals(pages: int, scrolls: int, max_per_seed: int) -> dict[str, tuple[str, str]]:
    session = build_session()
    collected: dict[str, tuple[str, str]] = {}
    for meal, lang, url, render in MEAL_SEEDS:
        before = len(collected)
        print(f"\n=== discover {meal} [{lang}] {url} ({render}) ===")
        try:
            if render == "js":
                found = _harvest_js_search(meal, lang, url, scrolls, max_per_seed)
            elif render == "chefkoch":
                found = _harvest_chefkoch(session, meal, lang, url, pages, max_per_seed)
            else:
                found = _harvest_html_listing(session, meal, lang, url, pages, max_per_seed)
        except Exception as exc:
            print(f"[discover-error] {url}: {exc}")
            found = []
        for m, lg, u in found:
            if u not in collected:
                collected[u] = (m, lg)
        print(f"[discover] {meal} {lang} -> +{len(collected) - before} (total {len(collected)})")

    by_meal = Counter(m for m, _ in collected.values())
    lines = [f"{lg}\t{m}\t{u}" for u, (m, lg) in collected.items()]
    MEAL_URLS_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"\n[discover-done] {len(collected)} meal-tagged URLs by meal={dict(by_meal)} -> {MEAL_URLS_FILE}")
    return collected


def read_meal_urls() -> list[tuple[str, str, str]]:
    if not MEAL_URLS_FILE.exists():
        raise FileNotFoundError(f"Missing {MEAL_URLS_FILE}. Run discover-meals first.")
    rows: list[tuple[str, str, str]] = []
    for line in MEAL_URLS_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) == 3:
            lang, meal, url = parts
        elif len(parts) == 2:
            meal, url = parts
            lang = language_from_url(url)
        else:
            continue
        rows.append((lang.strip().upper(), meal.strip().lower(), url.strip()))
    return rows


def extract_meal_locked(
    output_path: Path,
    per_meal_target: int,
    max_recipes: int,
    delay_min: float,
    delay_max: float,
) -> list[dict]:
    targets = ("breakfast", "lunch")
    rows = [row for row in read_meal_urls() if row[1] in targets]
    random.shuffle(rows)
    session = build_session()

    recipes = load_recipes_from(output_path)
    existing = load_existing_recipes()
    seen_ids = {r.get("id") for r in recipes}
    seen_ids.update(r.get("id") for r in existing)
    seen_urls = {str(r.get("source_url") or "") for r in recipes if r.get("source_url")}
    seen_urls.update(str(r.get("source_url") or "") for r in existing if r.get("source_url"))
    counts = Counter(str(r.get("meal_type") or "").lower() for r in recipes)
    success_since_save = 0

    def snapshot() -> dict:
        return {"breakfast": counts["breakfast"], "lunch": counts["lunch"]}

    def target_reached() -> bool:
        return all(counts[m] >= per_meal_target for m in targets)

    print(
        f"[meal-locked-start] urls={len(rows)} staged={len(recipes)} "
        f"per_meal_target={per_meal_target} counts={snapshot()}"
    )

    for idx, (lang, meal, url) in enumerate(rows, 1):
        if len(recipes) >= max_recipes or target_reached():
            break
        if meal not in targets or counts[meal] >= per_meal_target:
            continue
        if url in seen_urls:
            continue
        seen_urls.add(url)

        time.sleep(random.uniform(delay_min, delay_max))
        print(f"\n[meal {idx}/{len(rows)}] {lang} {meal} {url}")
        recipe = scrape_recipe(session, lang, url, forced_meal=meal)
        if recipe is None:
            continue
        if recipe["id"] in seen_ids:
            print(f"[duplicate] {recipe['id']}")
            continue
        if recipe.get("meal_type") not in targets:
            continue

        recipes.append(recipe)
        seen_ids.add(recipe["id"])
        counts[meal] += 1
        success_since_save += 1
        print(f"[meal-ok] {recipe['title']} meal={meal} counts={snapshot()}")

        if success_since_save >= SAVE_EVERY:
            save_recipes_to(output_path, recipes)
            success_since_save = 0
            print(f"[saved] {output_path} counts={snapshot()}")

    save_recipes_to(output_path, recipes)
    print(f"[meal-locked-complete] {len(recipes)} staged -> {output_path} counts={snapshot()}")
    return recipes


def merge_staging(staging_path: Path) -> bool:
    """Append reviewed staging recipes into the curated DB (dedup by id)."""
    staged = load_recipes_from(staging_path)
    if not staged:
        print(f"[merge] no staged recipes at {staging_path}")
        return True
    recipes = load_existing_recipes()
    seen = {r.get("id") for r in recipes}
    added = 0
    for recipe in staged:
        if recipe.get("id") in seen:
            continue
        recipes.append(recipe)
        seen.add(recipe.get("id"))
        added += 1
    save_recipes(recipes)
    print(f"[merge] added {added} new recipes from {staging_path} -> {OUTPUT_JSON} (total {len(recipes)})")
    return validate_bundled_recipes()


def main() -> int:
    parser = argparse.ArgumentParser(description="Build bundled real recipe database")
    sub = parser.add_subparsers(dest="command", required=True)

    crawl_parser = sub.add_parser("crawl", help="Phase 1: collect recipe URLs")
    crawl_parser.add_argument("--target-per-language", type=int, default=800)
    crawl_parser.add_argument("--max-sitemaps-per-site", type=int, default=250)
    crawl_parser.add_argument("--use-playwright-on-block", action="store_true")

    extract_parser = sub.add_parser("extract", help="Phase 2: scrape recipes and images")
    extract_parser.add_argument("--max-recipes", type=int, default=3000)
    extract_parser.add_argument("--delay-min", type=float, default=1.0)
    extract_parser.add_argument("--delay-max", type=float, default=3.0)

    all_parser = sub.add_parser("all", help="Run crawl then extract")
    all_parser.add_argument("--target-per-language", type=int, default=800)
    all_parser.add_argument("--max-sitemaps-per-site", type=int, default=250)
    all_parser.add_argument("--max-recipes", type=int, default=3000)
    all_parser.add_argument("--delay-min", type=float, default=1.0)
    all_parser.add_argument("--delay-max", type=float, default=3.0)
    all_parser.add_argument("--use-playwright-on-block", action="store_true")

    focus_parser = sub.add_parser(
        "extract-focus",
        help="Append only breakfast/lunch recipes for muscle, vegan, diabetes, and keto buckets",
    )
    focus_parser.add_argument("--max-recipes", type=int, default=2200)
    focus_parser.add_argument("--delay-min", type=float, default=0.2)
    focus_parser.add_argument("--delay-max", type=float, default=0.5)
    focus_parser.add_argument("--target-per-bucket", type=int, default=8)

    balanced_parser = sub.add_parser(
        "extract-balanced",
        help="Scrape selected breakfast/lunch/snack meals into staging only",
    )
    balanced_parser.add_argument("--output", type=str, default=str(STAGING_JSON))
    balanced_parser.add_argument("--per-meal-target", type=int, default=140)
    balanced_parser.add_argument("--max-recipes", type=int, default=600)
    balanced_parser.add_argument(
        "--max-urls",
        type=int,
        default=0,
        help="Maximum sorted URLs to attempt; 0 means all matching URLs",
    )
    balanced_parser.add_argument("--delay-min", type=float, default=1.0)
    balanced_parser.add_argument("--delay-max", type=float, default=3.0)
    balanced_parser.add_argument(
        "--meals",
        type=parse_meal_filter,
        default=BALANCE_MEALS,
        help="Comma-separated target meals, e.g. breakfast,lunch",
    )
    balanced_parser.add_argument(
        "--hosts",
        type=parse_host_filter,
        default=(),
        help="Optional comma-separated host filter, e.g. www.ah.nl,www.bbcgoodfood.com",
    )

    merge_parser = sub.add_parser(
        "merge-staging",
        help="Merge reviewed staging recipes into the curated DB (dedup by id), then validate",
    )
    merge_parser.add_argument("--input", type=str, default=str(STAGING_JSON))

    discover_parser = sub.add_parser(
        "discover-meals",
        help="Harvest breakfast/lunch recipe URLs from each site's meal listing/search pages",
    )
    discover_parser.add_argument("--pages", type=int, default=12, help="Listing pages per seed (?page=N)")
    discover_parser.add_argument("--scrolls", type=int, default=45, help="Infinite-scroll passes for JS search pages")
    discover_parser.add_argument("--max-per-seed", type=int, default=1400)

    meal_locked_parser = sub.add_parser(
        "extract-meal-locked",
        help="Scrape meal-tagged URLs (breakfast/lunch only, locked meal_type, real images) into staging",
    )
    meal_locked_parser.add_argument("--output", type=str, default=str(STAGING_JSON))
    meal_locked_parser.add_argument("--per-meal-target", type=int, default=500)
    meal_locked_parser.add_argument("--max-recipes", type=int, default=1200)
    meal_locked_parser.add_argument("--delay-min", type=float, default=0.4)
    meal_locked_parser.add_argument("--delay-max", type=float, default=1.2)

    sub.add_parser("validate", help="Audit assets/bundled_recipes.json")
    sub.add_parser("reclassify", help="Recompute meal and nutrition-goal labels for bundled recipes")

    args = parser.parse_args()

    if args.command == "crawl":
        crawl_recipe_urls(
            args.target_per_language,
            use_playwright_on_block=args.use_playwright_on_block,
            max_sitemaps_per_site=args.max_sitemaps_per_site,
        )
    elif args.command == "extract":
        extract_recipes(args.max_recipes, args.delay_min, args.delay_max)
    elif args.command == "all":
        crawl_recipe_urls(
            args.target_per_language,
            use_playwright_on_block=args.use_playwright_on_block,
            max_sitemaps_per_site=args.max_sitemaps_per_site,
        )
        extract_recipes(args.max_recipes, args.delay_min, args.delay_max)
        if not validate_bundled_recipes():
            return 1
    elif args.command == "extract-focus":
        extract_focus_recipes(
            args.max_recipes,
            args.delay_min,
            args.delay_max,
            args.target_per_bucket,
        )
        if not validate_bundled_recipes():
            return 1
    elif args.command == "extract-balanced":
        extract_meal_balanced(
            Path(args.output),
            args.per_meal_target,
            args.max_recipes,
            args.max_urls,
            args.delay_min,
            args.delay_max,
            args.meals,
            args.hosts,
        )
    elif args.command == "merge-staging":
        if not merge_staging(Path(args.input)):
            return 1
    elif args.command == "discover-meals":
        discover_meals(args.pages, args.scrolls, args.max_per_seed)
    elif args.command == "extract-meal-locked":
        extract_meal_locked(
            Path(args.output),
            args.per_meal_target,
            args.max_recipes,
            args.delay_min,
            args.delay_max,
        )
    elif args.command == "validate":
        if not validate_bundled_recipes():
            return 1
    elif args.command == "reclassify":
        if not reclassify_bundled_recipes():
            return 1
    else:
        parser.print_help()
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
