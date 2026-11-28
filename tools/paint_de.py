"""Paint colour check for the end-of-sprint pass (docs/research/lookdev/PRODUCTION_PLAN.md section 1, Car).

Usage: py -3.10 tools/paint_de.py <png> [<png> ...] [--target 8E0F1E] [--crop x0,y0,x1,y1]
For each image: mask the car-paint pixels (red hue, saturated, not too dark or blown out), report how many, their mean
colour, and the mean CIE76 delta E against the target in Lab. Pass: mean dE <= 10. Exit 1 when any image fails or has
fewer than 2000 paint pixels (the mask missed the car).
"""
import argparse
import colorsys
import sys

from PIL import Image


def srgb_to_lab(r: float, g: float, b: float) -> tuple:
    def lin(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    rl, gl, bl = lin(r), lin(g), lin(b)
    x = (0.4124 * rl + 0.3576 * gl + 0.1805 * bl) / 0.95047
    y = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
    z = (0.0193 * rl + 0.1192 * gl + 0.9505 * bl) / 1.08883

    def f(t: float) -> float:
        return t ** (1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
    fx, fy, fz = f(x), f(y), f(z)
    return (116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


def check(path: str, target: tuple, crop: tuple | None) -> tuple:
    im = Image.open(path).convert("RGB")
    if crop:
        im = im.crop(crop)
    im = im.resize((im.width // 2, im.height // 2))
    tl = srgb_to_lab(*target)
    n = 0
    de_sum = 0.0
    acc = [0.0, 0.0, 0.0]
    for r8, g8, b8 in im.getdata():
        r, g, b = r8 / 255.0, g8 / 255.0, b8 / 255.0
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        if not ((h < 0.04 or h > 0.93) and s > 0.55 and 0.18 < v < 0.97):
            continue
        lab = srgb_to_lab(r, g, b)
        de_sum += sum((lab[i] - tl[i]) ** 2 for i in range(3)) ** 0.5
        acc[0] += r8
        acc[1] += g8
        acc[2] += b8
        n += 1
    if n == 0:
        return 0, None, None
    return n, tuple(round(c / n) for c in acc), de_sum / n


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="+")
    ap.add_argument("--target", default="8E0F1E")
    ap.add_argument("--crop", default="")
    a = ap.parse_args()
    t = a.target
    target = (int(t[0:2], 16) / 255.0, int(t[2:4], 16) / 255.0, int(t[4:6], 16) / 255.0)
    crop = tuple(int(v) for v in a.crop.split(",")) if a.crop else None
    bad = 0
    for p in a.images:
        n, mean, de = check(p, target, crop)
        ok = n >= 2000 and de is not None and de <= 10.0
        bad += 0 if ok else 1
        print(f"{'PASS' if ok else 'FAIL'} {p}: paint pixels {n}, mean rgb {mean}, mean dE {de if de is None else round(de, 2)}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
