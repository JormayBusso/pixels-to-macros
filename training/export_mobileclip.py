"""
Export Apple **MobileCLIP** for open-vocabulary food recognition.

What it produces
----------------
1. ``MobileCLIPImage.mlmodelc`` — the CoreML **image encoder** (image -> unit
   embedding). This is the only model that runs on device.
2. ``FoodLabelEmbeddings.json`` — a precomputed **text embedding** for every
   food name in the vocabulary (``--vocab``, default ``training/food_vocab.txt``),
   embedded with prompt ensembling and L2-normalised.

On device, ``MobileCLIPService`` embeds each food crop and picks the nearest
label by cosine similarity — so it recognises *any* food in the vocabulary
without training. Add foods by editing ``food_vocab.txt`` and re-running.

No training, no cost
--------------------
MobileCLIP is pretrained and free. This only runs the encoders to convert /
precompute; a laptop CPU finishes in a couple of minutes.

Usage
-----
    pip install open_clip_torch torch coremltools
    python training/export_mobileclip.py --compile_ios

Then bundle both resources in the Runner target:
    ruby scripts/add_yolo_model.rb MobileCLIPImage.mlmodelc
    ruby scripts/add_yolo_model.rb FoodLabelEmbeddings.json

Model choice
------------
Default ``MobileCLIP-S2`` (good accuracy / size balance, ~256px). Lighter:
``MobileCLIP-S1``/``MobileCLIP-S0``. Pass ``--model``/``--pretrained`` to change.
"""

from __future__ import annotations

import argparse
import json
import platform
import shutil
import subprocess
from pathlib import Path

import coremltools as ct
import torch
from torch import nn

DEFAULT_MODEL = "MobileCLIP-S2"
DEFAULT_PRETRAINED = "datacompdr"
DEFAULT_VOCAB = "training/food_vocab.txt"

# OpenAI CLIP normalisation (MobileCLIP datacompdr uses these unless the model
# config overrides them, which we read at runtime).
OPENAI_MEAN = (0.48145466, 0.4578275, 0.40821073)
OPENAI_STD = (0.26862954, 0.26130258, 0.27577711)

# Prompt ensemble — averaging a few templates per label is a well-known CLIP
# zero-shot accuracy boost over a single bare word.
PROMPT_TEMPLATES = [
    "a photo of {}",
    "a photo of {}, a type of food",
    "a plate of {}",
    "a close-up photo of {}",
    "{}",
]


class _ImageEncoder(nn.Module):
    """Bake CLIP normalisation + L2-normalisation into the graph so Swift only
    hands over the raw RGB crop (scaled to [0, 1] by CoreML)."""

    def __init__(self, model: nn.Module, mean, std) -> None:
        super().__init__()
        self.model = model
        self.register_buffer("mean", torch.tensor(mean).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(std).view(1, 3, 1, 1))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = (x - self.mean) / self.std
        feat = self.model.encode_image(x)
        return feat / feat.norm(dim=-1, keepdim=True)


def _load(model_name: str, pretrained: str):
    try:
        import open_clip
    except ImportError as exc:  # pragma: no cover - dependency hint
        raise SystemExit(
            "open_clip_torch is required: pip install open_clip_torch torch"
        ) from exc

    model, _, _ = open_clip.create_model_and_transforms(
        model_name, pretrained=pretrained
    )
    model.eval()
    tokenizer = open_clip.get_tokenizer(model_name)

    visual = model.visual
    size = getattr(visual, "image_size", 224)
    if isinstance(size, (tuple, list)):
        size = int(size[0])
    mean = getattr(visual, "image_mean", None) or OPENAI_MEAN
    std = getattr(visual, "image_std", None) or OPENAI_STD
    logit_scale = float(model.logit_scale.exp().item())
    return model, tokenizer, int(size), tuple(mean), tuple(std), logit_scale


def _read_vocab(path: Path) -> list[str]:
    if not path.exists():
        raise SystemExit(f"Vocabulary file not found: {path}")
    labels: list[str] = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        labels.append(line.lower())
    # De-duplicate, preserve order.
    seen: set[str] = set()
    out = [x for x in labels if not (x in seen or seen.add(x))]
    if not out:
        raise SystemExit("Vocabulary is empty.")
    return out


@torch.no_grad()
def _text_embeddings(model, tokenizer, labels: list[str]) -> torch.Tensor:
    vectors = []
    for label in labels:
        prompts = [t.format(label) for t in PROMPT_TEMPLATES]
        tokens = tokenizer(prompts)
        emb = model.encode_text(tokens)
        emb = emb / emb.norm(dim=-1, keepdim=True)
        mean = emb.mean(dim=0)
        mean = mean / mean.norm()
        vectors.append(mean)
    return torch.stack(vectors, dim=0)


def export(args) -> tuple[Path, Path]:
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    model, tokenizer, size, mean, std, logit_scale = _load(args.model, args.pretrained)
    print(f"Loaded {args.model}/{args.pretrained}: input {size}px, scale {logit_scale:.1f}")

    # ── Text embedding table ───────────────────────────────────────────────
    labels = _read_vocab(Path(args.vocab))
    text = _text_embeddings(model, tokenizer, labels)
    table = {
        "model": args.model,
        "dim": int(text.shape[1]),
        "logit_scale": logit_scale,
        "labels": labels,
        "vectors": [[round(float(v), 6) for v in row] for row in text],
    }
    json_path = out_dir / "FoodLabelEmbeddings.json"
    json_path.write_text(json.dumps(table))
    print(f"Wrote {json_path} ({len(labels)} labels, dim {table['dim']})")

    # ── Image encoder -> CoreML ─────────────────────────────────────────────
    encoder = _ImageEncoder(model, mean, std).eval()
    example = torch.rand(1, 3, size, size)
    with torch.no_grad():
        traced = torch.jit.trace(encoder, example, strict=False)

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
        outputs=[ct.TensorType(name="embedding")],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )
    mlmodel.short_description = f"MobileCLIP ({args.model}) image encoder; unit embedding."
    mlmodel.input_description["image"] = "RGB food crop (resized to square)."

    pkg_path = out_dir / "MobileCLIPImage.mlpackage"
    if pkg_path.exists():
        shutil.rmtree(pkg_path)
    mlmodel.save(str(pkg_path))
    print(f"Saved {pkg_path}")
    return pkg_path, json_path


def compile_for_ios(pkg_path: Path, json_path: Path) -> None:
    if platform.system() != "Darwin":
        print("Skipping --compile_ios: not on macOS.")
        return
    dest_dir = Path("ios/Runner")
    dest_dir.mkdir(parents=True, exist_ok=True)
    compiled = dest_dir / f"{pkg_path.stem}.mlmodelc"
    if compiled.exists():
        shutil.rmtree(compiled)
    subprocess.run(
        ["xcrun", "coremlcompiler", "compile", str(pkg_path), str(dest_dir)],
        check=True,
    )
    shutil.copyfile(json_path, dest_dir / "FoodLabelEmbeddings.json")
    print(f"Compiled {compiled}")
    print("Bundle both resources in the Runner target:")
    print("    ruby scripts/add_yolo_model.rb MobileCLIPImage.mlmodelc")
    print("    ruby scripts/add_yolo_model.rb FoodLabelEmbeddings.json")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--pretrained", default=DEFAULT_PRETRAINED)
    parser.add_argument("--vocab", default=DEFAULT_VOCAB)
    parser.add_argument("--output_dir", default="training/output")
    parser.add_argument("--compile_ios", action="store_true")
    args = parser.parse_args()

    pkg, js = export(args)
    if args.compile_ios:
        compile_for_ios(pkg, js)


if __name__ == "__main__":
    main()
