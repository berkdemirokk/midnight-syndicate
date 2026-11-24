"""Noctra Sable R, stage 2A: details on the stage-1 body (body.py).

Build and render:
  blender --background --factory-startup --python details.py
Imports body.py for surface, shell, arches, glazing and materials. Every detail is a
patch of the body surface function S(s, v) or S(s, x) (offset along the normal), or a
pocket cut into the body (pocket()), never a free-floating box.
"""
import functools
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import body as B  # noqa: E402

OUT = os.path.join(HERE, "renders_stage2a")
Y0 = B.Y_OFFSET
B._half = functools.lru_cache(maxsize=None)(B._half)  # surface sampling is called many times

WHEEL_SPECS = {  # name: (x, axle y, radius, width); FL is +X (car left = +X, facing -Y)
    "wheel_FL": (0.815, -1.33, 0.335, 0.255),
    "wheel_FR": (-0.815, -1.33, 0.335, 0.255),
    "wheel_RL": (0.800, 1.33, 0.350, 0.315),
    "wheel_RR": (-0.800, 1.33, 0.350, 0.315),
}
XE = B.xs_of(0.06) - 0.010  # outer end of the front light band on the top surface
FLOOR_TAIL = (4.45 + B.TAIL_DS - Y0) - 0.035  # diffuser recess floor (y)
YF = 4.45 + B.TAIL_DS - Y0  # tail fascia plane (y)
YB = YF - 0.008  # lamp surround floor (y)

BITMAP = {
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
}


# ------------------------------------------------------------------ surface sampling
def sv(s, z):
    """Side parameter v (outer side, x > 0.3 w) whose section point is nearest height z."""
    best = (1e9, 0.3)
    for v in np.linspace(0.02, 0.62, 240):
        p = B.surf_point(s, v)
        if p[0] < 0.3 * B.w_max(s):
            continue
        d = abs(p[2] - z)
        if d < best[0]:
            best = (d, v)
    return best[1]


def side_pt(s, z, sg):
    v = sv(s, z)
    return B.surf(s, v) if sg > 0 else B.surf_mirror(s, v)


def grid_side(s_list, zs_of, sg):
    P, N = [], []
    for s in s_list:
        rp, rn = [], []
        for z in zs_of(s):
            p, n = side_pt(s, z, sg)
            rp.append(p)
            rn.append(n)
        P.append(rp)
        N.append(rn)
    return np.array(P), np.array(N)


def grid_top(s_list, x_list, sg):
    P, N = [], []
    for s in s_list:
        rp, rn = [], []
        for x in x_list:
            p, n = B.surf_xz(s, x) if sg > 0 else B.surf_xz_mirror(s, x)
            rp.append(p)
            rn.append(n)
        P.append(rp)
        N.append(rn)
    return np.array(P), np.array(N)


def centroid(f):
    return sum((v.co for v in f.verts), Vector((0.0, 0.0, 0.0))) / len(f.verts)


# ------------------------------------------------------------------ mesh primitives
def add_thick(bm, P, N, off, thk, mi):
    """Thick patch over a grid P (ni, nj, 3) with normals N: top = P + N*off,
    bottom = P + N*(off - thk). Closed by the grid boundary."""
    ni, nj = P.shape[0], P.shape[1]
    top = [[bm.verts.new(tuple(P[i, j] + N[i, j] * off)) for j in range(nj)] for i in range(ni)]
    bot = [[bm.verts.new(tuple(P[i, j] + N[i, j] * (off - thk))) for j in range(nj)] for i in range(ni)]
    fs = []
    for i in range(ni - 1):
        for j in range(nj - 1):
            fs.append(bm.faces.new([top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]]))
            fs.append(bm.faces.new([bot[i][j], bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j]]))
    perim = ([(0, j) for j in range(nj)] + [(i, nj - 1) for i in range(1, ni)]
             + [(ni - 1, j) for j in range(nj - 2, -1, -1)] + [(i, 0) for i in range(ni - 2, 0, -1)])
    for k in range(len(perim)):
        a = perim[k]
        b = perim[(k + 1) % len(perim)]
        fs.append(bm.faces.new([top[a[0]][a[1]], top[b[0]][b[1]], bot[b[0]][b[1]], bot[a[0]][a[1]]]))
    for f in fs:
        f.material_index = mi


def add_box(bm, c, size, mi):
    cx, cy, cz = c
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    vs = [bm.verts.new((cx + a * hx, cy + b * hy, cz + d * hz))
          for a in (-1, 1) for b in (-1, 1) for d in (-1, 1)]
    for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        bm.faces.new([vs[i] for i in q]).material_index = mi


def add_cyl(bm, p0, p1, r, mi, seg=24):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    M = Matrix.Translation((p0 + p1) * 0.5) @ rot
    n0 = len(bm.faces)
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg,
                          radius1=r, radius2=r, depth=d.length, matrix=M)
    for f in list(bm.faces)[n0:]:
        f.material_index = mi


def add_ell(bm, c, ax, ay, az, keep_top, mi):
    """Half ellipsoid (top or bottom half) at c with half-axes ax, ay, az."""
    n0 = len(bm.faces)
    M = Matrix.Translation(c) @ Matrix.Diagonal((ax, ay, az, 1.0))
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=1.0, matrix=M, calc_uvs=False)
    fs = list(bm.faces)[n0:]
    drop = []
    for f in fs:
        if (centroid(f).z > c[2]) == keep_top:
            f.material_index = mi
        else:
            drop.append(f)
    bmesh.ops.delete(bm, geom=drop, context='FACES')


def add_wing(bm, zb, mi):
    """Low fixed wing: NACA-like cambered section extruded across span x in [-0.75, 0.75]."""
    cs = (1.0 - np.cos(np.linspace(0.0, np.pi, 25))) / 2.0
    c, t, m, p = 0.24, 0.14, 0.02, 0.4
    yc = np.where(cs < p, m / p ** 2 * (2 * p * cs - cs ** 2),
                  m / (1 - p) ** 2 * ((1 - 2 * p) + 2 * p * cs - cs ** 2))
    yt = 5 * t * (0.2969 * np.sqrt(cs) - 0.1260 * cs - 0.3516 * cs ** 2 + 0.2843 * cs ** 3 - 0.1015 * cs ** 4)
    Yle = 4.22 - Y0
    up = [(Yle + cs[k] * c, zb + (yc[k] + yt[k]) * c) for k in range(24, -1, -1)]
    lo = [(Yle + cs[k] * c, zb + (yc[k] - yt[k]) * c) for k in range(1, 24)]
    loop = up + lo
    A = [bm.verts.new((-0.75, yy, zz)) for yy, zz in loop]
    Bv = [bm.verts.new((0.75, yy, zz)) for yy, zz in loop]
    n = len(loop)
    for k in range(n):
        bm.faces.new([A[k], A[(k + 1) % n], Bv[(k + 1) % n], Bv[k]]).material_index = mi
    bm.faces.new(A).material_index = mi
    bm.faces.new(list(reversed(Bv))).material_index = mi


def finish_obj(name, bm, mats):
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


# ------------------------------------------------------------------ body edits
def add_loft(bm, rings, mi):
    """Closed loft through rings (list of (N,3) arrays, same N); end caps are fans to the centroid.
    Used for streamlined parts (uprights, plates, fin) instead of boxes."""
    rv = [[bm.verts.new(tuple(p)) for p in ring] for ring in rings]
    N = len(rings[0])
    fs = []
    for r in range(len(rings) - 1):
        for j in range(N):
            k = (j + 1) % N
            fs.append(bm.faces.new([rv[r][j], rv[r][k], rv[r + 1][k], rv[r + 1][j]]))
    for ring_v, ring in ((rv[0], rings[0]), (rv[-1], rings[-1])):
        c = bm.verts.new(tuple(np.mean(ring, axis=0)))
        for j in range(N):
            fs.append(bm.faces.new([c, ring_v[j], ring_v[(j + 1) % N]]))
    for f in fs:
        f.material_index = mi


def ell_ring(c, ex, ez, ax, az, n=16, scale=1.0):
    """Ellipse ring around centre c in the plane of unit vectors ex (half-length ax) and ez (az)."""
    c, ex, ez = np.array(c, float), np.array(ex, float), np.array(ez, float)
    out = []
    for k in range(n):
        t = 2 * math.pi * k / n
        out.append(c + scale * (ax * math.cos(t) * ex + az * math.sin(t) * ez))
    return np.array(out)


def _v_top_cross(h, x0):
    """Around-section v where the top surface crosses half-width x0 (top half, X decreasing)."""
    X, V = h["X"], h["V"]
    for k in range(len(X) - 1):
        if X[k] >= x0 > X[k + 1]:
            f = (X[k] - x0) / (X[k] - X[k + 1])
            return float(V[k] + f * (V[k + 1] - V[k]))
    raise RuntimeError("no top crossing at x=%.3f" % x0)


def _v_side_cross(h, z0, xmin):
    """Around-section v where the outer side (X > xmin) crosses height z0 going up."""
    X, Z, V = h["X"], h["Z"], h["V"]
    for k in range(len(X) - 1):
        if Z[k] < z0 <= Z[k + 1] and X[k] > xmin:
            f = (z0 - Z[k]) / (Z[k + 1] - Z[k])
            return float(V[k] + f * (V[k + 1] - V[k]))
    raise RuntimeError("no side crossing at z=%.3f" % z0)


def light_band(s):
    """R-list 2A fix: the light blade runs from the centre notch (x 0.16 on top) round the nose
    corner and down the side to 0.10 m below the shoulder. Returns (v_side, v_top)."""
    h = B._half(s)
    return _v_side_cross(h, B.z_sh(s) - 0.10, 0.3 * B.w_max(s)), _v_top_cross(h, 0.16)


def v_grid(s_list, v_of_s, sg):
    P, N = [], []
    for s in s_list:
        rp, rn = [], []
        for v in v_of_s(s):
            p, n = B.surf(s, v) if sg > 0 else B.surf_mirror(s, v)
            rp.append(p)
            rn.append(n)
        P.append(rp)
        N.append(rn)
    return np.array(P), np.array(N)


def body_edit(body, fn):
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.faces.ensure_lookup_table()
    fn(bm)
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()


def pocket(body, pred, depth, name):
    """Cut a recess: faces whose centroid passes pred(x, s, z) are removed and replaced by a
    floor offset inward by depth plus walls along the open boundary (slot 1, M_Trim)."""
    res = {}

    def op(bm):
        bm.normal_update()
        sel = [f for f in bm.faces if pred(centroid(f).x, centroid(f).y + Y0, centroid(f).z)]
        res["n"] = len(sel)
        if not sel:
            return
        selset = set(sel)
        verts = set(v for f in sel for v in f.verts)
        cp = {}
        for v in verts:
            n = Vector((0.0, 0.0, 0.0))
            for lf in v.link_faces:
                n += lf.normal
            n.normalize()
            cp[v] = bm.verts.new(v.co - n * depth)
        edges = set(e for f in sel for e in f.edges)
        bnd = [e for e in edges if sum(1 for lf in e.link_faces if lf in selset) == 1]
        new = []
        for f in sel:
            new.append(bm.faces.new([cp[v] for v in reversed(list(f.verts))]))
        for e in bnd:
            a, b = e.verts
            new.append(bm.faces.new([a, b, cp[b], cp[a]]))
        bmesh.ops.delete(bm, geom=sel, context='FACES')  # also drops verts/edges used only by sel
        for f in new:
            f.material_index = 1

    body_edit(body, op)
    print("POCKET %-16s faces %4d depth %.3f" % (name, res.get("n", 0), depth))


def tail_slice(bm):
    """Cut horizontal edges into the tail fan at the ruling heights so the recess and
    lamp surround boundaries are straight lines, not fan slivers."""
    for z in (0.585, 0.66, 0.84):
        fs = [f for f in bm.faces if centroid(f).y + Y0 >= 4.2]
        geom = set(fs)
        for f in fs:
            geom.update(f.verts)
            geom.update(f.edges)
        bmesh.ops.bisect_plane(bm, geom=list(geom), plane_co=(0.0, 0.0, z),
                               plane_no=(0.0, 0.0, 1.0), dist=1e-6)
        bm.faces.ensure_lookup_table()
    print("TAIL slice, faces now", len(bm.faces))


def sill_and_caps(bm):
    """Rocker below z_bot + 0.085 is M_Trim (slot 1). Mirror housing tops are paint (slot 0)."""
    n_sill = 0
    for f in bm.faces:
        c = centroid(f)
        s = c.y + Y0
        if 0.5 <= s <= 3.7 and abs(c.x) >= 0.5 * B.w_max(s) and c.z < B.z_bot(s) + 0.085:
            f.material_index = 1
            n_sill += 1
    print("SILL faces", n_sill)
    for sg in (1, -1):
        add_ell(bm, (sg * 0.90, 1.58 - Y0, B.z_sh(1.58) + 0.06), 0.055, 0.10, 0.045, True, 0)


# ------------------------------------------------------------------ pocket predicates
def p_nose_intake(x, s, z):
    return abs(x) <= 0.55 and -0.05 <= s <= 0.10 and 0.24 <= z <= 0.34


def p_brake(x, s, z):
    return 0.60 <= abs(x) <= 0.80 and 0.03 <= s <= 0.07 and 0.33 <= z <= 0.40


def p_side_intake(x, s, z):
    return abs(x) > 0.55 and 2.66 <= s <= 3.10 and 0.36 <= z <= 0.61


def p_tail_low(x, s, z):
    return s >= 4.43 and z < 0.585


def p_tail_band(x, s, z):
    return s >= 4.44 and 0.66 <= z <= 0.84


# ------------------------------------------------------------------ materials
def extra_materials():
    out = {}
    m, b = B._principled("M_Carbon", B._lin((0x12, 0x12, 0x14)), 0.0, 0.35)
    b.inputs["Coat Weight"].default_value = 0.6
    b.inputs["Coat Roughness"].default_value = 0.2
    out["M_Carbon"] = m
    m, b = B._principled("M_Chrome", B._lin((0xE8, 0xE8, 0xEC)), 1.0, 0.12)
    out["M_Chrome"] = m
    m, b = B._principled("M_Lens", B._lin((0xFF, 0xFF, 0xFF)), 0.0, 0.05)
    b.inputs["Alpha"].default_value = 0.25
    m.surface_render_method = "BLENDED"
    out["M_Lens"] = m
    m, b = B._principled("M_LightFront", B._lin((0xDD, 0xEB, 0xFF)), 0.0, 0.2)
    b.inputs["Emission Color"].default_value = B._srgb_to_lin(B._lin((0xDD, 0xEB, 0xFF)))
    b.inputs["Emission Strength"].default_value = 6.0
    out["M_LightFront"] = m
    return out


# ------------------------------------------------------------------ object builders
def build_lights_front(mats):
    bm = bmesh.new()
    for sg in (1, -1):
        # lens band wraps the nose corner: v runs from the side (z_sh - 0.10) to the notch edge
        P, N = v_grid([0.035, 0.060, 0.085], lambda s: np.linspace(*light_band(s), 12), sg)
        add_thick(bm, P, N, 0.006, 0.002, 1)  # clear lens (slot 1)
        v0, v1 = light_band(0.060)
        edges = np.linspace(v0, v1, 10)
        for k in range(9):
            d = 0.12 * (edges[1] - edges[0])
            a, b_ = edges[k] + d, edges[k + 1] - d
            P, N = v_grid([0.042, 0.078], lambda s: [a, 0.5 * (a + b_), b_], sg)
            add_thick(bm, P, N, 0.0035, 0.0015, 0)  # emitter cells (slot 0)
    return finish_obj("lights_front", bm, [mats["M_LightFront"], mats["M_Lens"]])


def build_trim(mats, body):
    bm = bmesh.new()
    # front splitter: follows the nose underside, 25 mm thick, end plates
    sl = [-0.03, 0.05, 0.14, 0.23, 0.32]
    # span stays inside the nose underside (floor edge is w_max - 0.13), so the ends close cleanly
    fr = np.linspace(-0.80, 0.80, 9)
    P = np.zeros((5, 9, 3))
    N = np.zeros((5, 9, 3))
    for i, s in enumerate(sl):
        sc = max(s, 0.0)
        for j, f in enumerate(fr):
            P[i, j] = (f * B.w_max(sc), s - Y0, B.z_bot(sc) + 0.003)
            N[i, j] = (0.0, 0.0, 1.0)
    add_thick(bm, P, N, 0.0, 0.025, 1)
    # side skirts: 30 mm proud of the rocker, 60 mm tall, s 1.30 .. 3.15
    for sg in (1, -1):
        P, N = grid_side([1.30, 1.90, 2.50, 3.15],
                         lambda s: [B.z_bot(s) + 0.015, B.z_bot(s) + 0.045, B.z_bot(s) + 0.075], sg)
        add_thick(bm, P, N, 0.03, 0.03, 0)
    # diffuser: five vertical strakes in the recess
    for xk in (-0.27, -0.135, 0.0, 0.135, 0.27):
        add_box(bm, (xk, FLOOR_TAIL + 0.012, 0.34), (0.022, 0.024, 0.24), 0)
    # fixed low wing on swan-neck uprights, end plates
    zw = B.z_top(4.34) + 0.10 + 0.017
    add_wing(bm, zw, 1)
    for sx in (1, -1):
        # swan-neck upright: streamlined loft, chord along Y, tapering toward the wing
        zb_, zt_ = B.z_top(4.34) - 0.02, zw
        rings = [ell_ring((sx * 0.48, 4.34 - Y0, zb_ + hh * (zt_ - zb_)), (0, 1, 0), (1, 0, 0),
                          0.034, 0.013, 16, 1.0 - 0.25 * hh) for hh in np.linspace(0.0, 1.0, 6)]
        add_loft(bm, rings, 1)
        # end plate: rounded-rectangle (squircle) loft, two rings 8 mm apart in X
        rings = []
        for off in (-0.004, 0.004):
            c = np.array((sx * (0.75 + off), 2.06, zw))
            t = np.linspace(0.0, 2 * math.pi, 17)[:-1]
            sq = lambda a: np.sign(a) * np.abs(a) ** 0.3
            rings.append(np.array([c + 0.06 * sq(np.cos(a)) * np.array((0, 1, 0))
                                   + 0.13 * sq(np.sin(a)) * np.array((0, 0, 1)) for a in t]))
        add_loft(bm, rings, 1)
    # mirrors: round arm, housing base (trim), mirror face (chrome); housing top is paint (body)
    for sx in (1, -1):
        add_cyl(bm, (sx * 0.84, 1.58 - Y0, B.z_sh(1.58) + 0.03), (sx * 0.90, 1.58 - Y0, B.z_sh(1.58) + 0.03),
                0.011, 0, 16)
        add_ell(bm, (sx * 0.90, 1.58 - Y0, B.z_sh(1.58) + 0.06), 0.055, 0.10, 0.045, False, 0)
        add_box(bm, (sx * 0.952, 1.58 - Y0, B.z_sh(1.58) + 0.03), (0.004, 0.07, 0.05), 2)
    # door handles: flush pads, s 2.40, z = z_sh - 0.07
    for sg in (1, -1):
        P, N = grid_side([2.32, 2.40, 2.48],
                         lambda s: [B.z_sh(2.40) - 0.07 - 0.0125, B.z_sh(2.40) - 0.07,
                                    B.z_sh(2.40) - 0.07 + 0.0125], sg)
        add_thick(bm, P, N, 0.001, 0.003, 0)
    # antenna fin on the roof
    # roof fin: low rounded dome, top 8 mm above the roof and below the 1.19 m height limit
    add_ell(bm, (0.0, 2.30 - Y0, B.z_top(2.30) - 0.012), 0.006, 0.07, 0.020, True, 0)
    # front lower housing behind the light lens
    for sg in (1, -1):
        P, N = grid_top([0.030, 0.090], np.linspace(0.15, XE + 0.01, 5), sg)
        add_thick(bm, P, N, 0.0025, 0.0025, 0)
    # side intake: dark mesh slats on the pocket floor (floor is 60 mm inside the surface)
    for sg in (1, -1):
        for z in (0.38, 0.43, 0.48, 0.53, 0.58):
            p, _ = side_pt(2.88, z, sg)
            add_box(bm, (p[0] - sg * 0.052, 2.88 - Y0, z), (0.016, 0.44, 0.012), 0)
    # tail: diffuser and claws surround stay on the body; exhaust in exhaust object
    return finish_obj("trim", bm, [mats["M_Trim"], mats["M_Carbon"], mats["M_Chrome"]])


def build_lights_rear_plate(mats):
    bl = bmesh.new()
    for sx in (1, -1):
        for k in range(3):
            add_box(bl, (sx * (0.514 + 0.045 * k), YB + 0.002, 0.74), (0.028, 0.008, 0.115), 0)
    add_box(bl, (0.0, YB + 0.002, 0.80), (1.0, 0.008, 0.010), 0)
    lights = finish_obj("lights_rear", bl, [mats["M_LightRear"]])
    bp = bmesh.new()
    fl = FLOOR_TAIL
    add_box(bp, (0.0, fl + 0.004, 0.56), (0.36, 0.008, 0.12), 0)  # plate block (slot 0 M_Plate)
    px = 0.0095
    text = "NOCTRA"
    cols = []
    for ch in text:
        if cols:
            cols.append(None)
        cols.append(BITMAP[ch])
    g = 0
    for item in cols:
        if item is None:
            g += 1
            continue
        for r, row in enumerate(item):
            for cc, bit in enumerate(row):
                if bit == "1":
                    # viewer behind the car looks along -Y: viewer right is -X, so x grows to the left
                    add_box(bp, (-(g + cc - 17) * px, fl + 0.010, 0.56 + (3 - r) * px), (px * 0.9, 0.004, px * 0.9), 1)
        g += 5
    plate = finish_obj("plate_rear", bp, [mats["M_Plate"], mats["M_Trim"]])
    return lights, plate


def build_exhaust(mats):
    bm = bmesh.new()
    for sx in (1, -1):
        x = sx * 0.045
        add_cyl(bm, (x, FLOOR_TAIL - 0.004, 0.33), (x, FLOOR_TAIL + 0.040, 0.33), 0.030, 0, 32)
        add_cyl(bm, (x, FLOOR_TAIL + 0.034, 0.33), (x, FLOOR_TAIL + 0.0405, 0.33), 0.022, 1, 32)
    return finish_obj("exhaust", bm, [mats["M_Chrome"], mats["M_Trim"]])


def liner(bm, mi):
    """Dark cabin liner 30 mm inside the body surface, s 1.40 .. 3.06 (closes the tub from
    below and above; hides the red inner faces of the shell seen through the glass)."""
    for sg in (1, -1):
        P, N = [], []
        for s in (1.40, 1.90, 2.40, 2.90, 3.06):
            rp, rn = [], []
            for v in np.linspace(0.12, 0.98, 12):
                p, n = B.surf(s, v) if sg > 0 else B.surf_mirror(s, v)
                rp.append(p)
                rn.append(n)
            P.append(rp)
            N.append(rn)
        add_thick(bm, np.array(P), np.array(N), -0.030, 0.012, mi)


def build_interior(mats):
    bm = bmesh.new()
    mi = 0
    liner(bm, mi)
    add_box(bm, (0.0, -0.055, 0.38), (1.2, 1.65, 0.04), mi)  # cabin floor
    add_box(bm, (0.0, -0.76, 0.56), (1.5, 0.22, 0.12), mi)  # dash base
    add_ell(bm, (0.0, -0.76, 0.62), 0.78, 0.12, 0.20, True, mi)  # dash top, rounded
    add_box(bm, (-0.32, -0.70, 0.91), (0.22, 0.10, 0.08), mi)  # binnacle
    add_box(bm, (0.0, 0.30, 0.46), (0.20, 1.40, 0.12), mi)  # centre tunnel
    for sx in (-1, 1):
        x = sx * 0.32
        add_ell(bm, (x, -0.04, 0.50), 0.23, 0.25, 0.07, True, mi)  # seat cushion, domed
        add_box(bm, (x, -0.04, 0.42), (0.20, 0.20, 0.06), mi)  # seat pedestal
        add_ell(bm, (x, 0.20, 0.84), 0.23, 0.06, 0.30, True, mi)  # seat back, rounded top
        add_box(bm, (x, 0.20, 0.66), (0.40, 0.10, 0.28), mi)  # seat back lower body
        add_ell(bm, (x, 0.20, 1.03), 0.13, 0.07, 0.09, True, mi)  # headrest
    # steering wheel in front of the left seat, tilted toward the driver
    c = Vector((-0.32, -0.30, 0.88))
    X = Vector((1.0, 0.0, 0.0))
    V = Vector((0.0, 0.5, 0.866)).normalized()
    R = 0.16
    for k in range(16):
        t0 = 2 * math.pi * k / 16
        t1 = 2 * math.pi * (k + 1) / 16
        p0 = c + R * (math.cos(t0) * X + math.sin(t0) * V)
        p1 = c + R * (math.cos(t1) * X + math.sin(t1) * V)
        add_cyl(bm, p0, p1, 0.012, mi, 8)
    nrm = X.cross(V)
    add_cyl(bm, c - nrm * 0.02, c + nrm * 0.02, 0.03, mi, 12)
    return finish_obj("interior", bm, [mats["M_Interior"]])


def build_wheels(mats):
    out = []
    for name, (x, y, r, w) in WHEEL_SPECS.items():
        bm = bmesh.new()
        add_cyl(bm, (x - w / 2, y, r), (x + w / 2, y, r), r, 0, 48)
        out.append(finish_obj(name, bm, [mats["M_Tire"]]))
    return out


def build_col(body):
    pts = np.array([tuple(v.co) for v in body.data.vertices])
    chosen = [0]
    d = np.linalg.norm(pts - pts[0], axis=1)
    for _ in range(47):
        idx = int(np.argmax(d))
        chosen.append(idx)
        d = np.minimum(d, np.linalg.norm(pts - pts[idx], axis=1))
    bm = bmesh.new()
    for i in chosen:
        bm.verts.new(tuple(pts[i]))
    bm.verts.ensure_lookup_table()
    ret = bmesh.ops.convex_hull(bm, input=list(bm.verts))
    unused = list({g for g in ret["geom_interior"] + ret["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
    bmesh.ops.delete(bm, geom=unused, context='VERTS')
    ob = finish_obj("col_body", bm, [])
    ob.hide_render = True
    ob["collision_only"] = 1  # exported as glTF extras: the engine must skip this node
    print("COL verts", len(ob.data.vertices), "faces", len(ob.data.polygons))
    return ob


# ------------------------------------------------------------------ main
def render_set(sc, cam, tgt):
    views = {
        "side": ((9.0, 0.0, 0.85), (0.0, 0.0, 0.55), 60),
        "front34": ((-6.2, -6.6, 1.00), (0.0, 0.0, 0.55), 60),
        "rear34": ((6.2, 6.6, 1.00), (0.0, 0.0, 0.55), 60),
        "top": ((0.0, 0.01, 11.0), (0.0, 0.0, 0.0), 60),
        "front_low": ((-2.2, -7.4, 0.35), (0.0, 0.0, 0.55), 60),
        "rear_low": ((2.2, 7.4, 0.35), (0.0, 0.0, 0.55), 60),
        "nose_closeup": ((-1.4, -4.6, 0.9), (0.0, -2.1, 0.35), 85),
        "tail_closeup": ((1.9, 4.9, 1.0), (0.0, 2.1, 0.65), 85),
        "intake_closeup": ((2.9, 0.2, 0.8), (0.95, 0.6, 0.48), 85),
        "cabin_closeup": ((-1.6, -2.4, 1.5), (0.0, -0.05, 0.9), 70),
    }
    only = os.environ.get("VIEWS")
    for name, (cp, tp, lens) in views.items():
        if only and name not in only.split(","):
            continue
        cam.location = cp
        tgt.location = tp
        cam.data.lens = lens
        sc.render.filepath = os.path.join(OUT, name + ".png")
        bpy.context.view_layer.update()
        bpy.ops.render.render(write_still=True)
        print("RENDERED", name)


def main():
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    body = B.build_shell()
    B.cut_panel_lines(body)
    B.checks(body)
    underbody = B.cut_arches(body)
    glass = B.split_glazing(body)
    mats = B.make_materials()
    mats.update(extra_materials())
    # cabin reads as dark grey, not black, under the rig (silhouettes through the glass)
    mats["M_Interior"].node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = \
        B._srgb_to_lin(B._lin((0x4A, 0x4E, 0x56)))
    body.data.materials.clear()
    body.data.materials.append(mats["M_Paint"])
    body.data.materials.append(mats["M_Trim"])
    pocket(body, p_nose_intake, 0.030, "nose intake")
    pocket(body, p_brake, 0.012, "brake ducts")
    pocket(body, p_side_intake, 0.060, "side intake")
    body_edit(body, tail_slice)
    pocket(body, p_tail_low, 0.035, "diffuser recess")
    pocket(body, p_tail_band, 0.008, "lamp surround")
    body_edit(body, sill_and_caps)
    col_src = body
    for ob in (body, glass, underbody):
        B.finish_shading(ob)
    glass.data.materials.clear()
    glass.data.materials.append(mats["M_Glass"])
    glass.data.materials.append(mats["M_Trim"])
    underbody.data.materials.clear()
    underbody.data.materials.append(mats["M_Trim"])
    trim = build_trim(mats, body)
    lights_f = build_lights_front(mats)
    lights_r, plate = build_lights_rear_plate(mats)
    exhaust = build_exhaust(mats)
    interior = build_interior(mats)
    wheels = build_wheels(mats)
    col = build_col(col_src)
    for ob in (trim, lights_f, lights_r, exhaust, interior, plate):
        ob.select_set(True)
    for ob in (trim, lights_f, lights_r, exhaust, interior):
        B.finish_shading(ob)
    sc, cam, tgt = B.setup_scene(mats)
    render_set(sc, cam, tgt)
    tris = {}
    for ob in (body, glass, underbody, trim, lights_f, lights_r, exhaust, interior, plate, col, *wheels):
        tris[ob.name] = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print("TRIS", tris, "total", sum(tris.values()))
    print("OBJECTS", sorted(o.name for o in bpy.data.objects))
    print("DETAILS_DONE")


if __name__ == "__main__":
    main()
