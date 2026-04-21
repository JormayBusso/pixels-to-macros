"""
nutrition_calculator.py
───────────────────────
Fetches nutrient data from the USDA FoodData Central API for each food item,
then scales the per-100g values by the estimated weight.

USDA API docs: https://fdc.nal.usda.gov/api-guide.html
Free API key:  https://fdc.nal.usda.gov/api-key-signup.html
"""

import os
import requests

USDA_BASE_URL = "https://api.nal.usda.gov/fdc/v1"

# Nutrient IDs in USDA FoodData Central database
# Full list: https://fdc.nal.usda.gov/food-details/747447/nutrients
NUTRIENT_IDS = {
    "calories":             1008,  # Energy (kcal)
    "protein":              1003,  # Protein (g)
    "carbohydrates":        1005,  # Carbohydrate, by difference (g)
    "fiber":                1079,  # Fiber, total dietary (g)
    "sugars":               2000,  # Sugars, total (g)
    "fat":                  1004,  # Total lipid (fat) (g)
    "saturated_fat":        1258,  # Fatty acids, total saturated (g)
    "monounsaturated_fat":  1292,  # Fatty acids, total monounsaturated (g)
    "polyunsaturated_fat":  1293,  # Fatty acids, total polyunsaturated (g)
    "trans_fat":            1257,  # Fatty acids, total trans (g)
    "cholesterol":          1253,  # Cholesterol (mg)
    "sodium":               1093,  # Sodium, Na (mg)
    "potassium":            1092,  # Potassium, K (mg)
    "calcium":              1087,  # Calcium, Ca (mg)
    "iron":                 1089,  # Iron, Fe (mg)
    "vitamin_c":            1162,  # Vitamin C (mg)
    "vitamin_d":            1114,  # Vitamin D (IU)
    "vitamin_a":            1106,  # Vitamin A, RAE (µg)
    "vitamin_b12":          1178,  # Vitamin B-12 (µg)
    "folate":               1177,  # Folate, total (µg)
    "zinc":                 1095,  # Zinc, Zn (mg)
}

NUTRIENT_UNITS = {
    "calories":             "kcal",
    "protein":              "g",
    "carbohydrates":        "g",
    "fiber":                "g",
    "sugars":               "g",
    "fat":                  "g",
    "saturated_fat":        "g",
    "monounsaturated_fat":  "g",
    "polyunsaturated_fat":  "g",
    "trans_fat":            "g",
    "cholesterol":          "mg",
    "sodium":               "mg",
    "potassium":            "mg",
    "calcium":              "mg",
    "iron":                 "mg",
    "vitamin_c":            "mg",
    "vitamin_d":            "IU",
    "vitamin_a":            "µg",
    "vitamin_b12":          "µg",
    "folate":               "µg",
    "zinc":                 "mg",
}


def _get_api_key() -> str:
    key = os.getenv("USDA_API_KEY", "DEMO_KEY")
    return key


def _search_food(query: str) -> dict | None:
    """
    Search USDA for a food item and return the first matching result's nutrients.
    Returns a dict {nutrient_key: value_per_100g} or None on failure.
    """
    api_key = _get_api_key()
    params = {
        "api_key": api_key,
        "query": query,
        "dataType": ["Foundation", "SR Legacy", "Branded"],
        "pageSize": 5,
    }

    try:
        resp = requests.get(f"{USDA_BASE_URL}/foods/search", params=params, timeout=10)
        resp.raise_for_status()
        data = resp.json()
    except requests.RequestException as exc:
        raise RuntimeError(f"USDA API request failed for '{query}': {exc}") from exc

    foods = data.get("foods", [])
    if not foods:
        return None

    # Prefer Foundation or SR Legacy over Branded
    preferred = [f for f in foods if f.get("dataType") in ("Foundation", "SR Legacy")]
    food = preferred[0] if preferred else foods[0]

    return _extract_nutrients(food)


def _extract_nutrients(food_data: dict) -> dict:
    """Extract nutrient values per 100g from a USDA food record."""
    nutrients_raw = food_data.get("foodNutrients", [])

    # Build a map: nutrient_id → value
    id_to_value: dict[int, float] = {}
    for n in nutrients_raw:
        nid = n.get("nutrientId") or n.get("nutrient", {}).get("id")
        val = n.get("value") or n.get("amount", 0.0)
        if nid is not None:
            id_to_value[int(nid)] = float(val or 0.0)

    result: dict[str, float] = {}
    for key, nid in NUTRIENT_IDS.items():
        result[key] = id_to_value.get(nid, 0.0)

    result["food_name"] = food_data.get("description", "Unknown")
    result["fdc_id"] = food_data.get("fdcId")
    return result


def calculate_nutrition(food_items: list[dict]) -> dict:
    """
    For each food item, fetch per-100g nutrients from USDA and scale by weight.

    Parameters
    ----------
    food_items : list of dicts (output from volume_estimation.estimate_volumes)
                 each must have 'name' and 'estimated_weight_g'

    Returns
    -------
    {
      "items": [
        {
          "name": str,
          "weight_g": float,
          "matched_food": str,        # USDA food name
          "fdc_id": int | None,
          "nutrients": {key: {"value": float, "unit": str}, ...}
        },
        ...
      ],
      "totals": {key: {"value": float, "unit": str}, ...}
    }
    """
    result_items: list[dict] = []
    totals: dict[str, float] = {k: 0.0 for k in NUTRIENT_IDS}

    for item in food_items:
        weight_g = item.get("estimated_weight_g", 100.0)
        food_name = item["name"]

        per_100g = _search_food(food_name)

        if per_100g is None:
            # Fallback: use generic values
            per_100g = _fallback_nutrients(food_name)

        scaled: dict[str, dict] = {}
        for key in NUTRIENT_IDS:
            raw_val = per_100g.get(key, 0.0)
            scaled_val = round(raw_val * weight_g / 100.0, 2)
            scaled[key] = {"value": scaled_val, "unit": NUTRIENT_UNITS[key]}
            totals[key] += scaled_val

        result_items.append(
            {
                "name": food_name,
                "weight_g": weight_g,
                "matched_food": per_100g.get("food_name", food_name),
                "fdc_id": per_100g.get("fdc_id"),
                "nutrients": scaled,
                "volume_cm3": item.get("volume_cm3"),
                "confidence": item.get("confidence"),
                "scale_method": item.get("scale_method"),
            }
        )

    totals_formatted = {
        k: {"value": round(v, 2), "unit": NUTRIENT_UNITS[k]} for k, v in totals.items()
    }

    return {"items": result_items, "totals": totals_formatted}


def recalculate_item(food_name: str, weight_g: float) -> dict:
    """
    Recalculate nutrients for a single food item at a given weight.
    Used when the user manually adjusts a food or its weight.
    """
    per_100g = _search_food(food_name)
    if per_100g is None:
        per_100g = _fallback_nutrients(food_name)

    scaled: dict[str, dict] = {}
    for key in NUTRIENT_IDS:
        raw_val = per_100g.get(key, 0.0)
        scaled_val = round(raw_val * weight_g / 100.0, 2)
        scaled[key] = {"value": scaled_val, "unit": NUTRIENT_UNITS[key]}

    return {
        "name": food_name,
        "weight_g": weight_g,
        "matched_food": per_100g.get("food_name", food_name),
        "fdc_id": per_100g.get("fdc_id"),
        "nutrients": scaled,
    }


# ── Fallback nutrient estimates ───────────────────────────────────────────────
# Used when the USDA API returns no results. Generic averages per 100g.
_FALLBACK_TABLE: dict[str, dict] = {
    "default": {
        "calories": 150, "protein": 8, "carbohydrates": 15, "fiber": 2,
        "sugars": 3, "fat": 7, "saturated_fat": 2, "monounsaturated_fat": 3,
        "polyunsaturated_fat": 1, "trans_fat": 0, "cholesterol": 20,
        "sodium": 200, "potassium": 200, "calcium": 50, "iron": 1,
        "vitamin_c": 5, "vitamin_d": 0, "vitamin_a": 20, "vitamin_b12": 0,
        "folate": 15, "zinc": 1,
    },
    "chicken": {
        "calories": 165, "protein": 31, "carbohydrates": 0, "fiber": 0,
        "sugars": 0, "fat": 3.6, "saturated_fat": 1, "monounsaturated_fat": 1.5,
        "polyunsaturated_fat": 0.8, "trans_fat": 0, "cholesterol": 85,
        "sodium": 74, "potassium": 256, "calcium": 15, "iron": 1,
        "vitamin_c": 0, "vitamin_d": 4, "vitamin_a": 6, "vitamin_b12": 0.3,
        "folate": 4, "zinc": 1,
    },
    "rice": {
        "calories": 130, "protein": 2.7, "carbohydrates": 28, "fiber": 0.4,
        "sugars": 0, "fat": 0.3, "saturated_fat": 0.1, "monounsaturated_fat": 0.1,
        "polyunsaturated_fat": 0.1, "trans_fat": 0, "cholesterol": 0,
        "sodium": 1, "potassium": 35, "calcium": 10, "iron": 0.2,
        "vitamin_c": 0, "vitamin_d": 0, "vitamin_a": 0, "vitamin_b12": 0,
        "folate": 3, "zinc": 0.5,
    },
    "broccoli": {
        "calories": 34, "protein": 2.8, "carbohydrates": 7, "fiber": 2.6,
        "sugars": 1.7, "fat": 0.4, "saturated_fat": 0.04, "monounsaturated_fat": 0,
        "polyunsaturated_fat": 0.2, "trans_fat": 0, "cholesterol": 0,
        "sodium": 33, "potassium": 316, "calcium": 47, "iron": 0.7,
        "vitamin_c": 89, "vitamin_d": 0, "vitamin_a": 31, "vitamin_b12": 0,
        "folate": 63, "zinc": 0.4,
    },
}


def _fallback_nutrients(food_name: str) -> dict:
    name_lower = food_name.lower()
    for key, vals in _FALLBACK_TABLE.items():
        if key != "default" and key in name_lower:
            result = dict(vals)
            result["food_name"] = f"{food_name} (estimated)"
            result["fdc_id"] = None
            return result
    result = dict(_FALLBACK_TABLE["default"])
    result["food_name"] = f"{food_name} (estimated)"
    result["fdc_id"] = None
    return result
