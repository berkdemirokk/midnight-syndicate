"""Kestrel GT-R: 20 inch wheels (tyre + ten turbine spokes, centre-lock nut) and ventilated brakes.

Spec: docs/art/CAR_01_BODY_SURFACE_SPEC.md, "Wheels". Positions: ruling R4 (WHEELS below).
Canonical wheel: outboard face at +X, origin at the wheel centre, spins about local X.
Right-hand wheels are the mirror image (x -> -x) of the canonical build, not a rotation.
Pure bmesh geometry, called from build_car.py inside Blender.
"""
import math

import numpy as np
import bpy
import bmesh
from mathutils import Matrix

# name: (world x of centre, axle y, tyre outer radius R, tyre width W, rim half-width, is_rear)
WHEELS = {
    "wheel_FL": (0.820, -1.375, 0.343, 0.265, 0.125, False),
    "wheel_FR": (-0.820, -1.375, 0.343, 0.265, 0.125, False),
    "wheel_RL": (0.815, 1.375, 0.352, 0.305, 0.140, True),
    "wheel_RR": (-0.815, 1.375, 0.352, 0.305, 0.140, True),
}
SEG = 48            # tyre and rim segments around (spec: 64 for the tyre)
GROOVES = (-0.075, -0.025, 0.025, 0.075)  # four circumferential tread grooves (centres, x)
GROOVE_HW = 0.0045  # 9 mm wide
GROOVE_D = 0.006    # 6 mm deep
SPOKE_PAIRS = 10  # single spokes (SPOKE_OPEN 0), each twisted TWIST rad from hub to barrel
SPOKE_OPEN = 0.0
TWIST = math.radians(14.0)
SPOKE_TABLE = (0.070, 0.252)    # radial extent of a spoke: hub to inside of barrel


def _ang(j, n):
    return 2.0 * math.pi * j / n


# ------------------------------------------------------------------ tyre section (pure maths)
def tyre_profile(R, W, hr):
    """Closed tyre section loop (x, r, region). Outer surface from the +X bead over the tread to
    the -X bead, then the inner loop back. Shared with textures.py for the sidewall V ranges."""
    hw = 0.5 * W
    xb = hr - 0.006          # bead, just inside the rim lip
    rb = 0.266               # bead top, under the rim lip (20 inch rim: seat radius 0.254)
    top = R - 0.028          # sidewall top = start of the shoulder arc
    rs = 0.022               # shoulder radius
    xs = hw - 0.004          # maximum sidewall x
    xc = xs - rs             # shoulder arc centre x

    side = []
    NS = 7
    for i in range(NS):
        t = i / (NS - 1)
        x = xb + (xs - xb) * math.sin(0.5 * math.pi * t) ** 0.7 + 0.004 * math.sin(math.pi * t)
        side.append((x, rb + (top - rb) * t, "side"))
    sh = []
    for a in (22.5, 45.0, 67.5, 90.0):
        ar = math.radians(a)
        sh.append((xc + rs * math.cos(ar), top + rs * math.sin(ar), "shoulder"))
    right = side + sh

    def rt(x):  # tread crown: R at centre, R - 6 mm at the shoulder
        return R - 0.006 * (x / xc) ** 2

    tread = []
    base = np.linspace(xc, -xc, 9)[1:-1]
    for x in base:
        if all(abs(x - g) >= GROOVE_HW for g in GROOVES):
            tread.append((float(x), rt(x), "tread"))
    for g in GROOVES:
        tread.append((g + GROOVE_HW, rt(g + GROOVE_HW), "tread"))
        tread.append((g + GROOVE_HW, rt(g + GROOVE_HW) - GROOVE_D, "tread"))
        tread.append((g - GROOVE_HW, rt(g - GROOVE_HW) - GROOVE_D, "tread"))
        tread.append((g - GROOVE_HW, rt(g - GROOVE_HW), "tread"))
    tread.sort(key=lambda p: -p[0])  # stable: groove wall pairs keep their order

    left = [(-x, r, reg) for (x, r, reg) in reversed(right)]
    outer = right + tread + left
    inner = [(-xb, rb - 0.010, "inner"), (xb, rb - 0.010, "inner")]
    loop = outer + inner
    return [(p[0], p[1]) for p in loop], [p[2] for p in loop]


def tyre_vfrac(pts):
    """Arc-length fraction around the closed tyre loop (V of the tyre texture), one per point."""
    P = np.asarray(pts, float)
    seg = np.hypot(*(np.roll(P, -1, axis=0) - P).T)
    cum = np.concatenate([[0.0], np.cumsum(seg)[:-1]])
    return cum / seg.sum()


# ------------------------------------------------------------------ generic builders
def lathe(bm, prof, n, mi, vf=None, uv_layer=None):
    """Revolve a closed (x, r) loop about the X axis. Ring k has n vertices at angle 2 pi j / n.
    A ring at r = 0 collapses to one vertex (fan). Faces get material index mi.
    If vf (one V per profile point) and uv_layer are given, U = j / n around (last seam at 1.0)."""
    rings = []
    for x, r in prof:
        if r < 1e-9:
            rings.append([bm.verts.new((x, 0.0, 0.0))])
        else:
            rings.append([bm.verts.new((x, r * math.cos(_ang(j, n)), r * math.sin(_ang(j, n))))
                          for j in range(n)])
    info = {}
    for k, rg in enumerate(rings):
        for j, v in enumerate(rg):
            info[v] = (k, j if len(rg) > 1 else None)
    new = []
    K = len(rings)
    for k in range(K):
        A, Bv = rings[k], rings[(k + 1) % K]
        if len(A) == 1 and len(Bv) == 1:
            continue
        if len(A) == 1 or len(Bv) == 1:
            if len(A) == 1:
                c, ring = A[0], Bv
                for j in range(n):
                    new.append(bm.faces.new([c, ring[j], ring[(j + 1) % n]]))
            else:
                c, ring = Bv[0], A
                for j in range(n):
                    new.append(bm.faces.new([ring[j], ring[(j + 1) % n], c]))
            continue
        for j in range(n):
            j1 = (j + 1) % n
            new.append(bm.faces.new([A[j], A[j1], Bv[j1], Bv[j]]))
    for f in new:
        f.material_index = mi
    bmesh.ops.recalc_face_normals(bm, faces=new)
    if uv_layer is not None and vf is not None:
        for f in new:
            js = {info[v][1] for v in f.verts if info[v][1] is not None}
            wrap = (0 in js) and (n - 1 in js)
            for lp in f.loops:
                k, j = info[lp.vert]
                u = 0.5 if j is None else (1.0 if (wrap and j == 0) else j / n)
                lp[uv_layer].uv = (u, float(vf[k]))
    return new


def rect(x0, x1, r0, r1):
    return [(x0, r0), (x0, r1), (x1, r1), (x1, r0)]


def merge_bm(dst, src, mi=None):
    vmap = {v: dst.verts.new(tuple(v.co)) for v in src.verts}
    for f in src.faces:
        nf = dst.faces.new([vmap[v] for v in f.verts])
        nf.material_index = mi if mi is not None else f.material_index


def _blade(th, x0, x1):
    """Tapered concave spoke: 5 stations, closed prism, 2 mm chamfer on every edge."""
    tmp = bmesh.new()
    NS = 5
    r0, r1 = SPOKE_TABLE
    rings = []
    for i in range(NS):
        t = i / (NS - 1)
        r = r0 + (r1 - r0) * t
        x = x0 + (x1 - x0) * t ** 1.6          # concave: hub face inboard, flares to the barrel
        w = 0.034 + (0.020 - 0.034) * t        # 34 mm at the hub, 20 mm at the barrel
        a = th + TWIST * t
        cs, sn = math.cos(a), math.sin(a)
        py, pz = r * cs, r * sn
        ty, tz = -sn, cs
        ring = []
        for sa, sb in ((1, 1), (1, -1), (-1, -1), (-1, 1)):
            ring.append(tmp.verts.new((x + sb * 0.006, py + sa * 0.5 * w * ty, pz + sa * 0.5 * w * tz)))
        rings.append(ring)
    fs = []
    for i in range(NS - 1):
        for k in range(4):
            k1 = (k + 1) % 4
            fs.append(tmp.faces.new([rings[i][k], rings[i][k1], rings[i + 1][k1], rings[i + 1][k]]))
    fs.append(tmp.faces.new(rings[0]))
    fs.append(tmp.faces.new(list(reversed(rings[-1]))))
    bmesh.ops.recalc_face_normals(tmp, faces=fs)
    bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=0.002, segments=1, affect="EDGES")
    return tmp


def _lug(bm, c, axis_x_len, rad, mi):
    """Hex lug nut along X, centre c (x at the nut mid-length)."""
    M = Matrix.Translation(c) @ Matrix.Rotation(math.pi / 2, 4, "Y")
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=6, radius1=rad, radius2=rad,
                          depth=axis_x_len, matrix=M)
    for f in list(bm.faces)[-8:]:
        f.material_index = mi


def _mirror(bm):
    for v in bm.verts:
        v.co.x = -v.co.x
    bmesh.ops.reverse_faces(bm, faces=list(bm.faces))


def _finish(name, bm, mats, loc):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    bpy.context.collection.objects.link(ob)
    return ob


# ------------------------------------------------------------------ wheel
def build_wheel(name, mats):
    x_w, y_ax, R, W, hr, rear = WHEELS[name]
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    pts, _ = tyre_profile(R, W, hr)
    vf = tyre_vfrac(pts)
    lathe(bm, pts, SEG, 0, vf, uv)                        # tyre, slot 0 (M_Tire)

    # rim barrel: 14 mm lips at the 0.25 bead seat, to 0.264
    barrel = [(hr, 0.268), (hr - 0.008, 0.268), (hr - 0.012, 0.254), (-(hr - 0.012), 0.254),
              (-(hr - 0.008), 0.268), (-hr, 0.268), (-hr, 0.249), (hr, 0.249)]
    lathe(bm, barrel, SEG, 1)
    # hub 0.150 diameter with a centre cap and cap ring
    lathe(bm, [(0.020, 0.0), (0.020, 0.070), (0.062, 0.075), (0.096, 0.075), (0.098, 0.068),
               (0.098, 0.0)], 48, 1)
    _lug(bm, (0.110, 0.0, 0.0), 0.024, 0.040, 1)  # centre-lock nut, hex
    lathe(bm, [(0.098, 0.040), (0.098, 0.052), (0.104, 0.052), (0.104, 0.040)], 32, 1)  # nut seat ring

    # ten turbine spokes, concave, from the barrel to the hub face (55 mm inboard, rear 10% deeper)
    x1 = hr - 0.012
    x0 = hr - 0.055 * (1.10 if rear else 1.0)
    for p in range(SPOKE_PAIRS):
        thc = math.pi / 2 + 2 * math.pi * p / SPOKE_PAIRS
        for th in ((thc,) if SPOKE_OPEN == 0.0 else (thc - SPOKE_OPEN, thc + SPOKE_OPEN)):
            merge_bm(bm, _blade(th, x0, x1), 1)

    if name.endswith(("FR", "RR")):
        _mirror(bm)
    else:
        # the mirrored wheels read the tyre texture the right way round from outside; the canonical
        # build runs its U the other way, so flip U on the tyre faces to match
        for f in bm.faces:
            if f.material_index == 0:
                for lp in f.loops:
                    u, v = lp[uv].uv
                    lp[uv].uv = (1.0 - u, v)
    ob = _finish(name, bm, [mats["M_Tire"], mats["M_Rim"]], (x_w, y_ax, R))
    return ob


# ------------------------------------------------------------------ brake
def build_brake(name, mats):
    x_w, y_ax, R, W, hr, rear = WHEELS[name]
    Rd = 0.195 if rear else 0.205  # 0.39 / 0.41 m discs
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    rin = 0.040

    def vf_of(prof):
        return [(r - rin) / (Rd - rin) for _, r in prof]

    parts = [
        rect(-0.015, -0.004, 0.075, Rd),       # inboard plate, 11 mm
        rect(0.004, 0.015, 0.075, Rd),         # outboard plate, 11 mm; 8 mm vent gap between
        rect(-0.015, 0.015, Rd - 0.012, Rd),   # outer band closes the vent at the rim
        rect(-0.015, 0.060, rin, 0.075),       # hat, bolts into the hub boss
    ]
    for prof in parts:
        lathe(bm, prof, 48, 0, vf_of(prof), uv)
    # 36 radial vanes in the vent gap
    rr0, rr1 = 0.080, Rd - 0.013
    for k in range(30):
        a = 2 * math.pi * k / 30
        cy, sy = math.cos(a), math.sin(a)
        L = rr1 - rr0
        rm = 0.5 * (rr0 + rr1)
        cen = (0.0, rm * cy, rm * sy)
        tv = (0.0, -sy, cy)
        rv = (0.0, cy, sy)
        vs = []  # corners: index = (sa, sb, sc) bits, x = +-4 mm (fills the 8 mm gap)
        for sa in (1, -1):
            for sb in (1, -1):
                for sc in (1, -1):
                    vs.append(bm.verts.new((sa * 0.004,
                                            cen[1] + sb * 0.003 * tv[1] + sc * 0.5 * L * rv[1],
                                            cen[2] + sb * 0.003 * tv[2] + sc * 0.5 * L * rv[2])))
        for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            bm.faces.new([vs[i] for i in q]).material_index = 0
    # disc, hat and vanes are all slot 0 (M_BrakeDisc)

    # caliper: rounded block wrapping the trailing-upper edge (angle 45 deg in the y-z plane)
    thc = math.radians(45.0)
    cy, sy = math.cos(thc), math.sin(thc)
    tv = (-sy, cy)
    rv = (cy, sy)
    cr = Rd - 0.025
    sph = bmesh.new()
    bmesh.ops.create_uvsphere(sph, u_segments=16, v_segments=8, radius=1.0)
    for v in sph.verts:
        lx, ly, lz = v.co.x * 0.110, v.co.y * 0.045, v.co.z * 0.035
        v.co = (lz, cr * cy + tv[0] * lx + rv[0] * ly, cr * sy + tv[1] * lx + rv[1] * ly)
    merge_bm(bm, sph, 1)
    sph.free()
    if name.endswith(("FR", "RR")):
        _mirror(bm)
    return _finish(name.replace("wheel_", "brake_"), bm, [mats["M_BrakeDisc"], mats["M_Caliper"]],
                   (x_w, y_ax, R))


def build_all(mats):
    wheels, brakes = [], []
    for name in WHEELS:
        wheels.append(build_wheel(name, mats))
        brakes.append(build_brake(name, mats))
    return wheels, brakes
