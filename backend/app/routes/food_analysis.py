"""
food_analysis.py
────────────────
Main API routes:
  POST /api/analyze          – analyse two plate images end-to-end
  POST /api/recalculate      – recalculate nutrition after user edits
"""

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from app.models.schemas import AnalysisResponse, RecalculateRequest
from app.services.ai_recognition import identify_foods
from app.services.volume_estimation import estimate_volumes
from app.services.nutrition_calculator import calculate_nutrition, recalculate_item

router = APIRouter()

MAX_IMAGE_SIZE = 10 * 1024 * 1024  # 10 MB
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp", "image/heic"}


def _validate_image(upload: UploadFile, field_name: str) -> None:
    if upload.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"{field_name}: unsupported file type '{upload.content_type}'. "
                   "Please upload JPEG, PNG, or WebP.",
        )


@router.post("/analyze", response_model=AnalysisResponse)
async def analyze_plate(
    top_image: UploadFile = File(..., description="Top-down photo of the plate"),
    side_image: UploadFile = File(..., description="Side-view photo of the plate"),
    plate_diameter_cm: float = Form(26.0, ge=10, le=50, description="Real plate diameter in cm"),
):
    """
    Full analysis pipeline:
    1. Read both uploaded images
    2. AI recognition  → list of foods with area/height fractions
    3. Volume estimation → estimated weight per food item
    4. Nutrition lookup → scaled nutrient values
    """
    _validate_image(top_image, "top_image")
    _validate_image(side_image, "side_image")

    top_bytes = await top_image.read()
    side_bytes = await side_image.read()

    if len(top_bytes) > MAX_IMAGE_SIZE or len(side_bytes) > MAX_IMAGE_SIZE:
        raise HTTPException(status_code=413, detail="Image file too large. Maximum size is 10 MB.")

    try:
        # Step 1: Identify foods using GPT-4o Vision
        foods = identify_foods(top_bytes, side_bytes)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"AI recognition failed: {exc}") from exc

    try:
        # Step 2: Estimate volumes and weights
        foods_with_volume = estimate_volumes(top_bytes, side_bytes, foods, plate_diameter_cm)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Volume estimation failed: {exc}") from exc

    try:
        # Step 3: Calculate nutrition
        nutrition = calculate_nutrition(foods_with_volume)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Nutrition lookup failed: {exc}") from exc

    return AnalysisResponse(
        items=nutrition["items"],
        totals=nutrition["totals"],
        plate_diameter_cm=plate_diameter_cm,
    )


@router.post("/recalculate", response_model=AnalysisResponse)
async def recalculate_nutrition(body: RecalculateRequest):
    """
    Re-fetch and re-sum nutrition data after the user manually edits
    food names or weights.
    """
    items_result = []
    for adj in body.items:
        try:
            item_data = recalculate_item(adj.name, adj.weight_g)
            items_result.append(item_data)
        except Exception as exc:
            raise HTTPException(
                status_code=502, detail=f"Nutrition lookup failed for '{adj.name}': {exc}"
            ) from exc

    # Aggregate totals
    from app.services.nutrition_calculator import NUTRIENT_IDS, NUTRIENT_UNITS
    totals: dict[str, float] = {k: 0.0 for k in NUTRIENT_IDS}
    for item in items_result:
        for key in NUTRIENT_IDS:
            totals[key] += item["nutrients"][key]["value"]

    totals_formatted = {
        k: {"value": round(v, 2), "unit": NUTRIENT_UNITS[k]} for k, v in totals.items()
    }

    return AnalysisResponse(
        items=items_result,
        totals=totals_formatted,
        plate_diameter_cm=26.0,
        message="Recalculation complete",
    )
