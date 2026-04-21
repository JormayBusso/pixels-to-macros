"""
suggestions.py
──────────────
Smart suggestions engine, vitamin checker, grocery list generator,
and gamification streak logic.
"""

from datetime import date as date_type, timedelta
from typing import Optional
from sqlalchemy.orm import Session

# ── Recommended Daily Values ──────────────────────────────────────────────────

DAILY_VITAMIN_RDV: dict[str, dict] = {
    "vitamin_c":  {"rdv": 90,   "unit": "mg",  "name": "Vitamin C"},
    "vitamin_d":  {"rdv": 800,  "unit": "IU",  "name": "Vitamin D"},
    "vitamin_a":  {"rdv": 900,  "unit": "µg",  "name": "Vitamin A"},
    "vitamin_b12":{"rdv": 2.4,  "unit": "µg",  "name": "Vitamin B12"},
    "folate":     {"rdv": 400,  "unit": "µg",  "name": "Folate"},
    "calcium":    {"rdv": 1000, "unit": "mg",  "name": "Calcium"},
    "iron":       {"rdv": 18,   "unit": "mg",  "name": "Iron"},
    "zinc":       {"rdv": 11,   "unit": "mg",  "name": "Zinc"},
    "potassium":  {"rdv": 4700, "unit": "mg",  "name": "Potassium"},
}

# ── Nutrient → rich food sources ─────────────────────────────────────────────

NUTRIENT_FOOD_MAP: dict[str, list[str]] = {
    "vitamin_c":   ["bell peppers", "oranges", "strawberries", "kiwi", "broccoli"],
    "vitamin_d":   ["salmon", "tuna", "egg yolks", "fortified milk"],
    "vitamin_a":   ["sweet potato", "carrots", "spinach", "kale"],
    "vitamin_b12": ["beef", "chicken", "eggs", "dairy products", "fortified cereals"],
    "folate":      ["lentils", "black beans", "asparagus", "leafy greens"],
    "calcium":     ["milk", "yogurt", "cheese", "broccoli", "almonds"],
    "iron":        ["lean beef", "spinach", "lentils", "tofu", "pumpkin seeds"],
    "zinc":        ["beef", "pumpkin seeds", "chickpeas", "cashews"],
    "potassium":   ["bananas", "sweet potato", "avocado", "spinach"],
    "protein":     ["chicken breast", "greek yogurt", "eggs", "lentils", "tuna"],
    "fiber":       ["oats", "berries", "lentils", "broccoli", "whole grain bread"],
}

# ── Goal macro targets (% of calories) ───────────────────────────────────────

DIETARY_GOAL_MACROS: dict[str, dict] = {
    "balanced":      {"protein_pct": 25, "carbs_pct": 50, "fat_pct": 25},
    "diabetic":      {"protein_pct": 25, "carbs_pct": 40, "fat_pct": 35},
    "low_carb":      {"protein_pct": 35, "carbs_pct": 20, "fat_pct": 45},
    "muscle_growth": {"protein_pct": 35, "carbs_pct": 45, "fat_pct": 20},
    "weight_loss":   {"protein_pct": 30, "carbs_pct": 40, "fat_pct": 30},
    "vegan":         {"protein_pct": 20, "carbs_pct": 55, "fat_pct": 25},
    "keto":          {"protein_pct": 25, "carbs_pct": 5,  "fat_pct": 70},
    "mediterranean": {"protein_pct": 20, "carbs_pct": 50, "fat_pct": 30},
}

# ── Grocery categories ────────────────────────────────────────────────────────

_FOOD_CATEGORY: dict[str, str] = {
    "bell peppers": "Produce", "oranges": "Produce", "strawberries": "Produce",
    "kiwi": "Produce", "broccoli": "Produce", "sweet potato": "Produce",
    "carrots": "Produce", "spinach": "Produce", "kale": "Produce",
    "bananas": "Produce", "avocado": "Produce", "berries": "Produce",
    "asparagus": "Produce", "leafy greens": "Produce",
    "salmon": "Meat & Fish", "tuna": "Meat & Fish", "lean beef": "Meat & Fish",
    "beef": "Meat & Fish", "chicken breast": "Meat & Fish", "chicken": "Meat & Fish",
    "tofu": "Protein Alternatives",
    "lentils": "Legumes", "black beans": "Legumes", "chickpeas": "Legumes",
    "milk": "Dairy", "yogurt": "Dairy", "cheese": "Dairy",
    "fortified milk": "Dairy", "greek yogurt": "Dairy", "dairy products": "Dairy",
    "egg yolks": "Dairy & Eggs", "eggs": "Dairy & Eggs",
    "almonds": "Nuts & Seeds", "pumpkin seeds": "Nuts & Seeds", "cashews": "Nuts & Seeds",
    "oats": "Grains", "whole grain bread": "Grains", "fortified cereals": "Grains",
}


def _get_nutrient_value(nutrients: dict, key: str) -> float:
    val = nutrients.get(key, {})
    if isinstance(val, dict):
        return float(val.get("value", 0) or 0)
    return float(val or 0)


def check_vitamins(nutrients: dict) -> list[dict]:
    """Return status for every tracked vitamin/mineral."""
    result = []
    for key, info in DAILY_VITAMIN_RDV.items():
        current = _get_nutrient_value(nutrients, key)
        pct = (current / info["rdv"] * 100) if info["rdv"] > 0 else 0
        result.append({
            "key": key,
            "name": info["name"],
            "current": round(current, 2),
            "rdv": info["rdv"],
            "unit": info["unit"],
            "percentage": round(min(pct, 100), 1),
            "status": (
                "sufficient" if pct >= 80
                else ("low" if pct >= 40 else "deficient")
            ),
        })
    return result


def generate_suggestions(
    nutrients: dict,
    dietary_goal: str,
    caloric_target: Optional[int],
) -> list[str]:
    """Produce human-readable dietary advice."""
    suggestions: list[str] = []

    calories = _get_nutrient_value(nutrients, "calories")
    protein  = _get_nutrient_value(nutrients, "protein")
    carbs    = _get_nutrient_value(nutrients, "carbohydrates")
    fiber    = _get_nutrient_value(nutrients, "fiber")
    sodium   = _get_nutrient_value(nutrients, "sodium")

    target = caloric_target or 2000
    goal_macros = DIETARY_GOAL_MACROS.get(dietary_goal, DIETARY_GOAL_MACROS["balanced"])

    # Calorie check
    if calories < target * 0.6:
        suggestions.append(
            f"You've only consumed {int(calories)} kcal — well below your {target} kcal target. "
            "Consider a nutritious snack to fuel your body."
        )
    elif calories > target * 1.2:
        suggestions.append(
            f"You've exceeded your daily calorie target ({int(calories)}/{target} kcal). "
            "Consider lighter options for the rest of the day."
        )

    # Protein check
    protein_target_g = (target * goal_macros["protein_pct"] / 100) / 4
    if protein < protein_target_g * 0.7:
        suggestions.append(
            f"Your protein intake ({int(protein)}g) is below target. "
            "Try adding chicken, eggs, Greek yogurt, or legumes."
        )

    # Fiber check
    if fiber < 15:
        suggestions.append(
            "You're falling short on fiber today. "
            "Adding more vegetables, fruits, or whole grains will help."
        )

    # Sodium check
    if sodium > 2300:
        suggestions.append(
            f"Your sodium intake is high ({int(sodium)} mg). "
            "Try to limit processed and salty foods."
        )

    # Goal-specific advice
    if dietary_goal == "diabetic":
        if carbs > (target * 0.45) / 4:
            suggestions.append(
                "For a diabetic diet, aim to keep carbohydrates under 40 % of calories. "
                "Swap refined carbs for non-starchy vegetables."
            )
    elif dietary_goal == "muscle_growth":
        if protein < 120:
            suggestions.append(
                "For muscle growth, target 1.6–2.2 g protein per kg body weight. "
                "Consider a protein shake or extra lean meat."
            )
    elif dietary_goal == "keto":
        if carbs > 50:
            suggestions.append(
                f"Your carb intake ({int(carbs)} g) may disrupt ketosis. "
                "Keep net carbs under 50 g."
            )

    # Vitamin deficiency nudge
    vitamin_status = check_vitamins(nutrients)
    deficient = [v for v in vitamin_status if v["status"] == "deficient"]
    if deficient:
        names = ", ".join(v["name"] for v in deficient[:2])
        suggestions.append(
            f"You're low on {names} today. "
            "Try adding foods rich in these nutrients."
        )

    if not suggestions:
        suggestions.append(
            "Great job! Your nutrition looks balanced today. Keep it up!"
        )

    return suggestions


def generate_grocery_list(weekly_totals: dict, dietary_goal: str) -> list[dict]:
    """Auto-generate a shopping list from weekly nutritional gaps."""
    grocery_items: list[dict] = []
    daily_averages = {k: v / 7 for k, v in weekly_totals.items()}

    priority_nutrients: list[str] = []

    for key, info in DAILY_VITAMIN_RDV.items():
        if daily_averages.get(key, 0) < info["rdv"] * 0.7:
            priority_nutrients.append(key)

    if dietary_goal == "muscle_growth" and daily_averages.get("protein", 0) < 150:
        priority_nutrients.append("protein")
    if daily_averages.get("fiber", 0) < 20:
        priority_nutrients.append("fiber")

    added: set[str] = set()
    for nutrient in priority_nutrients:
        for food in NUTRIENT_FOOD_MAP.get(nutrient, [])[:2]:
            if food not in added:
                rdv_info = DAILY_VITAMIN_RDV.get(nutrient, {})
                grocery_items.append({
                    "item": food.title(),
                    "reason": f"Rich in {rdv_info.get('name', nutrient)}",
                    "category": _FOOD_CATEGORY.get(food, "Pantry"),
                    "priority": "high" if len(priority_nutrients) > 3 else "medium",
                })
                added.add(food)

    # Goal-specific staples
    goal_staples: dict[str, list[dict]] = {
        "muscle_growth": [
            {"item": "Chicken Breast", "reason": "Lean protein source", "category": "Meat & Fish", "priority": "high"},
            {"item": "Greek Yogurt",   "reason": "High protein & gut health", "category": "Dairy", "priority": "high"},
        ],
        "diabetic": [
            {"item": "Quinoa",   "reason": "Low glycaemic index grain", "category": "Grains",      "priority": "high"},
            {"item": "Almonds",  "reason": "Healthy fats, blood-sugar control", "category": "Nuts & Seeds", "priority": "medium"},
        ],
        "keto": [
            {"item": "Avocados",    "reason": "Healthy fats for ketosis",  "category": "Produce", "priority": "high"},
            {"item": "Coconut Oil", "reason": "MCTs support ketosis",       "category": "Oils",   "priority": "medium"},
        ],
    }
    for item in goal_staples.get(dietary_goal, []):
        if item["item"].lower() not in added:
            grocery_items.append(item)
            added.add(item["item"].lower())

    return grocery_items


def get_streak_info(db: Session, user_id: int, today: date_type) -> dict:
    """Return current streak length and plant-growth metadata."""
    from app.models.db_models import DailyStreak

    start = today - timedelta(days=30)
    streaks = (
        db.query(DailyStreak)
        .filter(
            DailyStreak.user_id == user_id,
            DailyStreak.date >= start,
            DailyStreak.date <= today,
        )
        .all()
    )
    streak_map = {s.date: s.goal_met for s in streaks}

    current_streak = 0
    check = today
    while check >= start:
        if streak_map.get(check, False):
            current_streak += 1
            check -= timedelta(days=1)
        else:
            break

    plant_level  = min(10, current_streak)
    plant_health = (
        "thriving" if current_streak >= 5
        else "growing"  if current_streak >= 2
        else "wilting"  if current_streak == 0
        else "alive"
    )

    return {
        "current_streak": current_streak,
        "plant_level": plant_level,
        "plant_health": plant_health,
    }
