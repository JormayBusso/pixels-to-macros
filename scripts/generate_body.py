"""Generate a clean anatomical body outline PNG for the body map screen.

Output: assets/body_outline.png  (600 × 960, RGBA)
"""
from __future__ import annotations
import math
from PIL import Image, ImageDraw, ImageFilter
import os

W, H = 600, 960

img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)


# ─── helpers ────────────────────────────────────────────────────────────────

def pt(fx: float, fy: float):
    return (fx * W, fy * H)


def ellipse_pts(cx: float, cy: float, rx: float, ry: float):
    x0, y0 = cx * W - rx * W, cy * H - ry * H
    x1, y1 = cx * W + rx * W, cy * H + ry * H
    return [(x0, y0), (x1, y1)]


BODY_FILL  = (220, 225, 235, 255)   # light blue-grey silhouette
BODY_EDGE  = (160, 170, 185, 255)   # outline
ORGAN_FILL = (245, 245, 250, 200)   # very light inner shapes
ORGAN_EDGE = (180, 185, 200, 255)


# ─── body silhouette ─────────────────────────────────────────────────────────
#  Drawn in layers, largest first so details sit on top.

def smooth_polygon(draw_obj, points, fill, outline, width=2):
    """Draw a polygon and soften with a small inner/outer outline pass."""
    draw_obj.polygon(points, fill=fill, outline=outline)


# ── Legs ──────────────────────────────────────────────────────────────────────
# Left leg (anatomically right on screen)
left_leg = [pt(0.355, 0.535), pt(0.435, 0.535), pt(0.430, 0.680),
            pt(0.425, 0.830), pt(0.415, 0.955), pt(0.330, 0.955),
            pt(0.320, 0.830), pt(0.315, 0.685)]
draw.polygon(left_leg, fill=BODY_FILL, outline=BODY_EDGE)

# Right leg
right_leg = [pt(0.565, 0.535), pt(0.645, 0.535), pt(0.680, 0.685),
             pt(0.680, 0.830), pt(0.670, 0.955), pt(0.580, 0.955),
             pt(0.570, 0.830), pt(0.565, 0.680)]
draw.polygon(right_leg, fill=BODY_FILL, outline=BODY_EDGE)

# ── Arms ──────────────────────────────────────────────────────────────────────
# Left arm
left_arm = [pt(0.165, 0.190), pt(0.290, 0.168), pt(0.300, 0.200),
            pt(0.285, 0.350), pt(0.270, 0.490), pt(0.215, 0.490),
            pt(0.195, 0.350), pt(0.150, 0.210)]
draw.polygon(left_arm, fill=BODY_FILL, outline=BODY_EDGE)

# Right arm
right_arm = [pt(0.835, 0.190), pt(0.710, 0.168), pt(0.700, 0.200),
             pt(0.715, 0.350), pt(0.730, 0.490), pt(0.785, 0.490),
             pt(0.805, 0.350), pt(0.850, 0.210)]
draw.polygon(right_arm, fill=BODY_FILL, outline=BODY_EDGE)

# ── Torso ────────────────────────────────────────────────────────────────────
torso = [pt(0.290, 0.155), pt(0.710, 0.155),
         pt(0.730, 0.280), pt(0.720, 0.400),
         pt(0.680, 0.535), pt(0.320, 0.535),
         pt(0.280, 0.400), pt(0.270, 0.280)]
draw.polygon(torso, fill=BODY_FILL, outline=BODY_EDGE)

# ── Neck ─────────────────────────────────────────────────────────────────────
draw.rectangle([pt(0.442, 0.118), pt(0.558, 0.162)], fill=BODY_FILL, outline=BODY_EDGE)

# ── Head ─────────────────────────────────────────────────────────────────────
draw.ellipse(ellipse_pts(0.500, 0.073, 0.115, 0.073), fill=BODY_FILL, outline=BODY_EDGE)

# Redraw torso/neck top edge over the gap
draw.line([pt(0.290, 0.155), pt(0.710, 0.155)], fill=BODY_EDGE, width=2)


# ─── internal organ outlines ─────────────────────────────────────────────────
#  Draw as dashed / outline-only so they appear as guide marks inside body.

def draw_organ(cx, cy, rx, ry, label=""):
    x0 = cx * W - rx * W
    y0 = cy * H - ry * H
    x1 = cx * W + rx * W
    y1 = cy * H + ry * H
    draw.ellipse([(x0, y0), (x1, y1)], fill=ORGAN_FILL, outline=ORGAN_EDGE, width=2)


# Brain (inside head)
draw_organ(0.500, 0.068, 0.080, 0.048)
# Eyes
draw_organ(0.461, 0.063, 0.022, 0.016)
draw_organ(0.539, 0.063, 0.022, 0.016)

# Left lung
draw_organ(0.430, 0.250, 0.070, 0.095)
# Right lung
draw_organ(0.570, 0.250, 0.070, 0.095)
# Heart (slightly left, between lungs)
draw_organ(0.455, 0.247, 0.042, 0.048)

# Liver (right upper abdomen)
draw_organ(0.560, 0.335, 0.075, 0.048)
# Stomach (left of liver)
draw_organ(0.445, 0.345, 0.052, 0.042)

# Left kidney
draw_organ(0.420, 0.390, 0.038, 0.050)
# Right kidney
draw_organ(0.580, 0.390, 0.038, 0.050)

# Large intestine / gut (centre-lower abdomen as rounded rectangle-ish)
gut_pts = [pt(0.360, 0.420), pt(0.640, 0.420),
           pt(0.650, 0.445), pt(0.640, 0.515),
           pt(0.360, 0.515), pt(0.350, 0.445)]
draw.polygon(gut_pts, fill=ORGAN_FILL, outline=ORGAN_EDGE)

# ── Spine indicator (dashed vertical line in torso) ───────────────────────────
for i in range(8):
    y_frac = 0.175 + i * 0.044
    cx, cy = 0.500 * W, y_frac * H
    draw.rectangle([(cx - 5, cy - 6), (cx + 5, cy + 6)],
                   fill=ORGAN_FILL, outline=ORGAN_EDGE)

# ── Rib cage outlines ─────────────────────────────────────────────────────────
for i in range(5):
    y = 0.195 + i * 0.040
    # left ribs
    x0l = 0.310 + i * 0.008
    draw.arc([pt(x0l, y - 0.010), pt(0.497, y + 0.030)], start=200, end=355,
             fill=ORGAN_EDGE, width=2)
    # right ribs
    x1r = 0.690 - i * 0.008
    draw.arc([pt(0.503, y - 0.010), pt(x1r, y + 0.030)], start=185, end=340,
             fill=ORGAN_EDGE, width=2)

# ── Femur / leg bones ─────────────────────────────────────────────────────────
# Left
draw.line([pt(0.375, 0.545), pt(0.365, 0.710)], fill=ORGAN_EDGE, width=4)
draw.line([pt(0.365, 0.710), pt(0.370, 0.830)], fill=ORGAN_EDGE, width=3)
# Right
draw.line([pt(0.625, 0.545), pt(0.632, 0.710)], fill=ORGAN_EDGE, width=4)
draw.line([pt(0.632, 0.710), pt(0.628, 0.830)], fill=ORGAN_EDGE, width=3)

# ── Arm bones ─────────────────────────────────────────────────────────────────
# Left upper arm
draw.line([pt(0.265, 0.180), pt(0.248, 0.330)], fill=ORGAN_EDGE, width=3)
draw.line([pt(0.248, 0.330), pt(0.238, 0.475)], fill=ORGAN_EDGE, width=2)
# Right upper arm
draw.line([pt(0.735, 0.180), pt(0.752, 0.330)], fill=ORGAN_EDGE, width=3)
draw.line([pt(0.752, 0.330), pt(0.762, 0.475)], fill=ORGAN_EDGE, width=2)

# ── Muscle outlines (bicep/thigh) ─────────────────────────────────────────────
# Left bicep
draw.arc([pt(0.185, 0.188), pt(0.282, 0.330)], start=155, end=25, fill=ORGAN_EDGE, width=2)
# Right bicep
draw.arc([pt(0.718, 0.188), pt(0.815, 0.330)], start=155, end=25, fill=ORGAN_EDGE, width=2)

# ── Immune nodes (lymph nodes — small dots at neck sides) ────────────────────
for cx in [0.438, 0.562]:
    draw_organ(cx, 0.148, 0.018, 0.015)


# ─── Soften edges (Gaussian blur just the body layer) ────────────────────────
# Apply a very slight blur to smooth pixelated polygon edges
img = img.filter(ImageFilter.GaussianBlur(radius=0.8))

# ─── Save ────────────────────────────────────────────────────────────────────
out_path = os.path.join(os.path.dirname(__file__), '..', 'assets', 'body_outline.png')
img.save(out_path, format='PNG', optimize=True)
print(f"Saved body_outline.png → {os.path.abspath(out_path)}")
print(f"Size: {img.size}")
