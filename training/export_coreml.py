"""
Export a trained food-segmentation model to CoreML (.mlpackage) for iOS.

Two checkpoint types are auto-detected:
  * Ultralytics YOLO-seg (.pt, e.g. best.pt) -> exported via ultralytics'
    native Core ML exporter (raw outputs; NMS runs on-device in Swift).
  * Legacy SegFormer (.pth from training/train.py) -> traced with
    torch.jit.trace and converted directly from the TorchScript graph.

Usage (YOLO, the current `upgraded`-branch path):
    python training/export_coreml.py --checkpoint best.pt --compile_ios

Usage (legacy SegFormer):
    python training/export_coreml.py \
        --checkpoint training/output/best.pth \
        --img_size 512

Outputs:
    training/output/FoodSegYolo.mlpackage         (YOLO)
    training/output/FoodSegmentation.mlpackage    (SegFormer)
    training/output/FoodSegmentationLabels.json   (index -> class name)

With --compile_ios on macOS, the .mlpackage is compiled to .mlmodelc and copied
into ios/Runner/ (FoodSegYolo.mlmodelc is what YOLOSegmentationService loads).
Otherwise compile manually with:
    xcrun coremlcompiler compile training/output/FoodSegYolo.mlpackage ios/Runner/
"""

from __future__ import annotations

import argparse
import platform
import shutil
import subprocess
from pathlib import Path

import coremltools as ct
import torch
import torch.nn.functional as F


class _SegmentationWrapper(torch.nn.Module):
    """Normalise image input and upsample logits for Core ML tracing."""

    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        self.model = model
        self.register_buffer(
            "mean",
            torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1),
        )
        self.register_buffer(
            "std",
            torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = (x - self.mean) / self.std
        out = self.model(x)
        # SegFormer logits are lower-resolution than the input. Upsample here
        # so iOS receives masks at the same grid size that FramePreprocessor
        # and DepthFusion use (512×512 by default).
        if out.shape[-2:] != x.shape[-2:]:
            out = F.interpolate(out, size=x.shape[-2:], mode="bilinear", align_corners=False)
        return out


def _normalise_id2label(raw: dict | None, num_classes: int) -> dict[int, str]:
    if not raw:
        return {idx: f"class_{idx}" for idx in range(num_classes)}
    result: dict[int, str] = {}
    for key, value in raw.items():
        try:
            idx = int(key)
        except (TypeError, ValueError):
            continue
        result[idx] = str(value)
    for idx in range(num_classes):
        result.setdefault(idx, f"class_{idx}")
    return result


def load_model(checkpoint: Path, num_classes: int | None = None) -> tuple[torch.nn.Module, int, dict[int, str]]:
    """Load the current SegFormer training checkpoint and return wrapped model."""
    payload = torch.load(checkpoint, map_location="cpu", weights_only=False)
    if not isinstance(payload, dict) or "model_state_dict" not in payload:
        raise ValueError(
            "Expected a checkpoint from training/train.py containing "
            "'model_state_dict'."
        )

    args_map = payload.get("args", {}) if isinstance(payload.get("args"), dict) else {}
    inferred_classes = int(args_map.get("num_labels") or 0)
    raw_id2label = payload.get("id2label") if isinstance(payload.get("id2label"), dict) else None
    if raw_id2label:
        inferred_classes = max(inferred_classes, max(int(k) for k in raw_id2label.keys()) + 1)
    if num_classes is None or num_classes <= 0:
        num_classes = inferred_classes or 155
    if inferred_classes and inferred_classes != num_classes:
        print(
            f"[export] Checkpoint has {inferred_classes} labels; "
            f"overriding requested num_classes {num_classes} -> {inferred_classes}"
        )
        num_classes = inferred_classes

    id2label = _normalise_id2label(raw_id2label, num_classes)
    label2id = {label: idx for idx, label in id2label.items()}
    model_name = str(args_map.get("model_name") or "nvidia/segformer-b2-finetuned-ade-512-512")

    from train import SegFormerFoodModel  # lazy: SegFormer-only deps

    model = SegFormerFoodModel(model_name, num_classes, id2label, label2id)
    missing, unexpected = model.load_state_dict(payload["model_state_dict"], strict=False)
    if missing:
        print(f"[export] Missing keys while loading checkpoint: {missing[:8]}{'...' if len(missing) > 8 else ''}")
    if unexpected:
        print(f"[export] Ignored unexpected keys: {unexpected[:8]}{'...' if len(unexpected) > 8 else ''}")

    model.eval()
    wrapper = _SegmentationWrapper(model)
    wrapper.eval()
    return wrapper, num_classes, id2label


def convert_coreml(
    model: torch.nn.Module,
    num_classes: int,
    img_size: int,
    output: Path,
) -> Path:
    """Trace PyTorch model to CoreML (.mlpackage) with FP16 weights."""
    model.eval()
    dummy = torch.rand(1, 3, img_size, img_size)

    with torch.no_grad():
        traced = torch.jit.trace(model, dummy)

    print("[export] TorchScript trace complete.")

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="image",
                shape=ct.Shape(shape=(1, 3, img_size, img_size)),
                scale=1 / 255.0,
                bias=[0.0, 0.0, 0.0],
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="segmentation")],
        minimum_deployment_target=ct.target.iOS17,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
    )

    mlpackage_path = output / "FoodSegmentation.mlpackage"
    mlmodel.save(str(mlpackage_path))

    size_mb = sum(
        f.stat().st_size for f in mlpackage_path.rglob("*") if f.is_file()
    ) / 1e6
    print(f"CoreML exported: {mlpackage_path} ({size_mb:.1f} MB)")

    if size_mb > 30:
        print("WARNING: Model exceeds 30 MB. Consider a smaller backbone.")

    return mlpackage_path


def write_labels(id2label: dict[int, str], output: Path) -> Path:
    labels_path = output / "FoodSegmentationLabels.json"
    import json

    labels_path.write_text(
        json.dumps({str(k): v for k, v in sorted(id2label.items())}, indent=2),
        encoding="utf-8",
    )
    print(f"Labels exported: {labels_path}")
    return labels_path


def compile_for_ios(mlpackage_path: Path, ios_runner_dir: Path) -> Path:
    """Compile .mlpackage to .mlmodelc and copy it where iOS loads it."""
    if platform.system() != "Darwin":
        raise RuntimeError(
            "CoreML compilation requires macOS/Xcode. Run this step on the Mac "
            "that builds the iOS app."
        )
    if shutil.which("xcrun") is None:
        raise RuntimeError("xcrun not found. Install Xcode command line tools.")

    ios_runner_dir.mkdir(parents=True, exist_ok=True)
    compiled_path = ios_runner_dir / f"{mlpackage_path.stem}.mlmodelc"
    if compiled_path.exists():
        shutil.rmtree(compiled_path)

    subprocess.run(
        [
            "xcrun",
            "coremlcompiler",
            "compile",
            str(mlpackage_path),
            str(ios_runner_dir),
        ],
        check=True,
    )

    if not compiled_path.exists():
        raise RuntimeError(f"Expected compiled model was not created: {compiled_path}")

    size_mb = sum(
        f.stat().st_size for f in compiled_path.rglob("*") if f.is_file()
    ) / 1e6
    print(f"iOS model ready: {compiled_path} ({size_mb:.1f} MB)")
    return compiled_path


def copy_labels_for_ios(labels_path: Path, ios_runner_dir: Path) -> Path:
    ios_runner_dir.mkdir(parents=True, exist_ok=True)
    dst = ios_runner_dir / "FoodSegmentationLabels.json"
    shutil.copy2(labels_path, dst)
    print(f"iOS labels ready: {dst}")
    return dst


def is_yolo_checkpoint(checkpoint: Path) -> bool:
    """Detect an Ultralytics YOLO checkpoint (.pt) vs a SegFormer .pth.

    YOLO checkpoints store the model object plus 'train_args'/'date' and have no
    'model_state_dict'; the SegFormer trainer writes 'model_state_dict'.
    """
    if checkpoint.suffix.lower() != ".pt":
        # SegFormer checkpoints are saved as .pth; only sniff .pt files.
        try:
            payload = torch.load(checkpoint, map_location="cpu", weights_only=False)
        except Exception:
            return False
        return isinstance(payload, dict) and "model_state_dict" not in payload
    try:
        payload = torch.load(checkpoint, map_location="cpu", weights_only=False)
    except Exception:
        # An unpicklable .pt almost certainly needs the ultralytics loader.
        return True
    if not isinstance(payload, dict):
        return True
    return "model_state_dict" not in payload


def export_yolo(
    checkpoint: Path,
    img_size: int,
    output: Path,
    *,
    compile_ios: bool,
    ios_runner_dir: Path,
    model_basename: str = "FoodSegYolo",
) -> Path:
    """Export an Ultralytics YOLO-seg checkpoint to Core ML for iOS.

    NMS is unsupported for *segmentation* Core ML export, so raw outputs are
    emitted and NMS runs on-device in Swift (YOLOSegmentationService).
    """
    from ultralytics import YOLO

    yolo = YOLO(str(checkpoint))
    if getattr(yolo, "task", None) != "segment":
        print(f"[export] WARNING: model task is '{getattr(yolo, 'task', None)}', expected 'segment'.")

    exported = Path(
        yolo.export(format="coreml", nms=False, imgsz=img_size, half=True)
    )

    mlpackage_path = output / f"{model_basename}.mlpackage"
    if mlpackage_path.exists():
        shutil.rmtree(mlpackage_path)
    shutil.move(str(exported), str(mlpackage_path))

    size_mb = sum(
        f.stat().st_size for f in mlpackage_path.rglob("*") if f.is_file()
    ) / 1e6
    print(f"CoreML exported: {mlpackage_path} ({size_mb:.1f} MB)")
    if size_mb > 30:
        print("WARNING: Model exceeds 30 MB. Consider a smaller backbone (yolo11n-seg).")

    id2label = {int(k): str(v) for k, v in yolo.names.items()}
    labels_path = write_labels(id2label, output)

    if compile_ios:
        compile_for_ios(mlpackage_path, ios_runner_dir)
        copy_labels_for_ios(labels_path, ios_runner_dir)

    return mlpackage_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Export model to CoreML")
    parser.add_argument("--checkpoint", type=str, required=True)
    parser.add_argument("--num_classes", type=int, default=0, help="Optional override; checkpoint labels win when present.")
    parser.add_argument(
        "--img_size",
        type=int,
        default=0,
        help="Inference size. Default: 640 for YOLO, 512 for SegFormer.",
    )
    parser.add_argument("--output_dir", type=str, default="training/output")
    parser.add_argument(
        "--compile_ios",
        action="store_true",
        help="On macOS, compile and place the .mlmodelc into ios/Runner.",
    )
    parser.add_argument("--ios_runner_dir", type=str, default="ios/Runner")
    parser.add_argument(
        "--model_basename",
        type=str,
        default="FoodSegYolo",
        help="Output name for the YOLO export (iOS loads FoodSegYolo.mlmodelc).",
    )
    args = parser.parse_args()

    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)
    checkpoint = Path(args.checkpoint)
    ios_runner_dir = Path(args.ios_runner_dir)

    if is_yolo_checkpoint(checkpoint):
        img_size = args.img_size or 640
        print(f"[export] Detected Ultralytics YOLO checkpoint -> Core ML (imgsz={img_size}).")
        export_yolo(
            checkpoint,
            img_size,
            output,
            compile_ios=args.compile_ios,
            ios_runner_dir=ios_runner_dir,
            model_basename=args.model_basename,
        )
    else:
        img_size = args.img_size or 512
        print(f"[export] Detected SegFormer checkpoint -> Core ML (imgsz={img_size}).")
        model, num_classes, id2label = load_model(checkpoint, args.num_classes)
        mlpackage_path = convert_coreml(model, num_classes, img_size, output)
        labels_path = write_labels(id2label, output)
        if args.compile_ios:
            compile_for_ios(mlpackage_path, ios_runner_dir)
            copy_labels_for_ios(labels_path, ios_runner_dir)

    print("\nDone.")


if __name__ == "__main__":
    main()
