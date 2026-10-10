"""
Build a bundled recipes.json for the Pixels to Macros app.

Pulls free recipes from TheMealDB (no key required) and combines them with a
curated procedural pack so that every nutrition goal × meal type bucket has
plenty of options. Output:

    assets/recipes.json   — single JSON array, ~1000 recipes
    assets/recipes_meta.json — counts per (goal, meal type)

Each recipe row:
{
  "id":        "tmdb-52772",
  "name":      "Teriyaki Chicken Casserole",
  "image":     "https://www.themealdb.com/...jpg",   (optional)
  "meal_type": "dinner",                              (breakfast|lunch|dinner|snack)
  "goals":     ["muscle", "maintain"],               (subset of NutritionGoalType)
  "minutes":   45,
  "servings":  4,
  "calories":  520,                                  (per serving, est.)
  "protein_g": 38,
  "carbs_g":   42,
  "fat_g":     18,
  "tags":      ["chicken","japanese","high-protein"],
  "ingredients": [{"name":"chicken thigh","amount":"500 g"}, ...],
  "steps":     ["Preheat oven...", "Mix sauce..."],
  "source":    "TheMealDB" | "Curated"
}

Run:
    python scripts/build_recipes_json.py
"""

from __future__ import annotations

import json
import re
import time
import urllib.error
import urllib.request
from pathlib import Path

OUT_PATH = Path("assets/recipes.json")
META_PATH = Path("assets/recipes_meta.json")
THEMEALDB_BASE = "https://www.themealdb.com/api/json/v1/1"

GOALS = ("muscle", "diabetes", "vegan", "weight_loss", "keto", "maintain")
MEAL_TYPES = ("breakfast", "lunch", "dinner", "snack")


# ─────────────────────────── Heuristics ───────────────────────────

VEGAN_BLOCK = {
    "chicken", "beef", "pork", "lamb", "fish", "salmon", "tuna", "shrimp",
    "prawn", "egg", "milk", "cheese", "butter", "yogurt", "yoghurt", "honey",
    "ham", "bacon", "duck", "anchovy", "gelatin",
}
HIGH_PROTEIN = {
    "chicken", "beef", "salmon", "tuna", "egg", "tofu", "tempeh", "yogurt",
    "yoghurt", "cottage cheese", "lentil", "chickpea", "shrimp", "tuna",
    "turkey",
}
LOW_CARB_BLOCK = {
    "rice", "pasta", "bread", "noodle", "potato", "sugar", "flour", "oats",
    "tortilla", "couscous", "quinoa", "polenta", "bun", "honey",
}
SUGARY = {
    "sugar", "honey", "syrup", "chocolate", "candy", "caramel", "fructose",
    "molasses",
}


def http_json(url: str, retries: int = 3, sleep: float = 0.4):
    last_err = None
    for _ in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=15) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.URLError as e:
            last_err = e
            time.sleep(sleep)
    raise RuntimeError(f"GET {url} failed: {last_err}")


def fetch_themealdb_all_ids() -> list[str]:
    """List meal IDs by walking categories (TheMealDB has no full dump)."""
    ids: list[str] = []
    cats = http_json(f"{THEMEALDB_BASE}/list.php?c=list").get("meals", []) or []
    for cat in cats:
        cat_name = cat["strCategory"]
        rows = http_json(
            f"{THEMEALDB_BASE}/filter.php?c={urllib.parse.quote(cat_name)}"
        ).get("meals", []) or []
        ids.extend(r["idMeal"] for r in rows)
    # Dedup while preserving order.
    seen = set()
    deduped = []
    for i in ids:
        if i not in seen:
            seen.add(i)
            deduped.append(i)
    return deduped


def fetch_themealdb_meal(meal_id: str) -> dict | None:
    rows = http_json(f"{THEMEALDB_BASE}/lookup.php?i={meal_id}").get("meals")
    if not rows:
        return None
    return rows[0]


# ─────────────────────────── Normalisation ───────────────────────────

def parse_themealdb_meal(raw: dict) -> dict:
    name = (raw.get("strMeal") or "").strip()
    image = (raw.get("strMealThumb") or "").strip() or None
    instructions = (raw.get("strInstructions") or "").strip()
    category = (raw.get("strCategory") or "").lower()
    area = (raw.get("strArea") or "").lower()

    ingredients = []
    flat_ingredient_names: list[str] = []
    for i in range(1, 21):
        ing = (raw.get(f"strIngredient{i}") or "").strip()
        amt = (raw.get(f"strMeasure{i}") or "").strip()
        if not ing:
            continue
        ingredients.append({"name": ing, "amount": amt})
        flat_ingredient_names.append(ing.lower())

    steps = [
        s.strip() for s in re.split(r"(?<=[.!?])\s+(?=[A-Z])|\r?\n+", instructions)
        if len(s.strip()) > 4
    ]

    # Heuristic meal-type assignment from category.
    meal_type = (
        "dessert" if category in {"dessert"} else
        "breakfast" if category in {"breakfast"} else
        "snack" if category in {"side", "starter", "miscellaneous"} else
        "lunch" if area in {"japanese", "italian", "thai", "indian", "chinese"} else
        "dinner"
    )
    if meal_type == "dessert":
        meal_type = "snack"

    goals = derive_goals(flat_ingredient_names, category)

    return {
        "id": f"tmdb-{raw['idMeal']}",
        "name": name,
        "image": image,
        "meal_type": meal_type,
        "goals": goals,
        "minutes": _estimate_minutes(steps),
        "servings": 4,
        "tags": [t for t in {category, area} if t],
        "ingredients": ingredients,
        "steps": steps,
        "source": "TheMealDB",
        # Macros are unknown for free TheMealDB rows; leave 0 — the app
        # falls back to "estimate from ingredients" when displaying recipes.
        "calories": 0,
        "protein_g": 0,
        "carbs_g": 0,
        "fat_g": 0,
    }


def derive_goals(ingredients: list[str], category: str) -> list[str]:
    text = " ".join(ingredients) + " " + category
    goals: set[str] = set()

    is_vegan = not any(b in text for b in VEGAN_BLOCK)
    if is_vegan:
        goals.add("vegan")

    high_protein = any(p in text for p in HIGH_PROTEIN)
    if high_protein:
        goals.add("muscle")

    low_carb = not any(c in text for c in LOW_CARB_BLOCK)
    if low_carb:
        goals.add("keto")
        goals.add("diabetes")

    sugary = any(s in text for s in SUGARY)
    if not sugary:
        goals.add("maintain")
        if not low_carb and high_protein:
            goals.add("weight_loss")

    if not goals:
        goals.add("maintain")
    return sorted(goals)


def _estimate_minutes(steps: list[str]) -> int:
    # Rough heuristic: ~5 minutes per non-trivial step, capped 15..120.
    n = max(1, len([s for s in steps if len(s) > 20]))
    return max(15, min(120, n * 5 + 10))


# ─────────────────────────── Curated supplement ───────────────────────────
#
# A small catalogue of ingredient templates × cooking methods. Combined they
# generate hundreds of plausible recipes that fill in goal/meal-type buckets
# the TheMealDB pull might leave thin. These are intentionally simple
# meal-prep style recipes so the steps are reliably correct.

PROTEIN_OPTIONS = [
    ("chicken breast", 150, 31, 0, 3.6, ["chicken"]),
    ("salmon fillet", 150, 22, 0, 13, ["fish"]),
    ("tofu", 150, 12, 3, 7, ["vegan", "tofu"]),
    ("tempeh", 150, 19, 9, 11, ["vegan", "soy"]),
    ("ground turkey", 150, 27, 0, 8, ["turkey"]),
    ("beef sirloin", 150, 26, 0, 9, ["beef"]),
    ("eggs (3)", 150, 18, 1, 15, ["egg"]),
    ("greek yogurt", 200, 18, 7, 4, ["yogurt"]),
    ("cottage cheese", 200, 22, 7, 4, ["dairy"]),
    ("lentils", 200, 18, 40, 1, ["vegan", "legume"]),
    ("chickpeas", 200, 19, 45, 6, ["vegan", "legume"]),
    ("shrimp", 150, 24, 0, 1.5, ["seafood"]),
]
CARB_OPTIONS = [
    ("brown rice", 200, 5, 45, 1.5, ["grain"]),
    ("quinoa", 200, 8, 39, 4, ["grain", "vegan"]),
    ("sweet potato", 200, 4, 41, 0.2, ["vegetable"]),
    ("rolled oats", 80, 10, 54, 6, ["grain", "vegan"]),
    ("whole-wheat pasta", 200, 14, 70, 2, ["grain", "vegan"]),
    ("none (low-carb)", 0, 0, 0, 0, ["keto"]),
]
VEG_OPTIONS = [
    ("steamed broccoli", 150, 4, 11, 0.6, ["vegetable", "vegan"]),
    ("roasted bell peppers", 150, 1, 9, 0.3, ["vegetable", "vegan"]),
    ("baby spinach", 100, 3, 4, 0.4, ["vegetable", "vegan"]),
    ("zucchini", 200, 2, 6, 0.4, ["vegetable", "vegan", "keto"]),
    ("mixed salad greens", 100, 1, 3, 0.2, ["vegetable", "vegan", "keto"]),
    ("asparagus", 150, 3, 6, 0.2, ["vegetable", "vegan", "keto"]),
]
FAT_OPTIONS = [
    ("olive oil drizzle", 10, 0, 0, 9, ["fat"]),
    ("avocado", 80, 1.5, 6, 12, ["fat", "vegan", "keto"]),
    ("almonds (handful)", 25, 5, 5, 14, ["fat", "vegan", "nut"]),
    ("none", 0, 0, 0, 0, []),
]


def curated_pack() -> list[dict]:
    out: list[dict] = []
    for proto in PROTEIN_OPTIONS:
        for carb in CARB_OPTIONS:
            for veg in VEG_OPTIONS:
                fat = FAT_OPTIONS[0] if "vegan" in proto[5] else FAT_OPTIONS[1]
                cal = (proto[1] / 100 * (proto[2] * 4 + proto[3] * 4 + proto[4] * 9)
                       + carb[1] / 100 * (carb[2] * 4 + carb[3] * 4 + carb[4] * 9)
                       + veg[1] / 100 * (veg[2] * 4 + veg[3] * 4 + veg[4] * 9)
                       + fat[1] / 100 * (fat[2] * 4 + fat[3] * 4 + fat[4] * 9))
                p_g = proto[2] + carb[2] + veg[2] + fat[2]
                c_g = proto[3] + carb[3] + veg[3] + fat[3]
                f_g = proto[4] + carb[4] + veg[4] + fat[4]
                tags = sorted(set(proto[5] + carb[5] + veg[5] + fat[5]))
                goals = []
                if "vegan" in proto[5] and "vegan" in carb[5] and "vegan" in veg[5]:
                    goals.append("vegan")
                if proto[2] >= 18:
                    goals.append("muscle")
                if c_g <= 20:
                    goals.append("keto")
                    goals.append("diabetes")
                if cal <= 450 and proto[2] >= 18:
                    goals.append("weight_loss")
                goals.append("maintain")
                goals = sorted(set(goals))

                proto_name = proto[0].split(" (")[0]
                carb_name = carb[0]
                veg_name = veg[0]
                name = f"{proto_name.title()} with {carb_name} & {veg_name}"
                if carb_name.startswith("none"):
                    name = f"Low-carb {proto_name.title()} & {veg_name}"

                # Decide meal type by total calories.
                meal_type = (
                    "snack" if cal < 250 else
                    "breakfast" if "oats" in carb_name or "yogurt" in proto_name or "egg" in proto_name else
                    "lunch" if cal < 500 else
                    "dinner"
                )

                steps = [
                    f"Season the {proto_name} with salt, pepper and a pinch of paprika.",
                    "Heat a non-stick pan over medium-high heat with a drop of oil.",
                    f"Cook the {proto_name} until done (internal temperature reached for safety), about 6-10 minutes per side.",
                ]
                if not carb_name.startswith("none"):
                    steps.append(
                        f"Meanwhile, cook the {carb_name} according to package directions."
                    )
                steps.append(
                    f"Steam or sauté the {veg_name} until tender-crisp, 4-6 minutes."
                )
                steps.append(
                    f"Plate everything together, finish with {fat[0]}, and serve."
                )

                out.append({
                    "id": f"curated-{proto_name}-{carb_name}-{veg_name}".replace(" ", "_"),
                    "name": name,
                    "image": None,
                    "meal_type": meal_type,
                    "goals": goals,
                    "minutes": 25,
                    "servings": 1,
                    "tags": tags,
                    "ingredients": [
                        {"name": proto[0], "amount": f"{proto[1]} g"},
                        *([{"name": carb[0], "amount": f"{carb[1]} g"}]
                          if carb[1] > 0 else []),
                        {"name": veg[0], "amount": f"{veg[1]} g"},
                        *([{"name": fat[0], "amount": f"{fat[1]} g"}]
                          if fat[1] > 0 else []),
                    ],
                    "steps": steps,
                    "source": "Curated",
                    "calories": round(cal),
                    "protein_g": round(p_g, 1),
                    "carbs_g": round(c_g, 1),
                    "fat_g": round(f_g, 1),
                })
    return out


# ─────────────────────────── Main ───────────────────────────

def main() -> None:
    print("Building recipes.json…")
    recipes: list[dict] = []

    # 1. TheMealDB (real recipes, ~300)
    try:
        ids = fetch_themealdb_all_ids()
        print(f"  TheMealDB: {len(ids)} meal IDs")
        for n, mid in enumerate(ids, 1):
            try:
                raw = fetch_themealdb_meal(mid)
                if raw:
                    recipes.append(parse_themealdb_meal(raw))
            except Exception as e:
                print(f"    skip {mid}: {e}")
            if n % 50 == 0:
                print(f"    fetched {n}/{len(ids)}")
            time.sleep(0.05)  # be polite
    except Exception as e:
        print(f"  TheMealDB pull failed ({e}); continuing with curated only.")

    # 2. Curated supplement (procedural, ~1000-2000)
    curated = curated_pack()
    print(f"  Curated pack: {len(curated)} recipes")
    recipes.extend(curated)

    # 3. Cap to ~1100 to keep app size reasonable, but keep at least 60
    #    recipes per (goal, meal_type) bucket where possible.
    by_bucket: dict[tuple[str, str], list[dict]] = {}
    for r in recipes:
        for g in r["goals"]:
            by_bucket.setdefault((g, r["meal_type"]), []).append(r)

    selected_ids: set[str] = set()
    selected: list[dict] = []
    quota_per_bucket = 60
    for bucket_recipes in by_bucket.values():
        for r in bucket_recipes[:quota_per_bucket]:
            if r["id"] not in selected_ids:
                selected_ids.add(r["id"])
                selected.append(r)

    # If under 1000, top up with the remaining unique recipes.
    if len(selected) < 1000:
        for r in recipes:
            if r["id"] not in selected_ids:
                selected_ids.add(r["id"])
                selected.append(r)
                if len(selected) >= 1100:
                    break

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(selected, ensure_ascii=False, indent=0))
    size_mb = OUT_PATH.stat().st_size / 1e6
    print(f"  Wrote {OUT_PATH} ({len(selected)} recipes, {size_mb:.2f} MB)")

    meta = {
        "total": len(selected),
        "by_goal": {
            g: sum(1 for r in selected if g in r["goals"]) for g in GOALS
        },
        "by_meal_type": {
            mt: sum(1 for r in selected if r["meal_type"] == mt) for mt in MEAL_TYPES
        },
        "by_source": {
            s: sum(1 for r in selected if r["source"] == s)
            for s in {"TheMealDB", "Curated"}
        },
    }
    META_PATH.write_text(json.dumps(meta, indent=2))
    print("  Meta:", json.dumps(meta, indent=2))


if __name__ == "__main__":
    import urllib.parse  # late import to avoid F401 noise
    main()
