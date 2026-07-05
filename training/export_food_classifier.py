"""
Export a **pretrained** fine-grained food classifier to CoreML for the
crop-and-classify hybrid (`FoodClassifierService` / `FoodClassifier.mlmodelc`).

Why this exists
---------------
The food-trained YOLO segmenter answers *where* food is, but its 103-class
recall (~0.36) means it often mislabels or misses composite/plated dishes
(e.g. an open sandwich with smoked salmon). A dedicated classifier answers
*what* the food is, far more accurately, on the cropped region. The Swift hook
(`FoodClassifierService`) already exists and is inert until this `.mlmodelc`
is bundled — so this script is the one missing piece.

No training, no cost
--------------------
This converts an **existing pretrained** Hugging Face image classifier (default:
a ViT fine-tuned on Food-101) straight to CoreML. Nothing is trained. It runs on
a laptop CPU in a couple of minutes. If you later want broader/regional coverage
you can fine-tune on the free Kaggle GPU and pass `--hf_id <your-model>`.

The CoreML model is a native classifier (CoreML `ClassifierConfig`), so Vision
returns ranked `VNClassificationObservation`s and Swift needs no label file.
ImageNet normalisation is baked into the graph; Vision does the resize/crop.

Usage
-----
    pip install transformers torch coremltools
    python training/export_food_classifier.py --compile_ios

Outputs
-------
    training/output/FoodClassifier.mlpackage
    ios/Runner/FoodClassifier.mlmodelc        (with --compile_ios, on macOS)
    ios/Runner/FoodClassifierLabels.json      (optional logits-fallback labels)

Then bundle it in the Runner target:
    ruby scripts/add_yolo_model.rb FoodClassifier.mlmodelc

Recommended models (all free, pretrained)
-----------------------------------------
    nateraw/food                         Food-101 ViT (default; 101 dishes)
    Kaludi/food-category-classification-v2.0   ~11 robust categories (Bread,
                                         Seafood, ...) — coarse but very reliable
For the best open-vocabulary accuracy on arbitrary foods, use the already wired
MobileCLIP path (`training/export_mobileclip.py`) and keep this classifier as a
second, Food-101-specific crop signal.
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

DEFAULT_HF_ID = "nateraw/food"


class _ClassifierWrapper(nn.Module):
    """Bake ImageNet normalisation + softmax into the graph.

    Vision hands over the raw RGB frame scaled to ``[0, 1]`` (CoreML
    ``scale=1/255``); this wrapper applies the ImageNet mean/std the backbone
    expects and returns class **probabilities** so the CoreML classifier head
    reads calibrated scores.
    """

    def __init__(self, model: nn.Module) -> None:
        super().__init__()
        self.model = model
        self.register_buffer(
            "mean", torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1)
        )
        self.register_buffer(
            "std", torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1)
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = (x - self.mean) / self.std
        logits = self.model(x).logits
        return logits.softmax(dim=-1)


def load_model(hf_id: str):
    try:
        from transformers import AutoModelForImageClassification
    except ImportError as exc:  # pragma: no cover - dependency hint
        raise SystemExit(
            "transformers is required: pip install transformers torch"
        ) from exc

    model = AutoModelForImageClassification.from_pretrained(hf_id)
    model.eval()
    id2label = model.config.id2label
    labels = [str(id2label[i]) for i in range(len(id2label))]
    size = getattr(model.config, "image_size", 224) or 224
    return _ClassifierWrapper(model).eval(), labels, int(size)


def export(hf_id: str, out_dir: Path) -> tuple[Path, list[str]]:
    out_dir.mkdir(parents=True, exist_ok=True)
    model, labels, size = load_model(hf_id)
    print(f"Loaded {hf_id}: {len(labels)} classes, input {size}x{size}")

    example = torch.rand(1, 3, size, size)
    with torch.no_grad():
        traced = torch.jit.trace(model, example, strict=False)

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
        classifier_config=ct.ClassifierConfig(class_labels=labels),
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )

    mlmodel.short_description = (
        f"Pretrained food classifier ({hf_id}); {len(labels)} classes."
    )
    mlmodel.input_description["image"] = "RGB food crop (resized to square)."

    pkg_path = out_dir / "FoodClassifier.mlpackage"
    if pkg_path.exists():
        shutil.rmtree(pkg_path)
    mlmodel.save(str(pkg_path))
    print(f"Saved {pkg_path}")
    return pkg_path, labels


def write_labels_json(labels: list[str], dest: Path) -> None:
    """Optional fallback label map (used only if the model is ever re-exported
    as a raw-logits MultiArray instead of a native classifier)."""
    mapping = {str(i): label for i, label in enumerate(labels)}
    dest.write_text(json.dumps(mapping, indent=2))
    print(f"Wrote {dest}")


def compile_for_ios(mlpackage_path: Path, labels: list[str]) -> None:
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
    write_labels_json(labels, dest_dir / "FoodClassifierLabels.json")
    print(f"Compiled {compiled}")
    print("Bundle it in the Runner target with:")
    print("    ruby scripts/add_yolo_model.rb FoodClassifier.mlmodelc")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hf_id", default=DEFAULT_HF_ID)
    parser.add_argument("--output_dir", default="training/output")
    parser.add_argument("--compile_ios", action="store_true")
    args = parser.parse_args()

    pkg, labels = export(args.hf_id, Path(args.output_dir))
    if args.compile_ios:
        compile_for_ios(pkg, labels)


if __name__ == "__main__":
    main()


# ──────────────────────────────────────────────────────────────────────────
# Implemented companion — open-vocabulary recognition (free, pretrained)
# ──────────────────────────────────────────────────────────────────────────
# A fixed 101-class head cannot name foods outside its list. The app therefore
# also ships Apple's MobileCLIP image encoder plus `FoodLabelEmbeddings.json`,
# generated from `training/food_vocab.txt`. At scan time `MobileCLIPService`
# embeds the crop and takes the nearest food label by cosine similarity. Add
# regional dishes or nutrition-database labels to the vocabulary, regenerate the
# embedding table, and the Swift runtime can use them without retraining.
