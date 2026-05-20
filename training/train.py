"""
Production FoodSeg154 semantic-segmentation training for Pixels to Macros.

Architecture:
  - Hugging Face SegFormer-B2: nvidia/segformer-b2-finetuned-ade-512-512
  - 155 classes by default: 154 food classes + background
  - id2label/label2id configured before loading pretrained weights

Loss:
  - 0.5 * segmentation_models_pytorch.losses.FocalLoss
  - 0.5 * segmentation_models_pytorch.losses.DiceLoss

Safety:
  - last_checkpoint.pth saved every 300 seconds
  - best.pth saved whenever validation mIoU improves
  - AMP enabled on CUDA for Kaggle T4/T4x2

Kaggle install:
  pip install -q transformers albumentations segmentation-models-pytorch \
    opencv-python-headless safetensors tqdm Pillow

Example:
  python training/train.py \
    --data-dir /kaggle/input/foodseg154/FoodSeg154 \
    --output-dir /kaggle/working/foodseg154_segformer_b2 \
    --epochs 80 --batch-size 8 --num-labels 155
"""

from __future__ import annotations

import argparse
import json
import random
import time
from dataclasses import dataclass
from pathlib import Path

import albumentations as A
import cv2
import numpy as np
import segmentation_models_pytorch as smp
import torch
import torch.nn as nn
import torch.nn.functional as F
from albumentations.pytorch import ToTensorV2
from PIL import Image
from torch.utils.data import ConcatDataset, DataLoader, Dataset
from tqdm import tqdm
from transformers import (
    SegformerConfig,
    SegformerForSemanticSegmentation,
    get_cosine_schedule_with_warmup,
)

IGNORE_INDEX = 255
IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)
IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".webp")
MASK_EXTS = (".png", ".jpg", ".jpeg", ".tif", ".tiff")


@dataclass(frozen=True)
class Sample:
    image_path: Path
    mask_path: Path


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.benchmark = True


def read_category_file(data_dir: Path, num_labels: int) -> tuple[dict[int, str], dict[str, int]]:
    id2label = {0: "background"}
    for name in ("category_id.txt", "categories.txt", "classes.txt", "labels.txt"):
        label_file = data_dir / name
        if not label_file.exists():
            continue
        for line in label_file.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(None, 1)
            if len(parts) == 1:
                idx = len(id2label)
                label = parts[0]
            else:
                try:
                    idx = int(parts[0])
                    label = parts[1]
                except ValueError:
                    idx = len(id2label)
                    label = line
            if 0 <= idx < num_labels:
                id2label[idx] = label.strip() or f"class_{idx}"
        break

    for idx in range(num_labels):
        id2label.setdefault(idx, f"class_{idx}")
    label2id = {label: idx for idx, label in id2label.items()}
    return id2label, label2id


def list_files(directory: Path, exts: tuple[str, ...]) -> list[Path]:
    if not directory.exists():
        return []
    files: list[Path] = []
    for ext in exts:
        files.extend(directory.rglob(f"*{ext}"))
    return sorted(files)


def pair_images_and_masks(image_dir: Path, mask_dir: Path) -> list[Sample]:
    images = list_files(image_dir, IMAGE_EXTS)
    masks = {p.stem: p for p in list_files(mask_dir, MASK_EXTS)}
    samples: list[Sample] = []
    for image_path in images:
        mask_path = masks.get(image_path.stem)
        if mask_path is not None:
            samples.append(Sample(image_path=image_path, mask_path=mask_path))
    return samples


def candidate_layouts(data_dir: Path, split: str) -> list[tuple[Path, Path]]:
    return [
        (data_dir / "Images" / "img_dir" / split, data_dir / "Annotations" / "ann_dir" / split),
        (data_dir / "images" / split, data_dir / "annotations" / split),
        (data_dir / "images" / split, data_dir / "masks" / split),
        (data_dir / "Images" / split, data_dir / "Masks" / split),
        (data_dir / split / "images", data_dir / split / "masks"),
        (data_dir / split / "Images", data_dir / split / "Masks"),
        (data_dir / "JPEGImages" / split, data_dir / "SegmentationClass" / split),
    ]


def split_aliases(split: str) -> tuple[str, ...]:
    if split == "train":
        return ("train", "training")
    if split == "val":
        return ("val", "validation", "valid", "test")
    if split == "test":
        return ("test", "val", "validation", "valid")
    return (split,)


def discover_samples(data_dir: Path, split: str, seed: int) -> list[Sample]:
    for candidate_split in split_aliases(split):
        for image_dir, mask_dir in candidate_layouts(data_dir, candidate_split):
            samples = pair_images_and_masks(image_dir, mask_dir)
            if samples:
                return samples

    if split in {"train", "val"}:
        for image_dir, mask_dir in candidate_layouts(data_dir, "train"):
            samples = pair_images_and_masks(image_dir, mask_dir)
            if samples:
                rng = random.Random(seed)
                rng.shuffle(samples)
                cut = int(len(samples) * 0.85)
                return samples[:cut] if split == "train" else samples[cut:]

    flat_images = data_dir / "Images"
    flat_masks = data_dir / "Masks"
    samples = pair_images_and_masks(flat_images, flat_masks)
    if samples:
        rng = random.Random(seed)
        rng.shuffle(samples)
        train_end = int(len(samples) * 0.80)
        val_end = int(len(samples) * 0.90)
        if split == "train":
            return samples[:train_end]
        if split == "val":
            return samples[train_end:val_end]
        return samples[val_end:]

    raise FileNotFoundError(
        f"Could not find image/mask pairs for split '{split}' under {data_dir}. "
        "Supported layouts include Images/img_dir/train + Annotations/ann_dir/train, "
        "images/train + masks/train, or flat Images + Masks."
    )


def shift_scale_rotate(**kwargs):
    common = dict(
        shift_limit=0.06,
        scale_limit=0.16,
        rotate_limit=18,
        interpolation=cv2.INTER_LINEAR,
        mask_interpolation=cv2.INTER_NEAREST,
        border_mode=cv2.BORDER_CONSTANT,
        p=0.75,
    )
    common.update(kwargs)
    try:
        return A.ShiftScaleRotate(fill=(0, 0, 0), fill_mask=0, **common)
    except TypeError:
        return A.ShiftScaleRotate(value=(0, 0, 0), mask_value=0, **common)


def build_transforms(img_size: int, train: bool) -> A.Compose:
    if train:
        return A.Compose(
            [
                A.RandomRotate90(p=0.35),
                shift_scale_rotate(),
                A.ColorJitter(
                    brightness=0.22,
                    contrast=0.22,
                    saturation=0.18,
                    hue=0.04,
                    p=0.55,
                ),
                A.RandomBrightnessContrast(
                    brightness_limit=0.20,
                    contrast_limit=0.20,
                    p=0.55,
                ),
                A.HorizontalFlip(p=0.5),
                A.Resize(img_size, img_size, interpolation=cv2.INTER_LINEAR),
                A.Normalize(mean=IMAGENET_MEAN, std=IMAGENET_STD),
                ToTensorV2(),
            ]
        )
    return A.Compose(
        [
            A.Resize(img_size, img_size, interpolation=cv2.INTER_LINEAR),
            A.Normalize(mean=IMAGENET_MEAN, std=IMAGENET_STD),
            ToTensorV2(),
        ]
    )


class FoodSegDataset(Dataset):
    def __init__(
        self,
        data_dir: str | Path,
        split: str,
        img_size: int,
        num_labels: int,
        seed: int,
    ) -> None:
        self.data_dir = Path(data_dir)
        self.split = split
        self.num_labels = num_labels
        self.samples = discover_samples(self.data_dir, split, seed)
        self.transforms = build_transforms(img_size, train=split == "train")

    def __len__(self) -> int:
        return len(self.samples)

    def __getitem__(self, idx: int) -> dict[str, torch.Tensor]:
        sample = self.samples[idx]
        image = cv2.imread(str(sample.image_path), cv2.IMREAD_COLOR)
        if image is None:
            raise FileNotFoundError(sample.image_path)
        image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

        mask = np.array(Image.open(sample.mask_path))
        if mask.ndim == 3:
            mask = mask[..., 0]
        mask = mask.astype(np.int64)
        mask[(mask < 0) | (mask >= self.num_labels)] = IGNORE_INDEX

        augmented = self.transforms(image=image, mask=mask)
        return {
            "pixel_values": augmented["image"].float(),
            "labels": augmented["mask"].long(),
        }


class SegFormerFoodModel(nn.Module):
    def __init__(self, model_name: str, num_labels: int, id2label: dict[int, str], label2id: dict[str, int]) -> None:
        super().__init__()
        config = SegformerConfig.from_pretrained(
            model_name,
            num_labels=num_labels,
            id2label={str(k): v for k, v in id2label.items()},
            label2id=label2id,
        )
        self.model = SegformerForSemanticSegmentation.from_pretrained(
            model_name,
            config=config,
            ignore_mismatched_sizes=True,
        )

    def forward(self, pixel_values: torch.Tensor) -> torch.Tensor:
        return self.model(pixel_values=pixel_values).logits


class ComboLoss(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.focal = smp.losses.FocalLoss(
            mode="multiclass",
            ignore_index=IGNORE_INDEX,
            normalized=True,
        )
        self.dice = smp.losses.DiceLoss(
            mode="multiclass",
            from_logits=True,
            ignore_index=IGNORE_INDEX,
        )

    def forward(self, logits: torch.Tensor, labels: torch.Tensor) -> torch.Tensor:
        if logits.shape[-2:] != labels.shape[-2:]:
            logits = F.interpolate(logits, size=labels.shape[-2:], mode="bilinear", align_corners=False)
        return 0.5 * self.focal(logits, labels) + 0.5 * self.dice(logits, labels)


def unwrap_model(model: nn.Module) -> nn.Module:
    return model.module if isinstance(model, nn.DataParallel) else model


def save_checkpoint(
    path: Path,
    model: nn.Module,
    optimizer: torch.optim.Optimizer,
    scheduler,
    scaler: torch.cuda.amp.GradScaler,
    epoch: int,
    global_step: int,
    best_miou: float,
    args: argparse.Namespace,
    id2label: dict[int, str],
    label2id: dict[str, int],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    checkpoint = {
        "epoch": epoch,
        "global_step": global_step,
        "best_miou": best_miou,
        "model_state_dict": unwrap_model(model).state_dict(),
        "optimizer_state_dict": optimizer.state_dict(),
        "scheduler_state_dict": scheduler.state_dict(),
        "scaler_state_dict": scaler.state_dict(),
        "args": vars(args),
        "id2label": id2label,
        "label2id": label2id,
    }
    tmp = path.with_suffix(".tmp")
    torch.save(checkpoint, tmp)
    tmp.replace(path)


def load_checkpoint(
    path: Path,
    model: nn.Module,
    optimizer: torch.optim.Optimizer | None = None,
    scheduler=None,
    scaler: torch.cuda.amp.GradScaler | None = None,
) -> tuple[int, int, float]:
    checkpoint = torch.load(path, map_location="cpu")
    unwrap_model(model).load_state_dict(checkpoint["model_state_dict"], strict=True)
    if optimizer is not None and "optimizer_state_dict" in checkpoint:
        optimizer.load_state_dict(checkpoint["optimizer_state_dict"])
    if scheduler is not None and "scheduler_state_dict" in checkpoint:
        scheduler.load_state_dict(checkpoint["scheduler_state_dict"])
    if scaler is not None and "scaler_state_dict" in checkpoint:
        scaler.load_state_dict(checkpoint["scaler_state_dict"])
    return (
        int(checkpoint.get("epoch", -1)) + 1,
        int(checkpoint.get("global_step", 0)),
        float(checkpoint.get("best_miou", 0.0)),
    )


@torch.no_grad()
def evaluate(model: nn.Module, loader: DataLoader, device: torch.device, num_labels: int) -> dict[str, float]:
    model.eval()
    intersections = torch.zeros(num_labels, dtype=torch.float64, device=device)
    unions = torch.zeros(num_labels, dtype=torch.float64, device=device)
    correct = torch.tensor(0.0, device=device)
    total = torch.tensor(0.0, device=device)

    for batch in tqdm(loader, desc="Validation", leave=False):
        pixel_values = batch["pixel_values"].to(device, non_blocking=True)
        labels = batch["labels"].to(device, non_blocking=True)
        logits = model(pixel_values)
        logits = F.interpolate(logits, size=labels.shape[-2:], mode="bilinear", align_corners=False)
        preds = logits.argmax(dim=1)

        valid = labels != IGNORE_INDEX
        correct += (preds[valid] == labels[valid]).sum()
        total += valid.sum()

        for cls in range(num_labels):
            pred_c = (preds == cls) & valid
            label_c = (labels == cls) & valid
            intersections[cls] += (pred_c & label_c).sum()
            unions[cls] += (pred_c | label_c).sum()

    valid_classes = unions > 0
    ious = torch.zeros_like(unions)
    ious[valid_classes] = intersections[valid_classes] / unions[valid_classes]
    miou = ious[valid_classes].mean().item() if valid_classes.any() else 0.0

    fg_valid = valid_classes.clone()
    fg_valid[0] = False
    fg_miou = ious[fg_valid].mean().item() if fg_valid.any() else 0.0
    pixel_acc = (correct / total.clamp_min(1)).item()
    return {"miou": miou, "foreground_miou": fg_miou, "pixel_accuracy": pixel_acc}


def train_one_epoch(
    model: nn.Module,
    loader: DataLoader,
    criterion: nn.Module,
    optimizer: torch.optim.Optimizer,
    scheduler,
    scaler: torch.cuda.amp.GradScaler,
    device: torch.device,
    use_amp: bool,
    grad_clip: float,
) -> tuple[float, int]:
    model.train()
    losses: list[float] = []
    steps = 0
    progress = tqdm(loader, desc="Training", leave=False)
    for batch in progress:
        pixel_values = batch["pixel_values"].to(device, non_blocking=True)
        labels = batch["labels"].to(device, non_blocking=True)

        optimizer.zero_grad(set_to_none=True)
        with torch.cuda.amp.autocast(enabled=use_amp):
            logits = model(pixel_values)
            loss = criterion(logits, labels)

        scaler.scale(loss).backward()
        if grad_clip > 0:
            scaler.unscale_(optimizer)
            torch.nn.utils.clip_grad_norm_(model.parameters(), grad_clip)
        scaler.step(optimizer)
        scaler.update()
        scheduler.step()

        loss_value = float(loss.detach().cpu())
        losses.append(loss_value)
        steps += 1
        progress.set_postfix(loss=f"{loss_value:.4f}")

    return float(np.mean(losses)) if losses else 0.0, steps


def write_metrics(path: Path, rows: list[dict]) -> None:
    path.write_text(json.dumps(rows, indent=2), encoding="utf-8")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Train SegFormer-B2 on FoodSeg154")
    parser.add_argument("--data-dir", "--data_dir", dest="data_dir", required=True, help="FoodSeg154 root directory")
    parser.add_argument("--output-dir", "--output_dir", dest="output_dir", default="training/output", help="Checkpoint output directory")
    parser.add_argument("--model-name", "--model", dest="model_name", default="nvidia/segformer-b2-finetuned-ade-512-512")
    parser.add_argument("--num-labels", "--num_labels", "--num-classes", "--num_classes", dest="num_labels", type=int, default=155)
    parser.add_argument("--img-size", "--img_size", dest="img_size", type=int, default=512)
    parser.add_argument("--epochs", type=int, default=80)
    parser.add_argument("--batch-size", "--batch_size", dest="batch_size", type=int, default=8)
    parser.add_argument("--workers", "--num-workers", "--num_workers", dest="workers", type=int, default=2)
    parser.add_argument("--lr", type=float, default=6e-5)
    parser.add_argument("--weight-decay", type=float, default=0.01)
    parser.add_argument("--warmup-ratio", type=float, default=0.08)
    parser.add_argument("--grad-clip", type=float, default=1.0)
    parser.add_argument("--checkpoint-seconds", "--save-every-secs", "--save_every_secs", dest="checkpoint_seconds", type=int, default=300)
    parser.add_argument("--val-every", "--val_every", dest="val_every", type=int, default=1)
    parser.add_argument("--virtual-train-multiplier", "--virtual_train_multiplier", dest="virtual_train_multiplier", type=int, default=1)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--resume", default="", help="Path to last_checkpoint.pth")
    parser.add_argument("--amp", action="store_true", help="Compatibility flag; CUDA AMP is enabled by default")
    parser.add_argument("--no-amp", action="store_true", help="Disable CUDA AMP")
    parser.add_argument("--no-data-parallel", action="store_true", help="Disable multi-GPU DataParallel")
    return parser


def main() -> int:
    args = build_arg_parser().parse_args()
    if args.model_name.lower() in {"resnet101", "deeplabv3_resnet101"}:
        print("Legacy --model value detected; using SegFormer-B2 for FoodSeg154 instead.")
        args.model_name = "nvidia/segformer-b2-finetuned-ade-512-512"
    args.val_every = max(1, args.val_every)
    args.virtual_train_multiplier = max(1, args.virtual_train_multiplier)
    set_seed(args.seed)

    data_dir = Path(args.data_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    metrics_path = output_dir / "metrics.json"
    best_path = output_dir / "best.pth"
    last_path = output_dir / "last_checkpoint.pth"

    id2label, label2id = read_category_file(data_dir, args.num_labels)
    (output_dir / "id2label.json").write_text(json.dumps(id2label, indent=2), encoding="utf-8")

    train_ds = FoodSegDataset(data_dir, "train", args.img_size, args.num_labels, args.seed)
    val_ds = FoodSegDataset(data_dir, "val", args.img_size, args.num_labels, args.seed)
    print(f"Train samples: {len(train_ds)} | Val samples: {len(val_ds)}")
    train_data = train_ds
    if args.virtual_train_multiplier > 1:
        train_data = ConcatDataset([train_ds] * args.virtual_train_multiplier)
        print(
            f"Virtual train multiplier: {args.virtual_train_multiplier} "
            f"({len(train_data)} augmented samples per epoch)"
        )

    train_loader = DataLoader(
        train_data,
        batch_size=args.batch_size,
        shuffle=True,
        num_workers=args.workers,
        pin_memory=torch.cuda.is_available(),
        persistent_workers=args.workers > 0,
        drop_last=True,
    )
    val_loader = DataLoader(
        val_ds,
        batch_size=max(1, args.batch_size // 2),
        shuffle=False,
        num_workers=args.workers,
        pin_memory=torch.cuda.is_available(),
        persistent_workers=args.workers > 0,
    )

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    use_amp = device.type == "cuda" and not args.no_amp
    model = SegFormerFoodModel(args.model_name, args.num_labels, id2label, label2id)
    model.to(device)
    if device.type == "cuda" and torch.cuda.device_count() > 1 and not args.no_data_parallel:
        print(f"Using DataParallel across {torch.cuda.device_count()} GPUs")
        model = nn.DataParallel(model)

    criterion = ComboLoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    total_steps = max(1, len(train_loader) * args.epochs)
    warmup_steps = int(total_steps * args.warmup_ratio)
    scheduler = get_cosine_schedule_with_warmup(
        optimizer,
        num_warmup_steps=warmup_steps,
        num_training_steps=total_steps,
    )
    scaler = torch.cuda.amp.GradScaler(enabled=use_amp)

    start_epoch = 0
    global_step = 0
    best_miou = 0.0
    if args.resume:
        start_epoch, global_step, best_miou = load_checkpoint(
            Path(args.resume), model, optimizer, scheduler, scaler
        )
        print(f"Resumed from {args.resume}: epoch={start_epoch}, best_miou={best_miou:.4f}")

    history: list[dict] = []
    if metrics_path.exists():
        try:
            history = json.loads(metrics_path.read_text(encoding="utf-8"))
        except Exception:
            history = []

    last_checkpoint_time = time.monotonic()
    for epoch in range(start_epoch, args.epochs):
        print(f"\nEpoch {epoch + 1}/{args.epochs}")
        train_loss, steps = train_one_epoch(
            model,
            train_loader,
            criterion,
            optimizer,
            scheduler,
            scaler,
            device,
            use_amp,
            args.grad_clip,
        )
        global_step += steps

        now = time.monotonic()
        if now - last_checkpoint_time >= args.checkpoint_seconds:
            save_checkpoint(
                last_path,
                model,
                optimizer,
                scheduler,
                scaler,
                epoch,
                global_step,
                best_miou,
                args,
                id2label,
                label2id,
            )
            print(f"Saved timed checkpoint: {last_path}")
            last_checkpoint_time = now

        should_validate = ((epoch + 1) % args.val_every == 0) or (epoch + 1 == args.epochs)
        metrics = evaluate(model, val_loader, device, args.num_labels) if should_validate else {
            "miou": best_miou,
            "foreground_miou": 0.0,
            "pixel_accuracy": 0.0,
        }
        row = {
            "epoch": epoch + 1,
            "train_loss": train_loss,
            "validated": should_validate,
            "miou": metrics["miou"],
            "foreground_miou": metrics["foreground_miou"],
            "pixel_accuracy": metrics["pixel_accuracy"],
            "lr": scheduler.get_last_lr()[0],
        }
        history.append(row)
        write_metrics(metrics_path, history)

        if should_validate:
            print(
                f"loss={train_loss:.4f} | mIoU={metrics['miou']:.4f} | "
                f"fg_mIoU={metrics['foreground_miou']:.4f} | "
                f"pixel_acc={metrics['pixel_accuracy']:.4f}"
            )
        else:
            print(f"loss={train_loss:.4f} | validation skipped until epoch multiple of {args.val_every}")

        save_checkpoint(
            last_path,
            model,
            optimizer,
            scheduler,
            scaler,
            epoch,
            global_step,
            best_miou,
            args,
            id2label,
            label2id,
        )
        if should_validate and metrics["miou"] > best_miou:
            best_miou = metrics["miou"]
            save_checkpoint(
                best_path,
                model,
                optimizer,
                scheduler,
                scaler,
                epoch,
                global_step,
                best_miou,
                args,
                id2label,
                label2id,
            )
            print(f"New best mIoU {best_miou:.4f}; saved {best_path}")

    print(f"Training complete. Best mIoU: {best_miou:.4f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
