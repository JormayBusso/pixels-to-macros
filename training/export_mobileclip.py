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
    pip install -r training/requirements.txt
    python training/export_mobileclip.py --compile_ios

Then bundle both resources in the Runner target:
    ruby scripts/add_yolo_model.rb MobileCLIPImage.mlmodelc
    ruby scripts/add_yolo_model.rb FoodLabelEmbeddings.json

Model choice
------------
**Default: MobileCLIP2** (TMLR 2025) — Apple's reinforced-training successor.
It reaches materially higher zero-shot accuracy at the *same* on-device latency
and size because it reuses the exact MobileCLIP architecture (only the weights
differ)::

    MobileCLIP2-S2   77.2% ImageNet zero-shot   (vs 74.4% for MobileCLIP-S2)
    MobileCLIP2-B    79.4%
    MobileCLIP2-S0   71.5%                       (smallest / fastest)

Because the architecture is shared, we load the v2 weights straight into the
existing open_clip ``MobileCLIP-S2`` config. This script auto-downloads the
reinforced checkpoint from ``apple/MobileCLIP2-S2`` (``--mobileclip2-repo``) via
``huggingface_hub`` and reparameterises the MobileOne/FastViT branches for
inference — no source patching, one command. The 512-d embedding is unchanged,
so ``FoodLabelEmbeddings.json`` and the on-device cosine-nearest match in
``MobileCLIPService`` need no changes.

    # default — MobileCLIP2-S2:
    python training/export_mobileclip.py --compile_ios

    # a different v2 size (match the architecture to the repo):
    python training/export_mobileclip.py \
        --model MobileCLIP-B --mobileclip2-repo apple/MobileCLIP2-B --compile_ios

    # original MobileCLIP v1 weights (datacompdr):
    python training/export_mobileclip.py --legacy-v1 --compile_ios
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

DEFAULT_MODEL = "MobileCLIP-S2"  # open_clip architecture (shared by v1 + v2)
DEFAULT_MOBILECLIP2_REPO = "apple/MobileCLIP2-S2"  # reinforced v2 weights (default)
DEFAULT_PRETRAINED = "datacompdr"  # original v1 tag; used only with --legacy-v1
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


def _reparameterize(model):
    """Fuse MobileOne/FastViT training-time branches into single conv layers for
    faster on-device inference. Output is mathematically identical, so any
    failure here is non-fatal — we simply export the unfused graph."""
    for module_path, attr in (
        ("timm.utils.model", "reparameterize_model"),
        ("mobileclip.modules.common.mobileone", "reparameterize_model"),
    ):
        try:
            mod = __import__(module_path, fromlist=[attr])
            reparam = getattr(mod, attr)(model)
            print(f"Reparameterised for inference via {module_path}.{attr}")
            return reparam
        except Exception:  # noqa: BLE001 - optimisation only, never fatal
            continue
    return model


def _download_mobileclip2(repo_id: str) -> str:
    """Fetch the reinforced MobileCLIP2 checkpoint from the HuggingFace Hub and
    return a local path that open_clip loads into the matching MobileCLIP-* config
    (v2 shares v1's architecture; only the weights differ)."""
    try:
        from huggingface_hub import hf_hub_download, list_repo_files
    except ImportError as exc:  # pragma: no cover - dependency hint
        raise SystemExit(
            "huggingface_hub is required for MobileCLIP2 weights "
            "(pip install -r training/requirements.txt), or pass --legacy-v1."
        ) from exc

    checkpoints = sorted(
        (f for f in list_repo_files(repo_id) if f.endswith(".pt")), key=len
    )
    if not checkpoints:
        raise SystemExit(f"No .pt checkpoint found in HuggingFace repo '{repo_id}'.")
    path = hf_hub_download(repo_id=repo_id, filename=checkpoints[0])
    print(f"MobileCLIP2 weights: {repo_id}/{checkpoints[0]}")
    return path


def _load(model_name: str, pretrained: str):
    try:
        import open_clip
    except ImportError as exc:  # pragma: no cover - dependency hint
        raise SystemExit(
            "open_clip_torch is required: pip install -r training/requirements.txt"
        ) from exc

    model, _, _ = open_clip.create_model_and_transforms(
        model_name, pretrained=pretrained
    )
    model.eval()
    model = _reparameterize(model)
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

    if args.legacy_v1:
        pretrained, variant = args.pretrained, args.model
    else:
        pretrained = _download_mobileclip2(args.mobileclip2_repo)
        variant = f"{args.model} / MobileCLIP2 ({args.mobileclip2_repo})"

    model, tokenizer, size, mean, std, logit_scale = _load(args.model, pretrained)
    print(f"Loaded {variant}: input {size}px, scale {logit_scale:.1f}")

    # ── Text embedding table ───────────────────────────────────────────────
    labels = _read_vocab(Path(args.vocab))
    text = _text_embeddings(model, tokenizer, labels)
    table = {
        "model": variant,
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
    mlmodel.short_description = f"{variant} image encoder; unit embedding."
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
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help="open_clip architecture; MobileCLIP2 reuses the MobileCLIP-* configs.",
    )
    parser.add_argument(
        "--mobileclip2-repo",
        default=DEFAULT_MOBILECLIP2_REPO,
        help="HuggingFace repo with the reinforced MobileCLIP2 checkpoint (default weights).",
    )
    parser.add_argument(
        "--legacy-v1",
        action="store_true",
        help="Export original MobileCLIP v1 (--pretrained tag) instead of MobileCLIP2.",
    )
    parser.add_argument(
        "--pretrained",
        default=DEFAULT_PRETRAINED,
        help="open_clip pretrained tag, used only with --legacy-v1.",
    )
    parser.add_argument("--vocab", default=DEFAULT_VOCAB)
    parser.add_argument("--output_dir", default="training/output")
    parser.add_argument("--compile_ios", action="store_true")
    args = parser.parse_args()

    pkg, js = export(args)
    if args.compile_ios:
        compile_for_ios(pkg, js)


if __name__ == "__main__":
    main()
