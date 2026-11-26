"""Istanbul kit props and skyline cards. Uses the existing props kit generator (Geo, cyl, tube, build_prop).
Blender metres, Z up, every prop faces -Y, long props run along +X from the origin.
"""
import math

import numpy as np
from mathutils import Vector

import build_props as bp
from build_props import Geo, box, cyl, tube, sphere, put, part, light

PR, PRT = 0.0, 0.0


def define_materials():
    bp.define_materials()
    m = bp.mdef
    m("M_Rail", (0.49, 0.51, 0.56), 0.4, 0.8)
    m("M_Cobble", (0.34, 0.33, 0.32), 0.8)
    m("M_Cart_Teal", (0.06, 0.30, 0.34), 0.55)
    m("M_Simit_Dough", (0.62, 0.34, 0.11), 0.75)
    m("M_Fish_Silver", (0.72, 0.76, 0.80), 0.35, 0.6)
    m("M_Skyline_Asia", (0.5, 0.5, 0.5), 0.9, 0.0, (1, 1, 1), 1.6)
    m("M_Skyline_Bridge", (0.5, 0.5, 0.5), 0.9, 0.0, (1, 1, 1), 1.6)
    m("M_Skyline_Domes", (0.5, 0.5, 0.5), 0.9, 0.0, (1, 1, 1), 1.6)


def torus(R, r, mat, seg=8, ring=4, c=(0, 0, 0)):
    V, F = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        for j in range(ring):
            b = 2 * math.pi * j / ring
            rr = R + r * math.cos(b)
            V.append((c[0] + rr * math.cos(a), c[1] + rr * math.sin(a), c[2] + r * math.sin(b)))
    for i in range(seg):
        for j in range(ring):
            F.append((i * ring + j, ((i + 1) % seg) * ring + j, ((i + 1) % seg) * ring + (j + 1) % ring,
                      i * ring + (j + 1) % ring))
    return Geo().add(V, F, mat, True)


def wheel(r, mat_t, mat_h, x, y, z):
    g = put(Geo(), cyl(r, 0.06, mat_t, 14, 1), (x, y, z), rx=90)
    put(g, cyl(r * 0.2, 0.1, mat_h, 8, 1), (x, y, z), rx=90)
    for k in range(4):
        ang = 45 * k
        s = box((r * 1.8, 0.02, 0.025), (0, 0, 0), mat_h)
        put(g, s, (x, y, z), ry=ang)
    return g


def two_sided_quad(g, pts, mat):
    g.add(pts, [(0, 1, 2, 3)], mat, False)
    g.add(pts, [(3, 2, 1, 0)], mat, False)


def awning(g, x0, x1, n, yt, zt, yb, zb, mats):
    w = (x1 - x0) / n
    for k in range(n):
        a, b = x0 + k * w, x0 + (k + 1) * w
        two_sided_quad(g, [(a, yt, zt), (b, yt, zt), (b, yb, zb), (a, yb, zb)], mats[k % 2])


# ----------------------------------------------------------------------------- props
def p_tram():
    L = 12.0
    g = box((L, 3.4, 0.05), (L / 2, 0, 0.025), "M_Cobble")
    for sy in (-1, 1):
        y = sy * 0.7175
        put(g, box((L, 0.13, 0.02), (L / 2, y, 0.01), "M_Rail"))
        put(g, box((L, 0.035, 0.07), (L / 2, y, 0.055), "M_Rail"))
        put(g, box((L, 0.075, 0.035), (L / 2, y, 0.1075), "M_Rail"))
        put(g, box((L, 0.04, 0.012), (L / 2, y + sy * 0.09, 0.056), "M_Metal_Dark"))
    for sy in (-1, 1):                                    # concrete kerb inlay along both edges
        put(g, box((L, 0.1, 0.07), (L / 2, sy * 1.75, 0.035), "M_Concrete"))
    for px in (0.6, L - 0.6):
        py = 2.3
        put(g, cyl(0.22, 0.5, "M_Concrete", 12, 1), (px, py, 0))
        put(g, cyl(0.135, 6.1, "M_Metal_Dark", 12, 6, r2=0.085), (px, py, 0.4))
        put(g, cyl(0.16, 0.14, "M_Metal_Dark", 12, 1), (px, py, 4.1))
        put(g, cyl(0.11, 0.1, "M_Metal_Dark", 12, 1), (px, py, 2.6))
        put(g, sphere(0.1, "M_Metal_Dark", 8, 5), (px, py, 6.58))
        arm = [(px, py - 1.15 * k / 8.0 * 2 * 1.0 / 2 * 2, 5.85 + 0.25 * math.sin(math.pi * k / 8.0) * 0.6 - 0.0 * k) for k in range(9)]
        arm = [(px, py - (py * k / 8.0), 5.9 + 0.22 * math.sin(math.pi * k / 8.0)) for k in range(9)]
        put(g, tube(arm, 0.035, "M_Metal_Dark", 6))
        put(g, tube([(px, py, 5.2), (px, py - 1.1, 5.95)], 0.025, "M_Metal_Dark", 5))
        put(g, cyl(0.045, 0.2, "M_Concrete", 8, 1), (px, 0.0, 5.62))
    # contact wire straight, messenger wire sags between the poles, droppers join them
    put(g, tube([(0.0, 0, 5.5), (L, 0, 5.5)], 0.012, "M_Metal_Dark", 4))
    pts = [(L * k / 12.0, 0, 5.88 - 0.26 * (1 - ((L * k / 12.0 - L / 2) / (L / 2)) ** 2)) for k in range(13)]
    put(g, tube(pts, 0.011, "M_Metal_Dark", 4))
    for x in np.arange(1.2, L, 1.2):
        zm = 5.88 - 0.26 * (1 - ((x - L / 2) / (L / 2)) ** 2)
        put(g, tube([(x, 0, 5.5), (x, 0, zm)], 0.006, "M_Metal_Dark", 3))
    return dict(category="tram", mount="ground", budget=(1200, 4000), emissive=False,
                parts=[part("tram_rail_segment", g)], lights=[],
                notes="12 m tram bed, two rails (1435 mm), two poles with cantilever arms and a catenary; runs along +X, poles on +Y side")


def p_cobble():
    L = 12.0
    rng = np.random.default_rng(5)
    g = box((L, 1.2, 0.03), (L / 2, 1.0, 0.015), "M_Cobble")
    n = 12
    for i in range(n):
        put(g, box((L / n - 0.015, 0.22, 0.17), (L / n * (i + 0.5), -0.11, 0.085), "M_Concrete"))
    for row in range(3):
        x = -0.1 * (row % 2) * 2.0
        y = 0.07 + row * 0.15
        k = 0
        while x < L - 0.2:
            w = 0.24 + 0.06 * rng.random()
            hh = 0.03 + 0.025 * rng.random()
            put(g, box((w - 0.015, 0.135, hh * 2), (max(x, 0) + w / 2, y, 0.0 + hh * 0.5 + 0.015), "M_Cobble"))
            x += w
            k += 1
    return dict(category="street", mount="ground", budget=(800, 3000), emissive=False,
                parts=[part("cobble_strip", g)], lights=[],
                notes="12 m granite kerb with 3 rows of setts and a cobble field; kerb on -Y (road side), runs along +X, 1.6 m deep")


def p_railing():
    L = 6.0
    g = box((L, 0.3, 0.4), (L / 2, 0, 0.2), "M_Concrete")
    put(g, box((L, 0.36, 0.06), (L / 2, 0, 0.43), "M_Concrete"))
    zt, zm = 1.28, 0.78
    for k in range(5):
        x = k * 1.5
        put(g, cyl(0.055, zt - 0.46, "M_Metal_Dark", 8, 1), (x, 0, 0.46))
        put(g, sphere(0.085, "M_Metal_Dark", 8, 5), (x, 0, zt + 0.04))
        put(g, cyl(0.085, 0.07, "M_Metal_Dark", 8, 1), (x, 0, 0.46))
    put(g, cyl(0.032, L, "M_Metal_Dark", 8, 1), (0, 0, zt), ry=90)
    put(g, cyl(0.025, L, "M_Metal_Dark", 8, 1), (0, 0, zm), ry=90)
    put(g, box((L, 0.03, 0.03), (L / 2, 0, 0.55), "M_Metal_Dark"))
    x = 0.12
    while x < L - 0.05:
        if abs((x % 1.5)) > 0.05 and abs((x % 1.5) - 1.5) > 0.05:
            put(g, box((0.016, 0.016, zt - 0.55), (x, 0, 0.55 + (zt - 0.55) / 2), "M_Metal_Dark"))
        x += 0.15
    for k in range(4):                                    # scroll ring in each bay
        cx, cz, r = 0.75 + k * 1.5, 0.92, 0.19
        pts = [(cx + r * math.cos(2 * math.pi * i / 12), 0.0, cz + r * math.sin(2 * math.pi * i / 12)) for i in range(12)]
        put(g, tube(pts, 0.014, "M_Metal_Dark", 4, closed=True))
    return dict(category="furniture", mount="ground", budget=(600, 2500), emissive=False,
                parts=[part("seaside_railing", g)], lights=[],
                notes="6 m cast-iron promenade railing on a stone kerb, 4 bays with scroll rings; runs along +X, sea side on -Y")


def p_lamp():
    g = put(Geo(), cyl(0.28, 0.25, "M_Concrete", 8, 1))
    put(g, cyl(0.22, 0.9, "M_Metal_Dark", 8, 3, r2=0.11), (0, 0, 0.25))
    put(g, cyl(0.075, 2.9, "M_Metal_Dark", 10, 3, r2=0.06), (0, 0, 1.1))
    for z in (1.25, 2.0, 3.85):
        put(g, cyl(0.11, 0.07, "M_Metal_Dark", 10, 1), (0, 0, z))
    put(g, cyl(0.2, 0.1, "M_Metal_Dark", 6, 1), (0, 0, 3.98))
    glass = put(Geo(), cyl(0.17, 0.52, "M_Lamp_Sodium", 6, 1, r2=0.21), (0, 0, 4.08))
    for k in range(6):
        a = 2 * math.pi * k / 6
        put(g, box((0.03, 0.03, 0.52), (0.19 * math.cos(a), 0.19 * math.sin(a), 4.34), "M_Metal_Dark"))
    put(g, cyl(0.27, 0.24, "M_Metal_Dark", 6, 1, r2=0.03), (0, 0, 4.6))
    put(g, sphere(0.05, "M_Metal_Dark", 6, 4), (0, 0, 4.88))
    for s in (-1, 1):
        pts = [(s * 0.78 * k / 8.0, 0, 2.6 + 0.4 * math.sin(math.pi * 0.5 * k / 8.0) + 0.0 * k) for k in range(9)]
        put(g, tube(pts, 0.025, "M_Metal_Dark", 6))
        put(glass, sphere(0.13, "M_Lamp_Sodium", 8, 5), (s * 0.8, 0, 3.12))
        put(g, cyl(0.1, 0.05, "M_Metal_Dark", 8, 1), (s * 0.8, 0, 2.93))
    return dict(category="lamp", mount="ground", budget=(500, 2000), emissive=True,
                parts=[part("promenade_lamp_body", g), part("promenade_lamp_glass", glass)],
                lights=[light((0, 0, 4.3), [1.0, 0.72, 0.45], 10.0, 22.0)],
                notes="4.9 m cast-iron promenade lamp, hex lantern on top plus two side globes")


def p_simit():
    g = box((1.7, 0.8, 0.5), (0, 0, 0.55), "M_Cart_Teal")
    put(g, box((1.76, 0.86, 0.04), (0, 0, 0.82), "M_Wood_Dark"))
    put(g, wheel(0.36, "M_Metal_Dark", "M_Metal_Grey", -0.45, 0.46, 0.36))
    put(g, wheel(0.36, "M_Metal_Dark", "M_Metal_Grey", -0.45, -0.46, 0.36))
    for sy in (-1, 1):
        put(g, box((0.05, 0.05, 0.4), (0.78, sy * 0.3, 0.2), "M_Metal_Dark"))
    put(g, tube([(-0.85, 0, 0.9), (-1.35, 0, 1.0), (-1.45, 0, 0.98)], 0.022, "M_Metal_Dark", 6))
    for sx in (-1, 1):
        for sy in (-1, 1):
            put(g, box((0.035, 0.035, 0.78), (sx * 0.83, sy * 0.38, 1.22), "M_Cart_Teal"))
    put(g, box((1.8, 0.9, 0.05), (0, 0, 1.64), "M_Cart_Teal"))
    for z in (1.08, 1.38):
        put(g, box((1.64, 0.74, 0.02), (0, 0, z), "M_Wood_Dark"))
    rings = Geo()
    for z in (1.09, 1.39):
        for px in (-0.55, 0.0, 0.55):
            for k in range(3):
                put(rings, torus(0.085, 0.024, "M_Simit_Dough", 8, 4), (px, 0.0, z + 0.025 + k * 0.05))
    g.merge(rings)
    bulbs = Geo()
    put(bulbs, box((1.6, 0.04, 0.03), (0, -0.36, 1.59), "M_Bulb_Amber"))
    awning(g, -0.9, 0.9, 8, -0.47, 1.66, -1.0, 1.32, ["M_Awning_A", "M_Awning_B"])
    for k in range(6):
        put(bulbs, sphere(0.032, "M_Bulb_Amber", 6, 4), (-0.8 + k * 0.32, -1.0, 1.29))
    return dict(category="cart", mount="ground", budget=(800, 2500), emissive=True,
                parts=[part("simit_cart", g), part("simit_cart_lamps", bulbs)],
                lights=[light((0, -0.7, 1.45), [1.0, 0.72, 0.42], 2.6, 6.0)],
                notes="Wheeled simit stand, open display cabinet, striped awning, string bulbs; fronts -Y, handle on -X (original design, no text)")


def p_fish():
    g = box((2.2, 0.9, 0.72), (0, 0, 0.5), "M_Cart_Teal")
    put(g, box((2.28, 0.98, 0.05), (0, 0, 0.885), "M_Wood_Dark"))
    for sx in (-1, 1):
        for sy in (-1, 1):
            put(g, wheel(0.3, "M_Metal_Dark", "M_Metal_Grey", sx * 0.85, sy * 0.52, 0.3))
    put(g, box((0.7, 0.5, 0.14), (-0.6, 0, 0.98), "M_Metal_Dark"))
    put(g, box((0.9, 0.5, 0.05), (0.5, 0, 0.935), "M_Metal_Grey"))
    for k in range(8):
        fx = 0.17 + 0.095 * k
        fy = -0.17 + 0.1 * (k % 4)
        put(g, cyl(0.035, 0.24, "M_Fish_Silver", 6, 2, r2=0.012), (0.1 + 0.115 * (k // 4) * 0 + fx - 0.45 + 0.4, fy, 0.99), ry=90, rz=0)
    put(g, box((0.4, 0.3, 0.25), (1.45, 0.1, 0.125), "M_Wood_Dark"))
    put(g, box((0.4, 0.3, 0.25), (1.45, 0.1, 0.375), "M_Wood_Dark"))
    for sx in (-1, 1):
        put(g, cyl(0.025, 1.2, "M_Metal_Grey", 6, 1), (sx * 1.05, 0.42, 0.95))
        put(g, cyl(0.025, 0.95, "M_Metal_Grey", 6, 1), (sx * 1.05, -0.42, 0.95))
    awning(g, -1.15, 1.15, 10, 0.5, 2.18, -0.52, 1.88, ["M_Awning_B", "M_Awning_A"])
    hot = Geo()
    put(hot, box((0.62, 0.42, 0.02), (-0.6, 0, 1.06), "M_Bulb_Red"))
    for k in range(7):
        put(hot, sphere(0.035, "M_Bulb_Amber", 6, 4), (-0.95 + k * 0.32, -0.52, 1.86))
    return dict(category="cart", mount="ground", budget=(800, 3000), emissive=True,
                parts=[part("fish_cart", g), part("fish_cart_glow", hot)],
                lights=[light((-0.2, -0.3, 1.6), [1.0, 0.62, 0.32], 3.2, 7.0)],
                notes="Wheeled fish-and-bread stall: coal grill, silver fish tray, striped canopy; fronts -Y (original design, no text)")


def p_pier():
    g = put(Geo(), cyl(0.3, 0.25, "M_Concrete", 10, 1))
    put(g, cyl(0.2, 0.7, "M_Metal_Dark", 10, 3, r2=0.11), (0, 0, 0.25))
    put(g, cyl(0.09, 3.9, "M_Metal_Dark", 10, 3, r2=0.07), (0, 0, 0.95))
    for z in (1.6, 3.1):
        put(g, cyl(0.13, 0.08, "M_Metal_Dark", 10, 1), (0, 0, z))
    put(g, tube([(-0.62, 0, 4.55), (0, 0, 4.62), (0.62, 0, 4.55)], 0.03, "M_Metal_Dark", 6))
    glass = Geo()
    for s in (-1, 1):
        put(g, cyl(0.02, 0.1, "M_Metal_Dark", 6, 1), (s * 0.62, 0, 4.47))
        put(glass, cyl(0.1, 0.26, "M_Lamp_Cool", 8, 1, r2=0.13), (s * 0.62, 0, 4.2))
        put(g, cyl(0.15, 0.1, "M_Metal_Dark", 8, 1, r2=0.04), (s * 0.62, 0, 4.46))
    put(g, cyl(0.2, 0.08, "M_Metal_Dark", 10, 1), (0, 0, 4.66))
    put(glass, sphere(0.19, "M_Lamp_Cool", 10, 6), (0, 0, 4.9))
    put(g, cyl(0.12, 0.1, "M_Metal_Dark", 8, 1, r2=0.02), (0, 0, 5.08))
    put(glass, sphere(0.065, "M_Bulb_Red", 6, 4), (0, 0, 5.24))
    return dict(category="lamp", mount="ground", budget=(400, 2000), emissive=True,
                parts=[part("ferry_pier_light_body", g), part("ferry_pier_light_glass", glass)],
                lights=[light((0, 0, 4.8), [0.75, 0.86, 1.0], 8.0, 24.0), light((0, 0, 5.24), [1.0, 0.2, 0.14], 1.5, 7.0)],
                notes="5.3 m ferry pier mast light: two cool lanterns, a globe and a red end-of-pier marker")


# ----------------------------------------------------------------------------- skyline cards
def card_from_columns(L, Hc, hcol, R=900.0, step=6):
    """Curved card cut to a height profile: runs of equal height merged to keep tris low."""
    a = L / R
    n = len(hcol)
    xs, hs = [], []
    for i in range(0, n, step):
        seg = hcol[i:i + step + 1]
        xs.append(i)
        hs.append(float(seg.max()))
    xs.append(n)
    hs.append(hs[-1])
    pts = []
    for x, h in zip(xs, hs):
        pts.append((x, h))
    keep = [pts[0]]
    for k in range(1, len(pts) - 1):
        if abs(pts[k][1] - keep[-1][1]) < 0.15 and abs(pts[k][1] - pts[k + 1][1]) < 0.15:
            continue
        keep.append(pts[k])
    keep.append(pts[-1])
    V, F = [], []
    for x, h in keep:
        th = -a / 2 + a * x / float(n)
        V.append((R * math.sin(th), -R + R * math.cos(th), 0.0))
    for (x, h) in keep:
        th = -a / 2 + a * x / float(n)
        V.append((R * math.sin(th), -R + R * math.cos(th), max(h, 0.0)))
    m = len(keep)
    for i in range(m - 1):
        if keep[i][1] <= 0.0 and keep[i + 1][1] <= 0.0:
            continue
        F.append((i, i + 1, m + i + 1, m + i))
    return V, F


def card_from_quads(L, R, quads):
    a = L / R
    V, F = [], []
    for q in quads:
        base = len(V)
        for u, z in q:
            th = -a / 2 + a * u / L
            V.append((R * math.sin(th), -R + R * math.cos(th), z))
        n = len(q)
        F.append(tuple(range(base, base + n)) if n == 3 else (base, base + 1, base + 2, base + 3))
    return V, F


def make_card(name, mat, L, Hc, V, F, R=900.0):
    a = L / R
    g = Geo().add(V, F, mat, False)
    uvf = lambda co: ((math.atan2(co.x, co.y + R) + a / 2) / a, co.z / Hc)
    spec = dict(category="skyline", mount="ground", budget=None, emissive=True,
                parts=[part(name, g, 0.0, uvf)], lights=[],
                notes="")
    return spec
