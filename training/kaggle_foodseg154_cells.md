# Kaggle Cells: FoodSeg154 SegFormer-B2 Training

Set Kaggle accelerator to **GPU T4 x2**. Add your previous checkpoint as a Kaggle input if you want to resume.

## Cell 1 - Clone repo and install

```python
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

## Cell 2 - Prepare FoodSeg154 and checkpoint

```python
from pathlib import Path
import shutil

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

OUTPUT_DIR = Path('/kaggle/working/pixels-to-macros-foodseg154')
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

checkpoint_candidates = [
  Path('/kaggle/input/datasets/jormay/my-food-weights/last_checkpoint-4.pth'),
  Path('/kaggle/input/my-food-weights/last_checkpoint-4.pth'),
  Path('/kaggle/input/my-food-weights/last_checkpoint.pth'),
]
resume_path = OUTPUT_DIR / 'last_checkpoint.pth'
for checkpoint in checkpoint_candidates:
  if checkpoint.exists():
    shutil.copy(checkpoint, resume_path)
    print('Checkpoint copied:', resume_path)
    break
else:
  print('No previous checkpoint found; training will start fresh.')

print('DATA_DIR =', DATA_DIR)
print('OUTPUT_DIR =', OUTPUT_DIR)
```

## Cell 3 - Train SegFormer-B2

```python
from pathlib import Path

MODEL       = 'nvidia/segformer-b2-finetuned-ade-512-512'
EPOCHS      = 80
BATCH_SIZE  = 8   # use 4 if Kaggle runs out of memory
IMG_SIZE    = 512
LR          = 6e-5
NUM_WORKERS = 2
MULTIPLIER  = 3
VAL_EVERY   = 3

resume_arg = ''
resume_path = Path('/kaggle/working/pixels-to-macros-foodseg154/last_checkpoint.pth')
if resume_path.exists():
  resume_arg = f'--resume {resume_path}'

!python training/train.py \
  --data_dir       {DATA_DIR} \
  --output_dir     {OUTPUT_DIR} \
  --model_name     {MODEL} \
  --num-labels     155 \
  --epochs         {EPOCHS} \
  --batch_size     {BATCH_SIZE} \
  --img_size       {IMG_SIZE} \
  --lr             {LR} \
  --num_workers    {NUM_WORKERS} \
  --val_every      {VAL_EVERY} \
  --virtual_train_multiplier {MULTIPLIER} \
  --save_every_secs 300 \
  {resume_arg}
```

## Cell 4 - Inspect and zip outputs

```python
!ls -lh /kaggle/working/pixels-to-macros-foodseg154
!tail -n 80 /kaggle/working/pixels-to-macros-foodseg154/metrics.json
!cd /kaggle/working && zip -r pixels-to-macros-foodseg154.zip pixels-to-macros-foodseg154
```
