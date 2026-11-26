"""Noctra Vela: details on the body surface (body.py). Same method as the Sable R details.py.

Every detail is a patch of the body surface function S(s, v) or S(s, x) (offset along the normal),
or a pocket cut into the body (pocket()), never a free-floating box. Called from build_car.py.
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

Y0 = B.Y_OFFSET
B._half = functools.lru_cache(maxsize=None)(B._half)  # surface sampling is called many times

YF = B.BODY_END + B.TAIL_DS - Y0  # tail fascia plane (y)
YB = YF + 0.001  # lamp, plate and tip units stand on the tail fascia
NOSE_S = 0.32  # nose region for slicing (s)

# front fascia layout (half-widths and heights on the nose face)
GRILLE = (0.40, 0.405, 0.500)  # |x| <=, z from, z to
MOUTH = (0.60, 0.270, 0.360)
# rear fascia layout
PLATE_Z = (0.500, 0.640)
VALANCE_Z = 0.480  # below this the tail is black bumper trim


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


def grid_top(s_list, x_of, sg):
    """x_of(s) gives the half-widths sampled at station s (so a patch can follow the outline)."""
    P, N = [], []
    for s in s_list:
        rp, rn = [], []
        for x in x_of(s):
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
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=6, radius=1.0, matrix=M, calc_uvs=False)
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


def add_loft(bm, rings, mi):
    """Closed loft through rings (list of (N,3) arrays, same N); end caps are fans to the centroid."""
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


def rounded_poly(P, r, k):
    """Closed polygon with each corner replaced by a quadratic arc of radius r (k segments)."""
    out, n = [], len(P)
    for i in range(n):
        p, v, q = (np.array(P[i - 1], float), np.array(P[i], float), np.array(P[(i + 1) % n], float))
        A = v + (p - v) * min(r / np.linalg.norm(p - v), 0.45)
        Bp = v + (q - v) * min(r / np.linalg.norm(q - v), 0.45)
        for j in range(k + 1):
            u = j / k
            out.append(tuple((1 - u) ** 2 * A + 2 * (1 - u) * u * v + u * u * Bp))
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


# ------------------------------------------------------------------ body edits
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


def slice_planes(bm, in_region, planes):
    """Bisect the faces of a region along planes so recess outlines are straight lines."""
    for co, no in planes:
        fs = [f for f in bm.faces if in_region(centroid(f))]
        geom = set(fs)
        for f in fs:
            geom.update(f.verts)
            geom.update(f.edges)
        bmesh.ops.bisect_plane(bm, geom=list(geom), plane_co=co, plane_no=no, dist=1e-6)
        bm.faces.ensure_lookup_table()


def slice_fascias(bm):
    """Straight outlines on the nose (grille, mouth, black chin) and tail (plate, valance)."""
    nose = lambda c: c.y + Y0 < NOSE_S  # noqa: E731
    planes = []
    for z in (0.300, MOUTH[1], MOUTH[2], GRILLE[1], GRILLE[2]):
        planes.append(((0.0, 0.0, z), (0.0, 0.0, 1.0)))
    for x in (GRILLE[0], MOUTH[0], -GRILLE[0], -MOUTH[0]):
        planes.append(((x, 0.0, 0.0), (1.0, 0.0, 0.0)))
    slice_planes(bm, nose, planes)
    tail = lambda c: c.y + Y0 >= B.BODY_END - 0.02  # noqa: E731
    planes = [((0.0, 0.0, z), (0.0, 0.0, 1.0)) for z in (VALANCE_Z, PLATE_Z[0] - 0.01, PLATE_Z[1] + 0.01)]
    slice_planes(bm, tail, planes)
    print("FASCIA slice, faces now", len(bm.faces))


def p_grille(x, s, z):
    return abs(x) <= GRILLE[0] and s < 0.20 and GRILLE[1] <= z <= GRILLE[2]


def p_mouth(x, s, z):
    return abs(x) <= MOUTH[0] and s < 0.20 and MOUTH[1] <= z <= MOUTH[2]


def paint_black(bm):
    """Rocker, chin and tail valance are M_Trim (slot 1)."""
    n = 0
    for f in bm.faces:
        c = centroid(f)
        s = c.y + Y0
        black = False
        if 1.0 <= s <= 3.05 and abs(c.x) >= 0.5 * B.w_max(s) and c.z < B.z_bot(s) + 0.11:
            black = True  # rocker
        elif s < 0.40 and c.z < 0.300:
            black = True  # chin below the mouth
        elif s >= B.BODY_END - 0.02 and c.z < VALANCE_Z:
            black = True  # tail valance
        elif p_grille(c.x, s, c.z) or p_mouth(c.x, s, c.z):
            black = True  # grille slot and wide mouth
        if black:
            f.material_index = 1
            n += 1
    print("BLACK faces", n)


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
    b.inputs["Emission Strength"].default_value = 6.0
    out["M_LightFront"] = m
    return out


# ------------------------------------------------------------------ object builders
def lamp_x(s):
    return np.linspace(0.44, B.xs_of(s) - 0.012, 9)


def build_lights_front(mats):
    """Slim wedge headlamp on the bonnet corner: clear lens over three LED bars, per side."""
    bm = bmesh.new()
    rows = list(np.linspace(0.040, 0.190, 8))
    for sg in (1, -1):
        P, N = grid_top(rows, lamp_x, sg)
        add_thick(bm, P, N, 0.0095, 0.0015, 1)  # clear lens (slot 1)
        # thin day-running bar along the leading edge, and a block projector at the inner end
        P, N = grid_top(list(np.linspace(0.056, 0.076, 3)), lambda s: np.linspace(0.46, B.xs_of(s) - 0.030, 8), sg)
        add_thick(bm, P, N, 0.0065, 0.0012, 0)
        P, N = grid_top(list(np.linspace(0.105, 0.165, 4)), lambda s: np.linspace(0.48, 0.62, 5), sg)
        add_thick(bm, P, N, 0.0065, 0.0012, 0)
    return finish_obj("lights_front", bm, [mats["M_LightFront"], mats["M_Lens"]])


def spoiler_poly():
    """Roof spoiler section (s, z): rides the roof trailing edge and overhangs the hatch glass."""
    zt = B.z_top
    return [(3.34, zt(3.34) + 0.004), (3.44, zt(3.44) + 0.030), (3.54, zt(3.54) + 0.062),
            (3.64, zt(3.54) + 0.054), (3.675, zt(3.54) + 0.040), (3.660, zt(3.54) + 0.026),
            (3.58, zt(3.54) + 0.020), (3.50, zt(3.50) - 0.010), (3.40, zt(3.40) - 0.025),
            (3.34, zt(3.34) - 0.025)]


def build_trim(mats, body):
    bm = bmesh.new()
    # front splitter: carbon blade under the nose, follows the nose underside
    sl = [-0.03, 0.05, 0.14, 0.23, 0.32]
    fr = np.linspace(-0.80, 0.80, 9)
    P = np.zeros((5, 9, 3))
    N = np.zeros((5, 9, 3))
    for i, s in enumerate(sl):
        sc = max(s, 0.0)
        for j, f in enumerate(fr):
            P[i, j] = (f * B.w_max(sc), s - Y0, B.z_bot(sc) + 0.003)
            N[i, j] = (0.0, 0.0, 1.0)
    add_thick(bm, P, N, 0.0, 0.020, 1)
    # side skirts: 25 mm proud of the rocker, between the arches
    for sg in (1, -1):
        P, N = grid_side([1.16, 1.60, 2.10, 2.60, 2.90],
                         lambda s: [B.z_bot(s) + 0.012, B.z_bot(s) + 0.040, B.z_bot(s) + 0.068], sg)
        add_thick(bm, P, N, 0.025, 0.028, 0)
    # grille: dark mesh bars inside the upper slot, and a wide mouth with three bars
    def front_y(x, z):
        """y of the nose surface at (x, z), by ray from the front."""
        hit, loc, nrm, idx = body.ray_cast(Vector((x, -3.0, z)), Vector((0.0, 1.0, 0.0)))
        return loc.y if hit else -Y0
    for z in np.linspace(GRILLE[1] + 0.012, GRILLE[2] - 0.012, 4):
        wseg = 2 * GRILLE[0] / 8 - 0.008  # eight short bar segments, each placed on the surface
        for x0 in np.linspace(-GRILLE[0] + wseg / 2 + 0.01, GRILLE[0] - wseg / 2 - 0.01, 8):
            add_box(bm, (x0, front_y(x0, z) + 0.001, z), (wseg, 0.008, 0.007), 1)
    for z in (MOUTH[1] + 0.022, MOUTH[1] + 0.045, MOUTH[1] + 0.068):
        wseg = 2 * MOUTH[0] / 10 - 0.008
        for x0 in np.linspace(-MOUTH[0] + wseg / 2 + 0.01, MOUTH[0] - wseg / 2 - 0.01, 10):
            add_box(bm, (x0, front_y(x0, z) + 0.001, z), (wseg, 0.008, 0.007), 1)
    # headlamp housing under the lens, same grid density as the lens so it follows the nose
    for sg in (1, -1):
        P, N = grid_top(list(np.linspace(0.040, 0.190, 8)), lamp_x, sg)
        add_thick(bm, P, N, 0.0045, 0.0030, 0)
    # rear diffuser: three tapered carbon strakes
    for xk in (-0.12, 0.0, 0.12):
        y_a, y_b = YF - 0.050, YF + 0.012
        rings = [ell_ring((xk, y_a - 0.003, 0.405), (1, 0, 0), (0, 0, 1), 0.001, 0.035, 12)]
        for t in (0.0, 0.5, 1.0):
            rings.append(ell_ring((xk, y_a + t * (y_b - y_a), 0.405), (1, 0, 0), (0, 0, 1),
                                  0.004, 0.075 * (1.0 - 0.3 * t), 12))
        add_loft(bm, rings, 1)
    # roof spoiler: body-coloured section extruded across the roof, softened ends (M_Paint, slot 3)
    poly = spoiler_poly()
    pc = np.mean(np.array(poly), axis=0)
    rings = []
    for xo, inset in ((0.505, 0.80), (0.495, 0.96), (0.480, 1.0), (0.0, 1.0), (-0.480, 1.0), (-0.495, 0.96), (-0.505, 0.80)):
        rings.append(np.array([(xo, pc[0] - Y0 + (p[0] - pc[0]) * inset, pc[1] + (p[1] - pc[1]) * inset) for p in poly]))
    add_loft(bm, rings, 3)
    # mirrors: thin arm, teardrop housing (black base), paint cap on top
    for sx in (1, -1):
        sm = 1.40
        zm = B.z_sh(sm) + 0.060
        xo = B.w_max(sm) - 0.02
        add_cyl(bm, (sx * (xo - 0.06), sm - Y0, zm - 0.012), (sx * xo, sm - Y0, zm - 0.012), 0.006, 0, 12)
        rings, cap = [], []
        for x_off, sc in ((0.0, 0.45), (0.02, 0.80), (0.04, 1.0), (0.06, 0.92), (0.075, 0.55)):
            c = (sx * (xo + x_off), sm - Y0 - 0.010 * (1 - sc), zm)
            rings.append(ell_ring(c, (0, 1, 0), (0, 0, 1), 0.070 * sc, 0.048 * sc, 16))
            cap.append(ell_ring(c, (0, 1, 0), (0, 0, 1), 0.072 * sc, 0.050 * sc, 16)[:9])
        add_loft(bm, rings, 0)
        add_loft(bm, cap, 3)
    # door handles: flush pads near the rear of the door
    for sg in (1, -1):
        zh = B.z_sh(2.58) - 0.075
        P, N = grid_side([2.50, 2.58, 2.66], lambda s: [zh - 0.0125, zh, zh + 0.0125], sg)
        add_thick(bm, P, N, 0.001, 0.003, 0)
    return finish_obj("trim", bm, [mats["M_Trim"], mats["M_Carbon"], mats["M_Chrome"], mats["M_Paint"]])


def build_lights_rear_plate(mats):
    bl = bmesh.new()
    for sx in (1, -1):
        # vertical lamp unit on the tail corner, light bar running toward the centre
        add_box(bl, (sx * 0.640, YB + 0.003, 0.815), (0.120, 0.008, 0.200), 0)
        add_box(bl, (sx * 0.395, YB + 0.003, 0.905), (0.350, 0.008, 0.012), 0)
    add_box(bl, (0.0, YB + 0.003, 0.905), (0.50, 0.008, 0.012), 0)
    lights = finish_obj("lights_rear", bl, [mats["M_LightRear"]])
    bp = bmesh.new()
    zc = 0.5 * (PLATE_Z[0] + PLATE_Z[1])
    add_box(bp, (0.0, YB + 0.002, zc), (0.34, 0.012, 0.10), 0)
    add_box(bp, (0.0, YB + 0.006, zc + 0.06), (0.38, 0.016, 0.02), 1)
    add_box(bp, (0.0, YB + 0.006, zc - 0.06), (0.38, 0.016, 0.02), 1)
    add_box(bp, (-0.18, YB + 0.006, zc), (0.02, 0.016, 0.10), 1)
    add_box(bp, (0.18, YB + 0.006, zc), (0.02, 0.016, 0.10), 1)
    plate = finish_obj("plate_rear", bp, [mats["M_Plate"], mats["M_Trim"]])
    return lights, plate


def build_exhaust(mats):
    bm = bmesh.new()
    for sx in (1, -1):
        add_tube(bm, sx * 0.50, 0.425, YF - 0.030, YF + 0.040, 0.034, 0.027, 0, 1, 32)
    return finish_obj("exhaust", bm, [mats["M_Chrome"], mats["M_Trim"]])


def liner(bm, mi):
    """Dark cabin liner 30 mm inside the body surface (closes the tub, hides the inner paint
    faces seen through the glass)."""
    for sg in (1, -1):
        P, N = [], []
        # the liner must not cross the rear wheel: behind s 2.85 it starts above the arch (z 0.74)
        for s in list(np.linspace(1.20, 2.85, 8)) + [2.95, 3.20, 3.50, 3.80]:
            rp, rn = [], []
            vlo = 0.12 if s < 2.9 else sv(s, 0.74)
            for v in np.linspace(vlo, 0.98, 16):
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
    add_box(bm, (0.0, 0.10, 0.38), (1.2, 2.60, 0.04), mi)  # cabin floor
    add_box(bm, (0.0, -0.78, 0.60), (1.4, 0.22, 0.12), mi)  # dash base
    add_ell(bm, (0.0, -0.78, 0.66), 0.74, 0.12, 0.20, True, mi)  # dash top, rounded
    add_box(bm, (-0.32, -0.72, 0.93), (0.22, 0.10, 0.08), mi)  # binnacle
    add_box(bm, (0.0, 0.10, 0.46), (0.20, 1.40, 0.12), mi)  # centre tunnel
    for sx in (-1, 1):
        x = sx * 0.32
        add_ell(bm, (x, -0.08, 0.52), 0.23, 0.25, 0.07, True, mi)  # seat cushion
        add_box(bm, (x, -0.08, 0.44), (0.20, 0.20, 0.06), mi)
        add_ell(bm, (x, 0.18, 0.88), 0.23, 0.06, 0.30, True, mi)  # seat back
        add_box(bm, (x, 0.18, 0.69), (0.40, 0.10, 0.28), mi)
        add_ell(bm, (x, 0.18, 1.07), 0.13, 0.07, 0.09, True, mi)  # headrest
        add_ell(bm, (x, 1.05, 0.54), 0.23, 0.22, 0.07, True, mi)  # rear seat cushion
        add_ell(bm, (x, 1.30, 0.88), 0.23, 0.06, 0.28, True, mi)  # rear seat back
        add_box(bm, (x, 1.30, 0.69), (0.40, 0.10, 0.28), mi)
    c = Vector((-0.32, -0.34, 0.90))
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
