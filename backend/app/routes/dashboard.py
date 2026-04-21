"""
dashboard.py
────────────
Daily summary and historical analytics endpoints.
"""

from datetime import date as date_type, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.db_models import User, FoodLog, LiquidLog, DailyStreak
from app.services.auth_service import get_current_user
from app.services.suggestions import generate_suggestions, check_vitamins, get_streak_info

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


def _get_default_calories(dietary_goal: Optional[str]) -> int:
    return {
        "balanced": 2000, "diabetic": 1800, "low_carb": 1600,
        "muscle_growth": 2800, "weight_loss": 1500, "vegan": 2000,
        "keto": 1800, "mediterranean": 2200,
    }.get(dietary_goal or "balanced", 2000)


def _aggregate_nutrients(food_logs: list[FoodLog]) -> dict:
    totals: dict = {}
    for log in food_logs:
        for key, val in log.nutrients.items():
            if isinstance(val, dict):
                v    = float(val.get("value", 0) or 0)
                unit = val.get("unit", "")
                if key not in totals:
                    totals[key] = {"value": 0.0, "unit": unit}
                totals[key]["value"] += v
            elif isinstance(val, (int, float)):
                if key not in totals:
                    totals[key] = {"value": 0.0, "unit": ""}
                totals[key]["value"] += float(val)
    return totals


@router.get("/summary/{summary_date}")
def get_daily_summary(
    summary_date: date_type,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    food_logs = (
        db.query(FoodLog)
        .filter(FoodLog.user_id == current_user.id, FoodLog.date == summary_date)
        .all()
    )
    liquid_logs = (
        db.query(LiquidLog)
        .filter(LiquidLog.user_id == current_user.id, LiquidLog.date == summary_date)
        .all()
    )

    nutrients = _aggregate_nutrients(food_logs)

    total_water_ml  = sum(l.amount_ml for l in liquid_logs if "water" in l.liquid_type)
    total_liquid_ml = sum(l.amount_ml for l in liquid_logs)

    vitamin_status = check_vitamins(nutrients)
    suggestions    = generate_suggestions(
        nutrients=nutrients,
        dietary_goal=current_user.dietary_goal or "balanced",
        caloric_target=current_user.caloric_target,
    )

    caloric_target   = current_user.caloric_target or _get_default_calories(current_user.dietary_goal)
    current_calories = nutrients.get("calories", {}).get("value", 0)
    goal_met = (
        abs(current_calories - caloric_target) / caloric_target < 0.15
        if caloric_target else False
    )

    # Upsert streak record
    streak_record = (
        db.query(DailyStreak)
        .filter(DailyStreak.user_id == current_user.id, DailyStreak.date == summary_date)
        .first()
    )
    if not streak_record:
        streak_record = DailyStreak(
            user_id=current_user.id, date=summary_date, goal_met=goal_met
        )
        db.add(streak_record)
    else:
        streak_record.goal_met = goal_met
    db.commit()

    streak_info = get_streak_info(db, current_user.id, summary_date)

    return {
        "date": summary_date,
        "food_logs": [
            {
                "id": log.id,
                "food_name": log.food_name,
                "matched_food": log.matched_food,
                "weight_g": log.weight_g,
                "meal_type": log.meal_type,
                "nutrients": log.nutrients,
            }
            for log in food_logs
        ],
        "liquid_logs": [
            {"id": l.id, "liquid_type": l.liquid_type, "amount_ml": l.amount_ml}
            for l in liquid_logs
        ],
        "totals": nutrients,
        "total_water_ml": total_water_ml,
        "total_liquid_ml": total_liquid_ml,
        "vitamin_status": vitamin_status,
        "suggestions": suggestions,
        "goal_met": goal_met,
        "caloric_target": caloric_target,
        "streak": streak_info,
    }


@router.get("/history")
def get_history(
    days: int = Query(default=30, ge=1, le=365),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    end_date   = date_type.today()
    start_date = end_date - timedelta(days=days - 1)

    food_logs = (
        db.query(FoodLog)
        .filter(
            FoodLog.user_id == current_user.id,
            FoodLog.date >= start_date,
            FoodLog.date <= end_date,
        )
        .all()
    )

    by_date: dict[str, dict] = {}
    for log in food_logs:
        d = str(log.date)
        if d not in by_date:
            by_date[d] = {"calories": 0.0, "protein": 0.0, "carbohydrates": 0.0, "fat": 0.0}
        for macro in ("calories", "protein", "carbohydrates", "fat"):
            val = log.nutrients.get(macro, {})
            by_date[d][macro] += (
                float(val.get("value", 0)) if isinstance(val, dict) else float(val or 0)
            )

    streaks = (
        db.query(DailyStreak)
        .filter(
            DailyStreak.user_id == current_user.id,
            DailyStreak.date >= start_date,
            DailyStreak.date <= end_date,
        )
        .all()
    )
    streak_map = {str(s.date): s.goal_met for s in streaks}

    result = []
    current = start_date
    while current <= end_date:
        d = str(current)
        entry = {"date": d, **by_date.get(d, {"calories": 0, "protein": 0, "carbohydrates": 0, "fat": 0})}
        entry["goal_met"] = streak_map.get(d, False)
        result.append(entry)
        current += timedelta(days=1)

    return {"history": result, "period_days": days}
