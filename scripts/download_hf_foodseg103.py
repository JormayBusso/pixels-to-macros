"""
scripts/download_hf_foodseg103.py
----------------------------------
Downloads FoodSeg103 from Hugging Face (EduardoPacheco/FoodSeg103)
and saves it in the folder layout expected by training/train.py:

    data/FoodSeg103/
        Images/img_dir/train/XXXXX.jpg
        Images/img_dir/test/XXXXX.jpg
        Annotations/ann_dir/train/XXXXX.png
        Annotations/ann_dir/test/XXXXX.png
        category_id.txt

Usage (from repo root):
    pip install datasets Pillow
    python scripts/download_hf_foodseg103.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


DATASET_DIR = Path("data/FoodSeg103")
HF_DATASET  = "EduardoPacheco/FoodSeg103"

CATEGORY_ID_TXT = """\
0 background
1 candy
2 egg tart
3 french fries
4 chocolate
5 biscuit
6 popcorn
7 pudding
8 ice cream
9 cheese butter
10 cake
11 wine
12 milkshake
13 coffee
14 juice
15 milk
16 tea
17 almond
18 red beans
19 cashew
20 dried cranberries
21 soy
22 walnut
23 peanut
24 egg
25 apple
26 date
27 apricot
28 avocado
29 banana
30 strawberry
31 cherry
32 blueberry
33 raspberry
34 mango
35 olives
36 peach
37 lemon
38 pear
39 fig
40 pineapple
41 grape
42 kiwi
43 melon
44 orange
45 watermelon
46 steak
47 pork
48 chicken duck
49 sausage
50 fried meat
51 lamb
52 sauce
53 crab
54 fish
55 shellfish
56 shrimp
57 soup
58 bread
59 corn
60 hamburg
61 pizza
62 hanamaki baozi
63 wonton dumplings
64 pasta
65 noodles
66 rice
67 pie
68 tofu
69 eggplant
70 potato
71 garlic
72 cauliflower
73 tomato
74 kelp
75 seaweed
76 spring onion
77 rape
78 ginger
79 okra
80 lettuce
81 pumpkin
82 cucumber
83 white radish
84 carrot
85 asparagus
86 bamboo shoots
87 broccoli
88 celery stick
89 cilantro mint
90 snow peas
91 cabbage
92 bean sprouts
93 onion
94 pepper
95 green beans
96 french beans
97 king oyster mushroom
98 shiitake
99 enoki mushroom
100 oyster mushroom
101 white button mushroom
102 salad
103 other ingredients
"""


def ensure_packages() -> None:
    for pkg in ("datasets", "Pillow"):
        try:
            __import__(pkg.lower().replace("-", "_"))
        except ImportError:
            print(f"Installing {pkg} …")
            subprocess.check_call(
                [sys.executable, "-m", "pip", "install", pkg, "--quiet"]
            )


def convert_split(ds_split, split_name: str) -> None:
    img_dir  = DATASET_DIR / "Images"      / "img_dir"  / split_name
    ann_dir  = DATASET_DIR / "Annotations" / "ann_dir"  / split_name
    img_dir.mkdir(parents=True, exist_ok=True)
    ann_dir.mkdir(parents=True, exist_ok=True)

    total = len(ds_split)
    print(f"\n[{split_name}] saving {total} image/mask pairs …")
    for i, row in enumerate(ds_split):
        name  = f"{i:05d}"

        # Image — save as JPEG
        img = row["image"]
        if img.mode != "RGB":
            img = img.convert("RGB")
        img.save(img_dir / f"{name}.jpg", "JPEG", quality=95)

        # Mask — palette/L PNG (pixel value = class index)
        mask = row["label"]
        mask.save(ann_dir / f"{name}.png")

        if (i + 1) % 500 == 0 or (i + 1) == total:
            print(f"  {i + 1}/{total}")

    print(f"  [{split_name}] done.")


def verify() -> None:
    for split in ("train", "test"):
        imgs  = list((DATASET_DIR / "Images"      / "img_dir"  / split).glob("*.jpg"))
        masks = list((DATASET_DIR / "Annotations" / "ann_dir"  / split).glob("*.png"))
        print(f"  {split:5s}: {len(imgs)} images, {len(masks)} masks")


def main() -> None:
    ensure_packages()

    from datasets import load_dataset  # noqa: PLC0415

    # Check if already done
    train_dir = DATASET_DIR / "Images" / "img_dir" / "train"
    if train_dir.exists() and len(list(train_dir.glob("*.jpg"))) > 4000:
        print("Dataset already present — skipping download.")
        verify()
        return

    DATASET_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Loading {HF_DATASET} from Hugging Face …")
    print("(This will stream ~1.25 GB — may take a few minutes)\n")

    ds = load_dataset(HF_DATASET)   # returns DatasetDict with 'train' / 'validation'

    # HF uses 'validation'; our training script expects 'test' folder
    split_map = {
        "train":      "train",
        "validation": "test",
    }
    for hf_split, folder in split_map.items():
        if hf_split in ds:
            convert_split(ds[hf_split], folder)
        else:
            print(f"  WARNING: split '{hf_split}' not found in dataset — skipping.")

    # Write category file
    cat_file = DATASET_DIR / "category_id.txt"
    cat_file.write_text(CATEGORY_ID_TXT)
    print(f"\nWrote {cat_file}")

    print("\n=== Dataset summary ===")
    verify()

    print("\n=== Ready! Run training with: ===")
    print("  python training/train.py \\")
    print(f"      --data_dir ./{DATASET_DIR} \\")
    print("      --epochs 50 --batch_size 4 --num_workers 0")


if __name__ == "__main__":
    main()
