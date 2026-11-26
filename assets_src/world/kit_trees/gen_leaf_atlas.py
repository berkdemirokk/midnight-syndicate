"""Leaf-cluster atlas for the tree kit (stdlib only, deterministic, no network).

Writes game/assets/world/kits/trees/leaf_atlas.png (512x512 RGBA, alpha-tested cut-outs, no blending).
Quadrants, PNG order (top-left origin):
  top-left     plane (cinar)        lobed five-point leaves
  top-right    judas (erguvan)      heart-shaped leaves with pink-magenta blossom clusters
  bottom-left  cypress (servi)      narrow scale sprays
  bottom-right street (planter)     small oval leaves
Run:  py -3.10 assets_src/world/kit_trees/gen_leaf_atlas.py
"""
import math
import os
import random
import struct
import zlib

SIZE = 512
HALF = 256
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "game", "assets", "world", "kits", "trees", "leaf_atlas.png")


def write_png(path, w, h, rgba):
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def shape_radius(kind, theta):
    """Normalised outline radius (1.0 = size) for a leaf shape at angle theta (leaf axis = +x)."""
    if kind == "lobed":  # five broad lobes, like a plane-tree leaf
        return 0.45 + 0.55 * abs(math.cos(2.5 * theta)) ** 0.7
    if kind == "heart":  # broad with a notch at the stem end
        return 0.78 + 0.22 * math.cos(theta) ** 2 - 0.12 * math.exp(-((abs(theta) - math.pi) ** 2) * 8.0)
    return 0.85 + 0.15 * math.cos(2.0 * theta)  # oval


class Atlas:
    def __init__(self):
        self.px = bytearray(SIZE * SIZE * 4)  # RGBA straight, alpha 0 or 255

    def put(self, x, y, rgb):
        i = (y * SIZE + x) * 4
        self.px[i] = rgb[0]
        self.px[i + 1] = rgb[1]
        self.px[i + 2] = rgb[2]
        self.px[i + 3] = 255

    def leaf(self, rnd, box, cx, cy, size, angle, kind, rgb, aspect=1.0, vein=None):
        x0, y0, x1, y1 = box
        ca, sa = math.cos(angle), math.sin(angle)
        ext = int(size * 1.3) + 2
        for y in range(max(y0, int(cy) - ext), min(y1, int(cy) + ext + 1)):
            for x in range(max(x0, int(cx) - ext), min(x1, int(cx) + ext + 1)):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                lx = dx * ca + dy * sa
                ly = (-dx * sa + dy * ca) / aspect
                d = math.hypot(lx, ly)
                if d > 1e-6:
                    theta = math.atan2(ly, lx)
                    if d > size * shape_radius(kind, theta):
                        continue
                c = rgb
                if vein is not None and abs(ly) < 0.6 and d < size * 0.85:
                    c = vein
                shade = 0.9 + 0.1 * (d / max(size, 1.0)) + rnd.uniform(-0.03, 0.03)
                self.put(x, y, (min(255, int(c[0] * shade)), min(255, int(c[1] * shade)), min(255, int(c[2] * shade))))

    def blossom(self, rnd, box, cx, cy, size):
        base = (rnd.randint(190, 232), rnd.randint(30, 60), rnd.randint(95, 130))
        for k in range(5):
            a = k * 2.0 * math.pi / 5.0 + rnd.uniform(-0.2, 0.2)
            self.leaf(rnd, box, cx + math.cos(a) * size * 0.55, cy + math.sin(a) * size * 0.55,
                      size * 0.55, a, "oval", base, 0.8)
        self.leaf(rnd, box, cx, cy, size * 0.22, 0.0, "oval", (235, 200, 60), 1.0)


def fill_quadrant(atlas, rnd, box, count, kind, size_rng, colours, aspect=1.0, blossom_share=0.0):
    x0, y0, x1, y1 = box
    m = 6
    for _ in range(count):
        cx = rnd.uniform(x0 + m, x1 - m)
        cy = rnd.uniform(y0 + m, y1 - m)
        size = rnd.uniform(*size_rng)
        if blossom_share and rnd.random() < blossom_share:
            atlas.blossom(rnd, box, cx, cy, size * 0.75)
            continue
        rgb = rnd.choice(colours)
        rgb = tuple(max(0, min(255, int(v * rnd.uniform(0.9, 1.1)))) for v in rgb)
        vein = (int(rgb[0] * 0.6), int(rgb[1] * 0.7), int(rgb[2] * 0.6))
        atlas.leaf(rnd, box, cx, cy, size, rnd.uniform(0, 2 * math.pi), kind, rgb, aspect, vein)


def build():
    rnd = random.Random(20260612)
    atlas = Atlas()
    # Quadrant boxes are pixel rects (x0, y0, x1, y1), end exclusive.
    plane = (0, 0, HALF, HALF)
    judas = (HALF, 0, SIZE, HALF)
    cypress = (0, HALF, HALF, SIZE)
    street = (HALF, HALF, SIZE, SIZE)
    fill_quadrant(atlas, rnd, plane, 90, "lobed", (24, 34),
                  [(52, 98, 36), (68, 110, 44), (42, 84, 30), (88, 118, 50)])
    fill_quadrant(atlas, rnd, judas, 70, "heart", (20, 28),
                  [(46, 88, 38), (58, 98, 42), (40, 76, 32)], blossom_share=0.45)
    fill_quadrant(atlas, rnd, cypress, 110, "oval", (30, 40),
                  [(30, 60, 38), (36, 70, 42), (24, 52, 34), (52, 84, 46)], aspect=0.22)
    fill_quadrant(atlas, rnd, street, 80, "oval", (17, 24),
                  [(66, 104, 42), (78, 116, 48), (56, 92, 38)])
    write_png(OUT, SIZE, SIZE, bytes(atlas.px))
    return OUT


if __name__ == "__main__":
    print("wrote", build())
