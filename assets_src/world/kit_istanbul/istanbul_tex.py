"""Istanbul kit: generated textures (numpy only, project-owned, no downloads).

cobble (1024, 3 maps), roof tile (512), three far skyline cards (2048 x 512, one texture each).
Skyline cards use ONE image for albedo and emission (same as the existing M_Skyline): body is near
black, only lit windows and flood-lit domes sit above the shader's glow threshold.
Arc coordinates: u in metres along the card (0..L), z in metres up (0..Hc).
"""
import math

import numpy as np

W_TEX, H_TEX = 2048, 512
WARM = np.array([1.0, 0.70, 0.40], np.float32)
COOL = np.array([0.72, 0.84, 1.0], np.float32)
BODY_TOP = np.array([0.020, 0.024, 0.040], np.float32)
BODY_BOT = np.array([0.050, 0.060, 0.095], np.float32)


# ----------------------------------------------------------------------------- cobble and roof
def gen_cobble(seed=31):
    N, rows, sw = 1024, 16, 128
    rh = N // rows
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:N, 0:N]
    row = yy // rh
    off = rng.integers(0, sw, size=rows)
    xs = (xx + off[row]) % N
    col = xs // sw
    u = (xs % sw) / float(sw)
    v = (yy % rh) / float(rh)
    d = np.minimum(np.minimum(u, 1 - u) * sw, np.minimum(v, 1 - v) * rh)
    tone = rng.uniform(0.80, 1.12, size=(rows, N // sw)).astype(np.float32)
    warm = rng.uniform(-0.05, 0.05, size=(rows, N // sw)).astype(np.float32)
    hgt = rng.uniform(0.85, 1.0, size=(rows, N // sw)).astype(np.float32)
    t = tone[row, col]
    wm = warm[row, col]
    h = np.clip(d / 11.0, 0.0, 1.0) ** 0.6 * hgt[row, col]
    noise = rng.normal(0.0, 0.025, (N, N)).astype(np.float32)
    base = np.zeros((N, N, 3), np.float32)
    g = 0.34 * t + noise
    base[..., 0] = g + wm
    base[..., 1] = g + wm * 0.4
    base[..., 2] = g - wm * 0.6 + 0.01
    joint = d < 3.0
    base[joint] = np.array([0.045, 0.043, 0.04], np.float32)
    base = np.clip(base, 0, 1)
    gy, gx = np.gradient(h.astype(np.float32))
    s = 6.0
    nx, ny = -gx * s, gy * s
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
    rough = np.clip(0.72 + 0.18 * (1.0 - h) + noise, 0.3, 1.0)
    rough = np.stack([rough] * 3, -1)
    return base, normal.astype(np.float32), rough.astype(np.float32)


def gen_roof_tile(seed=41):
    N, rows, tw = 512, 16, 64
    rh = N // rows
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:N, 0:N]
    row = yy // rh
    xs = (xx + (row % 2) * (tw // 2)) % N
    col = xs // tw
    u = (xs % tw) / float(tw)
    v = (yy % rh) / float(rh)
    tone = rng.uniform(0.78, 1.15, size=(rows, N // tw)).astype(np.float32)
    moss = (rng.random(size=(rows, N // tw)) < 0.08).astype(np.float32)
    t = tone[row, col]
    barrel = 0.82 + 0.18 * np.cos((u - 0.5) * math.pi)
    shade = np.where(v > 0.72, 1.0 - 0.5 * (v - 0.72) / 0.28, 1.0)
    gap = (u < 0.04) | (u > 0.96)
    terra = np.array([0.50, 0.21, 0.12], np.float32)
    mossc = np.array([0.20, 0.24, 0.12], np.float32)
    mm = moss[row, col][..., None]
    c = (terra * (1 - mm) + mossc * mm) * (t * barrel * shade)[..., None]
    c = c + rng.normal(0.0, 0.015, (N, N, 1)).astype(np.float32)
    c[gap] = np.array([0.06, 0.03, 0.02], np.float32)
    return np.clip(c, 0, 1).astype(np.float32)


# ----------------------------------------------------------------------------- raster helpers
def _blank(L, Hc):
    yy = np.linspace(0.0, 1.0, H_TEX, dtype=np.float32)[:, None, None]      # 0 top .. 1 bottom
    img = BODY_TOP[None, None, :] * (1 - yy) + BODY_BOT[None, None, :] * yy
    return np.repeat(img, W_TEX, axis=1).copy()


def _px(L, Hc):
    return W_TEX / float(L), H_TEX / float(Hc)


def _rect(img, L, Hc, u0, u1, z0, z1, col):
    pu, pz = _px(L, Hc)
    x0, x1 = int(max(0, math.floor(u0 * pu))), int(min(W_TEX, math.ceil(u1 * pu)))
    r0, r1 = int(max(0, math.floor((1 - z1 / Hc) * H_TEX))), int(min(H_TEX, math.ceil((1 - z0 / Hc) * H_TEX)))
    if x1 > x0 and r1 > r0:
        img[r0:r1, x0:x1] = col


def _poly(img, L, Hc, pts, col):
    """Fill a convex polygon given in (u metres, z metres)."""
    pu, pz = _px(L, Hc)
    P = [(u * pu, (1 - z / Hc) * H_TEX) for u, z in pts]
    xs = [p[0] for p in P]
    ys = [p[1] for p in P]
    x0, x1 = int(max(0, math.floor(min(xs)))), int(min(W_TEX - 1, math.ceil(max(xs))))
    y0, y1 = int(max(0, math.floor(min(ys)))), int(min(H_TEX - 1, math.ceil(max(ys))))
    if x1 < x0 or y1 < y0:
        return
    X, Y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    inside = np.ones(X.shape, bool)
    sgn = 0.0
    n = len(P)
    area = sum(P[i][0] * P[(i + 1) % n][1] - P[(i + 1) % n][0] * P[i][1] for i in range(n))
    sgn = 1.0 if area >= 0 else -1.0
    for i in range(n):
        a, b = P[i], P[(i + 1) % n]
        cr = (b[0] - a[0]) * (Y - a[1]) - (b[1] - a[1]) * (X - a[0])
        inside &= (cr * sgn) >= -0.5
    sub = img[y0:y1 + 1, x0:x1 + 1]
    sub[inside] = col


def _dot(img, L, Hc, u, z, col, w=1.0, h=1.0):
    pu, pz = _px(L, Hc)
    cx, cy = u * pu, (1 - z / Hc) * H_TEX
    hw, hh = max(1.0, w * pu * 0.5), max(1.0, h * pz * 0.5)
    x0, x1 = int(max(0, round(cx - hw))), int(min(W_TEX, round(cx + hw)))
    y0, y1 = int(max(0, round(cy - hh))), int(min(H_TEX, round(cy + hh)))
    if x1 > x0 and y1 > y0:
        img[y0:y1, x0:x1] = col


def _colfill(img, L, Hc, hcol):
    """Dark body under a per-pixel-column height profile (metres)."""
    pu, pz = _px(L, Hc)
    body = _blank(L, Hc)
    out = img.copy()
    rows = np.arange(H_TEX)[:, None]
    zrow = (1 - (rows + 0.5) / H_TEX) * Hc
    mask = zrow <= hcol[None, :]
    out[mask] = body[mask]
    return out


def _window_grid(img, L, Hc, hcol, rng, p0=0.30, floor_h=3.1, win_w=1.0, win_h=1.3, step=2.4, lo=1.8, top_margin=1.8,
                 noise_u=None):
    """Windows over everything under the profile: warm 78 percent, cool 14 percent, a few dim."""
    pu, pz = _px(L, Hc)
    u = 0.0
    while u < L:
        i = min(W_TEX - 1, int(u * pu))
        top = hcol[i]
        local = p0 * (0.2 + 0.8 * (noise_u[i] if noise_u is not None else 1.0))
        z = lo
        while z + win_h < top - top_margin:
            if rng.random() < local * (1.0 - 0.35 * (z / max(top, 1.0))):
                r = rng.random()
                col = WARM * rng.uniform(0.75, 1.0) if r < 0.78 else (COOL * rng.uniform(0.7, 0.95) if r < 0.92 else WARM * 0.45)
                _dot(img, L, Hc, u + step * 0.5, z + win_h * 0.5, col, win_w, win_h)
            z += floor_h
        u += step


def _smooth_noise(rng, n=W_TEX, scale=90):
    k = rng.random(n // scale + 3).astype(np.float32)
    x = np.linspace(0, len(k) - 3, n)
    i = x.astype(int)
    f = x - i
    f = f * f * (3 - 2 * f)
    return k[i] * (1 - f) + k[i + 1] * f


def _dome(h, u, xc, r, zb, k=1.0):
    d = (u - xc) / r
    m = np.abs(d) < 1.0
    prof = zb + r * k * np.sqrt(np.clip(1 - d * d, 0, 1))
    return np.where(m, np.maximum(h, prof), h)


def _minaret(h, u, xc, zb, ht, w=2.6):
    d = np.abs(u - xc)
    h = np.where(d < w / 2, np.maximum(h, zb + ht * 0.78), h)                   # shaft
    h = np.where(d < w * 0.95, np.maximum(h, zb + ht * 0.70), h)               # balcony platform
    cone_h = ht * 0.22
    cap = d < w * 0.62
    prof = zb + ht * 0.78 + cone_h * (1 - d / (w * 0.62))
    return np.where(cap, np.maximum(h, prof), h)


def _house_roofline(rng, u, base, jit=2.6):
    h = base.copy()
    x = 0.0
    L = u[-1]
    while x < L:
        w = rng.uniform(4.5, 9.0)
        j = rng.uniform(0.0, jit)
        sel = (u >= x) & (u < x + w)
        h[sel] += j
        x += w
    return h


# ----------------------------------------------------------------------------- skyline: Asian shore hills
def skyline_asia(seed=11):
    L, Hc = 560.0, 96.0
    rng = np.random.default_rng(seed)
    u = (np.arange(W_TEX) + 0.5) * L / W_TEX
    base = (24 + 15 * np.sin(u * 0.0125 + 1.1) + 9 * np.sin(u * 0.031 + 0.3) + 4.5 * np.sin(u * 0.073 + 2.0)
            + 17 * np.exp(-((u - 360) / 75.0) ** 2) + 9 * np.exp(-((u - 90) / 50.0) ** 2))
    base = np.clip(base, 14, 70)
    h = _house_roofline(rng, u, base)
    # a hill mosque: dome with two minarets (soft silhouette, never a real landmark)
    mx = 200.0
    zb = float(np.interp(mx, u, base)) + 1.5
    h = _dome(h, u, mx, 9.0, zb + 2.0, 0.85)
    h = _minaret(h, u, mx - 15.0, zb - 1.5, 27.0)
    h = _minaret(h, u, mx + 15.0, zb - 1.5, 25.0)
    # a second small one on the far hill
    zb2 = float(np.interp(470, u, base)) + 1.0
    h = _dome(h, u, 470.0, 6.0, zb2 + 1.5, 0.85)
    h = _minaret(h, u, 482.0, zb2 - 1.0, 20.0, 2.2)
    # a tall radio mast on the main hill: red lamps
    mast_u = 372.0
    zbm = float(np.interp(mast_u, u, base)) + 2.0
    h = np.where(np.abs(u - mast_u) < 0.6, np.maximum(h, zbm + 24.0), h)
    h = np.clip(h, 0, Hc - 1)
    img = _colfill(_blank(L, Hc), L, Hc, h)
    nz = _smooth_noise(rng, scale=110)
    _window_grid(img, L, Hc, h, rng, p0=0.30, noise_u=nz)
    # minaret ring lights and dome glow
    for xc, ztop in ((mx - 15.0, zb - 1.5 + 27.0 * 0.70), (mx + 15.0, zb - 1.5 + 25.0 * 0.70)):
        _dot(img, L, Hc, xc, ztop, np.array([1.0, 0.82, 0.5], np.float32), 3.4, 0.8)
    for ix in range(int((mx - 9.0) * W_TEX / L), int((mx + 9.0) * W_TEX / L)):      # soft flood-light on the dome
        d = ((ix + 0.5) * L / W_TEX - mx) / 9.0
        if abs(d) >= 1.0:
            continue
        top = zb + 2.0 + 9.0 * 0.85 * math.sqrt(1 - d * d)
        for iy in range(int((1 - top / Hc) * H_TEX), int((1 - (zb + 2.0) / Hc) * H_TEX)):
            zz = (1 - (iy + 0.5) / H_TEX) * Hc
            img[iy, ix] = np.array([1.0, 0.74, 0.44], np.float32) * (0.4 + 0.5 * (1 - (zz - zb - 2.0) / max(top - zb - 2.0, 0.5)))
    _dot(img, L, Hc, mast_u, zbm + 22.0, np.array([1.0, 0.18, 0.12], np.float32), 1.4, 1.4)
    _dot(img, L, Hc, mast_u, zbm + 12.0, np.array([1.0, 0.18, 0.12], np.float32), 1.2, 1.2)
    # shore road: a ribbon of sodium dots at the water line
    uu = 0.0
    while uu < L:
        if rng.random() < 0.82:
            _dot(img, L, Hc, uu, 1.6, WARM * rng.uniform(0.8, 1.0), 1.2, 0.9)
        uu += rng.uniform(4.5, 7.0)
    return L, Hc, h, img


# ----------------------------------------------------------------------------- skyline: domes and minarets
def skyline_domes(seed=23):
    L, Hc = 420.0, 100.0
    rng = np.random.default_rng(seed)
    u = (np.arange(W_TEX) + 0.5) * L / W_TEX
    base = 15 + 9 * np.sin(u * 0.016 + 0.7) + 5 * np.sin(u * 0.043 + 1.9) + 7 * np.exp(-((u - 215) / 80.0) ** 2)
    h = _house_roofline(rng, u, base, jit=2.2)
    domes = []          # (xc, r, zb) for the flood-light pass
    mins = []           # (xc, zb, ht)
    # great mosque group (original massing): central dome, two half domes, four minarets
    cx = 215.0
    zb = 29.0
    h = _dome(h, u, cx, 19.0, zb, 0.92)
    domes.append((cx, 19.0, zb))
    for s in (-1, 1):
        h = _dome(h, u, cx + s * 22.0, 11.5, zb - 5.0, 0.95)
        domes.append((cx + s * 22.0, 11.5, zb - 5.0))
        h = _dome(h, u, cx + s * 36.0, 7.0, zb - 10.0, 0.95)
        domes.append((cx + s * 36.0, 7.0, zb - 10.0))
    h = np.where(np.abs(u - cx) < 21.0, np.maximum(h, zb - 1.0), h)     # drum / podium band
    for xc, ht in ((cx - 56.0, 66.0), (cx - 47.0, 58.0), (cx + 47.0, 58.0), (cx + 56.0, 66.0)):
        zbm = float(np.interp(xc, u, base)) + 3.0
        h = _minaret(h, u, xc, zbm, ht)
        mins.append((xc, zbm, ht))
    # second, smaller mosque on the left, a lone dome on the right
    h = _dome(h, u, 70.0, 12.0, 30.0, 0.9)
    domes.append((70.0, 12.0, 30.0))
    zbm = float(np.interp(88.0, u, base)) + 2.0
    h = _minaret(h, u, 88.0, zbm, 44.0, 2.3)
    mins.append((88.0, zbm, 44.0))
    h = _dome(h, u, 340.0, 10.0, 31.0, 0.9)
    domes.append((340.0, 10.0, 31.0))
    zbm = float(np.interp(355.0, u, base)) + 2.0
    h = _minaret(h, u, 355.0, zbm, 40.0, 2.3)
    mins.append((355.0, zbm, 40.0))
    # cypress trees: slim soft spikes between the groups
    for xc in (130.0, 150.0, 296.0, 312.0, 20.0, 395.0):
        sh = 6.0 + rng.uniform(0, 5)
        z0 = float(np.interp(xc, u, base))
        h = np.where(np.abs(u - xc) < 1.6, np.maximum(h, z0 + sh * (1 - np.abs(u - xc) / 1.6) + 4.0), h)
    h = np.clip(h, 0, Hc - 1)
    img = _colfill(_blank(L, Hc), L, Hc, h)
    nz = _smooth_noise(rng, scale=110)
    _window_grid(img, L, Hc, h, rng, p0=0.20, noise_u=nz)
    # soft flood-light on domes: warm gradient, brightest low, fading to the crown
    pu, pz = _px(L, Hc)
    for xc, r, zb0 in domes:
        for ix in range(int(max(0, (xc - r) * pu)), int(min(W_TEX, (xc + r) * pu))):
            uu = (ix + 0.5) / pu
            d = (uu - xc) / r
            if abs(d) >= 1.0:
                continue
            top = zb0 + r * 0.92 * math.sqrt(max(0.0, 1 - d * d))
            for iy in range(int((1 - min(top, Hc) / Hc) * H_TEX), int((1 - zb0 / Hc) * H_TEX)):
                zz = (1 - (iy + 0.5) / H_TEX) * Hc
                f = 1.0 - (zz - zb0) / max(top - zb0, 0.5)
                lit = (0.40 + 0.55 * f) * (1.0 - 0.35 * abs(d))
                img[iy, ix] = np.array([1.0, 0.74, 0.44], np.float32) * lit
    # minarets: lit balcony ring, lit cap and a soft flood on the shaft
    for xc, zb0, ht in mins:
        _dot(img, L, Hc, xc, zb0 + ht * 0.70, np.array([1.0, 0.84, 0.52], np.float32), 4.6, 1.0)
        _dot(img, L, Hc, xc, zb0 + ht * 0.50, np.array([0.80, 0.60, 0.36], np.float32), 1.6, ht * 0.30)
        _dot(img, L, Hc, xc, zb0 + ht * 0.96, np.array([0.95, 0.74, 0.44], np.float32), 1.5, 4.0)
    uu = 0.0
    while uu < L:
        if rng.random() < 0.85:
            _dot(img, L, Hc, uu, 1.5, WARM * rng.uniform(0.8, 1.0), 1.2, 0.9)
        uu += rng.uniform(5.0, 8.0)
    return L, Hc, h, img


# ----------------------------------------------------------------------------- skyline: suspension bridge
def bridge_shapes():
    """Convex quads / tris in (u metres, z metres). Generic suspension bridge, not a replica."""
    L = 520.0
    t1, t2 = 120.0, 400.0                  # tower centres
    zt, zd = 104.0, 26.0                   # tower top, deck level
    sag_mid = 34.0                         # cable height at midspan
    shapes = []                            # (kind, pts)

    def ribbon(poly_pts, th, kind):
        for (a, b) in zip(poly_pts[:-1], poly_pts[1:]):
            shapes.append((kind, [(a[0], a[1] - th / 2), (b[0], b[1] - th / 2), (b[0], b[1] + th / 2), (a[0], a[1] + th / 2)]))

    def cable(xa, za, xb, zb_, xlow, zlow, n):
        pts = []
        for i in range(n + 1):
            x = xa + (xb - xa) * i / n
            s = (x - xlow) / max(abs(xa - xlow), abs(xb - xlow))
            z = zlow + (max(za, zb_) - zlow) * s * s
            pts.append((x, z))
        return pts

    main = cable(t1, zt, t2, zt, 0.5 * (t1 + t2), sag_mid, 56)
    side_l = [(x, zd + 3.0 + (zt - zd - 3.0) * ((x - 8.0) / (t1 - 8.0)) ** 1.7) for x in np.linspace(8.0, t1, 14)]
    side_r = [(x, zd + 3.0 + (zt - zd - 3.0) * ((512.0 - x) / (512.0 - t2)) ** 1.7) for x in np.linspace(t2, 512.0, 14)]
    cabs = [main, side_l, side_r]
    for c in cabs:
        ribbon(c, 2.0, "cable")
    # hangers
    for c in cabs:
        for (a, b) in list(zip(c[:-1], c[1:])):
            x = 0.5 * (a[0] + b[0])
            z = 0.5 * (a[1] + b[1])
            if z > zd + 2.0:
                shapes.append(("hanger", [(x - 0.45, zd + 2.2), (x + 0.45, zd + 2.2), (x + 0.45, z), (x - 0.45, z)]))
    # deck: a slim truss and a thin box girder
    shapes.append(("deck", [(0.0, zd - 2.2), (L, zd - 2.2), (L, zd + 2.4), (0.0, zd + 2.4)]))
    # towers: two legs per tower (slight skew view), cross beams, cap
    for tc in (t1, t2):
        for dx in (-7.0, 7.0):
            shapes.append(("tower", [(tc + dx - 2.1, 0.0), (tc + dx + 2.1, 0.0), (tc + dx + 1.5, zt + 3.0), (tc + dx - 1.5, zt + 3.0)]))
        for zz in (52.0, 82.0, zt - 4.0):
            shapes.append(("tower", [(tc - 8.0, zz), (tc + 8.0, zz), (tc + 8.0, zz + 3.2), (tc - 8.0, zz + 3.2)]))
    return L, 112.0, shapes, dict(t1=t1, t2=t2, zt=zt, zd=zd, main=main, side_l=side_l, side_r=side_r)


def skyline_bridge(seed=37):
    L, Hc, shapes, info = bridge_shapes()
    rng = np.random.default_rng(seed)
    u = (np.arange(W_TEX) + 0.5) * L / W_TEX
    # shore hills at both ends (the bridge lands on them)
    land = np.zeros(W_TEX, np.float32)
    land += np.where(u < 40.0, 30.0 - 0.45 * u + 4.0 * np.sin(u * 0.2), 0.0)
    land += np.where(u > 480.0, 30.0 - 0.45 * (L - u) + 4.0 * np.sin((L - u) * 0.2), 0.0)
    land = np.clip(land, 0, Hc - 1).astype(np.float32)
    img = _blank(L, Hc)   # the mesh is cut to the shapes, so only those texels are ever seen
    steel = np.array([0.040, 0.046, 0.062], np.float32)
    for kind, pts in shapes:
        _poly(img, L, Hc, pts, steel)
    img = _colfill_only(img, L, Hc, land)
    # necklace of lights along the main and side cables
    for key, spacing in (("main", 3.0), ("side_l", 3.0), ("side_r", 3.0)):
        c = info[key]
        xs = np.array([p[0] for p in c])
        zs = np.array([p[1] for p in c])
        x = xs[0]
        while x < xs[-1]:
            z = float(np.interp(x, xs, zs))
            _dot(img, L, Hc, x, z + 0.8, np.array([1.0, 0.90, 0.68], np.float32), 1.5, 1.6)
            x += spacing
    # hanger flecks and deck edge lights
    x = 4.0
    while x < L - 4.0:
        _dot(img, L, Hc, x, info["zd"] + 2.7, np.array([0.76, 0.86, 1.0], np.float32), 1.4, 0.8)
        _dot(img, L, Hc, x, info["zd"] - 2.6, np.array([0.55, 0.70, 1.0], np.float32) * 0.8, 1.2, 0.6)
        x += 4.2
    # soft wash on the tower legs (warm, upward) and red crown beacons
    for tc in (info["t1"], info["t2"]):
        for dx in (-7.0, 7.0):
            for zz in range(4, int(info["zt"]), 5):
                f = 0.85 - 0.5 * (zz / info["zt"])
                _dot(img, L, Hc, tc + dx, zz + 2.0, np.array([1.0, 0.80, 0.55], np.float32) * f, 1.7 - 0.5 * zz / info["zt"], 3.6)
            _dot(img, L, Hc, tc + dx, info["zt"] + 4.0, np.array([1.0, 0.16, 0.10], np.float32), 1.6, 1.6)
    # hill houses on the shore
    _window_grid(img, L, Hc, land, rng, p0=0.34, lo=1.5)
    return L, Hc, shapes, land, img


def _colfill_only(img, L, Hc, hcol):
    body = _blank(L, Hc)
    rows = np.arange(H_TEX)[:, None]
    zrow = (1 - (rows + 0.5) / H_TEX) * Hc
    mask = (zrow <= hcol[None, :]) & (hcol[None, :] > 0.0)
    out = img.copy()
    out[mask] = body[mask]
    return out
