"""
grocery.py
──────────
Auto-generate a weekly grocery list from nutritional gaps.
"""

from datetime import date as date_type, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.db_models import User, FoodLog
from app.services.auth_service import get_current_user
from app.services.suggestions import generate_grocery_list

router = APIRouter(prefix="/grocery", tags=["grocery"])


@router.get("/list")
def get_grocery_list(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    end_date   = date_type.today()
    start_date = end_date - timedelta(days=6)

    food_logs = (
        db.query(FoodLog)
        .filter(
            FoodLog.user_id == current_user.id,
            FoodLog.date >= start_date,
            FoodLog.date <= end_date,
        )
        .all()
    )

    weekly_totals: dict[str, float] = {}
    for log in food_logs:
        for key, val in log.nutrients.items():
            v = float(val.get("value", 0)) if isinstance(val, dict) else float(val or 0)
            weekly_totals[key] = weekly_totals.get(key, 0.0) + v

    grocery_list = generate_grocery_list(
        weekly_totals=weekly_totals,
        dietary_goal=current_user.dietary_goal or "balanced",
    )

    return {
        "period": {"start": str(start_date), "end": str(end_date)},
        "grocery_list": grocery_list,
    }
