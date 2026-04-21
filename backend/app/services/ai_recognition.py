"""
ai_recognition.py
─────────────────
Uses Groq Vision (Llama 4 Scout) to identify food items from two plate images.

Returns a list of recognised foods with:
  - name          (str)  – food item name
  - top_fraction  (float)– estimated fraction of plate area occupied (0-1)
  - height_ratio  (float)– estimated height relative to plate rim (0-1)
  - confidence    (float)– model confidence (0-1)
"""

import base64
import json
import os
import re

from groq import Groq

_client: Groq | None = None


def _get_client() -> Groq:
    global _client
    if _client is None:
        api_key = os.getenv("GROQ_API_KEY")
        if not api_key:
            raise EnvironmentError("GROQ_API_KEY is not set in the environment.")
        _client = Groq(api_key=api_key)
    return _client


def _encode_image(image_bytes: bytes) -> str:
    """Encode raw image bytes to base64 string for the API."""
    return base64.standard_b64encode(image_bytes).decode("utf-8")


SYSTEM_PROMPT = """You are a professional nutritionist and food recognition AI.
You will receive two images of the same plate of food:
  1. TOP VIEW  – photo taken directly from above
  2. SIDE VIEW – photo taken from the side at roughly plate-rim height

Your task: identify every distinct food item on the plate.

For each food item provide:
- "name": a specific food name suitable for a nutrition database lookup (e.g. "cooked white rice", "grilled chicken breast", "steamed broccoli")
- "top_fraction": estimated fraction of the total plate area this food occupies in the top view (all fractions must sum to ≤ 1.0)
- "height_ratio": estimated height of this food relative to the plate rim height (1.0 = same height as rim, 2.0 = twice the rim height)
- "confidence": your confidence in this identification (0.0 – 1.0)

Return ONLY a valid JSON array with no extra text. Example:
[
  {"name": "cooked white rice", "top_fraction": 0.45, "height_ratio": 0.8, "confidence": 0.92},
  {"name": "grilled chicken breast", "top_fraction": 0.35, "height_ratio": 1.2, "confidence": 0.88},
  {"name": "steamed broccoli", "top_fraction": 0.20, "height_ratio": 0.9, "confidence": 0.85}
]"""


def identify_foods(top_image_bytes: bytes, side_image_bytes: bytes) -> list[dict]:
    """
    Call GPT-4o Vision with both plate images and return identified food items.

    Parameters
    ----------
    top_image_bytes  : raw bytes of the top-view image
    side_image_bytes : raw bytes of the side-view image

    Returns
    -------
    list of dicts with keys: name, top_fraction, height_ratio, confidence
    """
    client = _get_client()

    top_b64 = _encode_image(top_image_bytes)
    side_b64 = _encode_image(side_image_bytes)

    response = client.chat.completions.create(
        model="meta-llama/llama-4-scout-17b-16e-instruct",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Image 1 – TOP VIEW:"},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{top_b64}", "detail": "high"},
                    },
                    {"type": "text", "text": "Image 2 – SIDE VIEW:"},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{side_b64}", "detail": "high"},
                    },
                    {
                        "type": "text",
                        "text": (
                            "Identify all food items on this plate. "
                            "Return ONLY a valid JSON array as described."
                        ),
                    },
                ],
            },
        ],
        max_tokens=800,
        temperature=0.2,
    )

    raw = response.choices[0].message.content.strip()

    # Strip markdown code fences if the model wrapped its answer
    raw = re.sub(r"^```(?:json)?\s*", "", raw)
    raw = re.sub(r"\s*```$", "", raw)

    try:
        foods = json.loads(raw)
    except json.JSONDecodeError:
        # Attempt to extract first JSON array from the string
        match = re.search(r"\[.*\]", raw, re.DOTALL)
        if match:
            foods = json.loads(match.group())
        else:
            raise ValueError(f"Could not parse AI response as JSON:\n{raw}")

    # Validate and normalise each entry
    validated: list[dict] = []
    for item in foods:
        validated.append(
            {
                "name": str(item.get("name", "unknown food")),
                "top_fraction": float(item.get("top_fraction", 0.1)),
                "height_ratio": float(item.get("height_ratio", 1.0)),
                "confidence": float(item.get("confidence", 0.5)),
            }
        )

    return validated
