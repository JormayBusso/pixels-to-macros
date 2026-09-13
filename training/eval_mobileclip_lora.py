"""Evaluate MobileCLIP2 zero-shot or LoRA-adapted classification on Food-101.

Examples:
    python training/eval_mobileclip_lora.py
    python training/eval_mobileclip_lora.py --max-samples 100
    python training/eval_mobileclip_lora.py \
        --lora-checkpoint training/output/mobileclip-lora

The dataset is always instantiated with Food-101's official ``test`` split.
``--max-samples`` only limits how many examples from that held-out split are
scored; it never substitutes samples from the training split.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
from pathlib import Path

import torch
from torch.utils.data import DataLoader, Subset
from torchvision.datasets import Food101

try:
    from export_mobileclip import (
        DEFAULT_MOBILECLIP2_REPO,
        DEFAULT_MODEL,
        DEFAULT_PRETRAINED,
        PROMPT_TEMPLATES,
        _download_mobileclip2,
        _reparameterize,
    )
except ModuleNotFoundError:  # Support `python -m training.eval_mobileclip_lora`.
    from training.export_mobileclip import (
        DEFAULT_MOBILECLIP2_REPO,
        DEFAULT_MODEL,
        DEFAULT_PRETRAINED,
        PROMPT_TEMPLATES,
        _download_mobileclip2,
        _reparameterize,
    )


def _device() -> torch.device:
    if torch.cuda.is_available():
        return torch.device('cuda')
    if torch.backends.mps.is_available():
        return torch.device('mps')
    return torch.device('cpu')


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as checkpoint:
        for chunk in iter(lambda: checkpoint.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def _load_model(args: argparse.Namespace, device: torch.device):
    try:
        import open_clip
    except ImportError as exc:  # pragma: no cover - dependency hint
        raise SystemExit(
            'open_clip_torch is required: pip install -r training/requirements.txt'
        ) from exc

    if args.legacy_v1:
        pretrained = args.pretrained
        image_mean = image_std = None
    else:
        pretrained = _download_mobileclip2(args.mobileclip2_repo)
        checkpoint = Path(pretrained)
        if not checkpoint.is_file() or checkpoint.stat().st_size == 0:
            raise SystemExit(f'MobileCLIP2 checkpoint is missing or empty: {checkpoint}')
        digest = _sha256(checkpoint)
        print(
            f'MobileCLIP2 checkpoint: {checkpoint} '
            f'({checkpoint.stat().st_size:,} bytes, sha256={digest})'
        )
        # Apple's official ml-mobileclip preprocessing (mobileclip/__init__.py)
        # is Resize -> CenterCrop -> ToTensor() only, with NO Normalize step —
        # i.e. raw [0, 1] RGB. Verified against Apple's reference source and
        # empirically: raw pixels scored ~90% top-1 on a Food-101 zero-shot
        # subset with this checkpoint, OpenAI CLIP normalisation scored ~2.5%.
        image_mean = (0.0, 0.0, 0.0)
        image_std = (1.0, 1.0, 1.0)
    model, _, preprocess = open_clip.create_model_and_transforms(
        args.model,
        pretrained=pretrained,
        image_mean=image_mean,
        image_std=image_std,
    )

    if args.lora_checkpoint:
        try:
            from peft import PeftModel
        except ImportError as exc:  # pragma: no cover - dependency hint
            raise SystemExit(
                'Loading --lora-checkpoint requires peft '
                '(pip install peft).'
            ) from exc
        checkpoint = Path(args.lora_checkpoint)
        if not checkpoint.exists():
            raise SystemExit(f'LoRA checkpoint not found: {checkpoint}')
        # train_mobileclip_lora.py produces a standard PEFT adapter directory.
        # Apply it before MobileOne/FastViT inference reparameterisation so
        # adapter target-module names continue to match the training model.
        model = PeftModel.from_pretrained(model, checkpoint, is_trainable=False)
        variant = f'{args.model} + LoRA ({checkpoint})'
    else:
        model = _reparameterize(model)
        variant = (
            f'{args.model} / legacy v1 ({args.pretrained})'
            if args.legacy_v1
            else f'{args.model} / MobileCLIP2 ({args.mobileclip2_repo})'
        )

    tokenizer = open_clip.get_tokenizer(args.model)
    return model.eval().to(device), tokenizer, preprocess, variant


def _food101_prompts(categories: list[str]) -> list[list[str]]:
    """Build exactly the prompt ensemble used for FoodLabelEmbeddings.json."""
    return [
        [template.format(category.replace('_', ' ')) for template in PROMPT_TEMPLATES]
        for category in categories
    ]


@torch.inference_mode()
def _text_embeddings(
    model,
    tokenizer,
    categories: list[str],
    device: torch.device,
    single_template: bool,
):
    vectors = []
    for prompts in _food101_prompts(categories):
        if single_template:
            prompts = prompts[:1]
        embeddings = model.encode_text(tokenizer(prompts).to(device))
        embeddings = embeddings / embeddings.norm(dim=-1, keepdim=True)
        mean = embeddings.mean(dim=0)
        vectors.append(mean / mean.norm())
    return torch.stack(vectors)


def _balanced_test_subset(dataset: Food101, max_samples: int) -> Subset:
    """Select a deterministic, class-balanced prefix of the official test split."""
    per_category, remainder = divmod(max_samples, len(dataset.classes))
    remaining = {
        category: per_category + int(index < remainder)
        for index, category in enumerate(dataset.classes)
    }
    indices = []
    for index, target in enumerate(dataset._labels):
        category = dataset.classes[target]
        if remaining[category]:
            indices.append(index)
            remaining[category] -= 1
    return Subset(dataset, indices)


@torch.inference_mode()
def evaluate(args: argparse.Namespace) -> tuple[float, int, Counter, Counter]:
    device = _device()
    model, tokenizer, preprocess, variant = _load_model(args, device)
    print(f'Loaded {variant}; device {device.type}')

    dataset = Food101(
        root=args.data_root,
        split='test',
        transform=preprocess,
        download=True,
    )
    if args.max_samples is not None:
        dataset = _balanced_test_subset(
            dataset,
            min(args.max_samples, len(dataset)),
        )
        print(
            f'Reduced held-out subset: {len(dataset)} of '
            f'{len(dataset.dataset)} official Food-101 test samples.'
        )

    categories = dataset.dataset.classes if isinstance(dataset, Subset) else dataset.classes
    base_dataset = dataset.dataset if isinstance(dataset, Subset) else dataset
    if (
        len(categories) != 101
        or len(base_dataset._labels) != len(base_dataset)
        or min(base_dataset._labels) != 0
        or max(base_dataset._labels) != len(categories) - 1
    ):
        raise RuntimeError('Food-101 categories and labels are inconsistent.')
    print(
        f'Food-101 label mapping: {len(categories)} categories, '
        f'indices {min(base_dataset._labels)}..{max(base_dataset._labels)}.'
    )
    text = _text_embeddings(
        model,
        tokenizer,
        categories,
        device,
        args.single_template,
    )
    print(
        'Text prompts: '
        + ('single template "a photo of {}"' if args.single_template else '5-template ensemble')
    )
    loader = DataLoader(
        dataset,
        batch_size=args.batch_size,
        shuffle=False,
        num_workers=args.num_workers,
        pin_memory=device.type == 'cuda',
    )

    correct = 0
    total = 0
    category_correct: Counter = Counter()
    category_total: Counter = Counter()
    debug_remaining = args.debug_samples
    printed_preprocessing = False
    for images, targets in loader:
        cpu_targets = targets
        if not printed_preprocessing:
            print(
                f'Preprocess: shape={tuple(images.shape)}, dtype={images.dtype}, '
                f'range=[{images.min().item():.4f}, {images.max().item():.4f}]'
            )
            printed_preprocessing = True
        images = images.to(device, non_blocking=True)
        targets = targets.to(device, non_blocking=True)
        image_embeddings = model.encode_image(images)
        image_embeddings = image_embeddings / image_embeddings.norm(
            dim=-1, keepdim=True
        )
        predictions = (image_embeddings @ text.T).argmax(dim=1)
        # Compare on CPU: MPS equality has produced false negatives for these
        # otherwise-identical integer labels on this environment.
        predictions = predictions.cpu()
        matches = predictions.eq(cpu_targets)
        if debug_remaining:
            for target, prediction, match in zip(
                cpu_targets.tolist(),
                predictions.tolist(),
                matches.tolist(),
            ):
                if not debug_remaining:
                    break
                print(
                    f'Debug prediction: predicted={categories[prediction]} '
                    f'actual={categories[target]} correct={bool(match)}'
                )
                debug_remaining -= 1

        correct += int(matches.sum().item())
        total += int(targets.numel())
        for target, match in zip(cpu_targets.tolist(), matches.tolist()):
            category = categories[target]
            category_total[category] += 1
            category_correct[category] += int(match)

    accuracy = correct / total if total else 0.0
    print(f'Top-1 accuracy: {accuracy:.2%} ({correct}/{total})')
    print(f'Test samples evaluated: {total}')
    return accuracy, total, category_correct, category_total


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-root', default='training/data')
    parser.add_argument('--model', default=DEFAULT_MODEL)
    parser.add_argument('--mobileclip2-repo', default=DEFAULT_MOBILECLIP2_REPO)
    parser.add_argument('--legacy-v1', action='store_true')
    parser.add_argument('--pretrained', default=DEFAULT_PRETRAINED)
    parser.add_argument(
        '--lora-checkpoint',
        help='PEFT LoRA adapter directory produced by train_mobileclip_lora.py.',
    )
    parser.add_argument(
        '--max-samples',
        type=int,
        help='Limit evaluation to this many examples from the official test split.',
    )
    parser.add_argument('--batch-size', type=int, default=32)
    parser.add_argument('--num-workers', type=int, default=0)
    parser.add_argument(
        '--debug-samples',
        type=int,
        default=0,
        help='Print predicted and actual categories for this many test images.',
    )
    parser.add_argument(
        '--single-template',
        action='store_true',
        help='Use only "a photo of {category}" instead of the prompt ensemble.',
    )
    parser.add_argument(
        '--report-categories',
        nargs='*',
        metavar='CATEGORY',
        help='Print accuracies for these Food-101 names (for example apple_pie).',
    )
    args = parser.parse_args()
    if args.max_samples is not None and args.max_samples <= 0:
        parser.error('--max-samples must be positive')
    if args.batch_size <= 0:
        parser.error('--batch-size must be positive')
    if args.debug_samples < 0:
        parser.error('--debug-samples must be non-negative')

    _, _, category_correct, category_total = evaluate(args)
    for category in args.report_categories or []:
        normalized = category.lower().replace(' ', '_')
        if normalized not in category_total:
            print(f'Per-category {normalized}: no evaluated samples')
            continue
        correct = category_correct[normalized]
        total = category_total[normalized]
        print(f'Per-category {normalized}: {correct / total:.2%} ({correct}/{total})')


if __name__ == '__main__':
    main()
