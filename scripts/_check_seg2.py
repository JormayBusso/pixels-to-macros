from ultralytics import YOLO
from PIL import Image

m = YOLO('best.pt')

# Real food crop placed on a large WHITE plate at shrinking sizes — reproduces
# the app's case: one small food on a bare plate (out-of-distribution vs
# FoodSeg103's full plates).
src = Image.open('data/FoodSeg103/Images/img_dir/test/00002.jpg').convert('RGB')
w, h = src.size
food = src.crop((int(0.01 * w), int(0.05 * h), int(0.40 * w), int(0.32 * h)))  # tomato cluster

for name, frac in [('A_fills70', 0.70), ('B_half50', 0.50), ('C_small30', 0.30), ('D_tiny15', 0.15)]:
    plate = Image.new('RGB', (600, 600), (244, 244, 244))
    fw = int(600 * frac)
    fh = int(fw * food.height / food.width)
    plate.paste(food.resize((fw, fh)), ((600 - fw) // 2, (600 - fh) // 2))
    r = m.predict(plate, imgsz=640, conf=0.20, verbose=False)[0]
    dets = ([(m.names[int(c)], round(float(b), 2)) for b, c in zip(r.boxes.conf, r.boxes.cls)]
            if r.boxes is not None else [])
    print(f'{name}: {dets}')
    r.save(filename=f'/tmp/plate_{name}.jpg')
