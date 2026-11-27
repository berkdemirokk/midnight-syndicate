"""Side-by-side before/after sheets from two folders of harness captures (same shot names = same camera and preset).

Usage: py -3.10 tools/before_after.py <before_dir> <after_dir> <out_dir> [shot ...]
Default shots: the Ortakoy benchmark views. Each sheet is BEFORE | AFTER at half size, labelled, JPEG quality 88.
"""
import os
import sys

from PIL import Image, ImageDraw

SHOTS = ["bench_day_hero", "bench_day_street", "bench_day_car34", "bench_day_mosque", "bench_day_gameplay",
         "bench_night_hero", "bench_night_street", "bench_night_gameplay"]


def sheet(before: str, after: str, out: str, label: str) -> None:
    a = Image.open(before).convert("RGB")
    b = Image.open(after).convert("RGB")
    w, h = a.width // 2, a.height // 2
    a = a.resize((w, h), Image.LANCZOS)
    b = b.resize((w, h), Image.LANCZOS)
    s = Image.new("RGB", (w * 2 + 8, h + 40), (12, 12, 16))
    s.paste(a, (0, 40))
    s.paste(b, (w + 8, 40))
    d = ImageDraw.Draw(s)
    d.text((10, 12), "BEFORE (feature/vertical-slice a4c30a1)  " + label, fill=(230, 230, 230))
    d.text((w + 18, 12), "AFTER (release/rc-2026-11-28)  " + label, fill=(230, 230, 230))
    s.save(out, quality=88)


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    src, dst, out = sys.argv[1], sys.argv[2], sys.argv[3]
    shots = sys.argv[4:] or SHOTS
    os.makedirs(out, exist_ok=True)
    n = 0
    for name in shots:
        p, q = os.path.join(src, name + ".png"), os.path.join(dst, name + ".png")
        if os.path.exists(p) and os.path.exists(q):
            sheet(p, q, os.path.join(out, name + ".jpg"), name)
            n += 1
        else:
            print("missing:", name)
    print(f"{n} sheets in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
