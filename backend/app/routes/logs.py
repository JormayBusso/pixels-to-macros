"""
logs.py
───────
Food and liquid logging endpoints.
"""

import json
from datetime import date as date_type, datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field, field_validator

from app.database import get_db
from app.models.db_models import User, FoodLog, LiquidLog
from app.services.auth_service import get_current_user
from app.services.nutrition_calculator import recalculate_item

router = APIRouter(prefix="/logs", tags=["logs"])

VALID_MEAL_TYPES   = {"breakfast", "lunch", "dinner", "snack", "other"}
VALID_LIQUID_TYPES = {
    "water", "coffee", "tea", "juice", "soda",
    "milk", "smoothie", "sports_drink", "other",
}


# ── Schemas ───────────────────────────────────────────────────────────────────

class AddFoodLogRequest(BaseModel):
    date: date_type      = Field(default_factory=date_type.today)
    food_name: str       = Field(..., min_length=1, max_length=200)
    weight_g: float      = Field(..., gt=0, le=10_000)
    meal_type: str       = Field(default="other")
    nutrients: Optional[dict] = None   # pre-computed by AI analysis

    @field_validator("meal_type")
    @classmethod
    def check_meal_type(cls, v: str) -> str:
        if v not in VALID_MEAL_TYPES:
            raise ValueError(f"meal_type must be one of: {', '.join(sorted(VALID_MEAL_TYPES))}")
        return v


class UpdateFoodLogRequest(BaseModel):
    food_name: Optional[str]   = Field(None, min_length=1, max_length=200)
    weight_g:  Optional[float] = Field(None, gt=0, le=10_000)
    meal_type: Optional[str]   = None


class AddLiquidLogRequest(BaseModel):
    date: date_type  = Field(default_factory=date_type.today)
    liquid_type: str
    amount_ml: float = Field(..., gt=0, le=10_000)

    @field_validator("liquid_type")
    @classmethod
    def check_liquid_type(cls, v: str) -> str:
        return v.lower()


class FoodLogResponse(BaseModel):
    id: int
    date: date_type
    food_name: str
    matched_food: Optional[str]
    fdc_id: Optional[int]
    weight_g: float
    meal_type: str
    nutrients: dict

    model_config = {"from_attributes": True}


class LiquidLogResponse(BaseModel):
    id: int
    date: date_type
    liquid_type: str
    amount_ml: float
    created_at: datetime

    model_config = {"from_attributes": True}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _food_log_to_response(log: FoodLog) -> FoodLogResponse:
    return FoodLogResponse(
        id=log.id,
        date=log.date,
        food_name=log.food_name,
        matched_food=log.matched_food,
        fdc_id=log.fdc_id,
        weight_g=log.weight_g,
        meal_type=log.meal_type,
        nutrients=log.nutrients,
    )


# ── Food endpoints ────────────────────────────────────────────────────────────

@router.get("/food/{log_date}", response_model=list[FoodLogResponse])
def get_food_logs(
    log_date: date_type,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    logs = (
        db.query(FoodLog)
        .filter(FoodLog.user_id == current_user.id, FoodLog.date == log_date)
        .all()
    )
    return [_food_log_to_response(log) for log in logs]


@router.post("/food", response_model=FoodLogResponse, status_code=201)
def add_food_log(
    body: AddFoodLogRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    nutrients   = body.nutrients
    matched_food = body.food_name
    fdc_id      = None

    if not nutrients:
        try:
            item_data    = recalculate_item(body.food_name, body.weight_g)
            nutrients    = item_data["nutrients"]
            matched_food = item_data.get("matched_food", body.food_name)
            fdc_id       = item_data.get("fdc_id")
        except Exception:
            nutrients = {}

    log = FoodLog(
        user_id=current_user.id,
        date=body.date,
        food_name=body.food_name,
        matched_food=matched_food,
        fdc_id=fdc_id,
        weight_g=body.weight_g,
        meal_type=body.meal_type,
        nutrients_json=json.dumps(nutrients),
    )
    db.add(log)
    db.commit()
    db.refresh(log)
    return _food_log_to_response(log)


@router.put("/food/{log_id}", response_model=FoodLogResponse)
def update_food_log(
    log_id: int,
    body: UpdateFoodLogRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    log = (
        db.query(FoodLog)
        .filter(FoodLog.id == log_id, FoodLog.user_id == current_user.id)
        .first()
    )
    if not log:
        raise HTTPException(status_code=404, detail="Food log not found")

    changed = False
    if body.food_name is not None:
        log.food_name = body.food_name
        changed = True
    if body.weight_g is not None:
        log.weight_g = body.weight_g
        changed = True
    if body.meal_type is not None:
        if body.meal_type not in VALID_MEAL_TYPES:
            raise HTTPException(status_code=422, detail="Invalid meal_type")
        log.meal_type = body.meal_type

    if changed:
        try:
            item_data = recalculate_item(log.food_name, log.weight_g)
            log.nutrients_json = json.dumps(item_data["nutrients"])
            log.matched_food   = item_data.get("matched_food", log.food_name)
            log.fdc_id         = item_data.get("fdc_id")
        except Exception:
            pass  # keep existing nutrients if lookup fails

    db.commit()
    db.refresh(log)
    return _food_log_to_response(log)


@router.delete("/food/{log_id}", status_code=204)
def delete_food_log(
    log_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    log = (
        db.query(FoodLog)
        .filter(FoodLog.id == log_id, FoodLog.user_id == current_user.id)
        .first()
    )
    if not log:
        raise HTTPException(status_code=404, detail="Food log not found")
    db.delete(log)
    db.commit()


# ── Liquid endpoints ──────────────────────────────────────────────────────────

@router.get("/liquid/{log_date}", response_model=list[LiquidLogResponse])
def get_liquid_logs(
    log_date: date_type,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return (
        db.query(LiquidLog)
        .filter(LiquidLog.user_id == current_user.id, LiquidLog.date == log_date)
        .all()
    )


@router.post("/liquid", response_model=LiquidLogResponse, status_code=201)
def add_liquid_log(
    body: AddLiquidLogRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    log = LiquidLog(
        user_id=current_user.id,
        date=body.date,
        liquid_type=body.liquid_type,
        amount_ml=body.amount_ml,
    )
    db.add(log)
    db.commit()
    db.refresh(log)
    return log


@router.delete("/liquid/{log_id}", status_code=204)
def delete_liquid_log(
    log_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    log = (
        db.query(LiquidLog)
        .filter(LiquidLog.id == log_id, LiquidLog.user_id == current_user.id)
        .first()
    )
    if not log:
        raise HTTPException(status_code=404, detail="Liquid log not found")
    db.delete(log)
    db.commit()
