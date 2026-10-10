import coremltools as ct
import numpy as np
from PIL import Image

# The exact bundled, compiled model that ships in the app.
model = ct.models.CompiledMLModel('ios/Runner/FoodSegYolo.mlmodelc')

# Input feature name + size from the spec of a fresh reference (compiled models
# don't expose a spec, so read names from metadata we already saw: input is an
# image). Try common names.
spec_in = None
try:
    spec_in = model.get_spec().description.input  # may fail for compiled
except Exception as e:
    print('no spec on compiled model:', e)

# Build a clean tomato-on-white-plate image at 640x640 (the model input size).
src = Image.open('data/FoodSeg103/Images/img_dir/test/00002.jpg').convert('RGB')
w, h = src.size
food = src.crop((int(0.01 * w), int(0.05 * h), int(0.40 * w), int(0.32 * h)))
plate = Image.new('RGB', (640, 640), (244, 244, 244))
fw = int(640 * 0.45); fh = int(fw * food.height / food.width)
plate.paste(food.resize((fw, fh)), ((640 - fw) // 2, (640 - fh) // 2))

for in_name in ['image', 'input', 'input_1', 'x', 'images']:
    try:
        out = model.predict({in_name: plate})
        print('INPUT NAME =', in_name)
        for k, v in out.items():
            arr = np.array(v)
            print(' out', k, arr.shape)
        # find the [1,139,8400] det tensor
        det = None
        for k, v in out.items():
            arr = np.array(v)
            if arr.ndim == 3 and arr.shape[1] == 139:
                det = arr[0]  # (139, 8400)
        if det is not None:
            box = det[:4, :]      # cx,cy,w,h rows
            cls = det[4:4+103, :]  # class scores
            print('BOX coord range: min=%.3f max=%.3f  (>~1 => pixel space, ~0-1 => normalized)' % (box.min(), box.max()))
            print('CLASS score range: min=%.3f max=%.3f' % (cls.min(), cls.max()))
            best_anchor = cls.max(axis=0).argmax()
            best_cls = cls[:, best_anchor].argmax()
            print('top anchor: class_idx=%d score=%.3f cx=%.1f cy=%.1f w=%.1f h=%.1f' % (
                best_cls, cls[:, best_anchor].max(),
                box[0, best_anchor], box[1, best_anchor], box[2, best_anchor], box[3, best_anchor]))
        break
    except Exception as e:
        print('input name', in_name, 'failed:', str(e)[:80])
