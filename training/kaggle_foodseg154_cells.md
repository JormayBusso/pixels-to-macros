# Kaggle Cells: FoodSeg154 SegFormer-B2 Training

Set Kaggle accelerator to **GPU T4 x2**. Start this SegFormer run fresh; do not resume from the old ResNet checkpoint.

## Cell 1 - Clone, Install, and Check GPUs

```python
# Cell 1 - Clone repo and install dependencies
!git clone https://github.com/JormayBusso/pixels-to-macros.git
%cd pixels-to-macros

!git fetch --all
!git reset --hard origin/dev

!pip install -q --upgrade pip
!pip install -q segmentation-models-pytorch timm datasets transformers albumentations opencv-python-headless safetensors tqdm Pillow
!grep -vE '^torch|^torchvision|coremltools' training/requirements.txt > /tmp/kaggle_reqs.txt
!pip install -q -r /tmp/kaggle_reqs.txt

import torch
print('CUDA:', torch.cuda.is_available())
print('GPU count:', torch.cuda.device_count())
for i in range(torch.cuda.device_count()):
  print(i, torch.cuda.get_device_name(i))
```

## Cell 2 - Prepare FoodSeg154 and Clean Directory

```python
# Cell 2 - Prepare FoodSeg154 and set up fresh environment
from pathlib import Path

!python scripts/download_hf_foodseg154.py || true

candidates = [
  Path('./data/FoodSeg154'),
  Path('/kaggle/input/foodseg154/FoodSeg154'),
  Path('/kaggle/input/foodseg154'),
  Path('/kaggle/input/foodseg-154/FoodSeg154'),
  Path('/kaggle/input/foodseg-154'),
]
DATA_DIR = next((path for path in candidates if path.exists()), None)
assert DATA_DIR is not None, 'Add FoodSeg154 as a Kaggle input or set DATA_DIR manually.'

# Created a new folder name specifically for this SegFormer run
OUTPUT_DIR = Path('/kaggle/working/pixels-to-macros-segformer-154')
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

print('DATA_DIR =', DATA_DIR)
print('OUTPUT_DIR =', OUTPUT_DIR)
print('🚀 Ready to start fresh SegFormer training!')
```

## Cell 3 - Train SegFormer-B2

```python
# Cell 3 - Train SegFormer-B2 on FoodSeg154 (Fresh Start)
from pathlib import Path

MODEL       = 'nvidia/segformer-b2-finetuned-ade-512-512'
EPOCHS      = 80
BATCH_SIZE  = 8   # If Kaggle throws a CUDA OutOfMemory error, drop this to 4
IMG_SIZE    = 512
LR          = 6e-5
NUM_WORKERS = 2
MULTIPLIER  = 3
VAL_EVERY   = 3

!python training/train.py \
  --data_dir       {DATA_DIR} \
  --output_dir     {OUTPUT_DIR} \
  --model_name     {MODEL} \
  --num_classes    155 \
  --epochs         {EPOCHS} \
  --batch_size     {BATCH_SIZE} \
  --img_size       {IMG_SIZE} \
  --lr             {LR} \
  --num_workers    {NUM_WORKERS} \
  --val_every      {VAL_EVERY} \
  --virtual_train_multiplier {MULTIPLIER} \
  --save_every_secs 300
```

## Cell 4 - Inspect and zip outputs

```python
# Cell 4 - Inspect and zip outputs
!ls -lh /kaggle/working/pixels-to-macros-segformer-154
!tail -n 20 /kaggle/working/pixels-to-macros-segformer-154/metrics.json || true
!cd /kaggle/working && zip -r pixels-to-macros-segformer-154.zip pixels-to-macros-segformer-154
```
