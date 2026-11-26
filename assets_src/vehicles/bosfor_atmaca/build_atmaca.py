"""Bosfor Atmaca: deterministic build of one variant (stock | modified | taxi).

  blender --background --factory-startup --python build_atmaca.py -- <variant>

Writes out/atmaca_<variant>.blend, out/atmaca_<variant>_lod{0,1,2}.glb, out/summary_<variant>.json.
Surface approach of the hero car (stations along the length, a section polygon per station, straight window
edges by cutting pockets with prisms built from the glass outline) with its own data: a boxy three-box sedan.
Z up, nose -Y, origin at the wheelbase mid-point, +X right. Spec: docs/art/CAR_ATMACA_BRIEF.md.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")

Y_NOSE, Y_TAIL = -2.00, 2.20
AXLE = {"F": -1.225, "R": 1.225}
HALF_W = 0.825
ZC = 0.58  # the one body crease
SLOPE_F = 0.52 / 0.75  # windscreen rise per metre
SLOPE_R = 0.52 / 0.43  # rear screen drop per metre
ROOF_Z = 1.40
Y_ROOF0, Y_ROOF1 = -0.10, 0.95

VARIANTS = {
    "stock": dict(dz=0.0, wx=0.71, R=0.295, tw=0.165, rim_r=0.165, kind="steel", flares=False, glass="M_GlassClear",
                  paint=(0xE9, 0xDF, 0xC4), black_trim=False, arch_gap=0.045, brake_r=0.115, caliper=(0.45, 0.45, 0.47)),
    "modified": dict(dz=-0.05, wx=0.74, R=0.2875, tw=0.195, rim_r=0.190, kind="star", flares=True, glass="M_Glass",
                     paint=(0xD6, 0x5A, 0x14), black_trim=True, arch_gap=0.024, brake_r=0.150, caliper=(0.85, 0.08, 0.06)),
    "taxi": dict(dz=0.0, wx=0.71, R=0.295, tw=0.165, rim_r=0.165, kind="steel", flares=False, glass="M_GlassClear",
                 paint=(0xF2, 0xB8, 0x0B), black_trim=False, arch_gap=0.045, brake_r=0.115, caliper=(0.45, 0.45, 0.47)),
}


# ------------------------------------------------------------------ small helpers
def lin(hexrgb):
    out = []
    for v in hexrgb:
        v = v / 255.0
        out.append(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4)
    return tuple(out) + (1.0,)


def tbl(t, y):
    if y <= t[0][0]:
        return t[0][1]
    for (y0, v0), (y1, v1) in zip(t, t[1:]):
        if y <= y1:
            return v0 + (v1 - v0) * (y - y0) / (y1 - y0)
    return t[-1][1]


def corner_off(d, rho):
    """Quarter-circle corner: how far a surface is pulled in at distance d from the end face."""
    if d >= rho:
        return 0.0
    return rho * (1.0 - math.sqrt(max(0.0, 1.0 - (1.0 - d / rho) ** 2)))


def round_poly(pts, radii, n=5):
    """Open polyline with Bezier-rounded interior corners (radius radii[i], 0 keeps the corner sharp)."""
    out = [tuple(pts[0])]
    for i in range(1, len(pts) - 1):
        r = radii[i]
        if r <= 0:
            out.append(tuple(pts[i]))
            continue
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[i + 1])
        d1, d2 = p0 - p1, p2 - p1
        rr = min(r, d1.length * 0.5, d2.length * 0.5)
        a, b = p1 + d1.normalized() * rr, p1 + d2.normalized() * rr
        for k in range(n + 1):
            t = k / n
            q = (1 - t) ** 2 * a + 2 * t * (1 - t) * p1 + t * t * b
            out.append((q.x, q.y))
    out.append(tuple(pts[-1]))
    return out


def round_closed(pts, r, n=3):
    """Closed polygon with every corner rounded."""
    m = len(pts)
    out = []
    for i in range(m):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % m])
        d1, d2 = p0 - p1, p2 - p1
        rr = min(r, d1.length * 0.45, d2.length * 0.45)
        a, b = p1 + d1.normalized() * rr, p1 + d2.normalized() * rr
        for k in range(n + 1):
            t = k / n
            q = (1 - t) ** 2 * a + 2 * t * (1 - t) * p1 + t * t * b
            out.append((q.x, q.y))
    return out


def new_obj(name, bm, mats):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def box(bm, c, sx, sy, sz, mi=0):
    """Axis-aligned box centred on c with full sizes sx, sy, sz."""
    vs = [bm.verts.new((c[0] + a * sx / 2, c[1] + b * sy / 2, c[2] + d * sz / 2))
          for a in (-1, 1) for b in (-1, 1) for d in (-1, 1)]
    for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        bm.faces.new([vs[i] for i in q]).material_index = mi


def extrude_poly(bm, pts3, d3, mi=0):
    """Prism: planar polygon pts3 swept by vector d3 (closed, caps included)."""
    a = [bm.verts.new(p) for p in pts3]
    b = [bm.verts.new((p[0] + d3[0], p[1] + d3[1], p[2] + d3[2])) for p in pts3]
    n = len(a)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([a[i], a[j], b[j], b[i]]).material_index = mi
    bm.faces.new(a).material_index = mi
    bm.faces.new(b[::-1]).material_index = mi


def ribbon(bm, pts, width_vec, mi=0):
    """Strip along 3D polyline pts, thickened by +- width_vec/2 (a vector in the surface)."""
    h = Vector(width_vec) * 0.5
    left = [bm.verts.new(Vector(p) - h) for p in pts]
    right = [bm.verts.new(Vector(p) + h) for p in pts]
    for i in range(len(pts) - 1):
        bm.faces.new([left[i], left[i + 1], right[i + 1], right[i]]).material_index = mi


def revolve(bm, prof, seg, cy, cz, mi=0, xs=1.0):
    """Surface of revolution about an X-parallel axis through (cy, cz). prof = [(x, r)]; walk it so dx > 0
    puts the normal radially outward and dr < 0 puts it toward +X. xs = -1 mirrors to the right-hand side."""
    rings = []
    for x, r in prof:
        if r < 1e-6:
            rings.append([bm.verts.new((x * xs, cy, cz))])
        else:
            rings.append([bm.verts.new((x * xs, cy + r * math.cos(2 * math.pi * k / seg),
                                        cz + r * math.sin(2 * math.pi * k / seg))) for k in range(seg)])
    for i in range(len(prof) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(seg):
            k1 = (k + 1) % seg
            if len(a) == 1:
                f = [a[0], b[k1], b[k]]
            elif len(b) == 1:
                f = [a[k], a[k1], b[0]]
            else:
                f = [a[k], a[k1], b[k1], b[k]]
            if xs < 0:
                f = f[::-1]
            try:
                bm.faces.new(f).material_index = mi
            except ValueError:
                pass


# ------------------------------------------------------------------ materials
def principled(name, base_srgb, metallic=0.0, rough=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(base_srgb)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    return m, b


def make_mats(v):
    mats = {}
    m, b = principled("M_Paint", v["paint"], 0.05, 0.3)
    b.inputs["Coat Weight"].default_value = 1.0
    b.inputs["Coat Roughness"].default_value = 0.05
    mats["M_Paint"] = m
    if v["glass"] == "M_Glass":  # smoked, the engine replaces it with its own tinted glass
        m, b = principled("M_Glass", (0x0A, 0x0E, 0x12), 0.0, 0.04)
        b.inputs["Alpha"].default_value = 0.78
    else:
        m, b = principled("M_GlassClear", (0x5A, 0x72, 0x7C), 0.0, 0.03)
        b.inputs["Alpha"].default_value = 0.30
    m.surface_render_method = "BLENDED"
    mats["GLASS"] = m
    mats["M_Trim"] = principled("M_Trim", (0x10, 0x10, 0x11), 0.0, 0.55)[0]
    mats["M_Chrome"] = principled("M_Chrome", (0xD8, 0xDB, 0xDF), 1.0, 0.12)[0]
    m, b = principled("M_LightFront", (0xE8, 0xEE, 0xF4), 0.0, 0.15)
    b.inputs["Emission Color"].default_value = lin((0xF0, 0xF4, 0xFF))
    b.inputs["Emission Strength"].default_value = 0.25
    mats["M_LightFront"] = m
    m, b = principled("M_Indicator", (0xFF, 0x9A, 0x10), 0.0, 0.2)
    b.inputs["Emission Color"].default_value = lin((0xFF, 0x8A, 0x00))
    b.inputs["Emission Strength"].default_value = 0.3
    mats["M_Indicator"] = m
    m, b = principled("M_LightRear", (0xFF, 0x1A, 0x1A), 0.0, 0.2)
    b.inputs["Emission Color"].default_value = lin((0xFF, 0x1A, 0x1A))
    b.inputs["Emission Strength"].default_value = 0.6
    mats["M_LightRear"] = m
    m, b = principled("M_Reverse", (0xF0, 0xF0, 0xF0), 0.0, 0.2)
    mats["M_Reverse"] = m
    mats["M_Rim"] = principled("M_Rim", (0x50, 0x55, 0x5E) if v["kind"] == "star" else (0x8C, 0x91, 0x96), 1.0, 0.3)[0]
    mats["M_Tire"] = principled("M_Tire", (0x16, 0x16, 0x17), 0.0, 0.85)[0]
    mats["M_BrakeDisc"] = principled("M_BrakeDisc", (0x70, 0x74, 0x7A), 1.0, 0.45)[0]
    mats["M_Caliper"] = principled("M_Caliper", tuple(int(c * 255) for c in v["caliper"]), 0.0, 0.4)[0]
    mats["M_Interior"] = principled("M_Interior", (0x23, 0x24, 0x28), 0.0, 0.8)[0]
    mats["M_Plate"] = principled("M_Plate", (0xE8, 0xE8, 0xE2), 0.0, 0.5)[0]
    m, b = principled("M_TaxiSign", (0xFF, 0xF2, 0xC0), 0.0, 0.3)
    b.inputs["Emission Color"].default_value = lin((0xFF, 0xE9, 0x9A))
    b.inputs["Emission Strength"].default_value = 3.0
    mats["M_TaxiSign"] = m
    mats["M_Floor"] = principled("M_Floor", (0x14, 0x15, 0x1A), 0.0, 0.3)[0]
    return mats


# ------------------------------------------------------------------ body shell
def lower_profile(w, zb, zt):
    ctl = [(0.0, zb), (w - 0.08, zb), (w, ZC + V["dz"]), (w - 0.085, zt), (0.0, zt)]
    return round_poly(ctl, [0, 0.09, 0, 0.07, 0], 5)


def full_ring(half, y):
    right = [(x, y, z) for x, z in half]
    left = [(-x, y, z) for x, z in reversed(half[1:-1])]
    return right + left


def loft(bm, rings, mi=0):
    vs = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(vs[0])
    for a, b in zip(vs, vs[1:]):
        for k in range(n):
            k1 = (k + 1) % n
            bm.faces.new([a[k], a[k1], b[k1], b[k]]).material_index = mi
    bm.faces.new(vs[0][::-1]).material_index = mi
    bm.faces.new(vs[-1]).material_index = mi


ZT_T = [(-2.00, 0.80), (-1.50, 0.84), (-0.85, 0.88), (2.20, 0.88)]
ZB_T = [(-2.00, 0.17), (-1.75, 0.17), (-1.45, 0.17), (1.50, 0.17), (1.95, 0.17), (2.20, 0.17)]
END_D = [0.0, 0.006, 0.016, 0.03, 0.05, 0.075, 0.105, 0.14]
MID_Y = ([-1.75] + [-1.65 + 0.075 * i for i in range(14)] + [-0.55, -0.30, 0.30, 0.55]
         + [0.80 + 0.075 * i for i in range(13)] + [1.80, 1.90])


def lower_body():
    dz = V["dz"]
    ys = [Y_NOSE + d for d in END_D] + MID_Y + [Y_TAIL - d for d in reversed(END_D)]
    ys = sorted(set(ys))
    rings = []
    for y in ys:
        d = min(y - Y_NOSE, Y_TAIL - y)
        w = HALF_W - corner_off(d, 0.14)
        zt = tbl(ZT_T, y) + dz - corner_off(d, 0.075)
        zb = tbl(ZB_T, y) + dz + 0.0 + corner_off(d, 0.05)
        # front valance and tail apron lift off the ground
        zb += 0.07 * max(0.0, (y + 1.75) / -0.25) if y < -1.75 else 0.0
        zb += 0.07 * max(0.0, (y - 1.95) / 0.25) if y > 1.95 else 0.0
        rings.append(full_ring(lower_profile(w, zb, zt), y))
    bm = bmesh.new()
    loft(bm, rings)
    return new_obj("body_lower", bm, [MATS["M_Paint"]])


def lb_side_x(y, z):
    """X of the lower body side at height z (right side), crease included. Valid away from the ends."""
    zt, zb = tbl(ZT_T, y) + V["dz"], 0.17 + V["dz"]
    zc = ZC + V["dz"]
    w = HALF_W
    if z <= zc:
        return (w - 0.08) + 0.08 * (z - zb) / (zc - zb)
    return w - 0.085 * (z - zc) / (zt - zc)


# cabin: sides are planes, x(z) = 0.718 - 0.10 (z - dz - 0.70)
def xs_side(z):
    return 0.718 - 0.10 * (z - V["dz"] - 0.70)


def f_front(y):
    return ROOF_Z + V["dz"] + SLOPE_F * (y - Y_ROOF0)


def f_rear(y):
    return ROOF_Z + V["dz"] - SLOPE_R * (y - Y_ROOF1)


def cabin():
    dz = V["dz"]
    zbase = 0.70 + dz
    poly = [(-1.00, f_front(-1.00)), (Y_ROOF0, ROOF_Z + dz), (Y_ROOF1, ROOF_Z + dz), (1.50, f_rear(1.50))]
    prof = round_poly(poly, [0, 0.07, 0.07, 0], 5)
    rings = []
    for y, zr in prof:
        xb, xr = xs_side(zbase), xs_side(zr)
        half = round_poly([(0.0, zbase), (xb, zbase), (xr, zr), (0.0, zr)], [0, 0, 0.05, 0], 4)
        rings.append(full_ring(half, y))
    bm = bmesh.new()
    loft(bm, rings)
    return new_obj("cabin", bm, [MATS["M_Paint"]])


def window_polys():
    """Glass outlines as 3D loops on the cabin surface, one list per window, plus the prisms' directions."""
    dz = V["dz"]
    zz = lambda z: z + dz  # noqa: E731
    yA = lambda z: Y_ROOF0 + (z - dz - ROOF_Z) / SLOPE_F  # noqa: E731  A-pillar edge
    sides = [
        [(yA(zz(0.985)) + 0.075, zz(0.985)), (0.01, zz(0.985)), (0.01, zz(1.335)), (yA(zz(1.335)) + 0.075, zz(1.335))],
        [(0.20, zz(0.985)), (0.80, zz(0.985)), (0.70, zz(1.335)), (0.20, zz(1.335))],
    ]
    out = []
    for poly in sides:
        poly = round_closed(poly, 0.03, 3)
        out.append(("side", poly))
    # windscreen on plane z = f_front(y): (x, y) outline
    yb, yt = -0.78, -0.17
    wx = lambda y, f: xs_side(f(y)) - 0.075  # noqa: E731
    ws = round_closed([(-wx(yb, f_front), yb), (wx(yb, f_front), yb), (wx(yt, f_front), yt), (-wx(yt, f_front), yt)], 0.03, 3)
    out.append(("front", ws))
    yb2, yt2 = 1.30, 1.04
    rs = round_closed([(-(xs_side(f_rear(yb2)) - 0.10), yb2), ((xs_side(f_rear(yb2)) - 0.10), yb2),
                       ((xs_side(f_rear(yt2)) - 0.10), yt2), (-(xs_side(f_rear(yt2)) - 0.10), yt2)], 0.03, 3)
    out.append(("rear", rs))
    return out


def window_geometry():
    """Returns (cutter bm, glass bm). Cutters are prisms through the cabin skin, glass is recessed 12 mm."""
    cut, gl = bmesh.new(), bmesh.new()
    for kind, poly in window_polys():
        for sx in ((1, -1) if kind == "side" else (1,)):
            if kind == "side":
                def P(y, z, off, sx=sx):
                    return (sx * (xs_side(z) + off), y, z)
                outer = [P(y, z, 0.05) for y, z in poly]
                inner = [P(y, z, -0.40) for y, z in poly]
                glass = [P(y, z, -0.012) for y, z in poly]
                if sx < 0:
                    outer, inner, glass = outer[::-1], inner[::-1], glass[::-1]
            else:
                f, sl = (f_front, SLOPE_F) if kind == "front" else (f_rear, -SLOPE_R)
                n = Vector((0.0, -sl, 1.0)).normalized()
                depth = 0.30 if kind == "front" else 0.26
                base = [(x, y, f(y)) for x, y in poly]
                outer = [tuple(Vector(p) + n * 0.05) for p in base]
                inner = [tuple(Vector(p) - n * depth) for p in base]
                glass = [tuple(Vector(p) - n * 0.012) for p in base]
            extrude_poly_between(cut, outer, inner, MATS["M_Interior"])
            vs = [gl.verts.new(p) for p in glass]
            gl.faces.new(vs).material_index = 0
    return cut, gl


def extrude_poly_between(bm, outer, inner, mat):
    a = [bm.verts.new(p) for p in outer]
    b = [bm.verts.new(p) for p in inner]
    n = len(a)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([a[i], a[j], b[j], b[i]])
    bm.faces.new(a)
    bm.faces.new(b[::-1])


# ------------------------------------------------------------------ modifiers
def select_only(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def apply_mod(ob, mod):
    select_only(ob)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def boolean_diff(ob, cutter, mat_transfer=True):
    m = ob.modifiers.new("cut", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.operand_type = "OBJECT"
    m.object = cutter
    m.solver = "EXACT"
    if mat_transfer:
        try:
            m.material_mode = "TRANSFER"
        except (AttributeError, TypeError) as ex:
            print("material_mode unavailable:", ex)
    apply_mod(ob, m)


def bevel(ob, width, seg=2, angle=30.0):
    m = ob.modifiers.new("bev", "BEVEL")
    m.width = width
    m.segments = seg
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    apply_mod(ob, m)


def smooth(ob, angle=22.0):
    select_only(ob)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def join(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    ob.data.name = name
    return ob


def tri_count(ob):
    me = ob.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


# ------------------------------------------------------------------ wheels
def wheel_bm(side):
    """Canonical left wheel (outboard +X, origin at the centre), mirrored by `side`. Slots: tyre, rim, chrome, trim."""
    R, hw, rr = V["R"], V["tw"] / 2, V["rim_r"]
    xs = 1.0 if side > 0 else -1.0
    bm = bmesh.new()
    seg = 48
    sh = R - rr
    # tyre loop: inner bead -> inner shoulder -> tread (two grooves) -> outer shoulder -> outer bead
    inner = [(-(hw - 0.012), rr + 0.006), (-(hw - 0.003), rr + 0.22 * sh), (-hw, rr + 0.55 * sh), (-(hw - 0.003), R - 0.30 * sh),
             (-(hw - 0.022), R - 0.07 * sh), (-(hw - 0.050), R - 0.012)]
    tread = [(-0.04 * V["tw"] / 0.165, R), (-0.03, R - 0.004), (-0.022, R - 0.004), (-0.014, R), (0.014, R), (0.022, R - 0.004),
             (0.03, R - 0.004), (0.04 * V["tw"] / 0.165, R)]
    outer = [(-x, r) for x, r in reversed(inner)]
    revolve(bm, inner + [(inner[-1][0] + 0.012, R)] + tread + [(outer[0][0] - 0.012, R)] + outer, seg, 0.0, 0.0, 0, xs)
    # barrel (dark, seen through the spokes and past the dish)
    revolve(bm, [(hw - 0.015, rr - 0.004), (-(hw - 0.015), rr - 0.004)], seg, 0.0, 0.0, 3, xs)
    xf = hw - 0.012  # outer rim lip plane
    if V["kind"] == "steel":
        lip = [(xf, rr + 0.004), (xf + 0.003, rr - 0.006), (xf - 0.004, rr - 0.016)]
        dish = [(xf - 0.040, rr - 0.030), (xf - 0.043, 0.115), (xf - 0.030, 0.105), (xf - 0.030, 0.0)]
        revolve(bm, lip + dish, seg, 0.0, 0.0, 1, xs)
        # pressed ribs: five short raised bars on the dish
        for q in range(5):
            th = 2 * math.pi * q / 5
            cy, cz = 0.135 * math.cos(th), 0.135 * math.sin(th)
            hu, hv = 0.032, 0.008
            uy, uz = math.cos(th), math.sin(th)
            ty, tz = -uz, uy
            vs = []
            for dx in (xf - 0.044, xf - 0.036):
                for a in (-hu, hu):
                    for b in (-hv, hv):
                        vs.append(bm.verts.new((dx * xs, cy + a * uy + b * ty, cz + a * uz + b * tz)))
            for fq in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
                f = [vs[i] for i in fq]
                bm.faces.new(f if xs > 0 else f[::-1]).material_index = 1
        # chrome hubcap: ring + dome
        cap = [(xf - 0.022, 0.118), (xf - 0.012, 0.112), (xf - 0.004, 0.092), (xf + 0.004, 0.066), (xf + 0.010, 0.030), (xf + 0.012, 0.0)]
        revolve(bm, cap, 28, 0.0, 0.0, 2, xs)
        # lug nuts
        for q in range(4):
            th = 2 * math.pi * q / 4 + math.pi / 4
            revolve(bm, [(xf - 0.026, 0.0), (xf - 0.019, 0.016), (xf - 0.016, 0.0)], 6, 0.0 + 0.052 * math.cos(th),
                    0.052 * math.sin(th), 2, xs)
    else:
        lip = [(xf + 0.002, rr + 0.004), (xf + 0.004, rr - 0.010), (xf - 0.010, rr - 0.012)]
        revolve(bm, lip + [(xf - 0.030, rr - 0.024), (xf - 0.034, rr - 0.040)], seg, 0.0, 0.0, 1, xs)
        # five tapered concave spokes
        hub_r, tip_r = 0.050, rr - 0.030
        for q in range(5):
            th0 = 2 * math.pi * q / 5 + 0.2
            ns = 9
            rows = []
            for i in range(ns + 1):
                t = i / ns
                r = hub_r + (tip_r - hub_r) * t
                half_w = 0.034 - 0.006 * t + 0.008 * math.sin(math.pi * t)  # half width in metres
                x_face = xf - 0.052 + 0.040 * t ** 1.6  # concave: hub deep, tip at the lip
                ang = th0
                uy, uz = math.cos(ang), math.sin(ang)
                ty, tz = -uz, uy
                c = (r * uy, r * uz)
                row = []
                for xx, b in ((x_face, -half_w), (x_face, half_w), (x_face - 0.022, half_w * 0.8), (x_face - 0.022, -half_w * 0.8)):
                    row.append(bm.verts.new((xx * xs, c[0] + b * ty, c[1] + b * tz)))
                rows.append(row)
            for i in range(ns):
                a, b = rows[i], rows[i + 1]
                for k in range(4):
                    k1 = (k + 1) % 4
                    f = [a[k], a[k1], b[k1], b[k]]
                    bm.faces.new(f if xs > 0 else f[::-1]).material_index = 1
            for row, rev in ((rows[0], False), (rows[-1], True)):
                f = row[::-1] if rev else row
                bm.faces.new(f if xs > 0 else f[::-1]).material_index = 1
        # hub and centre cap
        revolve(bm, [(xf - 0.050, 0.075), (xf - 0.040, 0.062), (xf - 0.030, 0.045), (xf - 0.028, 0.0)], 20, 0.0, 0.0, 1, xs)
        revolve(bm, [(xf - 0.030, 0.034), (xf - 0.024, 0.030), (xf - 0.020, 0.0)], 16, 0.0, 0.0, 2, xs)
    return bm


def brake_bm(side):
    xs = 1.0 if side > 0 else -1.0
    rd = V["brake_r"]
    bm = bmesh.new()
    x0 = -0.020
    # disc: closed ring profile traversed so normals point out
    revolve(bm, [(x0 - 0.008, 0.045), (x0 - 0.008, rd), (x0 + 0.008, rd), (x0 + 0.008, 0.045)], 36, 0.0, 0.0, 0, xs)
    revolve(bm, [(x0 + 0.008, 0.045), (x0 + 0.008, rd)], 36, 0.0, 0.0, 0, xs)  # face toward +X (dr > 0 gives -X, so add reversed below)
    # caliper: a block hugging the disc at the top rear
    th = math.radians(115)
    cy, cz = (rd - 0.035) * math.cos(th), (rd - 0.035) * math.sin(th)
    box_x = [(x0 - 0.030) * xs, (x0 + 0.030) * xs]
    hu, hv = 0.034, 0.024
    uy, uz = math.cos(th), math.sin(th)
    ty, tz = -uz, uy
    vs = []
    for dx in box_x:
        for a in (-hu, hu):
            for b in (-hv, hv):
                vs.append(bm.verts.new((dx, cy + a * uy + b * ty, cz + a * uz + b * tz)))
    for fq in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        bm.faces.new([vs[i] for i in fq]).material_index = 1
    return bm


def build_wheels():
    ws, bs = [], []
    for side, sname in ((1, "L"), (-1, "R")):
        for tag in ("F", "R"):
            name = "%s%s" % (tag, sname)
            cx, cy, cz = side * V["wx"], AXLE[tag], V["R"]
            w = new_obj("wheel_" + name, wheel_bm(side), [MATS["M_Tire"], MATS["M_Rim"], MATS["M_Chrome"], MATS["M_Trim"]])
            w.location = (cx, cy, cz)
            b = new_obj("brake_" + name, brake_bm(side), [MATS["M_BrakeDisc"], MATS["M_Caliper"]])
            b.location = (cx, cy, cz)
            for ob in (w, b):
                select_only(ob)
                bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
                for m in list(ob.modifiers):
                    bpy.ops.object.modifier_apply(modifier=m.name)
            ws.append(w)
            bs.append(b)
    return ws, bs


# ------------------------------------------------------------------ the full car
def arch_cutter():
    bm = bmesh.new()
    ra = V["R"] + V["arch_gap"]
    for tag in ("F", "R"):
        for xs in (1.0, -1.0):
            revolve(bm, [(0.50, 0.0), (0.50, ra), (1.00, ra), (1.00, 0.0)], 56, AXLE[tag], V["R"], 0, xs)
    return new_obj("arch_cut", bm, [MATS["M_Trim"]])


def flares():
    """Bolt-on arch flares (modified only): rounded rectangle section swept round the arch."""
    bm = bmesh.new()
    ra = V["R"] + V["arch_gap"]
    sec = round_closed([(0.785, ra - 0.004), (0.885, ra - 0.004), (0.885, ra + 0.040), (0.785, ra + 0.040)], 0.014, 2)
    for tag in ("F", "R"):
        for sx in (1.0, -1.0):
            rows = []
            n = 30
            for i in range(n + 1):
                th = math.radians(4 + 172 * i / n)
                row = []
                for a, b in sec:
                    row.append(bm.verts.new((sx * a, AXLE[tag] + b * math.cos(th), V["R"] + b * math.sin(th))))
                rows.append(row)
            m = len(sec)
            for r0, r1 in zip(rows, rows[1:]):
                for k in range(m):
                    k1 = (k + 1) % m
                    bm.faces.new([r0[k], r0[k1], r1[k1], r1[k]])
            bm.faces.new(rows[0][::-1])
            bm.faces.new(rows[-1])
    return new_obj("flares", bm, [MATS["M_Paint"]])


def sweep_strip(bm, path, z0, z1, th, mi=0):
    """Vertical-faced bar along plan polyline path (x, y), height z0..z1, thickness th (outer = +normal side)."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    nrm = []
    for i in range(n):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, n - 1)]
        d = (b - a).normalized()
        nrm.append(Vector((d.y, -d.x)))  # left normal
    lo, hi, lo_i, hi_i = [], [], [], []
    for p, nn in zip(pts, nrm):
        lo.append(bm.verts.new((p.x + nn.x * th / 2, p.y + nn.y * th / 2, z0)))
        hi.append(bm.verts.new((p.x + nn.x * th / 2, p.y + nn.y * th / 2, z1)))
        lo_i.append(bm.verts.new((p.x - nn.x * th / 2, p.y - nn.y * th / 2, z0)))
        hi_i.append(bm.verts.new((p.x - nn.x * th / 2, p.y - nn.y * th / 2, z1)))
    for i in range(n - 1):
        for loop in ((lo, hi), (lo_i, hi_i)):
            bm.faces.new([loop[0][i], loop[0][i + 1], loop[1][i + 1], loop[1][i]]).material_index = mi
        bm.faces.new([hi[i], hi[i + 1], hi_i[i + 1], hi_i[i]]).material_index = mi
        bm.faces.new([lo[i], lo_i[i], lo_i[i + 1], lo[i + 1]]).material_index = mi
    for e in (0, n - 1):
        bm.faces.new([lo[e], hi[e], hi_i[e], lo_i[e]]).material_index = mi


def bumper_path(y_edge, sgn):
    """Plan path of a wrap-around bumper bar, front (sgn -1) or rear (sgn +1)."""
    yc = y_edge - sgn * 0.0  # centre line of the bar
    pts = [(-0.700, sgn * 1.80), (-0.690, sgn * 1.93), (-0.610, yc), (0.610, yc), (0.690, sgn * 1.93), (0.700, sgn * 1.80)]
    if sgn > 0:
        pts = [(-0.700, 1.96), (-0.690, 2.09), (-0.610, yc), (0.610, yc), (0.690, 2.09), (0.700, 1.96)]
    return round_poly(pts, [0, 0.10, 0.12, 0.12, 0.10, 0], 4)


def trim_parts():
    """Everything small: returns dict of objects name -> object (trim, lights_front, lights_rear, plate_rear, ...)."""
    dz = V["dz"]
    black = V["black_trim"]
    bm_trim = bmesh.new()  # slots: 0 M_Trim, 1 M_Chrome, 2 M_Paint, 3 M_Interior
    TR = [MATS["M_Trim"], MATS["M_Chrome"], MATS["M_Paint"], MATS["M_Interior"]]
    bmp = 0 if black else 1  # bumper bar slot
    ytop_n = lambda z: z  # noqa: E731
    # bumpers
    sweep_strip(bm_trim, bumper_path(-2.025, -1), 0.20 + dz, 0.335 + dz, 0.05, bmp)
    sweep_strip(bm_trim, bumper_path(2.225, 1), 0.20 + dz, 0.335 + dz, 0.05, bmp)
    # front: grille band, slats, frame, lower slot
    yn = Y_NOSE - 0.002
    box(bm_trim, (0, yn - 0.006, 0.58 + dz), 0.74, 0.012, 0.17, 0)  # grille band
    box(bm_trim, (0, yn - 0.012, 0.664 + dz), 0.76, 0.012, 0.012, 1)  # frame top
    box(bm_trim, (0, yn - 0.012, 0.496 + dz), 0.76, 0.012, 0.012, 1)  # frame bottom
    for sx in (-1, 1):
        box(bm_trim, (sx * 0.376, yn - 0.012, 0.58 + dz), 0.012, 0.012, 0.18, 1)
    for i in range(8):
        box(bm_trim, (-0.30 + i * 0.6 / 7, yn - 0.014, 0.58 + dz), 0.014, 0.012, 0.15, 1)  # eight vertical slats
    box(bm_trim, (0, yn - 0.006, 0.40 + dz), 0.60, 0.012, 0.06, 0)  # lower intake slot
    box(bm_trim, (0, yn - 0.010, 0.455 + dz), 0.20, 0.010, 0.014, 1)  # BOSFOR bar
    # lamp bezels (chrome stock, black modified)
    for sx in (1, -1):
        box(bm_trim, (sx * 0.535, yn - 0.003, 0.585 + dz), 0.34, 0.008, 0.185, bmp)
    # rear: garnish bar, plate frame, lock
    yt = Y_TAIL + 0.002
    box(bm_trim, (0, yt + 0.006, 0.665 + dz), 0.62, 0.012, 0.022, 1)
    box(bm_trim, (0, yt + 0.006, 0.40 + dz), 0.60, 0.012, 0.15, 0)  # plate recess frame
    box(bm_trim, (0.0, yt + 0.012, 0.54 + dz), 0.05, 0.012, 0.025, 1)  # boot lock
    # door handles and belt chrome
    for y in (-0.40, 0.50):
        for sx in (1, -1):
            box(bm_trim, (sx * (lb_side_x(y, 0.80 + dz) + 0.010), y, 0.80 + dz), 0.024, 0.14, 0.030, 0 if black else 1)
    # B pillar and sail louvres and belt chrome, mirrors
    for sx in (1, -1):
        for y0, y1 in ((0.01, 0.20),):
            z0, z1 = 0.985 + dz, 1.335 + dz
            pts = [(sx * (xs_side(z0) + 0.003), (y0 + y1) / 2, z0), (sx * (xs_side(z1) + 0.003), (y0 + y1) / 2, z1)]
            ribbon(bm_trim, pts, (0, y1 - y0, 0), 0)
        for z in (1.03, 1.065, 1.10):
            zz = z + dz
            y1 = 0.99 - (zz - dz - 1.03) * 0.8
            pts = [(sx * (xs_side(zz) + 0.003), 0.88 + (z - 1.03) * 0.3, zz), (sx * (xs_side(zz) + 0.003), y1 + 0.10, zz)]
            ribbon(bm_trim, pts, (0, 0, 0.014), 0)
        # belt strip
        zb = 0.972 + dz
        yA = Y_ROOF0 + (zb - dz - ROOF_Z) / SLOPE_F
        ribbon(bm_trim, [(sx * (xs_side(zb) + 0.003), yA + 0.02, zb), (sx * (xs_side(zb) + 0.003), 1.25, zb)], (0, 0, 0.012),
               0 if black else 1)
        # mirror
        box(bm_trim, (sx * 0.735, -0.60, 0.985 + dz), 0.10, 0.03, 0.03, 0)  # stalk
        box(bm_trim, (sx * 0.785, -0.60, 1.02 + dz), 0.075, 0.08, 0.10, 0)  # head
    # door seams, lower body, right and left
    for sx in (1, -1):
        for y in (-0.78, 0.09, 0.84):
            zlo = 0.66 + dz if y > 0.80 else 0.26 + dz
            zs = [zlo, ZC + dz, tbl(ZT_T, y) + dz - 0.01]
            pts = [(sx * (lb_side_x(y, z) + 0.002), y, z) for z in zs]
            ribbon(bm_trim, pts, (0.007, 0, 0), 0)
    # underside shows nothing here; taxi/mod extras
    if V["flares"]:
        for sx in (1, -1):  # side skirts, front lip
            box(bm_trim, (sx * 0.785, -0.02, 0.150), 0.05, 1.50, 0.08, 0)
        box(bm_trim, (0, -2.010, 0.130), 1.30, 0.08, 0.05, 0)  # front lip, hangs under the bumper bar
    return bm_trim, TR


def build_trim_obj():
    bm, TR = trim_parts()
    ob = new_obj("trim", bm, TR)
    return ob


def lamps_front():
    dz = V["dz"]
    bm = bmesh.new()
    yn = Y_NOSE - 0.004
    for sx in (1, -1):
        # cut-corner lamp: rectangle with the upper inner corner chamfered (its own shape)
        poly = [(0.375, 0.500), (0.695, 0.500), (0.695, 0.660), (0.455, 0.660), (0.375, 0.600)]
        pts = [(sx * x, yn, z + dz) for x, z in poly]
        if sx < 0:
            pts = pts[::-1]
        extrude_poly(bm, pts, (0, -0.014, 0), 0)
        ind = [(0.395, 0.462), (0.695, 0.462), (0.695, 0.486), (0.395, 0.486)]
        pts = [(sx * x, yn, z + dz) for x, z in ind]
        if sx < 0:
            pts = pts[::-1]
        extrude_poly(bm, pts, (0, -0.012, 0), 1)
    return new_obj("lights_front", bm, [MATS["M_LightFront"], MATS["M_Indicator"]])


def lamps_rear_plate():
    dz = V["dz"]
    bm = bmesh.new()
    yt = Y_TAIL + 0.004
    for sx in (1, -1):
        bars = [(0.30, 0.66, 0.700, 0.800, 0), (0.30, 0.66, 0.655, 0.695, 1), (0.30, 0.52, 0.610, 0.650, 2)]
        for x0, x1, z0, z1, mi in bars:
            poly = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
            pts = [(sx * x, yt, z + dz) for x, z in poly]
            if sx > 0:
                pts = pts[::-1]
            extrude_poly(bm, pts, (0, 0.014, 0), mi)
    lr = new_obj("lights_rear", bm, [MATS["M_LightRear"], MATS["M_Indicator"], MATS["M_Reverse"]])
    pm = bmesh.new()
    box(pm, (0, Y_TAIL + 0.016, 0.40 + dz), 0.46, 0.008, 0.105, 0)
    plate = new_obj("plate_rear", pm, [MATS["M_Plate"], MATS["M_Trim"]])
    return lr, plate


def text_mesh(body, loc, rot, size, mat, name, extrude=0.003):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.object.text_add(location=loc, rotation=rot)
    ob = bpy.context.active_object
    ob.data.body = body
    ob.data.size = size
    ob.data.extrude = extrude
    ob.data.align_x = "CENTER"
    ob.data.align_y = "CENTER"
    ob.data.resolution_u = 2
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.active_object
    ob.name = name
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return ob


def interior_obj():
    dz = V["dz"]
    bm = bmesh.new()
    for sx in (-1, 1):
        box(bm, (sx * 0.30, -0.02, 1.10 + dz), 0.46, 0.13, 0.38, 0)  # front seat back
        box(bm, (sx * 0.30, -0.02, 1.31 + dz), 0.20, 0.10, 0.13, 0)  # headrest
    box(bm, (0.0, 1.02, 1.10 + dz), 1.10, 0.12, 0.30, 0)  # rear seat back
    box(bm, (0.0, 0.95, 0.99 + dz), 1.10, 0.12, 0.06, 1)  # rear shelf side
    box(bm, (0.0, -0.64, 0.96 + dz), 1.20, 0.26, 0.10, 1)  # dash top
    box(bm, (-0.30, -0.50, 0.90 + dz), 0.18, 0.30, 0.10, 1)  # instrument hood
    ob = new_obj("interior", bm, [MATS["M_Interior"], MATS["M_Trim"]])
    bevel(ob, 0.02, 2, 40)
    sw = text_mesh("O", (-0.30, -0.46, 1.01 + dz), (math.radians(60), 0, 0), 0.34, MATS["M_Trim"], "swheel", 0.02)
    return ob, sw


def underbody_obj():
    dz = V["dz"]
    bm = bmesh.new()
    box(bm, (0, 0.10, 0.165 + dz), 1.10, 3.30, 0.02, 0)
    # exhaust: muffler and tail pipe
    ob = new_obj("underbody", bm, [MATS["M_Trim"]])
    em = bmesh.new()
    # muffler box and tailpipe drawn as boxes (hidden mostly)
    box(em, (0.30, 1.55, 0.21 + dz), 0.20, 0.70, 0.12, 0)
    box(em, (0.30, 2.14, 0.20 + dz), 0.06, 0.16, 0.06, 0)
    ex = new_obj("exh_tmp", em, [MATS["M_Chrome"]])
    return ob, ex


def col_obj():
    bm = bmesh.new()
    box(bm, (0, 0.10, 0.80), 1.64, 4.20, 1.26, 0)
    ob = new_obj("col_body", bm, [MATS["M_Trim"]])
    ob["collision_only"] = 1
    return ob


def taxi_parts():
    bm = bmesh.new()
    z0 = ROOF_Z + V["dz"] - 0.01
    yc = 0.42
    hl = 0.30  # half length along x
    prof = [(-0.085, 0.0), (0.085, 0.0), (0.105, 0.04), (0.085, 0.115), (-0.085, 0.115), (-0.105, 0.04)]  # (y, z) hexagon
    # pointed hexagonal prism along x (its own pillow shape): ends taper
    def ring(xx, k):
        return [bm.verts.new((xx, yc + y * k, z0 + z * k)) for y, z in prof]
    ra, rb, rc, rd = ring(-hl, 0.55), ring(-hl + 0.07, 1.0), ring(hl - 0.07, 1.0), ring(hl, 0.55)
    ringsx = [ra, rb, rc, rd]
    n = len(prof)
    for r0, r1 in zip(ringsx, ringsx[1:]):
        for k in range(n):
            k1 = (k + 1) % n
            bm.faces.new([r0[k], r0[k1], r1[k1], r1[k]])
    bm.faces.new(ra[::-1])
    bm.faces.new(rd)
    sign = new_obj("taxi_sign", bm, [MATS["M_TaxiSign"]])
    smooth(sign, 35)
    txts = []
    for sgn, rz in ((-1, 0.0), (1, math.pi)):
        t = text_mesh("TAKSİ", (0.0, yc + sgn * 0.1065, z0 + 0.058), (math.radians(90), 0, rz), 0.07, MATS["M_Trim"],
                      "taxi_txt%d" % sgn, 0.004)
        txts.append(t)
    # band and sawtooth on both sides (original style), M_Trim
    bb = bmesh.new()
    dz = V["dz"]
    for sx in (1, -1):
        ys = [-1.80 + i * 0.1 for i in range(0, 39)]
        z_lo, z_hi = 0.675 + dz, 0.725 + dz
        # continuous band as a ribbon along y at mid height (needs width in z)
        zm = 0.70 + dz
        pts = [(sx * (lb_side_x(y, zm) + 0.003), y, zm) for y in ys]
        ribbon(bb, pts, (0, 0, 0.05), 0)
        # sawtooth triangles above the band
        zt0, zt1 = 0.725 + dz, 0.775 + dz
        y = -1.80
        while y < 2.00:
            ym = y + 0.04
            a = (sx * (lb_side_x(y, zt0) + 0.003), y, zt0)
            b = (sx * (lb_side_x(y + 0.08, zt0) + 0.003), y + 0.08, zt0)
            c = (sx * (lb_side_x(ym, zt1) + 0.003), ym, zt1)
            va, vb, vc = bb.verts.new(a), bb.verts.new(b), bb.verts.new(c)
            bb.faces.new([va, vb, vc] if sx > 0 else [va, vc, vb])
            y += 0.16
    band = new_obj("taxi_band", bb, [MATS["M_Trim"]])
    return sign, txts, band


def spoiler_obj():
    dz = V["dz"]
    bm = bmesh.new()
    # ducktail: wedge on the boot edge with small end plates
    zt = tbl(ZT_T, 2.0) + dz
    p = [(2.20, zt - 0.005), (2.20, zt + 0.055), (2.06, zt + 0.032), (1.90, zt - 0.005)]
    for sx0, sx1 in ((-0.62, 0.62),):
        verts = [(sx0, y, z) for y, z in p], [(sx1, y, z) for y, z in p]
        a = [bm.verts.new(q) for q in verts[0]]
        b = [bm.verts.new(q) for q in verts[1]]
        n = len(p)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new([a[i], a[j], b[j], b[i]])
        bm.faces.new(a[::-1])
        bm.faces.new(b)
    ob = new_obj("spoiler", bm, [MATS["M_Paint"]])
    bevel(ob, 0.008, 2, 40)
    return ob


def build_variant(name):
    global V, MATS
    V = VARIANTS[name]
    MATS = make_mats(V)
    glass_mat = MATS["GLASS"]
    # --- paint shell
    low = lower_body()
    smooth(low, 22)
    cab = cabin()
    cut_bm, glass_bm = window_geometry()
    cutter = new_obj("win_cut", cut_bm, [MATS["M_Interior"]])
    boolean_diff(cab, cutter)
    bpy.data.objects.remove(cutter, do_unlink=True)
    smooth(cab, 22)
    arch = arch_cutter()
    boolean_diff(low, arch)
    bpy.data.objects.remove(arch, do_unlink=True)
    bevel(low, 0.012, 2, 55)
    smooth(low, 30)
    parts = [low, cab]
    if V["flares"]:
        fl = flares()
        bevel(fl, 0.006, 1, 40)
        smooth(fl, 35)
        parts += [fl, spoiler_obj()]
    for ob in parts[2:]:
        smooth(ob, 35)
    body = join(parts, "body")
    # --- glass
    glass = new_obj("glass", glass_bm, [glass_mat])
    smooth(glass, 60)
    trim = build_trim_obj()
    bevel(trim, 0.004, 1, 40)
    smooth(trim, 35)
    lf = lamps_front()
    lr, plate = lamps_rear_plate()
    # plate text and badge go into the plate / trim meshes
    ptxt = text_mesh("BOSFOR", (0, Y_TAIL + 0.021, 0.40 + V["dz"]), (math.radians(90), 0, math.radians(180)), 0.055,
                     MATS["M_Trim"], "plate_text", 0.002)
    badge = text_mesh("ATMACA", (0, Y_TAIL + 0.012, 0.715 + V["dz"]), (math.radians(90), 0, math.radians(180)), 0.040,
                      MATS["M_Chrome"], "badge_text", 0.003)
    inter, sw = interior_obj()
    under, exh = underbody_obj()
    col = col_obj()
    ws, bs = build_wheels()
    extras_trim = [badge]
    if name == "taxi":
        sign, txts, band = taxi_parts()
        trim = join([trim, sign] + txts + [band] + extras_trim, "trim")
    else:
        trim = join([trim] + extras_trim, "trim")
    plate = join([plate, ptxt], "plate_rear")
    inter = join([inter, sw], "interior")
    under = join([under, exh], "underbody")
    objs = {"body": body, "glass": glass, "trim": trim, "interior": inter, "underbody": under,
            "lights_front": lf, "lights_rear": lr, "plate_rear": plate, "col_body": col}
    for w in ws + bs:
        objs[w.name] = w
    for k, ob in objs.items():
        if ob.name != k:
            ob.name = k
        ob.data.name = k
    for k in ("lights_front", "lights_rear", "plate_rear", "interior", "underbody", "glass"):
        smooth(objs[k], 35)
    return objs


# ------------------------------------------------------------------ LODs and export
BUDGET = {0: 45000, 1: 15000, 2: 5000}


def visible(objs):
    return {k: o for k, o in objs.items() if k != "col_body"}


def total_tris(objs):
    return sum(tri_count(o) for o in objs.values() if o.name != "col_body")


def make_lod(objs, level):
    """Copies of every object under its public name; decimated by one bisected ratio to meet the budget.
    The LOD0 objects are renamed *_src meanwhile."""
    names = list(objs)
    for n in names:
        objs[n].name = n + "__src"
    copies = {}
    for n in names:
        if level == 2 and (n == "interior" or n.startswith("brake_")):
            continue
        src = objs[n]
        c = src.copy()
        c.data = src.data.copy()
        c.name = n
        c.data.name = n
        bpy.context.collection.objects.link(c)
        copies[n] = c
    decs = {}
    for n, c in copies.items():
        if n == "col_body":
            continue
        m = c.modifiers.new("lod", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.use_collapse_triangulate = True
        decs[n] = m
    dg = bpy.context.evaluated_depsgraph_get()

    def evaluated_total():
        t = 0
        for n, c in copies.items():
            if n == "col_body":
                continue
            oe = c.evaluated_get(dg)
            me = oe.to_mesh()
            t += sum(max(len(p.vertices) - 2, 0) for p in me.polygons)
            oe.to_mesh_clear()
        return t

    a, b, best = 0.02, 1.0, 0.02
    for _ in range(12):
        mid = 0.5 * (a + b)
        for m in decs.values():
            m.ratio = mid
        dg = bpy.context.evaluated_depsgraph_get()
        if evaluated_total() <= BUDGET[level]:
            best, a = mid, mid
        else:
            b = mid
    for m in decs.values():
        m.ratio = best
    for n, c in copies.items():
        if n in decs:
            apply_mod(c, decs[n])
    tot = sum(tri_count(c) for n, c in copies.items() if n != "col_body")
    print("LOD%d ratio %.3f tris %d (budget %d)" % (level, best, tot, BUDGET[level]))
    return copies, tot


def drop_lod(copies, objs):
    for c in copies.values():
        me = c.data
        bpy.data.objects.remove(c, do_unlink=True)
        if me.users == 0:
            bpy.data.meshes.remove(me)
    for n, o in objs.items():
        o.name = n


def export_glb(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    first = None
    for o in objs:
        o.select_set(True)
        first = first or o
    bpy.context.view_layer.objects.active = first
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=False, export_tangents=False, export_materials="EXPORT",
                              export_cameras=False, export_lights=False, export_extras=True)
    print("EXPORT", path, os.path.getsize(path))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    name = argv[0] if argv else "stock"
    export = not (len(argv) > 1 and argv[1] == "noexport")
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    objs = build_variant(name)
    for o in list(objs.values()):
        # triangulate-free: keep quads; counts come from loop triangles
        pass
    t0 = total_tris(objs)
    print("LOD0 tris", t0, {k: tri_count(o) for k, o in objs.items()})
    bb = [objs[k] for k in objs if k not in ("col_body",)]
    # overall dimensions from the car objects (wheels included, mirrors are in trim)
    xs, ys, zs = [], [], []
    for o in bb:
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            xs.append(p.x)
            ys.append(p.y)
            zs.append(p.z)
    dims = {"width": round(max(xs) - min(xs), 3), "length": round(max(ys) - min(ys), 3), "height": round(max(zs) - min(zs), 3)}
    print("DIMS", dims)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "atmaca_%s.blend" % name))
    totals = {0: t0}
    if export:
        export_glb(os.path.join(OUT, "atmaca_%s_lod0.glb" % name), list(objs.values()))
        for level in (1, 2):
            copies, tot = make_lod(objs, level)
            totals[level] = tot
            export_glb(os.path.join(OUT, "atmaca_%s_lod%d.glb" % (name, level)), list(copies.values()))
            drop_lod(copies, objs)
    with open(os.path.join(OUT, "summary_%s.json" % name), "w") as fh:
        json.dump({"variant": name, "tris": {"lod%d" % k: v for k, v in totals.items()}, "dims": dims,
                   "blender": bpy.app.version_string}, fh, indent=2)
    print("BUILD_DONE", name, json.dumps(totals))


V = VARIANTS["stock"]
MATS = {}

if __name__ == "__main__":
    main()
