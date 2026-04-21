"""
barcode.py
──────────
Barcode product lookup via the OpenFoodFacts public API.
"""

import httpx
from fastapi import APIRouter, Depends, HTTPException

from app.models.db_models import User
from app.services.auth_service import get_current_user

router = APIRouter(prefix="/barcode", tags=["barcode"])

_OFF_URL = "https://world.openfoodfacts.org/api/v0/product/{barcode}.json"


def _safe_float(value) -> float:
    try:
        return float(value or 0)
    except (ValueError, TypeError):
        return 0.0


@router.get("/{barcode}")
async def lookup_barcode(
    barcode: str,
    _: User = Depends(get_current_user),
):
    # Basic barcode validation (EAN-8, UPC-A/EAN-13, EAN-14)
    if not barcode.isdigit() or len(barcode) not in (8, 12, 13, 14):
        raise HTTPException(status_code=422, detail="Invalid barcode format")

    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(
                _OFF_URL.format(barcode=barcode),
                headers={"User-Agent": "NutriLens/1.0 (food-tracking; contact@nutrilens.app)"},
            )
            resp.raise_for_status()
        except httpx.RequestError as exc:
            raise HTTPException(status_code=502, detail=f"OpenFoodFacts request failed: {exc}")

    data = resp.json()
    if data.get("status") != 1:
        raise HTTPException(status_code=404, detail="Product not found in OpenFoodFacts database")

    product    = data.get("product", {})
    nutriments = product.get("nutriments", {})

    return {
        "barcode": barcode,
        "product_name": product.get("product_name", "Unknown"),
        "brand":        product.get("brands", ""),
        "serving_size_g": _safe_float(product.get("serving_size")),
        "nutrients_per_100g": {
            "calories":      _safe_float(nutriments.get("energy-kcal_100g")),
            "protein":       _safe_float(nutriments.get("proteins_100g")),
            "carbohydrates": _safe_float(nutriments.get("carbohydrates_100g")),
            "fat":           _safe_float(nutriments.get("fat_100g")),
            "fiber":         _safe_float(nutriments.get("fiber_100g")),
            "sugars":        _safe_float(nutriments.get("sugars_100g")),
            "sodium":        _safe_float(nutriments.get("sodium_100g", 0)) * 1000,
            "saturated_fat": _safe_float(nutriments.get("saturated-fat_100g")),
        },
        "image_url": product.get("image_url", ""),
    }
