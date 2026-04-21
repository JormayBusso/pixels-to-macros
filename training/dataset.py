"""
FoodSeg103 dataset loader for semantic segmentation training.

Expected directory structure after downloading FoodSeg103:
    data/FoodSeg103/
        Images/
            img_00001.jpg
            ...
        Masks/
            img_00001.png   (indexed colour: pixel value = class id)
            ...
        category_id.txt     (class index → label mapping)

Dataset split: 70% train / 15% val / 15% test (Part 7).
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

        images_dir = self.root / "Images"
        masks_dir = self.root / "Masks"

        if not images_dir.exists():
            raise FileNotFoundError(f"Images directory not found: {images_dir}")

        # Gather all image paths and sort for deterministic splits
        all_images = sorted(images_dir.glob("*.jpg"))
        if not all_images:
            all_images = sorted(images_dir.glob("*.png"))

        # Deterministic split
        rng = np.random.RandomState(seed)
        indices = rng.permutation(len(all_images))
        n = len(all_images)
        train_end = int(0.70 * n)
        val_end = int(0.85 * n)

        if split == "train":
            sel = indices[:train_end]
        elif split == "val":
            sel = indices[train_end:val_end]
        elif split == "test":
            sel = indices[val_end:]
        else:
            raise ValueError(f"Unknown split: {split}")

        self.image_paths = [all_images[i] for i in sel]
        self.mask_paths = [
            masks_dir / p.with_suffix(".png").name for p in self.image_paths
        ]

        # Load label map
        self.label_map = self._load_labels()

    def _load_labels(self) -> dict[int, str]:
        label_file = self.root / "category_id.txt"
        labels = {0: "background"}
        if label_file.exists():
            with open(label_file) as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 2:
                        idx = int(parts[0])
                        name = " ".join(parts[1:])
                        labels[idx] = name
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
            mask = np.zeros(self.target_size[::-1], dtype=np.int64)

        img_np = np.array(img, dtype=np.float32) / 255.0

        if self.transform:
            transformed = self.transform(image=img_np, mask=mask)
            img_np = transformed["image"]
            mask = transformed["mask"]

        # HWC → CHW
        img_tensor = np.transpose(img_np, (2, 0, 1)).astype(np.float32)

        return {
            "image": img_tensor,
            "mask": mask,
            "path": str(self.image_paths[idx]),
        }

    @property
    def num_classes(self) -> int:
        return max(self.label_map.keys()) + 1
