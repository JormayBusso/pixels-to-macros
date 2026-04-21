"""
volume_estimation.py
────────────────────
Estimates the volume (cm³) of each food item on the plate using:
  - Top view  → 2-D food footprint area
  - Side view → food height above the plate rim

Algorithm overview
──────────────────
1.  Detect the plate circle in the top-view image (HoughCircles).
    Use the known real-world plate diameter to calculate a pixel→cm scale.

2.  For each food item (provided as a fraction of the plate area from AI):
        food_area_cm² = plate_area_cm² × top_fraction

3.  In the side-view image, detect the plate rim and food peak heights:
        food_height_cm = plate_rim_height_px × height_ratio × scale_cm_per_px

4.  Volume approximation (accounts for non-cylindrical shape):
        volume_cm³ = food_area_cm² × food_height_cm × SHAPE_FACTOR

5.  Convert volume to estimated weight:
        weight_g = volume_cm³ × density_g_per_cm³

Fallback: if plate detection fails, the function uses an area-fraction estimate
based on the supplied plate_diameter_cm.
"""

import math
import numpy as np
import cv2

# Correction factor: food is rarely a perfect cylinder (typically 0.5–0.7)
SHAPE_FACTOR = 0.60

# ── Food density table (g / cm³) ─────────────────────────────────────────────
# Sources: USDA SR, food science literature
FOOD_DENSITY: dict[str, float] = {
    # Grains / starchy
    "rice": 1.00,
    "white rice": 1.00,
    "brown rice": 0.90,
    "pasta": 1.00,
    "noodles": 1.00,
    "spaghetti": 1.00,
    "potato": 0.95,
    "mashed potato": 0.85,
    "fries": 0.50,
    "bread": 0.30,
    "toast": 0.25,
    "oats": 0.40,
    "oatmeal": 0.85,
    "quinoa": 0.90,
    "couscous": 0.90,
    # Proteins
    "chicken": 0.70,
    "chicken breast": 0.70,
    "grilled chicken": 0.70,
    "beef": 0.80,
    "steak": 0.80,
    "pork": 0.80,
    "salmon": 0.90,
    "fish": 0.85,
    "tuna": 0.90,
    "shrimp": 0.90,
    "egg": 1.00,
    "scrambled egg": 0.90,
    "tofu": 1.05,
    # Vegetables
    "broccoli": 0.40,
    "cauliflower": 0.35,
    "spinach": 0.30,
    "salad": 0.20,
    "lettuce": 0.15,
    "carrot": 0.65,
    "tomato": 0.95,
    "cucumber": 0.95,
    "zucchini": 0.80,
    "pepper": 0.60,
    "corn": 0.80,
    "peas": 0.75,
    "beans": 0.80,
    # Dairy / sauces
    "cheese": 0.90,
    "yogurt": 1.05,
    "cream": 0.95,
    "sauce": 1.00,
    "gravy": 1.05,
    # Fruits
    "apple": 0.85,
    "banana": 0.95,
    "strawberry": 0.90,
    "blueberry": 0.85,
    "mango": 0.90,
    # Default
    "default": 0.80,
}


def _lookup_density(food_name: str) -> float:
    """Return density for a food name using keyword matching."""
    name_lower = food_name.lower()
    for key, density in FOOD_DENSITY.items():
        if key in name_lower:
            return density
    return FOOD_DENSITY["default"]


def _detect_plate_circle(image_bgr: np.ndarray) -> tuple[int, int, int] | None:
    """
    Attempt to detect the circular plate in the image.
    Returns (cx, cy, radius_px) or None if not found.
    """
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (15, 15), 0)

    height, width = gray.shape
    min_radius = int(min(height, width) * 0.25)
    max_radius = int(min(height, width) * 0.55)

    circles = cv2.HoughCircles(
        blurred,
        cv2.HOUGH_GRADIENT,
        dp=1.2,
        minDist=min(height, width) * 0.4,
        param1=60,
        param2=35,
        minRadius=min_radius,
        maxRadius=max_radius,
    )

    if circles is not None:
        circles = np.round(circles[0, :]).astype(int)
        # Take the largest detected circle (most likely the plate)
        best = max(circles, key=lambda c: c[2])
        return int(best[0]), int(best[1]), int(best[2])

    return None


def _measure_food_height_side(image_bgr: np.ndarray) -> float:
    """
    Estimate the food height in the side-view image as a fraction of image height.

    Strategy:
    - Find the lowest bright horizontal edge (plate surface / table top).
    - Find the highest point of significant content above background.
    - Return ratio: food_height_px / image_height_px
    """
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    height, width = gray.shape

    # Horizontal scan: find the row with the most edge energy (plate rim)
    edges = cv2.Canny(gray, 50, 150)

    # Sum horizontal edge pixels per row
    row_sum = np.sum(edges, axis=1)

    # The plate rim tends to be a strong horizontal line in the lower half
    lower_half = row_sum[height // 2 :]
    rim_row_local = int(np.argmax(lower_half))
    rim_row = rim_row_local + height // 2

    # Find the topmost row in the upper half that has content
    # Use threshold on brightness to detect food
    _, thresh = cv2.threshold(gray, 30, 255, cv2.THRESH_BINARY)
    upper_half = thresh[: height // 2, :]
    upper_row_sums = np.sum(upper_half, axis=1)
    nonzero_rows = np.where(upper_row_sums > width * 5)[0]

    if len(nonzero_rows) > 0:
        top_row = int(nonzero_rows[0])
    else:
        top_row = height // 4  # fallback

    food_height_px = rim_row - top_row
    food_height_fraction = max(0.05, min(food_height_px / height, 0.6))
    return food_height_fraction


def estimate_volumes(
    top_image_bytes: bytes,
    side_image_bytes: bytes,
    food_items: list[dict],
    plate_diameter_cm: float = 26.0,
) -> list[dict]:
    """
    Estimate volume and weight for each food item detected on the plate.

    Parameters
    ----------
    top_image_bytes   : raw bytes of the top-view image
    side_image_bytes  : raw bytes of the side-view image
    food_items        : list from ai_recognition.identify_foods()
    plate_diameter_cm : real-world plate diameter in cm (default 26 cm)

    Returns
    -------
    food_items with added keys:
      - estimated_weight_g (float)
      - volume_cm3         (float)
      - density_g_per_cm3  (float)
      - scale_method       (str)   – 'plate_detected' or 'fallback'
    """
    # Decode images
    top_arr = np.frombuffer(top_image_bytes, dtype=np.uint8)
    top_img = cv2.imdecode(top_arr, cv2.IMREAD_COLOR)

    side_arr = np.frombuffer(side_image_bytes, dtype=np.uint8)
    side_img = cv2.imdecode(side_arr, cv2.IMREAD_COLOR)

    plate_radius_cm = plate_diameter_cm / 2.0
    plate_area_cm2 = math.pi * plate_radius_cm ** 2

    # ── Step 1: detect plate in top view ─────────────────────────────────────
    scale_method = "fallback"
    scale_cm_per_px = None  # cm per pixel

    plate_circle = _detect_plate_circle(top_img)
    if plate_circle is not None:
        _, _, radius_px = plate_circle
        scale_cm_per_px = plate_radius_cm / radius_px
        scale_method = "plate_detected"

    # ── Step 2: measure food height from side view ────────────────────────────
    # Returns a baseline fraction of image height that represents the food zone
    side_height_fraction = _measure_food_height_side(side_img)

    # Convert side image height fraction to real cm
    img_height_px = side_img.shape[0]
    if scale_cm_per_px is not None:
        plate_rim_height_cm = plate_diameter_cm * 0.08  # typical rim ~8% of diameter
        food_base_height_cm = side_height_fraction * img_height_px * scale_cm_per_px
    else:
        # Fallback: assume food height is proportional to plate diameter
        food_base_height_cm = plate_diameter_cm * side_height_fraction * 0.5

    # ── Step 3: calculate volume & weight for each item ───────────────────────
    enriched: list[dict] = []
    for item in food_items:
        food_area_cm2 = plate_area_cm2 * item["top_fraction"]

        # Individual height scaled by the AI height_ratio
        food_height_cm = food_base_height_cm * item["height_ratio"]
        food_height_cm = max(0.3, min(food_height_cm, plate_diameter_cm * 0.5))

        volume_cm3 = food_area_cm2 * food_height_cm * SHAPE_FACTOR
        density = _lookup_density(item["name"])
        weight_g = round(volume_cm3 * density, 1)

        enriched.append(
            {
                **item,
                "estimated_weight_g": weight_g,
                "volume_cm3": round(volume_cm3, 2),
                "density_g_per_cm3": density,
                "scale_method": scale_method,
            }
        )

    return enriched
