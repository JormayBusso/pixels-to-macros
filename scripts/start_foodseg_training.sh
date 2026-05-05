#!/bin/zsh
# Launch FoodSeg103 training in background, write PID, and stream nothing.
cd "$(dirname "$0")/.."
source .venv/bin/activate
nohup python training/train.py \
  --data_dir ./data/FoodSeg103 \
  --epochs 40 \
  --batch_size 4 \
  --num_workers 0 \
  --img_size 513 \
  --lr 5e-4 \
  --patience 10 \
  > /tmp/foodseg_train.log 2>&1 &
TRAIN_PID=$!
disown
echo "$TRAIN_PID" > /tmp/foodseg_train.pid
echo "Started PID $TRAIN_PID, log /tmp/foodseg_train.log"
