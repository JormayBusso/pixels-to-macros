"""
Professional app icon for Pixels to Macros.

Design:
  - Deep forest-green radial gradient background
  - Subtle outer white ring (border)
  - White plate/lens ring in the centre
  - Four camera alignment tick marks (N/S/E/W) just inside the ring
  - Three vivid macro-nutrient dots arranged in an equilateral triangle:
      red   = Protein  (top)
      amber = Carbs    (bottom-left)
      cyan  = Fat      (bottom-right)
  - Small white centre dot
"""
import struct, zlib, math, os

SIZE = 1024
CX = CY = SIZE // 2


def make_png(buf: bytearray, w: int, h: int) -> bytes:
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw.extend(buf[y * stride:(y + 1) * stride])
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(bytes(raw), 6))
            + chunk(b'IEND', b''))


def lc(c1, c2, t):
    """Linear interpolate between two RGB tuples."""
    return (int(c1[0] + (c2[0] - c1[0]) * t),
            int(c1[1] + (c2[1] - c1[1]) * t),
            int(c1[2] + (c2[2] - c1[2]) * t))


def main():
    print("Generating professional app icon…")
    buf = bytearray(SIZE * SIZE * 4)
    R = SIZE // 2  # 512

    # Colours
    BG_C = (46, 125, 50)     # #2E7D32  forest green (centre)
    BG_E = (10,  40, 10)     # very dark green (edge)
    C_W  = (255, 255, 255)   # white
    C_WD = (200, 225, 200)   # off-white  (outer decorative ring)
    C_P  = (229,  57,  53)   # red    – Protein
    C_C  = (255, 145,   0)   # amber  – Carbs
    C_F  = (  0, 172, 193)   # cyan   – Fat / Vitamins

    # Squared radii (avoids sqrt in comparisons)
    R2          = R * R
    OR_O2       = 478 * 478;  OR_I2 = 468 * 468   # outer decorative ring
    PL_O2       = 310 * 310;  PL_I2 = 283 * 283   # plate / lens ring
    TICK_O2     = 268 * 268;  TICK_I2 = 244 * 244 # tick-mark band
    CENTER_R2   = 22 * 22

    # Equilateral triangle of macro dots (172 px from centre, radius 84)
    TD = 172; DR = 84; DR2 = DR * DR; SH = 7; SHA = 0.38
    DOTS = [
        (CX,       CY - TD,  C_P),   # top    – protein
        (CX - 149, CY +  86, C_C),   # lower-left  – carbs
        (CX + 149, CY +  86, C_F),   # lower-right – fat
    ]

    for y in range(SIZE):
        dy  = y - CY
        dy2 = dy * dy
        row = y * SIZE * 4

        for x in range(SIZE):
            dx = x - CX
            d2 = dx * dx + dy2

            if d2 > R2:
                continue  # outside circle → transparent

            off = row + x * 4

            # ── background gradient ──────────────────────────────────────
            t = math.sqrt(d2) / R
            bg = lc(BG_C, BG_E, t * t)
            buf[off], buf[off+1], buf[off+2], buf[off+3] = bg[0], bg[1], bg[2], 255

            # ── outer decorative ring ────────────────────────────────────
            if OR_I2 <= d2 <= OR_O2:
                buf[off], buf[off+1], buf[off+2] = C_WD
                continue

            # ── plate / lens ring ────────────────────────────────────────
            if PL_I2 <= d2 <= PL_O2:
                buf[off], buf[off+1], buf[off+2] = C_W
                continue

            # ── camera alignment tick marks (N / S / E / W) ──────────────
            if TICK_I2 <= d2 <= TICK_O2:
                if abs(dx) <= 22 or abs(dy) <= 22:
                    buf[off], buf[off+1], buf[off+2] = C_W
                    continue

            # ── dot drop-shadows (darken background) ─────────────────────
            for dcx, dcy, col in DOTS:
                sdx = x - (dcx + SH)
                sdy = y - (dcy + SH)
                if sdx*sdx + sdy*sdy <= DR2:
                    buf[off]   = int(buf[off]   * (1 - SHA))
                    buf[off+1] = int(buf[off+1] * (1 - SHA))
                    buf[off+2] = int(buf[off+2] * (1 - SHA))
                    break

            # ── macro-nutrient dots ───────────────────────────────────────
            hit = False
            for dcx, dcy, col in DOTS:
                ddx = x - dcx
                ddy = y - dcy
                if ddx*ddx + ddy*ddy <= DR2:
                    buf[off], buf[off+1], buf[off+2] = col
                    hit = True
                    break
            if hit:
                continue

            # ── centre white dot ──────────────────────────────────────────
            if d2 <= CENTER_R2:
                buf[off], buf[off+1], buf[off+2] = C_W

    png = make_png(buf, SIZE, SIZE)
    out = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'assets', 'app_icon.png')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'wb') as f:
        f.write(png)
    print(f"Saved → {out}  ({len(png):,} bytes)")


if __name__ == '__main__':
    main()
