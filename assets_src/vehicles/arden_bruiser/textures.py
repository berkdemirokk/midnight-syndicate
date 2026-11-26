"""Arden Bruiser, stage 2B: procedural textures (numpy, deterministic, PNG via zlib).

Every map is periodic (seamless when tiled) and power of two. Arrays are written visually: row 0
is the top of the image, which Blender loads at V = 1. Outputs go to out/textures/:
  paint_flake_normal.png   512  tiling flake normal for M_Paint (UV in metres, tile 0.06 m)
  carbon_base.png          512  carbon weave base colour for M_Carbon (tile 0.024 m)
  carbon_normal.png        512  carbon weave normal
  tyre_normal.png          1024 tread detail on the tread band, raised ARDEN BRUISER on both sidewalls
                                (U around the tyre, V along the section profile arc length)
  brake_roughness.png      512  radial brushed roughness for M_BrakeDisc (U around, V radius)
  brake_normal.png         512  drilled-hole dimples for M_BrakeDisc
  lens_normal.png          256  fine horizontal lens facets for M_Lens
  plate_base.png           512x128 plate base colour with the text NOCTRA (reads from behind)
"""
import math
import os
import struct
import zlib

import numpy as np

# 5x7 bitmap font. N O C T R A from details.py; S P E and the hyphen added for R-SPEC.
FONT = {
    "N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    " ": ["00000"] * 7,
}


def write_png(path, rgb):
    """rgb: (H, W, 3) uint8, row 0 at the top. Stdlib PNG writer (no pip)."""
    H, W, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(H))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def periodic_filter(a, sigma):
    """Gaussian blur of a 2D array with wrap-around (FFT), sigma in pixels."""
    n, m = a.shape
    ky = np.fft.fftfreq(n)[:, None]
    kx = np.fft.fftfreq(m)[None, :]
    G = np.exp(-2.0 * (math.pi * sigma) ** 2 * (kx ** 2 + ky ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * G))


def norm(a):
    a = a - a.mean()
    return a / (a.std() + 1e-12)


def normal_from_height(h, k):
    """OpenGL style tangent normal map (+Y up) from a periodic height field, strength k."""
    dx = 0.5 * (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1))
    dy = 0.5 * (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0))
    nx, ny, nz = -dx * k, dy * k, np.ones_like(h)
    L = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / L, ny / L, nz / L], axis=2)
    return np.clip((n * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8)


def to_u8(rgb_float):
    return np.clip(rgb_float * 255.0 + 0.5, 0, 255).astype(np.uint8)


# ------------------------------------------------------------------ paint
def paint_flake(rng, n=512):
    # 512 px over the 0.20 m UV tile: flakes about 1 to 2 mm, so they catch the light at render scale
    base = periodic_filter(rng.standard_normal((n, n)), 0.9)
    spark = (rng.random((n, n)) > 0.97) * rng.random((n, n))
    spark = periodic_filter(spark, 0.5)
    h = norm(base) * 0.5 + norm(spark) * 1.4
    return normal_from_height(h, 0.8)


# ------------------------------------------------------------------ carbon
def carbon(n=512, tow=16):
    y, x = np.mgrid[0:n, 0:n]
    fx = (x % tow) / tow
    fy = (y % tow) / tow
    warp = ((x // tow) + (y // tow)) % 2 == 0          # 2x2 twill: warp tow over here
    hw = np.sin(math.pi * fy) ** 0.5 * (0.7 + 0.3 * np.sin(math.pi * fx))
    hf = np.sin(math.pi * fx) ** 0.5 * (0.7 + 0.3 * np.sin(math.pi * fy))
    h = np.where(warp, hw, hf)
    tone = 0.10 + 0.05 * h + 0.012 * periodic_filter(np.random.default_rng(7).standard_normal((n, n)), 1.0)
    base = np.stack([tone * 0.95, tone * 0.97, tone * 1.02], axis=2)
    return to_u8(np.clip(base, 0, 1)), normal_from_height(h, 2.5)


# ------------------------------------------------------------------ tyre
def tyre_ranges():
    """V ranges of the tread and of each sidewall, from the same profile the mesh uses."""
    import wheels as W
    R, Wd, hr = W.WHEELS["wheel_FL"][2], W.WHEELS["wheel_FL"][3], W.WHEELS["wheel_FL"][4]
    pts, regs = W.tyre_profile(R, Wd, hr)
    V = W.tyre_vfrac(pts)
    out = {}
    tread = [v for v, g in zip(V, regs) if g == "tread"]
    out["tread"] = (min(tread), max(tread))
    for sign, key in ((1, "side_pos"), (-1, "side_neg")):
        vs = [v for (p, v, g) in zip(pts, V, regs) if g == "side" and sign * p[0] > 0]
        out[key] = (min(vs), max(vs))
    return out


def tyre(rng, H=1024, Wd=1024):
    rng_v = tyre_ranges()
    U = np.arange(Wd)[None, :] / Wd * np.ones((H, 1))
    Vr = (1.0 - np.arange(H) / (H - 1))[:, None] * np.ones((1, Wd))   # row 0 = V 1
    h = np.zeros((H, Wd))
    # tread band: fine lugs and sipes across the tread (64 per turn, periodic in U)
    t0, t1 = rng_v["tread"]
    mask_t = ((Vr >= t0) & (Vr <= t1)).astype(float)
    h += mask_t * 0.35 * (np.sin(2 * math.pi * 64 * U) > 0.6)
    h += mask_t * 0.12 * norm(periodic_filter(rng.standard_normal((H, Wd)), 1.5))
    h += 0.05 * norm(periodic_filter(rng.standard_normal((H, Wd)), 3.0))
    # raised lettering ARDEN BRUISER, 4x scale, both sidewalls
    text = "ARDEN BRUISER"
    scale, gap = 5, 1
    cols = []
    for ch in text:
        g = FONT[ch]
        for r in range(7):
            pass
        cols.append(g)
    text_w = len(text) * (5 + gap) * scale
    txt = np.zeros((7 * scale, text_w))
    for i, g in enumerate(cols):
        for r, row in enumerate(g):
            for c, bit in enumerate(row):
                if bit == "1":
                    x0 = i * (5 + gap) * scale + c * scale
                    txt[r * scale:(r + 1) * scale, x0:x0 + scale] = 1.0
    c0 = int(0.56 * Wd)  # canonical wheels flip U, so this lands at 0.14 to 0.44 on the outboard face
    letter = np.zeros((H, Wd))
    for key in ("side_pos", "side_neg"):
        v0, v1 = rng_v[key]
        rc = int(round((1.0 - 0.5 * (v0 + v1)) * (H - 1)))
        r0 = rc - txt.shape[0] // 2
        r_lo, r_hi = max(r0, 0), min(r0 + txt.shape[0], H)
        letter[r_lo:r_hi, c0:c0 + text_w] = txt[r_lo - r0:r_hi - r0, :]
    h += letter
    hs = periodic_filter(h, 0.7)
    normal = normal_from_height(hs / (np.abs(hs).max() + 1e-9), 3.0)
    # base colour: black rubber, light grey lettering (the lettering must read in the render)
    ls = periodic_filter(letter, 0.6)
    rubber = 0.075 + 0.02 * norm(periodic_filter(rng.standard_normal((H, Wd)), 1.0))
    lum = rubber * (1.0 - ls) + 0.55 * ls
    base = to_u8(np.stack([lum, lum, lum * 1.02], axis=2))
    return normal, base


# ------------------------------------------------------------------ brake
def brake(rng, n=512):
    # brushed: streaks run radially, so the value depends on U (around) only
    col = periodic_filter(rng.standard_normal(n)[None, :] * np.ones((n, 1)), 1.2)[0]
    rough = 0.38 + 0.10 * (col - col.mean()) / (col.std() + 1e-12)
    rough = np.broadcast_to(rough[None, :], (n, n)) + 0.02 * norm(rng.standard_normal((n, n)))
    rough_u8 = to_u8(np.clip(rough, 0, 1))
    # drilled holes: 48 around x 4 rows, dimple radius 5 px
    h = np.zeros((n, n))
    yy, xx = np.mgrid[0:n, 0:n]
    for ri, vfrac in enumerate((0.30, 0.46, 0.62, 0.78)):
        rr = (1.0 - vfrac) * (n - 1)
        for k in range(48):
            cx = (k + 0.5) / 48 * n
            d2 = ((xx - cx + n / 2) % n - n / 2) ** 2 + (yy - rr) ** 2
            rad = 5.0
            h -= np.clip(1.0 - d2 / rad ** 2, 0, None)
    return rough_u8, normal_from_height(h, 2.5)


# ------------------------------------------------------------------ lens and plate
def lens(n=256):
    y, x = np.mgrid[0:n, 0:n]
    h = 0.6 * np.sin(2 * math.pi * y / 16) + 0.15 * np.cos(2 * math.pi * x / 32)
    return normal_from_height(h, 0.8)


def _text_triangles(text="ARDEN"):
    """Triangles (N, 3, 2) of the text in Blender's built-in font (Bfont), flat in XY, reading +X."""
    import bpy  # the texture step runs inside Blender
    cu = bpy.data.curves.new("PLATE_TEXT", "FONT")
    cu.body = text
    cu.size = 1.0
    ob = bpy.data.objects.new("PLATE_TEXT", cu)
    bpy.context.scene.collection.objects.link(ob)
    oe = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = oe.to_mesh()
    me.calc_loop_triangles()
    co = np.array([v.co[:] for v in me.vertices], float)
    tri = np.array([t.vertices[:] for t in me.loop_triangles], int)
    oe.to_mesh_clear()
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    if len(tri) == 0:
        raise RuntimeError("plate text: built-in font produced no triangles")
    return co[tri][:, :, :2]


def plate(H=128, Wd=512, text="ARDEN"):
    """Pale plate with black NOCTRA. Columns run left to right, which is viewer's right when
    seen from behind (plate_uv: U grows toward -X, the viewer's right), so the text reads true."""
    T = _text_triangles(text)
    lo, hi = T.reshape(-1, 2).min(axis=0), T.reshape(-1, 2).max(axis=0)
    k = min(0.80 * Wd / (hi[0] - lo[0]), 0.74 * H / (hi[1] - lo[1]))
    cen = 0.5 * (lo + hi)
    # pixel space, columns to the right and rows top down: text y up becomes H - y
    P = (T - cen) * k + np.array([Wd / 2, H / 2])
    P[:, :, 1] = H - P[:, :, 1]
    mask = np.zeros((H, Wd), bool)
    for a, b, c in P:
        x0, x1 = max(int(np.floor(min(a[0], b[0], c[0]))), 0), min(int(np.ceil(max(a[0], b[0], c[0]))), Wd)
        y0, y1 = max(int(np.floor(min(a[1], b[1], c[1]))), 0), min(int(np.ceil(max(a[1], b[1], c[1]))), H)
        if x0 >= x1 or y0 >= y1:
            continue
        X, Y = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-9:
            continue
        l1 = ((b[1] - c[1]) * (X - c[0]) + (c[0] - b[0]) * (Y - c[1])) / d
        l2 = ((c[1] - a[1]) * (X - c[0]) + (a[0] - c[0]) * (Y - c[1])) / d
        inside = (l1 >= 0) & (l2 >= 0) & (1.0 - l1 - l2 >= 0)
        mask[y0:y1, x0:x1] |= inside
    base = np.empty((H, Wd, 3))
    base[:] = np.array([0.91, 0.92, 0.89])
    base[mask] = np.array([0.02, 0.02, 0.025])
    return to_u8(np.clip(base, 0, 1))


def make_all(out_dir):
    rng = np.random.default_rng(20260909)
    files = {}
    files["paint_flake_normal"] = paint_flake(rng)
    cb, cn = carbon()
    files["carbon_base"] = cb
    files["carbon_normal"] = cn
    tn, tb = tyre(rng)
    files["tyre_normal"] = tn
    files["tyre_base"] = tb
    br, bn = brake(rng)
    files["brake_roughness"] = np.stack([br] * 3, axis=2)
    files["brake_normal"] = bn
    files["lens_normal"] = lens()
    files["plate_base"] = plate()
    out = {}
    for name, arr in files.items():
        path = os.path.join(out_dir, name + ".png")
        write_png(path, arr)
        out[name] = (path, arr.shape[1], arr.shape[0])
    return out


if __name__ == "__main__":
    import sys
    d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "textures")
    for k, v in make_all(d).items():
        print("TEX", k, v[1], v[2])
