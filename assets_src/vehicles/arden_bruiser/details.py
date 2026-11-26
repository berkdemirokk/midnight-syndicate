"""Arden Bruiser details on the body shell (body.py): grille, headlight pods, hood vents, tail bar.

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

YF = B.L_TOTAL + B.TAIL_DS - Y0  # tail fascia plane (y)
FLOOR_TAIL = YF - 0.035  # valance recess floor (y)
YB = YF - 0.008  # lamp surround floor (y)

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
    c, t, m, p = 0.24, 0.14, 0.035, 0.4  # R9: camber 0.02 -> 0.035 so the plane reads as an aerofoil
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


def finish_obj(name, bm, mats, recalc=True):
    if recalc:
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
    # P8: band runs down the nose corner to just under the shoulder, toward the fender
    # round 8: wrap reaches further down the nose corner toward the fender (was z_sh - 0.035)
    return _v_side_cross(h, B.z_sh(s) - 0.085, 0.3 * B.w_max(s)), _v_top_cross(h, 0.16)


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




def pocket(body, pred, depth, name, keep=None):
    """Cut a recess: faces whose centroid passes pred(x, s, z) are removed and replaced by a
    floor offset inward by depth plus walls along the open boundary (slot 1, M_Trim).
    keep: optional list that receives (coords, normals) of every removed face (for lens patches)."""
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
        nn = {}
        for v in verts:
            n = Vector((0.0, 0.0, 0.0))
            for lf in v.link_faces:
                n += lf.normal
            n.normalize()
            nn[v] = n
            cp[v] = bm.verts.new(v.co - n * depth)
        if keep is not None:
            for f in sel:
                keep.append(([tuple(v.co) for v in f.verts], [tuple(nn[v]) for v in f.verts]))
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


def slice_region(bm, region, planes, label):
    """Bisect the faces inside region(centroid) along the given planes so recess outlines are straight."""
    for co, no in planes:
        fs = [f for f in bm.faces if region(centroid(f))]
        geom = set(fs)
        for f in fs:
            geom.update(f.verts)
            geom.update(f.edges)
        bmesh.ops.bisect_plane(bm, geom=list(geom), plane_co=co, plane_no=no, dist=1e-6)
        bm.faces.ensure_lookup_table()
    print("SLICE %s faces now %d" % (label, len(bm.faces)))


def _z(z):
    return ((0.0, 0.0, z), (0.0, 0.0, 1.0))


def _x(x):
    return ((x, 0.0, 0.0), (1.0, 0.0, 0.0))


def _y(s):
    return ((0.0, s - Y0, 0.0), (0.0, 1.0, 0.0))


# nose: grille opening |x| <= 0.58, z .36..0.60; headlight pods |x| .62..0.88, two stacked z bands
GR_X, GR_Z0, GR_Z1 = 0.58, 0.36, 0.60
POD_X0, POD_X1 = 0.62, 0.90
POD_LOW = (0.495, 0.575)
POD_UP = (0.595, 0.670)


def nose_slice(bm):
    reg = lambda c: c.y + Y0 <= 0.30
    slice_region(bm, reg, [_z(GR_Z0), _z(GR_Z1), _z(POD_LOW[0]), _z(POD_LOW[1]), _z(POD_UP[0]), _z(POD_UP[1]),
                           _x(GR_X), _x(-GR_X), _x(POD_X0), _x(-POD_X0), _x(POD_X1), _x(-POD_X1),
                           _z(0.32)], "nose")


def tail_slice(bm):
    reg = lambda c: c.y + Y0 >= 4.2
    slice_region(bm, reg, [_z(0.56), _z(TAIL_BAND[0]), _z(TAIL_BAND[1])], "tail")


def vent_slice(bm):
    reg = lambda c: abs(c.x) > 0.5 and 1.30 <= c.y + Y0 <= 2.0
    slice_region(bm, reg, [_y(VENT_S[0]), _y(VENT_S[1]), _z(VENT_Z[0]), _z(VENT_Z[1])], "fender vent")


TAIL_BAND = (0.745, 0.835)
VENT_S = (1.48, 1.86)
VENT_Z = (0.40, 0.60)


def p_grille(x, s, z):
    return abs(x) <= GR_X and s <= 0.30 and GR_Z0 <= z <= GR_Z1


def p_pod_low(x, s, z):
    return POD_X0 <= abs(x) <= POD_X1 and s <= 0.30 and POD_LOW[0] <= z <= POD_LOW[1]


def p_pod_up(x, s, z):
    return POD_X0 <= abs(x) <= POD_X1 and s <= 0.30 and POD_UP[0] <= z <= POD_UP[1]


def p_vent(x, s, z):
    return abs(x) > 0.5 and VENT_S[0] <= s <= VENT_S[1] and VENT_Z[0] <= z <= VENT_Z[1]


def p_tail_low(x, s, z):
    return s >= B.L_TOTAL - 0.02 and z < 0.56


def p_tail_band(x, s, z):
    return s >= B.L_TOTAL - 0.02 and TAIL_BAND[0] <= z <= TAIL_BAND[1]


def sill_and_chin(bm):
    """Rocker below z_bot + 0.085 and the front air dam below z 0.32 are M_Trim (slot 1). Mirror caps are paint."""
    n = 0
    for f in bm.faces:
        c = centroid(f)
        s = c.y + Y0
        if 0.5 <= s <= 4.3 and abs(c.x) >= 0.5 * B.w_max(s) and c.z < B.z_bot(s) + 0.032:
            f.material_index = 1
            n += 1
        elif s <= 0.30 and c.z < 0.30 and abs(c.x) < 0.70:
            f.material_index = 1
            n += 1
    print("SILL/CHIN faces", n)
    for sg in (1, -1):
        add_ell(bm, (sg * MIRROR_X, MIRROR_S - Y0, B.z_sh(MIRROR_S) + 0.075), 0.055, 0.10, 0.045, True, 0)


MIRROR_S = 2.02
MIRROR_X = 0.885


def rounded_poly(P, r, k):
    """Closed polygon with each corner replaced by a quadratic arc of radius r (k segments)."""
    out, n = [], len(P)
    for i in range(n):
        p, v, q = (np.array(P[i - 1], float), np.array(P[i], float), np.array(P[(i + 1) % n], float))
        A = v + (p - v) * min(r / np.linalg.norm(p - v), 0.45)
        B_ = v + (q - v) * min(r / np.linalg.norm(q - v), 0.45)
        for j in range(k + 1):
            u = j / k
            out.append(tuple((1 - u) ** 2 * A + 2 * (1 - u) * u * v + u * u * B_))
    return out


def add_tube(bm, xc, zc, y0, y1, ro, ri, mi_out, mi_in, n=32):
    """Exhaust tip along Y: outer wall, a real rim (annulus) at y1 and a dark bore inside."""
    def ring(r, y):
        return [bm.verts.new((xc + r * math.cos(2 * math.pi * k / n), y,
                              zc + r * math.sin(2 * math.pi * k / n))) for k in range(n)]
    O0, O1, I0, I1 = ring(ro, y0), ring(ro, y1), ring(ri, y0), ring(ri, y1)
    cen = bm.verts.new((xc, y0 + 0.002, zc))
    for j in range(n):
        k = (j + 1) % n
        bm.faces.new([O0[j], O0[k], O1[k], O1[j]]).material_index = mi_out
        bm.faces.new([O1[j], O1[k], I1[k], I1[j]]).material_index = mi_out
        bm.faces.new([I1[j], I1[k], I0[k], I0[j]]).material_index = mi_in
        bm.faces.new([I0[j], I0[k], cen]).material_index = mi_in


def add_surface_copy(bm, recs, off, mi):
    """One-sided copies of recorded body faces, moved along their vertex normals by off."""
    for co, nr in recs:
        vs = [bm.verts.new(tuple(np.array(c) + np.array(n) * off)) for c, n in zip(co, nr)]
        try:
            bm.faces.new(vs).material_index = mi
        except ValueError:
            pass


# ------------------------------------------------------------------ materials
def extra_materials():
    out = {}
    m, b = B._principled("M_Carbon", B._lin((0x12, 0x12, 0x14)), 0.0, 0.35)
    b.inputs["Coat Weight"].default_value = 0.0
    b.inputs["Coat Roughness"].default_value = 0.2
    b.inputs["Specular IOR Level"].default_value = 0.12
    out["M_Carbon"] = m
    m, b = B._principled("M_Chrome", B._lin((0xE8, 0xE8, 0xEC)), 1.0, 0.12)
    out["M_Chrome"] = m
    m, b = B._principled("M_Pillar", B._lin((0x08, 0x08, 0x0A)), 0.0, 0.12)
    b.inputs["Coat Weight"].default_value = 1.0
    out["M_Pillar"] = m
    m, b = B._principled("M_Lens", B._lin((0xFF, 0xFF, 0xFF)), 0.0, 0.05)
    b.inputs["Alpha"].default_value = 0.25
    m.surface_render_method = "BLENDED"
    out["M_Lens"] = m
    m, b = B._principled("M_LightFront", B._lin((0xDD, 0xEB, 0xFF)), 0.0, 0.2)
    b.inputs["Emission Color"].default_value = B._srgb_to_lin(B._lin((0xDD, 0xEB, 0xFF)))
    b.inputs["Emission Strength"].default_value = 2.5  # 6.0 blew the render out; engine sets its own
    out["M_LightFront"] = m
    return out


# ------------------------------------------------------------------ object builders
def build_lights_front(mats, recs):
    bm = bmesh.new()
    for r in recs:
        add_surface_copy(bm, r, -0.030, 0)   # emitter (slot 0), deep in the pocket
    for r in recs:
        add_surface_copy(bm, r, -0.005, 1)   # clear lens over it (slot 1)
    # projector look: a dark bezel ring with a bright disc inside it, two per pod, so the lamp has depth
    faces = [(np.mean(np.array(co), axis=0), np.mean(np.array(nr), axis=0)) for r in recs for co, nr in r]
    for sg in (1, -1):
        for zc in (0.535, 0.632):
            for xc in (0.685, 0.835):
                tgt = np.array([sg * xc, 0.0, zc])
                c, n = min(faces, key=lambda f: (sg * f[0][0] - xc) ** 2 + (f[0][2] - zc) ** 2)
                n = n / np.linalg.norm(n)
                base = c + n * -0.030
                add_cyl(bm, tuple(base + n * 0.004), tuple(base + n * 0.016), 0.037, 2, 12)   # dark bezel
                add_cyl(bm, tuple(base + n * 0.016), tuple(base + n * 0.020), 0.027, 0, 12)   # bright disc
    return finish_obj("lights_front", bm, [mats["M_LightFront"], mats["M_Lens"], mats["M_Trim"]], recalc=False)


def build_trim(mats, body):
    bm = bmesh.new()
    # front splitter: follows the nose underside, 28 mm thick
    sl = [-0.04, 0.05, 0.14, 0.23, 0.34]
    fr = np.linspace(-0.80, 0.80, 11)
    P = np.zeros((len(sl), len(fr), 3))
    N = np.zeros_like(P)
    for i, s in enumerate(sl):
        sc = max(s, 0.0)
        for j, f in enumerate(fr):
            P[i, j] = (f * B.w_max(sc), s - Y0, B.z_bot(sc) + 0.002)
            N[i, j] = (0.0, 0.0, 1.0)
    add_thick(bm, P, N, 0.0, 0.028, 1)
    # side skirts s 1.50 .. 3.60, 30 mm proud of the rocker
    for sg in (1, -1):
        P, N = grid_side([1.50, 2.10, 2.70, 3.30, 3.65],
                         lambda s: [B.z_bot(s) + 0.015, B.z_bot(s) + 0.045, B.z_bot(s) + 0.075], sg)
        add_thick(bm, P, N, 0.03, 0.03, 0)
    # grille: backing dark mesh (carbon bars) and one thick chrome-free satin bar, all inside the opening
    yb = -0.004 - Y0
    for z in (0.395, 0.435, 0.515, 0.555):
        add_box(bm, (0.0, yb, z), (1.10, 0.016, 0.016), 1)
    add_box(bm, (0.0, yb - 0.006, 0.475), (1.12, 0.024, 0.046), 2)  # thick centre bar, polished (slot 2)
    for xk in np.linspace(-0.50, 0.50, 9):
        add_box(bm, (xk, yb + 0.003, 0.48), (0.008, 0.012, 0.22), 1)
    # hood: two blade vents each side on the bulge
    for sg in (1, -1):
        for xa, xb in ((0.060, 0.115), (0.175, 0.230)):
            P, N = grid_top([0.95, 1.05, 1.15, 1.25, 1.35], [xa, 0.5 * (xa + xb), xb], sg)
            add_thick(bm, P, N, 0.0025, 0.004, 0)
    # fender vent blades
    for sg in (1, -1):
        for z in (0.45, 0.50, 0.55):
            p, n = side_pt(0.5 * (VENT_S[0] + VENT_S[1]), z, sg)
            q = p - n * 0.022
            add_box(bm, (q[0], 0.5 * (VENT_S[0] + VENT_S[1]) - Y0, z), (0.03, 0.32, 0.007), 1)
    # mirrors: thin arm, teardrop housing (black base), paint cap
    for sx in (1, -1):
        zm = B.z_sh(MIRROR_S) + 0.075
        add_cyl(bm, (sx * 0.74, MIRROR_S - Y0, zm - 0.01), (sx * MIRROR_X, MIRROR_S - Y0, zm - 0.01), 0.007, 0, 12)
        rings, cap = [], []
        for x_off, sc in ((0.0, 0.45), (0.02, 0.80), (0.04, 1.0), (0.06, 0.92), (0.075, 0.55)):
            c = (sx * (MIRROR_X + x_off), MIRROR_S - Y0 - 0.012 * (1 - sc), zm)
            rings.append(ell_ring(c, (0, 1, 0), (0, 0, 1), 0.075 * sc, 0.050 * sc, 16))
            cap.append(ell_ring(c, (0, 1, 0), (0, 0, 1), 0.077 * sc, 0.052 * sc, 16)[:9])
        add_loft(bm, rings, 0)
        add_loft(bm, cap, 3)
    # door handles
    for sg in (1, -1):
        zh = B.z_sh(2.88) - 0.075
        P, N = grid_side([2.78, 2.88, 2.98], lambda s: [zh - 0.0125, zh, zh + 0.0125], sg)
        add_thick(bm, P, N, 0.001, 0.003, 0)
    # ducktail underside: short chrome-free valance lip along the recess edge is the body itself
    return finish_obj("trim", bm, [mats["M_Trim"], mats["M_Carbon"], mats["M_Chrome"], mats["M_Paint"]])


def build_lights_rear_plate(mats):
    bl = bmesh.new()
    zc = 0.5 * (TAIL_BAND[0] + TAIL_BAND[1])
    for sx in (1, -1):
        # one continuous bar per half, from the centre notch to the corner, slightly lower at the notch
        pts = [(0.075, zc - 0.030), (0.075, zc + 0.036), (0.69, zc + 0.036), (0.725, zc + 0.020),
               (0.725, zc - 0.030)]
        poly = rounded_poly(pts, 0.012, 3)
        for z_off, th in ((0.0, 0.010),):
            vs0 = [bl.verts.new((sx * p[0], YB - 0.001, p[1])) for p in poly]
            vs1 = [bl.verts.new((sx * p[0], YB + th, p[1])) for p in poly]
            n = len(poly)
            for k in range(n):
                bl.faces.new([vs0[k], vs0[(k + 1) % n], vs1[(k + 1) % n], vs1[k]])
            f = bl.faces.new(vs1)
            if f.normal.y < 0:
                f.normal_flip()
            bl.faces.new(list(reversed(vs0)))
        # thin lower bar
        add_box(bl, (sx * 0.39, YB + 0.003, zc - 0.058), (0.64, 0.008, 0.010), 0)
    lights = finish_obj("lights_rear", bl, [mats["M_LightRear"]])
    bp = bmesh.new()
    zp = 0.655
    add_box(bp, (0.0, YF + 0.006, zp), (0.34, 0.012, 0.10), 0)
    add_box(bp, (0.0, YF + 0.009, zp + 0.058), (0.38, 0.016, 0.016), 1)
    add_box(bp, (0.0, YF + 0.009, zp - 0.058), (0.38, 0.016, 0.016), 1)
    add_box(bp, (-0.18, YF + 0.009, zp), (0.016, 0.016, 0.10), 1)
    add_box(bp, (0.18, YF + 0.009, zp), (0.016, 0.016, 0.10), 1)
    plate = finish_obj("plate_rear", bp, [mats["M_Plate"], mats["M_Trim"]])
    return lights, plate


def build_exhaust(mats):
    bm = bmesh.new()
    for xc in (-0.60, -0.40, 0.40, 0.60):
        add_tube(bm, xc, 0.46, FLOOR_TAIL - 0.004, YF + 0.018, 0.034, 0.027, 0, 1, 32)
    return finish_obj("exhaust", bm, [mats["M_Chrome"], mats["M_Trim"]])


def liner(bm, mi):
    """Dark cabin liner 30 mm inside the body surface under the greenhouse."""
    for sg in (1, -1):
        P, N = [], []
        for s in (1.90, 2.40, 2.90, 3.40, 3.88):
            rp, rn = [], []
            v0 = _v_side_cross(B._half(s), 0.82, 0.3 * B.w_max(s))  # above the rear arch (crown 0.76)
            for v in np.linspace(v0, 0.98, 10):
                p, n = B.surf(s, v) if sg > 0 else B.surf_mirror(s, v)
                rp.append(p)
                rn.append(n)
            P.append(rp)
            N.append(rn)
        add_thick(bm, np.array(P), np.array(N), -0.030, 0.012, mi)


def build_interior(mats):
    bm = bmesh.new()
    mi = 0
    add_box(bm, (0.0, -0.055, 0.38), (1.2, 1.65, 0.04), mi)  # cabin floor
    add_box(bm, (0.0, -0.76, 0.56), (1.5, 0.22, 0.12), mi)  # dash base
    add_ell(bm, (0.0, -0.76, 0.62), 0.78, 0.12, 0.20, True, mi)  # dash top, rounded
    add_box(bm, (-0.32, -0.70, 0.91), (0.22, 0.10, 0.08), mi)  # binnacle
    add_box(bm, (0.0, 0.30, 0.46), (0.20, 1.40, 0.12), mi)  # centre tunnel
    for sx in (-1, 1):
        x = sx * 0.32
        add_ell(bm, (x, -0.04, 0.50), 0.23, 0.25, 0.07, True, mi)
        add_box(bm, (x, -0.04, 0.42), (0.20, 0.20, 0.06), mi)
        add_ell(bm, (x, 0.20, 0.84), 0.23, 0.06, 0.30, True, mi)
        add_box(bm, (x, 0.20, 0.66), (0.40, 0.10, 0.28), mi)
        add_ell(bm, (x, 0.20, 1.03), 0.13, 0.07, 0.09, True, mi)
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
    # the furniture was laid out around y = 0; the greenhouse sits further aft: shift it, then add the liner
    bmesh.ops.translate(bm, vec=(0.0, 0.50, 0.0), verts=list(bm.verts))
    liner(bm, mi)
    return finish_obj("interior", bm, [mats["M_Interior"]])


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
    ob["collision_only"] = 1
    print("COL verts", len(ob.data.vertices), "faces", len(ob.data.polygons))
    return ob
