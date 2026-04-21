"""
schemas.py
──────────
Pydantic models for request and response validation.
"""

from pydantic import BaseModel, Field


# ── Request models ────────────────────────────────────────────────────────────

class AdjustedFoodItem(BaseModel):
    name: str = Field(..., description="Food name for USDA lookup")
    weight_g: float = Field(..., gt=0, description="Weight in grams (user-provided or estimated)")


class RecalculateRequest(BaseModel):
    items: list[AdjustedFoodItem]


# ── Response models ───────────────────────────────────────────────────────────

class NutrientValue(BaseModel):
    value: float
    unit: str


class FoodItemResult(BaseModel):
    name: str
    weight_g: float
    matched_food: str
    fdc_id: int | None = None
    nutrients: dict[str, NutrientValue]
    volume_cm3: float | None = None
    confidence: float | None = None
    scale_method: str | None = None


class AnalysisResponse(BaseModel):
    items: list[FoodItemResult]
    totals: dict[str, NutrientValue]
    plate_diameter_cm: float
    message: str = "Analysis complete"
