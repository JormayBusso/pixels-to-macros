"""
LoRA fine-tuning of Apple **MobileCLIP2** for food recognition.

What it does
------------
Loads the *exact same* MobileCLIP2 base model that
``training/export_mobileclip.py`` exports (reusing its checkpoint-download and
prompt helpers), attaches **LoRA adapters to the image encoder only**, and
fine-tunes with a CLIP-style contrastive image-text loss on **Food-101**.

Why image-encoder-only LoRA
---------------------------
On device, ``MobileCLIPService`` recognises food by embedding a crop with the
image encoder and picking the nearest **text** embedding from
``FoodLabelEmbeddings.json``. Those label prompts are a *fixed vocabulary*
(``training/food_vocab.txt``), so the text tower never needs to move — we freeze
it and adapt only the vision tower. Freezing text also means the per-class text
prototypes are constant, so we precompute them once and the objective reduces to
aligning each image to its class's frozen text prototype (a CLIP contrastive
image->text cross-entropy over the label set). Only the LoRA deltas on the image
encoder are trained; the exported 512-d embedding space is preserved, so the
adapter is drop-in compatible with the existing on-device cosine-nearest match.

LoRA library
------------
Uses **PEFT** (Hugging Face ``peft``) — the standard, well-maintained
open-source LoRA implementation. We do *not* hand-roll LoRA math. PEFT injects
``lora.Linear`` adapters in-place into the ``open_clip`` MobileCLIP image
encoder's attention (``qkv``/``proj``) and head (``fc``) Linear layers, and
saves a portable adapter checkpoint (``adapter_model.safetensors`` +
``adapter_config.json``) via ``save_pretrained``.

Data
----
``torchvision.datasets.Food101`` (auto-downloads the 101-class dataset). Each of
the 101 category names (e.g. ``apple_pie``) is turned into natural-language
prompts with the same ensemble templates as ``export_mobileclip.py``
(e.g. "a photo of apple pie, a type of food"), embedded once by the frozen text
tower into per-class prototypes.

Requirements (added to training/requirements.txt)
-------------------------------------------------
    open_clip_torch>=3.3.0   # already present
    huggingface_hub>=0.24.0  # already present (MobileCLIP2 weights)
    timm>=1.0.9              # already present (FastViT/MobileOne backbone)
    peft>=0.11.0             # NEW: LoRA adapters
    accelerate>=0.30.0       # NEW: pulled in by peft

Kaggle / Colab install
----------------------
    pip install -q open_clip_torch huggingface_hub timm peft accelerate torchvision

Examples
--------
    # Full run (auto-downloads MobileCLIP2-S2 weights + Food-101):
    python training/train_mobileclip_lora.py \
        --output-dir /kaggle/working/mobileclip_lora \
        --epochs 10 --batch-size 64 --lr 1e-4 --lora-rank 16

    # A smaller/faster architecture:
    python training/train_mobileclip_lora.py \
        --model MobileCLIP-S0 --mobileclip2-repo apple/MobileCLIP2-S0

    # Fast smoke test (no dataset download; synthetic images + real prompts):
    python training/train_mobileclip_lora.py --dummy-data \
        --model MobileCLIP-S0 --mobileclip2-repo apple/MobileCLIP2-S0 \
        --epochs 1 --max-classes 5 --max-samples-per-class 10 \
        --batch-size 4 --output-dir training/output/lora_smoke

After training, merge/export the adapted weights by loading the base model,
``PeftModel.from_pretrained(model.visual_or_model, adapter_dir)`` and re-running
``export_mobileclip.py`` on the adapted model to refresh
``MobileCLIPImage.mlmodelc``.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, Dataset
from tqdm import tqdm

# ── Reuse export_mobileclip.py's model/config logic ─────────────────────────
# The training script lives next to export_mobileclip.py, so when invoked as
# ``python training/train_mobileclip_lora.py`` the script's own directory is on
# sys.path and the sibling module imports directly. We reuse its reinforced-
# weight downloader and prompt ensemble so the base model + label prompts stay
# byte-for-byte identical to what gets exported. export_mobileclip imports
# coremltools at module top; on a lean training box (Kaggle) that may be absent,
# so we fall back to a minimal local copy of just the pieces we need.
sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from export_mobileclip import (  # type: ignore
        DEFAULT_MOBILECLIP2_REPO,
        DEFAULT_MODEL,
        DEFAULT_PRETRAINED,
        DEFAULT_VOCAB,
        OPENAI_MEAN,
        OPENAI_STD,
        PROMPT_TEMPLATES,
        _download_mobileclip2,
        _read_vocab,
    )

    _REUSED_EXPORT = True
except Exception as _exc:  # noqa: BLE001 - coremltools (or another export-only
    # dep) unavailable on a training box; reuse the identical constants/logic
    # locally so behaviour matches export_mobileclip.py without importing it.
    _REUSED_EXPORT = False
    _IMPORT_ERROR = _exc

    DEFAULT_MODEL = "MobileCLIP-S2"
    DEFAULT_MOBILECLIP2_REPO = "apple/MobileCLIP2-S2"
    DEFAULT_PRETRAINED = "datacompdr"
    DEFAULT_VOCAB = "training/food_vocab.txt"
    OPENAI_MEAN = (0.48145466, 0.4578275, 0.40821073)
    OPENAI_STD = (0.26862954, 0.26130258, 0.27577711)
    PROMPT_TEMPLATES = [
        "a photo of {}",
        "a photo of {}, a type of food",
        "a plate of {}",
        "a close-up photo of {}",
        "{}",
    ]

    def _download_mobileclip2(repo_id: str) -> str:  # noqa: D401 - mirror of export
        from huggingface_hub import hf_hub_download, list_repo_files

        checkpoints = sorted(
            (f for f in list_repo_files(repo_id) if f.endswith(".pt")), key=len
        )
        if not checkpoints:
            raise SystemExit(f"No .pt checkpoint found in HuggingFace repo '{repo_id}'.")
        path = hf_hub_download(repo_id=repo_id, filename=checkpoints[0])
        print(f"MobileCLIP2 weights: {repo_id}/{checkpoints[0]}")
        return path

    def _read_vocab(path: Path) -> list[str]:  # noqa: D401 - mirror of export
        if not path.exists():
            raise SystemExit(f"Vocabulary file not found: {path}")
        labels: list[str] = []
        for raw in path.read_text().splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            labels.append(line.lower())
        seen: set[str] = set()
        out = [x for x in labels if not (x in seen or seen.add(x))]
        if not out:
            raise SystemExit("Vocabulary is empty.")
        return out


def set_seed(seed: int) -> None:
    import random

    random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.benchmark = True


# ── Model loading (mirrors export_mobileclip._load, minus reparameterisation) ─
def load_trainable_clip(args, device: torch.device):
    """Build the open_clip MobileCLIP model with MobileCLIP2 (or legacy/random)
    weights. Unlike ``export_mobileclip._load`` we do **not** reparameterise the
    FastViT/MobileOne branches: reparam fuses training-time branches for
    inference and would break gradient flow, so we keep the trainable graph."""
    try:
        import open_clip
    except ImportError as exc:  # pragma: no cover - dependency hint
        raise SystemExit(
            "open_clip_torch is required: pip install -r training/requirements.txt"
        ) from exc

    if args.random_weights:
        pretrained = None
        variant = f"{args.model} (random init - smoke test only)"
    elif args.legacy_v1:
        pretrained = args.pretrained
        variant = f"{args.model} / MobileCLIP v1 ({args.pretrained})"
    else:
        pretrained = _download_mobileclip2(args.mobileclip2_repo)
        variant = f"{args.model} / MobileCLIP2 ({args.mobileclip2_repo})"

    model, preprocess_train, preprocess_val = open_clip.create_model_and_transforms(
        args.model, pretrained=pretrained
    )
    tokenizer = open_clip.get_tokenizer(args.model)

    visual = model.visual
    size = getattr(visual, "image_size", 224)
    if isinstance(size, (tuple, list)):
        size = int(size[0])
    logit_scale = float(model.logit_scale.exp().item())
    model.to(device)
    print(
        f"Loaded {variant}: input {size}px, logit_scale {logit_scale:.1f}, "
        f"reused export_mobileclip helpers: {_REUSED_EXPORT}"
    )
    return model, tokenizer, preprocess_train, preprocess_val, int(size), logit_scale


def attach_image_encoder_lora(model: nn.Module, rank: int, alpha: int, dropout: float):
    """Attach PEFT LoRA adapters to the image encoder's Linear layers only.

    PEFT injects the adapters *in place* into ``model.visual`` and freezes every
    other parameter, so the text tower stays frozen. Returns the wrapping
    ``PeftModel`` (used for ``save_pretrained``); forward passes still go through
    the original ``model.encode_image`` / ``model.encode_text``."""
    try:
        from peft import LoraConfig, get_peft_model
    except ImportError as exc:  # pragma: no cover - dependency hint
        raise SystemExit(
            "peft is required for LoRA: pip install peft accelerate "
            "(or pip install -r training/requirements.txt)"
        ) from exc

    # Full dotted names of the Linear layers inside the image encoder only:
    # MobileCLIP's vision tower is conv-heavy (FastViT/MobileOne); its Linear
    # layers are the self-attention qkv/proj and the projection head fc.
    target_modules = [
        f"visual.{name}"
        for name, module in model.visual.named_modules()
        if isinstance(module, nn.Linear)
    ]
    if not target_modules:
        raise SystemExit("No Linear layers found in the image encoder to adapt.")

    config = LoraConfig(
        r=rank,
        lora_alpha=alpha,
        lora_dropout=dropout,
        bias="none",
        target_modules=target_modules,
    )
    peft_model = get_peft_model(model, config)

    # Belt-and-braces: ensure nothing outside the image encoder trains.
    for name, param in model.named_parameters():
        if "lora_" in name and name.startswith(  # LoRA deltas live under visual.
            ("base_model.model.visual", "visual")
        ):
            param.requires_grad_(True)
        elif "lora_" not in name:
            param.requires_grad_(False)

    trainable = sum(p.numel() for p in peft_model.parameters() if p.requires_grad)
    total = sum(p.numel() for p in peft_model.parameters())
    print(
        f"LoRA attached to image encoder: {len(target_modules)} Linear layers, "
        f"rank={rank}, alpha={alpha}. Trainable {trainable:,} / {total:,} params "
        f"({100.0 * trainable / max(1, total):.3f}%). Text encoder frozen."
    )
    return peft_model


# ── Text prototypes (frozen text tower, prompt-ensembled like export) ───────
@torch.no_grad()
def build_text_prototypes(model, tokenizer, class_prompts, device) -> torch.Tensor:
    """One prototype per class = L2-normalised mean of its prompt-ensemble
    embeddings, produced by the frozen text tower (constant during training)."""
    vectors = []
    for name in class_prompts:
        prompts = [t.format(name) for t in PROMPT_TEMPLATES]
        tokens = tokenizer(prompts).to(device)
        emb = model.encode_text(tokens)
        emb = emb / emb.norm(dim=-1, keepdim=True)
        mean = emb.mean(dim=0)
        mean = mean / mean.norm()
        vectors.append(mean)
    return torch.stack(vectors, dim=0)


# ── Datasets ────────────────────────────────────────────────────────────────
def food101_class_to_prompt(raw: str) -> str:
    """Map a Food-101 category (e.g. ``apple_pie``) to a natural-language name
    (``apple pie``) for prompt building."""
    return raw.replace("_", " ").strip().lower()


class SubsetFood101(Dataset):
    """Food-101 restricted to the first ``max_classes`` categories and capped at
    ``max_samples_per_class`` images each, with labels remapped to a contiguous
    range. Enables fast smoke tests without touching the full 75k-image split."""

    def __init__(self, root, split, transform, max_classes, max_samples_per_class):
        from torchvision.datasets import Food101

        self.base = Food101(root=root, split=split, download=True)
        self.transform = transform
        classes = self.base.classes  # 101 sorted category names

        keep_labels = set(range(len(classes)))
        if max_classes and max_classes > 0:
            keep_labels = set(range(min(max_classes, len(classes))))
        self.classes = [classes[i] for i in sorted(keep_labels)]
        self.remap = {old: new for new, old in enumerate(sorted(keep_labels))}

        per_class: dict[int, int] = {}
        self.indices: list[int] = []
        for idx, label in enumerate(self.base._labels):
            if label not in keep_labels:
                continue
            if max_samples_per_class and per_class.get(label, 0) >= max_samples_per_class:
                continue
            per_class[label] = per_class.get(label, 0) + 1
            self.indices.append(idx)

    def __len__(self) -> int:
        return len(self.indices)

    def __getitem__(self, i: int):
        image, label = self.base[self.indices[i]]
        return self.transform(image), self.remap[label]


class DummyFoodData(Dataset):
    """Synthetic images + real food-vocab prompts for an offline smoke test.

    This is a MOCK: images are random noise (the encoder still runs a full
    forward/backward), labels are random, and class names come from the first
    ``num_classes`` entries of ``food_vocab.txt``. It exercises model loading,
    LoRA attachment, the forward pass, contrastive loss and checkpointing
    WITHOUT downloading the 5 GB Food-101 tarball."""

    def __init__(self, image_size, num_classes, num_samples, vocab_path):
        vocab = _read_vocab(Path(vocab_path))
        self.classes = [v.replace(" ", "_") for v in vocab[:num_classes]]
        self.image_size = image_size
        self.num_classes = len(self.classes)
        self.num_samples = num_samples
        g = torch.Generator().manual_seed(0)
        self.labels = torch.randint(0, self.num_classes, (num_samples,), generator=g)

    def __len__(self) -> int:
        return self.num_samples

    def __getitem__(self, i: int):
        img = torch.rand(3, self.image_size, self.image_size)
        return img, int(self.labels[i])


# ── Checkpointing ───────────────────────────────────────────────────────────
def save_adapter(peft_model, path: Path, meta: dict) -> None:
    path.mkdir(parents=True, exist_ok=True)
    peft_model.save_pretrained(str(path))
    (path / "food_classes.json").write_text(json.dumps(meta, indent=2))


# ── Training ────────────────────────────────────────────────────────────────
def train(args) -> int:
    set_seed(args.seed)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    model, tokenizer, preprocess_train, preprocess_val, image_size, logit_scale = (
        load_trainable_clip(args, device)
    )
    peft_model = attach_image_encoder_lora(
        model, args.lora_rank, args.lora_alpha, args.lora_dropout
    )

    # Data ------------------------------------------------------------------
    if args.dummy_data:
        dataset = DummyFoodData(
            image_size,
            args.max_classes or 5,
            (args.max_classes or 5) * (args.max_samples_per_class or 10),
            args.vocab,
        )
        raw_classes = dataset.classes
        print(f"DUMMY smoke-test data: {len(dataset)} synthetic images, "
              f"{len(raw_classes)} classes from {args.vocab}")
    else:
        dataset = SubsetFood101(
            args.data_dir,
            "train",
            preprocess_train,
            args.max_classes,
            args.max_samples_per_class,
        )
        raw_classes = dataset.classes
        print(f"Food-101 train: {len(dataset)} images, {len(raw_classes)} classes")

    class_prompts = [food101_class_to_prompt(c) for c in raw_classes]
    loader = DataLoader(
        dataset,
        batch_size=args.batch_size,
        shuffle=True,
        num_workers=args.workers,
        pin_memory=device.type == "cuda",
        drop_last=len(dataset) > args.batch_size,
    )

    # Frozen text prototypes (computed once — text tower never trains) --------
    text_prototypes = build_text_prototypes(model, tokenizer, class_prompts, device)
    print(f"Built {text_prototypes.shape[0]} frozen text prototypes "
          f"(dim {text_prototypes.shape[1]}).")

    scale = logit_scale if args.freeze_logit_scale else None
    optimizer = torch.optim.AdamW(
        [p for p in peft_model.parameters() if p.requires_grad],
        lr=args.lr,
        weight_decay=args.weight_decay,
    )
    use_amp = device.type == "cuda"
    scaler = torch.cuda.amp.GradScaler(enabled=use_amp)

    meta_base = {
        "base_model": args.model,
        "mobileclip2_repo": None if args.legacy_v1 or args.random_weights else args.mobileclip2_repo,
        "logit_scale": logit_scale,
        "prompt_templates": PROMPT_TEMPLATES,
        "food101_classes": raw_classes,
        "class_prompts": class_prompts,
        "lora_rank": args.lora_rank,
        "lora_alpha": args.lora_alpha,
    }

    best_acc = -1.0
    global_step = 0
    last_ckpt_time = time.monotonic()
    for epoch in range(args.epochs):
        peft_model.train()
        running_loss, running_correct, running_total = 0.0, 0, 0
        progress = tqdm(loader, desc=f"Epoch {epoch + 1}/{args.epochs}")
        for images, labels in progress:
            images = images.to(device, non_blocking=True)
            labels = labels.to(device, non_blocking=True)

            optimizer.zero_grad(set_to_none=True)
            with torch.cuda.amp.autocast(enabled=use_amp):
                feats = model.encode_image(images)
                feats = feats / feats.norm(dim=-1, keepdim=True)
                cur_scale = scale if scale is not None else model.logit_scale.exp()
                logits = cur_scale * feats @ text_prototypes.T
                loss = F.cross_entropy(logits, labels)

            scaler.scale(loss).backward()
            if args.grad_clip > 0:
                scaler.unscale_(optimizer)
                torch.nn.utils.clip_grad_norm_(
                    [p for p in peft_model.parameters() if p.requires_grad],
                    args.grad_clip,
                )
            scaler.step(optimizer)
            scaler.update()

            global_step += 1
            running_loss += loss.item() * images.size(0)
            running_correct += (logits.argmax(dim=-1) == labels).sum().item()
            running_total += images.size(0)
            progress.set_postfix(
                loss=running_loss / max(1, running_total),
                acc=running_correct / max(1, running_total),
            )

            now = time.monotonic()
            if now - last_ckpt_time >= args.checkpoint_seconds:
                save_adapter(peft_model, output_dir / "last_adapter",
                             {**meta_base, "epoch": epoch, "global_step": global_step})
                print(f"\nSaved timed adapter checkpoint -> {output_dir / 'last_adapter'}")
                last_ckpt_time = now

        epoch_loss = running_loss / max(1, running_total)
        epoch_acc = running_correct / max(1, running_total)
        print(f"Epoch {epoch + 1}: loss={epoch_loss:.4f} train_acc={epoch_acc:.4f}")

        save_adapter(peft_model, output_dir / "last_adapter",
                     {**meta_base, "epoch": epoch, "global_step": global_step,
                      "train_loss": epoch_loss, "train_acc": epoch_acc})
        if epoch_acc > best_acc:
            best_acc = epoch_acc
            save_adapter(peft_model, output_dir / "best_adapter",
                         {**meta_base, "epoch": epoch, "global_step": global_step,
                          "train_loss": epoch_loss, "train_acc": epoch_acc})
            print(f"New best train_acc={best_acc:.4f} -> {output_dir / 'best_adapter'}")

    save_adapter(peft_model, output_dir / "final_adapter",
                 {**meta_base, "epochs": args.epochs, "global_step": global_step})
    print(f"\nDone. LoRA adapter checkpoints written under {output_dir}/ "
          f"(last_adapter, best_adapter, final_adapter).")
    return 0


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    # Base model (mirrors export_mobileclip.py) ------------------------------
    parser.add_argument("--model", default=DEFAULT_MODEL,
                        help="open_clip architecture (MobileCLIP2 reuses the MobileCLIP-* configs).")
    parser.add_argument("--mobileclip2-repo", "--mobileclip2_repo", dest="mobileclip2_repo",
                        default=DEFAULT_MOBILECLIP2_REPO,
                        help="HuggingFace repo with the reinforced MobileCLIP2 checkpoint.")
    parser.add_argument("--legacy-v1", "--legacy_v1", dest="legacy_v1", action="store_true",
                        help="Use original MobileCLIP v1 (--pretrained tag) instead of MobileCLIP2.")
    parser.add_argument("--pretrained", default=DEFAULT_PRETRAINED,
                        help="open_clip pretrained tag, used only with --legacy-v1.")
    parser.add_argument("--random-weights", "--random_weights", dest="random_weights",
                        action="store_true",
                        help="Random-init the backbone (offline smoke tests only; no download).")
    parser.add_argument("--vocab", default=DEFAULT_VOCAB,
                        help="Food vocabulary file (used to name classes in --dummy-data mode).")
    # LoRA -------------------------------------------------------------------
    parser.add_argument("--lora-rank", "--lora_rank", dest="lora_rank", type=int, default=16)
    parser.add_argument("--lora-alpha", "--lora_alpha", dest="lora_alpha", type=int, default=32)
    parser.add_argument("--lora-dropout", "--lora_dropout", dest="lora_dropout",
                        type=float, default=0.05)
    # Data -------------------------------------------------------------------
    parser.add_argument("--data-dir", "--data_dir", dest="data_dir", default="training/data",
                        help="Root where torchvision downloads/reads Food-101.")
    parser.add_argument("--dummy-data", "--dummy_data", dest="dummy_data", action="store_true",
                        help="Use synthetic images + food-vocab prompts (offline smoke test).")
    parser.add_argument("--max-classes", "--max_classes", dest="max_classes", type=int, default=0,
                        help="Limit to the first N Food-101 classes (0 = all 101).")
    parser.add_argument("--max-samples-per-class", "--max_samples_per_class",
                        dest="max_samples_per_class", type=int, default=0,
                        help="Cap images per class (0 = all). Use small values for smoke tests.")
    # Optimisation -----------------------------------------------------------
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--batch-size", "--batch_size", dest="batch_size", type=int, default=64)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--weight-decay", "--weight_decay", dest="weight_decay",
                        type=float, default=0.01)
    parser.add_argument("--grad-clip", "--grad_clip", dest="grad_clip", type=float, default=1.0)
    parser.add_argument("--workers", "--num-workers", "--num_workers", dest="workers",
                        type=int, default=2)
    parser.add_argument("--freeze-logit-scale", "--freeze_logit_scale",
                        dest="freeze_logit_scale", action="store_true", default=True,
                        help="Keep CLIP temperature fixed (default; LoRA-only training).")
    parser.add_argument("--seed", type=int, default=42)
    # Checkpointing ----------------------------------------------------------
    parser.add_argument("--output-dir", "--output_dir", dest="output_dir",
                        default="training/output/mobileclip_lora")
    parser.add_argument("--checkpoint-seconds", "--checkpoint_seconds",
                        dest="checkpoint_seconds", type=int, default=300,
                        help="Save a timed 'last_adapter' checkpoint every N seconds.")
    return parser


def main() -> int:
    args = build_arg_parser().parse_args()
    return train(args)


if __name__ == "__main__":
    raise SystemExit(main())
