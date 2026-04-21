"""
Train a DeepLabV3 MobileNetV3-Large model for food segmentation.

Usage:
    python training/train.py --data_dir ./data/FoodSeg103 --epochs 50

Outputs:
    training/output/best.pth        — best validation checkpoint
    training/output/metrics.json    — training metrics per epoch
"""

from __future__ import annotations

import argparse
import json
import os
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from torchvision.models.segmentation import (
    deeplabv3_mobilenet_v3_large,
    DeepLabV3_MobileNet_V3_Large_Weights,
)
from tqdm import tqdm

from dataset import FoodSeg103Dataset


def get_model(num_classes: int, pretrained: bool = True) -> nn.Module:
    """Load DeepLabV3 MobileNetV3 and replace the classifier head."""
    weights = DeepLabV3_MobileNet_V3_Large_Weights.DEFAULT if pretrained else None
    model = deeplabv3_mobilenet_v3_large(weights=weights)

    # Replace classifier for our number of food classes
    in_channels = model.classifier[4].in_channels
    model.classifier[4] = nn.Conv2d(in_channels, num_classes, kernel_size=1)

    # Also replace aux classifier if present
    if model.aux_classifier is not None:
        aux_in = model.aux_classifier[4].in_channels
        model.aux_classifier[4] = nn.Conv2d(aux_in, num_classes, kernel_size=1)

    return model


def compute_miou(pred: np.ndarray, target: np.ndarray, num_classes: int) -> float:
    """Mean Intersection over Union."""
    ious = []
    for c in range(num_classes):
        pred_c = pred == c
        target_c = target == c
        intersection = (pred_c & target_c).sum()
        union = (pred_c | target_c).sum()
        if union > 0:
            ious.append(intersection / union)
    return float(np.mean(ious)) if ious else 0.0


def train_one_epoch(
    model: nn.Module,
    loader: DataLoader,
    criterion: nn.Module,
    optimizer: torch.optim.Optimizer,
    device: torch.device,
) -> float:
    model.train()
    total_loss = 0.0
    for batch in tqdm(loader, desc="  Train", leave=False):
        images = torch.from_numpy(np.stack(batch["image"])).to(device)
        masks = torch.from_numpy(np.stack(batch["mask"])).long().to(device)

        optimizer.zero_grad()
        output = model(images)["out"]
        loss = criterion(output, masks)
        loss.backward()
        optimizer.step()

        total_loss += loss.item() * images.size(0)
    return total_loss / len(loader.dataset)


@torch.no_grad()
def evaluate(
    model: nn.Module,
    loader: DataLoader,
    criterion: nn.Module,
    device: torch.device,
    num_classes: int,
) -> tuple[float, float]:
    model.eval()
    total_loss = 0.0
    all_preds, all_targets = [], []

    for batch in tqdm(loader, desc="  Val  ", leave=False):
        images = torch.from_numpy(np.stack(batch["image"])).to(device)
        masks = torch.from_numpy(np.stack(batch["mask"])).long().to(device)

        output = model(images)["out"]
        loss = criterion(output, masks)
        total_loss += loss.item() * images.size(0)

        preds = output.argmax(dim=1).cpu().numpy()
        all_preds.append(preds)
        all_targets.append(masks.cpu().numpy())

    avg_loss = total_loss / len(loader.dataset)
    all_preds = np.concatenate(all_preds)
    all_targets = np.concatenate(all_targets)
    miou = compute_miou(all_preds, all_targets, num_classes)
    return avg_loss, miou


def main():
    parser = argparse.ArgumentParser(description="Train food segmentation model")
    parser.add_argument("--data_dir", type=str, required=True)
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--batch_size", type=int, default=8)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--output_dir", type=str, default="training/output")
    parser.add_argument("--img_size", type=int, default=513)
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    # Datasets
    target_size = (args.img_size, args.img_size)
    train_ds = FoodSeg103Dataset(args.data_dir, split="train", target_size=target_size)
    val_ds = FoodSeg103Dataset(args.data_dir, split="val", target_size=target_size)

    num_classes = train_ds.num_classes
    print(f"Classes: {num_classes}, Train: {len(train_ds)}, Val: {len(val_ds)}")

    train_loader = DataLoader(
        train_ds, batch_size=args.batch_size, shuffle=True, num_workers=4,
        collate_fn=_collate,
    )
    val_loader = DataLoader(
        val_ds, batch_size=args.batch_size, shuffle=False, num_workers=4,
        collate_fn=_collate,
    )

    # Model
    model = get_model(num_classes).to(device)
    criterion = nn.CrossEntropyLoss(ignore_index=255)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)

    best_miou = 0.0
    metrics = []

    for epoch in range(1, args.epochs + 1):
        t0 = time.time()
        train_loss = train_one_epoch(model, train_loader, criterion, optimizer, device)
        val_loss, val_miou = evaluate(model, val_loader, criterion, device, num_classes)
        scheduler.step()
        elapsed = time.time() - t0

        entry = {
            "epoch": epoch,
            "train_loss": round(train_loss, 4),
            "val_loss": round(val_loss, 4),
            "val_miou": round(val_miou, 4),
            "lr": round(optimizer.param_groups[0]["lr"], 6),
            "time_s": round(elapsed, 1),
        }
        metrics.append(entry)
        print(
            f"Epoch {epoch:3d}/{args.epochs} | "
            f"train_loss={entry['train_loss']:.4f} | "
            f"val_loss={entry['val_loss']:.4f} | "
            f"mIoU={entry['val_miou']:.4f} | "
            f"{entry['time_s']:.0f}s"
        )

        if val_miou > best_miou:
            best_miou = val_miou
            torch.save(model.state_dict(), output_dir / "best.pth")
            print(f"  → Saved best model (mIoU={best_miou:.4f})")

    # Save metrics
    with open(output_dir / "metrics.json", "w") as f:
        json.dump(metrics, f, indent=2)

    print(f"\nDone. Best mIoU: {best_miou:.4f}")
    print(f"Checkpoint: {output_dir / 'best.pth'}")


def _collate(batch):
    """Custom collate that keeps dict structure."""
    return {
        "image": [b["image"] for b in batch],
        "mask": [b["mask"] for b in batch],
        "path": [b["path"] for b in batch],
    }


if __name__ == "__main__":
    main()
