"""Track road generator (Blender 5.3, deterministic). Config driven: one JSON per track in configs/.

Run:
  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup \
      --python build_road.py -- --config configs/city_01.json [--render]
City 01 keeps its old entry point: assets_src/world/city_01/build_road.py passes configs/city_01.json.
Outputs (config out_dir): <id>_road.glb, materials.json, <id>_centerline.json, report.json, renders in render_dir.
Blender coords: X east, Y north, Z up. Engine JSON uses godot = (x, z, -y).
"""
import bpy
import bisect
import json
import math
import os
import random
import sys
import time

import numpy as np

T_START = time.time()
HERE = os.path.dirname(os.path.abspath(__file__))
ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_RENDER = "--render" in ARGV
if "--config" not in ARGV:
    raise SystemExit("build_road.py needs -- --config <track.json>")
CFG_PATH = os.path.abspath(ARGV[ARGV.index("--config") + 1])
CFG = json.load(open(CFG_PATH, encoding="utf-8"))
RCFG = CFG["road"]
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, RCFG["out_dir"])
REN = os.path.join(REPO, RCFG["render_dir"])
PREFIX = CFG["id"]
os.makedirs(OUT, exist_ok=True)
os.makedirs(REN, exist_ok=True)

# ----------------------------------------------------------------- constants
CP = [tuple(p) for p in RCFG["cp"]]
DS = 2.0
ROAD_W = float(RCFG["road_w"])
WIDE_W = float(RCFG.get("wide_w", ROAD_W))
KERB_OUT = 0.30
SIDE_W = 3.5
PROM_W = 6.0
GZ = -0.3          # street level ground plane
WATER_Z = -1.2
WATER_EXT = 400.0
CROWN = 0.015
CHUNK_M = 120.0
CEIL_H = 5.2
GCELL = 12.0
M_PER = 200        # dense CR samples per control segment
DIST_NAMES = RCFG["dist_names"]
DIST_OF_PT = RCFG["dist_of_pt"]

MAT_SPEC = {
    "M_Asphalt": dict(hex="#1E232B", rough=0.30, metal=0.0, emis=None, strength=0.0,
                      uv="U across road (m), V along (m)",
                      note="wet asphalt; R = puddle mask, G = racing-groove wear, B = district/4"),
    "M_Curb": dict(hex="#8E8B84", rough=0.8, metal=0.0, emis=None, strength=0.0,
                   uv="U across (m), V along (m)", note="kerb 0.15 m, bevelled road edge"),
    "M_Paving": dict(hex="#5D6168", rough=0.7, metal=0.0, emis=None, strength=0.0,
                     uv="U across (m), V along (m)", note="paving slab sidewalk"),
    "M_Water": dict(hex="#0A1828", rough=0.05, metal=0.0, emis=None, strength=0.0,
                    uv="none", note="bay water plane at z=-1.2"),
    "M_RoadPaint": dict(hex="#E4E2D6", rough=0.6, metal=0.0, emis=None, strength=0.0,
                        uv="U = metres from right edge, V = metres along; tile worn paint", note="5 mm above asphalt"),
    "M_Concrete_Wall": dict(hex="#4A4E57", rough=0.85, metal=0.0, emis=None, strength=0.0,
                            uv="U and V in metres", note="retaining walls, parapets, tunnel walls, quay face"),
    "M_TunnelLight": dict(hex="#BFD8FF", rough=0.3, metal=0.0, emis="#BFD8FF", strength=12.0,
                          uv="metres", note="recessed ceiling light strips, emissive"),
    "M_TunnelStripe": dict(hex="#FFC23D", rough=0.6, metal=0.0, emis="#FFC23D", strength=0.4,
                           uv="metres", note="painted wall stripe in underpass"),
    "M_Ground": dict(hex="#2B2F36", rough=0.9, metal=0.0, emis=None, strength=0.0,
                     uv="world metres (x, y)", note="low-poly street level ground"),
    "M_Manhole": dict(hex="#3A3F47", rough=0.6, metal=0.3, emis=None, strength=0.0,
                      uv="decal", note="manhole cover decal, 3 mm above road"),
    "M_Grate": dict(hex="#2A2D33", rough=0.5, metal=0.6, emis=None, strength=0.0,
                    uv="decal", note="drain grate decal, 3 mm above road"),
    "M_ExpansionJoint": dict(hex="#15171B", rough=0.9, metal=0.0, emis=None, strength=0.0,
                             uv="metres", note="deck expansion joints"),
    "M_Rail": dict(hex="#7C8290", rough=0.4, metal=0.8, emis=None, strength=0.0,
                   uv="metres", note="steel top rail on parapets"),
}
if RCFG.get("cobble_cp"):   # cobbled street surface (Istanbul tracks): the engine binds M_Cobble from the Istanbul kit
    MAT_SPEC["M_Cobble"] = dict(hex="#6B665F", rough=0.7, metal=0.0, emis=None, strength=0.0,
                                uv="metres, tiled 1 m", note="granite setts, road surface of the cobbled section")
SLOTS = {
    "road": ["M_Asphalt", "M_Curb"] + (["M_Cobble"] if RCFG.get("cobble_cp") else []),
    "sidewalk": ["M_Paving", "M_Concrete_Wall"],
    "structure": ["M_Concrete_Wall", "M_Rail", "M_TunnelLight", "M_TunnelStripe"],
    "wall": ["M_Concrete_Wall"],
    "markings": ["M_RoadPaint", "M_ExpansionJoint"],
    "decals": ["M_Manhole", "M_Grate"],
    "water": ["M_Water"],
    "ground": ["M_Ground"],
}
NAMES = {
    "road": "road_{:02d}-col", "sidewalk": "sidewalk_{:02d}-col",
    "structure": "structure_{:02d}-col", "wall": "wall_{:02d}-colonly",
    "markings": "markings_{:02d}", "decals": "decals_{:02d}",
}
SINGLE_NAMES = {"water": "water_00", "ground": "ground-col"}


# ----------------------------------------------------------------- helpers
def clamp(x, a=0.0, b=1.0):
    return a if x < a else b if x > b else x


def smooth(t):
    t = clamp(t)
    return t * t * (3.0 - 2.0 * t)


def blend_in(s, a, b, r):
    """1 on [a, b], smooth ramp to 0 over r metres outside."""
    if a <= s <= b:
        return 1.0
    if s < a:
        return smooth(1.0 - (a - s) / r) if a - s < r else 0.0
    return smooth(1.0 - (s - b) / r) if s - b < r else 0.0


def srgb_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_lin(h):
    h = h.lstrip("#")
    return tuple(srgb_lin(int(h[k:k + 2], 16) / 255.0) for k in (0, 2, 4))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def wrap_pi(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def gsmooth(vals, sigma):
    n = len(vals)
    r = int(3 * sigma)
    ker = [(k, math.exp(-0.5 * (k / sigma) ** 2)) for k in range(-r, r + 1)]
    ks = sum(w for _, w in ker)
    out = []
    for i in range(n):
        acc = 0.0
        for k, w in ker:
            acc += w * vals[(i + k) % n]
        out.append(acc / ks)
    return out


def _comb(a, wa, b, wb):
    return tuple(wa * a[k] + wb * b[k] for k in range(3))


def cr_closed(pts, m):
    """Closed centripetal Catmull-Rom (alpha 0.5) through pts, m samples per segment."""
    n = len(pts)
    dense = []
    for i in range(n):
        p0, p1, p2, p3 = pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]

        def dd(a, b):
            return max(math.hypot(b[0] - a[0], b[1] - a[1]), 1e-6) ** 0.5

        t0 = 0.0
        t1 = t0 + dd(p0, p1)
        t2 = t1 + dd(p1, p2)
        t3 = t2 + dd(p2, p3)
        for k in range(m):
            t = t1 + (t2 - t1) * k / m
            a1 = _comb(p0, (t1 - t) / (t1 - t0), p1, (t - t0) / (t1 - t0))
            a2 = _comb(p1, (t2 - t) / (t2 - t1), p2, (t - t1) / (t2 - t1))
            a3 = _comb(p2, (t3 - t) / (t3 - t2), p3, (t - t2) / (t3 - t2))
            b1 = _comb(a1, (t2 - t) / (t2 - t0), a2, (t - t0) / (t2 - t0))
            b2 = _comb(a2, (t3 - t) / (t3 - t1), a3, (t - t1) / (t3 - t1))
            dense.append(_comb(b1, (t2 - t) / (t2 - t1), b2, (t - t1) / (t2 - t1)))
    return dense


# ----------------------------------------------------------------- centreline
# Helper point (not in the brief): bulges the waterfront 20 m east to lift lap length
# from 2199.4 m to 2203 m. Brief control point numbers are kept via KNOT_IDX.
HELPER = RCFG.get("helper")   # {"after_cp": 9, "pos": [x, y, z], "reason": "..."} or null
if HELPER:
    HELPER_WF = tuple(HELPER["pos"])
    _ac = int(HELPER["after_cp"])
    PTS = CP[:_ac + 1] + [HELPER_WF] + CP[_ac + 1:]
    KNOT_IDX = [i * M_PER if i <= _ac else (i + 1) * M_PER for i in range(len(CP))]
else:
    HELPER_WF = None
    PTS = list(CP)
    KNOT_IDX = [i * M_PER for i in range(len(CP))]
DENSE = cr_closed(PTS, M_PER)
ND = len(DENSE)
CUM = [0.0]
for _k in range(ND):
    _a = DENSE[_k]
    _b = DENSE[(_k + 1) % ND]
    CUM.append(CUM[-1] + math.hypot(_b[0] - _a[0], _b[1] - _a[1]))
LAP = CUM[-1]
NS = round(LAP / DS)
DSA = LAP / NS
SARC = [k * DSA for k in range(NS)]
S_CP = [CUM[k] for k in KNOT_IDX]


def dense_at(s):
    j = min(max(bisect.bisect_right(CUM, s) - 1, 0), ND - 1)
    a = DENSE[j]
    b = DENSE[(j + 1) % ND]
    seg = CUM[j + 1] - CUM[j]
    f = (s - CUM[j]) / seg if seg > 1e-9 else 0.0
    return tuple(a[k] + (b[k] - a[k]) * f for k in range(3))


_SP = [dense_at(s) for s in SARC]
SX = [p[0] for p in _SP]
SY = [p[1] for p in _SP]
SZ = gsmooth([p[2] for p in _SP], 6.0)

TXa, TYa = [], []
for _i in range(NS):
    _a = (SX[(_i - 1) % NS], SY[(_i - 1) % NS])
    _b = (SX[(_i + 1) % NS], SY[(_i + 1) % NS])
    _dx, _dy = _b[0] - _a[0], _b[1] - _a[1]
    _l = math.hypot(_dx, _dy)
    TXa.append(_dx / _l)
    TYa.append(_dy / _l)
LXa = [-t for t in TYa]   # left of travel direction
LYa = [t for t in TXa]

HD = [math.atan2(TYa[i], TXa[i]) for i in range(NS)]
_kraw = [wrap_pi(HD[(i + 1) % NS] - HD[(i - 1) % NS]) / (2 * DSA) for i in range(NS)]
KAP = []
for _i in range(NS):
    _vals = [_kraw[(_i + k) % NS] for k in (-2, -1, 0, 1, 2)]
    KAP.append(sum(_vals) / 5.0)   # signed: + left turn, - right turn (clockwise loop)

SLOPE = [(SZ[(i + 1) % NS] - SZ[(i - 1) % NS]) / (2 * DSA) for i in range(NS)]

_wide = RCFG.get("wide_cp")
WID = [ROAD_W + (WIDE_W - ROAD_W) * (blend_in(s, S_CP[_wide[0]], S_CP[_wide[1]], 40.0) if _wide else 0.0)
       for s in SARC]
_narrow = RCFG.get("narrow_cp")   # [cp_a, cp_b]: road narrows to narrow_w (old street), 40 m blends
if _narrow:
    _nw = float(RCFG["narrow_w"])
    WID = [w - (ROAD_W - _nw) * blend_in(s, S_CP[_narrow[0]], S_CP[_narrow[1]], 40.0) for w, s in zip(WID, SARC)]
_cob = RCFG.get("cobble_cp")      # [cp_a, cp_b]: road surface is M_Cobble, no paint
COB = [bool(_cob) and S_CP[_cob[0]] <= s < S_CP[_cob[1]] for s in SARC]
_prom = RCFG.get("prom_cp")    # promenade + open water on the left; null = none
PB = [blend_in(s, S_CP[_prom[0]], S_CP[_prom[1]], 25.0) if _prom else 0.0 for s in SARC]
WSL = [SIDE_W + (PROM_W - SIDE_W) * p for p in PB]
_bank = RCFG.get("bank_cp")
if _bank:
    _kmax = max(abs(KAP[i]) for i in range(NS) if S_CP[_bank[0]] <= SARC[i] <= S_CP[_bank[1]])
    BANK = [clamp(3.0 * KAP[i] / _kmax, -3.0, 3.0) * blend_in(SARC[i], S_CP[_bank[0]], S_CP[_bank[1]], 30.0)
            for i in range(NS)]
else:
    BANK = [0.0] * NS
TANB = [math.tan(math.radians(b)) for b in BANK]
DIST = [DIST_OF_PT[bisect.bisect_right(S_CP, s) - 1] for s in SARC]
CH_COUNT = int(math.ceil(LAP / CHUNK_M))
CH = [min(int(s // CHUNK_M), CH_COUNT - 1) for s in SARC]
_tube = RCFG.get("tube_cp")
TUBE = [(S_CP[_tube[0]] <= s < S_CP[_tube[1]]) if _tube else False for s in SARC]
ELEV = [SZ[i] > 0.8 for i in range(NS)]
CUT = [(SZ[i] < -0.75) and not TUBE[i] for i in range(NS)]
WATER = [PB[i] > 0.02 for i in range(NS)]


def uo(k, side):
    """Building-line offset from centreline at sample k, side +1 left / -1 right."""
    return WID[k] / 2.0 + KERB_OUT + (WSL[k] if side > 0 else SIDE_W)


def P3(k, u, dz):
    """Point on sample k at lateral u (+left) and dz above the banked plane."""
    return (SX[k] + u * LXa[k], SY[k] + u * LYa[k], SZ[k] + TANB[k] * u + dz)


def fr(s):
    x = (s % LAP) / DSA
    i0 = int(x) % NS
    f = x - int(x)
    i1 = (i0 + 1) % NS

    def lp(a):
        return a[i0] + (a[i1] - a[i0]) * f

    return lp(SX), lp(SY), lp(SZ), lp(TANB), lp(LXa), lp(LYa), lp(WID)


def road_pt(s, u, extra=0.0):
    x, y, z, tn, lx, ly, w = fr(s)
    return (x + u * lx, y + u * ly, z + tn * u + CROWN * max(0.0, w / 2.0 - abs(u)) + extra)


def chunk_of_s(s):
    return min(int((s % LAP) // CHUNK_M), CH_COUNT - 1)


def g(v):
    """Blender -> Godot coords."""
    return (v[0], v[2], -v[1])


# ----------------------------------------------------------------- checks
def arc_sep(a, b):
    d = abs(SARC[a] - SARC[b])
    return min(d, LAP - d)


def _circum(i):
    """Circumradius of three consecutive 2 m samples (strictest window: 2 m step)."""
    ax, ay = SX[i - 1], SY[i - 1]
    bx, by = SX[i], SY[i]
    cx, cy = SX[(i + 1) % NS], SY[(i + 1) % NS]
    cr2 = abs((bx - ax) * (cy - ay) - (by - ay) * (cx - ax))
    if cr2 < 1e-9:
        return 1e9
    ab = math.hypot(bx - ax, by - ay)
    bc = math.hypot(cx - bx, cy - by)
    ac = math.hypot(cx - ax, cy - ay)
    return ab * bc * ac / (2.0 * cr2)


R_SAMPLE = [_circum(i) for i in range(NS)]
RMIN = min(R_SAMPLE)
RMIN_S = SARC[R_SAMPLE.index(RMIN)]
GRAD_MAX = max(abs(x) for x in SLOPE)
# closest plan approach per minimum arc separation; 150 m is the "non-adjacent" definition
NA_THR = (45.0, 100.0, 150.0)
_na = {t: (1e9, -1, -1) for t in NA_THR}
for _i in range(NS):
    for _j in range(_i + 1, NS):
        _sep = arc_sep(_i, _j)
        if _sep < NA_THR[0]:
            continue
        _d = math.hypot(SX[_i] - SX[_j], SY[_i] - SY[_j])
        for _t in NA_THR:
            if _sep >= _t and _d < _na[_t][0]:
                _na[_t] = (_d, _i, _j)
NONADJ_MIN, NA_I, NA_J = _na[150.0]
CHECKS = {
    "lap_length_m": round(LAP, 2),
    "lap_length_ok": RCFG["lap_range"][0] <= LAP <= RCFG["lap_range"][1],
    "min_radius_m": round(RMIN, 2),
    "min_radius_method": "circumradius of 3 consecutive 2 m centreline samples",
    "min_radius_at_s": round(RMIN_S, 1),
    "min_radius_ok": RMIN >= RCFG["rmin_m"],
    "max_gradient_pct": round(GRAD_MAX * 100, 2),
    "max_gradient_ok": GRAD_MAX <= 0.06,
    "nonadjacent_def": "arc separation >= 150 m (shorter spans are the same bend or sweep)",
    "nonadjacent_min_plan_dist_m": round(NONADJ_MIN, 2),
    "nonadjacent_pair_s": [round(SARC[NA_I], 1), round(SARC[NA_J], 1)],
    "nonadjacent_ok_45m": NONADJ_MIN >= 45.0,
    "nonadjacent_min_arc45_m": [round(_na[45.0][0], 2), round(SARC[_na[45.0][1]], 1), round(SARC[_na[45.0][2]], 1)],
    "nonadjacent_min_arc100_m": [round(_na[100.0][0], 2), round(SARC[_na[100.0][1]], 1), round(SARC[_na[100.0][2]], 1)],
    "sample_spacing_m": round(DSA, 4),
    "sample_count": NS,
    "seam_gap_m": round(math.hypot(SX[0] - SX[NS - 1], SY[0] - SY[NS - 1]), 3),
    "cp_s_m": [round(s, 1) for s in S_CP],
}
print("CHECKS", json.dumps(CHECKS))


# ----------------------------------------------------------------- geometry builders
class Bld:
    def __init__(self, name):
        self.name = name
        self.v, self.uv, self.col, self.f, self.m = [], [], [], [], []

    def poly(self, pts, uvs, cols, mat, hint, dbl=False):
        if len(pts) == 4:
            n = cross(sub(pts[2], pts[0]), sub(pts[3], pts[1]))
        else:
            n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
        if dot(n, n) < 1e-14:
            return
        ids = []
        for p, uv, c in zip(pts, uvs, cols):
            self.v.append(tuple(p))
            self.uv.append(tuple(uv))
            self.col.append(tuple(c))
            ids.append(len(self.v) - 1)
        if dot(n, hint) < 0:
            ids.reverse()
        self.f.append(tuple(ids))
        self.m.append(mat)
        if dbl:
            # back face gets its own vertices: shared-vertex back faces make Blender report the mesh invalid
            self.poly(list(pts)[::-1], list(uvs)[::-1], list(cols)[::-1], mat, tuple(-c for c in hint))


BLD = {}


def bld(kind, k=0):
    key = (kind, k)
    if key not in BLD:
        name = NAMES[kind].format(k) if kind in NAMES else SINGLE_NAMES[kind]
        BLD[key] = Bld(name)
    return BLD[key]


def dcol(k):
    return (0.0, 0.0, DIST[k] / 4.0, 1.0)


def extrude(Bd, idxs, segs):
    """segs: (fuA(k), fzA(k,u), fuB(k), fzB(k,u), hint_u, hint_z, mat, dbl). Quads from sample i to i+1."""
    for i in idxs:
        i2 = (i + 1) % NS
        Va = SARC[i]
        Vb = SARC[i2] if i2 > 0 else LAP
        for fuA, fzA, fuB, fzB, hu, hz, mat, dbl in segs:
            uAi, uA2 = fuA(i), fuA(i2)
            uBi, uB2 = fuB(i), fuB(i2)
            zAi, zA2 = fzA(i, uAi), fzA(i2, uA2)
            zBi, zB2 = fzB(i, uBi), fzB(i2, uB2)
            pts = [P3(i, uAi, zAi), P3(i2, uA2, zA2), P3(i2, uB2, zB2), P3(i, uBi, zBi)]
            cA = 0.0
            cB = math.hypot(uBi - uAi, zBi - zAi)
            uvs = [(cA, Va), (cA, Vb), (cB, Vb), (cB, Va)]
            cols = [dcol(i), dcol(i2), dcol(i2), dcol(i)]
            Bd.poly(pts, uvs, cols, mat, (hu * LXa[i], hu * LYa[i], hz), dbl)


def cz(v):
    return lambda k, u: v


def absz(zabs):
    return lambda k, u: zabs - SZ[k] - TANB[k] * u


def rect(fuc, hwf, zlo, zhi, mat, sides="RTL", flip=False):
    """Rectangle profile in (u, dz): R right, T top, L left, B bottom. Hints point outward unless flip."""
    segs = []
    if "R" in sides:
        segs.append((lambda k: fuc(k) + hwf(k), zlo, lambda k: fuc(k) + hwf(k), zhi, 1.0, 0.0, mat, False))
    if "T" in sides:
        segs.append((lambda k: fuc(k) + hwf(k), zhi, lambda k: fuc(k) - hwf(k), zhi, 0.0, 1.0, mat, False))
    if "L" in sides:
        segs.append((lambda k: fuc(k) - hwf(k), zhi, lambda k: fuc(k) - hwf(k), zlo, -1.0, 0.0, mat, False))
    if "B" in sides:
        segs.append((lambda k: fuc(k) - hwf(k), zlo, lambda k: fuc(k) + hwf(k), zlo, 0.0, -1.0, mat, False))
    if flip:
        segs = [(a, b, c, d, -e, -f, m, dd) for a, b, c, d, e, f, m, dd in segs]
    return segs


def slab(ful, fur, zlo, zhi, mat):
    """Closed box slab between left edge ful(k) and right edge fur(k) (fur < 0), outward hints."""
    return [(fur, zlo, fur, zhi, -1.0, 0.0, mat, False),
            (fur, zhi, ful, zhi, 0.0, 1.0, mat, False),
            (ful, zhi, ful, zlo, 1.0, 0.0, mat, False),
            (ful, zlo, fur, zlo, 0.0, -1.0, mat, False)]


def cap_rect(Bd, k, u0, u1, z0, z1, mat, facing):
    pts = [P3(k, u0, z0), P3(k, u1, z0), P3(k, u1, z1), P3(k, u0, z1)]
    uvs = [(u0, 0.0), (u1, 0.0), (u1, z1 - z0), (u0, z1 - z0)]
    cols = [dcol(k)] * 4
    Bd.poly(pts, uvs, cols, mat, (TXa[k] * facing, TYa[k] * facing, 0.0))


# ----------------------------------------------------------------- road surface
def build_road_surface():
    for i in range(NS):
        i2 = (i + 1) % NS
        Bd = bld("road", CH[i])
        Va = SARC[i]
        Vb = SARC[i2] if i2 > 0 else LAP
        for j in range(8):
            corners = [(i, j), (i2, j), (i2, j + 1), (i, j + 1)]
            pts, uvs, cols = [], [], []
            for k, jj in corners:
                w = WID[k]
                u = -w / 2.0 + w * jj / 8.0
                V = Va if k == i else Vb
                crown = CROWN * max(0.0, w / 2.0 - abs(u))
                pts.append((SX[k] + u * LXa[k], SY[k] + u * LYa[k], SZ[k] + TANB[k] * u + crown))
                uvs.append((u + w / 2.0, V))
                puddle = puddle_at(k, u)
                groove = 0.2 + 0.55 * math.exp(-((u - 2.0) / 1.2) ** 2)
                cols.append((puddle, clamp(groove), DIST[k] / 4.0, 1.0))
            Bd.poly(pts, uvs, cols, 2 if COB[i] else 0, (0.0, 0.0, 1.0))


PUDDLE_PATCHES = []


def _init_patches():
    rng = random.Random(7711)
    for _ in range(70):
        PUDDLE_PATCHES.append((rng.uniform(0, LAP), rng.uniform(-5.5, 5.5),
                               rng.uniform(1.5, 4.5), rng.uniform(0.5, 0.9)))


_init_patches()


def puddle_at(k, u):
    w = WID[k]
    edge = clamp((abs(u) - (w / 2.0 - 1.2)) / 1.2)
    val = 0.65 * (1.0 - smooth(edge))
    s = SARC[k]
    for sc, uc, r, st in PUDDLE_PATCHES:
        ds = (s - sc + LAP / 2.0) % LAP - LAP / 2.0
        d = math.hypot(ds, u - uc)
        if d < r:
            val += st * smooth(1.0 - d / r)
    return clamp(val)


def build_kerbs_and_sidewalks():
    for i in range(NS):
        k = CH[i]
        for s in (1, -1):
            seg_kerb = [
                (lambda kk, s=s: s * (WID[kk] / 2.0 + 0.05), cz(0.15),
                 lambda kk, s=s: s * (WID[kk] / 2.0 + 0.30), cz(0.15), 0.0, 1.0, 1, False),
                (lambda kk, s=s: s * WID[kk] / 2.0, cz(0.10),
                 lambda kk, s=s: s * (WID[kk] / 2.0 + 0.05), cz(0.15), -s * 0.7, 0.7, 1, False),
                (lambda kk, s=s: s * WID[kk] / 2.0, cz(0.0),
                 lambda kk, s=s: s * WID[kk] / 2.0, cz(0.10), -float(s), 0.0, 1, False),
            ]
            extrude(bld("road", k), [i], seg_kerb)
            seg_walk = [
                (lambda kk, s=s: s * (WID[kk] / 2.0 + KERB_OUT), cz(0.15),
                 lambda kk, s=s: s * uo(kk, s), cz(0.15), 0.0, 1.0, 0, False),
            ]
            extrude(bld("sidewalk", k), [i], seg_walk)
        if WATER[i]:
            extrude(bld("sidewalk", k), [i], [
                (lambda kk: uo(kk, 1), cz(0.15), lambda kk: uo(kk, 1), cz(WATER_Z), 1.0, 0.0, 1, False)])


def build_collider_walls():
    """Invisible 3 m walls on both building lines (quay edge included via uo), closed loops."""
    for i in range(NS):
        k = CH[i]
        for s in (1, -1):
            extrude(bld("wall", k), [i], [
                (lambda kk, s=s: s * uo(kk, s), absz(GZ - 1.0),
                 lambda kk, s=s: s * uo(kk, s), cz(0.15 + 3.0), -float(s), 0.0, 0, True)])


def build_edge_barriers():
    """Low concrete kerb wall just outside the kerb on both sides (config road.edge_barrier = height in m): the
    promenade / sidewalk beside the road is at road height, so without it AI cars and players drive onto it.
    Not in the tube or in trenches (those have their own walls)."""
    h = float(RCFG.get("edge_barrier") or 0.0)
    if h <= 0.0:
        return
    for i in range(NS):
        if TUBE[i] or CUT[i]:
            continue
        k = CH[i]
        for s in (1, -1):
            extrude(bld("structure", k), [i], rect(
                lambda kk, s=s: s * (WID[kk] / 2.0 + KERB_OUT + 0.25), lambda kk: 0.25,
                cz(0.15), cz(0.15 + h), 0, "RTL", flip=(s < 0)))


# ----------------------------------------------------------------- structures
def build_structures():
    """Overpass fill walls, parapets, soffit, underpass tube, trench retaining walls."""
    for i in range(NS):
        k = CH[i]
        Bd = bld("structure", k)
        if ELEV[i]:
            segs = []
            for s in (1, -1):
                segs.append((lambda kk, s=s: s * uo(kk, s), absz(GZ),
                             lambda kk, s=s: s * uo(kk, s), cz(0.15), float(s), 0.0, 0, True))
                segs += rect(lambda kk, s=s: s * (uo(kk, s) - 0.125), lambda kk: 0.125,
                             cz(0.15), cz(0.15 + 0.9), 0, "RTL")
                segs += rect(lambda kk, s=s: s * (uo(kk, s) - 0.125), lambda kk: 0.05,
                             cz(0.15 + 0.9), cz(0.15 + 0.98), 1, "RTL")
            segs += rect(lambda kk: 0.0, lambda kk: uo(kk, 1), cz(-0.8), cz(-0.8), 0, "B")
            extrude(Bd, [i], segs)
        if TUBE[i]:
            # ceiling spans exactly between the two wall lines (left and right widths differ on the promenade)
            segs = slab(lambda kk: uo(kk, 1), lambda kk: -uo(kk, -1), cz(CEIL_H), cz(CEIL_H + 0.6), 0)
            for s in (1, -1):
                segs.append((lambda kk, s=s: s * uo(kk, s), cz(0.15),
                             lambda kk, s=s: s * uo(kk, s), cz(CEIL_H), -float(s), 0.0, 0, False))
                segs.append((lambda kk, s=s: s * (uo(kk, s) - 0.02), cz(1.15),
                             lambda kk, s=s: s * (uo(kk, s) - 0.02), cz(1.55), -float(s), 0.0, 3, False))
                segs.append((lambda kk, s=s: s * (WID[kk] / 2.0 - 2.25), cz(CEIL_H - 0.02),
                             lambda kk, s=s: s * (WID[kk] / 2.0 - 1.75), cz(CEIL_H - 0.02),
                             0.0, -1.0, 2, False))
            extrude(Bd, [i], segs)
        elif CUT[i]:
            segs = []
            for s in (1, -1):
                segs.append((lambda kk, s=s: s * uo(kk, s), cz(0.15),
                             lambda kk, s=s: s * uo(kk, s), absz(GZ), -float(s), 0.0, 0, True))
                # rim ledge at street level: closes the gap between the trench wall top and the sub-cell ground
                segs.append((lambda kk, s=s: s * uo(kk, s), absz(GZ + 0.01),
                             lambda kk, s=s: s * (uo(kk, s) + 2.0), absz(GZ + 0.01), 0.0, 1.0, 0, True))
            extrude(Bd, [i], segs)


def build_portals():
    tube = [i for i in range(NS) if TUBE[i]]
    if not tube:
        return
    for seg_i in (tube[0], tube[-1] - 1):
        Bd = bld("structure", CH[seg_i])
        segs = rect(lambda kk: 0.0, lambda kk: uo(kk, 1) + 0.5, cz(0.15), cz(6.3), 0, "RTL")
        segs += rect(lambda kk: 0.0, lambda kk: uo(kk, 1), cz(0.15), cz(5.8), 0, "RTL", flip=True)
        extrude(Bd, [seg_i], segs)
        for k, facing in ((seg_i, -1.0), (seg_i + 1, 1.0)):
            uk = uo(k, 1)
            cap_rect(Bd, k, -(uk + 0.5), -uk, 0.15, 5.8, 0, facing)
            cap_rect(Bd, k, uk, uk + 0.5, 0.15, 5.8, 0, facing)
            cap_rect(Bd, k, -(uk + 0.5), uk + 0.5, 5.8, 6.3, 0, facing)


# ----------------------------------------------------------------- markings
def ribbon(Bd, s0, s1, ua, ub, extra, mat, step=1.0):
    n = max(1, int(math.ceil(abs(s1 - s0) / step)))
    for q in range(n):
        sa = s0 + (s1 - s0) * q / n
        sb = s0 + (s1 - s0) * (q + 1) / n
        wa, wb = fr(sa)[6], fr(sb)[6]
        pts = [road_pt(sa, ua, extra), road_pt(sb, ua, extra),
               road_pt(sb, ub, extra), road_pt(sa, ub, extra)]
        uvs = [(ua + wa / 2.0, sa), (ua + wb / 2.0, sb), (ub + wb / 2.0, sb), (ub + wa / 2.0, sa)]
        Bd.poly(pts, uvs, [(0, 0, 0, 1)] * 4, mat, (0.0, 0.0, 1.0))


def edge_line(Bd, s0, s1, side, mat):
    n = max(1, int(math.ceil((s1 - s0) / 1.0)))
    for q in range(n):
        sa = s0 + (s1 - s0) * q / n
        sb = s0 + (s1 - s0) * (q + 1) / n
        if COB[min(int(sa / DSA), NS - 1)]:
            continue
        wa, wb = fr(sa)[6], fr(sb)[6]
        ua_a, ub_a = side * (wa / 2.0 - 0.375), side * (wa / 2.0 - 0.225)
        ua_b, ub_b = side * (wb / 2.0 - 0.375), side * (wb / 2.0 - 0.225)
        pts = [road_pt(sa, ua_a, 0.005), road_pt(sb, ua_b, 0.005),
               road_pt(sb, ub_b, 0.005), road_pt(sa, ub_a, 0.005)]
        uvs = [(ua_a + wa / 2.0, sa), (ua_b + wb / 2.0, sb), (ub_b + wb / 2.0, sb), (ub_a + wa / 2.0, sa)]
        Bd.poly(pts, uvs, [(0, 0, 0, 1)] * 4, mat, (0.0, 0.0, 1.0))


def ELEV_ZONE(s):
    return ELEV[min(int(s / DSA), NS - 1)]


def grid_box(sc, uc):
    a, b, t = 2.3, 1.2, 0.06
    Bd = bld("markings", chunk_of_s(sc))
    ribbon(Bd, sc - a, sc + a, uc - b - t, uc - b + t, 0.005, 0)
    ribbon(Bd, sc - a, sc + a, uc + b - t, uc + b + t, 0.005, 0)
    ribbon(Bd, sc - a - t, sc - a + t, uc - b, uc + b, 0.005, 0, step=2.4)
    ribbon(Bd, sc + a - t, sc + a + t, uc - b, uc + b, 0.005, 0, step=2.4)


def build_markings():
    paint, joint = 0, 1
    sf = S_CP[RCFG.get("start_cp", 1)]
    # dashed lane lines: 3 m dash, 9 m gap
    for ul in RCFG.get("lane_lines", (-3.5, 0.0, 3.5)):
        s = 0.0
        while s < LAP:
            near_grid = sf - 75 < s < sf + 12
            if not near_grid and not ELEV_ZONE(s) and not COB[min(int(s / DSA), NS - 1)]:
                ribbon(bld("markings", chunk_of_s(s)), s, s + 3.0, ul - 0.075, ul + 0.075, 0.005, paint)
            s += 12.0
    # solid edge lines, both sides, per chunk
    for side in (1, -1):
        for c in range(CH_COUNT):
            s0, s1 = c * CHUNK_M, min((c + 1) * CHUNK_M, LAP)
            edge_line(bld("markings", c), s0, s1, side, paint)
    # start/finish checkered band (14 columns of 1 m, four 0.5 m rows)
    ncol = int(ROAD_W)
    for r in range(4):
        for c in range(ncol):
            if (r + c) % 2 == 0:
                ua = -ncol / 2.0 + c
                ribbon(bld("markings", chunk_of_s(sf)), sf - 1.0 + 0.5 * r, sf - 0.5 + 0.5 * r,
                       ua, ua + 1.0, 0.005, paint)
    # 8 grid boxes: two columns, 8 m stagger, 16 m row pitch
    for r in range(4):
        for c in range(2):
            grid_box(sf - 6.0 - 16.0 * r - 8.0 * c, 1.75 if c == 0 else -1.75)
    # direction arrows before T1
    s3 = S_CP[RCFG.get("arrow_cp", 3)]
    for sa in (s3 - 60.0, s3 - 42.0, s3 - 24.0):
        for uc in RCFG.get("arrow_lanes", (-1.75, 1.75)):
            Bd = bld("markings", chunk_of_s(sa))
            Bd.poly([road_pt(sa - 1.6, uc - 0.2, 0.005), road_pt(sa - 1.6, uc + 0.2, 0.005),
                     road_pt(sa + 0.4, uc + 0.2, 0.005), road_pt(sa + 0.4, uc - 0.2, 0.005)],
                    [(0, 0)] * 4, [(0, 0, 0, 1)] * 4, paint, (0, 0, 1))
            Bd.poly([road_pt(sa + 0.4, uc - 1.0, 0.005), road_pt(sa + 2.0, uc, 0.005),
                     road_pt(sa + 0.4, uc + 1.0, 0.005)],
                    [(0, 0)] * 3, [(0, 0, 0, 1)] * 3, paint, (0, 0, 1))
    # zebra crossings (4): stripes run along the traffic direction (3 m long), 0.6 m wide at 1.2 m pitch across the road
    nz = 10 if ROAD_W == 14.0 else int(ROAD_W / 1.2) - 1
    for zs in ZEBRA_S:
        for k in range(nz):
            uc = -1.2 * (nz - 1) / 2.0 + 1.2 * k
            ribbon(bld("markings", chunk_of_s(zs)), zs, zs + 3.0, uc - 0.3, uc + 0.3, 0.005, paint)
    # chevron hatching on the outside of the hairpin
    _hp = RCFG.get("hairpin_cp")
    hp = [i for i in range(NS) if S_CP[_hp[0]] <= SARC[i] <= S_CP[_hp[1]]] if _hp else []
    kmean = sum(KAP[i] for i in hp) / max(1, len(hp))
    outer = -1.0 if kmean > 0 else 1.0
    s = S_CP[_hp[0]] + 4.0 if _hp else LAP
    while _hp and s < S_CP[_hp[1]] - 6.0:
        Bd = bld("markings", chunk_of_s(s))
        ue, ui = outer * (ROAD_W / 2.0 - 0.1), outer * (ROAD_W / 2.0 - 1.5)
        Bd.poly([road_pt(s, ue, 0.005), road_pt(s + 1.0, ue, 0.005),
                 road_pt(s + 2.0, ui, 0.005), road_pt(s + 1.0, ui, 0.005)],
                [(0, 0)] * 4, [(0, 0, 0, 1)] * 4, paint, (0, 0, 1))
        s += 2.4
    # expansion joints across the elevated deck every 20 m
    s = 0.0
    while s < LAP:
        if ELEV_ZONE(s) and not COB[min(int(s / DSA), NS - 1)]:
            ribbon(bld("markings", chunk_of_s(s)), s, s + 0.15, -ROAD_W / 2.0, ROAD_W / 2.0, 0.006, joint)
        s += 20.0


ZEBRA_S = [S_CP[c] + o for c, o in RCFG["zebra"]]


# ----------------------------------------------------------------- decals, water, ground
def build_decals():
    rng = random.Random(4242)
    sf = S_CP[RCFG.get("start_cp", 1)]
    placed = []

    def ok(s, u):
        k = min(int(s / DSA), NS - 1)
        if TUBE[k] or ELEV[k] or CUT[k] or WATER[k] or COB[k]:
            return False
        if sf - 75 < s < sf + 20:
            return False
        for zs in ZEBRA_S:
            if abs((s - zs + LAP / 2) % LAP - LAP / 2) < 10.0:
                return False
        return True

    def pick(kind):
        for _ in range(500):
            s = rng.uniform(0, LAP)
            if kind == "manhole":
                u = rng.uniform(-ROAD_W / 2.0 + 1.5, ROAD_W / 2.0 - 1.5)
            else:
                u = (1 if rng.random() < 0.5 else -1) * (WID[min(int(s / DSA), NS - 1)] / 2.0 - 0.7)
            if ok(s, u):
                return s, u
        return None

    items = [("manhole", 24), ("grate", 16)]
    for kind, count in items:
        for _ in range(count):
            p = pick(kind)
            if p is None:
                continue
            s, u = p
            placed.append((kind, s, u))
            Bd = bld("decals", chunk_of_s(s))
            if kind == "manhole":
                r = 0.35
                c0 = road_pt(s, u, 0.003)
                n = 14
                for q in range(n):
                    a1 = 2 * math.pi * q / n
                    a2 = 2 * math.pi * (q + 1) / n
                    p1 = road_pt(s + r * math.cos(a1), u + r * math.sin(a1), 0.003)
                    p2 = road_pt(s + r * math.cos(a2), u + r * math.sin(a2), 0.003)
                    Bd.poly([c0, p1, p2], [(0, 0)] * 3, [(0, 0, 0, 1)] * 3, 0, (0, 0, 1))
            else:
                hl, hw = 0.3, 0.2
                corners = [(-hl, -hw), (hl, -hw), (hl, hw), (-hl, hw)]
                pts = [road_pt(s + a, u + b, 0.003) for a, b in corners]
                Bd.poly(pts, [(0, 0)] * 4, [(0, 0, 0, 1)] * 4, 1, (0, 0, 1))
                for q in range(3):
                    off = -0.15 + 0.15 * q
                    pts = [road_pt(s - hl * 0.9, u + off - 0.02, 0.004), road_pt(s + hl * 0.9, u + off - 0.02, 0.004),
                           road_pt(s + hl * 0.9, u + off + 0.02, 0.004), road_pt(s - hl * 0.9, u + off + 0.02, 0.004)]
                    Bd.poly(pts, [(0, 0)] * 4, [(0, 0, 0, 1)] * 4, 1, (0, 0, 1))
    return placed


def build_water():
    Bd = bld("water")
    for i in range(NS):
        if not WATER[i]:
            continue
        i2 = (i + 1) % NS
        ua = uo(i, 1)
        ub = uo(i2, 1) if WATER[i2] else ua
        pts = [(SX[i] + ua * LXa[i], SY[i] + ua * LYa[i], WATER_Z),
               (SX[i2] + ub * LXa[i2], SY[i2] + ub * LYa[i2], WATER_Z),
               (SX[i2] + (ub + WATER_EXT) * LXa[i2], SY[i2] + (ub + WATER_EXT) * LYa[i2], WATER_Z),
               (SX[i] + (ua + WATER_EXT) * LXa[i], SY[i] + (ua + WATER_EXT) * LYa[i], WATER_Z)]
        Bd.poly(pts, [(0, 0)] * 4, [(0, 0, 0, 1)] * 4, 0, (0, 0, 1))


PIERS = []   # [{"offset_m", "pos", "left", "tangent", "len", "w"}] for the layout (pier lights)


def build_piers():
    """Ferry piers: a paved slab with concrete skirts reaching from the quay edge out over the water."""
    for pc in RCFG.get("piers", []):
        s = S_CP[pc["cp"]] + float(pc["s"])
        ln, pw = float(pc["len"]), float(pc["w"])
        x, y, z, tn, lx, ly, w = fr(s)
        k = min(int(s / DSA), NS - 1)
        u0 = uo(k, 1)
        tx, ty = ly, -lx
        bx, by = x + lx * u0, y + ly * u0
        zt = z + 0.15

        def pp(a, b, zz):
            return (bx + lx * a + tx * b, by + ly * a + ty * b, zz)

        Bd = bld("sidewalk", chunk_of_s(s))
        a0, a1, b0, b1, zb = -0.4, ln, -pw / 2.0, pw / 2.0, WATER_Z - 1.2
        Bd.poly([pp(a0, b0, zt), pp(a1, b0, zt), pp(a1, b1, zt), pp(a0, b1, zt)],
                [(b0, a0), (b0, a1), (b1, a1), (b1, a0)], [(0, 0, 0, 1)] * 4, 0, (0, 0, 1))
        Bd.poly([pp(a0, b1, zt), pp(a1, b1, zt), pp(a1, b1, zb), pp(a0, b1, zb)],
                [(a0, zt), (a1, zt), (a1, zb), (a0, zb)], [(0, 0, 0, 1)] * 4, 1, (tx, ty, 0.0))
        Bd.poly([pp(a0, b0, zb), pp(a1, b0, zb), pp(a1, b0, zt), pp(a0, b0, zt)],
                [(a0, zb), (a1, zb), (a1, zt), (a0, zt)], [(0, 0, 0, 1)] * 4, 1, (-tx, -ty, 0.0))
        Bd.poly([pp(a1, b1, zt), pp(a1, b0, zt), pp(a1, b0, zb), pp(a1, b1, zb)],
                [(b1, zt), (b0, zt), (b0, zb), (b1, zb)], [(0, 0, 0, 1)] * 4, 1, (lx, ly, 0.0))
        for q in range(0, int(ln), 6):   # mooring posts along both edges
            for b in (b0 + 0.2, b1 - 0.2):
                c = pp(q + 1.0, b, zt)
                r, h = 0.18, 0.5
                ring = [(c[0] + r * math.cos(2 * math.pi * j / 6), c[1] + r * math.sin(2 * math.pi * j / 6)) for j in range(6)]
                for j in range(6):
                    p1, p2 = ring[j], ring[(j + 1) % 6]
                    Bd.poly([(p1[0], p1[1], zt), (p2[0], p2[1], zt), (p2[0], p2[1], zt + h), (p1[0], p1[1], zt + h)],
                            [(0, 0)] * 4, [(0, 0, 0, 1)] * 4, 1, (p1[0] - c[0], p1[1] - c[1], 0.0))
                Bd.poly([(p[0], p[1], zt + h) for p in ring], [(0, 0)] * 6, [(0, 0, 0, 1)] * 6, 1, (0, 0, 1))
        PIERS.append({"offset_m": round(s, 3), "pos": [round(c, 4) for c in g((bx, by, zt))],
                      "left": [round(c, 5) for c in g((lx, ly, 0.0))], "tangent": [round(c, 5) for c in g((tx, ty, 0.0))],
                      "len": ln, "w": pw})


def build_ground():
    Bd = bld("ground")
    xs = [p for p in SX]
    ys = [p for p in SY]
    x0, x1 = min(xs) - 250.0, max(xs) + 250.0
    y0, y1 = min(ys) - 250.0, max(ys) + 250.0
    nx = int(math.ceil((x1 - x0) / GCELL))
    ny = int(math.ceil((y1 - y0) / GCELL))
    gx = x0 + (np.arange(nx) + 0.5) * GCELL
    gy = y0 + (np.arange(ny) + 0.5) * GCELL
    CX, CY = np.meshgrid(gx, gy, indexing="ij")
    CX = CX.ravel()
    CY = CY.ravel()
    Pn = np.stack([np.array(SX), np.array(SY)], 1)
    LXn, LYn = np.array(LXa), np.array(LYa)
    UOL = np.array([uo(k, 1) for k in range(NS)])
    UOR = np.array([uo(k, -1) for k in range(NS)])
    CUTn = np.array([CUT[k] or TUBE[k] for k in range(NS)])
    WATn = np.array(WATER)

    def forbidden(px, py):
        """True where a point lies inside the trench/tube footprint or the bay (no street-level ground there)."""
        out = np.zeros(px.shape[0], dtype=bool)
        for b0 in range(0, px.shape[0], 1000):
            cx = px[b0:b0 + 1000]
            cy = py[b0:b0 + 1000]
            d2 = (cx[:, None] - Pn[None, :, 0]) ** 2 + (cy[:, None] - Pn[None, :, 1]) ** 2
            j = d2.argmin(1)
            ux = (cx - Pn[j, 0]) * LXn[j] + (cy - Pn[j, 1]) * LYn[j]
            lim = np.where(ux > 0, UOL[j], UOR[j])
            cut = CUTn[j] & (np.abs(ux) < lim)
            bay = WATn[j] & (ux > UOL[j] - 0.2) & (ux < UOL[j] + WATER_EXT)
            out[b0:b0 + 1000] = cut | bay
        return out

    # coarse cells with any test point inside the footprint are split into 2 m sub-cells,
    # and a sub-cell is kept only when all its corners are outside it: no ground pokes into the tube
    h = GCELL / 2.0
    coarse_bad = np.zeros(CX.shape[0], dtype=bool)
    for tx, ty in ((CX - h, CY - h), (CX + h, CY - h), (CX + h, CY + h), (CX - h, CY + h), (CX, CY)):
        coarse_bad |= forbidden(tx, ty)
    SUB = 2.0
    n_sub = int(round(GCELL / SUB))
    bad_idx = np.nonzero(coarse_bad)[0]
    B = bad_idx.size
    ax = np.arange(n_sub) * SUB
    XLb = np.broadcast_to((CX[bad_idx] - h)[:, None, None] + ax[None, :, None], (B, n_sub, n_sub))
    YLb = np.broadcast_to((CY[bad_idx] - h)[:, None, None] + ax[None, None, :], (B, n_sub, n_sub))
    sub_bad = np.zeros((B, n_sub, n_sub), dtype=bool)
    for dx, dy in ((0, 0), (SUB, 0), (SUB, SUB), (0, SUB), (SUB / 2, SUB / 2)):
        sub_bad |= forbidden((XLb + dx).ravel(), (YLb + dy).ravel()).reshape(B, n_sub, n_sub)
    quads = [(xa, ya, xa + GCELL, ya + GCELL) for xa, ya in
             zip(CX[~coarse_bad] - h, CY[~coarse_bad] - h)]
    quads += [(XLb[b, i, j], YLb[b, i, j], XLb[b, i, j] + SUB, YLb[b, i, j] + SUB)
              for b, i, j in zip(*np.nonzero(~sub_bad))]
    for xa, ya, xb, yb in quads:
        pts = [(xa, ya, GZ), (xb, ya, GZ), (xb, yb, GZ), (xa, yb, GZ)]
        uvs = [(xa, ya), (xb, ya), (xb, yb), (xa, yb)]
        Bd.poly(pts, uvs, [(0, 0, 0, 1)] * 4, 0, (0, 0, 1))
    return len(quads), int(CX.shape[0])


# ----------------------------------------------------------------- materials and objects
MATS = {}


def make_materials():
    for name, sp in MAT_SPEC.items():
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = hex_lin(sp["hex"]) + (1.0,)
        bsdf.inputs["Roughness"].default_value = sp["rough"]
        bsdf.inputs["Metallic"].default_value = sp["metal"]
        if sp["emis"]:
            bsdf.inputs["Emission Color"].default_value = hex_lin(sp["emis"]) + (1.0,)
            bsdf.inputs["Emission Strength"].default_value = sp["strength"]
        MATS[name] = m


COLL = bpy.data.collections.new(PREFIX.upper() + "_ROAD")
bpy.context.scene.collection.children.link(COLL)


def make_obj(Bd, slots):
    me = bpy.data.meshes.new(Bd.name + "_mesh")
    me.from_pydata(Bd.v, [], Bd.f)
    me.update()
    for sname in slots:
        me.materials.append(MATS[sname])
    for p in me.polygons:
        p.material_index = Bd.m[p.index]
    uvl = me.uv_layers.new(name="UVMap")
    for lp in me.loops:
        uvl.data[lp.index].uv = Bd.uv[lp.vertex_index]
    ca = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    for k, c in enumerate(Bd.col):
        ca.data[k].color = c
    ob = bpy.data.objects.new(Bd.name, me)
    COLL.objects.link(ob)
    return ob


def tri_count(Bd):
    return sum(1 if len(f) == 3 else 2 for f in Bd.f)


def build_all():
    build_road_surface()
    build_kerbs_and_sidewalks()
    build_collider_walls()
    build_edge_barriers()
    build_structures()
    build_portals()
    build_markings()
    placed = build_decals()
    build_water()
    build_piers()
    kept, total = build_ground()
    return placed, kept, total


# ----------------------------------------------------------------- export and JSON
def export_glb(path):
    kw = dict(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
              export_tangents=True, export_materials="EXPORT", export_image_format="NONE")
    # only the authored "Col" attribute goes out, as COLOR_0 (the engine's default colour channel)
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    for key, val in (("export_vertex_color", "ACTIVE"), ("export_all_vertex_colors", False),
                     ("export_active_vertex_color_when_no_material", True)):
        if key in props:
            kw[key] = val
        else:
            print("EXPORT option missing:", key)
    print("EXPORT kwargs", kw)
    bpy.ops.export_scene.gltf(**kw)


def write_outputs(placed, kept, total, tri_by_kind, obj_count_by_kind, road_normal_up):
    # centreline in godot coords
    samples, edges = [], []
    for i in range(NS):
        right = (TYa[i], -TXa[i], 0.0)
        samples.append({
            "i": i,
            "offset_m": round(SARC[i], 3),
            "pos": [round(c, 4) for c in g((SX[i], SY[i], SZ[i]))],
            "tangent": [round(c, 5) for c in g((TXa[i], TYa[i], 0.0))],
            "right": [round(c, 5) for c in g(right)],
            "width": round(WID[i], 3),
            "bank_deg": round(BANK[i], 3),
            "district": DIST[i],
            "district_name": DIST_NAMES[DIST[i]],
            "chunk": CH[i],
        })
        edges.append({
            "i": i,
            "left_kerb": [round(c, 4) for c in g(P3(i, WID[i] / 2.0, 0.0))],
            "right_kerb": [round(c, 4) for c in g(P3(i, -WID[i] / 2.0, 0.0))],
            "left_building": [round(c, 4) for c in g(P3(i, uo(i, 1), KERB_OUT * 0 + 0.15))],
            "right_building": [round(c, 4) for c in g(P3(i, -uo(i, -1), 0.15))],
            "open_water_side": "left" if WATER[i] else None,
        })
    grid = []
    sf = S_CP[RCFG.get("start_cp", 1)]
    for r in range(4):
        for c in range(2):
            sc = sf - 6.0 - 16.0 * r - 8.0 * c
            uc = 1.75 if c == 0 else -1.75
            x, y, z, tn, lx, ly, w = fr(sc)
            p = road_pt(sc, uc, 0.0)
            tx, ty = fr(sc)[4], fr(sc)[5]
            # direction of travel from neighbouring samples
            k = int(sc / DSA) % NS
            dx, dy = TXa[k], TYa[k]
            d = g((dx, dy, 0.0))
            yaw = math.atan2(-d[0], -d[2])
            grid.append({"slot": r * 2 + c + 1, "pos": [round(c2, 4) for c2 in g(p)],
                         "yaw_rad": round(yaw, 5), "yaw_deg": round(math.degrees(yaw), 3),
                         "lane_x_m": uc, "offset_m": round(sc, 3)})
    start_p = road_pt(sf, 0.0, 0.0)
    k1 = int(sf / DSA) % NS
    start = {"offset_m": round(sf, 3), "pos": [round(c, 4) for c in g(start_p)],
             "tangent": [round(c, 5) for c in g((TXa[k1], TYa[k1], 0.0))],
             "right": [round(c, 5) for c in g((TYa[k1], -TXa[k1], 0.0))],
             "width": round(WID[k1], 3), "direction": "race direction +Y (Blender) = -Z (Godot)"}
    gates = []
    for n, cp_i in enumerate(RCFG["gate_cps"], start=1):
        s = S_CP[cp_i]
        k = int(s / DSA) % NS
        gates.append({"name": "G%d" % n, "cp": cp_i, "offset_m": round(s, 3),
                      "pos": [round(c, 4) for c in g(road_pt(s, 0.0, 0.0))],
                      "tangent": [round(c, 5) for c in g((TXa[k], TYa[k], 0.0))]})
    cps = [{"n": i, "pos": list(g(CP[i])), "offset_m": round(S_CP[i], 3),
            "district": DIST_OF_PT[i]} for i in range(len(CP))]
    zebra = [{"offset_m": round(z, 3), "pos": [round(c, 4) for c in g(road_pt(z, 0.0, 0.0))]} for z in ZEBRA_S]
    center = {
        "coords": "godot_y_up",
        "units": "metres",
        "lap_length": round(LAP, 3),
        "sample_spacing_m": round(DSA, 5),
        "sample_count": NS,
        "samples": samples,
        "edges": edges,
        "grid_slots": grid,
        "start_line": start,
        "gates": gates,
        "control_points": cps,
        "zebra_positions": zebra,
        "piers": PIERS,
        "control_offsets_m": [round(x, 3) for x in S_CP],
        "districts": DIST_NAMES,
        "helper_points_added": ([{"after_cp": HELPER["after_cp"], "pos": list(HELPER_WF),
                                  "reason": HELPER["reason"]}] if HELPER else []),
    }
    with open(os.path.join(OUT, PREFIX + "_centerline.json"), "w", encoding="utf-8") as fh:
        json.dump(center, fh, indent=1)

    mats = []
    for name, sp in MAT_SPEC.items():
        mats.append({"name": name, "base_colour_srgb": sp["hex"], "roughness": sp["rough"],
                     "metallic": sp["metal"],
                     "emissive_srgb": sp["emis"] or "#000000",
                     "emissive_strength": sp["strength"], "uv": sp["uv"], "notes": sp["note"],
                     "textures": "none embedded; engine applies CC0 PBR set or procedural shader"})
    with open(os.path.join(OUT, "materials.json"), "w", encoding="utf-8") as fh:
        json.dump({"coords": "godot_y_up", "materials": mats}, fh, indent=1)

    report = {
        "checks": CHECKS,
        "road_normals_up_fraction": round(road_normal_up, 4),
        "triangles_by_kind": tri_by_kind,
        "objects_by_kind": obj_count_by_kind,
        "triangles_total": sum(tri_by_kind.values()),
        "decals_placed": {"manholes": sum(1 for p in placed if p[0] == "manhole"),
                          "grates": sum(1 for p in placed if p[0] == "grate")},
        "ground_cells_kept": [kept, total],
        "chunks": CH_COUNT,
        "chunk_m": CHUNK_M,
        "district_sample_counts": {DIST_NAMES[d]: sum(1 for x in DIST if x == d) for d in range(len(DIST_NAMES))},
        "elevated_samples": sum(ELEV),
        "tube_samples": sum(TUBE),
        "cut_samples": sum(CUT),
        "water_samples": sum(WATER),
        "runtime_s": round(time.time() - T_START, 1),
    }
    with open(os.path.join(OUT, "report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=1)
    print("REPORT", json.dumps(report))


# ----------------------------------------------------------------- main
for _ob in list(bpy.data.objects):
    bpy.data.objects.remove(_ob, do_unlink=True)
make_materials()
placed, kept, total = build_all()

tri_by_kind, obj_by_kind = {}, {}
road_up, road_n = 0, 0
for (kind, k), Bd in sorted(BLD.items(), key=lambda kv: (kv[0][0], kv[0][1])):
    if not Bd.f:
        continue
    ob = make_obj(Bd, SLOTS[kind])
    tri_by_kind[kind] = tri_by_kind.get(kind, 0) + tri_count(Bd)
    obj_by_kind[kind] = obj_by_kind.get(kind, 0) + 1
    if kind == "road":
        for p in ob.data.polygons:
            road_n += 1
            if p.normal.z > 0.5:
                road_up += 1
road_frac = road_up / max(1, road_n)
print("TRIS", json.dumps(tri_by_kind), "OBJS", json.dumps(obj_by_kind), "ROAD_UP", road_frac)

export_glb(os.path.join(OUT, PREFIX + "_road.glb"))
write_outputs(placed, kept, total, tri_by_kind, obj_by_kind, road_frac)
print("DONE", round(time.time() - T_START, 1), "s")


# ----------------------------------------------------------------- QA renders (not exported)
QA_OBJS = []


def qa_mat(name, hexc, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    b.inputs["Emission Color"].default_value = hex_lin(hexc) + (1.0,)
    b.inputs["Emission Strength"].default_value = strength
    MATS[name] = m
    return m


def qa_label(body, x, y, z, size, mat_name="QA_text"):
    cu = bpy.data.curves.new("QA_T_" + body, "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    ob = bpy.data.objects.new("QA_T_" + body, cu)
    ob.visible_shadow = False  # QA only: stops the sun from printing ghost copies of the labels
    ob.data.materials.append(MATS[mat_name])
    ob.location = (x, y, z)
    COLL.objects.link(ob)
    QA_OBJS.append(ob)


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)


def set_camera(loc, target, lens, ortho=None):
    cam = bpy.context.scene.camera
    cam.location = loc
    if ortho is None:
        cam.data.type = "PERSP"
        cam.data.lens = lens
        cam.data.clip_end = 3000.0
        d = (target[0] - loc[0], target[1] - loc[1], target[2] - loc[2])
        from mathutils import Vector
        cam.rotation_euler = Vector(d).to_track_quat("-Z", "Y").to_euler()
    else:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
        cam.data.clip_end = 3000.0
        cam.rotation_euler = (0.0, 0.0, 0.0)


def build_qa_scene():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    try:
        scene.eevee.taa_render_samples = 24
    except Exception as exc:  # noqa: BLE001
        print("eevee samples not set:", exc)
    world = bpy.data.worlds.new("QAWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = hex_lin("#070A14") + (1.0,)
    bg.inputs["Strength"].default_value = 0.5
    scene.world = world
    # temporary wet-look asphalt for QA only (the exported GLB keeps the authored values)
    bsdf = MATS["M_Asphalt"].node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.12
    bsdf.inputs["Base Color"].default_value = hex_lin("#0E1116") + (1.0,)
    # QA only: the glossy water mirrors the sky and renders white in top view
    MATS["M_Water"].node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.45
    cam_data = bpy.data.cameras.new("QACam")
    cam = bpy.data.objects.new("QACam", cam_data)
    COLL.objects.link(cam)
    scene.camera = cam


def top_map():
    for ob in QA_OBJS:
        ob.hide_render = False
    for ob in bpy.data.objects:
        if ob.name.startswith("wall_"):
            ob.hide_render = True
    # district halos under the road (visible on the ground around the track)
    cols = ["#19E6FF", "#4D7CFF", "#2E9E9A", "#8C5CFF", "#FFB36B", "#FF4DB8", "#B6FF4D"]
    halos = {}
    for d in range(len(DIST_NAMES)):
        qa_mat("QA_D%d" % d, cols[d], 0.9)
        halos[d] = Bld("QA_halo_%d" % d)
    for i in range(NS):
        i2 = (i + 1) % NS
        Bd = halos[DIST[i]]
        pts = [(SX[i] - 60 * LXa[i], SY[i] - 60 * LYa[i], -0.05),
               (SX[i2] - 60 * LXa[i2], SY[i2] - 60 * LYa[i2], -0.05),
               (SX[i2] + 60 * LXa[i2], SY[i2] + 60 * LYa[i2], -0.05),
               (SX[i] + 60 * LXa[i], SY[i] + 60 * LYa[i], -0.05)]
        Bd.poly(pts, [(0, 0)] * 4, [(0, 0, 0, 1)] * 4, 0, (0, 0, 1))
    for d in range(len(DIST_NAMES)):
        ob = make_obj(halos[d], ["QA_D%d" % d])
        QA_OBJS.append(ob)
    qa_mat("QA_text", "#FFFFFF", 4.0)
    qa_mat("QA_red", "#FF3B30", 6.0)
    qa_mat("QA_arrow", "#FFC23D", 6.0)
    # district names placed outside the loop, clear of control point labels
    for name, lx, ly in RCFG["qa"]["district_labels"]:
        qa_label(name, lx, ly, 60.0, 24.0)
    for i, p in enumerate(CP):
        qa_label("P%d" % i, p[0] + 9.0, p[1] + 9.0, 15.0, 10.0)
        mk = bpy.data.meshes.new("QA_mk%d" % i)
        ob = bpy.data.objects.new("QA_mk%d" % i, mk)
        mk.from_pydata([(-2, -2, 0), (2, -2, 0), (2, 2, 0), (-2, 2, 0)], [], [(0, 1, 2, 3)])
        ob.location = (p[0], p[1], 3.0)
        ob.data.materials.append(MATS["QA_red"])
        COLL.objects.link(ob)
        QA_OBJS.append(ob)
    qa_label("START / FINISH", RCFG["qa"]["start_label"][0], RCFG["qa"]["start_label"][1], 15.0, 12.0)
    # direction arrow on the main straight (race direction +Y)
    ar = Bld("QA_arrow")
    ar.poly([(-9, 60, 4), (9, 60, 4), (0, 90, 4)], [(0, 0)] * 3, [(0, 0, 0, 1)] * 3, 0, (0, 0, 1))
    ar.poly([(-3, 20, 4), (3, 20, 4), (3, 60, 4), (-3, 60, 4)], [(0, 0)] * 4, [(0, 0, 0, 1)] * 4, 0, (0, 0, 1))
    QA_OBJS.append(make_obj(ar, ["QA_arrow"]))
    qa_label("RACE DIRECTION", 45.0, 105.0, 15.0, 9.0)
    sun = bpy.data.lights.new("QASun", "SUN")
    sun.energy = 1.5
    so = bpy.data.objects.new("QASun", sun)
    so.rotation_euler = (math.radians(55.0), 0.0, math.radians(25.0))  # oblique: no mirror glare on water
    COLL.objects.link(so)
    QA_OBJS.append(so)
    _tc = RCFG["qa"]["top_center"]
    set_camera((_tc[0], _tc[1], 1500.0), (_tc[0], _tc[1], 0.0), 0, ortho=RCFG["qa"]["top_scale"])
    render_to(os.path.join(REN, "top_map.png"))


def clear_street_lights():
    for ob in list(bpy.data.objects):
        if ob.type == "LIGHT" and ob.name.startswith("QAL_"):
            bpy.data.objects.remove(ob, do_unlink=True)


def street_view(name, s_cam, s_look, lens=24.0):
    clear_street_lights()
    for ob in QA_OBJS:
        ob.hide_render = True
    for ob in bpy.data.objects:
        if ob.name.startswith("wall_"):
            ob.hide_render = True
    n = 0
    s = s_cam - 40.0
    while s < s_cam + 170.0:
        w = fr(s)[6]
        for side in (1, -1):
            p = road_pt(s, side * (w / 2.0 + 1.6), 0.0)
            ld = bpy.data.lights.new("QAL_%d" % n, "POINT")
            ld.energy = 2200.0
            ld.shadow_soft_size = 0.6
            ld.use_shadow = False
            ld.color = hex_lin("#FFB36B") if n % 3 else hex_lin("#BFD8FF")
            lo = bpy.data.objects.new("QAL_%d" % n, ld)
            lo.location = (p[0], p[1], p[2] + 6.0)
            COLL.objects.link(lo)
            n += 1
        s += 22.0
    cam_p = road_pt(s_cam, 0.0, 1.3)
    tgt = road_pt(s_look, 0.0, 1.0)
    set_camera(cam_p, tgt, lens)
    render_to(os.path.join(REN, name))


def render_all():
    build_qa_scene()
    top_map()
    def sref(r):
        return ZEBRA_S[int(r[0][1:])] + r[1] if isinstance(r[0], str) else S_CP[r[0]] + r[1]
    for fname, a, b, lens in RCFG["qa"]["views"]:
        street_view(fname, sref(a), sref(b), lens=lens)


if DO_RENDER:
    render_all()
print("ALL DONE", round(time.time() - T_START, 1), "s")
