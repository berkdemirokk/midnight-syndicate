"""Tileable normal map of rain beads on clear coat: a few hundred round drops of mixed size, some run into
short streaks. Own work, no source image. Run: py -3.10 assets_src/vehicles/shared/build_rain_beads.py"""
import math, os, random
from PIL import Image

SIZE = 512
OUT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "game", "assets", "vehicles", "shared", "car_rain_beads_normal.png"))
random.seed(20261126)
h = [[0.0] * SIZE for _ in range(SIZE)]


def drop(cx, cy, r, sy=1.0):
    ry = r * sy
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            d = ((x - cx) / r) ** 2 + ((y - cy) / ry) ** 2
            if d < 1.0:
                v = math.sqrt(1.0 - d) * min(r, 9.0) / 9.0  # a spherical cap; small drops are lower
                yy, xx = y % SIZE, x % SIZE
                h[yy][xx] = max(h[yy][xx], v)


for _ in range(520):
    r = random.choice([2.2, 2.6, 3.0, 3.5, 4.5, 6.0, 8.0]) * random.uniform(0.8, 1.2)
    drop(random.uniform(0, SIZE), random.uniform(0, SIZE), r, random.choice([1.0, 1.0, 1.0, 1.4, 2.2]))

img = Image.new("RGB", (SIZE, SIZE))
px = img.load()
K = 5.0
for y in range(SIZE):
    for x in range(SIZE):
        dx = (h[y][(x + 1) % SIZE] - h[y][(x - 1) % SIZE]) * K
        dy = (h[(y + 1) % SIZE][x] - h[(y - 1) % SIZE][x]) * K
        n = 1.0 / math.sqrt(dx * dx + dy * dy + 1.0)
        px[x, y] = (int((-dx * n * 0.5 + 0.5) * 255), int((-dy * n * 0.5 + 0.5) * 255), int((n * 0.5 + 0.5) * 255))
img.save(OUT)
print(OUT)
