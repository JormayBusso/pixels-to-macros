# %% [markdown]
# # Pixels to Macros - FoodSeg154 SegFormer-B2 Training
# Run these cells in Kaggle with GPU accelerator set to **GPU T4 x2**.

# %%
# Cell 1 - Install dependencies
!pip install -q transformers albumentations segmentation-models-pytorch opencv-python-headless safetensors tqdm Pillow

# %%
# Cell 2 - Check GPUs
import torch
print('CUDA:', torch.cuda.is_available())
print('GPU count:', torch.cuda.device_count())
for i in range(torch.cuda.device_count()):
    print(i, torch.cuda.get_device_name(i))

# %%
# Cell 3 - Locate your dataset
# Add FoodSeg154 as a Kaggle input dataset, then adjust this path if needed.
from pathlib import Path

candidates = [
    Path('/kaggle/input/foodseg154/FoodSeg154'),
    Path('/kaggle/input/foodseg154'),
    Path('/kaggle/input/foodseg-154/FoodSeg154'),
    Path('/kaggle/input/foodseg-154'),
]
DATA_DIR = next((p for p in candidates if p.exists()), None)
print('DATA_DIR =', DATA_DIR)
assert DATA_DIR is not None, 'Set DATA_DIR to the folder containing FoodSeg154 images/masks.'

# %%
# Cell 4 - Bring in the training script
# Option A: upload this repo as a Kaggle dataset and set REPO_DIR to it.
# Option B: paste training/train.py into /kaggle/working/train.py.
from pathlib import Path
import shutil

REPO_DIR = Path('/kaggle/input/pixels-to-macros')
if (REPO_DIR / 'training' / 'train.py').exists():
    shutil.copy(REPO_DIR / 'training' / 'train.py', '/kaggle/working/train.py')
else:
    print('Upload the repo or paste training/train.py into /kaggle/working/train.py')

# %%
# Cell 5 - Start professional training
# If CUDA OOM happens, reduce --batch-size to 4.
!python /kaggle/working/train.py \
  --data-dir "$DATA_DIR" \
  --output-dir /kaggle/working/foodseg154_segformer_b2 \
  --model-name nvidia/segformer-b2-finetuned-ade-512-512 \
  --num-labels 155 \
  --img-size 512 \
  --epochs 80 \
  --batch-size 8 \
  --workers 2 \
  --lr 6e-5 \
  --weight-decay 0.01 \
  --checkpoint-seconds 300

# %%
# Cell 6 - Resume after a Kaggle crash or disconnect
from pathlib import Path
ckpt = Path('/kaggle/working/foodseg154_segformer_b2/last_checkpoint.pth')
print('Resume checkpoint exists:', ckpt.exists(), ckpt)

# Uncomment to resume:
# !python /kaggle/working/train.py \
#   --data-dir "$DATA_DIR" \
#   --output-dir /kaggle/working/foodseg154_segformer_b2 \
#   --model-name nvidia/segformer-b2-finetuned-ade-512-512 \
#   --num-labels 155 \
#   --img-size 512 \
#   --epochs 80 \
#   --batch-size 8 \
#   --workers 2 \
#   --lr 6e-5 \
#   --weight-decay 0.01 \
#   --checkpoint-seconds 300 \
#   --resume /kaggle/working/foodseg154_segformer_b2/last_checkpoint.pth

# %%
# Cell 7 - Inspect best model output files
!ls -lh /kaggle/working/foodseg154_segformer_b2
!tail -n 40 /kaggle/working/foodseg154_segformer_b2/metrics.json

# %%
# Cell 8 - Zip artifacts for download
!cd /kaggle/working && zip -r foodseg154_segformer_b2_artifacts.zip foodseg154_segformer_b2
