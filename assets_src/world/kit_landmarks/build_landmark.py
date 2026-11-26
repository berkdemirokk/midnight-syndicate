"""Waterfront mosque kit (Blender 5.3, deterministic, procedural only, no downloads).

Run:  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup --python build_landmark.py

Original design, not a replica of any real building: a floodlit neo-baroque prayer hall on a plinth with pilasters,
a three-step cornice and a string course, two window tiers of round-arched glass in raised archivolt frames, a porch
of three arches on the road side, a windowed drum and a ribbed dome with a finial, four corner turrets with little
domes, two fluted minarets with a balcony and a pencil cap, a stepped marble quay down to the water and a balustrade
around the paved square. Lamp posts stand along the seaside.

Frame (Blender metres, Z up; the glTF export turns Z into Godot Y, Blender Y into -Godot Z):
  origin  the quay's landward edge (Blender Y 0), centre of the quay, ground level
  +X      forward along the road (race direction)
  Y 0..32 quay, from the road (Y 0) to the sea (Y 32). The road is at Y < 0, the sea at Y > 32.
  Godot: local +Z points landward (toward the road); the hall front faces the road.
  Quay top at Z 0.15 (the road kerbs sit at 0.15), the seaward steps run down to the water at Z -1.2.

Output (game/assets/world/kits/landmarks/):
  landmark_mosque_lod0.glb  <= 22 000 tris, one surface per material name
  landmark_mosque_lod1.glb  <= 6 000 tris
  landmark_mosque_lod2.glb  <= 600 tris
  landmark_mosque_report.json  triangle counts per LOD and material

Materials (names are read by game/world/landmarks/landmarks.gd):
  M_Stone  marble and limestone          M_Dome  lead dome, pencil caps
  M_Glass  windows and portal (glow at night)   M_Lamp  lamp heads, minaret ring lights
  M_Iron   railing, lamp posts, finial   M_Paving  wet paved square

Every face is oriented by construction: each poly() call is given the outward direction and flips the face to match.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_DIR = os.path.join(REPO, "game", "assets", "world", "kits", "landmarks")
sys.path.insert(0, os.path.join(REPO, "assets_src", "pipeline"))
import bake_vertex_ao as ao  # noqa: E402

# baked ambient occlusion (vertex colour) per LOD: grid cell size in m, None = no subdivision (LOD1 budget is tight)
AO_CELL = {0: 5.5, 1: None}

MATS = ["M_Stone", "M_Dome", "M_Glass", "M_Lamp", "M_Iron", "M_Paving"]
STONE, DOME, GLASS, LAMP, IRON, PAVE = range(6)
MAT_COLOURS = [(0.88, 0.85, 0.79, 1.0), (0.42, 0.5, 0.5, 1.0), (0.12, 0.15, 0.2, 1.0),
               (1.0, 0.85, 0.55, 1.0), (0.1, 0.1, 0.11, 1.0), (0.5, 0.48, 0.44, 1.0)]

HALL_HALF = 10.0               # hall X half width
HALL_Y0, HALL_Y1 = 8.0, 28.0   # hall front (road side) and back
HALL_CY = 18.0
WALL_TOP = 15.0
DRUM_R = 7.8                   # circumradius of the 16-sided drum, and the dome's base radius
DRUM_Z0, DRUM_Z1 = 16.0, 24.0
DOME_RISE = 9.0
MIN_X, MIN_Y = 17.0, 3.0       # minaret axes, road-side corners beside the paved square
MIN_TOP = 52.6                 # pencil cap tip; about 2.2 x the drum top (24 m)
SEA_POST_Y = 28.5              # lamp posts, on the quay behind the seaward steps

GLASS_OFF = 0.04               # glass pane proud of the wall
FRAME_OFF = 0.26               # stone archivolt ring proud of the wall
RF = 0.22                      # archivolt width


def arch_loop(w, h, steps, grow=0.0, drop=0.0):
    """Round-headed opening in its own (u, v) plane: rectangle of height h, semicircular head of radius w/2 + grow,
    the bottom pushed down by drop. Same point count for the same steps, so inner and outer loops pair by index."""
    r = w / 2 + grow
    pts = [(-r, -drop), (r, -drop), (r, h)]
    for j in range(1, steps):
        a = math.pi * j / steps
        pts.append((r * math.cos(a), h + r * math.sin(a)))
    pts.append((-r, h))
    return pts


def centre(pts):
    return sum(pts, Vector((0.0, 0.0, 0.0))) / len(pts)


class Frame:
    """A vertical wall plane: origin (cx, cy) at height base, u along (tx, ty), offset along the outward normal (nx, ny)."""

    def __init__(self, cx, cy, tx, ty, nx, ny, base):
        self.cx, self.cy, self.tx, self.ty, self.nx, self.ny, self.base = cx, cy, tx, ty, nx, ny, base
        self.n3 = Vector((nx, ny, 0.0))
        self.t3 = Vector((tx, ty, 0.0))

    def at(self, u, v, off):
        return Vector((self.cx + self.tx * u + self.nx * off, self.cy + self.ty * u + self.ny * off, self.base + v))


class Part:
    """One bmesh with per-face material indices. detail 0 = LOD0, 1 = LOD1, 2 = LOD2."""

    def __init__(self, detail):
        self.bm = bmesh.new()
        self.detail = detail

    def poly(self, pts, mat, outward, smooth=False):
        verts = [self.bm.verts.new(tuple(p)) for p in pts]
        try:
            f = self.bm.faces.new(verts)
        except ValueError:
            return None
        f.material_index = mat
        f.smooth = smooth
        f.normal_update()
        if f.normal.dot(Vector(outward)) < 0.0:
            f.normal_flip()
        return f

    def box(self, x0, x1, y0, y1, z0, z1, mat):
        self.poly([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], mat, (0, 0, -1))
        self.poly([(x0, y0, z1), (x0, y1, z1), (x1, y1, z1), (x1, y0, z1)], mat, (0, 0, 1))
        self.poly([(x0, y0, z0), (x0, y0, z1), (x1, y0, z1), (x1, y0, z0)], mat, (0, -1, 0))
        self.poly([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], mat, (0, 1, 0))
        self.poly([(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)], mat, (-1, 0, 0))
        self.poly([(x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0)], mat, (1, 0, 0))

    def lbox(self, fr, u0, u1, v0, v1, o0, o1, mat):
        """Box in a wall frame: u along the wall, v up, offset o0..o1 out from the wall."""
        c = [fr.at(u0, v0, o0), fr.at(u1, v0, o0), fr.at(u1, v1, o0), fr.at(u0, v1, o0),
             fr.at(u0, v0, o1), fr.at(u1, v0, o1), fr.at(u1, v1, o1), fr.at(u0, v1, o1)]
        up = Vector((0.0, 0.0, 1.0))
        self.poly([c[0], c[1], c[2], c[3]], mat, -fr.n3)
        self.poly([c[4], c[5], c[6], c[7]], mat, fr.n3)
        self.poly([c[0], c[1], c[5], c[4]], mat, -up)
        self.poly([c[3], c[2], c[6], c[7]], mat, up)
        self.poly([c[0], c[3], c[7], c[4]], mat, -fr.t3)
        self.poly([c[1], c[2], c[6], c[5]], mat, fr.t3)

    def lathe(self, prof, segs, mat, cx=0.0, cy=0.0, a0=0.0, smooth=True):
        """Surface of revolution. prof is (r, z) listed like the outer wall of a solid: going up the outside and
        inward across the top, so the outward normal of each segment is (dz, -dr) in (r, z)."""
        rings = []
        for r, z in prof:
            rings.append([(cx + r * math.cos(a0 + 2 * math.pi * k / segs),
                           cy + r * math.sin(a0 + 2 * math.pi * k / segs), z) for k in range(segs)])
        for i in range(len(prof) - 1):
            (r0, z0), (r1, z1) = prof[i], prof[i + 1]
            dr, dz = r1 - r0, z1 - z0
            length = math.hypot(dr, dz) or 1.0
            nr, nz = dz / length, -dr / length
            for k in range(segs):
                k2 = (k + 1) % segs
                am = a0 + 2 * math.pi * (k + 0.5) / segs
                outward = (math.cos(am) * nr, math.sin(am) * nr, nz)
                a, b = rings[i][k], rings[i][k2]
                c, d = rings[i + 1][k2], rings[i + 1][k]
                if r0 == 0.0 and r1 == 0.0:
                    continue
                if r0 == 0.0:
                    pts = [a, c, d]
                elif r1 == 0.0:
                    pts = [a, b, c]
                else:
                    pts = [a, b, c, d]
                self.poly(pts, mat, outward, smooth)

    def window(self, fr, w, h, detail):
        """Round-headed window in a wall frame: glowing pane (GLASS) at GLASS_OFF, a raised stone archivolt ring at
        FRAME_OFF, reveals joining them, a sill. LOD0 adds the outer skirt to the wall and the mullions and transom."""
        steps = {0: 8, 1: 5}[detail]
        inner = arch_loop(w, h, steps)
        outer = arch_loop(w, h, steps, RF, RF)
        n = len(inner)
        axis = fr.at(0.0, 0.5 * h, 0.5 * (GLASS_OFF + FRAME_OFF))
        self.poly([fr.at(u, v, GLASS_OFF) for u, v in inner], GLASS, fr.n3)
        for i in range(n):
            j = (i + 1) % n
            oi, oj = fr.at(*outer[i], FRAME_OFF), fr.at(*outer[j], FRAME_OFF)
            ii, ij = fr.at(*inner[i], FRAME_OFF), fr.at(*inner[j], FRAME_OFF)
            self.poly([oi, oj, ij, ii], STONE, fr.n3)                       # archivolt ring
            gi, gj = fr.at(*inner[i], GLASS_OFF), fr.at(*inner[j], GLASS_OFF)
            rev = [ii, ij, gj, gi]
            self.poly(rev, STONE, axis - centre(rev))                       # reveal, faces into the opening
            if detail == 0:
                wi, wj = fr.at(*outer[i], 0.0), fr.at(*outer[j], 0.0)
                skirt = [oi, oj, wj, wi]
                self.poly(skirt, STONE, centre(skirt) - axis)               # outer edge of the frame, down to the wall
        self.lbox(fr, -(w / 2 + RF + 0.1), w / 2 + RF + 0.1, -RF - 0.16, -RF, 0.0, 0.34, STONE)  # sill
        if detail == 0:
            self.lbox(fr, -0.06, 0.06, 0.0, h, GLASS_OFF, GLASS_OFF + 0.09, STONE)                  # mullion
            self.lbox(fr, -w / 2, w / 2, 0.5 * h, 0.5 * h + 0.1, GLASS_OFF, GLASS_OFF + 0.09, STONE)  # transom


def dome_ribs(p, cx, cy, n_ribs, stations, rh=0.22, hw=0.13):
    """Raised ribs on the dome: each a short prism running meridian to crown, rh proud of the dome surface."""
    phis = [0.08 + (math.pi / 2 - 0.18) * i / (stations - 1) for i in range(stations)]
    for k in range(n_ribs):
        a = 2 * math.pi * k / n_ribs
        ca, sa = math.cos(a), math.sin(a)
        t = Vector((-sa, ca, 0.0))
        S, P, N = [], [], []
        for phi in phis:
            cp, sp = math.cos(phi), math.sin(phi)
            gr, gz = cp / DRUM_R, sp / DOME_RISE
            L = math.hypot(gr, gz)
            n = Vector((gr / L * ca, gr / L * sa, gz / L))
            s = Vector((cx + DRUM_R * cp * ca, cy + DRUM_R * cp * sa, DRUM_Z1 + DOME_RISE * sp))
            S.append(s)
            P.append(s + n * rh)
            N.append(n)
        for i in range(stations - 1):
            j = i + 1
            p.poly([P[i] - t * hw, P[i] + t * hw, P[j] + t * hw, P[j] - t * hw], DOME, (N[i] + N[j]))
            p.poly([S[i] + t * hw, P[i] + t * hw, P[j] + t * hw, S[j] + t * hw], DOME, t)
            p.poly([S[i] - t * hw, S[j] - t * hw, P[j] - t * hw, P[i] - t * hw], DOME, -t)


def shaft(p, mx, my, z0, z1, r, flutes, segs):
    """Upright shaft. flutes > 0: 2*flutes vertices alternating r and r - 0.09 (grooves); else a plain prism of segs."""
    n = 2 * flutes if flutes else segs
    depth = 0.09
    bot, top = [], []
    for k in range(n):
        rk = r - depth if (flutes and k % 2) else r
        a = 2 * math.pi * k / n
        bot.append(Vector((mx + rk * math.cos(a), my + rk * math.sin(a), z0)))
        top.append(Vector((mx + rk * math.cos(a), my + rk * math.sin(a), z1)))
    for k in range(n):
        k2 = (k + 1) % n
        mid = (bot[k] + bot[k2]) * 0.5
        out = Vector((mid.x - mx, mid.y - my, 0.0))
        p.poly([bot[k], bot[k2], top[k2], top[k]], STONE, out, smooth=True)


def build_hall(p):
    d = p.detail
    p.box(-10.5, 10.5, HALL_Y0 - 0.5, HALL_Y1 + 0.5, 0.15, 1.5, STONE)          # plinth, 0.5 m proud
    p.box(-HALL_HALF, HALL_HALF, HALL_Y0, HALL_Y1, 1.5, WALL_TOP, STONE)        # walls
    # three-step cornice, the outermost 0.6 m proud, then the roof slab
    p.box(-10.25, 10.25, HALL_Y0 - 0.25, HALL_Y1 + 0.25, 15.0, 15.2, STONE)
    p.box(-10.45, 10.45, HALL_Y0 - 0.45, HALL_Y1 + 0.45, 15.2, 15.4, STONE)
    p.box(-10.6, 10.6, HALL_Y0 - 0.6, HALL_Y1 + 0.6, 15.4, 15.65, STONE)
    p.box(-9.8, 9.8, HALL_Y0 + 0.2, HALL_Y1 - 0.2, 15.65, 16.0, STONE)
    # string course between the two window tiers, 0.35 m proud, all round
    p.box(-10.35, 10.35, HALL_Y0 - 0.35, HALL_Y0 + 0.02, 9.15, 9.45, STONE)
    p.box(-10.35, 10.35, HALL_Y1 - 0.02, HALL_Y1 + 0.35, 9.15, 9.45, STONE)
    p.box(-10.35, -9.98, HALL_Y0 + 0.02, HALL_Y1 - 0.02, 9.15, 9.45, STONE)
    p.box(9.98, 10.35, HALL_Y0 + 0.02, HALL_Y1 - 0.02, 9.15, 9.45, STONE)
    if d == 2:
        # silhouette only: the porch block and its stepped top
        p.box(-4.2, 4.2, 4.6, HALL_Y0 + 0.02, 0.15, 6.6, STONE)
        p.box(-3.4, 3.4, 4.4, HALL_Y0 + 0.1, 6.6, 7.5, STONE)
        return
    # pilasters between the bays, 0.45 m proud, with a base and a capital at LOD0
    for x in (-8.3, -3.0, 3.0, 8.3):
        p.box(x - 0.35, x + 0.35, HALL_Y0 - 0.45, HALL_Y0 + 0.02, 1.5, WALL_TOP, STONE)
        p.box(x - 0.35, x + 0.35, HALL_Y1 - 0.02, HALL_Y1 + 0.45, 1.5, WALL_TOP, STONE)
        if d == 0:
            p.box(x - 0.5, x + 0.5, HALL_Y0 - 0.6, HALL_Y0 + 0.02, 1.5, 2.0, STONE)
            p.box(x - 0.5, x + 0.5, HALL_Y1 - 0.02, HALL_Y1 + 0.6, 1.5, 2.0, STONE)
            p.box(x - 0.5, x + 0.5, HALL_Y0 - 0.6, HALL_Y0 + 0.02, 14.2, 15.0, STONE)
            p.box(x - 0.5, x + 0.5, HALL_Y1 - 0.02, HALL_Y1 + 0.6, 14.2, 15.0, STONE)
    for y in (9.0, 14.5, 21.5):
        p.box(-HALL_HALF - 0.45, -HALL_HALF + 0.02, y - 0.35, y + 0.35, 1.5, WALL_TOP, STONE)
        p.box(HALL_HALF - 0.02, HALL_HALF + 0.45, y - 0.35, y + 0.35, 1.5, WALL_TOP, STONE)
        if d == 0:
            p.box(-HALL_HALF - 0.6, -HALL_HALF + 0.02, y - 0.5, y + 0.5, 1.5, 2.0, STONE)
            p.box(HALL_HALF - 0.02, HALL_HALF + 0.6, y - 0.5, y + 0.5, 1.5, 2.0, STONE)
            p.box(-HALL_HALF - 0.6, -HALL_HALF + 0.02, y - 0.5, y + 0.5, 14.2, 15.0, STONE)
            p.box(HALL_HALF - 0.02, HALL_HALF + 0.6, y - 0.5, y + 0.5, 14.2, 15.0, STONE)
    # two window tiers: the lower tier is taller, both are round-headed
    for base, h in ((3.0, 4.6), (9.8, 3.0)):
        front_xs = [-6.0, 6.0] if base < 5 else [-6.0, 0.0, 6.0]   # road side: the centre lower bay is the porch
        for x in front_xs:
            p.window(Frame(x, HALL_Y0, 1.0, 0.0, 0.0, -1.0, base), 2.2, h, d)
        for x in (-6.0, 0.0, 6.0):
            p.window(Frame(x, HALL_Y1, 1.0, 0.0, 0.0, 1.0, base), 2.2, h, d)
        for y in (11.0, 18.0, 25.0):
            p.window(Frame(-HALL_HALF, y, 0.0, 1.0, -1.0, 0.0, base), 2.2, h, d)
            p.window(Frame(HALL_HALF, y, 0.0, 1.0, 1.0, 0.0, base), 2.2, h, d)
    # entrance porch on the road side: three arches of glass, stepped top
    p.box(-4.2, 4.2, 4.6, HALL_Y0 + 0.02, 0.15, 6.6, STONE)
    p.box(-4.6, 4.6, 4.2, HALL_Y0 + 0.1, 6.6, 7.0, STONE)
    p.box(-3.4, 3.4, 4.4, HALL_Y0 + 0.1, 7.0, 7.5, STONE)
    p.box(-2.2, 2.2, 4.7, HALL_Y0 + 0.1, 7.5, 8.0, STONE)
    for x in (-2.6, 0.0, 2.6):
        p.window(Frame(x, 4.6, 1.0, 0.0, 0.0, -1.0, 1.2), 1.9, 3.2, d)
    # balustrade on the roof edge and handrails
    if d == 0:
        for x in [-9.0 + 1.0 * i for i in range(19)]:
            p.box(x - 0.11, x + 0.11, HALL_Y0 + 0.5, HALL_Y0 + 0.72, 16.0, 16.9, STONE)
            p.box(x - 0.11, x + 0.11, HALL_Y1 - 0.72, HALL_Y1 - 0.5, 16.0, 16.9, STONE)
        for y in [9.0 + 1.0 * i for i in range(19)]:
            p.box(-HALL_HALF + 0.5, -HALL_HALF + 0.72, y - 0.11, y + 0.11, 16.0, 16.9, STONE)
            p.box(HALL_HALF - 0.72, HALL_HALF - 0.5, y - 0.11, y + 0.11, 16.0, 16.9, STONE)
    p.box(-9.6, 9.6, HALL_Y0 + 0.4, HALL_Y0 + 0.6, 16.9, 17.1, STONE)
    p.box(-9.6, 9.6, HALL_Y1 - 0.6, HALL_Y1 - 0.4, 16.9, 17.1, STONE)
    p.box(-9.8, -9.4, HALL_Y0 + 0.4, HALL_Y1 - 0.4, 16.9, 17.1, STONE)
    p.box(9.4, 9.8, HALL_Y0 + 0.4, HALL_Y1 - 0.4, 16.9, 17.1, STONE)


def build_drum_and_dome(p):
    d = p.detail
    seg_drum = {0: 16, 1: 16, 2: 8}[d]
    dome_segs = {0: 48, 1: 24, 2: 10}[d]
    dome_rings = {0: 12, 1: 6, 2: 3}[d]
    cy = HALL_CY
    p.lathe([(DRUM_R, DRUM_Z0), (DRUM_R, DRUM_Z1)], seg_drum, STONE, 0.0, cy, smooth=False)
    if d < 2:  # cornice band under the dome
        p.lathe([(7.95, DRUM_Z1 - 0.4), (7.95, DRUM_Z1 + 0.3), (7.45, DRUM_Z1 + 0.3), (7.45, DRUM_Z1 - 0.4)],
                seg_drum, STONE, 0.0, cy, smooth=False)
    dome = []
    for i in range(dome_rings + 1):
        phi = (math.pi / 2) * i / dome_rings
        dome.append((DRUM_R * math.cos(phi), DRUM_Z1 + DOME_RISE * math.sin(phi)))
    p.lathe(dome, dome_segs, DOME, 0.0, cy)
    if d < 2:
        dome_ribs(p, 0.0, cy, 16 if d == 0 else 8, 9 if d == 0 else 4)
    top = DRUM_Z1 + DOME_RISE
    p.lathe([(0.30, top - 0.4), (0.30, top + 0.2), (0.18, top + 0.8), (0.18, top + 3.0), (0.0, top + 3.6)],
            8, IRON, 0.0, cy)
    if d < 2:
        ball = [(0.35 * math.sin(math.pi * i / 8), top + 3.9 - 0.35 * math.cos(math.pi * i / 8)) for i in range(9)]
        p.lathe(ball, 12, LAMP, 0.0, cy)
        # windowed drum: one round-headed window per facet of the 16-sided drum
        apo = DRUM_R * math.cos(math.pi / 16)
        for k in range(seg_drum):
            a = 2 * math.pi * (k + 0.5) / seg_drum
            ca, sa = math.cos(a), math.sin(a)
            p.window(Frame(apo * ca, cy + apo * sa, -sa, ca, ca, sa, 17.2), 1.3, 2.0, d)


def build_turrets(p):
    d = p.detail
    seg = {0: 8, 1: 8, 2: 6}[d]
    for x in (-10.8, 10.8):
        for y in (HALL_Y0 - 0.8, HALL_Y1 + 0.8):
            p.box(x - 1.6, x + 1.6, y - 1.6, y + 1.6, 0.15, 22.0, STONE)
            p.box(x - 1.85, x + 1.85, y - 1.85, y + 1.85, 21.6, 22.2, STONE)
            dome = [(2.1, 22.2), (2.0, 23.6), (1.5, 25.2), (0.8, 26.9), (0.0, 28.2)]
            if d == 2:
                dome = [(2.1, 22.2), (1.4, 25.0), (0.0, 28.2)]
            p.lathe(dome, seg, DOME, x, y, math.pi / 8)
            if d == 0:
                for nx, ny in ((0.0, -1.0), (0.0, 1.0), (-1.0, 0.0), (1.0, 0.0)):
                    p.window(Frame(x + nx * 1.6, y + ny * 1.6, -ny, nx, nx, ny, 17.0), 1.0, 2.2, d)


def build_minaret(p, mx, my):
    d = p.detail
    seg = {0: 16, 1: 12, 2: 6}[d]
    flutes = {0: 16, 1: 8, 2: 0}[d]
    if d == 2:  # silhouette: plain plinth, shaft and cap
        p.lathe([(1.95, 0.15), (1.95, 3.0), (1.0, 3.3)], seg, STONE, mx, my)
        shaft(p, mx, my, 3.3, 46.2, 1.1, 0, seg)
        p.lathe([(1.15, 46.2), (0.0, MIN_TOP)], seg, DOME, mx, my)
        return
    p.lathe([(1.95, 0.15), (1.95, 1.1), (1.7, 1.2), (1.7, 2.9), (2.0, 3.0), (2.0, 3.3), (1.0, 3.3)], seg, STONE, mx, my)
    shaft(p, mx, my, 3.3, 46.2, 1.1, flutes, seg)
    p.lathe([(1.3, 46.0), (1.3, 46.4), (1.15, 46.5)], seg, STONE, mx, my)
    p.lathe([(1.15, 46.5), (0.0, MIN_TOP)], seg, DOME, mx, my)  # pencil lead cap
    p.lathe([(0.14, MIN_TOP - 0.1), (0.14, MIN_TOP + 1.0), (0.0, MIN_TOP + 1.6)], 6, IRON, mx, my)
    if d < 2:
        # one balcony: deck, rail ring, and a ring of lamps on the rail
        p.lathe([(0.9, 33.4), (1.8, 33.4), (1.8, 33.8), (0.9, 33.8)], seg, STONE, mx, my)
        p.lathe([(1.75, 34.9), (1.85, 34.9), (1.85, 35.05), (1.75, 35.05)], seg, STONE, mx, my)
        for k in range(12):
            a = 2 * math.pi * k / 12
            x, y = mx + 1.8 * math.cos(a), my + 1.8 * math.sin(a)
            p.box(x - 0.08, x + 0.08, y - 0.08, y + 0.08, 35.05, 35.3, LAMP)
    if d == 0:
        for k in range(8):  # bracketed underside of the balcony
            a = 2 * math.pi * k / 8
            x, y = mx + 1.4 * math.cos(a), my + 1.4 * math.sin(a)
            p.box(x - 0.12, x + 0.12, y - 0.12, y + 0.12, 32.7, 33.4, STONE)
        for k in range(16):  # balusters of the rail
            a = 2 * math.pi * k / 16
            x, y = mx + 1.8 * math.cos(a), my + 1.8 * math.sin(a)
            p.box(x - 0.05, x + 0.05, y - 0.05, y + 0.05, 33.8, 34.9, STONE)


def build_quay(p):
    d = p.detail
    # quay slab to the sea edge at 29.6, then two seaward steps down to the water (Z -1.2)
    p.box(-40.0, 40.0, 0.0, 29.6, -1.6, 0.15, STONE)
    p.box(-40.0, 40.0, 29.6, 30.8, -1.6, -0.35, STONE)
    p.box(-40.0, 40.0, 30.8, 32.0, -1.6, -0.85, STONE)
    p.box(-14.0, 14.0, 0.0, 8.0, 0.15, 0.17, PAVE)
    if d == 2:
        return
    # balustrade on both sides of the paved square, repeat units of balusters
    step = 0.5 if d == 0 else 1.0
    for x in (-14.0, 14.0):
        y = 0.1
        while y < 8.0:
            p.box(x - 0.06, x + 0.06, y - 0.06, y + 0.06, 0.17, 1.0, STONE)
            y += step
        p.box(x - 0.1, x + 0.1, 0.0, 8.0, 1.0, 1.1, STONE)
    # six lamp posts along the seaside
    for x in (-34.0, -24.0, -14.0, 14.0, 24.0, 34.0):
        p.lathe([(0.12, 0.15), (0.09, 0.5), (0.09, 6.4), (0.2, 6.6), (0.2, 6.75)], 8, IRON, x, SEA_POST_Y)
        p.box(x - 0.3, x + 0.3, SEA_POST_Y - 0.3, SEA_POST_Y + 0.3, 6.75, 7.2, LAMP)


def make_part(detail):
    p = Part(detail)
    build_quay(p)
    build_hall(p)
    build_drum_and_dome(p)
    build_turrets(p)
    build_minaret(p, -MIN_X, MIN_Y)
    build_minaret(p, MIN_X, MIN_Y)
    return p


def triangulate_count(bm):
    faces = [f for f in bm.faces]
    bmesh.ops.triangulate(bm, faces=faces)
    return len(bm.faces)


def export_glb(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
        export_image_format="NONE", export_materials="EXPORT", export_cameras=False, export_lights=False,
        export_extras=False)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = []
    for name, col in zip(MATS, MAT_COLOURS):
        m = bpy.data.materials.new(name)
        m.diffuse_color = col
        mats.append(m)
    os.makedirs(OUT_DIR, exist_ok=True)
    report = {"generator": "assets_src/world/kit_landmarks/build_landmark.py", "lods": {}}
    for detail in (0, 1, 2):
        p = make_part(detail)
        tris = triangulate_count(p.bm)
        per_mat = {}
        for f in p.bm.faces:
            per_mat[MATS[f.material_index]] = per_mat.get(MATS[f.material_index], 0) + 1
        mesh = bpy.data.meshes.new("landmark_mosque_lod%d" % detail)
        p.bm.normal_update()
        p.bm.to_mesh(mesh)
        p.bm.free()
        for m in mats:
            mesh.materials.append(m)
        obj = bpy.data.objects.new("landmark_mosque_lod%d" % detail, mesh)
        bpy.context.scene.collection.objects.link(obj)
        path = os.path.join(OUT_DIR, "landmark_mosque_lod%d.glb" % detail)
        ao_stats = None
        if detail < 2:
            ao_stats = ao.bake_ao([obj], cell_m=AO_CELL[detail])
            ao.export_glb_ao(path, [obj])
        else:
            export_glb(obj, path)
        mesh.calc_loop_triangles()
        report["lods"][str(detail)] = {"tris": tris, "tris_after_ao": len(mesh.loop_triangles), "ao": ao_stats,
                                      "materials_used": sorted(per_mat.keys()), "tris_per_material": per_mat,
                                      "file": os.path.relpath(path, REPO).replace("\\", "/")}
        print("[landmark] lod%d tris=%d materials=%s" % (detail, tris, sorted(per_mat.keys())))
        bpy.data.objects.remove(obj)
        bpy.data.meshes.remove(mesh)
    with open(os.path.join(OUT_DIR, "landmark_mosque_report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)


if __name__ == "__main__":
    main()
