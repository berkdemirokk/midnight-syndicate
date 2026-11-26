#!/usr/bin/env python3
"""Track layout generator (Environment Agent). Plain Python 3.10 + numpy, no Blender. Config driven (configs/<id>.json).

Run:  py -3.10 build_layout.py --config configs/<id>.json
Reads   <road.out_dir>/<id>_centerline.json, ../kit_buildings/out/catalog.json, ../kit_props/out/catalog.json
        (+ layout.extra_prop_catalogs)
Writes  <layout.out_dir>/<id>_layout.json (coords godot_y_up) and prints the checks.
City 01 entry point: assets_src/world/city_01/build_layout.py passes configs/city_01.json.

Conventions (Godot, Y up, forward -Z):
  godot = (blender_x, blender_z, -blender_y).
  Every placed item has yaw (rad, about +Y) and its LOCAL +Z is its front.
  A direction (sin yaw, 0, cos yaw) is the local +Z in world. Local X is (cos yaw, 0, -sin yaw).
  Buildings: front (facade, lz = 0) faces the road, body extends to lz = -depth, canopy to lz = +1.45.
  Props: catalog origins as measured from the GLBs (ground centre, wall face, or blade mid-height).
"""
import json
import math
import os
import random
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
if "--config" not in sys.argv:
    raise SystemExit("build_layout.py needs --config <track.json>")
CFG = json.load(open(os.path.abspath(sys.argv[sys.argv.index("--config") + 1]), encoding="utf-8"))
LC = CFG["layout"]
TRACK_ID = CFG["id"]
CL_PATH = os.path.join(REPO, CFG["road"]["out_dir"], TRACK_ID + "_centerline.json")
BCAT_PATH = os.path.join(HERE, "..", "kit_buildings", "out", "catalog.json")
PCAT_PATH = os.path.join(HERE, "..", "kit_props", "out", "catalog.json")
OUT_DIR = os.path.join(REPO, LC["out_dir"])
OUT_PATH = os.path.join(OUT_DIR, TRACK_ID + "_layout.json")

SEED = int(LC["seed"])
CANOPY = 1.45          # building collider and canopy reach in front of the facade
MIN_CL = float(LC.get("min_cl_m", 10.0))   # facade and body footprint must stay this far from the centreline
CANOPY_MIN = float(LC.get("canopy_min_m", 8.0))   # canopy may reach into the sidewalk band only
MARGIN = 0.5           # overlap test margin around a new footprint
BUDGET_TRIS = 450000
BUDGET_DRAWS = 350
NEON_CAP = int(LC.get("neon_cap", 40))
MIN_STOREYS = {int(k): v for k, v in LC.get("min_storeys", {}).items()}
LAP_RANGE = LC["lap_range"]
TUNNEL_D = LC.get("tunnel_district", 3)    # district index of the underpass (no buildings, tunnel lights), or null
DISTRICTS = {int(k): v for k, v in LC["districts"].items()}              # index -> key written to the layout
DISTRICT_NAMES = {int(k): v for k, v in LC["district_names"].items()}
BLD_POOL = {int(k): v for k, v in LC["bld_pool"].items()}
SIGN_BOX = {int(k): v for k, v in LC["sign_box"].items()}
SIGN_BLADE = LC["sign_blade"]
SIGN_P = {int(k): v for k, v in LC["sign_p"].items()}   # chance per anchor
FURN = [tuple(x) for x in LC["furniture"]]
LAMP_ASSET = {int(k): v for k, v in LC["lamp_asset"].items()}   # district -> lamp prop; "default" via key -1
LAMP_DEFAULT = LC["lamp_default"]
LAMP_SKIP_D = set(LC.get("lamp_skip_districts", [3]))
LAMP_STEP = LC.get("lamp_step_m", [28.0, 32.0])
SIDEWALK_CAP = {int(k): v for k, v in LC.get("sidewalk_cap", {}).items()}   # district -> max inward k
SECOND_ROW = [tuple(x) for x in LC["second_row"]]   # (back_m, [parent districts], prob)
SECOND_ROW_D = set(LC["second_row_districts"])
SIGN_D = set(LC["sign_districts"])
TALL_D = set(LC["tall_districts"])
BUS_D = LC.get("bus_district", 0)
BUS_FRACS = [tuple(x) for x in LC.get("bus_fracs", [[0.18, "right"], [0.62, "left"], [0.45, "right"]])]
STRING_D = LC.get("string_district")
MARKET_D = LC.get("market_district")
CABLE_D = LC.get("cable_district", 0)
APEX_GUESS = LC["apex_guess"]
BAY = LC.get("bay", [])           # [{"i":, "off":, "asset":}]
SKYLINES = LC.get("skylines", [])  # [{"i":, "off":, "district":}]
BILLBOARD = LC.get("billboard", "sign_billboard_zenith_tower_12x5")
if isinstance(BILLBOARD, str):
    BILLBOARD = [BILLBOARD]
NO_BUILD = [(x["side"], float(x["s"][0]), float(x["s"][1])) for x in LC.get("no_build", [])]   # open plaza stretches
PLAZA = LC.get("plaza", [])        # [{"i":, "side":, "off":, "asset":}] props placed off the road in an open stretch
LAMP_DECK = bool(LC.get("lamp_on_deck", False))   # lamps on the elevated deck sidewalk
BILLBOARD_N = int(LC.get("billboard_count", 8))
ACCENT_N = int(LC.get("accent_count", 6))
RAIL_D = LC.get("guardrails", True)
CORNER_BARRIERS = bool(LC.get("corner_barriers", True))
QUAY = LC.get("quay")      # Istanbul seaside: railing + promenade lamps on the water side instead of the City 01 quay props
TRAM = LC.get("tram")      # tram rails along a control point range
PIER_LIGHTS = LC.get("pier_lights")
PROBE_STEP = int(LC.get("probe_step", 30))


STREET = LC.get("street")                       # None switches the whole street-detail block off


def cp_index(e):
    """Sample index of an entry given as {"i":} or {"cp":, "s":} (metres after control point cp)."""
    if "i" in e:
        return int(e["i"])
    return int(round((CL["control_offsets_m"][int(e["cp"])] + float(e["s"])) / SP)) % N


def hexcol(rgb):
    return "#%02X%02X%02X" % tuple(int(round(max(0.0, min(1.0, c)) * 255)) for c in rgb)


def load_inputs():
    cl = json.load(open(CL_PATH, encoding="utf-8"))
    bcat = json.load(open(BCAT_PATH, encoding="utf-8"))
    for rel in LC.get("extra_building_catalogs", []):   # Istanbul kit buildings: same catalog format
        bcat["buildings"] = bcat["buildings"] + json.load(open(os.path.join(REPO, rel), encoding="utf-8"))["buildings"]
    pcat = json.load(open(PCAT_PATH, encoding="utf-8"))
    props = {p["id"]: p for p in pcat["items"]}
    for rel in LC.get("extra_prop_catalogs", []):   # per-track props (new sign texts): catalog dir is the file prefix
        ex = json.load(open(os.path.join(REPO, rel), encoding="utf-8"))
        for p in ex["items"]:
            p["_dir"] = os.path.dirname(rel).replace("\\", "/") + "/"
            props[p["id"]] = p
    if LC.get("street"):   # kit_street (side lanes, facade and sidewalk detail): same catalog format as kit_props
        for p in json.load(open(os.path.join(HERE, "..", "kit_street", "out", "catalog.json"), encoding="utf-8"))["items"]:
            p["_dir"] = "assets_src/world/kit_street/out/"
            props[p["id"]] = p
    return cl, {b["id"]: b for b in bcat["buildings"]}, props


CL, BCAT, PCAT = load_inputs()
ROAD_TRIS = int(LC["road_tris"]) if "road_tris" in LC else int(
    json.load(open(os.path.join(REPO, CFG["road"]["out_dir"], "report.json"), encoding="utf-8"))["triangles_total"])
S = CL["samples"]
E = CL["edges"]
N = len(S)
L = float(CL["lap_length"])
SP = L / N                                       # sample spacing (1.9993 m)
POS = np.array([s["pos"] for s in S], float)     # godot xyz
TAN = np.array([s["tangent"] for s in S], float)
RGT = np.array([s["right"] for s in S], float)
DIST = np.array([s["district"] for s in S])
Y = POS[:, 1]
P2 = POS[:, [0, 2]]                              # plan (x, z)
T2 = TAN[:, [0, 2]]
R2 = RGT[:, [0, 2]]
WATER = np.array([e["open_water_side"] == "left" for e in E])
LINE_PL = {"left": np.array([e["left_building"] for e in E])[:, [0, 2]],
           "right": np.array([e["right_building"] for e in E])[:, [0, 2]]}
LINE_Y = {"left": np.array([e["left_building"][1] for e in E]),
          "right": np.array([e["right_building"][1] for e in E])}
INW = {}   # unit vector from the building line toward the road, plan
for side in ("left", "right"):
    out = LINE_PL[side] - P2
    n = np.linalg.norm(out, axis=1)[:, None]
    INW[side] = -out / n
SIDES = ("left", "right")


def at(arr, sf):
    """Linear interpolation of a per-sample array at a fractional sample index (wraps the loop)."""
    i0 = int(math.floor(sf))
    t = sf - i0
    return arr[i0 % N] * (1.0 - t) + arr[(i0 + 1) % N] * t


def unit(v):
    return v / np.linalg.norm(v)


def yaw_from_front(f):
    """Yaw about +Y so that local +Z (sin yaw, cos yaw) points along plan vector f."""
    return math.atan2(float(f[0]), float(f[1]))


def local_to_world(base, yaw, lp):
    s, c = math.sin(yaw), math.cos(yaw)
    return [base[0] + c * lp[0] + s * lp[2], base[1] + lp[1], base[2] - s * lp[0] + c * lp[2]]


def local_dir(yaw, d):
    s, c = math.sin(yaw), math.cos(yaw)
    return [s * d[2] + c * d[0], d[1], c * d[2] - s * d[0]]


def cl_dist(Q):
    """Minimum plan distance from each row of Q (M,2) to the closed centreline polyline."""
    A = P2
    B = np.roll(P2, -1, axis=0)
    AB = B - A
    AB2 = np.maximum((AB * AB).sum(1), 1e-9)
    AP = Q[:, None, :] - A[None]
    t = np.clip((AP * AB[None]).sum(2) / AB2[None], 0.0, 1.0)
    proj = A[None] + t[..., None] * AB[None]
    return np.sqrt(((Q[:, None, :] - proj) ** 2).sum(2)).min(1)


def nearest_index(pt2):
    return int(np.argmin(((P2 - np.asarray(pt2)) ** 2).sum(1)))


def outline(F, f, w, d, lzs):
    u = np.array([f[1], -f[0]])
    pts = []
    for lz in lzs:
        for lx in np.linspace(-w / 2, w / 2, max(2, int(w) + 2)):
            pts.append(F + u * lx + f * lz)
    for lx in (-w / 2, w / 2):
        for lz in np.linspace(-d, 0.0, max(2, int(d) + 2)):
            pts.append(F + u * lx + f * lz)
    return np.array(pts)


def box_corners(F, f, w, d, expand=0.0):
    u = np.array([f[1], -f[0]])
    hw = w / 2 + expand
    cs = [(-hw, -d - expand), (hw, -d - expand), (hw, CANOPY), (-hw, CANOPY)]
    return np.array([F + u * lx + f * lz for lx, lz in cs])


def sat_overlap(a, b):
    for poly in (a, b):
        for k in range(4):
            e = poly[(k + 1) % 4] - poly[k]
            n = np.array([-e[1], e[0]])
            nn = np.linalg.norm(n)
            if nn < 1e-12:
                continue
            n = n / nn
            pa, pb = a @ n, b @ n
            if pa.max() <= pb.min() or pb.max() <= pa.min():
                return False
    return True


# ------------------------------------------------------------------ state
PLACED = []       # first-row and second-row footprints (dicts with corners, F, f, w, d)
INST = []         # every placed instance
LIGHTS = []
ALLEY_MARKS = []  # (side, sf) centres of alley gaps in Old Market, for market stalls
RNG = random.Random(SEED)


def add_instance(kind, asset, file, base, yaw, district, side, s_idx, extra=None, lod1_file=None):
    rec = {"kind": kind, "asset": asset, "file": file,
           "position": [round(float(base[0]), 3), round(float(base[1]), 3), round(float(base[2]), 3)],
           "yaw": round(float(yaw), 5), "district": DISTRICTS.get(district, "none") if district is not None else "none",
           "side": side, "s_offset_m": round(float(s_idx) * SP, 2)}
    if lod1_file:
        rec["lod1_file"] = lod1_file
    if extra:
        rec.update(extra)
    INST.append(rec)
    return rec


def skip_index(i, side):
    if TUNNEL_D is not None and DIST[i] == TUNNEL_D:
        return True
    for sd, a, b in NO_BUILD:
        if sd == side and a <= i * SP <= b:
            return True
    if side == "left" and WATER[i]:
        return True
    if Y[i] < -0.8:
        return True
    return False


def try_building(side, sf, bid, dist):
    b = BCAT[bid]
    w, d = b["width"], b["depth"]
    sf_mid = sf + (w / 2) / SP
    i_start = int(sf)
    i_end = int(sf + w / SP) + 1
    for i in range(i_start - 12, i_end + 13):
        if skip_index(i % N, side):
            return None
    for i in range(i_start, i_end + 1):          # whole footprint span must sit in the pool's district
        if int(DIST[i % N]) != dist:
            return None
    F = at(LINE_PL[side], sf_mid)
    f = unit(at(INW[side], sf_mid))
    road_y = at(Y, sf_mid)
    base_y = 0.0 if road_y > 0.8 else 0.15
    body = outline(F, f, w, d, [-d, 0.0])
    canopy = outline(F, f, w, d, [CANOPY])
    if cl_dist(body).min() < MIN_CL:
        return None
    if cl_dist(canopy).min() < CANOPY_MIN:
        return None
    cand = box_corners(F, f, w, d, expand=MARGIN)
    for p in PLACED:
        if np.linalg.norm(p["F"] - F) > (w + d) + 40.0:
            continue
        if sat_overlap(cand, p["corners"]):
            return None
    return {"F": F, "f": f, "w": w, "d": d, "bid": bid, "base": [float(F[0]), base_y, float(F[1])],
            "yaw": yaw_from_front(f), "corners": box_corners(F, f, w, d), "sf": sf_mid,
            "district": int(DIST[int(round(sf_mid)) % N]), "side": side, "height": b["height"]}


def pack_side(side):
    s = 0.0
    last = None
    placed_here = 0
    while s < L:
        sf = s / SP
        i = int(sf) % N
        if skip_index(i, side):
            s += 2.0
            continue
        dist = int(DIST[i])
        pool = [p for p in BLD_POOL.get(dist, []) if BCAT[p]["storeys"] >= MIN_STOREYS.get(dist, 1)]
        if not pool:
            s += 2.0
            continue
        pick = RNG.choice([p for p in pool if p != last] or pool)
        order = [pick] + sorted([p for p in pool if p != pick], key=lambda x: -BCAT[x]["width"])
        rec = None
        for bid in order:
            rec = try_building(side, sf, bid, dist)
            if rec:
                break
        if rec is None:
            s += 1.5
            continue
        rec["second_row"] = False
        PLACED.append(rec)
        placed_here += 1
        last = rec["bid"]
        lane_gw = lane_due(side, s + BCAT[rec["bid"]]["width"], dist)
        if lane_gw:   # a side lane: the next building starts one lane width further on
            LANES.append({"side": side, "idx": len(PLACED), "dist": dist})
            gap = lane_gw
        elif RNG.random() < 0.12:
            gap = RNG.uniform(4.0, 6.0)
            if MARKET_D is not None and dist == MARKET_D:
                ALLEY_MARKS.append((side, (s + BCAT[rec["bid"]]["width"] + gap / 2) / SP))
        else:
            gap = RNG.choice([0.5, 1.0, 1.5])
        s = s + BCAT[rec["bid"]]["width"] + gap
    return placed_here


def add_building_instances():
    for rec in PLACED:
        b = BCAT[rec["bid"]]
        add_instance("building", rec["bid"], "assets_src/world/kit_buildings/out/%s.glb" % rec["bid"],
                     rec["base"], rec["yaw"], rec["district"], rec["side"], rec["sf"],
                     {"lod_policy": "LOD0_LOD1_LOD2_by_distance", "storeys": b["storeys"],
                      "height_m": b["height"], "width_m": rec["w"], "depth_m": rec["d"]})


def second_row():
    """LOD2-only boxes behind the first row: 30 m back (Neon, Downtown, Market) and, for Downtown, a
    third 60 m row that fills the loop interior so the block is not an open void."""
    n_added = 0
    for back, parents, prob in SECOND_ROW:
        for rec in list(PLACED):
            if rec["district"] not in SECOND_ROW_D or rec["district"] not in parents:
                continue
            if back == 60.0 and not rec.get("second_row"):
                continue
            if back == 30.0 and rec.get("second_row") and rec["row_back"] != 0.0:
                continue
            if RNG.random() > prob:
                continue
            row_back = rec.get("row_back", 0.0) + back
            F2 = rec["F"] - rec["f"] * row_back    # behind the first-row facade
            b = BCAT[rec["bid"]]
            cand = box_corners(F2, rec["f"], rec["w"], rec["d"], expand=MARGIN)
            ok = True
            for p in PLACED:
                if np.linalg.norm(p["F"] - F2) > (rec["w"] + rec["d"]) + 40.0:
                    continue
                if sat_overlap(cand, p["corners"]):
                    ok = False
                    break
            if not ok:
                continue
            base = [float(F2[0]), 0.0, float(F2[1])]
            PLACED.append({"F": F2, "f": rec["f"], "w": rec["w"], "d": rec["d"], "bid": rec["bid"],
                           "base": base, "yaw": rec["yaw"], "corners": box_corners(F2, rec["f"], rec["w"], rec["d"]),
                           "sf": rec["sf"], "district": rec["district"], "side": rec["side"],
                           "second_row": True, "row_back": row_back, "height": b["height"]})
            add_instance("building_lod2_only", rec["bid"], "assets_src/world/kit_buildings/out/%s.glb" % rec["bid"],
                         base, rec["yaw"], rec["district"], rec["side"], rec["sf"],
                         {"lod_policy": "LOD2_only", "tris_lod2": b["tris"]["LOD2"],
                          "width_m": rec["w"], "depth_m": rec["d"], "height_m": b["height"],
                          "row_back_m": row_back})
            n_added += 1
    return n_added


def prop(asset, base, yaw, district, side, sf, lights_on=True, extra=None, lod1=False, source=None):
    p = PCAT[asset]
    pdir = p.get("_dir", "assets_src/world/kit_props/out/")
    fn = pdir + p["file"]
    lod1f = (pdir + p["lod1_file"]) if (lod1 and p.get("lod1_file")) else None
    rec = add_instance("prop", asset, fn, base, yaw, district, side, sf,
                       dict({"category": p["category"], "tris_lod0": p["tris"],
                             "tris_lod1": p.get("lod1_tris"), "materials": len(p["materials"])},
                            **(extra or {})), lod1_file=lod1f)
    if lights_on and p.get("lights"):
        # shortcut: string lights keep one of their four bulb hints, to hold the 60 m light count; upgrade to all four if the engine can afford it
        hints = p["lights"][1:2] if asset == "string_lights_span" else p["lights"]
        for h in hints:
            lpos = local_to_world(base, yaw, h["pos_godot"])
            d = h.get("direction_godot")
            LIGHTS.append({"type": h["type"], "source": source or "prop:" + asset, "district": DISTRICTS.get(district),
                           "position": [round(x, 3) for x in lpos],
                           "direction": ([round(x, 4) for x in local_dir(yaw, d)] if d else None),
                           "color": hexcol(h["color"]), "energy": h["energy"],
                           "range": 22.0 if source == "lamp_head" else h["range"], "shadows": False,
                           "s_offset_m": round(sf * SP, 2)})
    return rec


def point_on(side, i, k):
    """Plan point k metres inward from the building line at sample i, and its y."""
    LP = LINE_PL[side][i % N]
    inw = INW[side][i % N]
    return np.array([LP[0] + inw[0] * k, LINE_Y[side][i % N] - 0.15 + 0.15, LP[1] + inw[1] * k])


def sidewalk_k(i, base_k):
    """Keep sidewalk props clear of the kerb: Old Market roads are 16 m wide."""
    cap = SIDEWALK_CAP.get(int(DIST[i % N]))
    return min(base_k, cap) if cap is not None else base_k


def place_lamps():
    toggle = False
    s = RNG.uniform(0, 16.0)
    n = 0
    while s < L:
        i = int(s / SP) % N
        d = int(DIST[i])
        if d in LAMP_SKIP_D or (Y[i] > 0.8 and not LAMP_DECK) or Y[i] < -0.8:
            s += 4.0
            s += RNG.uniform(0, 0.0)
            continue
        side = "right" if toggle else "left"
        if side == "left" and WATER[i]:
            side = "right"
        k = sidewalk_k(i, 2.9)
        base = point_on(side, i, k)
        f = unit(INW[side][i])
        yaw = yaw_from_front(f)
        asset = LAMP_ASSET.get(d, LAMP_DEFAULT)
        prop(asset, [base[0], Y[i] + 0.15, base[2]], yaw, d, side, i,
             source="lamp_head")
        toggle = not toggle
        n += 1
        s += RNG.uniform(LAMP_STEP[0], LAMP_STEP[1])
    return n


def place_tunnel():
    idx = [i for i in range(N) if TUNNEL_D is not None and DIST[i] == TUNNEL_D]
    if not idx:
        return 0
    n = 0
    start = idx[0]
    end = idx[-1]
    for i in range(start, end + 1, 6):           # every 12 m
        c = P2[i]
        yc = Y[i] + 4.9
        LIGHTS.append({"type": "omni", "source": "tunnel_strip", "district": "underpass",
                       "position": [round(float(POS[i, 0]), 3), round(yc, 3), round(float(POS[i, 2]), 3)],
                       "direction": None, "color": "#BFD8FF", "energy": 6.0, "range": 14.0,
                       "shadows": False, "s_offset_m": round(i * SP, 2)})
        n += 1
    for i in range(start, end + 1, 6):           # tunnel wall fixtures, both walls, 12 m
        for side in SIDES:
            pt = point_on(side, i, 0.05)
            f = unit(-INW[side][i])
            prop("tunnel_wall_light", [pt[0], Y[i] + 2.6, pt[2]], yaw_from_front(f), 3, side, i,
                 lights_on=False, source="tunnel_fixture")
    for i in range(start, end + 1, 30):          # ventilation fans every 60 m, right wall only
        pt = point_on("right", i, 0.0)
        f = unit(-INW["right"][i])
        prop("tunnel_fan", [pt[0], Y[i] + 3.6, pt[2]], yaw_from_front(f), 3, "right", i, lights_on=False)
    return n


def place_furniture_and_street():
    counts = {}
    lamp_idx = set(int(x["s_offset_m"] / SP) for x in INST if x["asset"].startswith("lamp"))
    for side in SIDES:
        for i in range(0, N, 5):
            if skip_index(i, side) or Y[i] > 0.8 or Y[i] < -0.8:
                continue
            if any(abs(i - j) <= 3 for j in lamp_idx):
                continue
            d = int(DIST[i])
            f = unit(-INW[side][i])
            for name, p, k in FURN:
                if RNG.random() < p:
                    kk = sidewalk_k(i, k) + RNG.uniform(-0.3, 0.3)
                    pt = point_on(side, i, kk)
                    prop(name if name in PCAT else name, [pt[0], Y[i] + 0.15, pt[2]], yaw_from_front(f), d, side, i,
                         lights_on=False)
                    counts[name] = counts.get(name, 0) + 1
    return counts


def place_corner_barriers():
    """Jersey barriers on the outside of every corner (radius below 100 m)."""
    T = T2 / np.linalg.norm(T2, axis=1)[:, None]
    dT = (np.roll(T, -1, 0) - np.roll(T, 1, 0)) / (2 * SP)
    kr = (dT * R2).sum(1)                        # > 0 means turning right
    kap = np.abs(kr)
    n = 0
    for i in range(N if CORNER_BARRIERS else 0):
        if kap[i] < 1 / 100.0 or Y[i] > 0.8 or Y[i] < -0.8 or DIST[i] == TUNNEL_D:   # corners: radius under 100 m
            continue
        outer = "left" if kr[i] > 0 else "right"   # outside of a right turn is the left side
        if outer == "left" and WATER[i]:
            continue
        pt = point_on(outer, i, sidewalk_k(i, 3.2))
        f = unit(-INW[outer][i])
        if i % 2:
            continue
        prop("jersey_barrier", [pt[0], Y[i] + 0.0, pt[2]], yaw_from_front(f), int(DIST[i]), outer, i,
             lights_on=False)
        n += 1
    return n


def place_overpass_guardrails():
    n = 0
    for i in range(N):
        if not RAIL_D or Y[i] <= 1.0 or DIST[i] == TUNNEL_D:
            continue
        if i % 2:
            continue
        for side in SIDES:
            pt = point_on(side, i, 3.25)
            f = unit(-INW[side][i])
            prop("guardrail_segment", [pt[0], Y[i] + 0.15, pt[2]], yaw_from_front(f), int(DIST[i]), side, i,
                 lights_on=False)
            n += 1
    return n


def apex_index(guess, half=40):
    T = T2 / np.linalg.norm(T2, axis=1)[:, None]
    dT = (np.roll(T, -1, 0) - np.roll(T, 1, 0)) / (2 * SP)
    kap = np.abs((dT * R2).sum(1))
    idx = [(guess + k) % N for k in range(-half, half + 1)]
    return max(idx, key=lambda j: kap[j])


def place_chevrons_and_cones():
    T = T2 / np.linalg.norm(T2, axis=1)[:, None]
    dT = (np.roll(T, -1, 0) - np.roll(T, 1, 0)) / (2 * SP)
    kr = (dT * R2).sum(1)
    n = 0
    apexes = [apex_index(g) for g in APEX_GUESS]
    for a in apexes:
        outer = "left" if kr[a] > 0 else "right"
        if outer == "left" and WATER[a]:
            outer = "right"
        for off in (-4, 4):
            j = (a + off) % N
            pt = point_on(outer, j, sidewalk_k(j, 2.0))
            f = unit(-T[j])                       # faces the cars arriving from behind
            prop("chevron_board", [pt[0], Y[j] + 0.15, pt[2]], yaw_from_front(f), int(DIST[j]), outer, j,
                 lights_on=False)
            n += 1
    start_i = int(round(CL["start_line"]["offset_m"] / SP))
    for j in range(start_i - 40, start_i + 6, 4):
        for side in SIDES:
            pt = point_on(side, j % N, 3.4)
            prop("traffic_cone", [pt[0], Y[j % N] + 0.15, pt[2]], 0.0, int(DIST[j % N]), side, j % N,
                 lights_on=False)
            n += 1
    return n, apexes


def place_zebra_furniture():
    n = 0
    for z in CL["zebra_positions"]:
        j = int(round(z["offset_m"] / SP)) % N
        f = unit(-T2[j])
        for side in SIDES:
            pt = point_on(side, j, sidewalk_k(j, 2.2))
            prop("traffic_light", [pt[0], Y[j] + 0.15, pt[2]], yaw_from_front(f), int(DIST[j]), side, j,
                 lights_on=True, source="traffic_light_red")
            n += 1
            for off in (-2, 2):
                jj = (j + off) % N
                pb = point_on(side, jj, sidewalk_k(jj, 3.3))
                prop("bollard", [pb[0], Y[jj] + 0.15, pb[2]], yaw_from_front(f), int(DIST[jj]), side, jj,
                     lights_on=False)
                n += 1
    return n


def place_bus_shelters():
    n = 0
    neon_idx = [i for i in range(N) if DIST[i] == BUS_D]
    if not neon_idx:
        return 0
    for frac, side in BUS_FRACS:
        i = neon_idx[int(frac * (len(neon_idx) - 1))]
        if WATER[i] and side == "left":
            side = "right"
        pt = point_on(side, i, sidewalk_k(i, 2.2))
        f = unit(-INW[side][i])
        prop("bus_shelter", [pt[0], Y[i] + 0.15, pt[2]], yaw_from_front(f), BUS_D, side, i, lights_on=True,
             source="bus_shelter_panel")
        n += 1
    return n


def place_string_lights_and_cables():
    n = 0
    mk = [i for i in range(N) if STRING_D is not None and DIST[i] == STRING_D]
    for i in mk[::10]:
        pt = point_on("left", i, 2.0)
        yaw = math.atan2(-R2[i][1], R2[i][0])     # local X runs left to right across the road
        prop("string_lights_span", [pt[0], Y[i] + 5.6, pt[2]], yaw, STRING_D, "left", i, lights_on=True,
             source="string_light")
        n += 1
    neon_idx = [i for i in range(N) if CABLE_D is not None and DIST[i] == CABLE_D]
    for i in neon_idx[::60][:6]:
        pt = point_on("left", i, 0.25)
        yaw = math.atan2(-R2[i][1], R2[i][0])
        prop("cable_span", [pt[0], Y[i] + 0.15, pt[2]], yaw, CABLE_D, "left", i, lights_on=False)
        n += 1
    return n


def place_market_stalls():
    n = 0
    for side, sf in ALLEY_MARKS:
        i = int(sf) % N
        pt = point_on(side, i, 1.2)
        f = unit(-INW[side][i])
        prop("market_stall", [pt[0], Y[i] + 0.15, pt[2]], yaw_from_front(f), MARKET_D, side, i, lights_on=False)
        n += 1
    return n


def place_seaside():
    """Istanbul coast: seaside railing on the quay edge, warm promenade lamps, a few promenade furniture props."""
    n = 0
    water_idx = [i for i in range(N) if WATER[i]]
    step = int(QUAY.get("railing_step", 3))
    for i in water_idx:
        if i % step or not (WATER[(i - 1) % N] and WATER[(i + step) % N]):
            continue
        if any(abs(i * SP - pr["offset_m"]) < pr["w"] / 2.0 + 4.0 for pr in CL.get("piers", [])):
            continue   # the ferry pier opens the railing
        pt = point_on("left", i, float(QUAY.get("railing_k", 0.3)))
        t = T2[i] / np.linalg.norm(T2[i])
        yaw = math.atan2(-t[1], t[0])          # local +X (the 6 m run) along the direction of travel
        prop(QUAY["railing"], [pt[0], Y[i] + 0.15, pt[2]], yaw, int(DIST[i]), "left", i, lights_on=False)
        n += 1
    s = RNG.uniform(0, 8.0)
    lamps = 0
    while s < L:
        i = int(s / SP) % N
        if WATER[i] and WATER[(i - 8) % N] and WATER[(i + 8) % N]:
            pt = point_on("left", i, float(QUAY.get("lamp_k", 1.7)))
            f = unit(INW["left"][i])
            prop(QUAY["lamp"], [pt[0], Y[i] + 0.15, pt[2]], yaw_from_front(f), int(DIST[i]), "left", i, source="lamp_head")
            lamps += 1
        s += RNG.uniform(*QUAY.get("lamp_step_m", [22.0, 25.0]))
    for i in water_idx[::5]:
        for name, p, k in QUAY.get("furniture", []):
            if RNG.random() < p and WATER[(i - 4) % N] and WATER[(i + 4) % N]:
                pt = point_on("left", i, k)
                f = unit(INW["left"][i])
                prop(name, [pt[0], Y[i] + 0.15, pt[2]], yaw_from_front(f), int(DIST[i]), "left", i, lights_on=False)
                n += 1
    return n + lamps


def place_tram():
    """Tram rail segments (12 m, rails + poles + catenary) along the right-hand lane of a control point range."""
    if not TRAM:
        return 0
    a, b = [CL["control_offsets_m"][c] for c in TRAM["cps"]]
    step = float(TRAM.get("step_m", 12.0))
    u = float(TRAM.get("u", 2.3))
    n = 0
    s = a
    while s + step <= b:
        j = int(round((s + step) / SP)) % N      # segment origin = its far end; local +X runs back toward the start
        t = T2[j] / np.linalg.norm(T2[j])
        yaw = math.atan2(-t[1], t[0]) + math.pi  # local -Z (the pole side) = right of travel
        pos = P2[j] + R2[j] * u
        prop(TRAM["asset"], [float(pos[0]), float(Y[j]) + 0.03, float(pos[1])], yaw, int(DIST[j]), "right", j, lights_on=False)
        n += 1
        s += step
    return n


def place_pier_lights():
    """Three cool masts on each ferry pier: root, middle and head."""
    n = 0
    for pr in CL.get("piers", []) if PIER_LIGHTS else []:
        base = np.array([pr["pos"][0], pr["pos"][2]])
        left = np.array([pr["left"][0], pr["left"][2]])
        tan = np.array([pr["tangent"][0], pr["tangent"][2]])
        for a in (2.0, pr["len"] * 0.5, pr["len"] - 1.2):
            for b in (-pr["w"] / 2.0 + 0.6, pr["w"] / 2.0 - 0.6):
                pt = base + left * a + tan * b
                f = unit(-left if a > 3.0 else left)
                i = nearest_index(pt)
                prop(PIER_LIGHTS["asset"], [float(pt[0]), pr["pos"][1], float(pt[1])], yaw_from_front(f), int(DIST[i]), "left", i,
                     lights_on=True, source="ferry_pier_light")
                n += 1
    return n


def place_quay():
    if QUAY:
        return place_seaside()
    n = 0
    water_idx = [i for i in range(N) if WATER[i]]
    # promenade runs from the building line (offset 10.5) to the quay face (offset 16.5); k < 0 is outward
    for i in water_idx[::1]:
        if i % 2:
            continue
        pt = point_on("left", i, -6.0)          # railing on the quay edge, offset 16.5
        f = unit(-INW["left"][i])
        prop("quay_railing", [pt[0], Y[i] + 0.15, pt[2]], yaw_from_front(f), 2, "left", i, lights_on=False)
        n += 1
    for i in water_idx[::15]:
        pt = point_on("left", i, -2.5)          # jersey barriers on the promenade, offset 13
        f = unit(INW["left"][i])
        prop("jersey_barrier", [pt[0], Y[i] + 0.15, pt[2]], yaw_from_front(f), 2, "left", i, lights_on=False)
        n += 1
    return n


def place_bay_backdrop():
    n = 0
    for e in BAY:
        i, off, aid = cp_index(e), e["off"], e["asset"]
        base = P2[i] - (INW["left"][i] * 0) + (-INW["left"][i]) * (off - 10.5)
        prop(aid, [base[0], 0.0, base[1]], yaw_from_front(unit(-(base - P2[i]))),
             e.get("district", 2), "left", i, lights_on=True, source="bay_crane_light", extra={"far": True})
        n += 1
    for e in SKYLINES:
        i = cp_index(e)
        side = e.get("side", "left")
        sk = P2[i] - INW[side][i] * e["off"]
        prop(e.get("asset", "skyline_card"), [sk[0], 0.0, sk[1]], yaw_from_front(unit(-(sk - P2[i]))), e["district"], side, i,
             lights_on=False, extra={"far": True})
        n += 1
    return n


def place_plaza():
    """Original props (fountain sculpture) in an open stretch, off the road on the given side."""
    n = 0
    for e in PLAZA:
        i = cp_index(e)
        v = R2[i] if e["side"] == "right" else -R2[i]
        pt = P2[i] + v * e["off"]
        yaw = yaw_from_front(unit(-v)) if e.get("face") == "road" else 0.0
        prop(e["asset"], [float(pt[0]), e.get("y", -0.28) if "y" in e else -0.28, float(pt[1])], yaw, e.get("district", int(DIST[i])),
             e["side"], i, lights_on=True, source="plaza_light")
        n += 1
    return n


def place_signs_and_roofs():
    """Blade and fascia signs on anchors, rooftop billboards. Returns the sign list for neon fills."""
    signs = []
    land = [r for r in PLACED if not r["second_row"] and r["district"] in SIGN_D]
    for rec in land:
        cat = BCAT[rec["bid"]]
        d = rec["district"]
        prob = SIGN_P.get(d, 0.0)
        for an in cat["anchors"]:
            ax, ay, az = an["position"]
            base = rec["base"]
            wy = base[1]
            if an["name"].startswith("anchor_sign") and RNG.random() < prob:
                pool = SIGN_BOX.get(d)
                if not pool:
                    continue
                asset = RNG.choice(pool)
                wide = PCAT[asset]["size"][0]
                if abs(ax) + wide / 2 > rec["w"] / 2 - 0.5:
                    continue
                lp = [ax, ay, az]
                pos = local_to_world([base[0], wy, base[2]], rec["yaw"], lp)
                rr = prop(asset, pos, rec["yaw"], d, rec["side"], rec["sf"] + (ax + rec["w"] / 2) / SP,
                          lights_on=False, extra={"sign": True})
                signs.append({"asset": asset, "pos": pos, "yaw": rec["yaw"], "area": PCAT[asset]["size"][0] * PCAT[asset]["size"][1],
                              "kind": "box", "color": hexcol(PCAT[asset]["lights"][0]["color"]) if PCAT[asset].get("lights") else "#FFFFFF",
                              "bid": rec["bid"], "d": d})
            elif an["name"].startswith("anchor_blade") and RNG.random() < prob:
                asset = RNG.choice(SIGN_BLADE)
                flip = RNG.random() < 0.5
                yaw = rec["yaw"] + (math.pi if flip else 0.0)
                f = unit(np.array([math.sin(rec["yaw"]), math.cos(rec["yaw"])]))
                lp = [ax, ay, az]
                pos = local_to_world([base[0], wy, base[2]], rec["yaw"], lp)
                if flip:
                    pos = [pos[0] + f[0] * 1.4, pos[1], pos[2] + f[1] * 1.4]
                prop(asset, pos, yaw, d, rec["side"], rec["sf"] + (ax + rec["w"] / 2) / SP,
                     lights_on=False, extra={"sign": True, "flipped": flip})
                signs.append({"asset": asset, "pos": pos, "yaw": yaw, "area": 2.6 * 1.4, "kind": "blade",
                              "color": hexcol(PCAT[asset]["lights"][0]["color"]), "bid": rec["bid"], "d": d})
    # rooftop billboards: 8 tall land-side buildings
    tall = sorted([r for r in land if r["district"] in TALL_D], key=lambda r: -r["height"])
    for bi, rec in enumerate(tall[::max(1, len(tall) // max(1, BILLBOARD_N))][:BILLBOARD_N]):
        bb = BILLBOARD[bi % len(BILLBOARD)]
        base = [rec["base"][0], rec["base"][1] + rec["height"], rec["base"][2]]
        lp = [0.0, 0.0, -1.2]
        pos = local_to_world(base, rec["yaw"], lp)
        prop(bb, pos, rec["yaw"], rec["district"], rec["side"], rec["sf"],
             lights_on=False, extra={"sign": True, "rooftop": True})
        signs.append({"asset": bb, "pos": pos, "yaw": rec["yaw"],
                      "area": 12.4 * 9.1, "kind": "billboard",
                      "color": hexcol(PCAT[bb]["lights"][0]["color"]),
                      "bid": rec["bid"], "d": rec["district"]})
    return signs


def add_neon_fills(signs):
    signs = sorted(signs, key=lambda x: -x["area"])[:NEON_CAP]
    for s in signs:
        off = {"box": (0.0, 0.5, 0.6), "blade": (0.0, 0.0, 0.8), "billboard": (0.0, 6.5, 1.2)}[s["kind"]]
        pos = local_to_world(s["pos"], s["yaw"], off)
        rng = 14.0 if s["kind"] == "billboard" else (12.0 if s["kind"] == "box" else 10.0)
        LIGHTS.append({"type": "omni", "source": "neon_fill", "district": DISTRICTS.get(s["d"]),
                       "position": [round(x, 3) for x in pos], "direction": None, "color": s["color"],
                       "energy": 2.0, "range": rng, "shadows": False,
                       "s_offset_m": round(nearest_index([pos[0], pos[2]]) * SP, 2)})
    return len(signs)


def add_accents():
    cands = sorted([r for r in PLACED if not r["second_row"] and r["district"] in TALL_D],
                   key=lambda r: -r["height"])[:ACCENT_N]
    for r in cands:
        f = r["f"]
        pos = [r["F"][0] + f[0] * 6.0, r["base"][1] + 2.0, r["F"][1] + f[1] * 6.0]
        d = unit(np.array([-f[0] * 0.9, 0.45, -f[1] * 0.9]))
        LIGHTS.append({"type": "spot", "source": "landmark_accent", "district": DISTRICTS[r["district"]],
                       "position": [round(x, 3) for x in pos], "direction": [round(x, 4) for x in d],
                       "color": "#FFF1DC", "energy": 30.0, "range": 16.0, "shadows": False,
                       "s_offset_m": round(nearest_index([pos[0], pos[2]]) * SP, 2)})
    return len(cands)


def place_probes():
    probes = []
    for i in range(0, N, PROBE_STEP):   # one probe per 60 m
        tunnel = DIST[i] == TUNNEL_D
        h = 2.6 if tunnel else 12.5
        yh = Y[i] + h
        yaw = yaw_from_front(T2[i] / np.linalg.norm(T2[i]))
        probes.append({"position": [round(float(POS[i, 0]), 3), round(float(yh), 3), round(float(POS[i, 2]), 3)],
                       "yaw": round(float(yaw), 5),
                       "extents_half": [10.5, round(h, 2), 30.0],
                       "district": DISTRICTS[int(DIST[i])], "s_offset_m": round(i * SP, 2)})
    return probes


def racing_line():
    T = T2 / np.linalg.norm(T2, axis=1)[:, None]
    dT = (np.roll(T, -1, 0) - np.roll(T, 1, 0)) / (2 * SP)
    kr = (dT * R2).sum(1)
    k = np.pad(kr, 8, mode="wrap")
    g = np.exp(-0.5 * (np.arange(-8, 9) / 4.0) ** 2)
    g /= g.sum()
    krs = np.convolve(k, g, mode="same")[8:-8]
    shift = np.clip(135.0 * krs, -4.5, 4.5)
    k2 = np.pad(shift, 10, mode="wrap")
    g2 = np.exp(-0.5 * (np.arange(-10, 11) / 5.0) ** 2)
    g2 /= g2.sum()
    off = np.convolve(k2, g2, mode="same")[10:-10]
    off = np.clip(off, -4.5, 4.5)
    pts = P2 + R2 * off[:, None]
    pts3 = [[round(float(pts[i, 0]), 3), round(float(Y[i]), 3), round(float(pts[i, 1]), 3)] for i in range(0, N, 2)]
    return pts3, float(np.abs(off).max())


def coverage():
    res = {}
    for side in SIDES:
        cov = 0
        tot = 0
        cov_e = 0
        tot_e = 0
        for i in range(N):
            P = LINE_PL[side][i]
            best = 1e9
            for r in PLACED:
                if r["second_row"] or np.linalg.norm(r["F"] - P) > 60:
                    continue
                lx = (P - r["F"]) @ np.array([r["f"][1], -r["f"][0]])
                lz = (P - r["F"]) @ r["f"]
                dx = max(abs(lx) - r["w"] / 2, 0.0)
                dz = max(-r["d"] - lz, lz - CANOPY, 0.0)
                best = min(best, math.hypot(dx, dz))
            ok = best <= 6.0
            tot += 1
            cov += int(ok)
            eligible = (DIST[i] != TUNNEL_D) and not (side == "left" and WATER[i]) and Y[i] >= -0.8
            if eligible:
                tot_e += 1
                cov_e += int(ok)
        res[side] = {"pct_all": round(100.0 * cov / tot, 1), "pct_eligible": round(100.0 * cov_e / max(tot_e, 1), 1)}
    return res


def lights_within_60():
    """Worst case count of lights within 60 m of any centreline sample, in 3D and in plan (x,z).
    Returns the larger of the two so the engine budget is never under-reported."""
    if not LIGHTS:
        return 0, None, 0, 0
    Lp = np.array([l["position"] for l in LIGHTS])
    d3 = np.sqrt(((POS[:, None, :] - Lp[None]) ** 2).sum(2))
    dp = np.sqrt(((P2[:, None, :] - Lp[None][:, :, [0, 2]]) ** 2).sum(2))
    c3 = (d3 <= 60.0).sum(1)
    cp = (dp <= 60.0).sum(1)
    c = np.maximum(c3, cp)
    k = int(np.argmax(c))
    return int(c.max()), round(k * SP, 1), int(c3.max()), int(cp.max())


def budget():
    """Visible triangle and draw-call estimate at 40 viewpoints (1.4 m eye, race heading, 70 deg hfov, 350 m far)."""
    cos35 = math.cos(math.radians(35.0))
    res = []
    pos_xz = np.array([[r["position"][0], r["position"][2]] for r in INST])
    kinds = [r["kind"] for r in INST]
    for k in range(40):
        i = int(round(k * N / 40)) % N
        eye = np.array([POS[i, 0], POS[i, 1] + 1.4, POS[i, 2]])
        h = T2[i] / np.linalg.norm(T2[i])
        v = pos_xz - np.array([eye[0], eye[2]])
        dd = np.sqrt((v ** 2).sum(1)) + 1e-6
        vis = (dd < 350.0) & (dd > 1.0) & ((v @ h) / dd >= cos35)
        tris = ROAD_TRIS
        draws = 1
        n_vis = 0
        groups = set()
        for j in np.nonzero(vis)[0]:
            r = INST[j]
            dist = dd[j]
            if r["kind"] == "building":
                t = (r.get("tris_lod0") or BCAT[r["asset"]]["tris"]["LOD0"]) if dist < 60 else \
                    (BCAT[r["asset"]]["tris"]["LOD1"] if dist < 160 else BCAT[r["asset"]]["tris"]["LOD2"])
                lod = "L0" if dist < 60 else ("L1" if dist < 160 else "L2")
                mats = len(BCAT[r["asset"]]["materials"])
            elif r["kind"] == "building_lod2_only":
                t = BCAT[r["asset"]]["tris"]["LOD2"]
                lod = "L2"
                mats = 1
            else:
                p = PCAT[r["asset"]]
                if r.get("far"):
                    t = p["tris"]
                elif dist < 60:
                    t = p["tris"]
                elif dist < 160:
                    t = p.get("lod1_tris") or p["tris"]
                else:
                    t = 0
                lod = "L0" if dist < 60 else "L1"
                mats = len(p["materials"])
            if t <= 0:
                continue
            tris += t
            n_vis += 1
            draws += mats
            groups.add((r["asset"], lod))
        res.append({"viewpoint": k, "s_offset_m": round(i * SP, 1), "tris": int(tris), "instances": n_vis,
                    "draw_calls_before_instancing": int(draws), "draw_groups_after_instancing": len(groups) + 1})
    worst = sorted(res, key=lambda x: -x["tris"])[:3]
    return res, worst


# ------------------------------------------------------------------ street detail (kit_street): side lanes, facade and sidewalk props
STREET_CAT = os.path.join(HERE, "..", "kit_street", "out", "catalog.json")
STREET_DIR = "assets_src/world/kit_street/out/"
LANES = []                                      # lane gaps made while packing: {side, s0, gw, idx, dist}
LANE_RNG = random.Random(SEED + int((STREET or {}).get("lane_seed", 77)))   # own stream: street choices never move the building RNG
_next_lane = {}
SR = random.Random(SEED + 99)                   # facade / sidewalk / lane dressing choices


def lane_due(side, s_end, dist):
    """Width of a side-lane gap to leave after the building that ends at arc s_end, or 0."""
    cfg = (STREET or {}).get("lanes")
    if not cfg or dist not in cfg.get("districts", list(DISTRICTS)):
        return 0.0
    nxt = _next_lane.setdefault(side, LANE_RNG.uniform(0.25, 0.9) * cfg["step_m"][1])
    if s_end < nxt or s_end + 80.0 > L:
        return 0.0
    gw = LANE_RNG.uniform(*cfg["width_m"])
    i0, i1 = int(s_end / SP), int((s_end + gw) / SP) + 1
    for i in range(i0 - 8, i1 + 10):
        j = i % N
        if skip_index(j, side) or abs(Y[j]) > 0.8 or int(DIST[j]) != dist:
            return 0.0
    if any(abs(z["offset_m"] - (s_end + gw / 2.0)) < 16.0 for z in CL["zebra_positions"]):
        return 0.0
    _next_lane[side] = s_end + LANE_RNG.uniform(*cfg["step_m"])
    return gw


def build_lanes():
    """Turn the lane gaps into lanes: measure the real gap between the two neighbours, close the lane end with an
    LOD2 building, and keep the result in ST_LANES for lane_props()."""
    cfg = STREET["lanes"]
    out = []
    for ln in LANES:
        idx, side = ln["idx"], ln["side"]
        if idx < 1 or idx >= len(PLACED):
            continue
        prev, nxt = PLACED[idx - 1], PLACED[idx]
        if prev["side"] != side or nxt["side"] != side or prev["second_row"] or nxt["second_row"]:
            continue
        u = np.array([prev["f"][1], -prev["f"][0]])
        sgn = 1.0 if float(u @ (T2[int(round(prev["sf"])) % N] / np.linalg.norm(T2[int(round(prev["sf"])) % N]))) > 0 else -1.0
        e0 = prev["F"] + u * sgn * prev["w"] / 2.0
        un = np.array([nxt["f"][1], -nxt["f"][0]])
        e1 = nxt["F"] - un * sgn * nxt["w"] / 2.0
        f = unit(prev["f"] + nxt["f"])
        u = np.array([f[1], -f[0]]) * sgn          # lx axis, runs along the direction of travel
        gw = float((e1 - e0) @ u)
        if gw < 6.5 or gw > 16.0:
            continue
        Fc = (e0 + e1) / 2.0
        depth = min(prev["d"], nxt["d"])
        base_y = prev["base"][1]
        dist = ln["dist"]
        pool = BLD_POOL.get(dist, [])
        wide = sorted([b for b in pool if BCAT[b]["width"] >= gw + 1.5], key=lambda b: BCAT[b]["width"])
        bid = (wide or sorted(pool, key=lambda b: -BCAT[b]["width"]))[0] if pool else None
        if bid is None:
            continue
        b = BCAT[bid]
        length = max(10.0, min(float(cfg.get("max_len_m", 36.0)), depth - 1.5))
        placed = None
        while length >= 10.0 and placed is None:
            F2 = Fc - f * length
            cand = box_corners(F2, f, b["width"], b["depth"], expand=MARGIN)
            clash = any(p is not prev and p is not nxt and np.linalg.norm(p["F"] - F2) < (b["width"] + b["depth"]) + 40.0
                        and sat_overlap(cand, p["corners"]) for p in PLACED)
            if not clash:
                placed = F2
            else:
                length -= 4.0
        if placed is None:
            continue
        rec = {"F": placed, "f": f, "w": b["width"], "d": b["depth"], "bid": bid, "base": [float(placed[0]), base_y, float(placed[1])],
               "yaw": yaw_from_front(f), "corners": box_corners(placed, f, b["width"], b["depth"]), "sf": prev["sf"],
               "district": dist, "side": side, "second_row": True, "row_back": length, "height": b["height"]}
        PLACED.append(rec)
        add_instance("building_lod2_only", bid, "assets_src/world/kit_buildings/out/%s.glb" % bid, rec["base"], rec["yaw"], dist, side,
                     prev["sf"], {"lod_policy": "LOD2_only", "tris_lod2": b["tris"]["LOD2"], "width_m": b["width"],
                                  "depth_m": b["depth"], "height_m": b["height"], "row_back_m": length, "lane_end": True})
        out.append({"side": side, "F": Fc, "f": f, "u": u, "gw": gw, "len": length, "y": base_y,
                    "dist": dist, "sc": ((prev["sf"] + nxt["sf"]) / 2.0), "h": min(prev["height"], nxt["height"]),
                    "end_w": b["width"]})
    return out


def sprop(asset, ln, lx, lz, yoff, front, cat="street", extra=None):
    """Street prop at lane coordinates: lx across (along travel), lz along the lane (negative = into the block);
    front = plan vector the prop's local +Z should face."""
    pos = ln["F"] + ln["u"] * lx + ln["f"] * lz
    ex = {"category": cat, "street": True}
    if extra:
        ex.update(extra)
    return prop(asset, [float(pos[0]), ln["y"] + yoff, float(pos[1])], yaw_from_front(front), ln["dist"], ln["side"], ln["sc"],
                lights_on=False, extra=ex)


def lane_props(ln, k):
    cfg = STREET["lanes"]
    gw, ln_len, h = ln["gw"], ln["len"], ln["h"]
    half = gw / 2.0
    u, f = ln["u"], ln["f"]
    a_sgn = SR.choice([-1.0, 1.0])          # wall A takes the heavy dressing, wall B the light
    wallA, wallB = a_sgn * half, -a_sgn * half
    fa, fb = -a_sgn * u, a_sgn * u          # facing out of each wall into the lane
    n = 0
    sprop("street_alley_floor", ln, 0.0, 0.25, -0.02, f, "street_far"); n += 1
    # wall lamps with their light pools
    for lz, wall, fr in ((-4.5, wallA, fa), (-(ln_len - 4.0), wallB, fb)):
        if ln_len < 13.0 and lz < -6.0:
            continue
        sprop("street_alley_lamp", ln, wall, lz, 3.7, fr, "street"); n += 1
        sprop("street_glow_wall", ln, wall - math.copysign(0.04, wall), lz, 3.0, fr, "street_far"); n += 1   # light wash on the brick below the lamp
    for lz in sorted(set([-2.0, -4.5 - 4.0] + [-(ln_len - 4.0) + 3.0 * j for j in (0, 1)] + [-ln_len * 0.5])):
        if -lz < ln_len - 0.5:
            sprop("street_glow_pool", ln, SR.uniform(-0.8, 0.8), lz, 0.0, f, "street_far"); n += 1
    # hanging cables across the lane (14 m span, left anchor 7 m up)
    for lz in (-3.0, -ln_len * 0.55):
        if SR.random() < cfg.get("cables_p", 0.75) and h > 9.0:
            pos = ln["F"] + u * (-7.0) + f * lz
            prop("street_cables_hang", [float(pos[0]), ln["y"], float(pos[1])], math.atan2(-u[1], u[0]), ln["dist"], ln["side"], ln["sc"],
                 lights_on=False, extra={"category": "street_far", "street": True}); n += 1
    # wall A: fire escape, AC units
    if h >= 13.0 and ln_len >= 14.0 and SR.random() < cfg.get("fire_escape_p", 0.5):
        sprop("street_fire_escape", ln, wallA, -min(10.0, ln_len * 0.45) - 1.5, 0.4, fa, "street_wall"); n += 1
    for lz in (-2.0, -ln_len * 0.75):
        if SR.random() < 0.6 and h > 7.0:
            sprop("street_ac_unit", ln, wallA, lz, SR.uniform(4.6, min(9.0, h - 2.0)), fa, "street_wall"); n += 1
    if SR.random() < 0.7 and h > 9.0:
        sprop("street_ac_cluster", ln, wallB, -ln_len * 0.5, SR.uniform(5.0, min(8.0, h - 3.0)), fb, "street_wall"); n += 1
    if SR.random() < 0.45 and h > 8.0:
        sprop("street_ac_unit", ln, wallB, -3.0, SR.uniform(4.6, min(8.0, h - 2.0)), fb, "street_wall"); n += 1
    # floor clutter against wall A
    sprop("street_dumpster", ln, wallA - a_sgn * 0.65, -6.5, 0.0, fa); n += 1
    sprop("street_trash_bags", ln, wallA - a_sgn * 0.6, -8.7, 0.0, fa); n += 1
    if SR.random() < 0.8:
        sprop("street_crate_stack", ln, wallA - a_sgn * 0.5, -11.5, 0.0, fa); n += 1
    if SR.random() < 0.5 and ln_len >= 14.0:
        sprop("street_alley_gate", ln, wallB, -ln_len * 0.35, 0.0, fb); n += 1
    # floor of wall B: kiosk or scooters
    if gw >= 9.0 and SR.random() < cfg.get("kiosk_p", 0.4):
        sprop("street_kiosk", ln, wallB + a_sgn * 1.7, -6.0, 0.0, f); n += 1
    else:
        for lz in (-3.5, -5.2):
            if SR.random() < 0.7:
                sprop(SR.choice(["street_scooter_a", "street_scooter_b"]), ln, wallB + a_sgn * 0.7, lz, 0.0, f * SR.choice([1.0, -1.0])); n += 1
    # lane floor: manhole, puddles, steam
    sprop("street_manhole", ln, SR.uniform(-1.0, 1.0), -ln_len * 0.4, 0.0, f); n += 1
    for nm in ("street_puddle_a", "street_puddle_b", "street_puddle_c"):
        if SR.random() < 0.7:
            sprop(nm, ln, SR.uniform(-half + 1.8, half - 1.8), -SR.uniform(2.5, ln_len - 2.0), 0.0, np.array([math.sin(SR.uniform(0, 6.28)), math.cos(SR.uniform(0, 6.28))])); n += 1
    if SR.random() < cfg.get("steam_p", 0.5):
        sprop("street_steam_vent", ln, SR.uniform(-1.2, 1.2), -ln_len * 0.62, 0.0, f); n += 1
    # mouth: barrier, bollards
    if SR.random() < cfg.get("barrier_p", 0.25):
        for lx in (-gw / 4.0, gw / 4.0):
            sprop("street_roadwork_barrier", ln, lx, -0.8, 0.0, f); n += 1
    for lx in (-half + 0.7, half - 0.7):
        sprop(SR.choice(["street_bollard_stone", "street_bollard_flex"]), ln, lx, 1.1, 0.0, f); n += 1
    return n


def signal_pair(ln, i, phase):
    """Traffic signals at a lane mouth: a mast at the lane's near corner and one on the opposite kerb at the same s."""
    n = 0
    side = ln["side"]
    opp = "left" if side == "right" else "right"
    p1 = ln["F"] + ln["u"] * SR.choice([-1.0, 1.0]) * (ln["gw"] / 2.0 - 0.9) + ln["f"] * 2.3
    pts = [(p1, side), (point_on(opp, i, 2.3)[[0, 2]], opp)]
    for pt, sd in pts:
        xd = unit(P2[i] - pt)
        prop("street_signal", [float(pt[0]), float(Y[i]) + 0.15, float(pt[1])], math.atan2(-xd[1], xd[0]), int(DIST[i]), sd, i,
             lights_on=False, extra={"category": "signal_" + phase, "street": True})
        n += 1
    return n


def place_street_props(lanes):
    """Lane dressing, junction signals, facade props and sidewalk clutter. Returns the counts."""
    cnt = {"lanes": 0, "lane_props": 0, "facade": 0, "sidewalk": 0, "signals": 0}
    cfg = STREET
    lamp_idx = set(int(x["s_offset_m"] / SP) for x in INST if x["asset"].startswith("lamp") or x["asset"].endswith("lamp"))
    for k, ln in enumerate(lanes):
        cnt["lanes"] += 1
        cnt["lane_props"] += lane_props(ln, k)
        i = int(round(ln["sc"])) % N
        if cfg["lanes"].get("signal_every", 0) and k % int(cfg["lanes"]["signal_every"]) == 0:
            cnt["signals"] += signal_pair(ln, i, "a" if (k // int(cfg["lanes"]["signal_every"])) % 2 == 0 else "b")
    fc = cfg.get("facade")
    if fc:
        for rec in PLACED:
            if rec["second_row"] or rec["district"] not in fc.get("districts", list(DISTRICTS)):
                continue
            b = BCAT[rec["bid"]]
            w, h, f = rec["w"], rec["height"], rec["f"]
            u = np.array([f[1], -f[0]])
            anchors = [(a["position"][0], a["position"][1]) for a in b.get("anchors", [])]   # (lx, height)
            used = []

            def spot(zlo, zhi, half_w, extra_gap=1.0):
                for _ in range(6):
                    lx = SR.uniform(-w / 2 + half_w + 0.6, w / 2 - half_w - 0.6) if w > 2 * half_w + 1.2 else 0.0
                    z = SR.uniform(zlo, max(zlo, zhi))
                    if any(abs(lx - ax) < half_w + 1.4 and az - 3.5 < z < az + 2.5 for ax, az in anchors):
                        continue
                    if any(abs(lx - ux_) < half_w + hw_ + extra_gap and abs(z - uz_) < 2.2 for ux_, uz_, hw_ in used):
                        continue
                    used.append((lx, z, half_w))
                    return lx, z
                return None
            def put_wall(asset, lx, z):
                pos = np.array([rec["F"][0], rec["F"][1]]) + u * lx + f * 0.03
                prop(asset, [float(pos[0]), rec["base"][1] + z, float(pos[1])], rec["yaw"], rec["district"], rec["side"], rec["sf"],
                     lights_on=False, extra={"category": "street_wall", "street": True})
                cnt["facade"] += 1
            if h > 12.0 and fc.get("fire_escape", 0) and SR.random() < fc["fire_escape"] and b.get("storeys", 0) >= 5:
                s_ = spot(0.5, 0.5, 1.5, 0.5)
                if s_:
                    put_wall("street_fire_escape", s_[0], 0.5)
            if h > 9.0:
                for _ in range(int(fc.get("ac_max", 2))):
                    if SR.random() < fc.get("ac", 0.6):
                        s_ = spot(4.8, min(h - 3.0, fc.get("ac_zmax", 26.0)), 0.45)
                        if s_:
                            put_wall("street_ac_unit", s_[0], s_[1])
                if SR.random() < fc.get("cluster", 0.1):
                    s_ = spot(6.0, min(h - 3.5, fc.get("ac_zmax", 26.0)), 1.4)
                    if s_:
                        put_wall("street_ac_cluster", s_[0], s_[1])
    sc = cfg.get("sidewalk")
    if sc:
        lane_s = [ln["sc"] for ln in lanes]
        for side in SIDES:
            for i in range(2, N, int(sc.get("step", 4))):
                if skip_index(i, side) or abs(Y[i]) > 0.8:
                    continue
                if any(abs(i - j) <= 4 for j in lamp_idx) or any(abs(i - s_) < 9.0 for s_ in lane_s):
                    continue
                d = int(DIST[i])
                if d not in sc.get("districts", list(DISTRICTS)):
                    continue
                t = unit(T2[i])
                f = unit(-INW[side][i])
                roll = SR.random()
                pick = None
                acc = 0.0
                for name, p, kk, mode in sc["items"]:
                    acc += p
                    if roll < acc:
                        pick = (name, kk, mode)
                        break
                if not pick:
                    continue
                name, kk, mode = pick
                pt = point_on(side, i, sidewalk_k(i, kk))
                front = f if mode == "face" else (t * SR.choice([1.0, -1.0]) if mode == "along" else np.array([math.sin(SR.uniform(0, 6.28)), math.cos(SR.uniform(0, 6.28))]))
                prop(name, [pt[0], Y[i] + 0.15, pt[2]], yaw_from_front(front), d, side, i, lights_on=False,
                     extra={"category": "street", "street": True})
                cnt["sidewalk"] += 1
    return cnt


def main():
    random.seed(SEED)
    np.random.seed(SEED)
    rows = {}
    rows["left_first_row"] = pack_side("left")
    rows["right_first_row"] = pack_side("right")
    add_building_instances()
    lanes = build_lanes() if STREET and STREET.get("lanes") else []
    rows["second_row_lod2"] = second_row()
    cov = coverage()
    counts_lamps = place_lamps()
    counts_tunnel = place_tunnel()
    counts_furn = place_furniture_and_street()
    counts_barr = place_corner_barriers()
    counts_guard = place_overpass_guardrails()
    counts_chev, apexes = place_chevrons_and_cones()
    counts_zeb = place_zebra_furniture()
    counts_bus = place_bus_shelters()
    counts_str = place_string_lights_and_cables()
    counts_stall = place_market_stalls()
    counts_quay = place_quay()
    counts_bay = place_bay_backdrop()
    counts_plaza = place_plaza()
    counts_tram = place_tram()
    counts_pier = place_pier_lights()
    counts_street = place_street_props(lanes) if STREET else {}
    signs = place_signs_and_roofs()
    n_neon = add_neon_fills(signs)
    n_acc = add_accents()
    probes = place_probes()
    line_pts, max_shift = racing_line()
    max60, max60_at, max60_3d, max60_plan = lights_within_60()
    buds, worst = budget()

    lap_ok = LAP_RANGE[0] <= L <= LAP_RANGE[1]
    rec_out = {
        "coords": "godot_y_up",
        "units": "metres",
        "track": TRACK_ID,
        "generator": "assets_src/world/tracks/build_layout.py",
        "seed": SEED,
        "lap_length": L,
        "sample_spacing_m": round(SP, 4),
        "yaw_convention": "yaw rad about +Y; local +Z is front; world = (sin yaw, 0, cos yaw) for front",
        "instances": INST,
        "lights": LIGHTS,
        "reflection_probes": probes,
        "racing": {
            "grid_slots": CL["grid_slots"],
            "start_line": CL["start_line"],
            "gates": CL["gates"],
            "lap_length": L,
            "racing_line_spacing_m": 4.0,
            "racing_line": line_pts,
            "racing_line_max_shift_m": round(max_shift, 3),
        },
        "budget": {"road_tris": ROAD_TRIS, "viewpoints": buds, "worst3": worst,
                   "budget_tris": BUDGET_TRIS, "budget_draws": BUDGET_DRAWS},
        "checks": {
            "lap_length_m": round(L, 2), "lap_ok_2200_2500": lap_ok,
            "building_line_coverage_within_6m_pct": cov,
            "lights_total": len(LIGHTS),
            "max_lights_within_60m_of_any_sample": max60,
            "max_lights_within_60m_at_offset_m": max60_at,
            "max_lights_within_60m_3d": max60_3d,
            "max_lights_within_60m_plan": max60_plan,
            "reflection_probes": len(probes),
            "neon_fill_lights": n_neon,
            "accent_spots": n_acc,
            "alley_gaps_market": len(ALLEY_MARKS),
            "street_detail": counts_street if STREET else None,
            "buildings_first_row": len([r for r in PLACED if not r["second_row"]]),
            "buildings_second_row_lod2": rows["second_row_lod2"],
        },
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as fh:
        json.dump(rec_out, fh, separators=(",", ":"))

    # self-checks
    assert len(line_pts) == (N + 1) // 2
    for p in INST:
        assert all(math.isfinite(x) for x in p["position"]), p
    kinds = {}
    for r in INST:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    print("placed", kinds, "lights", len(LIGHTS), "probes", len(probes))
    print("rows", rows, "coverage", cov)
    print("lamps", counts_lamps, "tunnel", counts_tunnel, "furniture", counts_furn)
    print("barriers", counts_barr, "guardrails", counts_guard, "chevrons/cones", counts_chev, "apexes", apexes)
    print("zebra", counts_zeb, "bus", counts_bus, "string/cable", counts_str, "stalls", counts_stall,
          "quay", counts_quay, "bay", counts_bay, "plaza", counts_plaza, "signs", len(signs), "neon fills", n_neon, "accents", n_acc)
    print("tram", counts_tram, "pier lights", counts_pier, "street", counts_street, "lane gaps", len(LANES), "lanes built", len(lanes))
    print("max lights within 60 m", max60, "at offset", max60_at)
    print("racing line max shift", round(max_shift, 3), "points", len(line_pts))
    print("worst3", worst)
    print("wrote", OUT_PATH, os.path.getsize(OUT_PATH))


if __name__ == "__main__":
    main()
