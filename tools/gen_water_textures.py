"""Generate the two sea normal maps used by game/world/materials/water.gdshader.

Stdlib only, deterministic (fixed seeds). Each map is a periodic height field built from a sum of
sinusoids with integer cycles per tile (so it tiles seamlessly), and is stored as a slope map:
R = 0.5 + 0.5 * clamp(-dh/dx, -1, 1), G = 0.5 + 0.5 * clamp(-dh/dz, -1, 1), B = 255 (unused).
The shader decodes slope = rgb * 2 - 1 and builds the world normal itself, so no tangent frame is needed.

Usage: py -3.10 tools/gen_water_textures.py
Outputs: game/assets/world/water/water_swell.png (broad swell, 16 m tile)
         game/assets/world/water/water_chop.png  (fine chop, 3.2 m tile)
"""
import math
import os
import random
import struct
import sys
import zlib

SIZE = 512
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "game", "assets", "world", "water")


def write_png(path, width, height, rgb_rows):
    raw = bytearray()
    for row in rgb_rows:
        raw.append(0)  # filter: none
        raw.extend(row)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def make_waves(seed, count, min_cycles, max_cycles, slope_amp, spectrum_power):
    """Random integer-frequency waves: (kx, kz) cycles per tile, amplitude, phase."""
    rng = random.Random(seed)
    waves = []
    seen = set()
    while len(waves) < count:
        kx = rng.randint(-max_cycles, max_cycles)
        kz = rng.randint(-max_cycles, max_cycles)
        f = math.hypot(kx, kz)
        if f < min_cycles or f > max_cycles or (kx, kz) in seen or (-kx, -kz) in seen:
            continue
        seen.add((kx, kz))
        amp = slope_amp * (f ** -spectrum_power)
        waves.append((kx, kz, amp, rng.uniform(0.0, 2.0 * math.pi)))
    # Normalise so the RMS slope is slope_amp (peaks above it clamp at the encoding limit).
    rms = math.sqrt(sum((a * math.hypot(kx, kz)) ** 2 for kx, kz, a, _ in waves) / 2.0)
    scale = slope_amp / max(rms, 1e-9)
    return [(kx, kz, a * scale, p) for kx, kz, a, p in waves]


def slope_map(waves):
    """Analytic slope of the height field sampled on a SIZE x SIZE periodic grid."""
    two_pi_over = 2.0 * math.pi / SIZE
    rows = []
    # Precompute per-wave phase tables: cos/sin of (k * index) reused across rows.
    for z in range(SIZE):
        row = bytearray(SIZE * 3)
        for x in range(SIZE):
            sx = 0.0
            sz = 0.0
            for kx, kz, a, p in waves:
                ph = two_pi_over * (kx * x + kz * z) + p
                # dh/dx = -a * kx * sin(ph) * 2pi/SIZE_in_cycles ; slope = -dh/dx
                c = a * math.cos(ph)
                sx += c * kx
                sz += c * kz
            # slope magnitudes are already scaled into roughly [-1, 1]
            r = 0.5 + 0.5 * max(-1.0, min(1.0, sx))
            g = 0.5 + 0.5 * max(-1.0, min(1.0, sz))
            i = x * 3
            row[i] = int(round(r * 255.0))
            row[i + 1] = int(round(g * 255.0))
            row[i + 2] = 255
        rows.append(bytes(row))
    return rows


def generate(name, seed, count, min_cycles, max_cycles, slope_amp, spectrum_power):
    waves = make_waves(seed, count, min_cycles, max_cycles, slope_amp, spectrum_power)
    rows = slope_map(waves)
    path = os.path.join(OUT_DIR, name)
    write_png(path, SIZE, SIZE, rows)
    print("wrote %s (%d waves, %d bytes)" % (path, len(waves), os.path.getsize(path)))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    # Swell: few long waves, slopes up to ~0.25 (gentle, a few cycles per 16 m tile).
    generate("water_swell.png", seed=1101, count=10, min_cycles=1, max_cycles=5,
             slope_amp=0.5, spectrum_power=0.6)
    # Chop: many short waves, steeper per-texel slopes, 3.2 m tile.
    generate("water_chop.png", seed=2202, count=16, min_cycles=4, max_cycles=40,
             slope_amp=0.6, spectrum_power=0.9)
    return 0


if __name__ == "__main__":
    sys.exit(main())
