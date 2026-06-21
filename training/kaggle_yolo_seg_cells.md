# Kaggle Cells: FoodSeg → YOLO11-seg (Core ML) Training

Set the Kaggle accelerator to **GPU T4 x2** (training uses one GPU by default).

This is the `upgraded`-branch path: a YOLO11-seg instance-segmentation model that
trains far faster than SegFormer (COCO-pretrained) and exports straight to Core ML
with `format=coreml nms=True`. It trains on the **same FoodSeg dataset** — there is
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

results = model.train(
    data='/kaggle/working/foodseg_yolo/data.yaml',
    epochs=100,
    imgsz=640,
    batch=16,          # drop to 8 if you hit CUDA OutOfMemory
    device=0,          # single T4. For T4x2 DDP use device=[0, 1]
    patience=25,       # early stop if val mAP plateaus
    cos_lr=True,
    close_mosaic=10,
    project='/kaggle/working/runs',
    name='foodseg_yolo11s',
)

BEST = Path(results.save_dir) / 'weights' / 'best.pt'
print('best weights ->', BEST)
```

## Cell 4 - Export to Core ML (.mlpackage) + labels JSON

```python
# Cell 4 - Export the trained model to Core ML for iOS
import json, shutil
from pathlib import Path
import yaml
from ultralytics import YOLO

best = YOLO(str(BEST))
# nms=True bakes non-max-suppression into the model so iOS gets clean detections.
mlpackage = best.export(format='coreml', nms=True, imgsz=640, half=True)
print('Core ML ->', mlpackage)

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

## Notes

- **Reality check on accuracy:** FoodSeg103/154 has 100+ fine-grained, imbalanced
  classes, so per-class mIoU/mAP is modest even at SOTA (~45% mIoU is near the
  published ceiling). YOLO11-seg won't make that number huge, but it converges in
  a fraction of the epochs and runs much faster on-device. If you only need
  density-bucket accuracy for volume→calories, consider merging rare classes in
  `category_id.txt` before converting — that is the single biggest accuracy lever.
- **iOS wiring (Phase 2):** the current Swift `SegmentationService` expects a dense
  `[1, C, 512, 512]` semantic tensor. A YOLO-seg Core ML model outputs
  detections + prototype masks instead, so `SegmentationService` and
  `DepthFusion.assignLabels` need a one-time rewrite to composite YOLO instance
  masks into the per-pixel label grid. Do that against the real exported
  `.mlpackage` so the output tensor names/shapes match exactly.
