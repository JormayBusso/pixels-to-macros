"""
Convert FoodSeg103 / FoodSeg154 semantic-segmentation masks into the
Ultralytics YOLO instance-segmentation format (polygons), so the dataset can
train a YOLOv8-seg / YOLO11-seg model that exports cleanly to Core ML.

Why this exists
---------------
The original pipeline trains SegFormer (dense per-pixel semantic masks). For a
real-time, offline iOS app a YOLO*-seg model is lighter, converges much faster
from COCO-pretrained weights, and has first-class Core ML export
(`yolo export format=coreml nms=True`). YOLO needs per-instance polygons, which
this script derives from the semantic masks via connected-component contours.

Supported input layouts (auto-detected, mirrors training/dataset.py)
  Layout A — official FoodSeg:
      <data>/Images/img_dir/{train,test}/*.jpg
      <data>/Annotations/ann_dir/{train,test}/*.png
      <data>/category_id.txt
  Layout B — flat / mini:
      <data>/Images/*.jpg
      <data>/Masks/*.png
      <data>/category_id.txt   (optional)

Output (Ultralytics layout)
  <out>/images/{train,val}/*.jpg
  <out>/labels/{train,val}/*.txt    # "<cls> x1 y1 x2 y2 ..." normalised 0-1
  <out>/data.yaml

Class indexing
  FoodSeg mask value 0 = background (dropped). Food ids 1..N map to YOLO class
  ids 0..N-1, so YOLO class = foodseg_id - 1.

Example
  python training/foodseg_to_yolo.py \
      --data-dir ./data/FoodSeg103 \
      --output-dir ./data/FoodSeg103_yolo \
      --val-frac 0.15
"""

from __future__ import annotations

import argparse
import os
import random
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".webp")
MASK_EXTS = (".png", ".tif", ".tiff", ".jpg", ".jpeg")


def read_labels(data_dir: Path) -> dict[int, str]:
    """Parse category_id.txt -> {id: name}. Tolerates "id name" or "name"."""
    id2label: dict[int, str] = {0: "background"}
    for name in ("category_id.txt", "categories.txt", "classes.txt", "labels.txt"):
        path = data_dir / name
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(None, 1)
            if len(parts) == 2 and parts[0].isdigit():
                id2label[int(parts[0])] = parts[1].strip()
            else:
                id2label[len(id2label)] = line
        break
    return id2label


def load_mask(path: Path) -> np.ndarray:
    """Load a class-index mask as a 2-D uint array (palette indices preserved)."""
    arr = np.array(Image.open(path))
    if arr.ndim == 3:
        # Unexpected RGB mask: collapse to the first channel.
        arr = arr[:, :, 0]
    return arr


def find_image_for_mask(mask_path: Path, image_dir: Path) -> Path | None:
    for ext in IMAGE_EXTS:
        candidate = image_dir / mask_path.with_suffix(ext).name
        if candidate.exists():
            return candidate
    return None


def collect_pairs(data_dir: Path) -> tuple[list[tuple[Path, Path]], list[tuple[Path, Path]]]:
    """Return (train_pairs, val_source_pairs). val_source may be empty."""
    official_img = data_dir / "Images" / "img_dir"
    if (official_img / "train").exists():
        train_pairs = _pairs(
            official_img / "train",
            data_dir / "Annotations" / "ann_dir" / "train",
        )
        test_pairs = _pairs(
            official_img / "test",
            data_dir / "Annotations" / "ann_dir" / "test",
        )
        return train_pairs, test_pairs

    flat_img = data_dir / "Images"
    flat_mask = data_dir / "Masks"
    if flat_img.exists() and flat_mask.exists():
        return _pairs(flat_img, flat_mask), []

    raise FileNotFoundError(
        f"No FoodSeg dataset found at {data_dir}. Expected Images/img_dir/train "
        "or Images/ + Masks/."
    )


def _pairs(image_dir: Path, mask_dir: Path) -> list[tuple[Path, Path]]:
    pairs: list[tuple[Path, Path]] = []
    if not mask_dir.exists():
        return pairs
    masks: dict[str, Path] = {}
    for ext in MASK_EXTS:
        for m in mask_dir.rglob(f"*{ext}"):
            masks.setdefault(m.stem, m)
    for stem, mask_path in sorted(masks.items()):
        image_path = find_image_for_mask(mask_path, image_dir)
        if image_path is not None:
            pairs.append((image_path, mask_path))
    return pairs


def mask_to_polygons(
    mask: np.ndarray,
    min_area_frac: float,
    epsilon_frac: float,
) -> list[tuple[int, list[float]]]:
    """Turn a class-index mask into [(yolo_class, [x1,y1,...normalised])]."""
    height, width = mask.shape[:2]
    image_area = float(height * width)
    min_area = max(16.0, min_area_frac * image_area)
    results: list[tuple[int, list[float]]] = []

    for class_id in np.unique(mask):
        if class_id <= 0:  # background / ignore
            continue
        binary = (mask == class_id).astype(np.uint8)
        contours, _ = cv2.findContours(
            binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )
        for contour in contours:
            if cv2.contourArea(contour) < min_area:
                continue
            epsilon = epsilon_frac * cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, max(epsilon, 1.0), True)
            if len(approx) < 3:
                continue
            poly: list[float] = []
            for point in approx.reshape(-1, 2):
                poly.append(round(float(point[0]) / width, 6))
                poly.append(round(float(point[1]) / height, 6))
            results.append((int(class_id) - 1, poly))
    return results


def link_or_copy(src: Path, dst: Path, copy: bool) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        dst.unlink()
    if copy:
        import shutil

        shutil.copy2(src, dst)
        return
    try:
        os.symlink(src.resolve(), dst)
    except OSError:
        import shutil

        shutil.copy2(src, dst)


def write_split(
    pairs: list[tuple[Path, Path]],
    split: str,
    out_dir: Path,
    min_area_frac: float,
    epsilon_frac: float,
    copy_images: bool,
) -> tuple[int, int]:
    images_out = out_dir / "images" / split
    labels_out = out_dir / "labels" / split
    images_out.mkdir(parents=True, exist_ok=True)
    labels_out.mkdir(parents=True, exist_ok=True)

    kept_images = 0
    total_instances = 0
    for image_path, mask_path in pairs:
        mask = load_mask(mask_path)
        polygons = mask_to_polygons(mask, min_area_frac, epsilon_frac)
        if not polygons:
            continue  # skip frames with no foreground food
        link_or_copy(image_path, images_out / image_path.name, copy_images)
        label_lines = [
            f"{cls} " + " ".join(f"{v:.6f}" for v in poly) for cls, poly in polygons
        ]
        (labels_out / f"{image_path.stem}.txt").write_text(
            "\n".join(label_lines) + "\n", encoding="utf-8"
        )
        kept_images += 1
        total_instances += len(polygons)
    return kept_images, total_instances


def write_data_yaml(out_dir: Path, id2label: dict[int, str]) -> Path:
    num_food = max(id2label) if id2label else 0
    names = [id2label.get(i, f"class_{i}") for i in range(1, num_food + 1)]
    lines = [
        f"path: {out_dir.resolve()}",
        "train: images/train",
        "val: images/val",
        f"nc: {len(names)}",
        "names:",
    ]
    lines += [f"  {i}: {name}" for i, name in enumerate(names)]
    yaml_path = out_dir / "data.yaml"
    yaml_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return yaml_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument(
        "--val-frac",
        type=float,
        default=0.15,
        help="Fraction of the train split reserved for validation when the "
        "dataset has no dedicated test split.",
    )
    parser.add_argument(
        "--min-area-frac",
        type=float,
        default=0.0008,
        help="Drop contours smaller than this fraction of the image area.",
    )
    parser.add_argument(
        "--epsilon-frac",
        type=float,
        default=0.004,
        help="Polygon simplification strength (fraction of contour perimeter).",
    )
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--copy-images",
        action="store_true",
        help="Copy images instead of symlinking (use on filesystems without "
        "symlink support).",
    )
    args = parser.parse_args()

    data_dir: Path = args.data_dir
    out_dir: Path = args.output_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    id2label = read_labels(data_dir)
    train_pairs, test_pairs = collect_pairs(data_dir)

    if test_pairs:
        val_pairs = test_pairs
    else:
        rng = random.Random(args.seed)
        rng.shuffle(train_pairs)
        cut = int(len(train_pairs) * (1.0 - args.val_frac))
        train_pairs, val_pairs = train_pairs[:cut], train_pairs[cut:]

    print(f"[convert] train images: {len(train_pairs)}  val images: {len(val_pairs)}")

    train_kept, train_inst = write_split(
        train_pairs, "train", out_dir, args.min_area_frac, args.epsilon_frac, args.copy_images
    )
    val_kept, val_inst = write_split(
        val_pairs, "val", out_dir, args.min_area_frac, args.epsilon_frac, args.copy_images
    )

    yaml_path = write_data_yaml(out_dir, id2label)

    print(
        f"[convert] kept train {train_kept} imgs / {train_inst} instances, "
        f"val {val_kept} imgs / {val_inst} instances"
    )
    print(f"[convert] classes: {max(id2label)}")
    print(f"[convert] wrote {yaml_path}")
    print("[convert] done.")


if __name__ == "__main__":
    main()
