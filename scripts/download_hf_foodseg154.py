"""
Download and normalize FoodSeg154 into the layout expected by training/train.py.

The script first tries FOODSEG154_HF_DATASET if set, then a short list of
known public Hugging Face dataset IDs. If none are available in the current
environment, add FoodSeg154 as a Kaggle input dataset and point DATA_DIR at it
in the Kaggle training cell.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from typing import Any

DATASET_DIR = Path("data/FoodSeg154")
CANDIDATE_DATASETS = tuple(
    value
    for value in (
        os.environ.get("FOODSEG154_HF_DATASET"),
        "nateraw/foodseg154",
        "segments-ai/foodseg154",
        "FoodSeg154/FoodSeg154",
    )
    if value
)


def ensure_packages() -> None:
    for package, import_name in (("datasets", "datasets"), ("Pillow", "PIL")):
        try:
            __import__(import_name)
        except ImportError:
            subprocess.check_call([sys.executable, "-m", "pip", "install", package, "--quiet"])


def first_present(row: dict[str, Any], names: tuple[str, ...]) -> Any:
    for name in names:
        value = row.get(name)
        if value is not None:
            return value
    return None


def as_image(value: Any, *, mask: bool) -> Image.Image:
    from PIL import Image  # noqa: PLC0415

    if isinstance(value, Image.Image):
        image = value
    elif isinstance(value, dict) and "path" in value:
        image = Image.open(value["path"])
    else:
        image = Image.fromarray(value)
    return image.convert("L" if mask else "RGB")


def convert_split(ds_split, split_name: str) -> None:
    img_dir = DATASET_DIR / "Images" / "img_dir" / split_name
    ann_dir = DATASET_DIR / "Annotations" / "ann_dir" / split_name
    img_dir.mkdir(parents=True, exist_ok=True)
    ann_dir.mkdir(parents=True, exist_ok=True)

    total = len(ds_split)
    print(f"[{split_name}] saving {total} pairs")
    for index, row in enumerate(ds_split):
        image_value = first_present(row, ("image", "img", "rgb", "pixel_values"))
        mask_value = first_present(row, ("label", "mask", "annotation", "segmentation", "semantic_mask"))
        if image_value is None or mask_value is None:
            raise KeyError(f"Could not find image/mask columns. Available columns: {list(row.keys())}")

        name = f"{index:06d}"
        as_image(image_value, mask=False).save(img_dir / f"{name}.jpg", "JPEG", quality=95)
        as_image(mask_value, mask=True).save(ann_dir / f"{name}.png")

        if (index + 1) % 500 == 0 or (index + 1) == total:
            print(f"  {index + 1}/{total}")


def write_default_categories() -> None:
    lines = ["0 background", *[f"{idx} food_{idx:03d}" for idx in range(1, 155)]]
    (DATASET_DIR / "category_id.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    ensure_packages()
    from datasets import load_dataset  # noqa: PLC0415

    train_dir = DATASET_DIR / "Images" / "img_dir" / "train"
    if train_dir.exists() and len(list(train_dir.glob("*.jpg"))) > 1000:
        print(f"FoodSeg154 already present at {DATASET_DIR}")
        return 0

    last_error: Exception | None = None
    dataset = None
    dataset_id = ""
    for candidate in CANDIDATE_DATASETS:
        try:
            print(f"Trying Hugging Face dataset: {candidate}")
            dataset = load_dataset(candidate)
            dataset_id = candidate
            break
        except Exception as exc:  # pragma: no cover - network/catalog dependent
            last_error = exc
            print(f"  unavailable: {exc}")

    if dataset is None:
        print("Could not download FoodSeg154 from the configured Hugging Face candidates.")
        print("Set FOODSEG154_HF_DATASET to a valid dataset ID or add FoodSeg154 as a Kaggle input.")
        if last_error is not None:
            print(f"Last error: {last_error}")
        return 1

    DATASET_DIR.mkdir(parents=True, exist_ok=True)
    split_map = {
        "train": "train",
        "training": "train",
        "validation": "val",
        "valid": "val",
        "val": "val",
        "test": "val",
    }
    written = set()
    for source_split, target_split in split_map.items():
        if source_split in dataset and target_split not in written:
            convert_split(dataset[source_split], target_split)
            written.add(target_split)

    if "train" not in written:
        raise RuntimeError(f"Dataset {dataset_id} has no train-like split: {list(dataset.keys())}")
    if "val" not in written:
        print("No validation split found; training/train.py will create an internal validation split if needed.")

    write_default_categories()
    print(f"FoodSeg154 ready at {DATASET_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())