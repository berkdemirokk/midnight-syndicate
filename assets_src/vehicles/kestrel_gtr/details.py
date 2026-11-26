"""Kestrel GT-R details on the body (body.py): same detail engine as the Noctra Sable R, own layout.

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
    "wheel_FL": (0.820, B.AX_F - Y0, 0.343, 0.265),
    "wheel_FR": (-0.820, B.AX_F - Y0, 0.343, 0.265),
    "wheel_RL": (0.815, B.AX_R - Y0, 0.352, 0.305),
    "wheel_RR": (-0.815, B.AX_R - Y0, 0.352, 0.305),
}
XE = B.xs_of(0.25) - 0.010  # outer end of the front lamp pod on the top surface
LAMP_S = (0.20, 0.245, 0.29, 0.335)  # head lamp pod stations
MIR_S = 2.28  # mirror station
FLOOR_TAIL = (B.LEN + B.TAIL_DS - Y0) - 0.035  # diffuser recess floor (y)
YF = B.LEN + B.TAIL_DS - Y0  # tail fascia plane (y)
YB = YF - 0.008  # lamp surround floor (y)

PLATE_Z = 0.80  # plate centre height, inside the lamp panel
Z_PANEL = (0.52, 0.70, 0.90)  # tail: diffuser recess top, lamp panel bottom and top
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
    # P8: band runs down the nose corner to just under the shoulder, toward the fender
    # round 8: wrap reaches further down the nose corner toward the fender (was z_sh - 0.035)
    return _v_side_cross(h, B.z_sh(s) - 0.10, 0.3 * B.w_max(s)), _v_top_cross(h, 0.60)


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


def lip_bevel(body):
    """P3: round the side-intake opening edge (wall to paint) into a 10 mm lip."""
    def op(bm):
        edges = []
        for e in bm.edges:
            if len(e.link_faces) != 2:
                continue
            a, b = e.link_faces
            if {a.material_index, b.material_index} != {0, 1}:
                continue
            m = (e.verts[0].co + e.verts[1].co) * 0.5
            if abs(m.x) > 0.55 and 1.40 <= m.y + Y0 <= 1.86 and 0.46 <= m.z <= 0.78:
                edges.append(e)
        bmesh.ops.bevel(bm, geom=edges, offset=0.010, offset_type='OFFSET', segments=3,
                        profile=0.5, affect='EDGES', clamp_overlap=True)
        print("INTAKE lip edges", len(edges))
    body_edit(body, op)


def _bisect(bm, pred, co, no):
    fs = [f for f in bm.faces if pred(centroid(f))]
    geom = set(fs)
    for f in fs:
        geom.update(f.verts)
        geom.update(f.edges)
    bmesh.ops.bisect_plane(bm, geom=list(geom), plane_co=co, plane_no=no, dist=1e-6)
    bm.faces.ensure_lookup_table()


def pre_slice(bm):
    """Cut the pocket outlines into the grid first (constant s, z and x planes in the pocket
    neighbourhood), so every pocket edge is a straight line and not a stair-step of quads."""
    def zone(x0, x1, s0, s1, z0, z1):
        return lambda c: x0 <= abs(c.x) <= x1 and s0 <= c.y + Y0 <= s1 and z0 <= c.z <= z1
    # fender gill (both sides, |x| > 0.55)
    g = zone(0.55, 2.0, 1.30, 1.95, 0.35, 0.90)
    for s_ in (1.46, 1.80):
        _bisect(bm, g, (0, s_ - Y0, 0), (0, 1, 0))
    for z_ in (0.50, 0.74):
        _bisect(bm, g, (0, 0, z_), (0, 0, 1))
    # bonnet vent
    v = zone(0.0, 0.45, 0.90, 1.75, 0.70, 1.2)
    for s_ in (1.02, 1.62):
        _bisect(bm, v, (0, s_ - Y0, 0), (0, 1, 0))
    for x_ in (-0.30, 0.30):
        _bisect(bm, v, (x_, 0, 0), (1, 0, 0))
    # nose mouth
    n = zone(0.0, 0.75, -0.2, 0.30, 0.15, 0.55)
    for z_ in (0.27, 0.385):
        _bisect(bm, n, (0, 0, z_), (0, 0, 1))
    for x_ in (-0.58, 0.58):
        _bisect(bm, n, (x_, 0, 0), (1, 0, 0))
    _bisect(bm, n, (0, 0.11 - Y0, 0), (0, 1, 0))
    print("PRE_SLICE faces", len(bm.faces))


def tail_slice(bm):
    """Cut horizontal edges into the tail fan at the ruling heights so the recess and
    lamp surround boundaries are straight lines, not fan slivers."""
    for z in Z_PANEL:
        fs = [f for f in bm.faces if centroid(f).y + Y0 >= B.LEN - 0.25]
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
        if 0.5 <= s <= 4.2 and abs(c.x) >= 0.5 * B.w_max(s) and c.z < B.z_bot(s) + 0.085:
            f.material_index = 1
            n_sill += 1
    print("SILL faces", n_sill)
    for sg in (1, -1):
        add_ell(bm, (sg * 0.93, MIR_S - Y0, B.z_sh(MIR_S) + 0.06), 0.055, 0.10, 0.045, True, 0)


# ------------------------------------------------------------------ pocket predicates
def p_nose_intake(x, s, z):
    return abs(x) <= 0.58 and -0.05 <= s <= 0.11 and 0.27 <= z <= 0.385


def rounded_poly(P, r, k):
    """Closed polygon with each corner replaced by a quadratic arc of radius r (k segments)."""
    out, n = [], len(P)
    for i in range(n):
        p, v, q = (np.array(P[i - 1], float), np.array(P[i], float), np.array(P[(i + 1) % n], float))
        A = v + (p - v) * min(r / np.linalg.norm(p - v), 0.45)
        B = v + (q - v) * min(r / np.linalg.norm(q - v), 0.45)
        for j in range(k + 1):
            u = j / k
            out.append(tuple((1 - u) ** 2 * A + 2 * (1 - u) * u * v + u * u * B))
    return out


def add_tube(bm, xc, zc, y0, y1, ro, ri, mi_out, mi_in, n=32):
    """Exhaust tip along Y: outer wall, a real rim (annulus) at y1 and a dark bore inside."""
    def ring(r, y):
        return [bm.verts.new((xc + r * math.cos(2 * math.pi * k / n), y,
                              zc + r * math.sin(2 * math.pi * k / n))) for k in range(n)]
    O0, O1, I0, I1 = ring(ro, y0), ring(ro, y1), ring(ri, y0), ring(ri, y1)
    cen = bm.verts.new((xc, y0 + 0.002, zc))  # bore floor centre
    for j in range(n):
        k = (j + 1) % n
        bm.faces.new([O0[j], O0[k], O1[k], O1[j]]).material_index = mi_out  # outer wall
        bm.faces.new([O1[j], O1[k], I1[k], I1[j]]).material_index = mi_out  # rim, wall thickness
        bm.faces.new([I1[j], I1[k], I0[k], I0[j]]).material_index = mi_in   # dark bore wall
        bm.faces.new([I0[j], I0[k], cen]).material_index = mi_in            # dark bore floor


def p_side_intake(x, s, z):
    return abs(x) > 0.55 and 1.46 <= s <= 1.80 and 0.50 <= z <= 0.74


def p_tail_low(x, s, z):
    return s >= B.LEN - 0.02 and z < Z_PANEL[0]


def p_tail_band(x, s, z):
    return s >= B.LEN - 0.01 and Z_PANEL[1] <= z <= Z_PANEL[2]


def p_bonnet_vent(x, s, z):
    return abs(x) <= 0.30 and 1.02 <= s <= 1.62 and z > 0.78


# ------------------------------------------------------------------ materials
def extra_materials():
    out = {}
    m, b = B._principled("M_Carbon", B._lin((0x12, 0x12, 0x14)), 0.0, 0.35)
    # round 8: wing plates and uprights use this slot; strip-light reflections turned them pale grey
    b.inputs["Coat Weight"].default_value = 0.0
    b.inputs["Coat Roughness"].default_value = 0.2
    b.inputs["Specular IOR Level"].default_value = 0.12
    out["M_Carbon"] = m
    m, b = B._principled("M_Chrome", B._lin((0xE8, 0xE8, 0xEC)), 1.0, 0.12)
    out["M_Chrome"] = m
    # P1: gloss black greenhouse pillars and roof rails (material count 15, per the lead)
    m, b = B._principled("M_Pillar", B._lin((0x08, 0x08, 0x0A)), 0.0, 0.12)
    b.inputs["Coat Weight"].default_value = 1.0
    out["M_Pillar"] = m
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
        # slim pod: lens wraps the fender corner from the bonnet (x 0.60) down the nose corner
        P, N = v_grid(list(LAMP_S), lambda s: np.linspace(*light_band(s), 14), sg)
        add_thick(bm, P, N, 0.006, 0.002, 1)  # clear lens (slot 1)
        v0, v1 = light_band(0.2675)
        edges = np.linspace(v0, v1, 6)
        for k in range(5):  # five lit cells (slot 0)
            d = 0.10 * (edges[1] - edges[0])
            a, b_ = edges[k] + d, edges[k + 1] - d
            P, N = v_grid([0.22, 0.31], lambda s: [a, 0.5 * (a + b_), b_], sg)
            add_thick(bm, P, N, 0.0035, 0.0015, 0)
    return finish_obj("lights_front", bm, [mats["M_LightFront"], mats["M_Lens"]])


def build_trim(mats, body):
    bm = bmesh.new()
    # front splitter: follows the nose underside, 25 mm thick
    sl = [-0.03, 0.05, 0.14, 0.23, 0.32]
    fr = np.linspace(-0.80, 0.80, 9)  # span stays inside the nose underside, so the ends close cleanly
    P = np.zeros((5, 9, 3))
    N = np.zeros((5, 9, 3))
    for i, s in enumerate(sl):
        sc = max(s, 0.0)
        for j, f in enumerate(fr):
            P[i, j] = (f * B.w_max(sc), s - Y0, B.z_bot(sc) + 0.003)
            N[i, j] = (0.0, 0.0, 1.0)
    add_thick(bm, P, N, 0.0, 0.025, 1)
    # side skirts between the arches
    for sg in (1, -1):
        P, N = grid_side([1.42, 2.00, 2.70, 3.28],
                         lambda s: [B.z_bot(s) + 0.015, B.z_bot(s) + 0.045, B.z_bot(s) + 0.075], sg)
        add_thick(bm, P, N, 0.03, 0.03, 0)
    # diffuser: seven tapered strakes, 135 mm apart, rounded leading ends
    for xk in (-0.39, -0.26, -0.13, 0.0, 0.13, 0.26, 0.39):
        y_a, y_b = FLOOR_TAIL + 0.004, YF + 0.012
        rings = [ell_ring((xk, y_a - 0.003, 0.42), (1, 0, 0), (0, 0, 1), 0.001, 0.05, 12)]
        for t_ in (0.0, 0.5, 1.0):
            rings.append(ell_ring((xk, y_a + t_ * (y_b - y_a), 0.42), (1, 0, 0), (0, 0, 1),
                                  0.004, 0.10 * (1.0 - 0.3 * t_), 12))
        add_loft(bm, rings, 0)
    # ducktail lip: carbon blade along the deck edge, each ring follows the crowned deck
    yl = B.LEN - 0.07 - Y0
    rings = []
    for xk, sc in ((-0.72, 0.5), (-0.56, 0.9), (-0.30, 1.0), (0.0, 1.0), (0.30, 1.0), (0.56, 0.9), (0.72, 0.5)):
        zl = B.top_z(B.LEN - 0.07, abs(xk)) + 0.004
        rings.append(ell_ring((xk, yl, zl), (0, 1, 0), (0, 0, 1), 0.040 * sc, 0.012 * sc, 12))
    add_loft(bm, rings, 1)
    # mirrors: thin arm, teardrop housing (black base), paint cap on top
    for sx in (1, -1):
        zm = B.z_sh(MIR_S) + 0.05
        add_cyl(bm, (sx * 0.84, MIR_S - Y0, zm - 0.01), (sx * 0.93, MIR_S - Y0, zm - 0.01), 0.006, 0, 12)
        rings, cap = [], []
        for x_off, sc in ((0.0, 0.45), (0.02, 0.80), (0.04, 1.0), (0.06, 0.92), (0.075, 0.55)):
            c = (sx * (0.93 + x_off), MIR_S - Y0 - 0.012 * (1 - sc), zm)
            rings.append(ell_ring(c, (0, 1, 0), (0, 0, 1), 0.075 * sc, 0.050 * sc, 16))
            cap.append(ell_ring(c, (0, 1, 0), (0, 0, 1), 0.077 * sc, 0.052 * sc, 16)[:9])
        add_loft(bm, rings, 0)
        add_loft(bm, cap, 3)
    # door handles: flush pads
    for sg in (1, -1):
        P, N = grid_side([2.92, 3.00, 3.08],
                         lambda s: [B.z_sh(3.0) - 0.07 - 0.0125, B.z_sh(3.0) - 0.07,
                                    B.z_sh(3.0) - 0.07 + 0.0125], sg)
        add_thick(bm, P, N, 0.001, 0.003, 0)
    # wide mouth: five slats across the recess
    for z in (0.295, 0.315, 0.335, 0.355):
        add_box(bm, (0.0, 0.060 - Y0, z), (1.02, 0.010, 0.008), 0)
    # front fender gill: three blades 25 mm behind the opening
    for sg in (1, -1):
        for z in (0.56, 0.62, 0.68):
            p, n = side_pt(1.63, z, sg)
            q = p - n * 0.025
            add_box(bm, (q[0], 1.63 - Y0, z), (0.03, 0.26, 0.006), 0)
    # bonnet louvre: five carbon slats in the vent recess
    for s_k in np.linspace(1.08, 1.56, 5):
        add_box(bm, (0.0, s_k - Y0, B.top_z(s_k, 0.0) - 0.016), (0.50, 0.014, 0.006), 1)
    return finish_obj("trim", bm, [mats["M_Trim"], mats["M_Carbon"], mats["M_Chrome"], mats["M_Paint"]])


def build_lights_rear_plate(mats):
    bl = bmesh.new()
    y0 = YB + 0.001
    for sx in (1, -1):
        for xc in (0.50, 0.73):  # four round lamps: bright ring, dark core, small bright dot
            add_tube(bl, sx * xc, 0.80, y0, y0 + 0.012, 0.062, 0.040, 0, 1, 32)
            add_cyl(bl, (sx * xc, y0, 0.80), (sx * xc, y0 + 0.009, 0.80), 0.022, 0, 20)
    lights = finish_obj("lights_rear", bl, [mats["M_LightRear"], mats["M_Trim"]])
    bp = bmesh.new()
    # plate face 0.34 x 0.10 m (slot 0, M_Plate: the KESTREL text is in its texture), in the lamp panel
    add_box(bp, (0.0, YB + 0.006, PLATE_Z), (0.34, 0.012, 0.10), 0)
    add_box(bp, (0.0, YB + 0.010, PLATE_Z + 0.06), (0.38, 0.016, 0.02), 1)
    add_box(bp, (0.0, YB + 0.010, PLATE_Z - 0.06), (0.38, 0.016, 0.02), 1)
    add_box(bp, (-0.18, YB + 0.010, PLATE_Z), (0.02, 0.016, 0.10), 1)
    add_box(bp, (0.18, YB + 0.010, PLATE_Z), (0.02, 0.016, 0.10), 1)
    plate = finish_obj("plate_rear", bp, [mats["M_Plate"], mats["M_Trim"]])
    return lights, plate


def build_exhaust(mats):
    bm = bmesh.new()
    for x in (-0.325, -0.195, 0.195, 0.325):  # quad tips, split about the centre
        add_tube(bm, x, 0.42, FLOOR_TAIL - 0.004, FLOOR_TAIL + 0.040, 0.038, 0.030, 0, 1, 32)
    return finish_obj("exhaust", bm, [mats["M_Chrome"], mats["M_Trim"]])


def liner(bm, mi):
    """Dark cabin liner 30 mm inside the body surface (closes the tub from below and above;
    hides the paint-coloured inner faces of the shell seen through the glass)."""
    for sg in (1, -1):
        # two patches: the front one runs down to the floor; the rear one starts above the arch
        # (z 0.84), otherwise the liner cuts straight through the rear wheel
        for stations, zlo in (((2.00, 2.50, 3.00, 3.20), None), ((3.32, 3.60, 3.98), 0.84)):
            P, N = [], []
            for s in stations:
                v0 = 0.12 if zlo is None else _v_side_cross(B._half(s), zlo, 0.3 * B.w_max(s))
                rp, rn = [], []
                for v in np.linspace(v0, 0.98, 12):
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
    DY, SY = -0.15, 0.62  # dash and seat y (hero values were -0.76 and -0.04)
    add_box(bm, (0.0, 0.66, 0.36), (1.3, 1.95, 0.04), mi)  # cabin floor
    add_box(bm, (0.0, DY, 0.60), (1.55, 0.22, 0.14), mi)  # dash base
    add_ell(bm, (0.0, DY, 0.67), 0.80, 0.13, 0.22, True, mi)  # dash top, rounded
    add_box(bm, (-0.34, DY + 0.06, 0.96), (0.22, 0.10, 0.08), mi)  # binnacle
    add_box(bm, (0.0, 0.95, 0.46), (0.22, 1.60, 0.14), mi)  # centre tunnel
    for sx in (-1, 1):
        x = sx * 0.34
        add_ell(bm, (x, SY, 0.50), 0.24, 0.26, 0.07, True, mi)  # seat cushion, domed
        add_box(bm, (x, SY, 0.42), (0.21, 0.21, 0.06), mi)  # seat pedestal
        add_ell(bm, (x, SY + 0.24, 0.86), 0.24, 0.06, 0.31, True, mi)  # seat back, rounded top
        add_box(bm, (x, SY + 0.24, 0.68), (0.42, 0.10, 0.28), mi)  # seat back lower body
        add_ell(bm, (x, SY + 0.24, 1.05), 0.13, 0.07, 0.09, True, mi)  # headrest
    add_box(bm, (0.0, 1.55, 0.58), (1.5, 0.55, 0.06), mi)  # parcel shelf under the fastback glass
    # steering wheel in front of the driver seat, tilted toward the driver
    c = Vector((-0.34, DY + 0.42, 0.92))
    X = Vector((1.0, 0.0, 0.0))
    V = Vector((0.0, 0.5, 0.866)).normalized()
    R = 0.17
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
