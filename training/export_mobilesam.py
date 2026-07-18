"""
Export **MobileSAM** (Faster Segment Anything, TinyViT encoder) to CoreML so the
on-device scan can turn a coarse YOLO/SegFormer food box into a *pixel-exact*
silhouette — the box-prompted mask refiner recommended for the scan pipeline.

Two CoreML models are produced (SAM is a two-stage, prompt-based model):

    MobileSamEncoder  image[1024x1024x3]              -> image_embeddings[1,256,64,64]
    MobileSamDecoder  image_embeddings + box[1,4]     -> mask[1,1,1024,1024] (logits)

The encoder runs once per frame; the lightweight decoder runs once per detected
food box (its corner points are the prompt), so refining several foods is cheap.
SAM's ImageNet-style pixel normalisation is baked into the encoder graph, so
Swift hands over the raw 1024x1024 RGB crop and passes the box in the same 1024
pixel space; the mask comes back as logits to threshold at 0.

Usage
-----
    pip install "git+https://github.com/ChaoningZhang/MobileSAM.git"
    curl -L -o training/weights/mobile_sam.pt \
        https://github.com/ChaoningZhang/MobileSAM/raw/master/weights/mobile_sam.pt
    python training/export_mobilesam.py --compile_ios

Outputs
-------
    training/output/MobileSamEncoder.mlpackage
    training/output/MobileSamDecoder.mlpackage
    ios/Runner/MobileSamEncoder.mlmodelc     (with --compile_ios, on macOS)
    ios/Runner/MobileSamDecoder.mlmodelc     (with --compile_ios, on macOS)

The Swift refiner stays inert until BOTH .mlmodelc are bundled (register them
with `ruby scripts/add_yolo_model.rb MobileSamEncoder.mlmodelc` and again for the
decoder), so the scan is never broken by a missing model.
"""

from __future__ import annotations

import argparse
import platform
import subprocess
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from mobile_sam import sam_model_registry

# SAM works at a fixed 1024-pixel square input.
IMG_SIZE = 1024
# SAM pixel normalisation (0-255 domain).
PIXEL_MEAN = [123.675, 116.28, 103.53]
PIXEL_STD = [58.395, 57.12, 57.375]

ROOT = Path(__file__).resolve().parent
DEFAULT_CKPT = ROOT / "weights" / "mobile_sam.pt"
OUT_DIR = ROOT / "output"
IOS_DIR = ROOT.parent / "ios" / "Runner"


class EncoderWrapper(nn.Module):
    """Bake SAM pixel normalisation, then run the TinyViT image encoder."""

    def __init__(self, sam: nn.Module):
        super().__init__()
        self.image_encoder = sam.image_encoder
        self.register_buffer(
            "mean", torch.tensor(PIXEL_MEAN).view(1, 3, 1, 1)
        )
        self.register_buffer(
            "std", torch.tensor(PIXEL_STD).view(1, 3, 1, 1)
        )

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        x = (image - self.mean) / self.std
        return self.image_encoder(x)


class BoxDecoderWrapper(nn.Module):
    """Prompt the mask decoder with a single box and upscale to full 1024."""

    def __init__(self, sam: nn.Module):
        super().__init__()
        self.prompt_encoder = sam.prompt_encoder
        self.mask_decoder = sam.mask_decoder

    def forward(
        self, image_embeddings: torch.Tensor, box: torch.Tensor
    ) -> torch.Tensor:
        # box: [1, 4] as (x0, y0, x1, y1) in 1024 pixel space -> corners [1,2,2].
        boxes = box.reshape(-1, 2, 2)
        sparse, dense = self.prompt_encoder(points=None, boxes=boxes, masks=None)
        low_res_masks, _iou = self.mask_decoder(
            image_embeddings=image_embeddings,
            image_pe=self.prompt_encoder.get_dense_pe(),
            sparse_prompt_embeddings=sparse,
            dense_prompt_embeddings=dense,
            multimask_output=False,
        )
        # low_res_masks: [1,1,256,256] logits -> full-resolution logits.
        masks = F.interpolate(
            low_res_masks, size=(IMG_SIZE, IMG_SIZE),
            mode="bilinear", align_corners=False,
        )
        return masks


def _compile(mlpackage: Path) -> None:
    """Compile an .mlpackage to a bundled .mlmodelc next to the other models."""
    if platform.system() != "Darwin":
        print(f"  (skip compile on {platform.system()}; run with --compile_ios on macOS)")
        return
    out = IOS_DIR / (mlpackage.stem + ".mlmodelc")
    if out.exists():
        subprocess.run(["rm", "-rf", str(out)], check=True)
    subprocess.run(
        ["xcrun", "coremlcompiler", "compile", str(mlpackage), str(IOS_DIR)],
        check=True,
    )
    print(f"  compiled -> {out}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", default=str(DEFAULT_CKPT))
    ap.add_argument("--compile_ios", action="store_true")
    args = ap.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Loading MobileSAM from {args.checkpoint} …")
    sam = sam_model_registry["vit_t"](checkpoint=args.checkpoint)
    sam.eval()

    # ── Encoder ──────────────────────────────────────────────────────────────
    print("Tracing + converting encoder …")
    enc = EncoderWrapper(sam).eval()
    img = torch.rand(1, 3, IMG_SIZE, IMG_SIZE) * 255.0
    with torch.no_grad():
        enc_traced = torch.jit.trace(enc, img, strict=False)
    enc_ml = ct.convert(
        enc_traced,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, IMG_SIZE, IMG_SIZE),
                scale=1.0,
                bias=[0, 0, 0],
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="image_embeddings")],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )
    enc_path = OUT_DIR / "MobileSamEncoder.mlpackage"
    enc_ml.save(str(enc_path))
    print(f"  saved {enc_path}")

    # ── Decoder ──────────────────────────────────────────────────────────────
    print("Tracing + converting box decoder …")
    dec = BoxDecoderWrapper(sam).eval()
    embeddings = torch.rand(1, 256, 64, 64)
    box = torch.tensor([[64.0, 64.0, 960.0, 960.0]])
    with torch.no_grad():
        dec_traced = torch.jit.trace(dec, (embeddings, box), strict=False)
    dec_ml = ct.convert(
        dec_traced,
        inputs=[
            ct.TensorType(name="image_embeddings", shape=(1, 256, 64, 64)),
            ct.TensorType(name="box", shape=(1, 4)),
        ],
        outputs=[ct.TensorType(name="mask")],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )
    dec_path = OUT_DIR / "MobileSamDecoder.mlpackage"
    dec_ml.save(str(dec_path))
    print(f"  saved {dec_path}")

    if args.compile_ios:
        print("Compiling for iOS …")
        _compile(enc_path)
        _compile(dec_path)

    print("Done.")


if __name__ == "__main__":
    main()
