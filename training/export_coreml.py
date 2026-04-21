"""
Export a trained PyTorch model to ONNX and then to CoreML (.mlpackage).

Usage:
    python training/export_coreml.py \
        --checkpoint training/output/best.pth \
        --num_classes 104 \
        --img_size 513

Outputs:
    training/output/FoodSegmentation.onnx
    training/output/FoodSegmentation.mlpackage

Then compile to .mlmodelc with:
    xcrun coremlcompiler compile FoodSegmentation.mlpackage FoodSegmentation.mlmodelc

Copy FoodSegmentation.mlmodelc into the Xcode project bundle.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import coremltools as ct
import numpy as np
import onnx
import torch

from train import get_model


def export_onnx(
    checkpoint: Path,
    num_classes: int,
    img_size: int,
    output: Path,
) -> Path:
    """Export PyTorch checkpoint → ONNX."""
    model = get_model(num_classes, pretrained=False)
    state = torch.load(checkpoint, map_location="cpu", weights_only=True)
    model.load_state_dict(state)
    model.eval()

    dummy = torch.randn(1, 3, img_size, img_size)
    onnx_path = output / "FoodSegmentation.onnx"

    torch.onnx.export(
        model,
        dummy,
        str(onnx_path),
        opset_version=13,
        input_names=["image"],
        output_names=["segmentation"],
        dynamic_axes={
            "image": {0: "batch"},
            "segmentation": {0: "batch"},
        },
    )

    # Validate
    onnx_model = onnx.load(str(onnx_path))
    onnx.checker.check_model(onnx_model)
    print(f"ONNX exported: {onnx_path} ({onnx_path.stat().st_size / 1e6:.1f} MB)")
    return onnx_path


def convert_coreml(
    onnx_path: Path,
    img_size: int,
    output: Path,
) -> Path:
    """Convert ONNX → CoreML (.mlpackage) with FP16 quantisation."""
    mlmodel = ct.converters.convert(
        str(onnx_path),
        source="onnx",
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, img_size, img_size),
                scale=1 / 255.0,
                bias=[0, 0, 0],
                color_layout=ct.colorlayout.RGB,
            )
        ],
        minimum_deployment_target=ct.target.iOS17,
        convert_to="mlprogram",
    )

    # FP16 quantisation (Part 7 — preferred)
    mlmodel_fp16 = ct.models.neural_network.quantization_utils.quantize_weights(
        mlmodel, nbits=16
    )

    mlpackage_path = output / "FoodSegmentation.mlpackage"
    mlmodel_fp16.save(str(mlpackage_path))

    size_mb = sum(
        f.stat().st_size for f in mlpackage_path.rglob("*") if f.is_file()
    ) / 1e6
    print(f"CoreML exported: {mlpackage_path} ({size_mb:.1f} MB)")

    if size_mb > 30:
        print("⚠️  WARNING: Model exceeds 30 MB limit (Part 6). "
              "Consider pruning or using a smaller backbone.")

    return mlpackage_path


def main():
    parser = argparse.ArgumentParser(description="Export model to CoreML")
    parser.add_argument("--checkpoint", type=str, required=True)
    parser.add_argument("--num_classes", type=int, default=104)
    parser.add_argument("--img_size", type=int, default=513)
    parser.add_argument("--output_dir", type=str, default="training/output")
    args = parser.parse_args()

    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)

    onnx_path = export_onnx(
        Path(args.checkpoint), args.num_classes, args.img_size, output
    )
    convert_coreml(onnx_path, args.img_size, output)

    print("\n✅ Done. Next steps:")
    print("  1. xcrun coremlcompiler compile "
          f"{output / 'FoodSegmentation.mlpackage'} "
          f"{output / 'FoodSegmentation.mlmodelc'}")
    print("  2. Copy FoodSegmentation.mlmodelc into ios/Runner/ in Xcode")


if __name__ == "__main__":
    main()
