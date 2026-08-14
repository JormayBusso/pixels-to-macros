# Kaggle Cells: FoodSeg → YOLO11-seg (Core ML) Training

Set the Kaggle accelerator to **GPU T4** — a single T4 is enough for this run.
(Dual-GPU DDP works in theory but is unreliable inside Kaggle notebooks, so the
cells use one GPU; selecting "T4 x2" would just leave the second card idle.)

This is the `upgraded`-branch path: a YOLO11-seg instance-segmentation model that
trains far faster than SegFormer (COCO-pretrained) and exports straight to Core ML
with `format=coreml` (NMS runs on-device in Swift). It trains on the **same FoodSeg dataset** — there is
no public "food-segmentation" checkpoint to download; the professional result comes
from fine-tuning YOLO11-seg on FoodSeg.

## Cell 1 - Clone repo (upgraded branch) and install

```python
# Cell 1 - Clone repo and install Ultralytics
!git clone https://github.com/JormayBusso/pixels-to-macros.git
%cd pixels-to-macros

!git fetch --all
!git checkout upgraded
!git reset --hard origin/upgraded

!pip install -q --upgrade pip
!pip install -q ultralytics opencv-python-headless

import torch, ultralytics
print('CUDA:', torch.cuda.is_available(), '| GPUs:', torch.cuda.device_count())
ultralytics.checks()
```

## Cell 2 - Locate FoodSeg and convert masks → YOLO polygons

```python
# Cell 2 - Convert semantic masks to YOLO-seg instance polygons
from pathlib import Path

# Tries the auto HF download first, then common Kaggle input mounts.
!python scripts/download_hf_foodseg103.py || true

candidates = [
    Path('./data/FoodSeg103'),
    Path('/kaggle/input/foodseg103/FoodSeg103'),
    Path('/kaggle/input/foodseg103'),
    Path('/kaggle/input/foodseg-103/FoodSeg103'),
    Path('/kaggle/input/foodseg154/FoodSeg154'),
    Path('/kaggle/input/foodseg154'),
]
DATA_DIR = next((p for p in candidates if p.exists()), None)
assert DATA_DIR is not None, 'Add FoodSeg as a Kaggle input or set DATA_DIR manually.'

YOLO_DIR = Path('/kaggle/working/foodseg_yolo')

!python training/foodseg_to_yolo.py \
    --data-dir   {DATA_DIR} \
    --output-dir {YOLO_DIR} \
    --val-frac   0.15

print('data.yaml ->', YOLO_DIR / 'data.yaml')
print((YOLO_DIR / 'data.yaml').read_text()[:400])
```

## Cell 3 - Train YOLO11-seg

```python
# Cell 3 - Fine-tune YOLO11-seg from COCO-pretrained weights
from ultralytics import YOLO

# yolo11s-seg = good accuracy/size for mobile. Use yolo11n-seg for max speed,
# or yolo11m-seg if you have time and want higher mAP.
model = YOLO('yolo11s-seg.pt')

# Accuracy-focused config. Key edge-accuracy levers: mask_ratio=1 trains masks
# at full resolution (default 4 downsamples 4x), overlap_mask keeps touching
# instances (peanuts, berries) separable, and copy_paste/mixup/cutmix add
# clustered + occluded food arrangements.
results = model.train(
    data='/kaggle/working/foodseg_yolo/data.yaml',
    epochs=140,
    imgsz=640,          # match on-device Swift input size (raise both to 768
                        # together for even finer edges).
    batch=12,           # 640 + mask_ratio=1 uses more VRAM; drop to 8 on OOM
    device=0,           # one T4 is enough; multi-GPU DDP is flaky in notebooks
    patience=35,        # early stop if val mask mAP plateaus
    optimizer='auto',
    cos_lr=True,
    mask_ratio=1,       # full-res mask targets -> sharpest boundaries
    overlap_mask=True,  # keep overlapping instances separable
    copy_paste=0.3, copy_paste_mode='flip',
    mixup=0.15, cutmix=0.10,
    mosaic=1.0, close_mosaic=15,
    hsv_h=0.015, hsv_s=0.7, hsv_v=0.4,
    degrees=10.0, translate=0.1, scale=0.5, shear=2.0,
    fliplr=0.5, flipud=0.5,
    project='/kaggle/working/runs',
    name='foodseg_yolo11s',
    plots=True,
)

BEST = Path(results.save_dir) / 'weights' / 'best.pt'
print('best weights ->', BEST)

# Validate at full mask resolution (retina_masks) — reports the crisp-edge mAP
# you will actually get on-device.
metrics = YOLO(str(BEST)).val(
    data='/kaggle/working/foodseg_yolo/data.yaml',
    imgsz=640, retina_masks=True, plots=True,
)
print('mask mAP50-95 :', round(metrics.seg.map, 4))
```

## Cell 4 - Export to Core ML (.mlpackage) + labels JSON

```python
# Cell 4 - Export the trained model to Core ML for iOS
import json, shutil
from pathlib import Path
import yaml
from ultralytics import YOLO

best = YOLO(str(BEST))
# NOTE: nms=True is NOT supported for *segmentation* Core ML export, so NMS is
# performed on-device in Swift (YOLOSegmentationService). Export raw outputs.
mlpackage = best.export(format='coreml', nms=False, imgsz=640, half=True)
print('Core ML ->', mlpackage)
print('Rename the .mlpackage to FoodSegYolo.mlpackage before adding it to iOS.')

# Write the class label map iOS reads (index -> name), matching the existing
# FoodSegmentationLabels.json convention.
names = yaml.safe_load((YOLO_DIR / 'data.yaml').read_text())['names']
labels = {str(k): v for k, v in names.items()}
out = Path('/kaggle/working/FoodSegYolo')
out.mkdir(exist_ok=True)
shutil.copytree(mlpackage, out / Path(mlpackage).name, dirs_exist_ok=True)
(out / 'FoodSegmentationLabels.json').write_text(json.dumps(labels, indent=2))

# Zip for download from the Kaggle output panel.
shutil.make_archive('/kaggle/working/FoodSegYolo', 'zip', out)
print('Download /kaggle/working/FoodSegYolo.zip from the Output tab.')
```

## Cell 5 - Export the nateraw/food ViT classifier (zipped as FoodClassifier)

```python
# Cell 5 - Fine-grained Food-101 classifier -> Core ML classifier model.
# Runs ONCE per scan on-device (see FoodClassifierService.swift), so a ViT is
# affordable. ~165 MB at FP16 — large; swap REPO for a MobileViT/EfficientFormer
# Food-101 checkpoint if you need a lighter model.
!pip install -q transformers coremltools

import json, shutil
from pathlib import Path
import numpy as np
import torch
import coremltools as ct
from transformers import AutoModelForImageClassification, AutoImageProcessor

REPO = 'nateraw/food'
processor = AutoImageProcessor.from_pretrained(REPO)
model = AutoModelForImageClassification.from_pretrained(REPO).eval()

size = 224
mean = list(map(float, processor.image_mean))
std = list(map(float, processor.image_std))

# Bake the per-channel ViT normalisation INTO the graph (Core ML ImageType
# `scale` is scalar-only and cannot express per-channel std). Swift then just
# hands raw RGB pixels to the model.
class Wrapped(torch.nn.Module):
    def __init__(self, m, mean, std):
        super().__init__()
        self.m = m
        self.register_buffer('mean', torch.tensor(mean).view(1, 3, 1, 1))
        self.register_buffer('std', torch.tensor(std).view(1, 3, 1, 1))

    def forward(self, x):          # x in [0,1] from ImageType scale=1/255
        x = (x - self.mean) / self.std
        return self.m(pixel_values=x).logits

wrapped = Wrapped(model, mean, std).eval()
traced = torch.jit.trace(wrapped, torch.rand(1, 3, size, size))

labels = [model.config.id2label[i] for i in range(len(model.config.id2label))]

mlmodel = ct.convert(
    traced,
    inputs=[ct.ImageType(name='image', shape=(1, 3, size, size),
                         scale=1 / 255.0, bias=[0.0, 0.0, 0.0],
                         color_layout=ct.colorlayout.RGB)],
    classifier_config=ct.ClassifierConfig(labels),  # -> VNClassificationObservation
    minimum_deployment_target=ct.target.iOS17,
    compute_precision=ct.precision.FLOAT16,
    convert_to='mlprogram',
)
mlmodel.short_description = 'Food-101 ViT classifier (nateraw/food)'

out = Path('/kaggle/working/FoodClassifier')
out.mkdir(exist_ok=True)
mlmodel.save(str(out / 'FoodClassifier.mlpackage'))
(out / 'FoodClassifierLabels.json').write_text(
    json.dumps({str(i): l for i, l in enumerate(labels)}, indent=2)
)
shutil.make_archive('/kaggle/working/FoodClassifier', 'zip', out)
print('Download /kaggle/working/FoodClassifier.zip from the Output tab.')
print('On the Mac: xcrun coremlcompiler compile FoodClassifier.mlpackage ios/Runner/')
print('Then drag ios/Runner/FoodClassifier.mlmodelc into the Runner target.')
```

## Notes

- **Reality check on accuracy:** FoodSeg103/154 has 100+ fine-grained, imbalanced
  classes, so per-class mIoU/mAP is modest even at SOTA (~45% mIoU is near the
  published ceiling). YOLO11-seg won't make that number huge, but it converges in
  a fraction of the epochs and runs much faster on-device. If you only need
  density-bucket accuracy for volume→calories, consider merging rare classes in
  `category_id.txt` before converting — that is the single biggest accuracy lever.
- **iOS wiring (done):** `ios/Runner/Scanner/YOLOSegmentationService.swift` already
  decodes the raw outputs, runs manual class-aware NMS, assembles the prototype
  masks, and emits the same `SegmentedObject` contract the depth/volume pipeline
  uses — so `DepthFusion` turns the 2-D masks into 3-D volume unchanged. To
  activate it: compile and bundle the trained export as `FoodSegYolo.mlmodelc`:

  ```bash
  xcrun coremlcompiler compile FoodSegYolo.mlpackage ios/Runner/
  # then drag ios/Runner/FoodSegYolo.mlmodelc into the Runner target in Xcode
  ```

  `InferencePipeline` auto-selects the YOLO path when that model is present and
  falls back to SegFormer otherwise.
