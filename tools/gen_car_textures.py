"""Procedural car material textures, stdlib only (zlib + struct). Original, project-owned output.

Writes PNG files into game/assets/vehicles/shared/ for car_materials.gd:
  car_flake_normal.png     512 px tileable normal map: orange peel (low frequency) + metallic flake (sparkle)
  car_flake_roughness.png  512 px tileable roughness, red channel (multiplies the material roughness)
  car_rubber_roughness.png 256 px tyre sidewall roughness variation, red channel
  car_brushed_roughness.png 512 px brushed-metal streaks for rims, red channel
  car_grain_normal.png     256 px fine grain normal for satin black plastic trim

Run: py -3.10 tools/gen_car_textures.py
Deterministic: the same seed gives the same bytes, so the manifest sha256 stays stable.
"""
import math
import os
import random
import struct
import zlib

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "vehicles", "shared")


def write_png(path, w, h, rgb_rows):
    """rgb_rows: list of h bytearrays, each w*3 bytes (8-bit RGB, no alpha)."""
    raw = bytearray()
    for row in rgb_rows:
        raw.append(0)  # filter type 0 (none) per scanline
        raw += row

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def smooth(t):
    return t * t * (3.0 - 2.0 * t)


def value_noise(size, cells, rng):
    """Tileable value noise, size x size, from a cells x cells lattice. Returns flat list of floats 0..1."""
    lattice = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    out = [0.0] * (size * size)
    step = size / cells
    for y in range(size):
        gy = y / step
        y0 = int(gy) % cells
        y1 = (y0 + 1) % cells
        ty = smooth(gy - int(gy))
        for x in range(size):
            gx = x / step
            x0 = int(gx) % cells
            x1 = (x0 + 1) % cells
            tx = smooth(gx - int(gx))
            a = lattice[y0][x0] + (lattice[y0][x1] - lattice[y0][x0]) * tx
            b = lattice[y1][x0] + (lattice[y1][x1] - lattice[y1][x0]) * tx
            out[y * size + x] = a + (b - a) * ty
    return out


def normal_rows(h, size, strength):
    """Height field (flat list, tileable) to tangent-space normal map rows, RGB 8-bit."""
    rows = []
    for y in range(size):
        row = bytearray(size * 3)
        ym = ((y - 1) % size) * size
        yp = ((y + 1) % size) * size
        yc = y * size
        for x in range(size):
            xm = (x - 1) % size
            xp = (x + 1) % size
            dx = (h[yc + xp] - h[yc + xm]) * strength
            dy = (h[yp + x] - h[ym + x]) * strength
            nx, ny, nz = -dx, dy, 1.0
            inv = 1.0 / math.sqrt(nx * nx + ny * ny + nz * nz)
            i = x * 3
            row[i] = int((nx * inv * 0.5 + 0.5) * 255.0 + 0.5)
            row[i + 1] = int((ny * inv * 0.5 + 0.5) * 255.0 + 0.5)
            row[i + 2] = int((nz * inv * 0.5 + 0.5) * 255.0 + 0.5)
        rows.append(row)
    return rows


def gray_rows(v, size):
    """Values 0..1 (flat list) to grey RGB rows. The red channel is what StandardMaterial3D reads."""
    rows = []
    for y in range(size):
        row = bytearray(size * 3)
        for x in range(size):
            b = int(max(0.0, min(1.0, v[y * size + x])) * 255.0 + 0.5)
            i = x * 3
            row[i] = row[i + 1] = row[i + 2] = b
        rows.append(row)
    return rows


def flake_normal(rng, size=512):
    peel = value_noise(size, 16, rng)  # orange peel: 32 px cells, broad and soft
    # Flake: sparse single-pixel glints, then a 3x3 blur so each flake is a small facet, not a dot.
    glint = [1.0 if rng.random() < 0.05 else 0.0 for _ in range(size * size)]
    flake = [0.0] * (size * size)
    for y in range(size):
        for x in range(size):
            acc = 0.0
            for dy in (-1, 0, 1):
                row = ((y + dy) % size) * size
                for dx in (-1, 0, 1):
                    acc += glint[row + (x + dx) % size]
            flake[y * size + x] = acc / 9.0 * 3.0
    h = [0.35 * peel[i] + flake[i] for i in range(size * size)]
    return normal_rows(h, size, strength=2.2)


def flake_roughness(rng, size=512):
    # Multiplies material roughness (0.42): 0.67..1.0 gives 0.28..0.42, the flake breaks up the gloss a little.
    base = value_noise(size, 32, rng)
    out = []
    for i in range(size * size):
        out.append(0.67 + 0.33 * (0.7 * base[i] + 0.3 * rng.random()))
    return gray_rows(out, size)


def rubber_roughness(rng, size=256):
    # Tyre sidewall: broad patches plus radial-ish streaks (columns). Multiplies roughness 0.92.
    patch = value_noise(size, 8, rng)
    out = []
    cols = [rng.random() for _ in range(size)]
    for y in range(size):
        for x in range(size):
            v = 0.55 * patch[y * size + x] + 0.45 * cols[x]
            out.append(0.8 + 0.2 * v)
    return gray_rows(out, size)


def brushed_roughness(rng, size=512):
    # Brushed metal: one random value per row (streaks run along x), smoothed a little so they are not noise.
    rows_v = [rng.random() for _ in range(size)]
    smooth_v = [(rows_v[(y - 1) % size] + 2 * rows_v[y] + rows_v[(y + 1) % size]) / 4.0 for y in range(size)]
    out = []
    for y in range(size):
        for x in range(size):
            fine = 0.06 * (rng.random() - 0.5)
            out.append(0.55 + 0.45 * smooth_v[y] + fine)
    return gray_rows(out, size)


def grain_normal(rng, size=256):
    h = [rng.random() for _ in range(size * size)]
    return normal_rows(h, size, strength=0.35)


def main():
    os.makedirs(OUT, exist_ok=True)
    jobs = [
        ("car_flake_normal.png", 512, lambda r: flake_normal(r, 512), 101),
        ("car_flake_roughness.png", 512, lambda r: flake_roughness(r, 512), 102),
        ("car_rubber_roughness.png", 256, lambda r: rubber_roughness(r, 256), 103),
        ("car_brushed_roughness.png", 512, lambda r: brushed_roughness(r, 512), 104),
        ("car_grain_normal.png", 256, lambda r: grain_normal(r, 256), 105),
    ]
    for name, size, fn, seed in jobs:
        rows = fn(random.Random(seed))
        write_png(os.path.join(OUT, name), size, size, rows)
        print("wrote", name, size)


if __name__ == "__main__":
    main()
