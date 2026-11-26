"""MIDNIGHT SYNDICATE - Istanbul kit generator (World Tour: Istanbul).

Run (Blender 5.3, deterministic):
  blender.exe --background --factory-startup --python build_istanbul.py -- build
Writes out/: GLBs (yali x3, wooden/apartment rows x3 with LOD0-2, 9 props, 3 skyline cards), textures/,
materials.json, catalog.json, report.json. Reuses the building kit helpers (build_buildings.py) and the
props kit helpers (build_props.py). Blender metres, Z up, building front faces -Y, origin = centre of the
front facade at the pavement. Engine JSON is in Godot coordinates: godot = (bx, bz, -by).
"""
import json
import math
import os
import random
import sys

_argv = sys.argv
sys.argv = ["x", "--", "noop"]            # importing build_buildings must not rebuild that kit
KIT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, KIT)
sys.path.insert(0, os.path.join(KIT, "..", "kit_buildings"))
sys.path.insert(0, os.path.join(KIT, "..", "kit_props"))
sys.path.insert(0, os.path.join(KIT, "..", "..", "..", "assets_src", "pipeline"))
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

import bake_vertex_ao as ao  # noqa: E402
import build_buildings as bb  # noqa: E402
import build_props as bp  # noqa: E402
import istanbul_props as ip  # noqa: E402
import istanbul_tex as tx  # noqa: E402
import istanbul_detail as idt  # noqa: E402
sys.argv = _argv

OUT = os.path.join(KIT, "out")
TEXD = os.path.join(OUT, "textures")
SEED = 20261126
# baked ambient occlusion: grid cell in m per LOD (None = not subdivided). LOD0 budget 12 000, LOD1 budget 1 200.
AO_CELL = {0: 3.5, 1: None}
Z = Vector((0.0, 0.0, 1.0))
GEN = "game/assets/world/kits/istanbul/textures/"
CC0 = "game/assets/textures/cc0/"

# ----------------------------------------------------------------------------- materials (new names only)
# (base hex, roughness, metallic, tint for impostor, cc0 set or None, uv tile m, generated textures)
NEW = {
    "M_Plaster_Butter": ("#D2B98A", 0.85, 0.0, "#A38B5E", "beige_wall_001", 2.0, None),
    "M_Plaster_Rose": ("#B88277", 0.85, 0.0, "#8D6259", "beige_wall_001", 2.0, None),
    "M_Plaster_Sky": ("#8E9E8A", 0.85, 0.0, "#6F7E6B", "beige_wall_001", 2.0, None),
    "M_Plaster_Sage": ("#7F9079", 0.85, 0.0, "#64745D", "beige_wall_001", 2.0, None),
    "M_Plaster_Ochre": ("#B9914F", 0.85, 0.0, "#8E6C3A", "clay_plaster", 2.0, None),
    "M_Plaster_Cream": ("#E3D7BB", 0.75, 0.0, "#B9AD92", "beige_wall_001", 2.0, None),
    "M_Wood_Yali_Dark": ("#8A6A4E", 0.7, 0.0, "#5A4534", "dark_wooden_planks", 1.5, None),
    "M_Wood_Oxblood": ("#8C4A3D", 0.7, 0.0, "#6B3A2F", "dark_wooden_planks", 1.5, None),
    "M_Paint_Shutter_Green": ("#2F5B4A", 0.6, 0.0, "#2F5B4A", None, 1.0, None),
    "M_Paint_Door_Blue": ("#34495A", 0.6, 0.0, "#34495A", None, 1.0, None),
    "M_Roof_Tile": ("#FFFFFF", 0.8, 0.0, "#7A3A22", None, 1.2, ("roof_tile_basecolor.png",)),
    "M_Cobble": ("#FFFFFF", 0.8, 0.0, "#585553", None, 1.0,
                 ("cobble_basecolor.png", "cobble_normal.png", "cobble_roughness.png")),
    "M_Cart_Teal": ("#0F4D57", 0.55, 0.0, "#0F4D57", None, 1.0, None),
    "M_Simit_Dough": ("#9E5718", 0.75, 0.0, "#9E5718", None, 1.0, None),
    "M_Fish_Silver": ("#B8C2CC", 0.35, 0.6, "#B8C2CC", None, 1.0, None),
}
SKY = {"M_Skyline_Asia": "skyline_asia.png", "M_Skyline_Bridge": "skyline_bridge.png", "M_Skyline_Domes": "skyline_domes.png"}


def register_blender_slots():
    for name, (base, rough, metal, tint, cc, tile, gen) in NEW.items():
        bb.FLAT_SLOTS[name] = dict(base=base, rough=rough, metal=metal, emit="#000000", estr=0.0, tint=tint, uv="metres")
    for name in SKY:
        bb.FLAT_SLOTS[name] = dict(base="#202838", rough=0.9, metal=0.0, emit="#FFFFFF", estr=0.0, tint="#202838", uv="card")


def write_materials(used):
    mats = {}
    for name, (base, rough, metal, tint, cc, tile, gen) in NEW.items():
        if name not in used:
            continue
        rec = dict(base_color=base, roughness=rough, metallic=metal, emission_color="#000000", emission_strength=0.0,
                   uv="metres, tiled every uv_tile_m", tint_for_impostor=tint, licence="project-owned")
        if cc:
            rec["textures"] = dict(basecolor=CC0 + cc + "/basecolor.jpg", normal=CC0 + cc + "/normal.jpg",
                                   roughness=CC0 + cc + "/roughness.jpg")
            rec["uv_tile_m"] = tile
            rec["licence"] = "CC0-1.0"
            rec["source"] = "cc0 set " + cc
        elif gen:
            keys = ["basecolor", "normal", "roughness"][:len(gen)]
            rec["textures"] = {k: GEN + g for k, g in zip(keys, gen)}
            rec["uv_tile_m"] = tile
            rec["source"] = "generated, project-owned"
        mats[name] = rec
    for name, f in SKY.items():
        if name in used:
            mats[name] = dict(base_color="#808080", roughness=0.9, metallic=0.0, emission_color="#FFFFFF",
                              emission_strength=1.6, uv="card: u along the arc, v up", texture_file=GEN + f,
                              licence="project-owned",
                              note="ShaderMaterial built by IstanbulMaterials (window_atlas shader, skyline_towers 0)")
    doc = {"coords": "godot_y_up", "generator": "build_istanbul.py", "materials": mats,
           "notes": "New names only. Existing M_ names (M_WindowAtlas, M_ShopInterior, M_Plaster_*, M_Lamp_*, ...) come from the other three materials.json files."}
    with open(os.path.join(OUT, "materials.json"), "w") as fh:
        json.dump(doc, fh, indent=1)


# ----------------------------------------------------------------------------- facade helpers
def win_op(ops, rng, u0, u1, v0, v1, wall, p, detail, shut=False, balc=False):
    t = bb.pick_tile(rng, p)
    ops.append(dict(kind="win", u0=u0, u1=u1, v0=v0, v1=v1, r=0.16 if detail else 0.04, glass="M_WindowAtlas",
                    uv=bb.tile_uv(t), tile=t, wall=wall, bars=False, sill=False, balc=balc, shut=shut))


def win_frames(b, f, ops, trim, shutter="M_Paint_Shutter_Green", surround=True):
    j = 0
    for o in ops:
        if o["kind"] != "win":
            continue
        u0, u1, v0, v1, r = o["u0"], o["u1"], o["v0"], o["v1"], o["r"]
        if surround:
            idt.casing(b, f, o, trim)                               # proud surround, sill, cornice lip
        bb.fbox(b, f, u0, u0 + 0.07, v0, v1, r - 0.07, r, trim)     # sash frame inside the reveal
        bb.fbox(b, f, u1 - 0.07, u1, v0, v1, r - 0.07, r, trim)
        bb.fbox(b, f, u0, u1, v1 - 0.07, v1, r - 0.07, r, trim)
        bb.fbox(b, f, u0, u1, v0, v0 + 0.07, r - 0.07, r, trim)
        um = 0.5 * (u0 + u1)
        bb.fbox(b, f, um - 0.025, um + 0.025, v0, v1, r - 0.06, r, trim)
        bb.fbox(b, f, u0, u1, v0 + 0.62 * (v1 - v0) - 0.025, v0 + 0.62 * (v1 - v0) + 0.025, r - 0.06, r, trim)
        if o.get("shut"):
            mode = j % 3
            j += 1
            if mode == 0:
                idt.open_shutter(b, f, o, shutter)
            elif mode == 1:
                idt.closed_shutters(b, f, o, shutter)


def cumba(b, f, uc, w, proj, vb, h, wall, trim, rng, detail, p_lit, roof=True, tile_mat="M_Roof_Tile"):
    hw = w / 2.0
    plan = [(uc - hw - proj, 0.0), (uc - hw, proj), (uc + hw, proj), (uc + hw + proj, 0.0)]

    def P(pt, v):
        return f.P(pt[0], v, -pt[1])

    vt = vb + h
    b.poly([P(plan[0], vb), P(plan[3], vb), P(plan[2], vb), P(plan[1], vb)], -Z, trim)
    k2 = 0.7071
    nrm = [-f.A * k2 + f.N * k2, f.N, f.A * k2 + f.N * k2]
    for k in range(3):
        a, c = plan[k], plan[k + 1]
        b.poly([P(a, vb), P(c, vb), P(c, vt), P(a, vt)], nrm[k], wall)
        if k < 2 or True:
            s0, s1 = 0.12, 0.88
            v0, v1 = vb + 0.38, vt - 0.3
            pa = (a[0] + (c[0] - a[0]) * s0, a[1] + (c[1] - a[1]) * s0)
            pc = (a[0] + (c[0] - a[0]) * s1, a[1] + (c[1] - a[1]) * s1)
            fr = [P(pa, v0 - 0.07), P(pc, v0 - 0.07), P(pc, v1 + 0.07), P(pa, v1 + 0.07)]
            b.poly([q + nrm[k] * 0.012 for q in fr], nrm[k], trim)
            panes = [(0.0, 1.0)] if k != 1 or not detail else [(0.0, 0.48), (0.52, 1.0)]
            for (t0, t1) in panes:
                qa = (pa[0] + (pc[0] - pa[0]) * t0, pa[1] + (pc[1] - pa[1]) * t0)
                qc = (pa[0] + (pc[0] - pa[0]) * t1, pa[1] + (pc[1] - pa[1]) * t1)
                gl = [P(qa, v0), P(qc, v0), P(qc, v1), P(qa, v1)]
                t = bb.pick_tile(rng, p_lit)
                b.poly([q + nrm[k] * 0.026 for q in gl], nrm[k], "M_WindowAtlas", bb.tile_uv(t))
            if detail:                                           # panelled apron: trim border, wall panel
                ap = [P(pa, vb + 0.1), P(pc, vb + 0.1), P(pc, v0 - 0.12), P(pa, v0 - 0.12)]
                b.poly([q + nrm[k] * 0.02 for q in ap], nrm[k], trim)
                ins = [(pa[0] + (pc[0] - pa[0]) * t, pa[1] + (pc[1] - pa[1]) * t) for t in (0.1, 0.9)]
                b.poly([P(ins[0], vb + 0.16) + nrm[k] * 0.03, P(ins[1], vb + 0.16) + nrm[k] * 0.03,
                        P(ins[1], v0 - 0.16) + nrm[k] * 0.03, P(ins[0], v0 - 0.16) + nrm[k] * 0.03], nrm[k], wall)
            if detail and k == 1:
                mid = (pa[0] + (pc[0] - pa[0]) * 0.5, pa[1])
                b.poly([P((mid[0] - 0.03, mid[1]), v0) + nrm[k] * 0.03, P((mid[0] + 0.03, mid[1]), v0) + nrm[k] * 0.03,
                        P((mid[0] + 0.03, mid[1]), v1) + nrm[k] * 0.03, P((mid[0] - 0.03, mid[1]), v1) + nrm[k] * 0.03],
                       nrm[k], trim)
        b.poly([P(a, vt) + nrm[k] * 0.03, P(c, vt) + nrm[k] * 0.03, P(c, vt + 0.14) + nrm[k] * 0.03,
                P(a, vt + 0.14) + nrm[k] * 0.03], nrm[k], trim)
    if roof:
        W1 = f.P(uc - hw, vt + 0.6, 0.0)
        W2 = f.P(uc + hw, vt + 0.6, 0.0)
        b.poly([P(plan[1], vt + 0.14), P(plan[2], vt + 0.14), W2, W1], f.N * 0.5 + Z, tile_mat)
        b.poly([P(plan[0], vt + 0.14), P(plan[1], vt + 0.14), W1], -f.A * 0.6 + f.N * 0.3 + Z * 0.7, tile_mat)
        b.poly([P(plan[2], vt + 0.14), P(plan[3], vt + 0.14), W2], f.A * 0.6 + f.N * 0.3 + Z * 0.7, tile_mat)
    else:
        b.poly([P(plan[0], vt + 0.14), P(plan[1], vt + 0.14), P(plan[2], vt + 0.14), P(plan[3], vt + 0.14)], Z, trim)
    if detail:                                           # three corbel brackets under the floor
        for (uu, tt) in ((plan[1][0] + 0.12, proj), (uc, proj), (plan[2][0] - 0.12, proj)):
            tri = [f.P(uu, vb - 0.8, 0.0), f.P(uu, vb, -tt), f.P(uu, vb, 0.0)]
            for sgn in (-1, 1):
                b.poly([q + f.A * (0.05 * sgn) for q in tri], f.A * sgn, trim)
            b.poly([f.P(uu - 0.05, vb - 0.8, 0.0), f.P(uu + 0.05, vb - 0.8, 0.0), f.P(uu + 0.05, vb, -tt),
                    f.P(uu - 0.05, vb, -tt)], f.N * 0.6 - Z * 0.8, trim)


def plain_ops(rng, f, detail, floors_z, nb, wall, p, ww=1.0, wh=1.9, shut=False):
    ops = []
    bw = f.W / nb
    for z0 in floors_z:
        for k in range(nb):
            cu = (k + 0.5) * bw
            win_op(ops, rng, cu - ww / 2, cu + ww / 2, z0 + 0.6, z0 + 0.6 + wh, wall, p, detail, shut)
    return ops


def band_trim(b, f, W, z, trim, lo=-0.06):
    bb.fbox(b, f, 0.0, W, z - 0.08, z + 0.1, lo, 0.0, trim)


def hip_roof(b, x0, x1, y0, y1, ze, pitch_deg, ovf, ovs, ovb, mat, trim, detail):
    xl, xr, yf, yb = x0 - ovs, x1 + ovs, y0 - ovf, y1 + ovb
    run = 0.5 * (yb - yf)
    rise = math.tan(math.radians(pitch_deg)) * run
    rl = max(2.0, (xr - xl) - (yb - yf))
    ym = 0.5 * (yf + yb)
    xm = 0.5 * (xl + xr)
    zr = ze + rise
    zeave = ze - math.tan(math.radians(pitch_deg)) * ovf
    h = 0.5 * rl
    Pfl, Pfr, Pbr, Pbl = (xl, yf, zeave), (xr, yf, zeave), (xr, yb, zeave), (xl, yb, zeave)
    Rl, Rr = (xm - h, ym, zr), (xm + h, ym, zr)
    b.poly([Pfl, Pfr, Rr, Rl], (0, -rise, run), mat)
    b.poly([Pbr, Pbl, Rl, Rr], (0, rise, run), mat)
    b.poly([Pbl, Pfl, Rl], (-rise, 0, run), mat)
    b.poly([Pfr, Pbr, Rr], (rise, 0, run), mat)
    b.poly([(xl, yf, zeave), (xl, yb, zeave), (xr, yb, zeave), (xr, yf, zeave)], (0, 0, -1), trim)
    if detail:
        for (a, c, d) in (((xl, yf), (xr, yf), 1), ((xl, yb), (xr, yb), 1)):
            b.box((a[0], a[1] - 0.04, zeave - 0.02), (c[0], c[1] + 0.04, zeave + 0.2), trim)
        for xx in (xl, xr):
            b.box((xx - 0.04, yf, zeave - 0.02), (xx + 0.04, yb, zeave + 0.2), trim)
        b.box((xm - h, ym - 0.08, zr), (xm + h, ym + 0.08, zr + 0.14), trim)
    return zr


def gable_roof_x(b, x0, x1, y0, y1, ze, rise, ovf, ovb, ovs, mat, wall, trim, detail):
    xl, xr, yf, yb = x0 - ovs, x1 + ovs, y0 - ovf, y1 + ovb
    ym = 0.5 * (y0 + y1)
    zr = ze + rise
    s = rise / (ym - y0)
    zf, zb = ze - s * ovf, ze - s * ovb
    b.poly([(xl, yf, zf), (xr, yf, zf), (xr, ym, zr), (xl, ym, zr)], (0, -rise, ym - y0), mat)
    b.poly([(xr, yb, zb), (xl, yb, zb), (xl, ym, zr), (xr, ym, zr)], (0, rise, ym - y0), mat)
    b.poly([(x0, y0, ze), (x0, y1, ze), (x0, ym, zr)], (-1, 0, 0), wall)
    b.poly([(x1, y1, ze), (x1, y0, ze), (x1, ym, zr)], (1, 0, 0), wall)
    b.poly([(xl, yf, zf), (xl, y0, ze), (xr, y0, ze), (xr, yf, zf)], (0, 0, -1), trim)
    if detail:
        b.box((xl, yf - 0.03, zf - 0.02), (xr, yf + 0.05, zf + 0.18), trim)
        b.box((xl, ym - 0.07, zr), (xr, ym + 0.07, zr + 0.12), trim)
        x = xl + 0.5                                             # rafter tails under both eaves
        while x < xr - 0.3:
            b.box((x, yf - 0.2, zf - 0.2), (x + 0.1, yf, zf - 0.04), trim)
            b.box((x, yb, zb - 0.2), (x + 0.1, yb + 0.2, zb - 0.04), trim)
            x += 0.85
    return zr


def chimney(b, x, y, z, h, mat="M_Brick_Red"):
    b.box((x - 0.35, y - 0.35, z), (x + 0.35, y + 0.35, z + h), mat)
    b.box((x - 0.45, y - 0.45, z + h), (x + 0.45, y + 0.45, z + h + 0.14), "M_Concrete_Smooth")


# ----------------------------------------------------------------------------- yali
YALI = [
    dict(id="bld_yali", variant="a", name="butter pastel, 3 floors", F=3, W=18.6, D=11.2, N=5, door=2,
         cumba=[1, 3], cumba_f=[1, 2], wall="M_Plaster_Butter", trim="M_Plaster_Cream", ov=1.3, pitch=18, chim=[(-4.5, 4.0), (5.0, 7.0)]),
    dict(id="bld_yali", variant="b", name="dark wood, 2 floors, long eaves", F=2, W=24.0, D=10.4, N=7, door=3,
         cumba=[1, 3, 5], cumba_f=[1], wall="M_Wood_Yali_Dark", trim="M_Plaster_Cream", ov=1.7, pitch=16, chim=[(-7.0, 5.0), (8.0, 5.0)]),
    dict(id="bld_yali", variant="c", name="dusty rose, 3 floors, central bay tower", F=3, W=15.4, D=12.6, N=5, door=2,
         cumba=[2], cumba_f=[1, 2], wall="M_Plaster_Rose", trim="M_Plaster_Cream", ov=1.4, pitch=20, chim=[(0.0, 6.5)]),
]
FH, GH = 3.4, 0.9


def build_yali(sp, lod, rng):
    b = bb.Builder()
    detail = lod == 0
    W, D, F, N = sp["W"], sp["D"], sp["F"], sp["N"]
    wall, trim = sp["wall"], sp["trim"]
    base = "M_Concrete_Stained"
    ze = GH + F * FH
    faces = {
        "front": bb.Face((-W / 2, 0, 0), (1, 0, 0), (0, -1, 0), W, ze),
        "right": bb.Face((W / 2, 0, 0), (0, 1, 0), (1, 0, 0), D, ze),
        "back": bb.Face((W / 2, D, 0), (-1, 0, 0), (0, 1, 0), W, ze),
        "left": bb.Face((-W / 2, D, 0), (0, -1, 0), (-1, 0, 0), D, ze),
    }
    zs = [GH + fl * FH for fl in range(F)]
    bwid = W / N
    for name, f in faces.items():
        ops = []
        dface = detail and name == "front"
        if name == "front":
            for fl in range(F):
                for k in range(N):
                    cu = (k + 0.5) * bwid
                    if fl == 0 and k == sp["door"]:
                        ops.append(dict(kind="door", u0=cu - 0.7, u1=cu + 0.7, v0=GH, v1=GH + 2.5, r=0.25 if detail else 0.05,
                                        glass="M_Paint_Door_Blue", wall=base))
                        if detail:
                            win_op(ops, rng, cu - 0.62, cu + 0.62, GH + 2.56, GH + 2.9, wall, 0.5, True)
                    elif fl in sp["cumba_f"] and k in sp["cumba"]:
                        continue
                    else:
                        win_op(ops, rng, cu - 0.52, cu + 0.52, zs[fl] + 0.6, zs[fl] + 2.5, wall, 0.5, dface, shut=(fl == 0 and k % 2 == 0))
        else:
            span = f.W
            nb = max(2, int(round(span / 3.7)))
            fz = zs if name != "right" or True else zs
            ops = plain_ops(rng, f, dface, fz, nb, wall, 0.45, 0.95, 1.8)
        bb.wall_decomp(b, f, ops, wall, base, GH)
        bb.emit_ops(b, f, ops, dface)
        if detail:
            win_frames(b, f, ops, trim, surround=(name == "front"))
            for o in ops:
                if o["kind"] == "door":
                    idt.door_panels(b, f, o, trim)
            for z in zs[1:]:
                band_trim(b, f, f.W, z - 0.12, trim)
            bb.fbox(b, f, 0.0, f.W, GH - 0.1, GH + 0.05, -0.08, 0.0, "M_Concrete_Smooth")
            bb.fbox(b, f, -0.05, 0.22, GH, ze, -0.07, 0.0, trim)
            bb.fbox(b, f, f.W - 0.22, f.W + 0.05, GH, ze, -0.07, 0.0, trim)
            bb.fbox(b, f, -0.1, f.W + 0.1, ze - 0.22, ze, -0.15, 0.0, trim)
            if name == "front":
                excl = [(o["u0"], o["u1"], o["v0"], o["v1"]) for o in ops]
                for fl in sp["cumba_f"]:
                    for k in sp["cumba"]:
                        cx = (k + 0.5) * bwid
                        excl.append((cx - 2.2, cx + 2.2, zs[fl], zs[fl] + FH))
                idt.siding(b, f, excl, f.W, GH + 0.05, ze - 0.25, wall)
                idt.downpipe(b, f, 0.3, GH + 0.05, ze - 0.3, "M_Metal_Painted")
                idt.downpipe(b, f, f.W - 0.4, GH + 0.05, ze - 0.3, "M_Metal_Painted")
                cu_d = (sp["door"] + 0.5) * bwid
                for sx in (-1, 1):
                    idt.lantern(b, f, cu_d + sx * 1.35, GH + 1.7, "M_Metal_Painted")
                for i, o in enumerate(ops):
                    if o["kind"] == "win" and abs(o["v0"] - (zs[1] + 0.6)) < 1e-6 and i % 2 == 0:
                        idt.flower_box(b, f, o, "M_Wood_Yali_Dark", "M_Paint_Shutter_Green")
        if name == "front":
            for fl in sp["cumba_f"]:
                for k in sp["cumba"]:
                    cumba(b, f, (k + 0.5) * bwid, 2.3 if sp["variant"] != "c" else 2.6, 0.85, zs[fl] + 0.12, FH - 0.24,
                          wall, trim, rng, detail, 0.55, roof=(fl == F - 1))
            cu = (sp["door"] + 0.5) * bwid
            for i in range(3):                         # entrance steps
                bb.fbox(b, f, cu - 0.95, cu + 0.95, 0.0, 0.3 * (i + 1), -0.35 * (3 - i), 0.0, "M_Concrete_Smooth")
            if detail:
                bb.fbox(b, f, cu - 1.1, cu + 1.1, GH + 2.95, GH + 3.1, -0.7, 0.0, trim)        # door hood over the transom
                for sx in (-1, 1):
                    bb.fbox(b, f, cu + sx * 0.95 - 0.04, cu + sx * 0.95 + 0.04, GH + 1.9, GH + 2.95, -0.65, -0.55, trim)
            if lod == 0:
                b.anchor("anchor_sign_01", f.P(cu, GH + 3.1, -0.15), f.N)
    zr = hip_roof(b, -W / 2, W / 2, 0.0, D, ze, sp["pitch"], sp["ov"], sp["ov"], sp["ov"] * 0.6, "M_Roof_Tile", trim, detail)
    if detail:
        ov, pit, yf, yb = sp["ov"], math.radians(sp["pitch"]), -sp["ov"], D + sp["ov"] * 0.6
        xl, xr = -W / 2 - sp["ov"], W / 2 + sp["ov"]
        ym, zeave = 0.5 * (yf + yb), ze - math.tan(pit) * sp["ov"]
        hh = 0.5 * max(2.0, (xr - xl) - (yb - yf))
        for p0, p1 in (((xl, yf, zeave), (-hh, ym, zr)), ((xr, yf, zeave), (hh, ym, zr)),
                       ((xl, yb, zeave), (-hh, ym, zr)), ((xr, yb, zeave), (hh, ym, zr))):
            idt.ridge_strip(b, p0, p1, "M_Roof_Tile")
        if sp["variant"] in ("a", "c"):
            yd = yf + 0.5 * (ym - yf)
            zsl = zeave + (zr - zeave) * (yd - yf) / (ym - yf)
            for xc in (-0.25 * W, 0.25 * W):
                idt.dormer(b, xc, yd - 0.45, zsl - 0.25, 1.1, trim, "M_WindowAtlas", "M_Roof_Tile", rng)
        for (cx, cy) in sp["chim"]:
            chimney(b, cx, cy, ze + 0.6, zr - ze + 0.7)
        # exposed rafter brackets under the wide eave (front and back)
        for yy, sgn in ((0.0, -1), (D, 1)):
            x = -W / 2 + 0.6
            while x < W / 2 - 0.3:
                b.box((x, yy + sgn * 0.05 - (0.04 if sgn < 0 else -0.0), ze - 0.45), (x + 0.1, yy + sgn * 0.62, ze - 0.2), trim)
                x += 1.3
    return b, ze


# ----------------------------------------------------------------------------- wooden / apartment rows
def H_(fl):
    return 3.5 + (fl - 1) * 3.1


ROWS = [
    dict(id="bld_ahsap_row", variant="a", name="pastel street row, 3 houses", D=10.4, gh=0.5, siding=False, houses=[
        dict(w=5.6, F=3, wall="M_Plaster_Butter", trim="M_Plaster_Cream", cumba=[1, 2], shop="M_Awning_Red", pitch=0.34, chim=True),
        dict(w=6.2, F=4, wall="M_Plaster_Rose", trim="M_Plaster_Cream", cumba=[2, 3], shop=None, pitch=0.30, chim=False),
        dict(w=5.2, F=3, wall="M_Plaster_Sky", trim="M_Plaster_Cream", cumba=[], shop="M_Awning_Teal", pitch=0.34, chim=True)]),
    dict(id="bld_ahsap_row", variant="b", name="wooden row, 4 narrow houses", D=9.6, gh=0.5, siding=False, houses=[
        dict(w=4.6, F=3, wall="M_Wood_Yali_Dark", trim="M_Plaster_Cream", cumba=[1, 2], shop=None, pitch=0.36, chim=True, shut=True),
        dict(w=5.0, F=3, wall="M_Plaster_Ochre", trim="M_Plaster_Cream", cumba=[], shop="M_Awning_Teal", pitch=0.32, chim=False, shut=True),
        dict(w=4.4, F=4, wall="M_Wood_Oxblood", trim="M_Plaster_Cream", cumba=[2, 3], shop=None, pitch=0.36, chim=True, shut=True),
        dict(w=5.2, F=3, wall="M_Plaster_Sage", trim="M_Plaster_Cream", cumba=[1], shop="M_Awning_Red", pitch=0.32, chim=False, shut=True)]),
    dict(id="bld_ahsap_row", variant="c", name="old apartment row with balconies and a corner cumba", D=11.0, gh=0.5, siding=False, houses=[
        dict(w=6.4, F=5, wall="M_Plaster_Cream", trim="M_Plaster_Ochre", cumba=[2, 3], shop="M_Awning_Teal", pitch=0.26, chim=True, balc=[1, 3, 4]),
        dict(w=6.2, F=5, wall="M_Plaster_Ochre", trim="M_Plaster_Cream", cumba=[], shop="M_Awning_Red", pitch=0.26, chim=False, balc=[1, 2, 3, 4]),
        dict(w=5.6, F=4, wall="M_Plaster_Sky", trim="M_Plaster_Cream", cumba=[1, 2, 3], shop=None, pitch=0.30, chim=True)]),
]


def build_row(sp, lod, rng):
    b = bb.Builder()
    detail = lod == 0
    D, gh = sp["D"], sp["gh"]
    W = sum(h["w"] for h in sp["houses"])
    x = -W / 2
    shopi = 0
    off = rng.randrange(4)
    spans = []
    for hi, h in enumerate(sp["houses"]):
        w, F = h["w"], h["F"]
        ze = H_(F)
        wall, trim = h["wall"], h["trim"]
        base = "M_Concrete_Stained" if hi % 2 == 0 else "M_Brick_Dark"
        faces = {
            "front": bb.Face((x, 0, 0), (1, 0, 0), (0, -1, 0), w, ze),
            "right": bb.Face((x + w, 0, 0), (0, 1, 0), (1, 0, 0), D, ze),
            "back": bb.Face((x + w, D, 0), (-1, 0, 0), (0, 1, 0), w, ze),
            "left": bb.Face((x, D, 0), (0, -1, 0), (-1, 0, 0), D, ze),
        }
        for name, f in faces.items():
            ops = []
            if name == "front":
                dface = detail
                uc = w / 2
                if h["shop"]:
                    ops.append(dict(kind="door", u0=0.3, u1=1.15, v0=0.0, v1=2.3, r=0.25 if detail else 0.05,
                                    glass="M_Paint_Door_Blue", wall=base))
                    ops.append(dict(kind="shop", u0=1.35, u1=w - 0.3, v0=0.55, v1=2.8, r=0.35 if detail else 0.05,
                                    glass="M_ShopGlass", wall=base, interior=True, q=bb.shop_quad(off + shopi)))
                    shopi += 1
                else:
                    ops.append(dict(kind="door", u0=uc - 0.5, u1=uc + 0.5, v0=0.0, v1=2.4, r=0.25 if detail else 0.05,
                                    glass="M_Paint_Door_Blue", wall=base))
                    for s in (-1, 1):
                        if w > 4.9 or s < 0:
                            cu = uc + s * (1.75 if w > 4.9 else 1.45)
                            if 0.5 < cu < w - 0.5:
                                win_op(ops, rng, cu - 0.45, cu + 0.45, 0.95, 2.6, wall, 0.5, dface, shut=h.get("shut", False))
                for fl in range(1, F):
                    z0 = H_(fl) - 3.1 if fl > 0 else 0
                    z0 = 3.5 + (fl - 1) * 3.1
                    if fl in h["cumba"]:
                        continue
                    n = 2 if w >= 5.0 else 1
                    for k in range(n):
                        cu = (k + 0.5) * w / n
                        win_op(ops, rng, cu - 0.47, cu + 0.47, z0 + 0.6, z0 + 2.4, wall, 0.5, dface,
                               shut=h.get("shut", False), balc=bool(detail and fl in h.get("balc", [])))
            else:
                nb = 1 if f.W < 5.5 else 2
                if name in ("right", "left") and ((name == "left" and hi > 0) or (name == "right" and hi < len(sp["houses"]) - 1)):
                    nb = 0                                    # party walls
                zl = [0.9] + [3.5 + (fl - 1) * 3.1 + 0.6 for fl in range(1, F)]
                ops = []
                if nb > 0:
                    bw = f.W / nb
                    for zz in zl:
                        for k in range(nb):
                            cu = (k + 0.5) * bw
                            win_op(ops, rng, cu - 0.45, cu + 0.45, zz, zz + 1.6, wall, 0.4, False)
            dd = detail and name == "front"
            bb.wall_decomp(b, f, ops, wall, base, gh if name == "front" else 0.0)
            bb.emit_ops(b, f, ops, dd)
            if detail:
                win_frames(b, f, ops, trim, surround=(name == "front"))
                for o in ops:
                    if o["kind"] == "door":
                        idt.door_panels(b, f, o, trim)
                    if o.get("balc"):
                        idt.balcony_bars(b, f, o, "M_Metal_Painted")
            if dd:
                for fl in range(1, F):
                    band_trim(b, f, w, 3.5 + (fl - 1) * 3.1 - 0.12, trim)
                bb.fbox(b, f, 0.0, 0.18, 0.0, ze, -0.07, 0.0, trim)
                bb.fbox(b, f, w - 0.18, w, 0.0, ze, -0.07, 0.0, trim)
                bb.fbox(b, f, -0.1, w + 0.1, ze - 0.2, ze, -0.14, 0.0, trim)
                dop = [o for o in ops if o["kind"] == "door"][0]
                bb.fbox(b, f, dop["u0"] - 0.08, dop["u0"], 0.0, dop["v1"] + 0.1, -0.1, 0.1, trim)
                bb.fbox(b, f, dop["u1"], dop["u1"] + 0.08, 0.0, dop["v1"] + 0.1, -0.1, 0.1, trim)
                bb.fbox(b, f, dop["u0"] - 0.14, dop["u1"] + 0.14, dop["v1"], dop["v1"] + 0.16, -0.45, 0.1, trim)
                bb.fbox(b, f, dop["u0"] - 0.1, dop["u1"] + 0.1, -0.0, 0.12, -0.3, 0.0, "M_Concrete_Smooth")
                for k in range(int(w / 1.1)):
                    bb.fbox(b, f, 0.35 + k * 1.1, 0.5 + k * 1.1, ze - 0.62, ze - 0.2, -0.6, -0.14, trim)
            if name == "front":
                if h["shop"]:
                    bb.fbox(b, f, 1.2, w - 0.15, 2.95, 3.4, -0.12, 0.0, "M_SignBand")
                    for k in range(5):
                        ua = 1.25 + k * (w - 1.5) / 5.0
                        ub = ua + (w - 1.5) / 5.0
                        b.poly([f.P(ua, 2.95, -0.05), f.P(ub, 2.95, -0.05), f.P(ub, 2.45, -1.2), f.P(ua, 2.45, -1.2)],
                               f.N * 0.5 + Z, h["shop"] if k % 2 == 0 else "M_Plaster_Cream")
                    if detail:
                        idt.awning_arms(b, f, [1.4, w - 0.5], 2.45, 1.2, "M_Metal_Painted")
                    if lod == 0:
                        b.anchor("anchor_sign_%02d" % shopi, f.P(w / 2 + 0.6, 3.2, -0.13), f.N)
                if detail:
                    excl = [(o["u0"], o["u1"], o["v0"], o["v1"]) for o in ops]
                    if h["shop"]:
                        excl.append((1.2, w - 0.15, 2.95, 3.4))
                    for fl in h["cumba"]:
                        z0 = 3.5 + (fl - 1) * 3.1
                        cw = min(2.3, w - 1.8)
                        excl.append((w / 2 - cw / 2 - 0.9, w / 2 + cw / 2 + 0.9, z0, z0 + 3.0))
                    if sp.get("siding", True):
                        idt.siding(b, f, excl, w, gh + 0.05, ze - 0.25, wall)
                    if not h["shop"]:
                        idt.downpipe(b, f, 0.3, gh + 0.05, ze - 0.3, "M_Metal_Painted")
                        idt.lantern(b, f, w / 2 + 0.78, 1.7, "M_Metal_Painted")
                    for i, o in enumerate(ops):
                        if sp["variant"] != "a" and o["kind"] == "win" and abs(o["v0"] - 4.1) < 1e-6 and i % 3 == 0:
                            idt.flower_box(b, f, o, "M_Wood_Yali_Dark", "M_Paint_Shutter_Green")
                for fl in h["cumba"]:
                    z0 = 3.5 + (fl - 1) * 3.1
                    cw = min(2.3, w - 1.8)
                    cumba(b, f, w / 2, cw, 0.8, z0 + 0.1, 2.9, wall, trim, rng, detail, 0.55, roof=(fl == max(h["cumba"])))
        # roof
        rise = h["pitch"] * (D / 2)
        zr = gable_roof_x(b, x, x + w, 0.0, D, ze, rise, 0.9, 0.4, 0.12, "M_Roof_Tile", wall, trim, detail)
        if detail and h["chim"]:
            chimney(b, x + w * 0.7, D * 0.5 + 0.8, ze + 0.9, rise + 0.3)
        spans.append((x, x + w, ze, zr))
        x += w
    return b, spans


# ----------------------------------------------------------------------------- LOD2 hulls
def lod2_boxes(boxes, D, roofs):
    """boxes: (x0, x1, ze, zr). Faces mapped to the impostor atlas quadrants (TL front, TR back, BL left, BR right)."""
    b = bb.Builder()
    mat = "M_ImpostorAtlas"
    W = max(bx[1] for bx in boxes) - min(bx[0] for bx in boxes)
    xmin = min(bx[0] for bx in boxes)
    Hm = max(bx[2] for bx in boxes)
    e = 0.004
    for (x0, x1, ze, zr) in boxes:
        ua, ub = (x0 - xmin) / W, (x1 - xmin) / W
        va, vb = 0.5 + 0.5 * 0.0, 0.5 + 0.5 * min(1.0, ze / Hm)
        fu = lambda q0, q1: [(q0 + e + (q1 - q0 - 2 * e) * ua, 0.5 + e), (q0 + e + (q1 - q0 - 2 * e) * ub, 0.5 + e),
                              (q0 + e + (q1 - q0 - 2 * e) * ub, vb), (q0 + e + (q1 - q0 - 2 * e) * ua, vb)]
        b.poly([(x0, 0, 0), (x1, 0, 0), (x1, 0, ze), (x0, 0, ze)], (0, -1, 0), mat, fu(0.0, 0.5))
        b.poly([(x1, D, 0), (x0, D, 0), (x0, D, ze), (x1, D, ze)], (0, 1, 0), mat,
               [(1.0 - (0.5 - e) * ub - e - 0.0, 0.5 + e), (1.0 - (0.5 - e) * ua - e - 0.0, 0.5 + e),
                (1.0 - (0.5 - e) * ua - e - 0.0, vb), (1.0 - (0.5 - e) * ub - e - 0.0, vb)])
        side_uv = [(0.0 + e, 0.0 + e), (0.5 - e, 0.0 + e), (0.5 - e, min(0.5, 0.5 * ze / Hm) - e), (0.0 + e, min(0.5, 0.5 * ze / Hm) - e)]
        b.poly([(x0, D, 0), (x0, 0, 0), (x0, 0, ze), (x0, D, ze)], (-1, 0, 0), mat, side_uv)
        b.poly([(x1, 0, 0), (x1, D, 0), (x1, D, ze), (x1, 0, ze)], (1, 0, 0), mat, [(u + 0.5, v) for u, v in side_uv])
        patch = [(0.006, 0.006), (0.02, 0.006), (0.02, 0.02), (0.006, 0.02)]
        if roofs == "gable":
            ym = D / 2
            zr_ = zr
            b.poly([(x0, 0, ze), (x1, 0, ze), (x1, ym, zr_), (x0, ym, zr_)], (0, -(zr_ - ze), ym), mat, patch)
            b.poly([(x1, D, ze), (x0, D, ze), (x0, ym, zr_), (x1, ym, zr_)], (0, (zr_ - ze), ym), mat, patch)
        else:
            b.poly([(x0, 0, ze), (x1, 0, ze), (x1, D, ze), (x0, D, ze)], (0, 0, 1), mat, patch)
    return b


def lod2_yali(sp, ze):
    W, D = sp["W"], sp["D"]
    b = lod2_boxes([(-W / 2, W / 2, ze, ze)], D, "flat")
    ov = sp["ov"]
    h = math.tan(math.radians(sp["pitch"])) * (D / 2 + ov)
    patch = [(0.006, 0.006), (0.02, 0.006), (0.02, 0.02), (0.006, 0.02)]
    xl, xr, yf, yb = -W / 2 - ov, W / 2 + ov, -ov, D + ov * 0.6
    ym = 0.5 * (yf + yb)
    rl = max(2.0, (xr - xl) - (yb - yf)) / 2
    Rl, Rr = (-rl, ym, ze + h), (rl, ym, ze + h)
    b.poly([(xl, yf, ze), (xr, yf, ze), Rr, Rl], (0, -h, 3), "M_ImpostorAtlas", patch)
    b.poly([(xr, yb, ze), (xl, yb, ze), Rl, Rr], (0, h, 3), "M_ImpostorAtlas", patch)
    b.poly([(xl, yb, ze), (xl, yf, ze), Rl], (-h, 0, 3), "M_ImpostorAtlas", patch[:3])
    b.poly([(xr, yf, ze), (xr, yb, ze), Rr], (h, 0, 3), "M_ImpostorAtlas", patch[:3])
    return b


# ----------------------------------------------------------------------------- export
def box_bounds(bld):
    return bb.bounds(bld)


def export_building(name, spec_id, variant, kind, lods, anchors_b, spv, var, district_tags, cat, rep):
    bb.clear_scene()
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    objs, tri = [], {}
    for lod in (0, 1, 2):
        o = bb.mesh_object("LOD%d" % lod, lods[lod], root)
        objs.append(o)
        tri["LOD%d" % lod] = lods[lod].total_tris()
        if lod in AO_CELL:  # baked ambient occlusion, LOD2 impostor card is left alone
            ao.bake_ao([o], cell_m=AO_CELL[lod])
            o.data.calc_loop_triangles()
            tri["LOD%d" % lod] = len(o.data.loop_triangles)
    (x0, x1), (y0, y1), (z0, z1) = bb.bounds(lods[0])
    col = bb.mesh_object(name + "-colonly", bb._box_builder((x0, y0, z0), (x1, y1, z1)), root)
    objs.append(col)
    anchors = []
    for an, p, n in lods[0].anchors:
        e = bpy.data.objects.new(an, None)
        e.location = p
        e.parent = root
        bpy.context.scene.collection.objects.link(e)
        objs.append(e)
        anchors.append(dict(name=an, position=bb.to_godot(p), normal=bb.to_godot(n)))
    ao.export_glb_ao(os.path.join(OUT, name + ".glb"), objs, root, apply=True, tangents=True)
    mats = sorted(set(sum([list(lods[k].parts.keys()) for k in (0, 1, 2)], [])))
    ratio = tri["LOD1"] / max(1, tri["LOD0"])
    cat["buildings"].append(dict(
        id=name, type=spec_id, variant=variant, file=name + ".glb", district="istanbul", tags=district_tags,
        storeys=spv["storeys"], width=round(x1 - x0, 3), depth=round(y1 - y0, 3), height=round(z1 - z0, 3), tris=tri,
        materials=mats, impostor_textures=["textures/impostor_%s_basecolor.png" % name, "textures/impostor_%s_emissive.png" % name],
        anchors=anchors, notes=spv.get("name", ""),
        collider=dict(name=name + "-colonly", type="box", size=[round(x1 - x0, 3), round(z1 - z0, 3), round(y1 - y0, 3)],
                      center=bb.to_godot(Vector((0.5 * (x0 + x1), 0.5 * (y0 + y1), 0.5 * (z0 + z1)))))))
    rep["buildings"][name] = dict(lod0=tri["LOD0"], lod1=tri["LOD1"], lod2=tri["LOD2"], lod1_ratio=round(ratio, 3),
                                  lod1_ok=ratio <= 0.30, lod0_in_budget=3000 <= tri["LOD0"] <= 12000)
    print("BUILT", name, tri, "ratio", round(ratio, 3))
    return mats


def build_buildings(cat, rep):
    used = set()
    idx = 0
    for sp in YALI:
        idx += 1
        name = "%s_%s" % (sp["id"], sp["variant"])
        l0, ze = build_yali(sp, 0, random.Random(SEED + idx))
        l1, _ = build_yali(sp, 1, random.Random(SEED + idx))
        spv = dict(sp, storeys=sp["F"])
        ib, ie = bb.impostor_atlas(random.Random(SEED + idx * 13), dict(storeys=sp["F"] * 2, W=sp["W"], D=sp["D"]), dict(wall=sp["wall"]))
        bb.write_png(os.path.join(TEXD, "impostor_%s_basecolor.png" % name), ib)
        bb.write_png(os.path.join(TEXD, "impostor_%s_emissive.png" % name), ie)
        l2 = lod2_yali(sp, ze)
        used.update(export_building(name, sp["id"], sp["variant"], "yali", {0: l0, 1: l1, 2: l2}, None, spv, None,
                                    ["istanbul", "yali", "waterside", "wooden", "cumba"], cat, rep))
    for sp in ROWS:
        idx += 1
        name = "%s_%s" % (sp["id"], sp["variant"])
        l0, spans = build_row(sp, 0, random.Random(SEED + idx))
        l1, _ = build_row(sp, 1, random.Random(SEED + idx))
        W = sum(h["w"] for h in sp["houses"])
        mx = max(h["F"] for h in sp["houses"])
        spv = dict(sp, storeys=mx)
        ib, ie = bb.impostor_atlas(random.Random(SEED + idx * 13), dict(storeys=mx, W=W, D=sp["D"]), dict(wall=sp["houses"][0]["wall"]))
        bb.write_png(os.path.join(TEXD, "impostor_%s_basecolor.png" % name), ib)
        bb.write_png(os.path.join(TEXD, "impostor_%s_emissive.png" % name), ie)
        l2 = lod2_boxes([(a, c, ze, zr) for (a, c, ze, zr) in spans], sp["D"], "gable")
        used.update(export_building(name, sp["id"], sp["variant"], "row", {0: l0, 1: l1, 2: l2}, None, spv, None,
                                    ["istanbul", "coast_street", "row", "cumba", "shops"], cat, rep))
    return used


# ----------------------------------------------------------------------------- props and skylines
def build_props_and_cards(cat, rep):
    bp.OUT = OUT
    ip.define_materials()
    reg = {
        "tram_rail_segment": ip.p_tram(), "cobble_strip": ip.p_cobble(), "seaside_railing": ip.p_railing(),
        "promenade_lamp": ip.p_lamp(), "simit_cart": ip.p_simit(), "fish_cart": ip.p_fish(), "ferry_pier_light": ip.p_pier(),
    }
    # skyline cards
    L, Hc, h, _img = tx.skyline_asia()
    V, F = ip.card_from_columns(L, Hc, h)
    s = ip.make_card("skyline_asia_hills", "M_Skyline_Asia", L, Hc, V, F)
    s["notes"] = "Far Asian-shore hills card, %.0f m long, lit houses, hill mosque and mast; cut to the hill silhouette" % L
    reg["skyline_asia_hills"] = dict(s, _L=L, _Hc=Hc)
    L, Hc, shapes, land, _img = tx.skyline_bridge()
    V, F = ip.card_from_quads(L, 900.0, [q for _, q in shapes])
    V2, F2 = ip.card_from_columns(L, Hc, land)
    off = len(V)
    V += V2
    F += [tuple(i + off for i in fc) for fc in F2]
    s = ip.make_card("skyline_bridge", "M_Skyline_Bridge", L, Hc, V, F)
    s["notes"] = "Far generic suspension bridge, %.0f m long, necklace lights on the cables, red tower beacons (not an exact replica)" % L
    reg["skyline_bridge"] = dict(s, _L=L, _Hc=Hc)
    L, Hc, h, _img = tx.skyline_domes()
    V, F = ip.card_from_columns(L, Hc, h, step=4)
    s = ip.make_card("skyline_domes", "M_Skyline_Domes", L, Hc, V, F)
    s["notes"] = "Far skyline of domes and minarets, %.0f m long, soft flood-lit silhouettes (original massing, never raced through)" % L
    reg["skyline_domes"] = dict(s, _L=L, _Hc=Hc)
    used = set()
    for pid, spec in reg.items():
        L_ = spec.pop("_L", None)
        Hc_ = spec.pop("_Hc", None)
        r = bp.build_prop(pid, spec)
        used.update(r["materials"])
        cat["items"].append({"id": r["id"], "category": r["category"], "file": r["file"], "size": r["size"],
                             "tris": r["tris"], "lod1_tris": r["lod1_tris"], "lod1_file": r["lod1_file"],
                             "collider_tris": r["collider_tris"], "materials": r["materials"], "lights": r["lights"],
                             "emissive": r["emissive"], "mount": r["mount"], "notes": r["notes"]})
        rep["props"][pid] = dict(tris=r["tris"], lod1=r["lod1_tris"], size=r["size"], budget=r["budget"],
                                 in_budget=(r["budget"] is None or r["budget"][0] <= r["tris"] <= r["budget"][1]))
        print("PROP", pid, r["tris"], r["lod1_tris"], r["size"])
    return used


def write_textures():
    os.makedirs(TEXD, exist_ok=True)
    b, n, r = tx.gen_cobble()
    bb.write_png(os.path.join(TEXD, "cobble_basecolor.png"), b)
    bb.write_png(os.path.join(TEXD, "cobble_normal.png"), n)
    bb.write_png(os.path.join(TEXD, "cobble_roughness.png"), r)
    bb.write_png(os.path.join(TEXD, "roof_tile_basecolor.png"), tx.gen_roof_tile())
    for fn, f in (("skyline_asia.png", tx.skyline_asia), ("skyline_domes.png", tx.skyline_domes), ("skyline_bridge.png", tx.skyline_bridge)):
        bb.write_png(os.path.join(TEXD, fn), f()[-1])


def main():
    os.makedirs(OUT, exist_ok=True)
    register_blender_slots()
    write_textures()
    cat = {"coords": "godot_y_up", "generator": "build_istanbul.py", "seed": SEED, "kit": "istanbul",
           "source": "assets_src/world/kit_istanbul/build_istanbul.py", "materials_file": "materials.json",
           "buildings": [], "items": []}
    rep = {"buildings": {}, "props": {}}
    used = build_buildings(cat, rep)
    used |= build_props_and_cards(cat, rep)
    write_materials(used)
    rep["summary"] = dict(
        buildings=len(cat["buildings"]), items=len(cat["items"]),
        all_lod1_ok=all(v["lod1_ok"] for v in rep["buildings"].values()),
        all_lod0_in_budget=all(v["lod0_in_budget"] for v in rep["buildings"].values()),
        all_props_in_budget=all(v["in_budget"] for v in rep["props"].values()))
    with open(os.path.join(OUT, "catalog.json"), "w") as fh:
        json.dump(cat, fh, indent=1)
    with open(os.path.join(OUT, "report.json"), "w") as fh:
        json.dump(rep, fh, indent=1)
    print("SUMMARY", json.dumps(rep["summary"]))


if "build" in _argv[_argv.index("--") + 1:] if "--" in _argv else False:
    main()
