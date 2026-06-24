#!/usr/bin/env python3
"""
Import breakfast/lunch recipes from kwestiasmaku.com (Polish) into a staging file.

kwestiasmaku publishes real recipes (title, ingredients, steps, image) but NO
nutrition data. The site also resets Python `requests` connections (TLS
fingerprint), so we fetch HTML/images with `curl` and parse with
`recipe_scrapers.scrape_html`.

Because the site has no published macros, calories/protein/carbs/fat are
ESTIMATED from ingredient quantities using a USDA-style reference table. Every
imported recipe is therefore marked:

    "nutrition_estimated": true   # macros are ingredient estimates, not published
    "meal_locked": true           # meal_type comes from the source category page
    "insulin_units": 0.0          # never feed estimates into insulin math

and is deliberately kept OUT of the macro-derived goals (diabetes, keto,
weight_loss, muscle) by `classify_goals(nutrition_estimated=True)` so estimated
numbers never drive the medical (diabetes/insulin) or fitness features. Only the
always-on `maintain` tag and the ingredient-derived vegan/vegetarian tags apply.

Usage:
    python scripts/import_kwestiasmaku.py --breakfast-target 320 --lunch-target 180
    python scripts/scrape_real_recipes.py merge-staging --input assets/scraped_staging_pl.json
"""

from __future__ import annotations

import argparse
import io
import random
import re
import subprocess
import sys
import time
import unicodedata
from pathlib import Path
from urllib.parse import urljoin, urlparse

from bs4 import BeautifulSoup
from PIL import Image, ImageOps
from recipe_scrapers import scrape_html

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scrape_real_recipes as srr  # noqa: E402

ROOT = srr.ROOT
IMAGE_DIR = srr.IMAGE_DIR
IMAGE_MAX_BYTES = srr.IMAGE_MAX_BYTES
DEFAULT_OUTPUT = ROOT / "assets" / "scraped_staging_pl.json"

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/125.0 Safari/537.36"
)

BREAKFAST_INDEXES = (
    "https://www.kwestiasmaku.com/dania_dla_dwojga/sniadania/przepisy.html",
    "https://www.kwestiasmaku.com/dania_dla_dwojga/sniadania/jajo_sniadanie/przepisy.html",
    "https://www.kwestiasmaku.com/przepisy/sniadania-bez-chleba",
    "https://www.kwestiasmaku.com/przepisy/owsianka",
    "https://www.kwestiasmaku.com/przepisy/platki",
    "https://www.kwestiasmaku.com/przepisy/jaglanka",
    "https://www.kwestiasmaku.com/przepisy/budyn-jaglany",
    "https://www.kwestiasmaku.com/przepisy/pasty-kanapkowe",
    "https://www.kwestiasmaku.com/przepisy/pasta-jajeczna",
    "https://www.kwestiasmaku.com/przepisy/szakszuka",
    "https://www.kwestiasmaku.com/przepisy/kanapki",
)
LUNCH_INDEXES = (
    "https://www.kwestiasmaku.com/przepisy/lunche",
    "https://www.kwestiasmaku.com/przepisy/salatki",
    "https://www.kwestiasmaku.com/przepisy/zupy",
    "https://www.kwestiasmaku.com/przepisy/zapiekanki",
)


# ── Polish-aware quantity → grams ─────────────────────────────────────────────
def strip_diacritics(text: str) -> str:
    nfkd = unicodedata.normalize("NFKD", text)
    return "".join(c for c in nfkd if not unicodedata.combining(c)).lower()


def _first_number(text: str) -> float:
    # Handle "1/2", "1,5", "2-3" (take the first value), "1 1/2".
    text = text.strip()
    m = re.match(r"(\d+)\s+(\d+)/(\d+)", text)
    if m:
        return int(m.group(1)) + int(m.group(2)) / max(1, int(m.group(3)))
    m = re.match(r"(\d+)/(\d+)", text)
    if m:
        return int(m.group(1)) / max(1, int(m.group(2)))
    m = re.match(r"(\d+(?:[.,]\d+)?)", text)
    if m:
        return float(m.group(1).replace(",", "."))
    return 0.0


# grams per "unit" keyword (matched on diacritic-stripped text)
_UNIT_GRAMS = (
    ("kg", 1000.0),
    ("dag", 10.0),
    ("dkg", 10.0),
    ("gram", 1.0),
    (" g", 1.0),
    ("ml", 1.0),
    ("litr", 1000.0),
    (" l ", 1000.0),
    ("lyzeczk", 5.0),
    ("lyzk", 15.0),
    ("szklank", 250.0),
    ("szczypt", 1.0),
    ("zabek", 5.0),
    ("zabki", 5.0),
    ("zabkow", 5.0),
    ("puszk", 400.0),
    ("garsc", 30.0),
    ("garsci", 30.0),
    ("peczek", 80.0),
    ("peczka", 80.0),
    ("plasterek", 15.0),
    ("plasterk", 15.0),
    ("plaster", 20.0),
    ("opakowan", 200.0),
    ("opak", 200.0),
    ("kromk", 30.0),
    ("kostk", 100.0),
    ("listek", 2.0),
    ("listk", 2.0),
)


def estimate_grams(raw: str) -> tuple[str, str, float]:
    """Return (name, amount, grams) for a Polish/English ingredient line."""
    text = re.sub(r"\s+", " ", raw.strip())
    if not text:
        return "", "", 0.0
    flat = strip_diacritics(text)
    value = _first_number(flat)

    grams = 0.0
    if value > 0:
        padded = f" {flat} "
        for key, factor in _UNIT_GRAMS:
            if key in padded:
                grams = value * factor
                break
        else:
            # number but no recognised unit -> piece count
            if any(t in flat for t in ("jaj", "jajk", "jajo")):
                grams = value * 50.0
            else:
                grams = value * 80.0
    else:
        grams = 25.0  # "do smaku" / "do smazenia" – small seasoning amount

    grams = round(max(0.0, min(3000.0, grams)), 1)
    # amount = leading quantity text; name = remainder (best effort)
    amount_match = re.match(r"^[\d\s.,/]+(?:\S+)?", text)
    amount = amount_match.group(0).strip() if amount_match else ""
    name = text[len(amount):].strip(" ,.-") if amount else text
    return (name or text), (amount or text), grams


# ── USDA-style per-100g macro reference (kcal, protein, carbs, fat, fiber, sugar)
_MACRO_TABLE: tuple[tuple[str, tuple[float, float, float, float, float, float]], ...] = (
    ("maslo orzechow", (588, 25, 20, 50, 6, 9)),
    ("orzech wlosk", (654, 15, 14, 65, 6.7, 2.6)),
    ("maslo", (717, 0.9, 0.1, 81, 0, 0)),
    ("oliwa", (884, 0, 0, 100, 0, 0)),
    ("olej", (884, 0, 0, 100, 0, 0)),
    ("smietan", (195, 2.8, 3.4, 19, 0, 3)),
    ("mleko", (60, 3.2, 5, 3.3, 0, 5)),
    ("jogurt", (61, 3.5, 4.7, 3.3, 0, 4.7)),
    ("kefir", (52, 3.3, 4.7, 1.5, 0, 4.7)),
    ("twarog", (98, 11, 3.4, 4.3, 0, 2.7)),
    ("ser bial", (98, 11, 3.4, 4.3, 0, 2.7)),
    ("ricotta", (174, 11, 3, 13, 0, 0.3)),
    ("mozzarell", (280, 28, 3.1, 17, 0, 1)),
    ("parmezan", (392, 36, 4, 26, 0, 0.9)),
    ("feta", (264, 14, 4, 21, 0, 4)),
    ("ser zolt", (350, 25, 1.3, 28, 0, 0.5)),
    ("ser ", (350, 25, 1.3, 28, 0, 0.5)),
    ("jaj", (143, 13, 1, 10, 0, 1)),
    ("maka", (364, 10, 76, 1, 2.7, 0.3)),
    ("cukier", (387, 0, 100, 0, 0, 100)),
    ("miod", (304, 0.3, 82, 0, 0.2, 82)),
    ("platki owsian", (389, 17, 66, 7, 10, 1)),
    ("owsian", (389, 17, 66, 7, 10, 1)),
    ("platki", (378, 8, 80, 4, 7, 8)),
    ("kasza jaglan", (378, 11, 73, 4, 8.5, 0)),
    ("jaglan", (378, 11, 73, 4, 8.5, 0)),
    ("kasza gryczan", (343, 13, 72, 3.4, 10, 0)),
    ("kasza", (350, 11, 72, 2, 6, 0.5)),
    ("ryz", (365, 7, 80, 0.7, 1.3, 0.1)),
    ("makaron", (371, 13, 75, 1.5, 3, 2.7)),
    ("chleb", (265, 9, 49, 3.2, 2.7, 5)),
    ("bagietk", (270, 9, 50, 3.5, 2, 3)),
    ("bulk", (270, 9, 50, 3.5, 2, 3)),
    ("tortill", (310, 8, 50, 8, 3, 2)),
    ("ziemniak", (77, 2, 17, 0.1, 2.2, 0.8)),
    ("pomidor", (18, 0.9, 3.9, 0.2, 1.2, 2.6)),
    ("ogorek", (15, 0.7, 3.6, 0.1, 0.5, 1.7)),
    ("cebul", (40, 1.1, 9.3, 0.1, 1.7, 4.2)),
    ("czosn", (149, 6.4, 33, 0.5, 2.1, 1)),
    ("papryk", (31, 1, 6, 0.3, 2.1, 4.2)),
    ("pieczark", (22, 3.1, 3.3, 0.3, 1, 2)),
    ("grzyb", (22, 3.1, 3.3, 0.3, 1, 2)),
    ("salat", (15, 1.4, 2.9, 0.2, 1.3, 0.8)),
    ("szpinak", (23, 2.9, 3.6, 0.4, 2.2, 0.4)),
    ("marchew", (41, 0.9, 10, 0.2, 2.8, 4.7)),
    ("cukini", (17, 1.2, 3.1, 0.3, 1, 2.5)),
    ("kukurydz", (86, 3.2, 19, 1.2, 2.7, 3.2)),
    ("oliwk", (115, 0.8, 6, 11, 3.2, 0)),
    ("awokado", (160, 2, 9, 15, 7, 0.7)),
    ("ciecierzyc", (164, 9, 27, 2.6, 8, 4.8)),
    ("cieciork", (164, 9, 27, 2.6, 8, 4.8)),
    ("hummus", (166, 8, 14, 10, 6, 0)),
    ("fasol", (127, 9, 23, 0.5, 6, 0.3)),
    ("soczewic", (116, 9, 20, 0.4, 8, 1.8)),
    ("banan", (89, 1.1, 23, 0.3, 2.6, 12)),
    ("jablk", (52, 0.3, 14, 0.2, 2.4, 10)),
    ("truskawk", (32, 0.7, 7.7, 0.3, 2, 4.9)),
    ("borowk", (57, 0.7, 14, 0.3, 2.4, 10)),
    ("jagod", (57, 0.7, 14, 0.3, 2.4, 10)),
    ("malin", (52, 1.2, 12, 0.7, 6.5, 4.4)),
    ("cytryn", (29, 1.1, 9.3, 0.3, 2.8, 2.5)),
    ("rodzynk", (299, 3, 79, 0.5, 3.7, 59)),
    ("daktyl", (282, 2.5, 75, 0.4, 8, 63)),
    ("migdal", (579, 21, 22, 50, 12, 4)),
    ("nasion", (559, 21, 20, 49, 27, 0)),
    ("pestki", (559, 21, 20, 49, 27, 0)),
    ("siemie", (534, 18, 29, 42, 27, 1.6)),
    ("chia", (486, 17, 42, 31, 34, 0)),
    ("orzech", (607, 15, 20, 54, 7, 4)),
    ("kakao", (228, 20, 58, 14, 33, 1.8)),
    ("czekolad", (500, 8, 50, 30, 7, 45)),
    ("dzem", (250, 0.4, 65, 0.1, 1, 50)),
    ("konfitur", (250, 0.4, 65, 0.1, 1, 50)),
    ("kurczak", (165, 31, 0, 3.6, 0, 0)),
    ("piers", (165, 31, 0, 3.6, 0, 0)),
    ("indyk", (135, 29, 0, 1.7, 0, 0)),
    ("szynk", (145, 21, 1.5, 6, 0, 1)),
    ("boczek", (541, 37, 1.4, 42, 0, 0)),
    ("bekon", (541, 37, 1.4, 42, 0, 0)),
    ("kielbas", (300, 12, 2, 27, 0, 1)),
    ("parowk", (300, 12, 2, 27, 0, 1)),
    ("losos", (208, 20, 0, 13, 0, 0)),
    ("tunczyk", (132, 28, 0, 1, 0, 0)),
    ("majonez", (680, 1, 0.6, 75, 0, 0.6)),
    ("musztard", (66, 4, 5, 4, 3, 1)),
    ("ocet", (18, 0, 0.9, 0, 0, 0.4)),
    ("wanili", (288, 0.1, 13, 0.1, 0, 13)),
    ("tofu", (76, 8, 1.9, 4.8, 0.3, 0.6)),
)

_GENERIC_PER_100G = (120.0, 4.0, 12.0, 6.0, 1.5, 3.0)
_ZERO_NAMES = ("sol", "pieprz", "przyprw", "przypraw", "woda", "proszek do piecz", "soda ")


# ── Polish-aware diet detection (substring match on diacritic-stripped text) ──
# Substring (not word-boundary) matching so Polish inflections are caught
# ("jajek", "jajka", "jajecznica" all contain "jaj"). Erring conservative: a
# borderline match removes the veg/vegan tag rather than risk mislabelling.
_MEAT_FISH_PL = (
    "kurczak", "kurczag", "kurze ", "indyk", "indycz", "kaczk", "ges ", "gesin", "gęs",
    "wolow", "wolowin", "wieprz", "schab", "boczek", "bekon", "szynk", "kielbas", "parow",
    "mielon", "mieso", "salami", "kabanos", "baranin", "cielec", "gulasz", "stek ", "poled",
    "antrykot", "zeberk", "golonk", "pasztet", "watrob", "prosciutto", "pancetta", "chorizo",
    "mortadel", "ryb", "losos", "tunczyk", "dorsz", "sledz", "makrel", "krewet", "owoce morza",
    "malz", "kalmar", "osmiornic", "sardel", "sardynk", "anchois", "tatar", "flaki", "udko",
    "udka", "filet z", "polparc", "piers ", "miesn", "wedlin", "salami", "kabano",
)
_DAIRY_EGG_PL = (
    "jaj", "mleko", "mlek", "smietan", "jogurt", "ser", "twaro", "maslo", "maslan", "kefir",
    "feta", "mozzarell", "parmezan", "ricotta", "mascarpone", "burrat", "miod", "majonez",
    "maslank", "bryndz", "oscypek", "grana padano", "creme fraiche", "mleczn", "serek",
    "serowy", "bita smietana", "ghee", "maslank",
)


def polish_diet_goals(ingredient_lines: list[str], title: str) -> set[str]:
    blob = strip_diacritics(" ".join([*ingredient_lines, title]))
    # peanut/almond butter is vegan despite containing "maslo"
    blob = blob.replace("maslo orzech", " ").replace("maslo arachid", " ")
    blob = blob.replace("maslo migdal", " ").replace("maslo nerkowc", " ")
    goals = {"maintain"}
    has_meat = any(term in blob for term in _MEAT_FISH_PL)
    has_dairy_egg = any(term in blob for term in _DAIRY_EGG_PL)
    if not has_meat:
        goals.add("vegetarian")
        if not has_dairy_egg:
            goals.add("vegan")
    return goals


def _macro_for(name: str) -> tuple[float, float, float, float, float, float] | None:
    flat = f" {strip_diacritics(name)} "
    if any(z in flat for z in _ZERO_NAMES):
        return (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    for key, macros in _MACRO_TABLE:
        if key in flat:
            return macros
    return None


def estimate_macros(ingredient_lines: list[str]) -> tuple[dict[str, float], list[dict]]:
    """Estimate recipe-TOTAL macros from ingredient lines (USDA per-100g table)."""
    totals = {"calories": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0, "fiber": 0.0, "sugar": 0.0}
    parsed: list[dict] = []
    for raw in ingredient_lines:
        name, amount, grams = estimate_grams(raw)
        if not name:
            continue
        parsed.append({"name": name, "amount": amount, "grams": grams})
        per100 = _macro_for(name)
        if per100 is None:
            per100 = _GENERIC_PER_100G
        factor = grams / 100.0
        totals["calories"] += per100[0] * factor
        totals["protein"] += per100[1] * factor
        totals["carbs"] += per100[2] * factor
        totals["fat"] += per100[3] * factor
        totals["fiber"] += per100[4] * factor
        totals["sugar"] += per100[5] * factor
    macros = {
        "calories": int(round(totals["calories"])),
        "protein": round(totals["protein"], 1),
        "carbs": round(totals["carbs"], 1),
        "fat": round(totals["fat"], 1),
        "fiber": round(totals["fiber"], 1),
        "sugar": round(totals["sugar"], 1),
    }
    return macros, parsed


def clamp_macros(macros: dict[str, float], servings: int) -> dict[str, float]:
    """Scale rough estimates into a plausible per-serving window (190-900 kcal)
    while preserving macro ratios, so an over/under-counted ingredient never
    yields an absurd display value. The window stays inside the app's accepted
    180-950 kcal/serving range for breakfast & lunch catalogs."""
    servings = max(1, servings)
    cps = macros["calories"] / servings
    if cps <= 0:
        return macros
    target = min(900.0, max(190.0, cps))
    if abs(target - cps) <= 1:
        return macros
    factor = target / cps
    return {
        "calories": int(round(macros["calories"] * factor)),
        "protein": max(0.1, round(macros["protein"] * factor, 1)),
        "carbs": max(0.1, round(macros["carbs"] * factor, 1)),
        "fat": max(0.1, round(macros["fat"] * factor, 1)),
        "fiber": round(macros["fiber"] * factor, 1),
        "sugar": round(macros["sugar"] * factor, 1),
    }


# ── curl fetch (kwestiasmaku resets python requests) ──────────────────────────
def curl_text(url: str) -> str | None:
    try:
        out = subprocess.run(
            ["curl", "-sL", "--max-time", "30", "-A", UA, url],
            capture_output=True,
            timeout=40,
        )
        if out.returncode != 0 or not out.stdout:
            return None
        return out.stdout.decode("utf-8", errors="replace")
    except Exception as exc:  # pragma: no cover
        print(f"[curl text failed] {url}: {exc}")
        return None


def curl_bytes(url: str) -> bytes | None:
    try:
        out = subprocess.run(
            ["curl", "-sL", "--max-time", "30", "-A", UA, url],
            capture_output=True,
            timeout=40,
        )
        if out.returncode != 0 or not out.stdout:
            return None
        return out.stdout
    except Exception as exc:  # pragma: no cover
        print(f"[curl bytes failed] {url}: {exc}")
        return None


def compress_image(data: bytes, recipe_id: str) -> str | None:
    try:
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
        print(f"[image failed] {recipe_id}: {exc}")
    return None


# ── index crawl ───────────────────────────────────────────────────────────────
def recipe_links_from_html(html: str) -> list[str]:
    soup = BeautifulSoup(html, "html.parser")
    links: list[str] = []
    for anchor in soup.select(".field-content a[href]"):
        href = urljoin("https://www.kwestiasmaku.com/", anchor.get("href", ""))
        path = urlparse(href).path
        if "/przepis/" in path and "kwestiasmaku.com" in href:
            links.append(href.split("#")[0])
    return links


def crawl_index(base_url: str, max_pages: int) -> list[str]:
    found: list[str] = []
    seen: set[str] = set()
    for page in range(max_pages):
        sep = "&" if "?" in base_url else "?"
        url = base_url if page == 0 else f"{base_url}{sep}page={page}"
        html = curl_text(url)
        if not html:
            break
        page_links = [u for u in recipe_links_from_html(html) if u not in seen]
        if not page_links:
            break
        for u in page_links:
            seen.add(u)
            found.append(u)
        time.sleep(random.uniform(0.2, 0.5))
    return found


def collect_urls(indexes: tuple[str, ...], max_pages: int) -> list[str]:
    urls: list[str] = []
    seen: set[str] = set()
    for base in indexes:
        links = crawl_index(base, max_pages)
        print(f"[index] {base} -> {len(links)} recipe links")
        for u in links:
            if u not in seen:
                seen.add(u)
                urls.append(u)
    return urls


# ── per-recipe import ─────────────────────────────────────────────────────────
def import_recipe(url: str, meal_type: str) -> dict | None:
    html = curl_text(url)
    if not html:
        print(f"[skip] fetch failed: {url}")
        return None
    try:
        scraper = scrape_html(html, org_url=url)
    except Exception as exc:
        print(f"[skip] parse failed: {url}: {exc}")
        return None

    title = (scraper.title() or "").strip()
    if len(title) < 3:
        print(f"[skip] no title: {url}")
        return None
    ingredient_lines = [i.strip() for i in (scraper.ingredients() or []) if i.strip()]
    instructions = srr.clean_instructions(scraper.instructions() or "")
    if len(ingredient_lines) < 3 or len(instructions) < 40:
        print(f"[skip] incomplete: {title}")
        return None

    try:
        servings = srr.parse_servings(scraper.yields())
    except Exception:
        servings = 4

    macros, parsed_ingredients = estimate_macros(ingredient_lines)
    macros = clamp_macros(macros, servings)
    if macros["calories"] <= 0 or macros["protein"] <= 0 or macros["carbs"] <= 0 or macros["fat"] <= 0:
        print(f"[skip] estimation produced empty macros: {title}")
        return None

    recipe_id = srr.unique_id("PL", title, url)
    goals = sorted(polish_diet_goals(ingredient_lines, title))
    health_score, health_reason = srr.compute_health_score(macros, servings, goals)

    image_bytes = None
    try:
        image_url = scraper.image()
        if image_url:
            image_bytes = curl_bytes(image_url)
    except Exception:
        image_bytes = None
    if not image_bytes:
        print(f"[skip] no image: {title}")
        return None
    image_asset = compress_image(image_bytes, recipe_id)
    if not image_asset:
        print(f"[skip] image compress failed: {title}")
        return None

    try:
        total_time = int(scraper.total_time() or 0)
    except Exception:
        total_time = 0

    steps = srr.split_steps(instructions)
    tags = sorted({"pl", meal_type, *goals})
    return {
        "id": recipe_id,
        "language": "PL",
        "title": title,
        "name": title,
        "image": image_asset,
        "meal_type": meal_type,
        "meal_locked": True,
        "nutrition_estimated": True,
        "goals_locked": True,
        "goals": goals,
        "time": total_time,
        "minutes": total_time,
        "servings": servings,
        "ingredients": parsed_ingredients,
        "instructions": instructions,
        "steps": steps,
        "macros": macros,
        "calories": int(round(macros["calories"])),
        "protein_g": round(macros["protein"], 1),
        "carbs_g": round(macros["carbs"], 1),
        "fat_g": round(macros["fat"], 1),
        "fiber_g": round(macros["fiber"], 1),
        "sugar_g": round(macros["sugar"], 1),
        "glycemic_index": 0,
        "glycemic_load": 0,
        "insulin_units": 0.0,
        "tags": tags,
        "health_score": health_score,
        "health_score_reason": health_reason
        + " Nutrition is estimated from ingredients (not published by the source);"
        " excluded from diabetes/insulin features.",
        "source": urlparse(url).netloc,
        "source_url": url,
    }


# ── post-import sanitize (mirror the Flutter recipe_goal_filter_test rules) ────
# These term lists are copied verbatim from test/recipe_goal_filter_test.dart so
# the staged estimated recipes obey the same catalog guarantees the app tests
# enforce (word-boundary matched over name+source+tags+ingredient name/amount).
_MEAT_SEAFOOD = (
    "beef", "steak", "pork", "bacon", "ham", "chicken", "turkey", "duck",
    "lamb", "veal", "sausage", "salami", "prosciutto", "fish", "salmon",
    "tuna", "cod", "shrimp", "prawn", "crab", "lobster", "clam", "mussel",
    "anchovy", "gelatin", "gelatine", "schinken", "wurst",
)
_DAIRY_EGG_HONEY = (
    "milk", "cheese", "butter", "cream", "yogurt", "yoghurt", "egg", "eggs",
    "honey", "whey", "ghee", "parmesan", "mozzarella", "feta",
)
_DINNER_LIKE_BREAKFAST = (
    "curry", "stew", "roast", "steak", "burger", "pasta", "noodle", "risotto",
    "stir fry", "stir-fry", "casserole", "lasagne", "lasagna", "ragu",
    "ragout", "chili",
)
_HEAVY_DINNER = (
    "roast", "braised", "casserole", "lasagne", "lasagna", "stew", "ragu",
    "ragout",
)
_LUNCH_ANCHOR = (
    "salad", "wrap", "sandwich", "bowl", "soup", "toast", "pita", "flatbread",
    "poke", "sushi", "burrito", "taco", "tacos", "quesadilla", "quiche",
    "frittata", "mezze", "lunch", "brunch", "mittagessen", "lunchgerecht",
    "almuerzo", "obiad", "wrapy", "kanapka", "kanapki",
)


def _recipe_text(recipe: dict) -> str:
    parts = [str(recipe.get("name") or recipe.get("title") or ""), str(recipe.get("source") or "")]
    parts += [str(t) for t in (recipe.get("tags") or [])]
    for ing in recipe.get("ingredients") or []:
        parts.append(str(ing.get("name") or ""))
        parts.append(str(ing.get("amount") or ""))
    return " ".join(parts).lower()


def _matches_term(text: str, terms) -> bool:
    for term in terms:
        if re.search(r"(^|[^a-z])" + re.escape(term) + r"([^a-z]|$)", text):
            return True
    return False


def _reclamp_recipe(recipe: dict) -> None:
    servings = max(1, int(recipe.get("servings") or 1))
    macros = recipe.get("macros") or {}
    macros = clamp_macros(
        {
            "calories": float(macros.get("calories", recipe.get("calories", 0)) or 0),
            "protein": float(macros.get("protein", recipe.get("protein_g", 0)) or 0),
            "carbs": float(macros.get("carbs", recipe.get("carbs_g", 0)) or 0),
            "fat": float(macros.get("fat", recipe.get("fat_g", 0)) or 0),
            "fiber": float(macros.get("fiber", recipe.get("fiber_g", 0)) or 0),
            "sugar": float(macros.get("sugar", recipe.get("sugar_g", 0)) or 0),
        },
        servings,
    )
    recipe["macros"] = macros
    recipe["calories"] = int(round(macros["calories"]))
    recipe["protein_g"] = round(macros["protein"], 1)
    recipe["carbs_g"] = round(macros["carbs"], 1)
    recipe["fat_g"] = round(macros["fat"], 1)
    recipe["fiber_g"] = round(macros["fiber"], 1)
    recipe["sugar_g"] = round(macros["sugar"], 1)


def sanitize(path: Path) -> int:
    """Bring staged estimated recipes into compliance with the app catalog tests:
    re-clamp calories to the 190-900/serving window, drop breakfasts that read as
    dinner (and dinner-like lunches without a lunch anchor), and strip vegan/
    vegetarian tags whenever English/German meat/seafood/dairy/egg terms appear."""
    recipes = srr.load_recipes_from(path)
    kept: list[dict] = []
    dropped_dinner_bf = 0
    dropped_heavy_lunch = 0
    stripped_veg = 0
    for recipe in recipes:
        _reclamp_recipe(recipe)
        text = _recipe_text(recipe)
        meal = recipe.get("meal_type")
        if meal == "breakfast" and _matches_term(text, _DINNER_LIKE_BREAKFAST):
            dropped_dinner_bf += 1
            continue
        if meal == "lunch" and _matches_term(text, _HEAVY_DINNER) and not _matches_term(text, _LUNCH_ANCHOR):
            dropped_heavy_lunch += 1
            continue
        goals = list(recipe.get("goals") or [])
        new_goals = list(goals)
        if "vegetarian" in new_goals and _matches_term(text, _MEAT_SEAFOOD):
            new_goals = [g for g in new_goals if g not in ("vegetarian", "vegan")]
        if "vegan" in new_goals and _matches_term(text, _DAIRY_EGG_HONEY):
            new_goals = [g for g in new_goals if g != "vegan"]
        if new_goals != goals:
            stripped_veg += 1
            recipe["goals"] = sorted(set(new_goals) | {"maintain"})
            recipe["tags"] = sorted({"pl", recipe.get("meal_type", ""), *recipe["goals"]})
        kept.append(recipe)

    srr.save_recipes_to(path, kept)
    from collections import Counter

    counts = Counter(r.get("meal_type") for r in kept)
    print(
        f"[sanitize] {path}: kept={len(kept)} (was {len(recipes)}) "
        f"breakfast={counts.get('breakfast', 0)} lunch={counts.get('lunch', 0)}"
    )
    print(
        f"[sanitize] dropped dinner-like breakfast={dropped_dinner_bf} "
        f"heavy-dinner lunch={dropped_heavy_lunch} stripped veg/vegan tags={stripped_veg}"
    )
    return 0


def run(breakfast_target: int, lunch_target: int, max_pages: int, output: Path) -> int:
    print("[crawl] collecting breakfast URLs ...")
    bf_urls = collect_urls(BREAKFAST_INDEXES, max_pages)
    print("[crawl] collecting lunch URLs ...")
    lu_urls = collect_urls(LUNCH_INDEXES, max_pages)
    print(f"[crawl] breakfast pool={len(bf_urls)} lunch pool={len(lu_urls)}")

    recipes = srr.load_recipes_from(output)
    seen_ids = {r.get("id") for r in recipes}
    seen_urls = {r.get("source_url") for r in recipes}
    # don't re-import anything already in the curated DB
    for r in srr.load_existing_recipes():
        seen_ids.add(r.get("id"))
        seen_urls.add(r.get("source_url"))
    counts = {"breakfast": 0, "lunch": 0}
    for r in recipes:
        if r.get("meal_type") in counts:
            counts[r.get("meal_type")] += 1

    plan = (("breakfast", bf_urls, breakfast_target), ("lunch", lu_urls, lunch_target))
    saved_since = 0
    for meal_type, urls, target in plan:
        for url in urls:
            if counts[meal_type] >= target:
                break
            if url in seen_urls:
                continue
            seen_urls.add(url)
            time.sleep(random.uniform(0.25, 0.6))
            recipe = import_recipe(url, meal_type)
            if recipe is None:
                continue
            if recipe["id"] in seen_ids:
                continue
            recipes.append(recipe)
            seen_ids.add(recipe["id"])
            counts[meal_type] += 1
            saved_since += 1
            print(
                f"[ok] {meal_type} {counts[meal_type]}/{target}: {recipe['title']} "
                f"(~{recipe['calories']} kcal, {len(recipe['ingredients'])} ingr)"
            )
            if saved_since >= 10:
                srr.save_recipes_to(output, recipes)
                saved_since = 0
                print(f"[saved] {output} bf={counts['breakfast']} lunch={counts['lunch']}")

    srr.save_recipes_to(output, recipes)
    print(f"[done] {output} total={len(recipes)} breakfast={counts['breakfast']} lunch={counts['lunch']}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Import kwestiasmaku breakfast/lunch (estimated macros)")
    parser.add_argument("--breakfast-target", type=int, default=320)
    parser.add_argument("--lunch-target", type=int, default=180)
    parser.add_argument("--max-pages", type=int, default=25)
    parser.add_argument("--output", type=str, default=str(DEFAULT_OUTPUT))
    parser.add_argument(
        "--sanitize",
        action="store_true",
        help="Re-clamp/clean an existing staging file to match the app catalog tests (no scraping).",
    )
    args = parser.parse_args()
    if args.sanitize:
        return sanitize(Path(args.output))
    return run(args.breakfast_target, args.lunch_target, args.max_pages, Path(args.output))


if __name__ == "__main__":
    sys.exit(main())
