"""LOD0 detail helpers for the Istanbul timber houses (build_istanbul.py calls these under `detail` only).

Face coordinates follow bb.Face: u along the front, v up, t positive into the wall (depth), so a
proud part uses negative t. World-space helpers (dormer, ridge_strip) use Blender metres, Z up, front -Y.
"""
from mathutils import Vector

import build_buildings as bb

Z = Vector((0.0, 0.0, 1.0))


def casing(b, f, o, trim):
    """Moulded surround proud of the wall: jambs, head with a cornice lip, projecting sill."""
    u0, u1, v0, v1 = o["u0"], o["u1"], o["v0"], o["v1"]
    bb.fbox(b, f, u0 - 0.1, u0, v0 - 0.1, v1 + 0.1, -0.07, 0.0, trim)
    bb.fbox(b, f, u1, u1 + 0.1, v0 - 0.1, v1 + 0.1, -0.07, 0.0, trim)
    bb.fbox(b, f, u0 - 0.14, u1 + 0.14, v1 + 0.1, v1 + 0.2, -0.1, 0.0, trim)
    bb.fbox(b, f, u0 - 0.16, u1 + 0.16, v1 + 0.2, v1 + 0.24, -0.12, 0.0, trim)
    bb.fbox(b, f, u0 - 0.12, u1 + 0.12, v0 - 0.12, v0 - 0.04, -0.12, 0.0, trim)


def slats(b, f, u0, u1, v0, v1, mat, n=5):
    """Louvre slats across a closed shutter leaf (proud of the leaf)."""
    step = (v1 - v0) / n
    for k in range(n):
        va = v0 + step * (k + 0.5) - 0.025
        bb.fbox(b, f, u0 + 0.04, u1 - 0.04, va, va + 0.05, -0.075, -0.04, mat)


def closed_shutters(b, f, o, mat):
    """Leaves flat against the wall on both sides of the casing, each with slats."""
    u0, u1, v0, v1 = o["u0"], o["u1"], o["v0"], o["v1"]
    w = 0.5 * (u1 - u0)
    for sa, sb in ((u0 - 0.1 - w, u0 - 0.1), (u1 + 0.1, u1 + 0.1 + w)):
        bb.fbox(b, f, sa, sb, v0, v1, -0.04, 0.0, mat)
        slats(b, f, sa, sb, v0, v1, mat)


def open_shutter(b, f, o, mat, reach=0.45):
    """One leaf swung out at 90 degrees, hinged on the left casing; slats on its +u face."""
    u0, v0, v1 = o["u0"], o["v0"], o["v1"]
    hu = u0 - 0.13
    bb.fbox(b, f, hu - 0.02, hu + 0.02, v0, v1, -reach, 0.0, mat)
    step = (v1 - v0) / 5
    for k in range(5):
        va = v0 + step * (k + 0.5) - 0.025
        bb.fbox(b, f, hu + 0.02, hu + 0.045, va, va + 0.05, -reach + 0.06, -0.06, mat)


def door_panels(b, f, o, trim):
    """Panelled double leaves: centre stile, two rails, side stiles, recessed 25 cm behind the wall."""
    u0, u1, v0, v1, r = o["u0"], o["u1"], o["v0"], o["v1"], o["r"]
    um = 0.5 * (u0 + u1)
    bb.fbox(b, f, um - 0.04, um + 0.04, v0, v1, r - 0.05, r, trim)
    for vr in (v0 + 0.4 * (v1 - v0), v0 + 0.72 * (v1 - v0)):
        bb.fbox(b, f, u0, u1, vr, vr + 0.06, r - 0.05, r, trim)
    bb.fbox(b, f, u0, u0 + 0.06, v0, v1, r - 0.06, r, trim)
    bb.fbox(b, f, u1 - 0.06, u1, v0, v1, r - 0.06, r, trim)


def balcony_bars(b, f, o, mat):
    """Iron railing as thin posts: a bar every 0.24 m between the slab and the top rail."""
    u0, u1, v0 = o["u0"], o["u1"], o["v0"]
    ua, ub = u0 - 0.2, u1 + 0.2
    n = int((ub - ua) / 0.24)
    for k in range(n + 1):
        uc = ua + 0.02 + k * (ub - ua - 0.04) / n
        bb.fbox(b, f, uc - 0.012, uc + 0.012, v0 - 0.14, v0 + 0.72, -0.9, -0.87, mat)
    for vr in (v0 - 0.02, v0 + 0.38):
        bb.fbox(b, f, ua, ub, vr, vr + 0.03, -0.9, -0.87, mat)
    for uu in (u0 - 0.2, u1 + 0.13):
        bb.fbox(b, f, uu - 0.05, uu + 0.07, v0 - 0.5, v0 - 0.28, -0.45, 0.0, mat)     # corbel under the slab


def flower_box(b, f, o, wood, leaf):
    """Window box under the sill: timber box, green planting proud of it."""
    u0, u1, v0 = o["u0"], o["u1"], o["v0"]
    bb.fbox(b, f, u0 - 0.04, u1 + 0.04, v0 - 0.3, v0 - 0.12, -0.26, -0.02, wood)
    bb.fbox(b, f, u0 - 0.02, u1 + 0.02, v0 - 0.12, v0 - 0.04, -0.3, -0.24, leaf)


def lantern(b, f, u, v, mat):
    """Wall lantern: a painted body and a small cap."""
    bb.fbox(b, f, u - 0.07, u + 0.07, v, v + 0.3, -0.24, 0.0, mat)
    bb.fbox(b, f, u - 0.1, u + 0.1, v + 0.3, v + 0.34, -0.27, -0.2, mat)


def downpipe(b, f, u, v0, v1, mat):
    bb.fbox(b, f, u, u + 0.09, v0, v1, -0.1, 0.0, mat)


def awning_arms(b, f, u_list, v, reach, mat):
    """Iron arms holding a canvas awning out from the wall."""
    for u in u_list:
        bb.fbox(b, f, u, u + 0.05, v - 0.04, v + 0.02, -reach, 0.0, mat)


def siding(b, f, excl, W, v_lo, v_hi, mat, course=0.36, margin=0.25, t0=-0.03):
    """Horizontal clapboard: shallow boards proud of the wall, cut around openings (u0, u1, v0, v1)."""
    lo, hi = 0.25, W - 0.25
    n = int((v_hi - v_lo) / course)
    for i in range(n):
        va = v_lo + i * course + 0.02
        vb = va + course - 0.03
        cuts = sorted((u0 - margin, u1 + margin) for (u0, u1, v0, v1) in excl if v0 < vb and v1 > va)
        cur = lo
        for a, c in cuts + [(hi, hi)]:
            end = min(a, hi)
            if end - cur > 0.05:
                bb.fbox(b, f, cur, end, va, vb, t0, 0.0, mat)
            cur = max(cur, c)


def dormer(b, xc, y_front, z_base, w, trim, glass_t, roof_mat, rng):
    """Small gabled dormer on a front roof slope, world coords (front faces -Y)."""
    x0, x1 = xc - w / 2, xc + w / 2
    yf, yb = y_front, y_front + 0.9
    zt = z_base + 1.2
    b.box((x0, yf, z_base), (x1, yb, zt), trim)
    t = bb.pick_tile(rng, 0.6)
    b.poly([(x0 + 0.15, yf - 0.01, z_base + 0.3), (x1 - 0.15, yf - 0.01, z_base + 0.3),
            (x1 - 0.15, yf - 0.01, zt - 0.2), (x0 + 0.15, yf - 0.01, zt - 0.2)], (0, -1, 0), glass_t, bb.tile_uv(t))
    b.poly([(x0, yf, zt), (x1, yf, zt), (xc, yf, zt + 0.5)], (0, -1, 0), trim)
    b.poly([(x0, yf, zt), (xc, yf, zt + 0.5), (xc, yb, zt + 0.5), (x0, yb, zt)], (-1, 0, 1), roof_mat)
    b.poly([(x1, yf, zt), (x1, yb, zt), (xc, yb, zt + 0.5), (xc, yf, zt + 0.5)], (1, 0, 1), roof_mat)


def ridge_strip(b, p0, p1, mat, w=0.14, h=0.07):
    """Raised roll along a hip line: a four-sided section, open ends (they sit in the roof and the ridge cap)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    side = d.cross(Z)
    if side.length < 1e-6:
        return
    side = side.normalized() * (w / 2)
    up = d.cross(side).normalized()
    if up.z < 0:
        up = -up
    up = up * h
    sec = [side, up, -side, -up]
    for k in range(4):
        a, c = sec[k], sec[(k + 1) % 4]
        nrm = (a + c).normalized()
        b.poly([p0 + a, p0 + c, p1 + c, p1 + a], nrm, mat)


def shop_front(b, f, w, trim, awn):
    """Shop row front (u 0..w): pilasters with base and capital, a panelled stall riser under the glass,
    a moulding over the fascia, and a scalloped valance hanging from the awning edge."""
    for ua, ub in ((1.18, 1.36), (w - 0.3, w - 0.12)):
        bb.fbox(b, f, ua, ub, 0.5, 2.95, -0.14, 0.0, trim)                  # pilaster shaft
        bb.fbox(b, f, ua - 0.03, ub + 0.03, 0.3, 0.5, -0.19, 0.0, trim)     # base
        bb.fbox(b, f, ua - 0.03, ub + 0.03, 2.85, 2.95, -0.19, 0.0, trim)   # capital
    bb.fbox(b, f, 1.36, w - 0.3, 0.05, 0.55, -0.12, 0.0, trim)              # stall riser
    bb.fbox(b, f, 1.5, w - 0.45, 0.14, 0.44, -0.17, -0.12, trim)            # raised panel on the riser
    bb.fbox(b, f, 1.2, w - 0.15, 3.4, 3.46, -0.14, -0.04, trim)             # moulding over the fascia
    edges = [1.25 + k * (w - 1.5) / 5.0 for k in range(6)]
    for ua, ub in zip(edges[:-1], edges[1:]):                               # valance scallops
        bb.fbox(b, f, ua + 0.06, ub - 0.06, 2.3, 2.45, -1.22, -1.14, awn)


def pediment(b, f, uc, w, v0, apex, mat_wall, mat_trim, mat_glass):
    """Street-facing gable on the front wall above the eave: a trimmed triangle with a square attic window."""
    t = -0.1                                                        # stands 10 cm proud of the wall, clear of the eave
    b.poly([f.P(uc - w / 2, v0, t), f.P(uc + w / 2, v0, t), f.P(uc, apex, t)], f.N, mat_wall)
    bb.fbox(b, f, uc - w / 2 - 0.1, uc + w / 2 + 0.1, v0 - 0.02, v0 + 0.1, -0.16, -0.1, mat_trim)   # base band
    s = 0.28
    bb.fbox(b, f, uc - s - 0.08, uc + s + 0.08, apex - 0.52, apex - 0.1, -0.16, -0.1, mat_trim)    # attic frame
    bb.fbox(b, f, uc - s, uc + s, apex - 0.46, apex - 0.16, -0.19, -0.16, mat_glass)               # attic glass


def belvedere(b, xc, yc, zr, mat_wall, mat_roof):
    """Small lantern on the hip apex: a four-sided body with a pyramid cap (silhouette only)."""
    r, h = 0.9, 1.1
    b.box((xc - r, yc - r, zr - 0.1), (xc + r, yc + r, zr + h), mat_wall)
    top = zr + h + 0.7
    c = [(xc - r - 0.1, yc - r - 0.1, zr + h), (xc + r + 0.1, yc - r - 0.1, zr + h),
         (xc + r + 0.1, yc + r + 0.1, zr + h), (xc - r - 0.1, yc + r + 0.1, zr + h)]
    for k in range(4):
        a, d = c[k], c[(k + 1) % 4]
        b.poly([a, d, (xc, yc, top)], (a[0] + d[0] - 2 * xc, a[1] + d[1] - 2 * yc, 1.2), mat_roof)


def grilles(b, f, o, mat):
    """Iron grille on a ground-floor window: three vertical bars and a transom, set just inside the reveal."""
    u0, u1, v0, v1, r = o["u0"], o["u1"], o["v0"], o["v1"], o["r"]
    for uc in (u0 + 0.25 * (u1 - u0), 0.5 * (u0 + u1), u0 + 0.75 * (u1 - u0)):
        bb.fbox(b, f, uc - 0.012, uc + 0.012, v0 + 0.01, v1 - 0.01, -0.03, r - 0.06, mat)
    bb.fbox(b, f, u0 + 0.01, u1 - 0.01, v0 + 0.6 * (v1 - v0), v0 + 0.6 * (v1 - v0) + 0.024, -0.03, r - 0.06, mat)
