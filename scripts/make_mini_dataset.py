"""
scripts/make_mini_dataset.py
----------------------------
Generates a tiny synthetic FoodSeg103-compatible dataset so you can
verify the training pipeline runs correctly before downloading the
full 5 GB dataset.

Creates:
    data/FoodSeg103_mini/
        Images/          200 tiny RGB images (100x100 px)
        Masks/           200 matching segmentation masks
        category_id.txt  10 food class labels

Usage (from repo root):
    python scripts/make_mini_dataset.py
    python training/train.py --data_dir ./data/FoodSeg103_mini --epochs 2 --batch_size 2 --img_size 128
"""

from __future__ import annotations

import random
from pathlib import Path

import numpy as np
from PIL import Image

# ── Config ────────────────────────────────────────────────────────────────────
OUTPUT_DIR  = Path("data/FoodSeg103_mini")
N_IMAGES    = 200
IMG_SIZE    = 100   # pixels — tiny so generation is instant
NUM_CLASSES = 10    # background (0) + 9 food classes

LABELS = {
    0: "background",
    1: "apple",
    2: "rice",
    3: "chicken",
    4: "bread",
    5: "salad",
    6: "pasta",
    7: "egg",
    8: "fish",
    9: "potato",
}

# Each class gets a rough representative colour (for visual debugging)
CLASS_COLOURS = [
    (200, 200, 200),  # background – grey
    (220,  60,  60),  # apple      – red
    (240, 230, 140),  # rice       – pale yellow
    (180, 120,  60),  # chicken    – brown
    (210, 170,  90),  # bread      – tan
    (80,  180,  80),  # salad      – green
    (240, 200, 100),  # pasta      – golden
    (255, 240, 180),  # egg        – cream
    (60,  120, 200),  # fish       – blue-ish
    (180, 120,  80),  # potato     – light brown
]


def make_image_and_mask(rng: random.Random) -> tuple[np.ndarray, np.ndarray]:
    """Return (H,W,3) uint8 image and (H,W) int64 mask with 1-4 random food blobs."""
    img  = np.full((IMG_SIZE, IMG_SIZE, 3), 200, dtype=np.uint8)
    mask = np.zeros((IMG_SIZE, IMG_SIZE), dtype=np.int64)

    n_blobs = rng.randint(1, 4)
    for _ in range(n_blobs):
        cls   = rng.randint(1, NUM_CLASSES - 1)
        cx    = rng.randint(10, IMG_SIZE - 10)
        cy    = rng.randint(10, IMG_SIZE - 10)
        rx    = rng.randint(5, 20)
        ry    = rng.randint(5, 20)
        colour = CLASS_COLOURS[cls]

        ys, xs = np.ogrid[:IMG_SIZE, :IMG_SIZE]
        ellipse = ((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2 <= 1

        img[ellipse]  = colour
        mask[ellipse] = cls

    return img, mask


def main() -> None:
    rng = random.Random(42)

    images_dir = OUTPUT_DIR / "Images"
    masks_dir  = OUTPUT_DIR / "Masks"
    images_dir.mkdir(parents=True, exist_ok=True)
    masks_dir.mkdir(parents=True, exist_ok=True)

    for i in range(1, N_IMAGES + 1):
        name = f"img_{i:05d}"
        img_arr, mask_arr = make_image_and_mask(rng)

        Image.fromarray(img_arr, "RGB").save(images_dir / f"{name}.jpg")
        Image.fromarray(mask_arr.astype(np.uint8), "L").save(masks_dir / f"{name}.png")

        if i % 50 == 0:
            print(f"  Generated {i}/{N_IMAGES}")

    # Write category file
    label_file = OUTPUT_DIR / "category_id.txt"
    with open(label_file, "w") as f:
        for idx, name in LABELS.items():
            f.write(f"{idx} {name}\n")

    print(f"\nDone! Mini dataset written to: {OUTPUT_DIR.resolve()}")
    print(f"  {N_IMAGES} images / {N_IMAGES} masks / {NUM_CLASSES} classes")
    print()
    print("Next step — run a quick training sanity check:")
    print("  python training/train.py \\")
    print("      --data_dir ./data/FoodSeg103_mini \\")
    print("      --epochs 2 --batch_size 2 --img_size 128")


if __name__ == "__main__":
    main()
