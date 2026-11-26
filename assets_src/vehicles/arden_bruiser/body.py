"""Arden Bruiser body surface (docs/art/CAR_BRUISER_BRIEF.md). Surface engine of the hero car, own curve data.

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
Y_OFFSET = 2.375  # blender y = s - 2.375 (axles at y -1.425 / +1.425)


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


L_TOTAL = 4.80  # station s runs 0 at the nose to L_TOTAL at the tail (overall 4.85 with nose cap and tail ring); curves are defined to 4.85
_Z_TOP = _pchip([(0, .700), (0.10, .775), (0.40, .815), (0.95, .865), (1.40, .895), (1.80, .925),
                 (2.00, 1.060), (2.25, 1.235), (2.50, 1.335), (2.80, 1.358), (3.10, 1.340),
                 (3.45, 1.215), (3.75, 1.075), (4.00, .985), (4.20, .935), (4.45, .940),
                 (4.62, .975), (4.74, .958), (4.85, .880)])
_Z_BOT = _pchip([(0, .270), (0.15, .190), (0.50, .135), (4.00, .135), (4.25, .205), (4.85, .500)])
_W_MAX = _pchip([(0, .735), (0.06, .830), (0.25, .915), (0.95, .958), (1.45, .915), (2.40, .868),
                 (3.10, .930), (3.80, .960), (4.25, .940), (4.60, .880), (4.85, .800)])
_Z_SH = _pchip([(0, .640), (0.12, .700), (0.50, .760), (0.95, .815), (1.50, .855), (2.00, .895),
                (2.70, .925), (3.20, .950), (3.80, .965), (4.30, .945), (4.85, .900)])
_N_TOP = _pchip([(0, 2.0), (1.10, 2.2), (1.70, 2.8), (2.30, 3.0), (3.00, 2.9), (3.70, 2.6), (4.85, 2.0)])
_SHELF = _pchip([(0, 0.0), (1.50, 0.0), (1.90, .045), (3.60, .050), (4.20, 0.0), (4.85, 0.0)])
BULGE_H = 0.034  # power bulge height on the bonnet centre line
BULGE_HW = 0.30  # half width of the bulge


def bulge(s, x):
    """Power bulge added to the bonnet: rises from s 0.40, full height 0.75 to 1.40, gone by 1.75."""
    if s <= 0.40 or s >= 1.75 or x >= BULGE_HW:
        return 0.0
    ramp = _smoothstep((s - 0.40) / 0.35) * _smoothstep((1.75 - s) / 0.35)
    u = x / BULGE_HW
    return BULGE_H * ramp * (1.0 - u * u) ** 2


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
CAB_SHELF_W = 0.12  # flat-ish shoulder top between the body side and the glass base
CAB_SHELF_DROP = 0.012  # the shelf falls this much toward the glass
CAB_TUMBLE_DEG = 22.0  # side glass lean from vertical
CAB_GLASS_EXP = 1.35  # >1: the glass is steepest at its base and rolls smoothly into the roof
ROOF_CROWN = 0.03  # roof edge sits this far below the roof centre (no flat slab)


def cab_blend(s):
    """R9: 0 outside the cabin, 1 across the greenhouse, smooth ramps at both ends."""
    return _smoothstep((s - 1.62) / 0.25) * _smoothstep((3.98 - s) / 0.40)


def cab_edges(s):
    """(glass base x, roof edge x, belt z) of the greenhouse section at station s."""
    zs, zt = z_sh(s), z_top(s)
    xg = xs_of(s) - CAB_SHELF_W
    zb = zs - CAB_SHELF_DROP
    h = max(zt - ROOF_CROWN - zb, 1e-6)
    xr = min(XR_FIXED, xg - 0.02)
    return xg, xr, zs


def _top_z_tumble(s, x):
    """Greenhouse section: shoulder shelf, leaning side glass, crowned roof (continuous slope)."""
    zs, zt = z_sh(s), z_top(s)
    xs = xs_of(s)
    xg = xs - CAB_SHELF_W  # glass base
    zb = zs - CAB_SHELF_DROP
    h = max(zt - ROOF_CROWN - zb, 1e-6)  # glass height up to the roof edge
    xr = min(XR_FIXED, xg - 0.02)  # roof edge: constant half width
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
        return z0 + b * (z1 - z0) + bulge(s, x) + fender_ridge(s, x)
    return _top_z_dome(s, x) + bulge(s, x) + fender_ridge(s, x)


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
SIDE_INT = (1, 1, 4, 4, 3, 2, 2)  # interior points on side segments A0..A7
TOP_BP = ("sg_e1", "sg_c", "sg_e2", "sgo", "pwa", "bn_e1", "bn_c", "bn_e2",
          "en_e1", "en_c", "en_e2", "rs", "centre")
TOP_INT = (0, 0, 0, 2, 2, 2, 0, 0, 2, 0, 0, 2, 7)  # interior points before each top breakpoint
LAB_TOP0 = 10  # edge labels: side segments 0..6, top segments 10..21
FORCED_S = (1.84, 2.50, 3.10, 3.84)  # glazing boundaries as grid rows
CROSS_OFF = (-0.0025, -0.00125, 0.0, 0.00125, 0.0025)  # 5 mm groove, 2.5 mm bevel steps
CROSS_DEPTH = (0.0, 0.004, 0.005, 0.004, 0.0)  # 5 mm deep centre
LONG_DEPTH = (0.0, 0.005, 0.0)  # edge, centre, edge of a longitudinal groove
# constant-s grooves: (s0, from breakpoint, to breakpoint)
CROSS_GROOVES = ((1.96, "A2", "A7"), (3.06, "A2", "A7"), (0.42, "A2", "A7"), (4.50, "A2", "A7"),
                 (0.30, "bn_e1", "M"), (1.78, "bn_e1", "M"), (3.98, "en_e1", "M"), (4.72, "en_e1", "M"))
# constant-v grooves: (breakpoint names, s from, s to)
LONG_GROOVES = ((("bn_e1", "bn_c", "bn_e2"), 0.30, 1.78),
                (("en_e1", "en_c", "en_e2"), 3.98, 4.72))
NOSE_K = 5
NOSE_FWD = 0.045
TAIL_DS = 0.018
TAIL_SCALE = 0.935


def _smoothstep(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def _scallop(s):
    """R5: door scallop depth (m) at station s, fades in and out between s 1.25 and 2.70."""
    if s < 0.80 or s > 4.30:
        return 0.0
    return 0.009 * _smoothstep((s - 1.20) / 0.90) * _smoothstep((3.90 - s) / 0.90)


def fender_ridge(s, x):
    """Raised crown over the front fender and rear haunch, beside a lower bonnet / deck centre."""
    if x < 0.5:
        return 0.0
    g = math.exp(-((x - 0.77) / 0.075) ** 2)
    f = 0.024 * _smoothstep((s - 0.25) / 0.35) * _smoothstep((1.85 - s) / 0.40)
    r = 0.022 * _smoothstep((s - 3.95) / 0.30) * _smoothstep((4.75 - s) / 0.25)
    return g * (f + r)


def _side_anchors(s):
    zb, zs, w = z_bot(s), z_sh(s), w_max(s)
    xs, H = xs_of(s), z_sh(s) - z_bot(s)
    return [(0.0, zb), (w - 0.130, zb), (w - 0.065, zb + 0.045), (w - 0.022, zb + 0.30 * H),
            (w, zb + 0.60 * H), (w - 0.040, zs - 0.075), (w - 0.085, zs - 0.015), (xs, zs)]


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
        zc = z_bot(s) + 0.40 * H
        for k in range(1, tags["A7"] + 1):
            x_, z_ = pts[k]
            pts[k] = (x_ - sc * math.exp(-((z_ - zc) / (0.30 * H)) ** 2), z_)
    # top breakpoints, non-increasing in x (accumulate-min keeps the order at the nose)
    xs = A[-1][0]
    # sgo: side-glass outer edge; pwa: windscreen edge, so the A-pillar is 70 mm wide in x.
    # shortcut: at s < 0.28 pwa falls under the bonnet line and those nodes collapse, nose only.
    raw = [xs - 0.0025, xs - 0.005, xs - 0.0075, xs - 0.07, xs - 0.14,
           0.6725, 0.67, 0.6675, 0.6025, 0.60, 0.5975, 0.45, 0.0]
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
    base = np.concatenate([np.linspace(0.0, 0.30, 16), np.linspace(0.30, 1.20, 18)[1:],
                           np.linspace(1.20, 2.10, 24)[1:], np.linspace(2.10, 4.20, 36)[1:],
                           np.linspace(4.20, L_TOTAL, 14)[1:]])
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
    hT = _half(L_TOTAL)
    cT = float(hT["Z"].mean())
    rings.append((L_TOTAL + TAIL_DS, hT["X"] * TAIL_SCALE, cT + (hT["Z"] - cT) * TAIL_SCALE, zero))
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
ARCH = ((-1.425, 0.345, 0.60), (1.425, 0.358, 0.50))
ARCH_X1 = 1.30


def _is_well(c, n, axle_y, r, x0):
    """Face lies on the arch cylinder (inner well) and faces the axle."""
    dy, dz = c[1] - axle_y, c[2] - r
    rad = math.hypot(dy, dz)
    if abs(rad - (r + 0.048)) > 0.0025 or not (x0 - 0.005 <= abs(c[0]) <= ARCH_X1 + 0.005):
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
            bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=r + 0.048, depth=ARCH_X1 - x0,
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
        is_floor = c[2] < z_bot(min(max(s, 0.0), L_TOTAL)) + 0.006 and n[2] < -0.5
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
def _greenhouse_slot(co, pv):
    """Material slot for a paint face that is not glass. 0 body paint (roof, sail panels), 2 gloss-black
    A-pillar and roof rails (the band x 0.495..0.55 and the A-pillar foot)."""
    c = co[list(pv)].mean(axis=0)
    s, x, z = c[1] + Y_OFFSET, abs(c[0]), c[2]
    if not (1.78 <= s <= 3.95) or z <= z_sh(s) + 0.03:
        return 0
    if x <= WS_EDGE_X - 0.005:
        return 0  # roof panel
    if x <= SIDE_TOP_X + 0.005 or s < 2.22:
        return 2
    return 0


# One continuous side window (lead, 2026-11-25): the front edge follows the A-pillar rake, the rear
# edge leans forward with the fastback; no vertical B-pillar box. Only the leaning glass surface
# between the glass base and the roof edge is glass (the roof stays paint/carbon).
DLO_FRONT_S, DLO_FRONT_RAKE = 1.96, 1.50  # front edge s at the belt, and ds/dz going up
DLO_REAR_S, DLO_REAR_RAKE = 3.85, 1.75  # rear edge s at the belt, and -ds/dz going up
DLO_BELT_GAP = 0.030  # glass starts this far above the shoulder
WS_EDGE_X = 0.54  # windscreen and rear screen end at this half-width ...
SIDE_TOP_X = 0.585  # ... side glass starts here: the paint band between is the A/C-pillar line


BELT_S0, BELT_S1 = 1.90, 3.75
WS_S0, WS_S1 = 1.84, 2.50  # windscreen base and top (s)
RS_S0, RS_S1 = 3.10, 3.84  # fastback rear glass top and bottom (s)
RS_EDGE_X = 0.54
XR_FIXED = 0.585  # roof edge half width, constant along the cabin (so the side-glass cut is a straight x line)


def belt_z(s):
    """Window bottom line: a straight line along the shoulder (a plane, so it can be cut cleanly)."""
    z0 = z_sh(BELT_S0) + DLO_BELT_GAP
    z1 = z_sh(BELT_S1) + DLO_BELT_GAP
    return z0 + (z1 - z0) * (s - BELT_S0) / (BELT_S1 - BELT_S0)


def _in_side_dlo(s, x, z):
    if not (1.8 <= s <= 3.80):
        return False
    xg, xr, zs = cab_edges(s)
    if z <= belt_z(s) or not (SIDE_TOP_X < x < xg - 0.005):
        return False
    dz = z - (z_sh(2.35) + DLO_BELT_GAP)  # same reference height as the rake cut planes
    return DLO_FRONT_S + DLO_FRONT_RAKE * dz <= s <= DLO_REAR_S - DLO_REAR_RAKE * dz


def _cut_dlo_edges(body):
    """Cut the cabin top along the two raked side-window planes so the window edges are straight
    lines instead of a stair-step of whole faces. In (s, z) the front edge is s = F + Rf*(z - zb)
    and the rear edge s = R - Rr*(z - zb): planes that do not depend on x. zb varies a little with
    s; the belt height at the window's middle is used for the plane."""
    zb = z_sh(2.35) + DLO_BELT_GAP
    bm = bmesh.new()
    bm.from_mesh(body.data)
    def cabin_faces():
        out = []
        for f in bm.faces:
            c = f.calc_center_median()
            s = c.y + Y_OFFSET
            if 1.70 <= s <= 3.98 and c.z > z_sh(min(max(s, 0.0), L_TOTAL)) - 0.02:
                out.append(f)
        return out
    # front edge  s = F + Rf*(z - zb)  ->  y - Rf*z = const, normal (0, 1, -Rf)
    # rear edge   s = R - Rr*(z - zb)  ->  y + Rr*z = const, normal (0, 1, +Rr)
    for s0, k in ((DLO_FRONT_S, -DLO_FRONT_RAKE), (DLO_REAR_S, DLO_REAR_RAKE)):
        geom = cabin_faces()
        if not geom:
            continue
        verts = list({v for f in geom for v in f.verts})
        edges = list({e for f in geom for e in f.edges})
        bmesh.ops.bisect_plane(bm, geom=verts + edges + geom, plane_co=(0.0, s0 - Y_OFFSET, zb), plane_no=(0.0, 1.0, k))
    # window bottom: z = z0 + b*(s - 1.8)  ->  -b*y + z = const, normal (0, -b, 1)
    b = (belt_z(BELT_S1) - belt_z(BELT_S0)) / (BELT_S1 - BELT_S0)
    geom = cabin_faces()
    verts = list({v for f in geom for v in f.verts})
    edges = list({e for f in geom for e in f.edges})
    bmesh.ops.bisect_plane(bm, geom=verts + edges + geom, plane_co=(0.0, BELT_S0 - Y_OFFSET, belt_z(BELT_S0)), plane_no=(0.0, -b, 1.0))
    # windscreen top/bottom and rear-screen ends: constant-s cuts (they are planes y = const)
    for sc in (WS_S0, WS_S1, RS_S0, RS_S1):
        geom = cabin_faces()
        verts = list({v for f in geom for v in f.verts})
        edges = list({e for f in geom for e in f.edges})
        bmesh.ops.bisect_plane(bm, geom=verts + edges + geom, plane_co=(0.0, sc - Y_OFFSET, 0.0), plane_no=(0.0, 1.0, 0.0))
    # straight pillar lines: constant half-width cuts on both sides
    for xc in (WS_EDGE_X, SIDE_TOP_X, -WS_EDGE_X, -SIDE_TOP_X):
        geom = cabin_faces()
        verts = list({v for f in geom for v in f.verts})
        edges = list({e for f in geom for e in f.edges})
        bmesh.ops.bisect_plane(bm, geom=verts + edges + geom, plane_co=(xc, 0.0, 0.0), plane_no=(1.0, 0.0, 0.0))
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()


def split_glazing(body):
    """Move the glazing faces to a 'glass' object, 2 mm inside the body; the
    one-face-wide border of each pane is M_Trim (material slot 1)."""
    co = _co(body.data)
    polys = _polys(body.data)
    sel = {}
    for pi, pv in enumerate(polys):
        c = co[list(pv)].mean(axis=0)
        s = c[1] + Y_OFFSET
        x, z = abs(c[0]), c[2]
        if s < WS_S0 - 0.05 or s > RS_S1 + 0.05:
            continue
        xs, zs = xs_of(s), z_sh(s)
        pwa, sgo = xs - 0.14, xs - 0.07  # A-pillar paint between pwa and sgo (70 mm)
        if not (x < xs - 0.0015 and z > zs - 0.015):  # top surface only
            continue
        if WS_S0 <= s <= WS_S1 and x <= WS_EDGE_X:
            sel[pi] = "windscreen"
        elif _in_side_dlo(s, x, z):
            sel[pi] = "side"
        elif RS_S0 <= s <= RS_S1 and x <= RS_EDGE_X:
            sel[pi] = "rear"
    gl = sorted(sel)
    print("GLASS faces", len(gl), {k: list(sel.values()).count(k) for k in set(sel.values())})
    gset = set(gl)
    # border: any edge used by only one glass face
    ecount = {}
    for pi in gl:
        pv = polys[pi]
        for k in range(len(pv)):
            ek = tuple(sorted((pv[k], pv[(k + 1) % len(pv)])))
            ecount[ek] = ecount.get(ek, 0) + 1
    mats = []
    for pi in gl:
        pv = polys[pi]
        border = any(ecount[tuple(sorted((pv[k], pv[(k + 1) % len(pv)])))] == 1 for k in range(len(pv)))
        # No M_Trim border ring: since the window edges are cut along their planes, the one-face
        # ring was made of thin slivers and read as jagged black teeth. All glazing faces are glass.
        mats.append(0)
    # inward offset: average of face normals per vertex
    vn = np.zeros_like(co)
    for pi in gl:
        pv = polys[pi]
        n = _centre_normal(co, pv)
        for v in pv:
            vn[v] += n
    lens = np.linalg.norm(vn, axis=1, keepdims=True)
    vn = vn / np.maximum(lens, 1e-12)
    # Pane border vertices stay exactly on the body surface (shared seam positions: no crack, no
    # coplanar overlap, the body faces under the glass are removed); the interior sinks 2 mm.
    depth = np.full(len(co), 0.002)
    for ek, cnt in ecount.items():
        if cnt == 1:
            depth[ek[0]] = 0.0
            depth[ek[1]] = 0.0
    co_g = co - depth[:, None] * vn
    me_g, _ = _new_mesh("glass", co_g, [polys[pi] for pi in gl], mats)
    keep = [polys[i] for i in range(len(polys)) if i not in gset]
    # P1: greenhouse above the beltline is one dark canopy (slot 2 pillars, slot 3 roof panel)
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

    s_grid = np.linspace(0.0, L_TOTAL, 971)
    add("length_s_range", L_TOTAL, 4.85)
    add("width_max_w", 2 * max(w_max(s) for s in s_grid), 1.92)
    add("height_max_ztop", max(z_top(s) for s in s_grid), 1.36)
    add("shoulder_front_axle", z_sh(0.95), 0.815)
    add("shoulder_rear_axle", z_sh(3.80), 0.965)
    add("bonnet_centre_front_axle", z_top(0.95) + bulge(0.95, 0.0), 0.899)
    if body_obj is not None:
        d = body_obj.dimensions
        add("length_mesh_incl_nose_tail", float(d.y), 4.85)
        add("width_mesh", float(d.x), 1.92)
        # overall height is measured from the ground plane (z = 0), not from the floor
        add("height_mesh_above_ground", max(v[2] for v in body_obj.bound_box), 1.36)
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
    area("rearfill", (0.0, 6.0, 1.1), (math.radians(-90), 0, 0), 3.0, 260, (1.0, 0.95, 0.9))
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


def add_rear_details(mats):
    """Tail claws, joining bar and plate, sitting on the flat rear fascia (3 mm proud)."""
    yf = L_TOTAL + TAIL_DS - Y_OFFSET  # rear fascia plane (tail cap)
    yc = yf + 0.007
    bm = bmesh.new()
    for sx in (1, -1):
        for k in range(3):
            _box(bm, (sx * (0.514 + 0.045 * k), yc, 0.74), 0.028, 0.008, 0.115)
    _box(bm, (0.0, yc, 0.80), 1.0, 0.008, 0.010)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    lights = _mesh_obj("lights_rear", bm, mats["M_LightRear"])
    bm = bmesh.new()
    _box(bm, (0.0, yc + 0.001, 0.56), 0.36, 0.012, 0.12)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    plate = _mesh_obj("plate_rear", bm, mats["M_Plate"])
    return lights, plate


def _mesh_obj(name, bm, mat):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def add_interior(mats):
    """Placeholder cabin (two seats and a dash) so the glazing does not show empty red shell."""
    bm = bmesh.new()
    _box(bm, (-0.30, 0.0, 0.50), 0.36, 0.55, 0.42)
    _box(bm, (0.30, 0.0, 0.50), 0.36, 0.55, 0.42)
    _box(bm, (0.0, -0.45, 0.62), 0.80, 0.14, 0.18)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return _mesh_obj("interior", bm, mats["M_Interior"])


def add_wheels(mats):
    wheels = []
    for sx in (1, -1):
        for axle_y, r, wdt, xw in ((-1.33, 0.335, 0.255, 0.815), (1.33, 0.35, 0.315, 0.800)):  # R4
            bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=r, depth=wdt,
                                                location=(sx * xw, axle_y, r),
                                                rotation=(0, math.pi / 2, 0))
            w = bpy.context.active_object
            w.name = "wheel_%s%s" % ("L" if sx > 0 else "R", "F" if axle_y < 0 else "R")
            w.data.materials.append(mats["M_Tire"])
            wheels.append(w)
    return wheels


def main():
    if bpy is None:
        raise SystemExit("run inside Blender")
    os.makedirs(RENDER_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    checks_pre = None
    body = build_shell()
    cut_panel_lines(body)
    checks_pre = checks(body)  # spec dims on the grooved shell, before the arches
    underbody = cut_arches(body)
    _cut_dlo_edges(body)
    glass = split_glazing(body)
    for ob in (body, glass, underbody):
        finish_shading(ob)
    mats = make_materials()
    _assign(body, [mats["M_Paint"]])
    _assign(glass, [mats["M_Glass"], mats["M_Trim"]])
    _assign(underbody, [mats["M_Trim"], mats["M_Interior"]])
    lights, plate = add_rear_details(mats)
    interior = add_interior(mats)
    add_wheels(mats)
    sc, cam, tgt = setup_scene(mats)
    paint = render_views(sc, cam, VIEWS)
    # zoom check of the front arch lip (extra render, not in the deliverable list)
    tgt.location, cam.data.lens = (-0.8, -1.33, 0.4), 85
    render_views(sc, cam, {"front_arch_zoom": (-2.0, -2.6, 0.7)})
    tgt.location, cam.data.lens = (0.0, 0.0, 0.55), 60
    # clay look: same geometry, uniform grey
    clay_objs = (body, glass, underbody, lights, plate, interior)
    for ob in clay_objs:
        ob.data.materials.clear()
        ob.data.materials.append(mats["M_Clay"])
    cam_views = {"clay_side": VIEWS["side"], "clay_front34": VIEWS["front34"]}
    clay = render_views(sc, cam, cam_views)
    for ob, slots in ((body, [mats["M_Paint"]]), (glass, [mats["M_Glass"], mats["M_Trim"]]),
                      (underbody, [mats["M_Trim"]]), (lights, [mats["M_LightRear"]]),
                      (plate, [mats["M_Plate"]]), (interior, [mats["M_Interior"]])):
        _assign(ob, slots)
    contact_sheet([paint["front34"], paint["rear34"], paint["side"],
                   paint["top"], paint["front_low"], clay["clay_front34"]],
                  os.path.join(RENDER_DIR, "contact_sheet.png"))
    print("MAIN_DONE")
    return checks_pre


if __name__ == "__main__":
    main()
