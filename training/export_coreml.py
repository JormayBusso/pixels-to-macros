"""
Export a trained PyTorch model to CoreML (.mlpackage) via TorchScript tracing.

Modern coremltools (7+) dropped ONNX as a source; we trace the model with
torch.jit.trace and convert directly from the TorchScript graph.

Usage:
    python training/export_coreml.py \
        --checkpoint training/output/best.pth \
        --num_classes 104 \
        --img_size 513

Outputs:
    training/output/FoodSegmentation.mlpackage

Then compile to .mlmodelc with:
    xcrun coremlcompiler compile training/output/FoodSegmentation.mlpackage ios/Runner/

Copy FoodSegmentation.mlmodelc into the Xcode project bundle.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import coremltools as ct
import torch

from train import get_model


class _SegmentationWrapper(torch.nn.Module):
    """Normalise image input and unwrap DeepLabV3 output for Core ML tracing."""

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
        return self.model(x)["out"]


def load_model(checkpoint: Path, num_classes: int) -> tuple[torch.nn.Module, int]:
    """Load checkpoint, auto-detect num_classes, return wrapped model."""
    payload = torch.load(checkpoint, map_location="cpu", weights_only=True)
    state = payload.get("model_state", payload) if isinstance(payload, dict) else payload

    detected = state["classifier.4.weight"].shape[0]
    if detected != num_classes:
        print(
            f"[export] Checkpoint has {detected} classes; "
            f"overriding --num_classes {num_classes} -> {detected}"
        )
        num_classes = detected

    model = get_model(num_classes, pretrained=False)
    missing, unexpected = model.load_state_dict(state, strict=False)
    if unexpected:
        print(f"[export] Ignored unexpected keys: {unexpected}")

    model.eval()
    wrapper = _SegmentationWrapper(model)
    wrapper.eval()
    return wrapper, num_classes


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


def main() -> None:
    parser = argparse.ArgumentParser(description="Export model to CoreML")
    parser.add_argument("--checkpoint", type=str, required=True)
    parser.add_argument("--num_classes", type=int, default=104)
    parser.add_argument("--img_size", type=int, default=513)
    parser.add_argument("--output_dir", type=str, default="training/output")
    args = parser.parse_args()

    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)

    model, num_classes = load_model(Path(args.checkpoint), args.num_classes)
    convert_coreml(model, num_classes, args.img_size, output)

    print("\nDone.")


if __name__ == "__main__":
    main()
