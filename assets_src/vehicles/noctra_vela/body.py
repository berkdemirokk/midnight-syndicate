"""Noctra Vela body surface (hot hatch), same surface engine as the Sable R body.py.
Curve data and constants: docs/art/CAR_VELA_BRIEF.md.

Import-safe: importing this module does no scene work. Build and render with
  blender --background --factory-startup --python body.py
Pure maths (curves, surf, section) works without Blender.

Topology: every station s has the same half-section point list (44 points,
M = 43 half edges), mirrored to a 86-point ring. Section points are placed at
fixed indices: side anchors, then top breakpoints in x, so boundaries
(windscreen edge, rear-screen edge, engine-cover and bonnet lines, shoulder
groove) are grid lines for every station.
"""
import math
import os

import numpy as np

try:
    import bpy
    import bmesh
except ImportError:  # pure-maths import outside Blender
    bpy = None
    bmesh = None

HERE = os.path.dirname(os.path.abspath(__file__))
RENDER_DIR = os.path.join(HERE, "renders_stage1")
Y_OFFSET = 2.03  # blender y = s - 2.03 (axles at s 0.755 and 3.305, so y -1.275 and +1.275)
BODY_END = 3.94  # s of the last station before the tail cap


# ------------------------------------------------------------------ PCHIP curves
def _pchip(pts):
    """Monotone cubic Hermite (Fritsch-Carlson), scalar in, float out."""
    xs = np.array([p[0] for p in pts], float)
    ys = np.array([p[1] for p in pts], float)
    h = np.diff(xs)
    d = np.diff(ys) / h
    n = len(xs)
    m = np.zeros(n)
    for k in range(1, n - 1):
        if d[k - 1] * d[k] <= 0:
            m[k] = 0.0
        else:
            w1 = 2 * h[k] + h[k - 1]
            w2 = h[k] + 2 * h[k - 1]
            m[k] = (w1 + w2) / (w1 / d[k - 1] + w2 / d[k])

    def _end(h0, h1, d0, d1):
        mm = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
        if np.sign(mm) != np.sign(d0):
            mm = 0.0
        elif np.sign(d0) != np.sign(d1) and abs(mm) > abs(3 * d0):
            mm = 3 * d0
        return mm

    m[0] = _end(h[0], h[1], d[0], d[1])
    m[-1] = _end(h[-1], h[-2], d[-1], d[-2])

    def f(x):
        x = float(min(max(x, xs[0]), xs[-1]))
        i = min(max(int(np.searchsorted(xs, x, side="right")) - 1, 0), n - 2)
        t = (x - xs[i]) / h[i]
        h00 = 2 * t**3 - 3 * t**2 + 1
        h10 = t**3 - 2 * t**2 + t
        h01 = -2 * t**3 + 3 * t**2
        h11 = t**3 - t**2
        return float(h00 * ys[i] + h10 * h[i] * m[i] + h01 * ys[i + 1] + h11 * h[i] * m[i + 1])

    return f


_Z_TOP = _pchip([(0, .470), (0.05, .560), (0.15, .665), (0.45, .765), (0.755, .805), (1.00, .850),
                 (1.12, .900), (1.35, 1.035), (1.60, 1.195), (1.80, 1.320), (2.05, 1.395),
                 (2.30, 1.427), (2.65, 1.425), (3.00, 1.395), (3.22, 1.370), (3.38, 1.340),
                 (3.50, 1.270), (3.70, 1.050), (3.82, .985), (3.94, .950), (4.00, .940)])
_Z_BOT = _pchip([(0, .270), (0.12, .190), (0.40, .140), (0.80, .125), (3.30, .125), (3.65, .180),
                 (3.94, .360), (4.00, .380)])
_W_MAX = _pchip([(0, .640), (0.06, .800), (0.25, .885), (0.755, .920), (1.30, .858), (2.00, .835),
                 (2.60, .855), (3.305, .925), (3.60, .915), (3.76, .890), (3.88, .850), (3.94, .800), (4.00, .785)])
_Z_SH = _pchip([(0, .470), (0.08, .560), (0.20, .665), (0.45, .745), (0.755, .800), (1.20, .850),
                (1.80, .895), (2.40, .930), (3.00, .960), (3.50, .985), (3.75, .990), (3.94, .970), (4.00, .960)])
_N_TOP = _pchip([(0, 2.0), (1.00, 2.2), (1.30, 2.8), (3.00, 2.8), (3.90, 2.2), (4.00, 2.0)])
_SHELF = _pchip([(0, 0.0), (1.00, 0.0), (1.30, .050), (3.50, .050), (3.90, 0.0), (4.00, 0.0)])


def z_top(s):
    return _Z_TOP(s)


def z_bot(s):
    return _Z_BOT(s)


def w_max(s):
    return _W_MAX(s)


def z_sh(s):
    return _Z_SH(s)


def n_top(s):
    return _N_TOP(s)


def shelf(s):
    return _SHELF(s)


def xs_of(s):
    """Shoulder top x (half width where the shoulder break ends)."""
    return w_max(s) - 0.115


def xg_of(s):
    """x where the top rise starts (shelf inboard edge)."""
    return xs_of(s) - shelf(s)


def shelf_drop(s):
    return 0.005 * min(1.0, shelf(s) / 0.03)


# Greenhouse (lead, 2026-11-25). The cabin must be clearly narrower than the body: a shoulder
# shelf, then side glass leaning in, then a narrow crowned roof. With the glass starting at the
# widest shoulder the cabin read as a box sitting on the car.
CAB_SHELF_W = 0.06  # flat-ish shoulder top between the body side and the glass base
CAB_SHELF_DROP = 0.012  # the shelf falls this much toward the glass
CAB_TUMBLE_DEG = 12.0  # side glass lean from vertical
CAB_GLASS_EXP = 1.35  # >1: the glass is steepest at its base and rolls smoothly into the roof
ROOF_CROWN = 0.028  # roof edge sits this far below the roof centre (no flat slab)


def cab_blend(s):
    """R9: 0 outside the cabin, 1 across the greenhouse, smooth ramps at both ends."""
    return _smoothstep((s - 0.90) / 0.25) * _smoothstep((4.10 - s) / 0.25)


def cab_edges(s):
    """(glass base x, roof edge x, belt z) of the greenhouse section at station s."""
    zs, zt = z_sh(s), z_top(s)
    xg = xs_of(s) - CAB_SHELF_W
    zb = zs - CAB_SHELF_DROP
    h = max(zt - ROOF_CROWN - zb, 1e-6)
    xr = max(xg - h * np.tan(np.radians(CAB_TUMBLE_DEG)), 0.2)
    return xg, xr, zs


def _top_z_tumble(s, x):
    """Greenhouse section: shoulder shelf, leaning side glass, crowned roof (continuous slope)."""
    zs, zt = z_sh(s), z_top(s)
    xs = xs_of(s)
    xg = xs - CAB_SHELF_W  # glass base
    zb = zs - CAB_SHELF_DROP
    h = max(zt - ROOF_CROWN - zb, 1e-6)  # glass height up to the roof edge
    xr = max(xg - h * np.tan(np.radians(CAB_TUMBLE_DEG)), 0.2)  # roof edge
    if x >= xg:
        return zs - CAB_SHELF_DROP * (xs - x) / CAB_SHELF_W
    if x >= xr:
        u = (xg - x) / max(xg - xr, 1e-6)  # 0 at the glass base, 1 at the roof edge
        return zb + h * (1.0 - (1.0 - u) ** CAB_GLASS_EXP)
    q = x / xr
    return zt - ROOF_CROWN * q * q


def top_z(s, x):
    """Top surface height at station s and half-width x in [0, xs]."""
    b = cab_blend(s)
    if b > 0.0:
        z0, z1 = _top_z_dome(s, x), _top_z_tumble(s, x)
        return z0 + b * (z1 - z0)
    return _top_z_dome(s, x)


def _top_z_dome(s, x):
    zs, zt, n = z_sh(s), z_top(s), n_top(s)
    xs, xg = xs_of(s), xg_of(s)
    dr = shelf_drop(s)
    if x > xg:  # shelf: falls dr inward, fades in with the shelf
        return zs - dr * (xs - x) / max(shelf(s), 1e-9)
    q = (xg - x) / xg
    base = zs - dr
    return base + (zt - base) * (1.0 - (1.0 - q) ** n)


# ------------------------------------------------------------------ section layout
SIDE_INT = (1, 1, 2, 2, 2, 2, 2)  # interior points on side segments A0..A7
TOP_BP = ("sg_e1", "sg_c", "sg_e2", "sgo", "pwa", "bn_e1", "bn_c", "bn_e2",
          "en_e1", "en_c", "en_e2", "rs", "centre")
TOP_INT = (0, 0, 0, 2, 2, 2, 0, 0, 2, 0, 0, 2, 3)  # interior points before each top breakpoint
LAB_TOP0 = 10  # edge labels: side segments 0..6, top segments 10..21
FORCED_S = (1.12, 1.80, 3.38, 3.70, 2.80, 2.88)  # glazing boundaries as grid rows
CROSS_OFF = (-0.0025, -0.00125, 0.0, 0.00125, 0.0025)  # 5 mm groove, 2.5 mm bevel steps
CROSS_DEPTH = (0.0, 0.0, 0.0, 0.0, 0.0)  # cross panel grooves off: they made zigzag seams in engine
LONG_DEPTH = (0.0, 0.005, 0.0)  # edge, centre, edge of a longitudinal groove
# constant-s grooves: (s0, from breakpoint, to breakpoint)
CROSS_GROOVES = ((1.20, "A2", "A7"), (2.82, "A2", "A7"), (0.30, "A2", "A7"), (3.82, "A2", "A7"),
                 (0.30, "bn_e1", "M"), (1.08, "bn_e1", "M"))
# constant-v grooves: (breakpoint names, s from, s to)
LONG_GROOVES = ((("bn_e1", "bn_c", "bn_e2"), 0.30, 1.08),)
NOSE_K = 5
NOSE_FWD = 0.040
TAIL_DS = 0.050  # last tail ring; the tail is rounded over three rings, then capped flat
TAIL_RINGS = ((0.014, 0.984), (0.034, 0.950), (0.050, 0.905))  # (ds behind BODY_END, scale)


def _smoothstep(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def _scallop(s):
    """R5: door scallop depth (m) at station s, fades in and out between s 1.25 and 2.70."""
    if s < 1.25 or s > 2.80:
        return 0.0
    return 0.010 * _smoothstep((s - 1.25) / 0.20) * _smoothstep((2.80 - s) / 0.20)


def _side_anchors(s):
    zb, zs, w = z_bot(s), z_sh(s), w_max(s)
    xs, H = xs_of(s), z_sh(s) - z_bot(s)
    return [(0.0, zb), (w - 0.130, zb), (w - 0.065, zb + 0.045), (w - 0.022, zb + 0.30 * H),
            (w, zb + 0.62 * H), (w - 0.018, zs - 0.060), (w - 0.060, zs - 0.012), (xs, zs)]


def _half(s):
    """Half section (x >= 0) at station s, floor centre to top centre.

    Returns dict: X, Z (M+1 points), LAB (M edge labels), TAGS (name -> point index),
    V (arc-length fraction per point, 0 at floor centre, 1 at top centre).
    """
    A = _side_anchors(s)
    nA = len(A)
    T = []
    for k in range(nA):
        if k == 0:
            T.append((A[1][0] - A[0][0], A[1][1] - A[0][1]))
        elif k == nA - 1:
            T.append((A[-1][0] - A[-2][0], A[-1][1] - A[-2][1]))
        else:
            T.append(((A[k + 1][0] - A[k - 1][0]) / 2, (A[k + 1][1] - A[k - 1][1]) / 2))
    pts, labs, tags = [A[0]], [0], {"A0": 0}
    for i in range(7):
        P0, P1, T0, T1 = A[i], A[i + 1], T[i], T[i + 1]
        nint = SIDE_INT[i]
        for k in range(1, nint + 1):
            t = k / (nint + 1)
            if i == 0:  # floor: straight, no overshoot below the floor
                p = (P0[0] + (P1[0] - P0[0]) * t, P0[1] + (P1[1] - P0[1]) * t)
            else:
                h00 = 2 * t**3 - 3 * t**2 + 1
                h10 = t**3 - 2 * t**2 + t
                h01 = -2 * t**3 + 3 * t**2
                h11 = t**3 - t**2
                p = (h00 * P0[0] + h10 * T0[0] + h01 * P1[0] + h11 * T1[0],
                     h00 * P0[1] + h10 * T0[1] + h01 * P1[1] + h11 * T1[1])
            pts.append(p)
            labs.append(i)
        pts.append(P1)
        labs.append(i + 1 if i + 1 < 7 else LAB_TOP0)
        tags["A%d" % (i + 1)] = len(pts) - 1
    # R5: soft concave scallop along the door, centred at 45% of the side height
    sc = _scallop(s)
    if sc > 0.0:
        H = z_sh(s) - z_bot(s)
        zc = z_bot(s) + 0.45 * H
        for k in range(1, tags["A7"] + 1):
            x_, z_ = pts[k]
            pts[k] = (x_ - sc * math.exp(-((z_ - zc) / (0.22 * H)) ** 2), z_)
    # top breakpoints, non-increasing in x (accumulate-min keeps the order at the nose)
    xs = A[-1][0]
    # sgo: side-glass outer edge; pwa: windscreen edge, so the A-pillar is 70 mm wide in x.
    # shortcut: at s < 0.28 pwa falls under the bonnet line and those nodes collapse, nose only.
    raw = [xs - 0.0025, xs - 0.005, xs - 0.0075, xs - 0.05, xs - 0.10,
           0.6225, 0.62, 0.6175, 0.5025, 0.50, 0.4975, 0.42, 0.0]
    bx = np.minimum.accumulate(np.array(raw))
    xprev = xs
    for k, name in enumerate(TOP_BP):
        xk = float(bx[k])
        nint = TOP_INT[k]
        for m in range(1, nint + 1):
            x = xprev + (xk - xprev) * m / (nint + 1)
            pts.append((x, top_z(s, x)))
            labs.append(LAB_TOP0 + k)
        xprev = xk
        pts.append((xk, top_z(s, xk)))
        labs.append(LAB_TOP0 + k + 1 if k + 1 < len(TOP_BP) else -1)
        tags[name] = len(pts) - 1
    tags["M"] = len(pts) - 1
    P = np.array(pts, float)
    X, Z = P[:, 0], P[:, 1]
    seg = np.hypot(np.diff(X), np.diff(Z))
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    V = cum / cum[-1]
    return {"X": X, "Z": Z, "LAB": np.array(labs[:-1]), "TAGS": tags, "V": V}


def _normals2d(X, Z):
    tx, tz = np.gradient(X), np.gradient(Z)
    L = np.maximum(np.hypot(tx, tz), 1e-9)
    return tz / L, -tx / L  # outward for the floor -> side -> top path


def section(s):
    """Half section (x, z) points at station s, shape (M+1, 2)."""
    h = _half(s)
    return np.stack([h["X"], h["Z"]], axis=1)


def surf_point(s, v):
    """Surface point on the +X half: station s, around-section parameter v in [0, 1]."""
    h = _half(s)
    x = np.interp(v, h["V"], h["X"])
    z = np.interp(v, h["V"], h["Z"])
    return np.array([x, s - Y_OFFSET, z])


def surf(s, v):
    """Surface point and outward unit normal at (s, v), +X half. Returns (point, normal)."""
    v = min(max(v, 0.0), 1.0)
    p = surf_point(s, v)
    ds, dv = 1e-4, 1e-3
    ps = surf_point(s + ds, v) - surf_point(s - ds, v)
    pv = surf_point(s, min(v + dv, 1.0)) - surf_point(s, max(v - dv, 0.0))
    n = np.cross(ps, pv)
    n = n / max(np.linalg.norm(n), 1e-12)
    zc = 0.5 * (z_bot(s) + z_top(s))
    if np.dot(n, np.array([p[0], 0.0, p[2] - zc])) < 0:
        n = -n
    return p, n


def surf_xz(s, x_on_top):
    """Point and normal on the top surface at half-width x (x in [0, xs])."""
    x = min(max(x_on_top, 0.0), xs_of(s))
    z = top_z(s, x)
    slope = (top_z(s, x + 1e-4) - top_z(s, max(x - 1e-4, 0.0))) / (x + 1e-4 - max(x - 1e-4, 0.0))
    n = np.array([-slope, 0.0, 1.0])
    return np.array([x, s - Y_OFFSET, z]), n / np.linalg.norm(n)


def surf_mirror(s, v):
    """Same as surf on the -X half."""
    p, n = surf(s, v)
    return np.array([-p[0], p[1], p[2]]), np.array([-n[0], n[1], n[2]])


def surf_xz_mirror(s, x_on_top):
    p, n = surf_xz(s, x_on_top)
    return np.array([-p[0], p[1], p[2]]), np.array([-n[0], n[1], n[2]])


# ------------------------------------------------------------------ mesh shell
def _station_plan():
    base = np.concatenate([np.linspace(0.0, 0.30, 14), np.linspace(0.30, 1.20, 18)[1:],
                           np.linspace(1.20, 2.10, 24)[1:], np.linspace(2.10, 3.70, 32)[1:],
                           np.linspace(3.70, BODY_END, 18)[1:]])
    extra = list(FORCED_S)
    for s0, _, _ in CROSS_GROOVES:
        extra.extend(s0 + o for o in CROSS_OFF)
    return np.unique(np.round(np.concatenate([base, np.array(extra)]), 6))


def _row_depth(s, tags, M):
    """Groove depth (m) per half point at station s."""
    d = np.zeros(M + 1)
    for s0, lo, hi in CROSS_GROOVES:
        for off, dep in zip(CROSS_OFF, CROSS_DEPTH):
            if abs(s - (s0 + off)) < 1e-6:
                a, b = tags[lo], tags[hi]
                d[a:b + 1] = np.maximum(d[a:b + 1], dep)
    for names, sa, sb in LONG_GROOVES:
        if sa - 1e-6 <= s <= sb + 1e-6:
            for nm, dep in zip(names, LONG_DEPTH):
                d[tags[nm]] = max(d[tags[nm]], dep)
    return d


def _ring_arrays(X, Z, dh):
    """Mirror a half section into a 2M-slot ring (slot r: r<=M right, else left)."""
    M = len(X) - 1
    jj = np.concatenate([np.arange(M + 1), np.arange(M - 1, 0, -1)])
    sg = np.concatenate([np.ones(M + 1), -np.ones(M - 1)])
    nx2, nz2 = _normals2d(X, Z)
    seg = np.hypot(np.diff(X), np.diff(Z))
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    V = cum / cum[-1]
    return (X[jj] * sg, Z[jj], nx2[jj] * sg, nz2[jj], V[jj], dh[jj])


def _shell_arrays(rings):
    """rings: list of (s_value, X, Z, depth). Returns positions, faces, attribute arrays."""
    R = len(rings)
    M = len(rings[0][1]) - 1
    N = 2 * M
    pos = np.zeros((R * N + 2, 3))
    s_a = np.zeros(R * N + 2)
    v_a = np.zeros(R * N + 2)
    g_a = np.zeros(R * N + 2)
    gn_a = np.zeros((R * N + 2, 3))
    for i, (s, X, Z, dh) in enumerate(rings):
        xr, zr, nxr, nzr, vr, gr = _ring_arrays(X, Z, dh)
        sl = slice(i * N, (i + 1) * N)
        pos[sl, 0], pos[sl, 1], pos[sl, 2] = xr, s - Y_OFFSET, zr
        s_a[sl], v_a[sl], g_a[sl] = s, vr, gr
        gn_a[sl, 0], gn_a[sl, 2] = nxr, nzr
    c_nose, c_tail = R * N, R * N + 1
    pos[c_nose] = pos[0:N].mean(axis=0)
    pos[c_tail] = pos[(R - 1) * N:R * N].mean(axis=0)
    s_a[c_nose], s_a[c_tail] = rings[0][0], rings[-1][0]
    e = np.arange(N)
    quads = []
    for i in range(R - 1):
        quads.append(np.stack([i * N + e, i * N + (e + 1) % N, (i + 1) * N + (e + 1) % N,
                               (i + 1) * N + e], axis=1))
    quads = np.concatenate(quads, axis=0)
    # orientation: outward at a mid-body right-side quad
    mid = quads[(R // 2) * N + 2]
    a, b, d = pos[mid[0]], pos[mid[1]], pos[mid[3]]
    nrm = np.cross(b - a, d - a)
    ctr = pos[mid].mean(axis=0)
    if np.dot(nrm, ctr - np.array([0.0, ctr[1], 0.6])) < 0:
        quads = quads[:, ::-1]
    fan_nose = np.stack([np.full(N, c_nose), e, (e + 1) % N], axis=1)
    fan_tail = np.stack([np.full(N, c_tail), (R - 1) * N + (e + 1) % N, (R - 1) * N + e], axis=1)
    if np.dot(np.cross(pos[fan_nose[0][1]] - pos[c_nose], pos[fan_nose[0][2]] - pos[c_nose]),
              np.array([0.0, -1.0, 0.0])) < 0:
        fan_nose = fan_nose[:, ::-1].copy()  # nose cap faces forward (-Y)
    if np.dot(np.cross(pos[fan_tail[0][1]] - pos[c_tail], pos[fan_tail[0][2]] - pos[c_tail]),
              np.array([0.0, 1.0, 0.0])) < 0:
        fan_tail = fan_tail[:, ::-1].copy()  # tail cap faces aft (+Y)
    return pos, quads, fan_nose, fan_tail, s_a, v_a, g_a, gn_a


def build_shell():
    """Closed quad-grid body. Vertex attributes: s (station), v (around-section 0..1),
    groove (depth in m to push inward), gn (2D inward-pushing normal, vector).
    Face topology is grid-aligned to the glazing and groove boundaries.
    """
    S = _station_plan()
    h0 = _half(0.0)
    M = len(h0["X"]) - 1
    rings = []
    Xh, Zh = h0["X"], h0["Z"]
    cz = float(Zh.mean())
    zero = np.zeros(M + 1)
    for k in range(NOSE_K, 0, -1):  # nose closure: far ring first, s = 0 ring follows
        a = math.radians(k / NOSE_K * 80.0)
        sx, sz = max(math.cos(a), 0.55), math.cos(a)
        rings.append((-NOSE_FWD * math.sin(a), Xh * sx, cz + (Zh - cz) * sz, zero))
    # station rings
    for s in S:
        h = _half(s)
        dh = _row_depth(float(s), h["TAGS"], M)
        rings.append((float(s), h["X"], h["Z"], dh))
    # tail: one station 18 mm back, scaled, then a flat cap
    hT = _half(BODY_END)
    cT = float(hT["Z"].mean())
    for ds, sc in TAIL_RINGS:
        rings.append((BODY_END + ds, hT["X"] * sc, cT + (hT["Z"] - cT) * sc, zero))
    pos, quads, fan_nose, fan_tail, s_a, v_a, g_a, gn_a = _shell_arrays(rings)
    faces = [list(map(int, q)) for q in quads] + [list(map(int, t)) for t in fan_nose] + \
            [list(map(int, t)) for t in fan_tail]
    me = bpy.data.meshes.new("body")
    me.from_pydata(pos.tolist(), [], faces)
    me.update()
    for name, arr in (("s", s_a), ("v", v_a), ("groove", g_a)):
        at = me.attributes.new(name, "FLOAT", "POINT")
        at.data.foreach_set("value", arr.astype(np.float32))
    at = me.attributes.new("gn", "FLOAT_VECTOR", "POINT")
    at.data.foreach_set("vector", gn_a.astype(np.float32).ravel())
    ob = bpy.data.objects.new("body", me)
    bpy.context.collection.objects.link(ob)
    print("SHELL verts %d faces %d rings %d half_pts %d" % (len(me.vertices), len(me.polygons), len(rings), M + 1))
    return ob


def cut_panel_lines(obj):
    """Push groove vertices inward along their normal (grooves are grid rows/lines,
    5 mm wide and 5 mm deep). Run before the boolean."""
    me = obj.data
    n = len(me.vertices)
    co = np.empty(n * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    g = np.empty(n, np.float32)
    me.attributes["groove"].data.foreach_get("value", g)
    gn = np.empty(n * 3, np.float32)
    me.attributes["gn"].data.foreach_get("vector", gn)
    gn = gn.reshape(n, 3)
    # push along the dominant axis only: per-vertex section normals jitter at anchors and made zigzag seams
    side = np.abs(gn[:, 0]) >= np.abs(gn[:, 2])
    gn = np.where(side[:, None], np.stack([np.sign(gn[:, 0]), np.zeros(n), np.zeros(n)], axis=1),
                  np.stack([np.zeros(n), np.zeros(n), np.sign(gn[:, 2])], axis=1)).astype(np.float32)
    co = co - gn * g[:, None]
    me.vertices.foreach_set("co", co.ravel())
    me.update()
    print("PANEL grooves pushed on %d vertices" % int(np.count_nonzero(g)))


# ------------------------------------------------------------------ mesh helpers
def _co(me):
    n = len(me.vertices)
    a = np.empty(n * 3, np.float32)
    me.vertices.foreach_get("co", a)
    return a.reshape(n, 3).astype(float)


def _polys(me):
    return [tuple(p.vertices) for p in me.polygons]


def _new_mesh(name, co, polys, mats=None):
    used = np.unique(np.concatenate([np.array(p, int) for p in polys]))
    remap = -np.ones(len(co), int)
    remap[used] = np.arange(len(used))
    newp = [[int(remap[v]) for v in p] for p in polys]
    me = bpy.data.meshes.new(name)
    me.from_pydata(co[used].tolist(), [], newp)
    me.update()
    if mats is not None and len(mats):
        me.polygons.foreach_set("material_index", np.asarray(mats, np.int32))
    return me, used


def _centre_normal(co, pv):
    p0, p1, p2 = co[pv[0]], co[pv[1]], co[pv[2]]
    n = np.cross(p1 - p0, p2 - p0)
    return n / max(np.linalg.norm(n), 1e-12)


def _set_body_mesh(obj, me):
    old = obj.data
    obj.data = me
    bpy.data.meshes.remove(old)


# ------------------------------------------------------------------ arches
# (axle y, tyre radius, arch cylinder start x). Front starts at 0.66, not the spec's 0.50:
# the front fender top is only about 0.70 at x 0.50 to 0.59, below the arch crown (0.718),
# so a 0.50 start punched holes through the top surface. Rear keeps 0.50 (no breakthrough).
ARCH_GAP = 0.034  # arch radius minus tyre radius: the tyre fills the opening
ARCH = ((-1.275, 0.320, 0.60), (1.275, 0.320, 0.58))
ARCH_X1 = 1.30


def _is_well(c, n, axle_y, r, x0):
    """Face lies on the arch cylinder (inner well) and faces the axle."""
    dy, dz = c[1] - axle_y, c[2] - r
    rad = math.hypot(dy, dz)
    if abs(rad - (r + ARCH_GAP)) > 0.0025 or not (x0 - 0.005 <= abs(c[0]) <= ARCH_X1 + 0.005):
        return False
    return (n[1] * dy + n[2] * dz) < -0.4 * rad * np.linalg.norm(n)


def _well_flags(co, polys):
    flags = []
    for pv in polys:
        c = co[list(pv)].mean(axis=0)
        n = _centre_normal(co, pv)
        f = False
        for axle_y, r, x0 in ARCH:
            if _is_well(c, n, axle_y, r, x0):
                f = True
        flags.append(f)
    return flags


def _is_back_wall(c, n):
    """Face is the inboard end wall of an arch (left by the boolean), facing outboard."""
    for axle_y, r, x0 in ARCH:
        if (abs(abs(c[0]) - x0) < 0.004 and abs(n[0]) > 0.9 and n[0] * c[0] > 0
                and math.hypot(c[1] - axle_y, c[2] - r) < r + 0.06):
            return True
    return False


def cut_arches(body):
    """Exact boolean wheel arches, bevelled rim, wells and floor moved to 'underbody'.
    Returns the underbody object."""
    for axle_y, r, x0 in ARCH:
        for sx in (1, -1):
            bpy.ops.mesh.primitive_cylinder_add(vertices=72, radius=r + ARCH_GAP, depth=ARCH_X1 - x0,
                                                location=(sx * (x0 + ARCH_X1) / 2, axle_y, r),
                                                rotation=(0, math.pi / 2, 0))
            cyl = bpy.context.active_object
            bpy.context.view_layer.objects.active = body
            mod = body.modifiers.new("arch", "BOOLEAN")
            mod.operation = "DIFFERENCE"
            mod.object = cyl
            mod.solver = "EXACT"
            bpy.ops.object.modifier_apply(modifier=mod.name)
            bpy.data.objects.remove(cyl, do_unlink=True)
    co = _co(body.data)
    polys = _polys(body.data)
    flags = _well_flags(co, polys)
    print("ARCH well faces before bevel:", sum(flags))
    try:
        bm = bmesh.new()
        bm.from_mesh(body.data)
        bm.faces.ensure_lookup_table()
        wells = set(i for i, f in enumerate(flags) if f)
        edges = set()
        for i in wells:
            f = bm.faces[i]
            for e in f.edges:
                lf = e.link_faces
                if len(lf) == 2 and any(x.index not in wells for x in lf):
                    edges.add(e)
        bmesh.ops.bevel(bm, geom=list(edges), offset=0.012, segments=3, affect="EDGES",
                        clamp_overlap=True)
        bm.to_mesh(body.data)
        bm.free()
        print("ARCH rim bevel edges:", len(edges))
    except Exception as ex:  # reported, not hidden
        print("ARCH rim bevel FAILED:", str(ex)[:200])
    co = _co(body.data)
    polys = _polys(body.data)
    flags = _well_flags(co, polys)
    under = []
    under_mat = []  # slot 0 M_Trim floor, slot 1 M_Interior liner (well cylinder and end wall)
    keep = []
    for pv, f in zip(polys, flags):
        c = co[list(pv)].mean(axis=0)
        n = _centre_normal(co, pv)
        s = c[1] + Y_OFFSET
        is_floor = c[2] < z_bot(min(max(s, 0.0), BODY_END)) + 0.006 and n[2] < -0.5
        back = _is_back_wall(c, n)
        if f or back or is_floor:
            under.append(pv)
            under_mat.append(1 if (f or back) else 0)
        else:
            keep.append(pv)
    me_body, _ = _new_mesh("body", co, keep)
    _set_body_mesh(body, me_body)
    me_u, _ = _new_mesh("underbody", co, under, under_mat)
    ub = bpy.data.objects.new("underbody", me_u)
    bpy.context.collection.objects.link(ub)
    print("ARCH underbody faces %d (wells + floor)" % len(under))
    return ub


# ------------------------------------------------------------------ glazing
# Windscreen and hatch glass are strips of the top surface between two constant-s cuts and inside
# |x| <= WS_EDGE_X. The side glass is the leaning surface between the glass base and the roof,
# bounded by two raked planes (A-pillar, C-pillar) and the belt plane, so every window edge is a
# straight line. A black B-pillar band (glass slot 1) splits the door glass from the quarter glass.
WS_S = (1.12, 1.80)
RS_S = (3.38, 3.70)
B_PILLAR = (2.80, 2.88)
DLO_REF_S = 2.40  # rake planes are written for the belt height at this s
DLO_FRONT_S, DLO_FRONT_RAKE = 1.30, 1.45  # front edge s at the reference belt height, and ds/dz going up
DLO_REAR_S, DLO_REAR_RAKE = 3.62, 0.70  # rear edge s at the reference belt height, and -ds/dz going up
DLO_BELT_GAP = 0.030  # glass starts this far above the shoulder
WS_EDGE_X = 0.50  # windscreen and hatch glass end at this half-width ...
SIDE_TOP_X = 0.53  # ... side glass starts here: the black band between is the roof rail
BELT_S0, BELT_S1 = 1.4, 3.4  # the belt line is the straight line through z_sh + gap at these two s


def belt_z(s):
    """Window bottom line: a straight line along the shoulder (a plane, so it can be cut cleanly)."""
    z0 = z_sh(BELT_S0) + DLO_BELT_GAP
    z1 = z_sh(BELT_S1) + DLO_BELT_GAP
    return z0 + (z1 - z0) * (s - BELT_S0) / (BELT_S1 - BELT_S0)


def _dlo_zref():
    return z_sh(DLO_REF_S) + DLO_BELT_GAP


def _in_side_dlo(s, x, z):
    if not (1.4 <= s <= 3.9):
        return False
    xg, xr, zs = cab_edges(s)
    if z <= belt_z(s) or not (SIDE_TOP_X < x < xg - 0.005):
        return False
    dz = z - _dlo_zref()
    return DLO_FRONT_S + DLO_FRONT_RAKE * dz <= s <= DLO_REAR_S - DLO_REAR_RAKE * dz


def _cabin_faces(bm):
    out = []
    for f in bm.faces:
        c = f.calc_center_median()
        s = c.y + Y_OFFSET
        if 1.25 <= s <= 3.95 and c.z > z_sh(min(max(s, 0.0), BODY_END)) - 0.02:
            out.append(f)
    return out


def _cut_dlo_edges(body):
    """Cut the cabin top along the raked A- and C-pillar planes, the belt plane, the glass ends
    (constant s) and the pillar lines (constant |x|), so window edges are straight lines instead of
    a stair-step of whole faces."""
    bm = bmesh.new()
    bm.from_mesh(body.data)

    def cut(plane_co, plane_no):
        geom = _cabin_faces(bm)
        if not geom:
            return
        verts = list({v for f in geom for v in f.verts})
        edges = list({e for f in geom for e in f.edges})
        bmesh.ops.bisect_plane(bm, geom=verts + edges + geom, plane_co=plane_co, plane_no=plane_no)

    zb = _dlo_zref()
    for s0, k in ((DLO_FRONT_S, -DLO_FRONT_RAKE), (DLO_REAR_S, DLO_REAR_RAKE)):
        cut((0.0, s0 - Y_OFFSET, zb), (0.0, 1.0, k))
    b = (belt_z(BELT_S1) - belt_z(BELT_S0)) / (BELT_S1 - BELT_S0)  # belt z = z0 + b*(s - s0): normal (0, -b, 1)
    cut((0.0, BELT_S0 - Y_OFFSET, belt_z(BELT_S0)), (0.0, -b, 1.0))
    for sc in FORCED_S:
        cut((0.0, sc - Y_OFFSET, 0.0), (0.0, 1.0, 0.0))
    for xc in (WS_EDGE_X, SIDE_TOP_X, -WS_EDGE_X, -SIDE_TOP_X):
        cut((xc, 0.0, 0.0), (1.0, 0.0, 0.0))
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()


def _greenhouse_slot(co, pv):
    """Slot for a paint face that is not glass: 2 gloss-black pillar and roof rail (everything above the
    shoulder outside |x| 0.50, i.e. A/B/C pillars and the rail), 0 body paint (roof, bonnet)."""
    c = co[list(pv)].mean(axis=0)
    s, x, z = c[1] + Y_OFFSET, abs(c[0]), c[2]
    if not (1.25 <= s <= 3.95) or z <= belt_z(s) + 0.012:
        return 0
    if x > WS_EDGE_X + 0.002 and (s < 2.90 or x < SIDE_TOP_X + 0.001):
        return 2  # A/B pillar and roof rail; behind the B pillar the quarter panel is paint
    return 0


def split_glazing(body):
    """Move the glazing faces to a 'glass' object (border vertices stay on the body surface, the
    interior sinks 2 mm). Glass slot 1 (M_Trim) is the black B-pillar band."""
    co = _co(body.data)
    polys = _polys(body.data)
    sel = {}
    zr = _dlo_zref()
    for pi, pv in enumerate(polys):
        c = co[list(pv)].mean(axis=0)
        s = c[1] + Y_OFFSET
        x, z = abs(c[0]), c[2]
        if s < 1.25 or s > 3.95:
            continue
        xs, zs = xs_of(s), z_sh(s)
        if not (x < xs - 0.0015 and z > zs - 0.015):  # top surface only
            continue
        if WS_S[0] <= s <= WS_S[1] and x <= WS_EDGE_X:
            sel[pi] = "windscreen"
        elif RS_S[0] <= s <= RS_S[1] and x <= WS_EDGE_X:
            sel[pi] = "rear"
        elif _in_side_dlo(s, x, z):
            sel[pi] = "side"
    for pi in list(sel):  # drop stray side-glass quads that face inward or up (they showed as grey wedges)
        pv = polys[pi]
        c = co[list(pv)].mean(axis=0)
        n = _centre_normal(co, pv)
        if abs(c[0]) > WS_EDGE_X + 0.01 and n[0] * np.sign(c[0]) < 0.05 and n[2] < 0.5:
            del sel[pi]
    gl = sorted(sel)
    print("GLASS faces", len(gl), {k: list(sel.values()).count(k) for k in set(sel.values())})
    gset = set(gl)
    ecount = {}
    for pi in gl:
        pv = polys[pi]
        for k in range(len(pv)):
            ek = tuple(sorted((pv[k], pv[(k + 1) % len(pv)])))
            ecount[ek] = ecount.get(ek, 0) + 1
    mats = []
    for pi in gl:
        c = co[list(polys[pi])].mean(axis=0)
        s = c[1] + Y_OFFSET
        mats.append(1 if (sel[pi] == "side" and B_PILLAR[0] <= s <= B_PILLAR[1]) else 0)
    vn = np.zeros_like(co)
    for pi in gl:
        pv = polys[pi]
        n = _centre_normal(co, pv)
        for v in pv:
            vn[v] += n
    lens = np.linalg.norm(vn, axis=1, keepdims=True)
    vn = vn / np.maximum(lens, 1e-12)
    depth = np.full(len(co), 0.002)
    for ek, cnt in ecount.items():
        if cnt == 1:
            depth[ek[0]] = 0.0
            depth[ek[1]] = 0.0
    co_g = co - depth[:, None] * vn
    me_g, _ = _new_mesh("glass", co_g, [polys[pi] for pi in gl], mats)
    keep = [polys[i] for i in range(len(polys)) if i not in gset]
    me_b, _ = _new_mesh("body", co, keep, [_greenhouse_slot(co, pv) for pv in keep])
    _set_body_mesh(body, me_b)
    glass = bpy.data.objects.new("glass", me_g)
    bpy.context.collection.objects.link(glass)
    return glass


# ------------------------------------------------------------------ shading
def finish_shading(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    mod = obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    mod.keep_sharp = True


# ------------------------------------------------------------------ checks
def checks(body_obj=None):
    """Prints and returns the spec dimension checks. Raises if any is off by more than 3%."""
    rows = []

    def add(name, value, target):
        err = abs(value - target) / target
        rows.append((name, round(value, 4), target, round(err * 100, 2), err <= 0.03))

    s_grid = np.linspace(0.0, BODY_END, 801)
    add("width_max_w", 2 * max(w_max(s) for s in s_grid), 1.80)
    add("height_max_ztop", max(z_top(s) for s in s_grid), 1.42)
    if body_obj is not None:
        d = body_obj.dimensions
        add("length_mesh_incl_nose_tail", float(d.y), 4.05)
        add("width_mesh", float(d.x), 1.80)
        add("height_mesh_above_ground", max(v[2] for v in body_obj.bound_box), 1.42)
    bad = []
    for r in rows:
        print("CHECK %-28s value %8.4f target %7.3f err %5.2f%% %s" % (r[0], r[1], r[2], r[3], "ok" if r[4] else "FAIL"))
        if not r[4]:
            bad.append(r[0])
    if bad:
        raise RuntimeError("dimension checks off by more than 3%%: %s" % bad)
    return rows


# ------------------------------------------------------------------ materials, wheels, render
def _lin(c):
    return tuple(float(v) / 255.0 for v in c)


def _srgb_to_lin(c):
    out = []
    for v in c:
        out.append(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4)
    return tuple(out) + (1.0,)


def _principled(name, base_srgb, metallic=0.0, rough=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = _srgb_to_lin(base_srgb)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    return m, b


def make_materials():
    mats = {}
    m, b = _principled("M_Paint", _lin((0x8E, 0x0F, 0x1E)), 0.85, 0.32)
    b.inputs["Coat Weight"].default_value = 1.0
    b.inputs["Coat Roughness"].default_value = 0.04
    mats["M_Paint"] = m
    # tint lifted from #0A0F12 so the panes read against the dark studio (deviation, see notes)
    m, b = _principled("M_Glass", _lin((0x4A, 0x62, 0x6C)), 0.0, 0.03)  # P1: lighter tint, interior reads
    b.inputs["Alpha"].default_value = 0.35  # brief value; lets the seats show through the glass
    m.surface_render_method = "BLENDED"
    mats["M_Glass"] = m
    m, b = _principled("M_LightRear", _lin((0xFF, 0x1A, 0x1A)), 0.0, 0.2)
    b.inputs["Emission Color"].default_value = _srgb_to_lin(_lin((0xFF, 0x1A, 0x1A)))
    b.inputs["Emission Strength"].default_value = 4.0
    mats["M_LightRear"] = m
    m, b = _principled("M_Plate", _lin((0x30, 0x32, 0x36)), 0.0, 0.4)
    mats["M_Plate"] = m
    m, b = _principled("M_Interior", _lin((0x2A, 0x2C, 0x30)), 0.0, 0.7)
    mats["M_Interior"] = m
    m, b = _principled("M_Trim", _lin((0x0C, 0x0C, 0x0D)), 0.0, 0.5)  # P4: satin black trim
    b.inputs["Specular IOR Level"].default_value = 0.08  # the 520 W strip light must not grey the black parts
    mats["M_Trim"] = m
    m, b = _principled("M_Tire", _lin((0x1A, 0x1A, 0x1C)), 0.0, 0.85)
    mats["M_Tire"] = m
    m, b = _principled("M_Clay", (0.5, 0.5, 0.5), 0.0, 0.6)
    mats["M_Clay"] = m
    m, b = _principled("M_Floor", _lin((0x14, 0x15, 0x1A)), 0.0, 0.3)  # P9: softer key glare on the floor
    mats["M_Floor"] = m
    return mats


def _assign(obj, mats):
    obj.data.materials.clear()
    for m in mats:
        obj.data.materials.append(m)


def setup_scene(mats):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    try:
        sc.eevee.taa_render_samples = 48
    except AttributeError as ex:
        print("EEVEE samples prop:", ex)
    sc.world = bpy.data.worlds.new("studio")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.004, 0.005, 0.008, 1)
    fl = bpy.data.meshes.new("floor")
    fl_bm = bpy.data.objects.new("floor", fl)
    sc.collection.objects.link(fl_bm)
    fl.from_pydata([(-30, -30, 0), (30, -30, 0), (30, 30, 0), (-30, 30, 0)], [], [(0, 1, 2, 3)])
    fl.materials.append(mats["M_Floor"])

    def area(name, loc, rot, size, energy, col, sy=None):
        l = bpy.data.lights.new(name, "AREA")
        l.energy, l.color = energy, col
        l.shape = "RECTANGLE"
        l.size, l.size_y = size, (sy or size)
        o = bpy.data.objects.new(name, l)
        o.location, o.rotation_euler = loc, rot
        sc.collection.objects.link(o)

    # P9: key lowered and moved toward the nose so roof and bonnet do not clip to white
    # round 8: same power on a larger area = same diffuse fill, dimmer mirror peak on bonnet and roof
    area("key", (-4.2, -4.6, 2.6), (math.radians(68), 0, math.radians(-35)), 14, 18, (0.85, 0.92, 1.0))
    # P9: front fill lights the nose face (the front three-quarter was too dark)
    area("front_fill", (-3.6, -6.0, 1.3), (math.radians(80), 0, math.radians(-30)), 3.0, 120, (0.92, 0.95, 1.0))
    area("strip", (4.2, 0.0, 1.9), (0, math.radians(90), 0), 0.6, 520, (1, 1, 1), 9.0)
    area("rim", (3.0, 5.5, 3.0), (math.radians(-60), 0, math.radians(150)), 2.5, 500, (1.0, 0.75, 0.5))
    area("top", (0, 0, 6.0), (0, 0, 0), 5.0, 14, (1, 1, 1), 10.0)  # round 8: larger, dimmer (was the bonnet streak)
    # rear fill: lights the flat tail fascia (faces +Y) from behind, pointing -Y
    area("rearfill", (0.0, 6.0, 1.1), (math.radians(-90), 0, 0), 3.0, 110, (1.0, 0.95, 0.9))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 60
    sc.collection.objects.link(cam)
    sc.camera = cam
    tgt = bpy.data.objects.new("tgt", None)
    tgt.location = (0, 0, 0.55)
    sc.collection.objects.link(tgt)
    c = cam.constraints.new("TRACK_TO")
    c.target = tgt
    c.track_axis = "TRACK_NEGATIVE_Z"
    c.up_axis = "UP_Y"
    return sc, cam, tgt


VIEWS = {
    "front34": (-6.2, -6.6, 1.00),
    "rear34": (6.2, 6.6, 1.00),
    "side": (9.0, 0.0, 0.85),
    "top": (0.0, 0.01, 11.0),
    "front_low": (-2.2, -7.4, 0.35),
}


def render_views(sc, cam, views, prefix=""):
    paths = {}
    for name, loc in views.items():
        cam.location = loc
        out = os.path.join(RENDER_DIR, prefix + name + ".png")
        sc.render.filepath = out
        bpy.ops.render.render(write_still=True)
        paths[name] = out
        print("RENDERED", out)
    return paths


def contact_sheet(order, out_path):
    """3 x 2 grid of 800 x 450 cells on a 2400 x 1350 canvas, dark gutter."""
    W, H = 2400, 1350
    canvas = np.zeros((H, W, 4), np.float32)
    canvas[:, :, :3] = np.array([0x05, 0x06, 0x0A], np.float32) / 255.0
    canvas[:, :, 3] = 1.0
    for k, path in enumerate(order):
        img = bpy.data.images.load(path, check_existing=False)
        w, h = img.size
        px = np.empty(w * h * 4, np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)
        small = px.reshape(h // 2, 2, w // 2, 2, 4).mean(axis=(1, 3))  # 800 x 450
        col, row = k % 3, k // 3
        x0 = col * 800
        y0 = 150 + row * 600  # rows at y 150 and 750 (blender images are bottom-up)
        canvas[H - y0 - 450:H - y0, x0:x0 + 800] = small  # both bottom-up
        bpy.data.images.remove(img)
    out = bpy.data.images.new("contact", W, H, alpha=True)
    out.pixels.foreach_set(canvas.ravel())
    out.filepath_raw = out_path
    out.file_format = "PNG"
    out.save()
    print("CONTACT", out_path)


def _box(bm, c, sx, sy, sz):
    """Closed box, 8 verts, 6 quads, centre c, sizes sx sy sz."""
    cx, cy, cz = c
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    vs = [bm.verts.new((cx + a * hx, cy + b * hy, cz + d * hz))
          for a in (-1, 1) for b in (-1, 1) for d in (-1, 1)]
    for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        bm.faces.new([vs[i] for i in q])
