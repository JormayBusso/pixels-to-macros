"""
FoodSeg103 dataset loader for semantic segmentation training.

Supports two folder layouts automatically:

  Layout A — real FoodSeg103 download (official structure):
    data/FoodSeg103/
        Images/img_dir/train/*.jpg
        Images/img_dir/test/*.jpg
        Annotations/ann_dir/train/*.png
        Annotations/ann_dir/test/*.png
        category_id.txt

  Layout B — flat layout (synthetic mini dataset):
    data/FoodSeg103_mini/
        Images/*.jpg
        Masks/*.png
        category_id.txt   (optional)

For Layout A the official train/test split is used directly.
For Layout B a 70/15/15 random split is applied.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Callable

import numpy as np
from PIL import Image
from torch.utils.data import Dataset


class FoodSeg103Dataset(Dataset):
    """PyTorch dataset for FoodSeg103 semantic segmentation."""

    def __init__(
        self,
        root: str | Path,
        split: str = "train",
        transform: Callable | None = None,
        target_size: tuple[int, int] = (513, 513),
        seed: int = 42,
    ):
        self.root = Path(root)
        self.transform = transform
        self.target_size = target_size

        # ── Detect layout ────────────────────────────────────────────────────
        official_train = self.root / "Images" / "img_dir" / "train"
        official_test  = self.root / "Images" / "img_dir" / "test"
        flat_images    = self.root / "Images"

        if official_train.exists():
            self._init_official(split, official_train, official_test)
        elif flat_images.exists():
            self._init_flat(split, flat_images, seed)
        else:
            raise FileNotFoundError(
                f"Dataset not found at {self.root}.\n"
                "Expected either:\n"
                "  Images/img_dir/train/  (real FoodSeg103)\n"
                "  Images/*.jpg           (flat/mini layout)"
            )

        self.label_map = self._load_labels()

    # ── Layout A: official FoodSeg103 ────────────────────────────────────────
    def _init_official(self, split: str, train_dir: Path, test_dir: Path) -> None:
        ann_train = self.root / "Annotations" / "ann_dir" / "train"
        ann_test  = self.root / "Annotations" / "ann_dir" / "test"

        if split in ("train", "val"):
            # Use official train split; reserve last 15 % for val
            all_imgs = sorted(train_dir.glob("*.jpg"))
            n = len(all_imgs)
            val_start = int(0.85 * n)
            if split == "train":
                imgs = all_imgs[:val_start]
            else:
                imgs = all_imgs[val_start:]
            self.image_paths = imgs
            self.mask_paths  = [ann_train / p.with_suffix(".png").name for p in imgs]
        elif split == "test":
            imgs = sorted(test_dir.glob("*.jpg"))
            self.image_paths = imgs
            self.mask_paths  = [ann_test / p.with_suffix(".png").name for p in imgs]
        else:
            raise ValueError(f"Unknown split: {split}")

    # ── Layout B: flat/mini layout ────────────────────────────────────────────
    def _init_flat(self, split: str, images_dir: Path, seed: int) -> None:
        masks_dir = self.root / "Masks"

        all_images = sorted(images_dir.glob("*.jpg"))
        if not all_images:
            all_images = sorted(images_dir.glob("*.png"))

        rng = np.random.RandomState(seed)
        indices = rng.permutation(len(all_images))
        n = len(all_images)
        train_end = int(0.70 * n)
        val_end   = int(0.85 * n)

        if split == "train":
            sel = indices[:train_end]
        elif split == "val":
            sel = indices[train_end:val_end]
        elif split == "test":
            sel = indices[val_end:]
        else:
            raise ValueError(f"Unknown split: {split}")

        self.image_paths = [all_images[i] for i in sel]
        self.mask_paths  = [
            masks_dir / p.with_suffix(".png").name for p in self.image_paths
        ]

    # ── Label map ─────────────────────────────────────────────────────────────
    def _load_labels(self) -> dict[int, str]:
        label_file = self.root / "category_id.txt"
        labels = {0: "background"}
        if label_file.exists():
            with open(label_file) as f:
                for line in f:
                    parts = line.strip().split(None, 1)
                    if len(parts) >= 2:
                        try:
                            idx  = int(parts[0])
                            name = parts[1]
                            labels[idx] = name
                        except ValueError:
                            pass
        return labels

    def __len__(self) -> int:
        return len(self.image_paths)

    def __getitem__(self, idx: int) -> dict:
        img = Image.open(self.image_paths[idx]).convert("RGB")
        img = img.resize(self.target_size, Image.BILINEAR)

        mask_path = self.mask_paths[idx]
        if mask_path.exists():
            mask = Image.open(mask_path)
            mask = mask.resize(self.target_size, Image.NEAREST)
            mask = np.array(mask, dtype=np.int64)
        else:
            mask = np.zeros((self.target_size[1], self.target_size[0]), dtype=np.int64)

        img_np = np.array(img, dtype=np.float32) / 255.0

        if self.transform:
            transformed = self.transform(image=img_np, mask=mask)
            img_np = transformed["image"]
            mask   = transformed["mask"]

        img_tensor = np.transpose(img_np, (2, 0, 1)).astype(np.float32)

        return {
            "image": img_tensor,
            "mask":  mask,
            "path":  str(self.image_paths[idx]),
        }

    @property
    def num_classes(self) -> int:
        return max(self.label_map.keys()) + 1

