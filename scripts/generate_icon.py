"""Generate a green food-themed app icon for Pixels to Macros (fast version)."""
import struct, zlib, math, os

SIZE = 1024

def make_png(buf, w, h):
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

def main():
    print("Generating app icon...")
    buf = bytearray(SIZE * SIZE * 4)
    cx = cy = SIZE // 2
    r = SIZE // 2
    r2 = r * r
    fork_cx = cx - 120
    knife_cx = cx + 120

    for y in range(SIZE):
        dy = y - cy
        dy2 = dy * dy
        row = y * SIZE * 4
        for x in range(SIZE):
            dx = x - cx
            d2 = dx * dx + dy2
            off = row + x * 4
            if d2 > r2:
                continue  # transparent
            t = math.sqrt(d2) / r
            buf[off]     = int(76 + (27 - 76) * t)
            buf[off + 1] = int(175 + (94 - 175) * t)
            buf[off + 2] = int(80 + (32 - 80) * t)
            buf[off + 3] = 255

            # Fork
            is_utensil = False
            if 220 <= y <= 480:
                if abs(x - (fork_cx - 40)) <= 12 or abs(x - fork_cx) <= 12 or abs(x - (fork_cx + 40)) <= 12:
                    is_utensil = True
            if abs(y - 480) <= 15 and abs(x - fork_cx) <= 52:
                is_utensil = True
            if 480 <= y <= 800 and abs(x - fork_cx) <= 18:
                is_utensil = True
            # Knife
            if 220 <= y <= 520:
                bt = (y - 220) / 300.0
                hw = int(8 + 37 * bt)
                if abs(x - knife_cx) <= hw:
                    is_utensil = True
            if 520 <= y <= 800 and abs(x - knife_cx) <= 18:
                is_utensil = True

            if is_utensil:
                buf[off] = buf[off + 1] = buf[off + 2] = 255
                buf[off + 3] = 230

    png = make_png(buf, SIZE, SIZE)
    out = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'assets', 'app_icon.png')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'wb') as f:
        f.write(png)
    print(f"Icon saved to {out} ({len(png)} bytes)")

if __name__ == '__main__':
    main()
