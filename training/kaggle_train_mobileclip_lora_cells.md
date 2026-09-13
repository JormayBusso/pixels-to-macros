# Kaggle Cells: MobileCLIP2 LoRA fine-tuning on Food-101

Set the Kaggle accelerator to **GPU T4** (Settings → Accelerator). A single T4 is
enough — `training/train_mobileclip_lora.py` trains LoRA adapters on the image
encoder only (the text tower is frozen), so it is far lighter than a full
fine-tune.

This produces a LoRA adapter checkpoint that can be evaluated against the
already-corrected zero-shot baseline (**90.33% top-1** on a 300-sample Food-101
test subset, measured this session after fixing `training/export_mobileclip.py`'s
image-normalisation bug) before deciding whether to bundle it on-device.

## Cell 1 — Clone repo (upgraded branch) and install deps

```python
# Cell 1 - Clone repo and install training deps
!git clone https://github.com/JormayBusso/pixels-to-macros.git
%cd pixels-to-macros

!git fetch --all
!git checkout upgraded
!git reset --hard origin/upgraded

!pip install -q --upgrade pip
# Kaggle preinstalls torchao 0.10.0. peft's LoRA dispatcher unconditionally
# calls is_torchao_available(), which *raises* ImportError (not False) on a
# too-old torchao even though this model never touches torchao-quantized
# layers -> must upgrade torchao or `attach_image_encoder_lora` crashes.
!pip install -q --upgrade "torchao>0.16.0"
!pip install -q coremltools
!pip install -q open_clip_torch huggingface_hub timm peft accelerate torchvision

import torch
print('CUDA:', torch.cuda.is_available(), '| GPUs:', torch.cuda.device_count())
```

## Cell 2 — Train LoRA adapters on full Food-101

`torchvision.datasets.Food101` auto-downloads the full 101-class dataset
(~5GB) into `--data-dir` on first run. Defaults: `MobileCLIP-S2` (matches the
production export), rank-16 LoRA, 10 epochs, batch size 64, lr 1e-4 — these are
the script's own defaults, tuned as a reasonable starting point; adjust epochs
downward first if a run doesn't finish inside your Kaggle session time budget
(so you keep a usable adapter rather than losing the whole run).

```python
# Cell 2 - Full LoRA fine-tune run (auto-downloads MobileCLIP2-S2 + Food-101)
!python training/train_mobileclip_lora.py \
    --data-dir /kaggle/working/food101_data \
    --output-dir /kaggle/working/mobileclip_lora \
    --epochs 10 --batch-size 64 --lr 1e-4 --lora-rank 16
```

Checkpoints (`adapter_model.safetensors` + `adapter_config.json`) land in
`/kaggle/working/mobileclip_lora/` after each save interval (per
`--checkpoint-seconds`, script default) and again at the end of training — the
final checkpoint is what Cell 3 evaluates.

## Cell 3 — Evaluate the LoRA checkpoint against the zero-shot baseline

Runs the same eval harness twice: once on the full held-out Food-101 test split
with **no adapter** (reproducing this session's 90.33%-class baseline, but on
the FULL test set rather than the 300-sample subset used to establish it
quickly), then once **with** the LoRA adapter, so the two numbers are directly
comparable on the same metric and same data.

```python
# Cell 3a - Baseline (no LoRA), full official Food-101 test split (25,250 images)
!python training/eval_mobileclip_lora.py \
    --data-root /kaggle/working/food101_data \
    --batch-size 64

# Cell 3b - LoRA-adapted checkpoint, same full test split
!python training/eval_mobileclip_lora.py \
    --data-root /kaggle/working/food101_data \
    --lora-checkpoint /kaggle/working/mobileclip_lora \
    --batch-size 64
```

Compare the two `Top-1 accuracy: NN.NN%` lines printed at the end of each cell.
Only proceed to bundling the adapter on-device (a separate, blocked todo —
`finetune-mobileclip-lora-4` — requiring another explicit go-ahead) if the LoRA
run **measurably beats** the no-LoRA baseline; if it doesn't, that is itself a
useful, reportable finding — do not force a regression into the app.

## Cell 4 — Download the adapter checkpoint

```python
# Cell 4 - Zip the adapter for download from the Kaggle output pane
import shutil
shutil.make_archive('/kaggle/working/mobileclip_lora_adapter', 'zip', '/kaggle/working/mobileclip_lora')
print('Download /kaggle/working/mobileclip_lora_adapter.zip from the Output tab.')
```

## Notes

- If the T4 session times out mid-training, `train_mobileclip_lora.py` saves
  checkpoints periodically (`--checkpoint-seconds`, default in the script) to
  `--output-dir`, so a restarted Cell 2 run is not a total loss — check the
  script's own resume behaviour (`--help`) before restarting from scratch.
- `--data-dir` is intentionally set to `/kaggle/working/...` (not the repo's
  own `training/data/`, which is gitignored and meant for local runs) so the
  ~5GB Food-101 download lands in Kaggle's writable working directory.
- This notebook does not touch the app bundle or commit anything — it only
  produces a checkpoint for you to evaluate and, if it helps, hand back for
  bundling in a later, separately-approved step.
