"""
Train a semantic segmentation model for food segmentation.

Supported architectures (--model flag):
  mobilenet   – DeepLabV3 MobileNetV3-Large (lightweight, fast)
  resnet101   – DeepLabV3 ResNet-101 (much stronger backbone)
  segformer   – SegFormer-B3 (transformer-based, HuggingFace)

Usage:
    python training/train.py --data_dir ./data/FoodSeg103 --epochs 100 --model resnet101 --img_size 640

Outputs:
    training/output/best.pth             - best validation weights
    training/output/last_checkpoint.pth  - resumable training checkpoint
    training/output/metrics.json         - training metrics per epoch
"""

from __future__ import annotations

import argparse
import json
import random
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import segmentation_models_pytorch as smp
from PIL import Image
from torch.utils.data import DataLoader
from torchvision.models.segmentation import (
    DeepLabV3_MobileNet_V3_Large_Weights,
    deeplabv3_mobilenet_v3_large,
)
from tqdm import tqdm
import sys

from dataset import FoodSeg103Dataset


def get_model(num_classes: int, pretrained: bool = True, arch: str = "resnet101") -> nn.Module:
    """Build segmentation model by architecture name."""
    if arch == "segformer":
        return _get_segformer(num_classes, pretrained)
    elif arch == "resnet101":
        return smp.DeepLabV3Plus(
            encoder_name="efficientnet-b3",
            encoder_weights="imagenet" if pretrained else None,
            classes=num_classes,
            activation=None,
        )
    else:  # mobilenet
        return _get_deeplabv3_mobilenet(num_classes, pretrained)


def _get_deeplabv3_mobilenet(num_classes: int, pretrained: bool) -> nn.Module:
    weights = DeepLabV3_MobileNet_V3_Large_Weights.DEFAULT if pretrained else None
    model = deeplabv3_mobilenet_v3_large(weights=weights)
    in_channels = model.classifier[4].in_channels
    model.classifier[4] = nn.Conv2d(in_channels, num_classes, kernel_size=1)
    if model.aux_classifier is not None:
        aux_in = model.aux_classifier[4].in_channels
        model.aux_classifier[4] = nn.Conv2d(aux_in, num_classes, kernel_size=1)
    return model


def _get_segformer(num_classes: int, pretrained: bool) -> nn.Module:
    """SegFormer-B3 from HuggingFace transformers, wrapped for compatibility."""
    try:
        from transformers import SegformerForSemanticSegmentation, SegformerConfig
    except ImportError:
        raise ImportError("Install transformers: pip install transformers")

    if pretrained:
        model = SegformerForSemanticSegmentation.from_pretrained(
            "nvidia/segformer-b3-finetuned-ade-512-512",
            num_labels=num_classes,
            ignore_mismatched_sizes=True,
        )
    else:
        config = SegformerConfig(
            num_labels=num_classes,
            depths=[3, 4, 18, 3],
            hidden_sizes=[64, 128, 320, 512],
            decoder_hidden_size=256,
        )
        model = SegformerForSemanticSegmentation(config)

    return _SegFormerWrapper(model)


class _SegFormerWrapper(nn.Module):
    """Wraps HF SegFormer to match torchvision segmentation model interface.

    Input:  (B, 3, H, W) normalised tensors
    Output: dict with key 'out' → (B, num_classes, H, W)
    """

    def __init__(self, hf_model):
        super().__init__()
        self.hf_model = hf_model

    def forward(self, pixel_values):
        outputs = self.hf_model(pixel_values=pixel_values)
        logits = outputs.logits  # (B, num_classes, H/4, W/4)
        # Upsample to input resolution
        logits = F.interpolate(
            logits, size=pixel_values.shape[2:], mode="bilinear", align_corners=False
        )
        return {"out": logits}


class SoftDiceLoss(nn.Module):
    def __init__(self, num_classes: int, ignore_index: int = 255) -> None:
        super().__init__()
        self.num_classes = num_classes
        self.ignore_index = ignore_index

    def forward(self, logits: torch.Tensor, target: torch.Tensor) -> torch.Tensor:
        valid = target != self.ignore_index
        target_safe = target.clone()
        target_safe[~valid] = 0
        probs = logits.softmax(dim=1)
        one_hot = F.one_hot(target_safe, self.num_classes).permute(0, 3, 1, 2)
        one_hot = one_hot.to(dtype=probs.dtype)
        valid = valid.unsqueeze(1)
        probs = probs * valid
        one_hot = one_hot * valid

        dims = (0, 2, 3)
        intersection = (probs * one_hot).sum(dim=dims)
        cardinality = probs.sum(dim=dims) + one_hot.sum(dim=dims)
        dice = (2 * intersection + 1.0) / (cardinality + 1.0)
        return 1 - dice.mean()


class CombinedSegmentationLoss(nn.Module):
    def __init__(
        self,
        num_classes: int,
        class_weights: torch.Tensor | None,
        label_smoothing: float,
    ) -> None:
        super().__init__()
        self.ce = nn.CrossEntropyLoss(
            ignore_index=255,
            weight=class_weights,
            label_smoothing=label_smoothing,
        )
        self.dice = SoftDiceLoss(num_classes=num_classes)

    def forward(self, logits: torch.Tensor, target: torch.Tensor) -> torch.Tensor:
        return 0.72 * self.ce(logits, target) + 0.28 * self.dice(logits, target)


def choose_device() -> torch.device:
    if torch.cuda.is_available():
        return torch.device("cuda")
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def compute_class_weights(
    dataset: FoodSeg103Dataset,
    num_classes: int,
    max_masks: int = 512,
) -> torch.Tensor:
    counts = np.ones(num_classes, dtype=np.float64)
    for mask_path in tqdm(dataset.mask_paths[:max_masks], desc="Class weights", leave=False):
        if not mask_path.exists():
            continue
        mask = np.array(Image.open(mask_path), dtype=np.int64)
        valid = (mask >= 0) & (mask < num_classes)
        bincount = np.bincount(mask[valid].ravel(), minlength=num_classes)
        counts += bincount

    freq = counts / counts.sum()
    weights = 1.0 / np.log(1.02 + freq)
    weights = weights / weights.mean()
    weights[0] *= 0.35
    return torch.tensor(weights, dtype=torch.float32)


def confusion_matrix(pred: np.ndarray, target: np.ndarray, num_classes: int) -> np.ndarray:
    valid = (target >= 0) & (target < num_classes)
    encoded = num_classes * target[valid].astype(np.int64) + pred[valid]
    return np.bincount(encoded, minlength=num_classes**2).reshape(num_classes, num_classes)


def metrics_from_confusion(confusion: np.ndarray) -> tuple[float, float]:
    intersection = np.diag(confusion)
    union = confusion.sum(axis=1) + confusion.sum(axis=0) - intersection
    valid = union > 0
    miou = float(np.mean(intersection[valid] / union[valid])) if valid.any() else 0.0
    pixel_acc = float(intersection.sum() / max(confusion.sum(), 1))
    return miou, pixel_acc


def batch_to_tensors(batch: dict, device: torch.device) -> tuple[torch.Tensor, torch.Tensor]:
    non_blocking = device.type == "cuda"
    images = torch.from_numpy(np.stack(batch["image"])).contiguous().to(device, non_blocking=non_blocking)
    masks = torch.from_numpy(np.stack(batch["mask"])).long().contiguous().to(device, non_blocking=non_blocking)
    return images, masks


def train_one_epoch(
    model: nn.Module,
    loader: DataLoader,
    criterion: nn.Module,
    optimizer: torch.optim.Optimizer,
    device: torch.device,
    scaler: torch.cuda.amp.GradScaler,
    grad_clip: float,
    use_amp: bool,
) -> float:
    model.train()
    total_loss = 0.0
    seen = 0
    pbar = tqdm(loader, desc="  Train", leave=False)
    for i, batch in enumerate(pbar, start=1):
        images, masks = batch_to_tensors(batch, device)
        optimizer.zero_grad(set_to_none=True)

        with torch.cuda.amp.autocast(enabled=use_amp):
            output = model(images).contiguous()
            loss = criterion(output, masks)

        if use_amp:
            scaler.scale(loss).backward()
            scaler.unscale_(optimizer)
            if grad_clip > 0:
                torch.nn.utils.clip_grad_norm_(model.parameters(), grad_clip)
            scaler.step(optimizer)
            scaler.update()
        else:
            loss.backward()
            if grad_clip > 0:
                torch.nn.utils.clip_grad_norm_(model.parameters(), grad_clip)
            optimizer.step()

        batch_n = images.size(0)
        total_loss += loss.item() * batch_n
        seen += batch_n

        # Periodically print running loss so Colab/tee shows live progress
        if i % 20 == 0 or seen == len(loader.dataset):
            running_loss = total_loss / max(seen, 1)
            lr = optimizer.param_groups[0]["lr"]
            pbar.set_postfix({"loss": f"{running_loss:.4f}", "lr": f"{lr:.1e}"})
            print(f"[Train] batch {i}/{len(loader)} loss={running_loss:.4f} lr={lr:.1e}", flush=True)

    return total_loss / len(loader.dataset)


@torch.no_grad()
def evaluate(
    model: nn.Module,
    loader: DataLoader,
    criterion: nn.Module,
    device: torch.device,
    num_classes: int,
) -> tuple[float, float, float]:
    model.eval()
    total_loss = 0.0
    confusion = np.zeros((num_classes, num_classes), dtype=np.int64)
    seen = 0

    pbar = tqdm(loader, desc="  Val  ", leave=False)
    for i, batch in enumerate(pbar, start=1):
        images, masks = batch_to_tensors(batch, device)
        output = model(images).contiguous()
        loss = criterion(output, masks)
        batch_n = images.size(0)
        total_loss += loss.item() * batch_n
        seen += batch_n

        preds = output.argmax(dim=1).cpu().numpy()
        targets = masks.cpu().numpy()
        confusion += confusion_matrix(preds, targets, num_classes)

        if i % 20 == 0 or seen == len(loader.dataset):
            running_loss = total_loss / max(seen, 1)
            pbar.set_postfix({"loss": f"{running_loss:.4f}"})
            print(f"[Val] batch {i}/{len(loader)} loss={running_loss:.4f}", flush=True)

    avg_loss = total_loss / len(loader.dataset)
    miou, pixel_acc = metrics_from_confusion(confusion)
    return avg_loss, miou, pixel_acc


def set_backbone_trainable(model: nn.Module, trainable: bool) -> None:
    if isinstance(model, _SegFormerWrapper):
        # Freeze encoder layers for SegFormer
        encoder = model.hf_model.segformer
        for param in encoder.parameters():
            param.requires_grad = trainable
    elif hasattr(model, "backbone"):
        for param in model.backbone.parameters():
            param.requires_grad = trainable


def _collate(batch):
    return {
        "image": [b["image"] for b in batch],
        "mask": [b["mask"] for b in batch],
        "path": [b["path"] for b in batch],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Train food segmentation model")
    parser.add_argument("--data_dir", type=str, required=True)
    parser.add_argument("--model", type=str, default="resnet101",
                        choices=["mobilenet", "resnet101", "segformer"],
                        help="Model architecture")
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--batch_size", type=int, default=4)
    parser.add_argument("--lr", type=float, default=2e-4)
    parser.add_argument("--output_dir", type=str, default="training/output")
    parser.add_argument("--img_size", type=int, default=640)
    parser.add_argument("--num_workers", type=int, default=2)
    parser.add_argument("--patience", type=int, default=20)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--freeze_backbone_epochs", type=int, default=1)
    parser.add_argument("--label_smoothing", type=float, default=0.03)
    parser.add_argument("--grad_clip", type=float, default=1.0)
    parser.add_argument("--no_class_weights", action="store_true")
    parser.add_argument("--no_pretrained", action="store_true")
    parser.add_argument("--resume", type=str, default="")
    parser.add_argument("--amp", action="store_true")
    args = parser.parse_args()

    set_seed(args.seed)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Auto-resume from last checkpoint if --resume not explicitly given
    if not args.resume:
        auto_ckpt = output_dir / "last_checkpoint.pth"
        if auto_ckpt.exists():
            args.resume = str(auto_ckpt)
            print(f"Auto-resuming from {args.resume}")

    device = choose_device()
    use_amp = args.amp and device.type == "cuda"
    print(f"Device: {device}")
    print(f"AMP: {'on' if use_amp else 'off'}")

    target_size = (args.img_size, args.img_size)
    train_ds = FoodSeg103Dataset(
        args.data_dir,
        split="train",
        target_size=target_size,
        seed=args.seed,
        augment=True,
    )
    val_ds = FoodSeg103Dataset(
        args.data_dir,
        split="val",
        target_size=target_size,
        seed=args.seed,
        augment=False,
    )

    num_classes = train_ds.num_classes
    print(f"Classes: {num_classes}, Train: {len(train_ds)}, Val: {len(val_ds)}")

    train_loader = DataLoader(
        train_ds,
        batch_size=args.batch_size,
        shuffle=True,
        num_workers=args.num_workers,
        pin_memory=device.type == "cuda",
        collate_fn=_collate,
    )
    val_loader = DataLoader(
        val_ds,
        batch_size=args.batch_size,
        shuffle=False,
        num_workers=args.num_workers,
        pin_memory=device.type == "cuda",
        collate_fn=_collate,
    )

    print(f"Model: {args.model}")
    model = get_model(num_classes, pretrained=not args.no_pretrained, arch=args.model).to(device)
    set_backbone_trainable(model, args.freeze_backbone_epochs <= 0)

    class_weights = None
    if not args.no_class_weights:
        class_weights = compute_class_weights(train_ds, num_classes).to(device)

    criterion = CombinedSegmentationLoss(
        num_classes=num_classes,
        class_weights=class_weights,
        label_smoothing=args.label_smoothing,
    )
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
    scaler = torch.cuda.amp.GradScaler(enabled=use_amp)

    start_epoch = 1
    best_miou = 0.0
    metrics = []
    if args.resume:
        payload = torch.load(args.resume, map_location=device)
        state = payload.get("model_state", payload)

        # Safely copy matching parameters only. This allows resuming from
        # checkpoints trained with a different number of classes (classifier
        # heads will be skipped and remain freshly initialized).
        model_state = model.state_dict()
        compatible = {}
        skipped = []
        for k, v in state.items():
            if k not in model_state:
                skipped.append((k, getattr(v, "shape", None), None))
                continue
            target_shape = tuple(model_state[k].shape)
            src_shape = tuple(v.shape) if hasattr(v, "shape") else None
            if src_shape == target_shape:
                compatible[k] = v
            else:
                skipped.append((k, src_shape, target_shape))

        if compatible:
            model_state.update(compatible)
            model.load_state_dict(model_state)
        else:
            print("Warning: no compatible parameters found in checkpoint; using model defaults.")

        if skipped:
            print(f"Skipped {len(skipped)} incompatible state_dict keys when resuming:")
            for k, src, tgt in skipped:
                print(f"  - {k}: checkpoint={src} model={tgt}")

        # Try loading optimizer/scheduler state where possible. If we skipped
        # any parameters due to shape mismatches (e.g., different classifier
        # head sizes), do NOT load optimizer/scheduler state because it maps
        # by parameter IDs and will corrupt state for newly initialized
        # parameters.
        if skipped:
            print("Skipping optimizer/scheduler state load due to incompatible checkpoint parameters.")
        else:
            if "optimizer_state" in payload:
                try:
                    optimizer.load_state_dict(payload["optimizer_state"])
                except Exception as e:
                    print(f"Warning: could not load optimizer state: {e}")
            if "scheduler_state" in payload:
                try:
                    scheduler.load_state_dict(payload["scheduler_state"])
                except Exception as e:
                    print(f"Warning: could not load scheduler state: {e}")

        start_epoch = int(payload.get("epoch", 0)) + 1
        best_miou = float(payload.get("best_miou", 0.0))
        metrics = list(payload.get("metrics", []))
        print(f"Resumed from {args.resume} at epoch {start_epoch}")

    epochs_without_improvement = 0
    for epoch in range(start_epoch, args.epochs + 1):
        if epoch == args.freeze_backbone_epochs + 1:
            set_backbone_trainable(model, True)
            print("Backbone unfrozen")

        t0 = time.time()
        train_loss = train_one_epoch(
            model,
            train_loader,
            criterion,
            optimizer,
            device,
            scaler,
            args.grad_clip,
            use_amp,
        )
        val_loss, val_miou, pixel_acc = evaluate(
            model,
            val_loader,
            criterion,
            device,
            num_classes,
        )
        scheduler.step()
        elapsed = time.time() - t0

        improved = val_miou > best_miou + 1e-4
        if improved:
            best_miou = val_miou
            epochs_without_improvement = 0
            torch.save(model.state_dict(), output_dir / "best.pth")
        else:
            epochs_without_improvement += 1

        entry = {
            "epoch": epoch,
            "train_loss": round(train_loss, 4),
            "val_loss": round(val_loss, 4),
            "val_miou": round(val_miou, 4),
            "pixel_acc": round(pixel_acc, 4),
            "best_miou": round(best_miou, 4),
            "lr": round(optimizer.param_groups[0]["lr"], 7),
            "time_s": round(elapsed, 1),
        }
        metrics.append(entry)
        print(
            f"Epoch {epoch:3d}/{args.epochs} | "
            f"train_loss={entry['train_loss']:.4f} | "
            f"val_loss={entry['val_loss']:.4f} | "
            f"mIoU={entry['val_miou']:.4f} | "
            f"pixel_acc={entry['pixel_acc']:.4f} | "
            f"{entry['time_s']:.0f}s"
        )
        if improved:
            print(f"  -> Saved best model (mIoU={best_miou:.4f})")

        checkpoint = {
            "epoch": epoch,
            "model_state": model.state_dict(),
            "optimizer_state": optimizer.state_dict(),
            "scheduler_state": scheduler.state_dict(),
            "best_miou": best_miou,
            "metrics": metrics,
            "num_classes": num_classes,
        }
        torch.save(checkpoint, output_dir / "last_checkpoint.pth")
        with open(output_dir / "metrics.json", "w") as f:
            json.dump(metrics, f, indent=2)

        if epochs_without_improvement >= args.patience:
            print(f"Early stopping after {args.patience} stale epochs")
            break

    print(f"\nDone. Best mIoU: {best_miou:.4f}")
    print(f"Checkpoint: {output_dir / 'best.pth'}")

    # Auto-export to Core ML immediately after training
    best_ckpt = output_dir / "best.pth"
    if best_ckpt.exists():
        print("\n--- Auto-exporting best model to Core ML ---")
        try:
            import sys as _sys
            _sys.path.insert(0, str(Path(__file__).parent))
            from export_coreml import load_model as _load_model, convert_coreml as _convert_coreml
            _model, _nclasses = _load_model(best_ckpt, num_classes)
            _convert_coreml(_model, _nclasses, args.img_size, output_dir)
            print("Core ML export complete ✅")
        except Exception as e:
            print(f"Auto-export failed ({e}) — run export_coreml.py manually.")


if __name__ == "__main__":
    main()