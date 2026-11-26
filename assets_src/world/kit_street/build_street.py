"""CITY 01 street-detail kit generator (Blender 5.3, deterministic). Companion of kit_props.

Run:  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup --python build_street.py
Reuses the geometry helpers, material table and exporter of ../kit_props/build_props.py (same conventions:
metres, Z up, props face -Y, wall props: origin on the wall face and the body stands off toward -Y).
Writes out/prop_<id>.glb (+ _lod1 where a prop is above 800 tris), out/catalog.json (same format as the kit_props
catalog), out/materials.json (only the materials this kit adds), out/report.json.
"""
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "kit_props"))
import build_props as bp  # noqa: E402
from build_props import Geo, box, cyl, part, put, sphere, tube  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)
bp.OUT = OUT          # build_prop / bmat resolve their output folder through the module global
bp.TEXD = os.path.join(OUT, "textures")
bp.LOD1_MIN_TRIS = 450   # most street props are cheap: give every multi-part one a LOD1 anyway

NEW_MATS = ("M_Trash_Bag", "M_Steam", "M_Puddle", "M_Bulb_Green", "M_Glow_Pool", "M_Rubber", "M_Paint_Stripe", "M_Window_Warm", "M_Warn_Amber")


def define_new_materials():
    bp.mdef("M_Trash_Bag", (0.025, 0.027, 0.032), 0.28, 0.0)
    bp.mdef("M_Steam", (0.78, 0.84, 0.92), 1.0, 0.0)          # the builder swaps this for the soft alpha card
    bp.mdef("M_Puddle", (0.012, 0.016, 0.022), 0.04, 0.0)     # near-black mirror blob
    bp.mdef("M_Bulb_Green", (0.1, 1.0, 0.45), 0.4, 0.0, (0.1, 1.0, 0.45), 12.0)
    bp.mdef("M_Glow_Pool", (1.0, 0.62, 0.3), 1.0, 0.0, (1.0, 0.62, 0.3), 1.0)   # the builder swaps this for the additive pool
    bp.mdef("M_Rubber", (0.02, 0.02, 0.022), 0.9, 0.0)
    bp.mdef("M_Paint_Stripe", (0.93, 0.93, 0.9), 0.5, 0.0)
    bp.mdef("M_Window_Warm", (0.9, 0.55, 0.25), 0.6, 0.0, (1.0, 0.62, 0.3), 2.2)    # lit shop window: standard emission, no HDR blow-out
    bp.mdef("M_Warn_Amber", (0.9, 0.45, 0.05), 0.5, 0.0, (1.0, 0.5, 0.08), 3.0)
    bp.mdef("M_Manhole", (0.09, 0.09, 0.1), 0.4, 0.6)     # not in NEW_MATS: the engine library already has M_Manhole and M_Ground
    bp.mdef("M_Ground", (0.16, 0.16, 0.17), 0.8, 0.0)


def scaled(g, sx, sy, sz):
    return Geo().merge(g, Matrix.Diagonal(Vector((sx, sy, sz, 1.0))))


def quad(p, mat):
    return Geo().add(p, [(0, 1, 2, 3)], mat, False)


def disc(r, n, c, mat, facing=-1):
    """Flat n-gon in the XZ plane at centre c facing -Y (facing -1) or +Y (+1)."""
    cx, cy, cz = c
    V = [(cx, cy, cz)] + [(cx + r * math.cos(2 * math.pi * i / n), cy, cz + r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    F = []
    for i in range(n):
        a, b = 1 + i, 1 + (i + 1) % n
        F.append((0, a, b) if facing < 0 else (0, b, a))
    return Geo().add(V, F, mat, False)


def flat_blob(rx, ry, n, z, mat, seed=0, wob=0.25):
    """Irregular outline on the ground plane (normal +Z), triangle fan."""
    r = random.Random(seed)
    ph = [r.uniform(0, 6.28) for _ in range(3)]
    V = [(0, 0, z)]
    for i in range(n):
        a = 2 * math.pi * i / n
        k = 1.0 + wob * (math.sin(2 * a + ph[0]) * 0.6 + math.sin(3 * a + ph[1]) * 0.4)
        V.append((rx * k * math.cos(a), ry * k * math.sin(a), z))
    F = [(0, 1 + (i + 1) % n, 1 + i) if False else (0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
    return Geo().add(V, F, mat, False)


def spec(cat, mount, parts, notes, budget=(20, 3000), emissive=False):
    return dict(category=cat, mount=mount, budget=budget, emissive=emissive, parts=parts, lights=[], notes=notes)


# ----------------------------------------------------------------------------- props

def p_dumpster():
    g = box((1.9, 1.05, 0.9), (0, 0, 0.62), "M_Metal_Green")
    g.merge(box((1.96, 1.1, 0.08), (0, 0, 1.12), "M_Metal_Green"))
    for x in (-0.6, 0.0, 0.6):
        g.merge(box((0.06, 0.05, 0.85), (x, -0.55, 0.62), "M_Metal_Dark"))
    g.merge(box((1.95, 0.55, 0.05), (0, 0.25, 1.2), "M_Metal_Dark"))
    put(g, box((1.95, 0.5, 0.05), (0, 0, 0), "M_Metal_Dark"), c=(0, -0.28, 1.18), rx=-8)
    for x in (-0.85, 0.85):
        for y in (-0.38, 0.38):
            put(g, cyl(0.09, 0.07, "M_Rubber", sides=10, rings=1), c=(x, y, 0.1), ry=90)
    g.merge(box((1.9, 1.0, 0.1), (0, 0, 0.17), "M_Metal_Dark"))
    return spec("furniture", "ground", [part("dumpster", g)], "Skip dumpster 1.9 x 1.05 m, one lid propped open", (80, 900))


def p_trash_bags():
    g = Geo()
    for i, (x, y, z, r, sx, sy, sz) in enumerate(((0, 0, 0.3, 0.32, 1.0, 1.0, 0.85), (0.45, 0.1, 0.24, 0.27, 1.0, 1.1, 0.8),
                                                   (-0.38, 0.12, 0.22, 0.25, 1.1, 1.0, 0.85), (0.15, -0.3, 0.2, 0.24, 1.0, 1.0, 0.8),
                                                   (0.08, 0.1, 0.62, 0.22, 1.0, 1.0, 0.9))):
        put(g, scaled(sphere(r, "M_Trash_Bag", seg=8, rings=5), sx, sy, sz), c=(x, y, z), rz=i * 37)
        put(g, cyl(0.035, 0.1, "M_Trash_Bag", sides=5, rings=1, r2=0.0), c=(x, y, z + r * sz * 0.85))
    g.merge(box((0.5, 0.35, 0.05), (-0.1, 0.5, 0.03), "M_Rubber"))
    return spec("furniture", "ground", [part("trash_bags", g)], "Heap of black bin bags", (80, 900))


def _ac_body(mat_body="M_Metal_Grey"):
    g = box((0.85, 0.3, 0.6), (0, -0.22, 0.34), mat_body)
    g.merge(box((0.87, 0.04, 0.62), (0, -0.39, 0.34), "M_Metal_Dark"))
    put(g, cyl(0.22, 0.02, "M_Metal_Dark", sides=14, rings=1), c=(-0.12, -0.4, 0.34), rx=90)
    for k in range(5):
        g.merge(box((0.18, 0.012, 0.02), (0.28, -0.405, 0.22 + k * 0.07), "M_Metal_Dark"))
    g.merge(box((0.05, 0.3, 0.05), (-0.38, -0.2, 0.0), "M_Metal_Dark"))
    g.merge(box((0.05, 0.3, 0.05), (0.38, -0.2, 0.0), "M_Metal_Dark"))
    g.merge(box((0.03, 0.03, 0.2), (0.33, -0.18, -0.1), "M_Metal_Grey"))
    return g


def p_ac_unit_wall():
    return spec("furniture", "wall", [part("ac_unit", _ac_body())], "Split AC condenser on two brackets, wall face origin", (80, 900))


def p_ac_cluster_wall():
    g = Geo()
    put(g, _ac_body("M_Metal_Grey"), c=(-0.95, 0, 0.0))
    put(g, _ac_body("M_Metal_Grey"), c=(0.0, 0, 0.0))
    put(g, _ac_body("M_Concrete"), c=(0.95, 0, 0.62))
    g.merge(box((2.8, 0.06, 0.05), (0, -0.05, -0.04), "M_Metal_Dark"))
    g.merge(box((0.05, 0.06, 1.3), (-1.4, -0.05, 0.6), "M_Metal_Dark"))
    return spec("furniture", "wall", [part("ac_cluster", g)], "Three condensers on an angle-iron rack, wall face origin", (200, 2200))


def p_fire_escape():
    g = Geo()
    W, D = 3.0, 1.3
    floors = (3.4, 6.6, 9.8)
    for z in floors:
        g.merge(box((W, D, 0.05), (0, -D / 2, z), "M_Metal_Dark"))
        g.merge(tube([(-W / 2, 0.0, z + 1.0), (-W / 2, -D, z + 1.0), (W / 2, -D, z + 1.0), (W / 2, 0.0, z + 1.0)], 0.022, "M_Metal_Dark", sides=4))
        for k in range(9):
            g.merge(box((0.02, 0.02, 1.0), (-W / 2 + W * k / 8.0, -D, z + 0.5), "M_Metal_Dark"))
        for k in range(3):
            y = -D * (k + 1) / 4.0
            g.merge(box((0.02, 0.02, 1.0), (-W / 2, y, z + 0.5), "M_Metal_Dark"))
            g.merge(box((0.02, 0.02, 1.0), (W / 2, y, z + 0.5), "M_Metal_Dark"))
        for x in (-W / 2 + 0.1, W / 2 - 0.1):
            g.merge(box((0.05, 0.05, 0.5), (x, -D + 0.05, z - 0.3), "M_Metal_Dark"))
    for i, z in enumerate(floors[:-1]):
        xs, xe = (-W / 2 + 0.5, W / 2 - 0.5) if i % 2 == 0 else (W / 2 - 0.5, -W / 2 + 0.5)
        n = 8
        for k in range(n):
            t = (k + 0.5) / n
            g.merge(box((0.22, 0.6, 0.03), (xs + (xe - xs) * t, -0.5, z + 0.05 + (floors[i + 1] - z - 0.1) * t), "M_Metal_Dark"))
        for yy in (-0.2, -0.8):
            g.merge(bp.strut((xs, yy, z + 0.05), (xe, yy, floors[i + 1] - 0.05), 0.04, "M_Metal_Dark"))
    # drop ladder from the first landing
    for x in (-0.2, 0.2):
        g.merge(box((0.03, 0.03, 3.3), (W / 2 - 0.5 + x * 0.0 + (x * 1.0), -0.3, 1.7), "M_Metal_Dark"))
    for k in range(8):
        g.merge(box((0.46, 0.03, 0.03), (W / 2 - 0.5, -0.3, 0.35 + k * 0.4), "M_Metal_Dark"))
    return spec("furniture", "wall", [part("fire_escape", g)], "Three-landing iron fire escape 3 x 1.3 m, 10.8 m tall, wall face origin", (300, 3400))


def p_steam_vent():
    g = box((0.95, 0.95, 0.05), (0, 0, 0.0), "M_Metal_Dark")
    for k in range(7):
        g.merge(box((0.82, 0.05, 0.04), (0, -0.36 + k * 0.12, 0.03), "M_Metal_Grey"))
    pipe = put(Geo(), cyl(0.11, 0.75, "M_Metal_Grey", sides=10, rings=1), c=(0.52, 0.5, 0.0))
    put(pipe, cyl(0.15, 0.06, "M_Metal_Dark", sides=10, rings=1), c=(0.52, 0.5, 0.75))
    put(pipe, cyl(0.13, 0.05, "M_Metal_Dark", sides=10, rings=1), c=(0.52, 0.5, 0.0))
    ua = lambda co: ((co.x + 0.7) / 1.4, co.z / 3.4)
    ub = lambda co: ((co.y + 0.7) / 1.4, co.z / 3.4)
    ca = quad([(-0.7, 0, 0.15), (0.7, 0, 0.15), (0.7, 0, 3.4), (-0.7, 0, 3.4)], "M_Steam")
    cb = quad([(0, -0.7, 0.15), (0, 0.7, 0.15), (0, 0.7, 3.4), (0, -0.7, 3.4)], "M_Steam")
    return spec("furniture", "ground", [part("steam_grate", g), part("steam_pipe", pipe), part("steam_card_a", ca, 0.0, ua),
                                        part("steam_card_b", cb, 0.0, ub)],
                "Street steam vent: grate, stack and two crossed soft steam cards (the builder swaps in the alpha shader)", (40, 900))


def _head(dark, lens, off, x, z):
    """One 3-lens signal head centred at (x, 0, z): housing, back plates, visors; lens discs on both faces."""
    dark.merge(box((0.34, 0.3, 1.0), (x, 0, z), "M_Metal_Dark"))
    for face in (-1, 1):
        dark.merge(box((0.62, 0.04, 1.3), (x, 0.17 * face, z), "M_Metal_Dark"))
    for name, dz in (("red", 0.34), ("amber", 0.0), ("green", -0.34)):
        for face in (-1, 1):
            y = 0.2 * face
            dark.merge(box((0.3, 0.1, 0.03), (x, 0.2 * face, z + dz + 0.14), "M_Metal_Dark"))
            off.merge(disc(0.115, 14, (x, y + 0.001 * face, z + dz), "M_Signal_Off", facing=face))
            lens[name].merge(disc(0.105, 14, (x, y + 0.004 * face, z + dz), "M_Bulb_" + name.capitalize(), facing=face))


def p_street_signal():
    dark = put(Geo(), cyl(0.09, 6.2, "M_Metal_Dark", sides=12, rings=4, r2=0.065))
    put(dark, cyl(0.2, 0.35, "M_Concrete", sides=12, rings=1))
    dark.merge(tube([(0, 0, 5.55), (0.9, 0, 5.75), (2.2, 0, 5.8), (3.4, 0, 5.78)], 0.055, "M_Metal_Dark", sides=8))
    lens = {"red": Geo(), "amber": Geo(), "green": Geo()}
    off = Geo()
    _head(dark, lens, off, 3.05, 5.15)
    _head(dark, lens, off, 1.5, 5.15)
    dark.merge(box((0.3, 0.2, 0.4), (0.25, -0.1, 2.75), "M_Metal_Dark"))
    parts = [part("signal_pole", dark), part("signal_off", off)]
    for k in ("red", "amber", "green"):
        parts.append(part("signal_lens_%s" % k, lens[k]))
    s = spec("lamp", "ground", parts, "Signal mast with a 3.4 m arm along +X and two double-faced heads. Meshes signal_lens_red/amber/green are "
             "separate so the engine shows one at a time; signal_off holds the dark lens discs.", (300, 3200), True)
    return s


def p_scooter(body_mat="M_Container_Blue"):
    prof = [(0.62, 0.38), (0.45, 0.62), (0.05, 0.64), (-0.18, 0.56), (-0.4, 0.34), (-0.42, 0.22), (0.1, 0.2), (0.55, 0.25)]
    body = bp.prism_x(prof, -0.14, 0.14, body_mat)
    tyre = Geo()
    for y in (-0.62, 0.62):
        put(tyre, cyl(0.23, 0.11, "M_Rubber", sides=14, rings=1), c=(-0.055, y, 0.23), ry=90)
        put(tyre, cyl(0.12, 0.13, "M_Metal_Grey", sides=10, rings=1), c=(-0.065, y, 0.23), ry=90)
    g = box((0.36, 0.7, 0.07), (0, -0.05, 0.2), "M_Metal_Dark")
    g.merge(box((0.34, 0.5, 0.12), (0, 0.28, 0.72), "M_Metal_Dark"))
    put(g, cyl(0.025, 0.65, "M_Metal_Grey", sides=6, rings=1), c=(0, -0.62, 0.23), rx=-18)
    g.merge(tube([(-0.32, -0.48, 1.0), (0.0, -0.5, 1.02), (0.32, -0.48, 1.0)], 0.016, "M_Metal_Dark", sides=6))
    put(g, sphere(0.08, "M_Lamp_Cool", seg=8, rings=5), c=(0, -0.58, 0.86))
    g.merge(box((0.16, 0.12, 0.2), (0.0, -0.48, 0.86), "M_Metal_Dark"))
    for x in (-0.3, 0.3):
        g.merge(tube([(x * 0.9, -0.5, 1.0), (x * 1.1, -0.45, 1.2)], 0.008, "M_Metal_Grey", sides=4))
        g.merge(box((0.07, 0.05, 0.04), (x * 1.15, -0.45, 1.22), "M_Metal_Grey"))
    g.merge(box((0.22, 0.2, 0.05), (0, 0.78, 0.5), "M_Metal_Dark"))
    return spec("furniture", "ground", [part("scooter_body", body), part("scooter_wheels", tyre), part("scooter_frame", g)],
                "Parked scooter, kick-stand pose, faces -Y", (300, 2600), True)


def p_kiosk():
    body = box((2.5, 1.9, 2.3), (0, -0.95, 1.15), "M_Metal_Green")
    g = box((2.7, 2.1, 0.16), (0, -0.95, 2.38), "M_Metal_Dark")
    g.merge(box((2.7, 0.3, 0.2), (0, 0.03, 0.1), "M_Concrete"))
    g.merge(box((2.2, 0.35, 0.07), (0, -1.95, 1.05), "M_Wood_Dark"))
    for x in (-1.1, 1.1):
        g.merge(box((0.07, 0.07, 1.4), (x, -2.1, 0.7), "M_Metal_Dark"))
    for x in (-0.55, 0.0, 0.55):
        for z in (1.35, 1.65):
            g.merge(box((0.26, 0.05, 0.2), (x, -1.89, z), "M_Metal_Red" if (int(x * 10) + int(z * 10)) % 2 else "M_Awning_B"))
    shutter = box((0.06, 1.2, 1.2), (1.28, -0.95, 1.1), "M_Shutter")
    awn = Geo()
    for k in range(8):
        x0 = -1.45 + 2.9 * k / 8
        x1 = -1.45 + 2.9 * (k + 1) / 8
        awn.add([(x0, -2.35, 2.0), (x1, -2.35, 2.0), (x1, -1.85, 2.25), (x0, -1.85, 2.25)], [(0, 1, 2, 3)],
                "M_Awning_A" if k % 2 == 0 else "M_Awning_B", False)
    awn.merge(box((2.95, 0.04, 0.12), (0, -2.35, 1.96), "M_Awning_A"))
    glow = box((1.9, 0.04, 0.9), (0, -1.9, 1.55), "M_Window_Warm")
    sg = box((2.2, 0.12, 0.38), (0, -1.96, 2.62), "M_SignBox")
    parts = [part("kiosk_body", body), part("kiosk_trim", g), part("kiosk_shutter", shutter), part("kiosk_awning", awn),
             part("kiosk_window_glow", glow), part("kiosk_sign_box", sg)]
    try:
        txt = bp.neon_lines([("BUFE", "M_Neon_Amber")], 1.9, 0.26, 0.04, (-0.95, -2.03, 2.5), (1, 0, 0), (0, 0, 1), (0, -1, 0))
        parts.append(part("kiosk_sign_neon", txt))
    except Exception as e:  # text conversion is best effort
        print("[street] kiosk text skipped", e)
    return spec("furniture", "ground", parts, "Street kiosk (bufe): lit serving window, striped awning, amber sign. Front faces -Y", (300, 4200), True)


def p_newsstand():
    g = Geo()
    for x in (-0.85, 0.85):
        g.merge(box((0.05, 0.05, 1.9), (x, 0.1, 0.95), "M_Metal_Dark"))
        g.merge(box((0.05, 0.75, 0.05), (x, -0.25, 0.04), "M_Metal_Dark"))
        g.merge(box((0.05, 0.05, 1.1), (x, -0.55, 0.55), "M_Metal_Dark"))
    g.merge(box((1.9, 0.7, 0.05), (0, -0.2, 0.9), "M_Metal_Dark"))
    g.merge(box((1.9, 0.5, 0.05), (0, 0.0, 1.9), "M_Awning_A"))
    g.merge(box((1.9, 0.6, 0.04), (0, -0.25, 0.4), "M_Metal_Dark"))
    g.merge(box((1.8, 0.05, 0.9), (0, 0.11, 0.98), "M_Metal_Dark"))
    covers = Geo()
    mats = ("M_Poster_02", "M_Poster_04", "M_Poster_05", "M_Poster_06")
    for k, m in enumerate(mats):
        x = -0.65 + 0.43 * k
        covers.merge(quad([(x - 0.19, 0.08, 1.15), (x + 0.19, 0.08, 1.15), (x + 0.19, 0.08, 1.75), (x - 0.19, 0.08, 1.75)], m))
    uvn = lambda co: (((co.x + 0.84) % 0.43) / 0.38, (co.z - 1.15) / 0.6)
    return spec("furniture", "ground", [part("newsstand_frame", g), part("newsstand_covers", covers, 0.0, uvn)],
                "Newspaper rack with four back-lit magazine covers (existing poster textures)", (80, 1100), True)


def p_bus_stop_sign():
    g = put(Geo(), cyl(0.04, 3.1, "M_Metal_Grey", sides=8, rings=1))
    put(g, cyl(0.2, 0.2, "M_Concrete", sides=8, rings=1))
    pl = Geo()
    pl.merge(disc(0.28, 20, (0, -0.06, 3.05), "M_Chevron_Red", facing=-1))
    pl.merge(disc(0.19, 20, (0, -0.062, 3.05), "M_Paint_Stripe", facing=-1))
    pl.merge(box((0.2, 0.02, 0.1), (0, -0.065, 3.05), "M_Metal_Dark"))
    pl.merge(box((0.46, 0.04, 0.5), (0, -0.07, 2.55), "M_Paint_Stripe"))
    for k in range(5):
        pl.merge(box((0.36, 0.01, 0.025), (0, -0.095, 2.7 - 0.08 * k), "M_Metal_Dark"))
    return spec("furniture", "ground", [part("bus_sign_pole", g), part("bus_sign_plate", pl)], "Bus stop pole with a round sign and timetable plate", (40, 800))


def p_street_hydrant():
    g = put(Geo(), cyl(0.15, 0.08, "M_Metal_Dark", sides=12, rings=1))
    put(g, cyl(0.12, 0.62, "M_Hydrant_Red", sides=12, rings=2, r2=0.105), c=(0, 0, 0.08))
    put(g, cyl(0.12, 0.05, "M_Metal_Grey", sides=12, rings=1), c=(0, 0, 0.5))
    put(g, cyl(0.13, 0.08, "M_Hydrant_Red", sides=12, rings=1, r2=0.04), c=(0, 0, 0.7))
    put(g, cyl(0.04, 0.05, "M_Metal_Grey", sides=6, rings=1), c=(0, 0, 0.78))
    for x in (-0.15, 0.15):
        put(g, cyl(0.045, 0.1, "M_Metal_Grey", sides=8, rings=1), c=(x, 0, 0.38), ry=90 * (1 if x > 0 else -1))
    put(g, cyl(0.05, 0.1, "M_Metal_Grey", sides=8, rings=1), c=(0, -0.12, 0.34), rx=90)
    return spec("furniture", "ground", [part("street_hydrant", g)], "Pillar hydrant with two side outlets and a front pumper port", (80, 900))


def p_bollard_flex():
    g = put(Geo(), cyl(0.07, 0.95, "M_Paint_Stripe", sides=12, rings=3, r2=0.055))
    put(g, cyl(0.1, 0.03, "M_Metal_Dark", sides=12, rings=1))
    for z in (0.5, 0.72):
        put(g, cyl(0.074, 0.12, "M_Chevron_Red", sides=12, rings=1, r2=0.07), c=(0, 0, z))
    return spec("furniture", "ground", [part("bollard_flex", g)], "Flexible white post with red bands", (40, 700))


def p_bollard_stone():
    g = put(Geo(), cyl(0.16, 0.7, "M_Concrete", sides=12, rings=2, r2=0.14))
    put(g, sphere(0.15, "M_Concrete", seg=10, rings=5), c=(0, 0, 0.72))
    put(g, cyl(0.17, 0.06, "M_Metal_Dark", sides=12, rings=1), c=(0, 0, 0.45))
    return spec("furniture", "ground", [part("bollard_stone", g)], "Stone ball bollard", (40, 800))


def p_bollard_chain():
    g = Geo()
    for x in (-1.2, 1.2):
        put(g, cyl(0.045, 0.85, "M_Metal_Dark", sides=8, rings=1), c=(x, 0, 0))
        put(g, sphere(0.06, "M_Metal_Dark", seg=8, rings=4), c=(x, 0, 0.88))
    pts = [(-1.2 + 2.4 * k / 12, 0, 0.78 - 0.14 * (1 - ((-1.2 + 2.4 * k / 12) / 1.2) ** 2)) for k in range(13)]
    g.merge(tube(pts, 0.015, "M_Metal_Grey", sides=4))
    return spec("furniture", "ground", [part("bollard_chain", g)], "Two posts joined by a sagging chain, 2.4 m", (40, 800))


def p_manhole_decal():
    cover = flat_blob(0.46, 0.46, 18, 0.014, "M_Manhole", 1, 0.0)
    for k in range(3):
        cover.merge(box((0.5, 0.025, 0.004), (0, -0.12 + 0.12 * k, 0.016), "M_Metal_Dark"))
    ring = flat_blob(0.53, 0.53, 18, 0.011, "M_Metal_Dark", 2, 0.0)
    return spec("decal", "ground", [part("manhole_ring", ring), part("manhole_cover", cover)], "Manhole cover decal quads, 1.06 m ring", (20, 400))


def p_puddle(seed, rx, ry):
    return spec("decal", "ground", [part("puddle", flat_blob(rx, ry, 14, 0.012, "M_Puddle", seed, 0.3))],
                "Puddle decal, near-black mirror blob %.1f x %.1f m" % (rx * 2, ry * 2), (10, 200))


def p_glow_pool():
    g = flat_blob(3.2, 3.2, 16, 0.02, "M_Glow_Pool", 3, 0.0)
    return spec("decal", "ground", [part("glowpool", g)], "Warm light pool on the lane floor, radius 3.2 m (the builder swaps in the additive soft shader)", (10, 200), True)


def p_glow_wall():
    g = disc(2.6, 16, (0, -0.02, 0), "M_Glow_Pool", facing=-1)
    return spec("decal", "wall", [part("glowwall", g)], "Warm light wash on a lane wall, vertical disc radius 2.6 m facing -Y, origin at its centre (the builder swaps in the additive soft shader)", (10, 200), True)


def p_cables_hang():
    g = Geo()
    W = 14.0
    for x in (0.0, W):
        g.merge(box((0.12, 0.12, 0.12), (x, 0.0, 7.0), "M_Metal_Dark"))
        g.merge(box((0.04, 0.3, 0.04), (x, -0.15, 7.0), "M_Metal_Dark"))
    for dz, dy, sag in ((0.0, 0.0, 1.5), (-0.12, -0.15, 1.25), (0.1, 0.12, 1.7), (-0.25, 0.0, 1.0)):
        pts = [(W * i / 10.0, dy, 7.0 + dz - sag * 4 * (i / 10.0) * (1 - i / 10.0)) for i in range(11)]
        g.merge(tube(pts, 0.02, "M_Metal_Dark", sides=4))
    return spec("overhead", "span", [part("cables_hang", g)], "Four sagging cables across a lane, 14 m, origin at the left anchor 7 m up", (200, 1100))


def p_alley_gate():
    g = Geo()
    for x in (-1.9, 1.9):
        g.merge(box((0.14, 0.14, 2.7), (x, 0, 1.35), "M_Metal_Dark"))
    g.merge(box((3.9, 0.12, 0.12), (0, 0, 2.7), "M_Metal_Dark"))
    leaf = Geo()
    for k in range(13):
        leaf.merge(box((0.035, 0.035, 2.3), (-1.8 + 3.6 * k / 12.0, -0.05, 1.3), "M_Shutter"))
    for z in (0.3, 1.3, 2.3):
        leaf.merge(box((3.7, 0.04, 0.05), (0, -0.07, z), "M_Shutter"))
    leaf.merge(box((0.28, 0.07, 0.2), (1.5, -0.1, 1.05), "M_Metal_Dark"))
    return spec("furniture", "ground", [part("gate_frame", g), part("gate_bars", leaf)], "Steel alley gate 4 m wide, bars and padlock", (200, 2200))


def p_roadwork_barrier():
    legs = Geo()
    for x in (-0.85, 0.85):
        for y in (-0.22, 0.22):
            legs.merge(bp.strut((x, y, 0.0), (x, 0.0, 1.05), 0.045, "M_Metal_Dark"))
    boards = Geo()
    for k, z in enumerate((0.65, 0.95)):
        for j in range(8):
            x0 = -1.0 + 2.0 * j / 8.0
            boards.merge(box((0.25, 0.04, 0.2), (x0 + 0.125, 0.0, z), "M_Chevron_Red" if (j + k) % 2 == 0 else "M_Paint_Stripe"))
    lamp = put(Geo(), cyl(0.07, 0.09, "M_Warn_Amber", sides=10, rings=1), c=(-0.8, 0.0, 1.07))
    return spec("furniture", "ground", [part("barrier_legs", legs), part("barrier_boards", boards), part("barrier_lamp", lamp)],
                "A-frame roadwork barrier 2 m wide, red and white boards, amber lamp", (80, 1100), True)


def p_alley_floor():
    g = box((16.0, 40.0, 0.12), (0, 20.0, -0.06), "M_Ground")
    return spec("street_floor", "ground", [part("alley_floor", g)],
                "Lane floor 16 x 40 m, top at origin height, runs along +Y (into the block); the far end hides inside the end building", (8, 60))


def p_alley_lamp():
    g = box((0.18, 0.12, 0.4), (0, -0.06, 0.0), "M_Metal_Dark")
    g.merge(tube([(0, -0.1, 0.0), (0, -0.55, 0.12)], 0.03, "M_Metal_Dark", sides=6))
    put(g, cyl(0.17, 0.12, "M_Metal_Dark", sides=10, rings=1, r2=0.12), c=(0, -0.55, 0.1), rx=90)
    glow = put(Geo(), cyl(0.085, 0.03, "M_Lamp_Sodium", sides=10, rings=1), c=(0, -0.66, 0.08), rx=90)
    return spec("furniture", "wall", [part("alley_lamp", g), part("alley_lamp_bulb", glow)],
                "Caged wall lamp for a side lane. Origin on the wall at lamp height", (40, 700), True)


def p_crate_stack():
    g = box((0.6, 0.45, 0.4), (0, 0, 0.2), "M_Wood_Dark")
    g.merge(box((0.55, 0.42, 0.35), (0.62, 0.05, 0.175), "M_Wood_Dark"))
    put(g, box((0.55, 0.42, 0.35), (0, 0, 0), "M_Wood_Dark"), c=(0.2, -0.02, 0.58), rz=14)
    for x, y in ((0.0, 0.0), (0.62, 0.05)):
        g.merge(box((0.62, 0.02, 0.05), (x, -0.23, 0.2), "M_Metal_Dark"))
    return spec("furniture", "ground", [part("crate_stack", g)], "Three wooden crates", (40, 900))


# ----------------------------------------------------------------------------- build

def registry():
    reg = {}
    reg["street_dumpster"] = p_dumpster()
    reg["street_trash_bags"] = p_trash_bags()
    reg["street_ac_unit"] = p_ac_unit_wall()
    reg["street_ac_cluster"] = p_ac_cluster_wall()
    reg["street_fire_escape"] = p_fire_escape()
    reg["street_steam_vent"] = p_steam_vent()
    reg["street_signal"] = p_street_signal()
    reg["street_scooter_a"] = p_scooter()
    reg["street_scooter_b"] = p_scooter("M_Metal_Red")
    reg["street_kiosk"] = p_kiosk()
    reg["street_newsstand"] = p_newsstand()
    reg["street_bus_sign"] = p_bus_stop_sign()
    reg["street_hydrant"] = p_street_hydrant()
    reg["street_bollard_flex"] = p_bollard_flex()
    reg["street_bollard_stone"] = p_bollard_stone()
    reg["street_bollard_chain"] = p_bollard_chain()
    reg["street_manhole"] = p_manhole_decal()
    reg["street_puddle_a"] = p_puddle(11, 1.1, 0.7)
    reg["street_puddle_b"] = p_puddle(23, 0.8, 1.2)
    reg["street_puddle_c"] = p_puddle(37, 1.5, 0.9)
    reg["street_glow_pool"] = p_glow_pool()
    reg["street_glow_wall"] = p_glow_wall()
    reg["street_cables_hang"] = p_cables_hang()
    reg["street_alley_gate"] = p_alley_gate()
    reg["street_roadwork_barrier"] = p_roadwork_barrier()
    reg["street_alley_floor"] = p_alley_floor()
    reg["street_alley_lamp"] = p_alley_lamp()
    reg["street_crate_stack"] = p_crate_stack()
    return reg


def main():
    import shutil
    bp.define_materials()
    define_new_materials()
    shutil.copytree(os.path.join(HERE, "..", "kit_props", "out", "textures"), bp.TEXD, dirs_exist_ok=True)  # poster covers; removed again below
    records = []
    for pid, sp in registry().items():
        rec = bp.build_prop(pid, sp)
        records.append(rec)
        print("[street] %-26s tris=%5d lod1=%s size=%s mats=%s" % (pid, rec["tris"], rec["lod1_tris"], rec["size"], rec["materials"]))
    used = set()
    for r in records:
        used.update(r["materials"])
    mats_out = {}
    for name in sorted(used):
        if name not in NEW_MATS:
            continue
        s = bp.MATS[name]
        mats_out[name] = {"base_color": [round(c, 3) for c in s["base"]], "roughness": s["roughness"], "metallic": s["metallic"],
                          "emission_color": [round(c, 3) for c in s["emission"]] if s["emission"] else None,
                          "emission_strength": s["emission_strength"], "texture": None, "uv_tiling_m": 1.0, "source": "flat colour"}
    with open(os.path.join(OUT, "materials.json"), "w", encoding="utf-8") as f:
        json.dump({"textures_relative_to": "out/", "materials": mats_out}, f, indent=2)
    catalog = {"coords": "godot_y_up", "source": "assets_src/world/kit_street/build_street.py", "items": []}
    for r in records:
        catalog["items"].append({"id": r["id"], "category": r["category"], "file": r["file"], "size": r["size"],
                                 "tris": r["tris"], "lod1_tris": r["lod1_tris"], "lod1_file": r["lod1_file"],
                                 "collider_tris": r["collider_tris"], "materials": r["materials"], "lights": r["lights"],
                                 "emissive": r["emissive"], "mount": r["mount"], "notes": r["notes"]})
    with open(os.path.join(OUT, "catalog.json"), "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2)
    checks = []
    for r in records:
        b = r["budget"]
        if b is not None:
            checks.append({"id": r["id"], "check": "tri_budget", "tris": r["tris"], "range": list(b), "pass": b[0] <= r["tris"] <= b[1]})
        if r["tris"] > 800:
            checks.append({"id": r["id"], "check": "lod1_le_35pct", "lod1": r["lod1_tris"],
                           "pass": bool(r["lod1_tris"] is not None and r["lod1_tris"] <= 0.35 * r["tris"])})
    report = {"props": records, "checks": checks, "all_pass": all(c["pass"] for c in checks)}
    with open(os.path.join(OUT, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    shutil.rmtree(bp.TEXD, ignore_errors=True)
    print("[street] done: %d props, all_pass=%s" % (len(records), report["all_pass"]))
    for c in checks:
        if not c["pass"]:
            print("[street] FAIL", c)


if __name__ == "__main__":
    main()
