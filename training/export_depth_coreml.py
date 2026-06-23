"""
Export a monocular **metric** depth model (Depth Anything V2, metric-indoor
Small) to CoreML for the on-device camera (non-LiDAR) volume path.

Why metric-indoor-small
-----------------------
The non-LiDAR scan currently extrudes the food silhouette by a fixed per-class
height prior — the single biggest accuracy gap for the ~70% of iPhones without
LiDAR. A metric depth net predicts an absolute depth (in metres) per pixel, so
the food's height above the surrounding table can be *measured* instead of
guessed. The "indoor" small variant is ~25 MB, runs on the Neural Engine, and
its 0–20 m metric range comfortably covers a 30 cm hold distance.

The CoreML model takes an RGB image and returns a single-channel depth map in
metres. ImageNet normalisation is baked into the graph so Swift only has to
hand over the raw camera frame; Vision does the resize.

Usage
-----
    python training/export_depth_coreml.py --compile_ios

Outputs
-------
    training/output/MonoDepth.mlpackage      (depth, metres)
    ios/Runner/MonoDepth.mlmodelc            (with --compile_ios, on macOS)

The Swift `MonoDepthService` loads `MonoDepth.mlmodelc`; until it is bundled the
camera path keeps using the height-prior fallback unchanged.
"""

from __future__ import annotations

import argparse
import platform
import shutil
import subprocess
from pathlib import Path

import coremltools as ct
import numpy as np
import torch

# ImageNet statistics used by Depth Anything V2.
_MEAN = [0.485, 0.456, 0.406]
_STD = [0.229, 0.224, 0.225]

# Multiple-of-14 square input (37 * 14 = 518) expected by the ViT-S patch embed.
DEFAULT_SIZE = 518

# HuggingFace id of the metric (indoor) Small checkpoint.
DEFAULT_HF_ID = "depth-anything/Depth-Anything-V2-metric-indoor-small-hf"


class _DepthWrapper(torch.nn.Module):
    """Wrap the HF depth model so the CoreML graph accepts a 0–1 RGB image.

    ImageNet normalisation runs inside `forward`, letting the CoreML input be a
    plain image (scale 1/255) with no per-channel std handling on the Swift
    side. The output is the predicted depth in metres, shape ``[1, H, W]``.
    """

    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        self.model = model
        self.register_buffer("mean", torch.tensor(_MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(_STD).view(1, 3, 1, 1))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = (x - self.mean) / self.std
        out = self.model(pixel_values=x)
        depth = out.predicted_depth
        if depth.dim() == 3:
            depth = depth.unsqueeze(1)  # [B, 1, H, W]
        return depth


def load_model(hf_id: str) -> torch.nn.Module:
    try:
        from transformers import AutoModelForDepthEstimation
    except ImportError as exc:  # pragma: no cover - user environment
        raise SystemExit(
            "transformers is required: pip install 'transformers>=4.45' torch"
        ) from exc

    model = AutoModelForDepthEstimation.from_pretrained(hf_id)
    model.eval()
    return _DepthWrapper(model).eval()


def export(hf_id: str, size: int, out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    model = load_model(hf_id)

    example = torch.rand(1, 3, size, size)
    with torch.no_grad():
        traced = torch.jit.trace(model, example, strict=False)

    # Image input: Vision feeds the raw frame, CoreML scales to [0, 1].
    image_input = ct.ImageType(
        name="image",
        shape=(1, 3, size, size),
        scale=1.0 / 255.0,
        bias=[0.0, 0.0, 0.0],
        color_layout=ct.colorlayout.RGB,
    )

    mlmodel = ct.convert(
        traced,
        inputs=[image_input],
        outputs=[ct.TensorType(name="depth")],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )

    mlmodel.short_description = (
        "Depth Anything V2 metric (indoor, small). Output 'depth' is metres."
    )
    mlmodel.input_description["image"] = "RGB frame (any size; resized to square)."
    mlmodel.output_description["depth"] = "Per-pixel metric depth in metres."

    pkg_path = out_dir / "MonoDepth.mlpackage"
    if pkg_path.exists():
        shutil.rmtree(pkg_path)
    mlmodel.save(str(pkg_path))
    print(f"Saved {pkg_path}")
    return pkg_path


def compile_for_ios(mlpackage_path: Path) -> None:
    if platform.system() != "Darwin":
        print("Skipping --compile_ios: not on macOS.")
        return
    dest_dir = Path("ios/Runner")
    dest_dir.mkdir(parents=True, exist_ok=True)
    compiled = dest_dir / f"{mlpackage_path.stem}.mlmodelc"
    if compiled.exists():
        shutil.rmtree(compiled)
    subprocess.run(
        ["xcrun", "coremlcompiler", "compile", str(mlpackage_path), str(dest_dir)],
        check=True,
    )
    print(f"Compiled {compiled}")
    print("Run `ruby scripts/add_scanner_files.rb` is NOT needed for resources;")
    print("MonoDepth.mlmodelc is bundled as a Runner resource — add it via Xcode")
    print("or `ruby scripts/add_yolo_model.rb` style if not auto-picked up.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hf_id", default=DEFAULT_HF_ID)
    parser.add_argument("--img_size", type=int, default=DEFAULT_SIZE)
    parser.add_argument("--output_dir", default="training/output")
    parser.add_argument("--compile_ios", action="store_true")
    args = parser.parse_args()

    size = args.img_size - (args.img_size % 14)
    if size != args.img_size:
        print(f"Adjusted img_size {args.img_size} -> {size} (multiple of 14)")

    pkg = export(args.hf_id, size, Path(args.output_dir))
    if args.compile_ios:
        compile_for_ios(pkg)


if __name__ == "__main__":
    main()
