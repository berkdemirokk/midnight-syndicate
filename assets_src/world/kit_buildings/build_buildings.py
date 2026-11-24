"""MIDNIGHT SYNDICATE - building kit generator (Environment Agent).

Run (Blender 5.3, deterministic, seeded):
  blender.exe --background --factory-startup --python build_buildings.py -- build
  blender.exe --background --factory-startup --python build_buildings.py -- render <group>

`build` writes GLBs (images excluded, named material slots), generated textures,
materials.json, catalog.json and report.json into ./out.
`render` imports the GLBs, hooks CC0 textures onto the named slots for QA only,
and writes evidence renders into ./renders.

Blender metres, Z up, front facade faces -Y, origin = centre of front facade at pavement.
Engine JSON is written in Godot coordinates: godot = (bx, bz, -by).
"""
import bpy
import bmesh
import json
import math
import os
import random
import struct
import sys
import zlib

import numpy as np
from mathutils import Vector

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["build"]
MODE = ARGV[0] if ARGV else "build"
KIT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(KIT, "out")
REN = os.path.join(KIT, "renders")
ROOT = os.path.abspath(os.path.join(KIT, "..", "..", ".."))
CC0 = "game/assets/textures/cc0"          # repo-relative, used in materials.json
SEED = 20261124
Z = Vector((0.0, 0.0, 1.0))
LIT_P = 0.35
TS = 256

# ----------------------------------------------------------------------------- materials
# CC0 slots: (cc0 id, uv tile in metres, roughness, metallic, tint for impostor)
CC0_SLOTS = {
    "M_Concrete_Smooth": ("brushed_concrete_03", 2.0, 0.80, 0.0, "#7E7C78"),
    "M_Concrete_Stained": ("concrete_wall_006", 2.0, 0.85, 0.0, "#6E6A62"),
    "M_Concrete_Panels": ("concrete_panels", 2.0, 0.75, 0.0, "#8C8A84"),
    "M_Brick_Red": ("brick_wall_006", 2.0, 0.85, 0.0, "#8A4A3A"),
    "M_Brick_Dark": ("dark_brick_wall", 2.0, 0.85, 0.0, "#5A3A33"),
    "M_Brick_Painted": ("castle_brick_02_white", 2.0, 0.80, 0.0, "#D9D2C4"),
    "M_Plaster_Clay": ("clay_plaster", 2.0, 0.90, 0.0, "#B08D6E"),
    "M_Plaster_Beige": ("beige_wall_001", 2.0, 0.85, 0.0, "#CDBFA5"),
    "M_Metal_Painted": ("blue_metal_plate", 1.0, 0.45, 0.4, "#3B4A5C"),
    "M_Metal_Corrugated": ("corrugated_iron_03", 1.5, 0.50, 0.5, "#7A7F86"),
    "M_Metal_Rusty": ("corrugated_iron", 1.5, 0.70, 0.4, "#7A5238"),
    "M_Facade_Tile": ("concrete_tile_facade", 1.2, 0.35, 0.0, "#9A9A96"),   # reserved: 6 m repeat read as shingles
    "M_Wood_Planks": ("dark_wooden_planks", 1.5, 0.70, 0.0, "#5E4530"),
    "M_Roof_Bitumen": ("bitumen", 2.0, 0.90, 0.0, "#2A2A2C"),
}
# flat or generated slots: base sRGB hex, roughness, metallic, emission hex, strength
FLAT_SLOTS = {
    "M_WindowAtlas": dict(base="#202838", rough=0.25, metal=0.0, emit="#FFFFFF", estr=3.0, tint="#7A7A70",
                          gen=["window_atlas_basecolor.png", "window_atlas_emissive.png"],
                          uv="0..1 over an 8x8 tile atlas, one tile per pane"),
    "M_ShopInterior": dict(base="#3A2A1E", rough=0.8, metal=0.0, emit="#FFFFFF", estr=2.0, tint="#6A4A30",
                           gen=["shop_interior_basecolor.png", "shop_interior_emissive.png"],
                           uv="2x2 atlas: each shop picks one 0.5 UV card (goods, cafe, boutique, bar)"),
    "M_ShopGlass": dict(base="#0A1220", rough=0.05, metal=0.0, emit="#000000", estr=0.0, tint="#1A2638",
                        alpha=0.25, uv="metres (flat glass, tint only; BLEND so the lit interior card shows)"),
    "M_Frame": dict(base="#2B2F38", rough=0.55, metal=0.2, emit="#000000", estr=0.0, tint="#2B2F38",
                    uv="metres"),
    "M_SignBand": dict(base="#1A1E2A", rough=0.5, metal=0.1, emit="#000000", estr=0.0, tint="#1A1E2A",
                       uv="metres; neutral band, props agent places signs on anchors"),
    "M_Awning_Red": dict(base="#7A1F1C", rough=0.9, metal=0.0, emit="#000000", estr=0.0, tint="#7A1F1C", uv="metres"),
    "M_Awning_Teal": dict(base="#1E5A58", rough=0.9, metal=0.0, emit="#000000", estr=0.0, tint="#1E5A58", uv="metres"),
    "M_Aircraft_Red": dict(base="#2A0505", rough=0.5, metal=0.0, emit="#FF3B30", estr=6.0, tint="#401010", uv="metres"),
    "M_CeilingStrip": dict(base="#E8F0FF", rough=0.6, metal=0.0, emit="#BFD8FF", estr=5.0, tint="#BFD8FF", uv="metres"),
    "M_CollisionOnly": dict(base="#FFFFFF", rough=1.0, metal=0.0, emit="#000000", estr=0.0, tint="#808080",
                            uv="collider only, never rendered"),
    "M_ImpostorAtlas": dict(base="#FFFFFF", rough=0.8, metal=0.0, emit="#FFFFFF", estr=2.0, tint="#808080",
                            gen=["impostor_<building>_basecolor.png", "impostor_<building>_emissive.png"],
                            uv="0..1 atlas: TL front, TR back, BL left, BR right, BL corner 0.03 = roof"),
}


def hex2rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]


def srgb_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin_hex(h):
    return [srgb_lin(c) for c in hex2rgb(h)] + [1.0]


def mat_info(name):
    if name in CC0_SLOTS:
        cc, tile, rough, metal, tint = CC0_SLOTS[name]
        return dict(base="#FFFFFF", rough=rough, metal=metal, emit="#000000", estr=0.0, tint=tint,
                    cc0=cc, uv_tile_m=tile, uv="metres, tiled every uv_tile_m")
    return FLAT_SLOTS[name]


def ensure_mat(name):
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    info = mat_info(name)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = lin_hex(info["base"])
    bsdf.inputs["Roughness"].default_value = info["rough"]
    bsdf.inputs["Metallic"].default_value = info["metal"]
    if info["estr"] > 0.0:
        bsdf.inputs["Emission Color"].default_value = lin_hex(info["emit"])
        bsdf.inputs["Emission Strength"].default_value = info["estr"]
    if info.get("alpha", 1.0) < 1.0:
        bsdf.inputs["Alpha"].default_value = info["alpha"]
        m.surface_render_method = "BLENDED"
    return m


# ----------------------------------------------------------------------------- PNG and textures
def write_png(path, arr):
    arr = np.ascontiguousarray(arr)
    if arr.dtype != np.uint8:
        arr = np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)
    h, w, c = arr.shape
    ctype = 6 if c == 4 else 2
    raw = b"".join(b"\x00" + arr[y].tobytes() for y in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(png)


_g = np.mgrid[0:TS, 0:TS].astype(np.float32) / TS
YY, XX = _g[0], _g[1]


def _mix(a, b, t):
    return a[None, None, :] * (1.0 - t[..., None]) + b[None, None, :] * t[..., None]


def tile_gen(idx, rng):
    """One 256 px window pane. idx 0-15 dark, 16-23 warm blinds, 24-31 warm furniture,
    32-39 cool office grid, 40-47 TV blue, 48-55 curtains, 56-63 warm dim with lamp glow."""
    base = np.zeros((TS, TS, 3), np.float32)
    emi = np.zeros((TS, TS, 3), np.float32)
    nz = np.random.default_rng(rng.randrange(1 << 30)).normal(0.0, 0.012, (TS, TS, 1)).astype(np.float32)
    if idx < 16:
        top = np.array(hex2rgb("#2F4566"), np.float32)
        bot = np.array(hex2rgb("#0B1322"), np.float32)
        base = _mix(top, bot, YY).astype(np.float32)
        streak = (np.sin(XX * np.pi * rng.uniform(3, 9) + rng.uniform(0, 6.3)) * 0.5 + 0.5) ** 4
        base = base + streak[..., None] * 0.05 * np.array([0.5, 0.8, 1.0], np.float32)
    elif idx < 24:
        warm = np.array(hex2rgb("#FFB36B"), np.float32)
        room = np.array(hex2rgb("#6B4E36"), np.float32)
        blind = np.array(hex2rgb("#CDB08A"), np.float32)
        base[:] = room
        emi[:] = warm * (0.95 - 0.2 * YY)[..., None]
        lower = (YY >= 0.5)[..., None]
        stripe = (np.floor(YY * TS / 5.0) % 2)[..., None].astype(np.float32)
        base = np.where(lower, blind * (0.55 + 0.45 * stripe), base)
        emi = np.where(lower, warm * 0.28 * (0.6 + 0.4 * stripe), emi)
    elif idx < 32:
        warm = np.array(hex2rgb("#FFB36B"), np.float32)
        base[:] = np.array(hex2rgb("#A07048"), np.float32)
        emi[:] = warm * 0.9
        sil = ((YY > 0.6) & (YY < 0.86) & (XX > 0.12) & (XX < 0.88)) \
            | ((np.abs(XX - 0.76) < 0.012) & (YY > 0.22) & (YY < 0.8)) \
            | (((XX - 0.76) / 0.07) ** 2 + ((YY - 0.2) / 0.05) ** 2 < 1.0) \
            | (((XX - 0.25) / 0.09) ** 2 + ((YY - 0.66) / 0.12) ** 2 < 1.0)
        base[sil] = np.array([0.05, 0.035, 0.025], np.float32)
        emi[sil] = 0.0
    elif idx < 40:
        cool = np.array(hex2rgb("#BFD8FF"), np.float32)
        base[:] = np.array([0.55, 0.6, 0.66], np.float32)
        emi[:] = cool * 0.9
        grid = (np.abs(((XX * 4) % 1) - 0.5) > 0.47) | (np.abs(((YY * 4) % 1) - 0.5) > 0.47)
        emi[grid] *= 0.25
        base[grid] = np.array([0.1, 0.1, 0.12], np.float32)
        desk = (YY > 0.7) & (XX > 0.2) & (XX < 0.7)
        base[desk] = np.array([0.12, 0.12, 0.14], np.float32)
        emi[desk] *= 0.2
    elif idx < 48:
        blue = np.array(hex2rgb("#3A7BFF"), np.float32)
        base[:] = np.array([0.04, 0.06, 0.12], np.float32)
        scan = 0.75 + 0.25 * np.sin(YY * TS * np.pi * 0.5)
        flick = rng.uniform(0.7, 1.0)
        emi[:] = blue * (0.85 * scan * flick)[..., None]
    elif idx < 56:
        warm = np.array(hex2rgb("#FFB36B"), np.float32)
        base[:] = np.array([0.3, 0.22, 0.16], np.float32)
        emi[:] = warm * 0.55
        fold = 0.5 + 0.5 * np.sin(XX * TS * np.pi * rng.uniform(0.35, 0.5))
        cur = (XX < 0.32) | (XX > 0.68)
        colr = np.array(hex2rgb("#7E2D2A"), np.float32) * (0.6 + 0.4 * fold)[..., None]
        base = np.where(cur[..., None], colr, base)
        emi = np.where(cur[..., None], 0.0, emi)
    else:
        warm = np.array(hex2rgb("#FFB36B"), np.float32)
        base[:] = np.array([0.25, 0.18, 0.12], np.float32)
        r = np.sqrt((XX - 0.5) ** 2 + (YY - 0.35) ** 2)
        glow = np.clip(1.0 - r * 2.2, 0.0, 1.0)
        emi[:] = warm * (0.25 + 0.6 * glow)[..., None]
    return np.clip(base + nz, 0, 1), np.clip(emi, 0, 1)


def window_atlas(rng):
    A = np.zeros((2048, 2048, 3), np.float32)
    E = np.zeros((2048, 2048, 3), np.float32)
    for t in range(64):
        b, e = tile_gen(t, rng)
        r, c = divmod(t, 8)
        A[r * TS:(r + 1) * TS, c * TS:(c + 1) * TS] = b
        E[r * TS:(r + 1) * TS, c * TS:(c + 1) * TS] = e
    return A, E


def pick_tile(rng, p_lit, cool_p=0.3):
    if rng.random() < p_lit:
        if rng.random() < cool_p:
            return rng.randrange(32, 40)
        return rng.randrange(16, 64)
    return rng.randrange(0, 16)


def tile_uv(t):
    r, c = divmod(t, 8)
    e = 0.004
    u0, u1 = c / 8.0 + e, (c + 1) / 8.0 - e
    vb, vt = 1.0 - (r + 1) / 8.0 + e, 1.0 - r / 8.0 - e
    return [(u0, vb), (u1, vb), (u1, vt), (u0, vt)]


def shop_interior(rng):
    """1024 px atlas, four 512 px interior cards (2x2): 0 goods shelves, 1 cafe, 2 boutique, 3 bar.
    A shop picks one card through its UV rect (see shop_quad)."""
    Q = 512
    base = np.zeros((2 * Q, 2 * Q, 3), np.float32)
    emi = np.zeros((2 * Q, 2 * Q, 3), np.float32)
    yy, xx = np.mgrid[0:Q, 0:Q].astype(np.float32) / Q
    warm = np.array(hex2rgb("#FFB36B"), np.float32)

    def put(qi, b, e):
        r, c = divmod(qi, 2)
        base[r * Q:(r + 1) * Q, c * Q:(c + 1) * Q] = b
        emi[r * Q:(r + 1) * Q, c * Q:(c + 1) * Q] = e

    # 0 goods shelves, coloured packs
    b = np.zeros((Q, Q, 3), np.float32) + np.array(hex2rgb("#3A2A1E"), np.float32)
    e = np.zeros((Q, Q, 3), np.float32) + warm * 0.35
    for row in (0.2, 0.45, 0.7):
        y = int(row * Q) + rng.randrange(-8, 9)
        b[y:y + 10, :] = np.array([0.25, 0.16, 0.1], np.float32)
        x = 8
        while x < Q - 16:
            w = rng.randrange(10, 26)
            h = rng.randrange(40, 70)
            col = np.array([rng.random(), rng.random(), rng.random()], np.float32) * 0.6 + 0.2
            b[y - h:y, x:x + w] = col
            e[y - h:y, x:x + w] = col * 1.1
            x += w + rng.randrange(4, 12)
    put(0, b, np.clip(e, 0, 1))

    # 1 cafe: warm room, pendant lamps, round tables with chairs
    b = np.zeros((Q, Q, 3), np.float32) + np.array([0.3, 0.2, 0.13], np.float32)
    e = np.zeros((Q, Q, 3), np.float32) + warm * (0.55 - 0.25 * yy)[..., None]
    for lx in (0.2, 0.5, 0.8):
        lamp = ((xx - lx) ** 2 + (yy - 0.12) ** 2) < 0.0016
        e[lamp] = warm * 1.0
        b[lamp] = np.array([0.5, 0.4, 0.3], np.float32)
    for tx in (0.25, 0.7):
        table = ((xx - tx) / 0.14) ** 2 + ((yy - 0.78) / 0.05) ** 2 < 1.0
        b[table] = np.array([0.06, 0.04, 0.03], np.float32)
        e[table] *= 0.2
        chair = ((xx - tx) ** 2 / 0.0025 + (yy - 0.88) ** 2 / 0.004) < 1.0
        b[chair] = np.array([0.05, 0.035, 0.025], np.float32)
        e[chair] *= 0.1
    put(1, b, np.clip(e, 0, 1))

    # 2 boutique: pale walls, clothes rail, mannequins
    b = np.zeros((Q, Q, 3), np.float32) + np.array([0.55, 0.58, 0.62], np.float32)
    e = np.zeros((Q, Q, 3), np.float32) + np.array(hex2rgb("#BFD8FF"), np.float32) * 0.45
    rail = (yy > 0.32) & (yy < 0.345) & (xx > 0.08) & (xx < 0.92)
    b[rail] = np.array([0.1, 0.1, 0.12], np.float32)
    for k in range(7):
        x = 0.1 + k * 0.125
        h = (yy > 0.345) & (yy < 0.56) & (np.abs(xx - x) < 0.025)
        b[h] = np.array(hex2rgb(["#7E2D2A", "#1E5A58", "#2B2F38", "#C9A227"][k % 4]), np.float32) * 0.8
    for mx in (0.3, 0.7):
        fig = (((xx - mx) / 0.07) ** 2 + ((yy - 0.66) / 0.08) ** 2 < 1.0) | \
              ((np.abs(xx - mx) < 0.06) & (yy > 0.72) & (yy < 0.95))
        b[fig] = np.array([0.08, 0.07, 0.07], np.float32)
        e[fig] *= 0.15
    put(2, b, np.clip(e, 0, 1))

    # 3 bar: dark wood back-bar, mirror, rows of bottles, counter
    b = np.zeros((Q, Q, 3), np.float32) + np.array([0.12, 0.08, 0.05], np.float32)
    e = np.zeros((Q, Q, 3), np.float32) + warm * 0.3
    mirror = (xx > 0.1) & (xx < 0.9) & (yy > 0.12) & (yy < 0.5)
    e[mirror] = np.array(hex2rgb("#BFD8FF"), np.float32) * (0.35 + 0.25 * xx[mirror])[..., None]
    b[mirror] = np.array([0.05, 0.07, 0.1], np.float32)
    for shelf in (0.55, 0.7):
        ys = int(shelf * Q)
        b[ys:ys + 8, 40:Q - 40] = np.array([0.3, 0.2, 0.12], np.float32)
        x = 50
        while x < Q - 60:
            bw = rng.randrange(8, 14)
            bh = rng.randrange(30, 50)
            col = np.array([rng.random(), rng.random() * 0.7, rng.random() * 0.4], np.float32) * 0.8 + 0.1
            b[ys - bh:ys, x:x + bw] = col
            e[ys - bh:ys, x:x + bw] = col * 0.9
            x += bw + rng.randrange(3, 7)
    b[int(0.85 * Q):, :] = np.array([0.2, 0.13, 0.08], np.float32)
    put(3, b, np.clip(e, 0, 1))
    return base, np.clip(emi, 0, 1)


def shop_quad(q):
    """UV origin of interior card q (0-3) in the 2x2 shop atlas (image row 0 is the top).
    Shops on one building take q = offset + shop index, so neighbours never share a card."""
    r, c = divmod(q % 4, 2)
    return (0.5 * c, 0.5 * (1 - r))


def compose_quad(rng, wall_rgb, cols, rows, shop=True, p_lit=0.35):
    Q = 256
    base = np.zeros((Q, Q, 3), np.float32) + np.array(wall_rgb, np.float32)
    base *= (0.8 + 0.2 * np.linspace(1.0, 0.0, Q, dtype=np.float32))[:, None, None]
    emi = np.zeros((Q, Q, 3), np.float32)
    cw, ch = Q / cols, Q / rows
    for r in range(rows):
        for c in range(cols):
            x0, x1 = int(c * cw + 0.22 * cw), int((c + 1) * cw - 0.22 * cw)
            y0, y1 = int(r * ch + 0.3 * ch), int((r + 1) * ch - 0.2 * ch)
            if r == rows - 1 and shop:
                base[y0:y1, x0:x1] = np.array([0.05, 0.04, 0.03], np.float32)
                emi[y0:y1, x0:x1] = np.array(hex2rgb("#FFB36B"), np.float32) * 0.8
            elif rng.random() < p_lit:
                col = np.array(hex2rgb("#FFB36B") if rng.random() < 0.6 else hex2rgb("#BFD8FF"), np.float32)
                base[y0:y1, x0:x1] = col * 0.3
                emi[y0:y1, x0:x1] = col * 0.9
            else:
                base[y0:y1, x0:x1] = np.array([0.06, 0.09, 0.14], np.float32)
    return base, emi


def impostor_atlas(rng, sp, var):
    wall = hex2rgb(mat_info(var["wall"])["tint"])
    rows = min(sp["storeys"], 24)
    cols_f = max(3, int(sp["W"] / 3.3))
    cols_s = max(3, int(sp["D"] / 3.3))
    parts = [compose_quad(rng, wall, cols_f, rows), compose_quad(rng, wall, cols_f, rows, shop=False),
             compose_quad(rng, wall, cols_s, rows, shop=False), compose_quad(rng, wall, cols_s, rows, shop=False)]
    B = np.zeros((512, 512, 3), np.float32)
    E = np.zeros((512, 512, 3), np.float32)
    # TL front, TR back (top row), BL left, BR right (bottom row); image row 0 is top
    pos = [(0, 0), (0, 256), (256, 0), (256, 256)]
    for (r0, c0), (b, e) in zip(pos, parts):
        B[r0:r0 + 256, c0:c0 + 256] = b
        E[r0:r0 + 256, c0:c0 + 256] = e
    B[496:512, 0:16] = np.array(hex2rgb("#2A2A2C"), np.float32)   # roof patch (uv 0..0.03 in BL)
    return B, E


# ----------------------------------------------------------------------------- geometry builder
def metre_uv(p, n):
    if abs(n.z) > 0.5:
        return (p.x, p.y)
    if abs(n.x) > abs(n.y):
        return (p.y, p.z)
    return (p.x, p.z)


class Builder:
    def __init__(self):
        self.parts = {}
        self.anchors = []
        self.win_total = 0
        self.win_lit = 0
        self.reveal_min = 9.0
        self.curtain_min = 9.0

    def poly(self, pts, n, mat, uvs=None):
        pts = [Vector(p) for p in pts]
        n = Vector(n).normalized()
        if len(pts) >= 3:
            c = (pts[1] - pts[0]).cross(pts[2] - pts[0])
            if c.length < 1e-9:
                return
            if c.dot(n) < 0.0:
                pts = pts[::-1]
                if uvs is not None:
                    uvs = list(uvs)[::-1]
        if uvs is None:
            uvs = [metre_uv(p, n) for p in pts]
        self.parts.setdefault(mat, []).append((pts, [tuple(u) for u in uvs]))

    def box(self, mn, mx, mat, top=None, side=None):
        x0, y0, z0 = mn
        x1, y1, z1 = mx
        mt = top or mat
        ms = side or mat
        self.poly([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1), mt)
        self.poly([(x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0)], (0, 0, -1), ms)
        self.poly([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1, 0, 0), ms)
        self.poly([(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], (-1, 0, 0), ms)
        self.poly([(x0, y1, z0), (x0, y1, z1), (x1, y1, z1), (x1, y1, z0)], (0, 1, 0), ms)
        self.poly([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0), ms)

    def prism(self, cx, cy, z0, r, h, n, mat):
        ring0 = [(cx + r * math.cos(2 * math.pi * k / n), cy + r * math.sin(2 * math.pi * k / n), z0) for k in range(n)]
        ring1 = [(p[0], p[1], z0 + h) for p in ring0]
        for k in range(n):
            k1 = (k + 1) % n
            a = 2 * math.pi * (k + 0.5) / n
            self.poly([ring0[k], ring0[k1], ring1[k1], ring1[k]], (math.cos(a), math.sin(a), 0), mat)
        self.poly(ring1, (0, 0, 1), mat)

    def anchor(self, name, p, n):
        self.anchors.append((name, Vector(p), Vector(n).normalized()))

    def tris(self):
        t = {}
        for mat, polys in self.parts.items():
            t[mat] = sum(len(p) - 2 for p, _ in polys)
        return t

    def total_tris(self):
        return sum(self.tris().values())


class Face:
    def __init__(self, O, A, N, W, H):
        self.O = Vector(O)
        self.A = Vector(A)
        self.N = Vector(N)
        self.W = float(W)
        self.H = float(H)

    def P(self, u, v, t=0.0):
        return self.O + self.A * u + Z * v - self.N * t


def fbox(b, f, u0, u1, v0, v1, t0, t1, mat, top=None, side=None):
    pts = [f.P(u, v, t) for u in (u0, u1) for v in (v0, v1) for t in (t0, t1)]
    mn = (min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))
    mx = (max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))
    b.box(mn, mx, mat, top, side)


def quad_face(b, f, u0, u1, v0, v1, t, mat):
    pts = [f.P(u0, v0, t), f.P(u1, v0, t), f.P(u1, v1, t), f.P(u0, v1, t)]
    b.poly(pts, f.N, mat)


def wall_decomp(b, f, ops, wall, base, gh):
    vs = sorted(set([0.0, f.H] + [o["v0"] for o in ops] + [o["v1"] for o in ops]))
    for va, vb in zip(vs[:-1], vs[1:]):
        if vb - va < 1e-4:
            continue
        mid = 0.5 * (va + vb)
        mat = base if mid < gh else wall
        band = sorted([o for o in ops if o["v0"] <= mid <= o["v1"]], key=lambda o: o["u0"])
        cur = 0.0
        for o in band:
            if o["u0"] > cur + 1e-4:
                quad_face(b, f, cur, o["u0"], va, vb, 0.0, mat)
            cur = max(cur, o["u1"])
        if cur < f.W - 1e-4:
            quad_face(b, f, cur, f.W, va, vb, 0.0, mat)


def emit_ops(b, f, ops, detail):
    for o in ops:
        r = o.get("r", 0.0)
        u0, u1, v0, v1 = o["u0"], o["u1"], o["v0"], o["v1"]
        wm = o["wall"]
        kind = o["kind"]
        if kind == "win":
            b.win_total += 1
            if o.get("tile", 0) >= 16:
                b.win_lit += 1
        if detail and r > 0.0 and kind != "open":
            b.poly([f.P(u0, v0, 0), f.P(u0, v0, r), f.P(u0, v1, r), f.P(u0, v1, 0)], f.A, wm)
            b.poly([f.P(u1, v0, 0), f.P(u1, v1, 0), f.P(u1, v1, r), f.P(u1, v0, r)], -f.A, wm)
            b.poly([f.P(u0, v1, 0), f.P(u1, v1, 0), f.P(u1, v1, r), f.P(u0, v1, r)], -Z, wm)
            b.poly([f.P(u0, v0, 0), f.P(u0, v0, r), f.P(u1, v0, r), f.P(u1, v0, 0)], Z, wm)
            if kind == "win":
                b.reveal_min = min(b.reveal_min, r)
        if kind != "open" and o.get("glass"):
            pts = [f.P(u0, v0, r), f.P(u1, v0, r), f.P(u1, v1, r), f.P(u0, v1, r)]
            b.poly(pts, f.N, o["glass"], o.get("uv"))
        if kind == "shop" and o.get("interior"):
            pts = [f.P(u0 + 0.06, v0 + 0.06, 0.9), f.P(u1 - 0.06, v0 + 0.06, 0.9),
                   f.P(u1 - 0.06, v1 - 0.06, 0.9), f.P(u0 + 0.06, v1 - 0.06, 0.9)]
            qu, qv = o.get("q", (0.0, 0.0))
            b.poly(pts, f.N, "M_ShopInterior", [(qu + 0.01, qv + 0.01), (qu + 0.49, qv + 0.01),
                                                (qu + 0.49, qv + 0.49), (qu + 0.01, qv + 0.49)])
        if kind == "shop" and detail:
            fbox(b, f, u0 - 0.06, u1 + 0.06, 0.0, v0, -0.12, r, wm)   # stall riser
        if detail and o.get("bars"):
            um, vm = 0.5 * (u0 + u1), 0.5 * (v0 + v1)
            fbox(b, f, um - 0.03, um + 0.03, v0, v1, r - 0.07, r, "M_Frame")
            fbox(b, f, u0, u1, vm - 0.03, vm + 0.03, r - 0.07, r, "M_Frame")
        if detail and o.get("sill") and kind == "win":
            fbox(b, f, u0 - 0.05, u1 + 0.05, v0 - 0.09, v0 + 0.02, -0.08, r, wm)
            fbox(b, f, u0 - 0.04, u1 + 0.04, v1, v1 + 0.08, -0.06, 0.0, "M_Frame")
        if detail and o.get("balc"):
            fbox(b, f, u0 - 0.2, u1 + 0.2, v0 - 0.28, v0 - 0.14, -0.9, 0.0, wm)
            fbox(b, f, u0 - 0.2, u1 + 0.2, v0 + 0.7, v0 + 0.75, -0.92, -0.88, "M_Metal_Painted")
            fbox(b, f, u0 - 0.2, u0 - 0.15, v0 - 0.14, v0 + 0.75, -0.92, -0.88, "M_Metal_Painted")
            fbox(b, f, u1 + 0.15, u1 + 0.2, v0 - 0.14, v0 + 0.75, -0.92, -0.88, "M_Metal_Painted")
        if detail and o.get("ac"):
            fbox(b, f, u0 + 0.15, u0 + 0.85, v0 - 0.62, v0 - 0.16, -0.55, 0.0, "M_Metal_Painted")


def face_details(b, f, bays, gh, uh, storeys, trim, detail):
    if not detail:
        return
    for k in range(bays + 1):
        u = k * f.W / bays
        u0, u1 = max(0.0, u - 0.18), min(f.W, u + 0.18)
        fbox(b, f, u0, u1, gh, f.H, -0.2, 0.0, trim)
    for fl in range(1, storeys):
        vb = gh + (fl - 1) * uh
        fbox(b, f, 0.0, f.W, vb - 0.02, vb + 0.14, -0.10, 0.0, trim)


def street_ops(f, rng, detail, role, shops, bays, gh, uh, storeys, wall, base):
    ops = []
    W = f.W
    if role == "street" and shops > 0:
        uw = W / shops
        off = rng.randrange(4)
        for k in range(shops):
            a = k * uw
            e = a + uw
            ops.append(dict(kind="door", u0=a + 0.3, u1=a + 1.2, v0=0.0, v1=2.35,
                            r=0.35 if detail else 0.05, glass="M_Metal_Painted", wall=base))
            ops.append(dict(kind="shop", u0=a + 1.4, u1=e - 0.35, v0=0.55, v1=2.85,
                            r=0.5 if detail else 0.1, glass="M_ShopGlass", wall=base, interior=True,
                            q=shop_quad(off + k)))
    else:
        du = min(1.0, W * 0.3)
        ops.append(dict(kind="door", u0=du, u1=du + 0.9, v0=0.0, v1=2.3,
                        r=0.2 if detail else 0.05, glass="M_Metal_Painted", wall=base))
        cu = W * 0.7
        ops.append(dict(kind="win", u0=cu - 0.5, u1=cu + 0.5, v0=1.3, v1=2.5, r=0.2 if detail else 0.05,
                        glass="M_WindowAtlas", uv=tile_uv(pick_tile(rng, LIT_P)), tile=0, wall=base,
                        bars=bool(detail), sill=bool(detail)))
    nb = bays if role == "street" else max(2, int(round(W / 3.6)))
    bw = W / nb
    for fl in range(1, storeys):
        vb = gh + (fl - 1) * uh
        bias = rng.uniform(-0.12, 0.12)
        for bi in range(nb):
            cu = (bi + 0.5) * bw
            t = pick_tile(rng, LIT_P + bias)
            ops.append(dict(kind="win", u0=cu - 0.6, u1=cu + 0.6, v0=vb + 0.95, v1=vb + 2.45,
                            r=0.17 if detail else 0.05, glass="M_WindowAtlas", uv=tile_uv(t), tile=t,
                            wall=wall, bars=bool(detail), sill=bool(detail),
                            balc=bool(detail and role == "street" and rng.random() < 0.22),
                            ac=bool(detail and rng.random() < 0.3)))
    return ops


def curtain_ops(f, rng, detail, nfl, fh, wall, mullion_bays):
    ops = []
    nb = mullion_bays
    bw = f.W / nb
    for fl in range(nfl):
        vb = fl * fh
        bias = rng.uniform(-0.12, 0.12)
        for bi in range(nb):
            t = pick_tile(rng, 0.45 + bias, cool_p=0.5)
            r = 0.12 if detail else 0.02
            ops.append(dict(kind="win", u0=bi * bw + 0.12, u1=(bi + 1) * bw - 0.12, v0=vb + 0.25, v1=vb + fh - 0.25,
                            r=r, glass="M_WindowAtlas", uv=tile_uv(t), tile=t, wall=wall, bars=False, sill=False))
    return ops


def rooftop(b, sp, x0, x1, y0, y1, z, rng):
    for _ in range(rng.randint(3, 6)):
        cx = rng.uniform(x0 + 1.5, x1 - 1.5)
        cy = rng.uniform(y0 + 1.5, y1 - 1.5)
        b.box((cx - 0.6, cy - 0.45, z), (cx + 0.6, cy + 0.45, z + 0.8), "M_Metal_Painted")
    tx, ty = x1 - 2.6, y0 + 3.0
    b.prism(tx, ty, z, 1.2, 2.2, 8, "M_Metal_Corrugated")
    ax, ay = x0 + 2.2, y1 - 2.2
    b.box((ax - 0.08, ay - 0.08, z), (ax + 0.08, ay + 0.08, z + 8.0), "M_Metal_Painted")
    b.box((ax - 0.15, ay - 0.15, z + 8.0), (ax + 0.15, ay + 0.15, z + 8.3), "M_Aircraft_Red")
    lx = x1 - 0.9
    for k in range(-1, 2):
        pass
    b.box((lx - 0.22, y1, z), (lx - 0.14, y1 + 0.18, z + 3.0), "M_Metal_Painted")
    b.box((lx + 0.14, y1, z), (lx + 0.22, y1 + 0.18, z + 3.0), "M_Metal_Painted")
    for k in range(6):
        zr = z + 0.4 + k * 0.45
        b.box((lx - 0.14, y1 + 0.02, zr), (lx + 0.14, y1 + 0.1, zr + 0.06), "M_Metal_Painted")


def billboard(b, x0, y0, z, rng, anchors_name):
    bx0, bx1 = x0 + 1.5, x0 + 7.5
    bz0, bz1 = z + 2.0, z + 5.0
    y = y0 + 0.9
    b.box((bx0 + 0.2, y - 0.1, z), (bx0 + 0.45, y + 0.1, bz0), "M_Metal_Painted")
    b.box((bx1 - 0.45, y - 0.1, z), (bx1 - 0.2, y + 0.1, bz0), "M_Metal_Painted")
    b.box((bx0, y - 0.25, bz0), (bx1, y + 0.25, bz0 + 0.2), "M_Metal_Painted")
    b.box((bx0, y - 0.25, bz1), (bx1, y + 0.25, bz1 + 0.2), "M_Metal_Painted")
    b.box((bx0, y - 0.25, bz0), (bx0 + 0.2, y + 0.25, bz1 + 0.2), "M_Metal_Painted")
    b.box((bx1 - 0.2, y - 0.25, bz0), (bx1, y + 0.25, bz1 + 0.2), "M_Metal_Painted")
    b.poly([(bx0 + 0.2, y - 0.2, bz0 + 0.2), (bx1 - 0.2, y - 0.2, bz0 + 0.2),
            (bx1 - 0.2, y - 0.2, bz1), (bx0 + 0.2, y - 0.2, bz1)], (0, -1, 0), "M_SignBand")
    b.anchor(anchors_name, (0.5 * (bx0 + bx1), y - 0.2, 0.5 * (bz0 + bz1)), (0, -1, 0))


# ----------------------------------------------------------------------------- building types
def build_strip(sp, var, lod, rng):
    b = Builder()
    W, D = sp["W"], sp["D"]
    gh, uh, S = sp["gh"], sp["uh"], sp["storeys"]
    H = gh + (S - 1) * uh
    detail = lod == 0
    wall, base = var["wall"], var["base"]
    faces = {
        "front": Face((-W / 2, 0, 0), (1, 0, 0), (0, -1, 0), W, H),
        "right": Face((W / 2, 0, 0), (0, 1, 0), (1, 0, 0), D, H),
        "back": Face((W / 2, D, 0), (-1, 0, 0), (0, 1, 0), W, H),
        "left": Face((-W / 2, D, 0), (0, -1, 0), (-1, 0, 0), D, H),
    }
    for name, f in faces.items():
        role = "street" if name == "front" else "side"
        dface = detail and role == "street"   # side and back walls: flat glazing, no reveals (budget)
        ops = street_ops(f, rng, dface, role, sp["shops"], sp["bays"], gh, uh, S, wall, base)
        wall_decomp(b, f, ops, wall, base, gh)
        emit_ops(b, f, ops, dface)
        if lod <= 1:
            face_details(b, f, sp["bays"] if role == "street" else 3, gh, uh, S, wall, detail)
        if role == "street":
            uw = W / sp["shops"]
            fbox(b, f, 0.0, W, 2.95, 3.85, -0.15, 0.0, "M_SignBand")
            for k in range(sp["shops"]):
                a, e = k * uw, (k + 1) * uw
                b.poly([f.P(a + 0.2, 2.9, 0), f.P(e - 0.2, 2.9, 0), f.P(e - 0.2, 2.35, -1.45), f.P(a + 0.2, 2.35, -1.45)],
                       f.N * 0.55 + Z * 1.45, var["awn"])
                if detail:
                    fbox(b, f, a + 0.1, e - 0.1, 2.85, 2.9, -1.45, -1.4, "M_Metal_Painted")
            if lod == 0:
                for k in range(sp["shops"]):
                    a, e = k * uw, (k + 1) * uw
                    b.anchor("anchor_sign_%02d" % (k + 1), f.P(0.5 * (a + e), 3.4, -0.2), f.N)
                for k in range(sp["blades"]):
                    u = 0.5 + k * (W - 1.0) / max(1, sp["blades"] - 1) if sp["blades"] > 1 else W / 2
                    b.anchor("anchor_blade_%02d" % (k + 1), f.P(u, gh + 2.0 * uh, -0.1), f.N)
    # roof closure, cornice
    b.poly([(-W / 2, 0, H), (W / 2, 0, H), (W / 2, D, H), (-W / 2, D, H)], (0, 0, 1), "M_Roof_Bitumen")
    b.box((-W / 2 - 0.3, -0.4, H), (W / 2 + 0.3, D + 0.3, H + 0.4), "M_Concrete_Smooth", top="M_Roof_Bitumen")
    if lod == 0:
        rooftop(b, sp, -W / 2, W / 2, 0.0, D, H + 0.4, rng)
        if sp["roofbb"]:
            billboard(b, -W / 2, 0.0, H + 0.4, rng, "anchor_roof_01")
    return b


def build_tower(sp, var, lod, rng):
    b = Builder()
    W, D, S = sp["W"], sp["D"], sp["storeys"]
    detail = lod == 0
    Hp = 4.5 + 3 * 3.6
    Wt, Dt = W - 4.0, D - 4.0
    y0t = 2.5
    main_fl = S - 4 - 3
    Hm = Hp + main_fl * 3.8
    Hc = Hm + 3 * 3.8
    # podium
    pf = {
        "front": Face((-W / 2, 0, 0), (1, 0, 0), (0, -1, 0), W, Hp),
        "right": Face((W / 2, 0, 0), (0, 1, 0), (1, 0, 0), D, Hp),
        "back": Face((W / 2, D, 0), (-1, 0, 0), (0, 1, 0), W, Hp),
        "left": Face((-W / 2, D, 0), (0, -1, 0), (-1, 0, 0), D, Hp),
    }
    for name, f in pf.items():
        role = "street" if name == "front" else "side"
        ops = street_ops(f, rng, detail, role, sp["shops"], 4, 4.5, 3.6, 4, var["trim"], var["base"])
        wall_decomp(b, f, ops, var["trim"], var["base"], 4.5)
        emit_ops(b, f, ops, detail)
        if role == "street":
            uw = W / sp["shops"]
            fbox(b, f, 0.0, W, 3.0, 4.0, -0.15, 0.0, "M_SignBand")
            for k in range(sp["shops"]):
                a, e = k * uw, (k + 1) * uw
                b.poly([f.P(a + 0.2, 2.9, 0), f.P(e - 0.2, 2.9, 0), f.P(e - 0.2, 2.35, -1.45), f.P(a + 0.2, 2.35, -1.45)],
                       f.N * 0.55 + Z * 1.45, var["awn"])
                if lod == 0:
                    b.anchor("anchor_sign_%02d" % (k + 1), f.P(0.5 * (a + e), 3.5, -0.2), f.N)
    b.poly([(-W / 2, 0, Hp), (W / 2, 0, Hp), (W / 2, D, Hp), (-W / 2, D, Hp)], (0, 0, 1), "M_Roof_Bitumen")
    # tower curtain wall
    nb = max(3, int(round(Wt / 2.9)))
    nbs = max(3, int(round(Dt / 2.9)))
    tf = {
        "front": Face((-Wt / 2, y0t, Hp), (1, 0, 0), (0, -1, 0), Wt, Hm - Hp),
        "right": Face((Wt / 2, y0t, Hp), (0, 1, 0), (1, 0, 0), Dt, Hm - Hp),
        "back": Face((Wt / 2, y0t + Dt, Hp), (-1, 0, 0), (0, 1, 0), Wt, Hm - Hp),
        "left": Face((-Wt / 2, y0t + Dt, Hp), (0, -1, 0), (-1, 0, 0), Dt, Hm - Hp),
    }
    for name, f in tf.items():
        bays = nb if name in ("front", "back") else nbs
        ops = curtain_ops(f, rng, detail and name == "front", main_fl, 3.8, var["wall"], bays if detail else 1)
        wall_decomp(b, f, ops, var["wall"], var["wall"], 0.0)
        emit_ops(b, f, ops, detail and name == "front")
        if name == "front" and detail:
            bw = Wt / bays
            for k in range(bays + 1):
                u = k * bw
                fbox(b, f, u - 0.07, u + 0.07, 0.0, Hm - Hp, -0.16, 0.0, "M_Frame")
        elif lod <= 1 and name == "front":
            pass
    if lod == 0:
        for k, u in enumerate((Wt * 0.25, Wt * 0.75)):
            b.anchor("anchor_blade_%02d" % (k + 1), tf["front"].P(u, 8.0, -0.3), tf["front"].N)
    b.poly([(-Wt / 2, y0t, Hm), (Wt / 2, y0t, Hm), (Wt / 2, y0t + Dt, Hm), (-Wt / 2, y0t + Dt, Hm)], (0, 0, 1),
           "M_Roof_Bitumen")
    # crown: three floors, inset 2 m, red aircraft lights
    Wc, Dc = Wt - 4.0, Dt - 4.0
    xc0, yc0 = y0t + 2.0, 0.0
    cf = {
        "front": Face((-Wc / 2, y0t + 2.0, Hm), (1, 0, 0), (0, -1, 0), Wc, 3 * 3.8),
        "right": Face((Wc / 2, y0t + 2.0, Hm), (0, 1, 0), (1, 0, 0), Dc, 3 * 3.8),
        "back": Face((Wc / 2, y0t + 2.0 + Dc, Hm), (-1, 0, 0), (0, 1, 0), Wc, 3 * 3.8),
        "left": Face((-Wc / 2, y0t + 2.0 + Dc, Hm), (0, -1, 0), (-1, 0, 0), Dc, 3 * 3.8),
    }
    for name, f in cf.items():
        bays = max(3, int(round((Wc if name in ("front", "back") else Dc) / 2.9)))
        ops = curtain_ops(f, rng, detail and name == "front", 3, 3.8, var["wall"], bays if detail else 1)
        wall_decomp(b, f, ops, var["wall"], var["wall"], 0.0)
        emit_ops(b, f, ops, detail and name == "front")
    b.poly([(-Wc / 2, y0t + 2.0, Hc), (Wc / 2, y0t + 2.0, Hc), (Wc / 2, y0t + 2.0 + Dc, Hc),
            (-Wc / 2, y0t + 2.0 + Dc, Hc)], (0, 0, 1), "M_Roof_Bitumen")
    cy = y0t + 2.0 + Dc / 2.0
    if lod == 0:
        for sx in (-1, 1):
            for sy in (-1, 1):
                x = sx * (Wc / 2 - 0.8)
                y = cy + sy * (Dc / 2 - 0.8)
                b.box((x - 0.3, y - 0.3, Hc), (x + 0.3, y + 0.3, Hc + 0.6), "M_Aircraft_Red")
        b.box((-0.2, cy - 0.2, Hc), (0.2, cy + 0.2, Hc + 14.0), "M_Metal_Painted")
        b.box((-0.3, cy - 0.3, Hc + 14.0), (0.3, cy + 0.3, Hc + 14.5), "M_Aircraft_Red")
        b.anchor("anchor_roof_01", (0.0, cy, Hc + 8.0), (0, 0, 1))
    # setback plant on podium roof
    if lod == 0:
        b.box((-W / 2 + 2, 0.5, Hp), (-W / 2 + 6, 4.0, Hp + 1.2), "M_Metal_Painted")
    # LOD fallback tower footprint for box checks
    b.tower_box = ((-Wt / 2, y0t, Hp), (Wt / 2, y0t + Dt, Hm), (-Wc / 2, y0t + 2, Hm), (Wc / 2, y0t + 2 + Dc, Hc))
    return b


def build_market(sp, var, lod, rng):
    b = Builder()
    W, D, S = sp["W"], sp["D"], sp["storeys"]
    gh, uh = 3.2, 3.0
    H = gh + (S - 1) * uh
    detail = lod == 0
    faces = {
        "front": Face((-W / 2, 0, 0), (1, 0, 0), (0, -1, 0), W, H),
        "right": Face((W / 2, 0, 0), (0, 1, 0), (1, 0, 0), D, H),
        "back": Face((W / 2, D, 0), (-1, 0, 0), (0, 1, 0), W, H),
        "left": Face((-W / 2, D, 0), (0, -1, 0), (-1, 0, 0), D, H),
    }
    for name, f in faces.items():
        street = name == "front"
        ops = []
        if street:
            uw = W / 2
            for k in range(2):
                a = k * uw
                e = a + uw
                ops.append(dict(kind="door", u0=a + 0.25, u1=a + 1.05, v0=0.0, v1=2.1, r=0.25 if detail else 0.05,
                                glass="M_Wood_Planks", wall=var["base"]))
                ops.append(dict(kind="shop", u0=a + 1.2, u1=e - 0.25, v0=0.5, v1=2.05, r=0.3 if detail else 0.05,
                                glass="M_ShopGlass" if k == 0 else "M_Metal_Corrugated", wall=var["base"],
                                interior=(k == 0), q=shop_quad(rng.randrange(4))))
            for fl in range(1, S):
                vb = gh + (fl - 1) * uh
                for k in range(2):
                    cu = (k + 0.5) * uw
                    t = pick_tile(rng, LIT_P + rng.uniform(-0.1, 0.1))
                    ops.append(dict(kind="win", u0=cu - 0.6, u1=cu + 0.6, v0=vb + 0.85, v1=vb + 2.25,
                                    r=0.14 if detail else 0.05, glass="M_WindowAtlas", uv=tile_uv(t), tile=t,
                                    wall=var["wall"], bars=False, sill=bool(detail)))
        else:
            nb = 2 if name == "back" else max(2, int(round(W / 3.0)))
            for fl in range(1, S):
                vb = gh + (fl - 1) * uh
                for bi in range(nb if name != "back" else 1):
                    cu = (bi + 0.5) * (W if name == "back" else (D if False else (D if name in ("right", "left") else W))) / (nb if name != "back" else 1)
                    span = W if name in ("back",) else D
                    cu = (bi + 0.5) * span / nb
                    t = pick_tile(rng, LIT_P + rng.uniform(-0.1, 0.1))
                    ops.append(dict(kind="win", u0=cu - 0.5, u1=cu + 0.5, v0=vb + 0.85, v1=vb + 2.25,
                                    r=0.14 if detail else 0.05, glass="M_WindowAtlas", uv=tile_uv(t), tile=t,
                                    wall=var["wall"], bars=False, sill=bool(detail)))
            ops.append(dict(kind="door", u0=0.8, u1=1.8, v0=0.0, v1=2.1, r=0.2 if detail else 0.05,
                            glass="M_Metal_Corrugated", wall=var["base"]))
        wall_decomp(b, f, ops, var["wall"], var["base"], gh)
        emit_ops(b, f, ops, detail)
        if detail and not street:
            for o in ops:
                if o["kind"] == "win":
                    fbox(b, f, o["u0"] - 0.42, o["u0"] - 0.04, o["v0"], o["v1"], -0.06, 0.0, "M_Metal_Painted")
                    fbox(b, f, o["u1"] + 0.04, o["u1"] + 0.42, o["v0"], o["v1"], -0.06, 0.0, "M_Metal_Painted")
            for k in range(int(f.W / 0.3)):
                u = k * 0.3 + 0.1
                fbox(b, f, u, u + 0.16, H - 0.08, H + 0.02, -0.22, 0.0, var["trim"])
        if street:
            uw = W / 2
            if detail:
                for k in range(2):
                    a, e = k * uw, (k + 1) * uw
                    fbox(b, f, a, a + 0.2, 0.0, H, -0.12, 0.0, var["trim"])
                    fbox(b, f, e - 0.2, e, 0.0, H, -0.12, 0.0, var["trim"])
                    fbox(b, f, a + 0.35, e - 0.35, 2.05, 2.15, -0.08, 0.0, var["trim"])
                    fbox(b, f, a + 0.35, a + 0.95, 0.9, 1.0, -0.03, 0.0, "M_Frame")
                    fbox(b, f, a + 0.35, a + 0.95, 1.9, 2.0, -0.03, 0.0, "M_Frame")
                    fbox(b, f, a + 0.15, e - 0.15, 1.9, 1.95, -1.2, -1.15, var["awn"])
                    fbox(b, f, a + 1.2, e - 0.25, 0.0, 0.5, -0.14, 0.0, var["trim"])
                    for bx in (a + 0.3, (a + e) / 2, e - 0.3):
                        fbox(b, f, bx - 0.04, bx + 0.04, 2.4, 2.9, -0.5, -0.14, "M_Metal_Painted")
                for k in range(int(W / 0.3)):
                    u = k * 0.3 + 0.1
                    fbox(b, f, u, u + 0.16, H - 0.08, H + 0.02, -0.22, 0.0, var["trim"])
                for k in range(int(W / 0.5)):
                    u = k * 0.5 + 0.2
                    fbox(b, f, u, u + 0.12, H + 0.5, H + 0.9, -0.1, 0.0, var["trim"])
            for k in range(2):
                a, e = k * uw, (k + 1) * uw
                fbox(b, f, a + 0.12, e - 0.12, 2.4, 3.0, -0.14, 0.0, "M_SignBand")
                b.poly([f.P(a + 0.15, 2.35, 0), f.P(e - 0.15, 2.35, 0), f.P(e - 0.15, 1.95, -1.2),
                        f.P(a + 0.15, 1.95, -1.2)], f.N * 0.5 + Z * 1.2, var["awn"])
                if lod == 0:
                    b.anchor("anchor_sign_%02d" % (k + 1), f.P(0.5 * (a + e), 2.7, -0.18), f.N)
                    fbox(b, f, a + 0.3, a + 0.45, 1.8, 2.25, -0.55, -0.45, "M_Metal_Painted")
            for k in range(2):
                cu = (k + 0.5) * uw
                for fl in range(1, S):
                    vb = gh + (fl - 1) * uh
                    if lod == 0:
                        fbox(b, f, cu - 0.6 - 0.4, cu - 0.6 - 0.04, vb + 0.85, vb + 2.25, -0.06, 0.0, "M_Metal_Painted")
                        fbox(b, f, cu + 0.6 + 0.04, cu + 0.6 + 0.4, vb + 0.85, vb + 2.25, -0.06, 0.0, "M_Metal_Painted")
                        fbox(b, f, cu - 0.66, cu + 0.66, vb + 0.6, vb + 0.85, -0.25, 0.0, "M_Wood_Planks")
                        fbox(b, f, cu - 0.7, cu + 0.7, vb + 2.3, vb + 2.36, -0.08, 0.0, "M_Frame")
            if lod == 0:
                b.anchor("anchor_blade_01", f.P(W / 2, gh + uh, -0.12), f.N)   # blade sign between the window bays
            if detail:
                # quoins at the corners
                for k in range(int(H / 0.45)):
                    if k % 2 == 0:
                        fbox(b, f, 0.0, 0.22, k * 0.45, k * 0.45 + 0.4, -0.1, 0.0, var["trim"])
                        fbox(b, f, W - 0.22, W, k * 0.45, k * 0.45 + 0.4, -0.1, 0.0, var["trim"])
                for k in range(int(W / 0.6)):
                    u = k * 0.6 + 0.3
                    fbox(b, f, u - 0.12, u + 0.12, H - 0.5, H - 0.1, -0.35, 0.0, var["trim"])
            fbox(b, f, -0.25, W + 0.25, H, H + 0.5, -0.4, 0.0, var["trim"], top="M_Roof_Bitumen")
    b.poly([(-W / 2, 0, H), (W / 2, 0, H), (W / 2, D, H), (-W / 2, D, H)], (0, 0, 1), "M_Roof_Bitumen")
    if lod == 0:
        rooftop(b, sp, -W / 2, W / 2, 0.0, D, H + 0.5, rng)
    return b


def roof_prism(b, x0, x1, y0, y1, eave, ridge, mat, uvpatch=False):
    xm = 0.5 * (x0 + x1)
    hw, dh = (x1 - x0) / 2.0, ridge - eave
    uv = [(0.006, 0.006), (0.02, 0.006), (0.02, 0.02), (0.006, 0.02)] if uvpatch else None
    b.poly([(x0, y0, eave), (x0, y1, eave), (xm, y1, ridge), (xm, y0, ridge)], (-dh, 0, hw), mat,
           uv)
    b.poly([(x1, y0, eave), (xm, y0, ridge), (xm, y1, ridge), (x1, y1, eave)], (dh, 0, hw), mat,
           uv[::-1] if uv else None)
    tri_uv = [(0.006, 0.006), (0.02, 0.006), (0.013, 0.02)] if uvpatch else None
    b.poly([(x0, y0, eave), (x1, y0, eave), (xm, y0, ridge)], (0, -1, 0), mat, tri_uv)
    b.poly([(x1, y1, eave), (x0, y1, eave), (xm, y1, ridge)], (0, 1, 0), mat, tri_uv)


def build_warehouse(sp, var, lod, rng):
    b = Builder()
    W, D = sp["W"], sp["D"]
    eave, ridge = 9.0, 12.5
    detail = lod == 0
    wall = var["wall"]
    faces = {
        "front": Face((-W / 2, 0, 0), (1, 0, 0), (0, -1, 0), W, eave),
        "right": Face((W / 2, 0, 0), (0, 1, 0), (1, 0, 0), D, eave),
        "back": Face((W / 2, D, 0), (-1, 0, 0), (0, 1, 0), W, eave),
        "left": Face((-W / 2, D, 0), (0, -1, 0), (-1, 0, 0), D, eave),
    }
    for name, f in faces.items():
        ops = []
        if name == "front":
            for u0 in (3.0, 13.0):
                ops.append(dict(kind="door", u0=u0, u1=u0 + 8.0, v0=0.0, v1=5.5, r=0.2 if detail else 0.05,
                                glass="M_Metal_Painted", wall=wall))
            for k in range(8):
                u = 1.0 + 2.9 * k
                t = pick_tile(rng, LIT_P)
                ops.append(dict(kind="win", u0=u, u1=u + 1.4, v0=6.4, v1=7.8, r=0.15 if detail else 0.05,
                                glass="M_WindowAtlas", uv=tile_uv(t), tile=t, wall=wall, bars=detail, sill=detail))
        else:
            span = W if name == "back" else D
            n = int(span / 4.0)
            for k in range(n):
                u = 2.0 + k * 4.0
                if u + 1.4 > span:
                    break
                t = pick_tile(rng, LIT_P)
                ops.append(dict(kind="win", u0=u, u1=u + 1.4, v0=6.4, v1=7.8, r=0.15 if detail else 0.05,
                                glass="M_WindowAtlas", uv=tile_uv(t), tile=t, wall=wall, bars=detail, sill=detail))
            if name == "back":
                ops.append(dict(kind="door", u0=W / 2 - 2.5, u1=W / 2 + 2.5, v0=0.0, v1=5.5,
                                r=0.2 if detail else 0.05, glass="M_Metal_Painted", wall=wall))
        wall_decomp(b, f, ops, wall, wall, 0.0)
        emit_ops(b, f, ops, detail)
        if detail:
            span = W if name in ("front", "back") else D
            for k in range(int(span / 2.0) + 1):
                u = min(span - 0.15, k * 2.0)
                if any(u < o["u1"] + 0.3 and o["u0"] - 0.3 < u + 0.15 for o in ops):
                    continue   # no rib across a door or window opening
                fbox(b, f, u, u + 0.15, 0.0, eave, -0.2, 0.0, "M_Metal_Painted")
            for o in ops:
                if o["kind"] == "door" and o["v1"] > 3.0:   # roller door slats, jambs and header
                    for z in np.arange(0.45, o["v1"] - 0.2, 0.42):
                        fbox(b, f, o["u0"] + 0.05, o["u1"] - 0.05, float(z), float(z) + 0.05, -0.06, 0.0,
                             "M_Metal_Painted")
                    fbox(b, f, o["u0"] - 0.14, o["u0"], 0.0, o["v1"] + 0.15, -0.22, 0.0, "M_Metal_Painted")
                    fbox(b, f, o["u1"], o["u1"] + 0.14, 0.0, o["v1"] + 0.15, -0.22, 0.0, "M_Metal_Painted")
                    fbox(b, f, o["u0"] - 0.14, o["u1"] + 0.14, o["v1"], o["v1"] + 0.15, -0.22, 0.0, "M_Metal_Painted")
        if name == "front":
            fbox(b, f, 2.0, W - 2.0, 5.6, 5.9, -3.0, 0.0, "M_Metal_Painted")
            fbox(b, f, 2.0, 2.3, 0.0, 5.6, -3.0, -2.7, "M_Metal_Painted")
            fbox(b, f, W - 2.3, W - 2.0, 0.0, 5.6, -3.0, -2.7, "M_Metal_Painted")
            if detail:
                for k in range(6):
                    u = 1.5 + k * 4.0
                    fbox(b, f, u, u + 0.3, 0.0, 0.8, -1.2, -0.9, "M_Metal_Painted")
    roof_prism(b, -W / 2, W / 2, 0.0, D, eave, ridge, "M_Metal_Rusty")
    prism_wall = "M_Metal_Rusty"
    if lod == 0:
        for k in range(6):
            x = -W / 2 + 3.0 + k * 3.5
            b.box((x - 0.6, D * 0.5 - 0.6, ridge - 0.4), (x + 0.6, D * 0.5 + 0.6, ridge + 0.9), "M_Metal_Painted")
        b.anchor("anchor_roof_01", (0.0, 0.0, ridge + 1.0), (0, -1, 0))
    return b


def build_parking(sp, var, lod, rng):
    b = Builder()
    W, D = sp["W"], sp["D"]
    zs = [0.0, 3.4, 6.8, 10.2, 13.6, 17.0]
    H = zs[-1]
    detail = lod == 0
    for name, f in {
        "front": Face((-W / 2, 0, 0), (1, 0, 0), (0, -1, 0), W, H),
        "back": Face((W / 2, D, 0), (-1, 0, 0), (0, 1, 0), W, H),
        "left": Face((-W / 2, D, 0), (0, -1, 0), (-1, 0, 0), D, H),
        "right": Face((W / 2, 0, 0), (0, 1, 0), (1, 0, 0), D, H),
    }.items():
        ops = []
        if name in ("front", "back"):
            for i in range(5):
                for k in range(4):
                    ops.append(dict(kind="open", u0=k * 7.5 + 0.25, u1=(k + 1) * 7.5 - 0.25,
                                    v0=zs[i] + 1.25, v1=zs[i + 1] - 0.02, r=0.0, wall=var["wall"]))
        wall_decomp(b, f, ops, var["wall"], var["wall"], 0.0)
        emit_ops(b, f, ops, False)
    for z in zs:
        b.box((-W / 2 - 0.4, -0.4, z), (W / 2 + 0.4, D + 0.4, z + 0.35), var["deck"])
    for i in range(1, 5):
        z = zs[i]
        for xi in range(3):
            x = -W / 2 + 4.0 + xi * 11.0
            for y in (3.0, 14.0, 26.0, 37.0):
                b.poly([(x - 1.5, y, z - 0.02), (x + 1.5, y, z - 0.02), (x + 1.5, y + 0.3, z - 0.02),
                        (x - 1.5, y + 0.3, z - 0.02)], (0, 0, -1), "M_CeilingStrip")
    for xi in range(5):
        x = -W / 2 + xi * 7.5
        for yi in range(4):
            y = 1.5 + yi * 12.5
            b.box((x - 0.25, y - 0.25, 0.0), (x + 0.25, y + 0.25, H), var["base"])
    for i in range(5):
        z0 = zs[i] + 0.35
        z1 = zs[i + 1]
        b.poly([(W / 2, 2.0, z0), (W / 2 + 6.0, 2.0, z1), (W / 2 + 6.0, 8.0, z1), (W / 2, 8.0, z0)],
               (-(z1 - z0), 0, 6.0), var["ramp"])
        if detail:
            for y in (0.0, 14.0, 26.0):
                for u in range(4):
                    x = -W / 2 + 0.75 + u * 2.0
                    b.box((x, y + 0.2, z0), (x + 0.1, y + 0.3, z0 + 0.05), "M_Metal_Painted")
    if detail:
        for i in range(5):
            for y in range(2, int(D) - 1, 4):
                b.box((-W / 2 + 1.0, y, zs[i] + 0.35), (W / 2 - 1.0, y + 0.12, zs[i] + 0.37), "M_Frame")
            for face_y in (0.0, D):
                for k in range(int(W / 2.5) + 1):
                    u = min(W - 0.1, k * 2.5)
                    b.box((-W / 2 + u, face_y - 0.1, zs[i] + 0.35), (-W / 2 + u + 0.1, face_y + 0.1, zs[i] + 1.25),
                          "M_Metal_Painted")
    # switchback ramps on the street side: rise from 8 m out to each deck edge, with a support column
    xa, xb = -W / 2 + 1.0, -W / 2 + 5.0
    for i in range(5):
        z0, z1 = zs[i] + 0.35, zs[i + 1] + 0.35
        b.poly([(xa, -8.0, z0), (xb, -8.0, z0), (xb, 0.0, z1), (xa, 0.0, z1)], (0, -(z1 - z0), 8.0), var["ramp"])
        b.box((xa + 0.3, -8.4, 0.0), (xb - 0.3, -7.6, z0), var["base"])
        b.poly([(xa, -8.0, z0), (xa, 0.0, z1), (xa, 0.0, z1 + 0.1), (xa, -8.0, z0 + 0.1)], (-1, 0, 0), "M_Metal_Painted")
        b.poly([(xb, -8.0, z0), (xb, 0.0, z1), (xb, 0.0, z1 + 0.1), (xb, -8.0, z0 + 0.1)], (1, 0, 0), "M_Metal_Painted")
    b.poly([(-W / 2, 0, H), (W / 2, 0, H), (W / 2, D, H), (-W / 2, D, H)], (0, 0, 1), var["deck"])
    if lod == 0:
        b.anchor("anchor_sign_01", (0.0, -0.5, 14.5), (0, -1, 0))
    return b


def build_lod2(sp, var, rng, impostor_name):
    """Closed box-like hull per building; faces mapped to the impostor atlas quadrants."""
    b = Builder()
    mat = "M_ImpostorAtlas"
    W, D, S = sp["W"], sp["D"], sp["storeys"]
    if sp["kind"] == "tower":
        Hp = 4.5 + 3 * 3.6
        Wt, Dt = W - 4.0, D - 4.0
        Hm = Hp + (S - 7) * 3.8
        Hc = Hm + 3 * 3.8
        boxes = [(-W / 2, W / 2, 0.0, D, 0.0, Hp), (-Wt / 2, Wt / 2, 2.5, 2.5 + Dt, Hp, Hm),
                 (-(Wt - 4) / 2, (Wt - 4) / 2, 4.5, 4.5 + Dt - 4, Hm, Hc)]
    elif sp["kind"] == "market":
        boxes = [(-W / 2, W / 2, 0.0, D, 0.0, 3.2 + (S - 1) * 3.0)]
    elif sp["kind"] == "warehouse":
        boxes = [(-W / 2, W / 2, 0.0, D, 0.0, 9.0)]
    elif sp["kind"] == "parking":
        boxes = [(-W / 2, W / 2, 0.0, D, 0.0, 17.0)]
    else:
        boxes = [(-W / 2, W / 2, 0.0, D, 0.0, 4.2 + (S - 1) * 3.3)]
    quad = {"front": (0.0, 0.5, 0.5, 1.0), "back": (0.5, 1.0, 0.5, 1.0),
            "left": (0.0, 0.5, 0.0, 0.5), "right": (0.5, 1.0, 0.0, 0.5)}

    def qu(name, pts):
        u0, u1, v0, v1 = quad[name]
        e = 0.004
        uv = [(u0 + e, v0 + e), (u1 - e, v0 + e), (u1 - e, v1 - e), (u0 + e, v1 - e)]
        return uv

    for (x0, x1, y0, y1, z0, z1) in boxes:
        f_front = [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)]
        f_back = [(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)]
        f_left = [(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)]
        f_right = [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)]
        b.poly(f_front, (0, -1, 0), mat, qu("front", f_front))
        b.poly(f_back, (0, 1, 0), mat, qu("back", f_back))
        b.poly(f_left, (-1, 0, 0), mat, qu("left", f_left))
        b.poly(f_right, (1, 0, 0), mat, qu("right", f_right))
        roof = [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        b.poly(roof, (0, 0, 1), mat, [(0.006, 0.006), (0.02, 0.006), (0.02, 0.02), (0.006, 0.02)])
    if sp["kind"] == "warehouse":
        b2 = Builder()
        roof_prism(b2, -W / 2, W / 2, 0.0, D, 9.0, 12.5, mat, uvpatch=True)
        for k, v in b2.parts.items():
            b.parts.setdefault(k, []).extend(v)
    return b


# ----------------------------------------------------------------------------- specs
SPECS = [
    dict(id="bld_neon_01", district="neon", tags=["neon_strip", "street_wall", "shops"], kind="strip",
         storeys=8, W=14.0, D=16.0, gh=4.2, uh=3.3, bays=4, shops=3, blades=2, roofbb=False,
         var=dict(a=dict(wall="M_Plaster_Beige", base="M_Concrete_Stained", awn="M_Awning_Red", trim="M_Concrete_Smooth"),
                  b=dict(wall="M_Brick_Dark", base="M_Concrete_Smooth", awn="M_Awning_Teal", trim="M_Plaster_Clay"))),
    dict(id="bld_neon_02", district="neon", tags=["neon_strip", "street_wall", "shops"], kind="strip",
         storeys=13, W=12.0, D=15.0, gh=4.2, uh=3.3, bays=3, shops=2, blades=2, roofbb=False,
         var=dict(a=dict(wall="M_Brick_Painted", base="M_Concrete_Smooth", awn="M_Awning_Teal", trim="M_Concrete_Smooth"),
                  b=dict(wall="M_Plaster_Clay", base="M_Brick_Dark", awn="M_Awning_Red", trim="M_Brick_Dark"))),
    dict(id="bld_neon_03", district="neon", tags=["neon_strip", "street_wall", "shops", "roof_billboard"], kind="strip",
         storeys=19, W=16.0, D=18.0, gh=4.2, uh=3.3, bays=4, shops=3, blades=3, roofbb=True,
         var=dict(a=dict(wall="M_Concrete_Panels", base="M_Concrete_Stained", awn="M_Awning_Red", trim="M_Concrete_Smooth"),
                  b=dict(wall="M_Brick_Dark", base="M_Concrete_Stained", awn="M_Awning_Teal", trim="M_Concrete_Panels"))),
    dict(id="bld_downtown_01", district="downtown", tags=["downtown", "curtain_wall", "podium", "crown"], kind="tower",
         storeys=26, W=26.0, D=26.0, shops=4,
         var=dict(a=dict(wall="M_Concrete_Panels", base="M_Concrete_Stained", trim="M_Brick_Dark", awn="M_Awning_Teal"),
                  b=dict(wall="M_Concrete_Smooth", base="M_Concrete_Stained", trim="M_Concrete_Stained", awn="M_Awning_Red"))),
    dict(id="bld_downtown_02", district="downtown", tags=["downtown", "curtain_wall", "podium", "crown"], kind="tower",
         storeys=36, W=30.0, D=28.0, shops=4,
         var=dict(a=dict(wall="M_Concrete_Panels", base="M_Concrete_Stained", trim="M_Brick_Dark", awn="M_Awning_Teal"),
                  b=dict(wall="M_Concrete_Smooth", base="M_Concrete_Stained", trim="M_Concrete_Smooth", awn="M_Awning_Red"))),
    dict(id="bld_downtown_03", district="downtown", tags=["downtown", "curtain_wall", "podium", "crown"], kind="tower",
         storeys=44, W=22.0, D=22.0, shops=3,
         var=dict(a=dict(wall="M_Concrete_Stained", base="M_Concrete_Stained", trim="M_Concrete_Smooth", awn="M_Awning_Red"),
                  b=dict(wall="M_Concrete_Panels", base="M_Brick_Dark", trim="M_Concrete_Smooth", awn="M_Awning_Teal"))),
    dict(id="bld_market_01", district="market", tags=["old_market", "shophouse", "awnings"], kind="market",
         storeys=3, W=8.0, D=11.0,
         var=dict(a=dict(wall="M_Brick_Red", base="M_Brick_Red", trim="M_Plaster_Beige", awn="M_Awning_Red"),
                  b=dict(wall="M_Plaster_Clay", base="M_Brick_Dark", trim="M_Brick_Painted", awn="M_Awning_Teal"))),
    dict(id="bld_market_02", district="market", tags=["old_market", "shophouse", "awnings"], kind="market",
         storeys=4, W=9.0, D=12.0,
         var=dict(a=dict(wall="M_Plaster_Clay", base="M_Brick_Red", trim="M_Brick_Painted", awn="M_Awning_Red"),
                  b=dict(wall="M_Brick_Red", base="M_Plaster_Clay", trim="M_Plaster_Beige", awn="M_Awning_Teal"))),
    dict(id="bld_waterfront_01", district="waterfront", tags=["waterfront", "warehouse"], kind="warehouse",
         storeys=1, W=24.0, D=40.0,
         var=dict(a=dict(wall="M_Metal_Rusty", base="M_Metal_Rusty", trim="M_Metal_Painted", awn="M_Awning_Red"),
                  b=dict(wall="M_Metal_Corrugated", base="M_Metal_Corrugated", trim="M_Metal_Painted", awn="M_Awning_Teal"))),
    dict(id="bld_parking_01", district="parking", tags=["parking", "open_decks", "ramp"], kind="parking",
         storeys=5, W=30.0, D=40.0,
         var=dict(a=dict(wall="M_Concrete_Smooth", base="M_Concrete_Smooth", deck="M_Concrete_Smooth", ramp="M_Concrete_Stained", trim="M_Concrete_Smooth", awn="M_Awning_Red"),
                  b=dict(wall="M_Concrete_Stained", base="M_Concrete_Stained", deck="M_Concrete_Smooth", ramp="M_Concrete_Panels", trim="M_Concrete_Stained", awn="M_Awning_Teal"))),
]


# variant b has its own massing (variant a keeps the SPECS dimensions)
ALT_B = {
    "bld_neon_01": dict(storeys=10, W=12.5, D=14.0, bays=3, shops=2),
    "bld_neon_02": dict(storeys=16, W=14.0, D=13.0, bays=4, shops=3),
    "bld_neon_03": dict(storeys=15, W=18.0, D=16.0, bays=5, shops=4),
    "bld_downtown_01": dict(storeys=30, W=24.0, D=30.0, shops=3),
    "bld_downtown_02": dict(storeys=42, W=26.0, D=24.0, shops=4),
    "bld_downtown_03": dict(storeys=32, W=24.0, D=26.0, shops=4),
    "bld_market_01": dict(storeys=2, W=9.0, D=10.0),
    "bld_market_02": dict(storeys=5, W=7.0, D=14.0),
    "bld_waterfront_01": dict(W=30.0, D=34.0),
    "bld_parking_01": dict(W=36.0, D=40.0),
}


def build_any(sp, var, lod, rng):
    k = sp["kind"]
    if k == "strip":
        return build_strip(sp, var, lod, rng)
    if k == "tower":
        return build_tower(sp, var, lod, rng)
    if k == "market":
        return build_market(sp, var, lod, rng)
    if k == "warehouse":
        return build_warehouse(sp, var, lod, rng)
    return build_parking(sp, var, lod, rng)


def lod_name_list():
    return ["LOD0", "LOD1", "LOD2"]


# ----------------------------------------------------------------------------- scene assembly
def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def mesh_object(name, b, parent):
    me = bpy.data.meshes.new(name + "_mesh")
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    slots = {}
    for mat in sorted(b.parts.keys()):
        slots[mat] = len(slots)
        me.materials.append(ensure_mat(mat))
    for mat, polys in b.parts.items():
        idx = slots[mat]
        for pts, uvs in polys:
            verts = [bm.verts.new((p.x, p.y, p.z)) for p in pts]
            try:
                f = bm.faces.new(verts)
            except ValueError:
                continue
            f.material_index = idx
            for loop, uv in zip(f.loops, uvs):
                loop[uv_layer].uv = uv
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.parent = parent
    bpy.context.scene.collection.objects.link(obj)
    return obj


def bounds(b):
    xs, ys, zs = [], [], []
    for polys in b.parts.values():
        for pts, _ in polys:
            for p in pts:
                xs.append(p.x)
                ys.append(p.y)
                zs.append(p.z)
    return (min(xs), max(xs)), (min(ys), max(ys)), (min(zs), max(zs))


def to_godot(v):
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


def export_glb(path, root, children):
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for c in children:
        c.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_tangents=True, export_image_format="NONE", export_materials="EXPORT",
                              export_yup=True, export_cameras=False, export_lights=False)


def build_all():
    os.makedirs(OUT, exist_ok=True)
    rng_master = random.Random(SEED)
    cat = {"coords": "godot_y_up", "generator": "build_buildings.py", "seed": SEED, "buildings": []}
    rep = {"coords": "godot_y_up", "checks": [], "buildings": {}, "tex": {}}

    # textures first
    wa, we = window_atlas(random.Random(SEED + 1))
    write_png(os.path.join(OUT, "window_atlas_basecolor.png"), wa)
    write_png(os.path.join(OUT, "window_atlas_emissive.png"), we)
    sb, se = shop_interior(random.Random(SEED + 2))
    write_png(os.path.join(OUT, "shop_interior_basecolor.png"), sb)
    write_png(os.path.join(OUT, "shop_interior_emissive.png"), se)
    rep["tex"]["window_atlas"] = "2048x2048, 8x8 tiles, 0-15 dark, 16-23 warm blinds, 24-31 warm furniture, 32-39 cool office, 40-47 TV blue, 48-55 curtains, 56-63 warm dim"

    idx = 0
    for sp in SPECS:
        for vk in ("a", "b"):
            idx += 1
            name = "%s_%s" % (sp["id"], vk)
            var = sp["var"][vk]
            spv = dict(sp, **(ALT_B.get(sp["id"], {}) if vk == "b" else {}))
            rng = random.Random(SEED + idx * 97)
            clear_scene()
            root = bpy.data.objects.new(name, None)
            root.empty_display_size = 1.0
            bpy.context.scene.collection.objects.link(root)
            lods = {}
            for lod in (0, 1):
                lb = build_any(spv, var, lod, random.Random(SEED + idx * 97 + lod))
                lods[lod] = lb
            ib, ie = impostor_atlas(random.Random(SEED + idx * 131), spv, var)
            write_png(os.path.join(OUT, "impostor_%s_basecolor.png" % name), ib)
            write_png(os.path.join(OUT, "impostor_%s_emissive.png" % name), ie)
            lods[2] = build_lod2(spv, var, rng, name)
            objs = []
            tri_counts = {}
            for lod in (0, 1, 2):
                o = mesh_object("LOD%d" % lod, lods[lod], root)
                objs.append(o)
                tri_counts["LOD%d" % lod] = lods[lod].total_tris()
            (x0, x1), (y0, y1), (z0, z1) = bounds(lods[0])
            W_bb, D_bb, H_bb = x1 - x0, y1 - y0, z1 - z0
            col_mn, col_mx = (x0, y0, z0), (x1, y1, z1)
            col = mesh_object(name + "-colonly", _box_builder(col_mn, col_mx), root)
            objs.append(col)
            anchors = []
            for an, p, n in lods[0].anchors:
                e = bpy.data.objects.new(an, None)
                e.empty_display_size = 0.4
                e.location = p
                e.parent = root
                bpy.context.scene.collection.objects.link(e)
                objs.append(e)
                anchors.append(dict(name=an, position=to_godot(p), normal=to_godot(n)))
            glb = os.path.join(OUT, name + ".glb")
            export_glb(glb, root, objs)
            mats_used = sorted(set(list(lods[0].parts.keys()) + list(lods[1].parts.keys()) + list(lods[2].parts.keys())))
            ratio = tri_counts["LOD1"] / max(1, tri_counts["LOD0"])
            cat["buildings"].append(dict(
                id=name, type=sp["id"], variant=vk, file="out/%s.glb" % name, district=sp["district"],
                tags=sp.get("tags", []), storeys=spv["storeys"], width=round(W_bb, 3), depth=round(D_bb, 3),
                height=round(H_bb, 3), tris=tri_counts, materials=mats_used,
                impostor_textures=["out/impostor_%s_basecolor.png" % name, "out/impostor_%s_emissive.png" % name],
                anchors=anchors,
                collider=dict(name=name + "-colonly", type="box", size=[round(W_bb, 3), round(H_bb, 3), round(D_bb, 3)],
                              center=to_godot(Vector((0.5 * (x0 + x1), 0.5 * (y0 + y1), 0.5 * (z0 + z1)))))))
            lo = tri_counts["LOD0"]
            cap = 18000 if spv["kind"] == "tower" else 12000
            rep["buildings"][name] = dict(
                lod0=lo, lod1=tri_counts["LOD1"], lod2=tri_counts["LOD2"],
                lod0_in_budget=(3000 <= lo <= cap), lod1_ratio=round(ratio, 3), lod1_ok=ratio <= 0.30,
                lit_fraction=round(lods[0].win_lit / max(1, lods[0].win_total), 3),
                windows=lods[0].win_total, min_reveal_m=round(lods[0].reveal_min, 3) if lods[0].reveal_min < 9 else None,
                anchors=len(anchors))
            print("BUILT", name, tri_counts, "ratio", round(ratio, 3))

    write_materials()
    cat["materials_file"] = "out/materials.json"
    with open(os.path.join(OUT, "catalog.json"), "w") as fh:
        json.dump(cat, fh, indent=1)
    rep["summary"] = dict(
        types=len(SPECS), variants=2, glbs=len(cat["buildings"]),
        all_lod0_in_budget=all(v["lod0_in_budget"] for v in rep["buildings"].values()),
        all_lod1_ok=all(v["lod1_ok"] for v in rep["buildings"].values()))
    with open(os.path.join(OUT, "report.json"), "w") as fh:
        json.dump(rep, fh, indent=1)
    print("SUMMARY", json.dumps(rep["summary"]))


def _box_builder(mn, mx):
    b = Builder()
    b.box(mn, mx, "M_CollisionOnly")
    return b


def write_materials():
    mats = {}
    for name in sorted(list(CC0_SLOTS.keys()) + list(FLAT_SLOTS.keys())):
        info = mat_info(name)
        rec = dict(base_color=info["base"], roughness=info["rough"], metallic=info["metal"],
                   emission_color=info["emit"], emission_strength=info["estr"], uv=info["uv"], tint_for_impostor=info["tint"])
        if info.get("alpha", 1.0) < 1.0:
            rec["alpha"] = info["alpha"]
            rec["alpha_mode"] = "BLEND"
        if "cc0" in info:
            rec["source"] = "cc0 set %s (game/assets/textures/cc0/%s)" % (info["cc0"], info["cc0"])
            rec["textures"] = dict(basecolor="%s/%s/basecolor.jpg" % (CC0, info["cc0"]),
                                   normal="%s/%s/normal.jpg" % (CC0, info["cc0"]),
                                   roughness="%s/%s/roughness.jpg" % (CC0, info["cc0"]))
            rec["uv_tile_m"] = info["uv_tile_m"]
        elif "gen" in info:
            rec["generated"] = ["out/" + g for g in info["gen"]]
        rec["licence"] = "CC0-1.0" if "cc0" in info else "project-owned"
        mats[name] = rec
    mats["M_CollisionOnly"] = dict(base_color="#FFFFFF", note="collider only, never rendered")
    doc = {"coords": "godot_y_up", "generator": "build_buildings.py", "materials": mats,
           "notes": "M_ImpostorAtlas: one 512 px atlas per building, see catalog.json impostor_textures. "
                    "M_WindowAtlas and M_ShopInterior are shared; per-window tile chosen in the UVs."}
    with open(os.path.join(OUT, "materials.json"), "w") as fh:
        json.dump(doc, fh, indent=1)


if __name__ == "__main__" or True:
    if MODE == "build":
        build_all()
    elif MODE == "render":
        sys.path.insert(0, KIT)
        import render_buildings
        render_buildings.run(ARGV[1:], sys.modules[__name__])
