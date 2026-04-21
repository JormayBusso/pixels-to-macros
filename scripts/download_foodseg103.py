"""
scripts/download_foodseg103.py
------------------------------
Downloads and extracts the real FoodSeg103 dataset.

FoodSeg103: 7,118 food images, 103 food categories.
Paper: "A Large-Scale Benchmark for Food Image Segmentation" (Wu et al. 2021)
Official repo: https://github.com/LARC-CMU-SMU/FoodSeg103-Benchmark-v1

Usage (from repo root):
    pip install gdown
    python scripts/download_foodseg103.py

Output:
    data/FoodSeg103/
        Images/img_dir/train/*.jpg   (4,983 images)
        Images/img_dir/test/*.jpg    (2,135 images)
        Annotations/ann_dir/train/*.png
        Annotations/ann_dir/test/*.png
        category_id.txt
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path


DATASET_DIR = Path("data/FoodSeg103")
# Official FoodSeg103 release on Google Drive
GDRIVE_FILE_ID = "1sZ_d5PKAeJ5J5ZjNRDNFrXgmSBYM8ax4"
ZIP_NAME = "FoodSeg103.zip"


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
57 bread
58 corn
59 hamburg
60 pizza
61 hanamaki baozi
62 wonton dumplings
63 taro
64 rice
65 tofu
66 eggplant
67 potato
68 garlic
69 cauliflower
70 tomato
71 kelp
72 seaweed
73 spring onion
74 rape
75 ginger
76 okra
77 lettuce
78 pumpkin
79 cucumber
80 white radish
81 carrot
82 asparagus
83 bamboo shoots
84 broccoli
85 celery stick
86 cilantro mint
87 snow peas
88 cabbage
89 bean sprouts
90 onion
91 pepper
92 green beans
93 french beans
94 king oyster mushroom
95 white mushroom
96 shiitake
97 enoki mushroom
98 oyster mushroom
99 black fungus
100 dough
101 noodles
102 rice noodle
103 others
"""


def install_gdown() -> None:
    print("Installing gdown...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "gdown", "--quiet"])


def download() -> Path:
    try:
        import gdown
    except ImportError:
        install_gdown()
        import gdown

    zip_path = Path(ZIP_NAME)
    if zip_path.exists():
        print(f"Archive already exists: {zip_path} — skipping download.")
        return zip_path

    print(f"Downloading FoodSeg103 (~1.3 GB) from Google Drive...")
    url = f"https://drive.google.com/uc?id={GDRIVE_FILE_ID}"
    gdown.download(url, str(zip_path), quiet=False)
    return zip_path


def extract(zip_path: Path) -> None:
    print(f"\nExtracting {zip_path} → data/ ...")
    with zipfile.ZipFile(zip_path, "r") as zf:
        members = zf.namelist()
        total = len(members)
        for i, member in enumerate(members, 1):
            zf.extract(member, "data/")
            if i % 500 == 0:
                print(f"  {i}/{total} files extracted")
    print(f"  Done — {total} files extracted.")


def write_category_file() -> None:
    cat_file = DATASET_DIR / "category_id.txt"
    if not cat_file.exists():
        cat_file.write_text(CATEGORY_ID_TXT)
        print(f"Wrote {cat_file}")


def verify() -> None:
    train_imgs = list((DATASET_DIR / "Images" / "img_dir" / "train").glob("*.jpg"))
    test_imgs  = list((DATASET_DIR / "Images" / "img_dir" / "test").glob("*.jpg"))
    train_mask = list((DATASET_DIR / "Annotations" / "ann_dir" / "train").glob("*.png"))
    test_mask  = list((DATASET_DIR / "Annotations" / "ann_dir" / "test").glob("*.png"))

    print(f"\nDataset summary:")
    print(f"  Train images : {len(train_imgs)}")
    print(f"  Test  images : {len(test_imgs)}")
    print(f"  Train masks  : {len(train_mask)}")
    print(f"  Test  masks  : {len(test_mask)}")

    if len(train_imgs) == 0:
        print("\nWARNING: No images found. Check the extracted folder structure.")
        print(f"Expected: {DATASET_DIR}/Images/img_dir/train/")
    else:
        print("\nDataset is ready for training!")
        print("\nRun training with:")
        print("  python training/train.py \\")
        print(f"      --data_dir ./{DATASET_DIR} \\")
        print("      --epochs 50 --batch_size 4 --num_workers 0")


def main() -> None:
    DATASET_DIR.mkdir(parents=True, exist_ok=True)

    # If already extracted, skip download
    train_dir = DATASET_DIR / "Images" / "img_dir" / "train"
    if train_dir.exists() and any(train_dir.glob("*.jpg")):
        print("Dataset already extracted.")
        write_category_file()
        verify()
        return

    zip_path = download()
    extract(zip_path)
    write_category_file()
    verify()

    # Clean up zip to save space
    answer = input(f"\nDelete the {zip_path} archive to save ~1.3 GB? [y/N]: ").strip().lower()
    if answer == "y":
        zip_path.unlink()
        print("Archive deleted.")


if __name__ == "__main__":
    main()
