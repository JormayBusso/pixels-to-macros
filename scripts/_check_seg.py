import sys, glob, numpy as np
from ultralytics import YOLO

m = YOLO('best.pt')
imgs = sorted(glob.glob('data/FoodSeg103/Images/img_dir/test/*.jpg'))[:4]
print('testing', len(imgs), 'FoodSeg103 test images (in-distribution)')
for i, p in enumerate(imgs):
    r = m.predict(p, imgsz=640, conf=0.20, verbose=False)[0]
    n = 0 if r.masks is None else len(r.masks)
    print(f'\n--- {p.split("/")[-1]}: {n} detections ---')
    if r.boxes is not None:
        for b, c in zip(r.boxes.conf.tolist(), r.boxes.cls.tolist()):
            print(f'   {m.names[int(c)]:20s} conf={b:.2f}')
    r.save(filename=f'/tmp/seg_test_{i}.jpg')
print('\noverlays saved to /tmp/seg_test_0..3.jpg')
