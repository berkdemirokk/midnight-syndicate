"""Waterfront mosque kit (Blender 5.3, deterministic, procedural only, no downloads).

Run:  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup --python build_landmark.py

Original design, not a replica of any real building: a square prayer hall with tall arched windows, a portal, pilasters,
a balustrade, one octagonal drum and dome with a finial, two back corner turrets with pencil caps, two slim minarets on
the road-side corners with two balconies each, a marble quay over the water, a paved square, an iron railing and lamps.

Frame (Blender metres, Z up; the glTF export turns Z into Godot Y, Blender Y into -Godot Z):
  origin  the quay's landward edge on the seaside railing line, ground level
  +X      forward along the road (race direction)
  -Y      seaward (away from the road). Blender +Y runs toward the sea, so the road is at Blender Y < 0.
  Godot: local +Z points landward (toward the road); the hall front faces the road.
  Quay top at Z 0.15 (the road kerbs sit at 0.15), water at Z -1.2.

Output (game/assets/world/kits/landmarks/):
  landmark_mosque_lod0.glb  <= 22 000 tris, 6 surfaces, one per material name
  landmark_mosque_lod1.glb  <= 6 000 tris
  landmark_mosque_lod2.glb  <= 600 tris
  landmark_mosque_report.json  triangle counts per LOD and material

Materials (names are read by game/world/landmarks/landmarks.gd):
  M_Stone  marble and limestone          M_Dome  lead dome, pencil caps
  M_Glass  windows and portal (glow at night)   M_Lamp  lamp heads, minaret ring lights
  M_Iron   railing, lamp posts, finial   M_Paving  wet paved square
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_DIR = os.path.join(REPO, "game", "assets", "world", "kits", "landmarks")

MATS = ["M_Stone", "M_Dome", "M_Glass", "M_Lamp", "M_Iron", "M_Paving"]
STONE, DOME, GLASS, LAMP, IRON, PAVE = range(6)
MAT_COLOURS = [(0.88, 0.85, 0.79, 1.0), (0.42, 0.5, 0.5, 1.0), (0.12, 0.15, 0.2, 1.0),
               (1.0, 0.85, 0.55, 1.0), (0.1, 0.1, 0.11, 1.0), (0.5, 0.48, 0.44, 1.0)]

HALL_HALF = 10.0          # hall X half width
HALL_Y0, HALL_Y1 = 8.0, 28.0   # hall front (road side) and back
HALL_CY = 18.0
WALL_TOP = 15.0
DRUM_R = 7.794            # circumradius of an 8-sided drum whose faces sit 7.2 m from the axis
DRUM_APOTHEM = 7.2
DRUM_Z0, DRUM_Z1 = 16.0, 24.0
DOME_RISE = 9.0
MINARET_X, MINARET_Y = 12.8, 5.0


def arch_pts(w, h, steps=6):
    """Arched opening in its own (u, v) plane: rectangle of height h, semicircular head of radius w/2."""
    pts = [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, h)]
    for j in range(1, steps):
        a = math.pi * j / steps
        pts.append((w / 2 * math.cos(a), h + w / 2 * math.sin(a)))
    pts.append((-w / 2, h))
    return pts


class Part:
    """One bmesh with per-face material indices. detail 0 = LOD0, 1 = LOD1, 2 = LOD2."""

    def __init__(self, detail):
        self.bm = bmesh.new()
        self.detail = detail

    def poly(self, pts, mat, outward):
        verts = [self.bm.verts.new(tuple(p)) for p in pts]
        try:
            f = self.bm.faces.new(verts)
        except ValueError:
            return None
        f.material_index = mat
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

    def lathe(self, prof, segs, mat, cx=0.0, cy=0.0, a0=0.0):
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
                self.poly(pts, mat, outward)

    def wall_arch(self, cx, cy, tx, ty, nx, ny, w, h, base, mat, off):
        """Arch in a vertical plane through (cx, cy): u along the tangent (tx, ty), off along the outward normal."""
        pts = []
        for u, v in arch_pts(w, h):
            pts.append((cx + tx * u + nx * off, cy + ty * u + ny * off, base + v))
        return self.poly(pts, mat, (nx, ny, 0.0))

    def window(self, cx, cy, tx, ty, nx, ny, w, h, base, frame=True):
        if frame and self.detail == 0:
            self.wall_arch(cx, cy, tx, ty, nx, ny, w + 0.5, h + 0.25, base - 0.15, STONE, 0.10)
        self.wall_arch(cx, cy, tx, ty, nx, ny, w, h, base, GLASS, 0.13)


def build_hall(p):
    d = p.detail
    p.box(-11.0, 11.0, HALL_Y0 - 1.0, HALL_Y1 + 1.0, 0.15, 1.5, STONE)            # plinth
    p.box(-HALL_HALF, HALL_HALF, HALL_Y0, HALL_Y1, 1.5, WALL_TOP, STONE)          # walls
    p.box(-10.8, 10.8, HALL_Y0 - 0.2, HALL_Y1 + 0.2, WALL_TOP, WALL_TOP + 0.6, STONE)  # cornice
    p.box(-9.8, 9.8, HALL_Y0 + 0.2, HALL_Y1 - 0.2, WALL_TOP + 0.6, 16.0, STONE)   # roof slab
    if d == 2:
        return
    # pilasters, proud of the walls
    for x in (-8.3, -3.0, 3.0, 8.3):
        p.box(x - 0.3, x + 0.3, HALL_Y0 - 0.25, HALL_Y0 + 0.05, 1.5, WALL_TOP, STONE)
        p.box(x - 0.3, x + 0.3, HALL_Y1 - 0.05, HALL_Y1 + 0.25, 1.5, WALL_TOP, STONE)
    for y in (9.0, 14.5, 21.5):
        p.box(-HALL_HALF - 0.25, -HALL_HALF + 0.05, y - 0.3, y + 0.3, 1.5, WALL_TOP, STONE)
        p.box(HALL_HALF - 0.05, HALL_HALF + 0.25, y - 0.3, y + 0.3, 1.5, WALL_TOP, STONE)
    # windows: lower row base 3.0, upper row base 9.2, width 2.2, rectangle 3.2 under a semicircle
    w, h = 2.2, 3.2
    for base in (3.0, 9.2):
        # road side (front, normal -Y): the centre lower window is the portal; back (normal +Y) has all three
        front_xs = [-6.0, 6.0] if base < 5 else [-6.0, 0.0, 6.0]
        for x in front_xs:
            p.window(x, HALL_Y0, 1.0, 0.0, 0.0, -1.0, w, h, base)
        for x in (-6.0, 0.0, 6.0):
            p.window(x, HALL_Y1, 1.0, 0.0, 0.0, 1.0, w, h, base)
        for y in (11.0, 18.0, 25.0):  # sides (normal -X, +X)
            p.window(-HALL_HALF, y, 0.0, 1.0, -1.0, 0.0, w, h, base)
            p.window(HALL_HALF, y, 0.0, 1.0, 1.0, 0.0, w, h, base)
    # portal on the road side: taller arch, warm inside at night, with a porch of two columns and a stepped pediment
    p.wall_arch(0.0, HALL_Y0, 1.0, 0.0, 0.0, -1.0, 4.4, 5.0, 1.35, STONE, 0.10)
    p.wall_arch(0.0, HALL_Y0, 1.0, 0.0, 0.0, -1.0, 3.4, 4.6, 1.5, GLASS, 0.13)
    if d < 2:
        for x in (-2.9, 2.9):
            p.lathe([(0.42, 1.5), (0.36, 1.9), (0.3, 2.0), (0.3, 7.9), (0.5, 8.1), (0.5, 8.4), (0.0, 8.4)], 8,
                    STONE, x, HALL_Y0 - 1.2)
        p.box(-3.4, 3.4, HALL_Y0 - 1.5, HALL_Y0 - 0.1, 8.4, 9.0, STONE)
        p.box(-2.4, 2.4, HALL_Y0 - 1.5, HALL_Y0 - 0.1, 9.0, 9.5, STONE)
    # balustrade on the roof edge
    if d == 0:
        for x in [-9.0 + 1.0 * i for i in range(19)]:
            p.box(x - 0.11, x + 0.11, HALL_Y0 + 0.5, HALL_Y0 + 0.72, 16.0, 16.9, STONE)
            p.box(x - 0.11, x + 0.11, HALL_Y1 - 0.72, HALL_Y1 - 0.5, 16.0, 16.9, STONE)
        for y in [9.0 + 1.0 * i for i in range(19)]:
            p.box(-HALL_HALF + 0.5, -HALL_HALF + 0.72, y - 0.11, y + 0.11, 16.0, 16.9, STONE)
            p.box(HALL_HALF - 0.72, HALL_HALF - 0.5, y - 0.11, y + 0.11, 16.0, 16.9, STONE)
    # handrails on the four sides of the roof
    p.box(-9.6, 9.6, HALL_Y0 + 0.4, HALL_Y0 + 0.6, 16.9, 17.1, STONE)
    p.box(-9.6, 9.6, HALL_Y1 - 0.6, HALL_Y1 - 0.4, 16.9, 17.1, STONE)
    p.box(-9.8, -9.4, HALL_Y0 + 0.4, HALL_Y1 - 0.4, 16.9, 17.1, STONE)
    p.box(9.4, 9.8, HALL_Y0 + 0.4, HALL_Y1 - 0.4, 16.9, 17.1, STONE)


def build_drum_and_dome(p):
    segs_dome = {0: 48, 1: 24, 2: 10}[p.detail]
    rings_dome = {0: 12, 1: 6, 2: 3}[p.detail]
    drum_segs = 8
    p.lathe([(DRUM_R, DRUM_Z0), (DRUM_R, DRUM_Z1)], drum_segs, STONE, 0.0, HALL_CY)
    if p.detail < 2:  # cornice band under the dome
        p.lathe([(7.9, DRUM_Z1 - 0.4), (7.9, DRUM_Z1 + 0.3), (7.4, DRUM_Z1 + 0.3), (7.4, DRUM_Z1 - 0.4)], drum_segs,
                STONE, 0.0, HALL_CY)
    dome = []
    for i in range(rings_dome + 1):
        phi = (math.pi / 2) * i / rings_dome
        dome.append((DRUM_R * math.cos(phi), DRUM_Z1 + DOME_RISE * math.sin(phi)))
    p.lathe(dome, segs_dome, DOME, 0.0, HALL_CY)
    top = DRUM_Z1 + DOME_RISE
    p.lathe([(0.30, top - 0.4), (0.30, top + 0.2), (0.18, top + 0.8), (0.18, top + 3.0), (0.0, top + 3.6)],
            8, IRON, 0.0, HALL_CY)
    ball = []
    for i in range(9):
        phi = math.pi * i / 8
        ball.append((0.35 * math.sin(phi), top + 3.9 - 0.35 * math.cos(phi)))
    if p.detail < 2:
        p.lathe(ball, 12, LAMP, 0.0, HALL_CY)
    if p.detail == 0:  # windows on the drum, one per octagon face
        for k in range(drum_segs):
            phi = (k + 0.5) * math.pi / 4
            nx, ny = math.cos(phi), math.sin(phi)
            tx, ty = -math.sin(phi), math.cos(phi)
            cx, cy = DRUM_APOTHEM * nx, HALL_CY + DRUM_APOTHEM * ny
            p.window(cx, cy, tx, ty, nx, ny, 1.4, 2.0, 17.2)
    elif p.detail == 1:
        for k in range(drum_segs):
            phi = (k + 0.5) * math.pi / 4
            nx, ny = math.cos(phi), math.sin(phi)
            tx, ty = -math.sin(phi), math.cos(phi)
            p.window(DRUM_APOTHEM * nx, HALL_CY + DRUM_APOTHEM * ny, tx, ty, nx, ny, 1.4, 2.0, 17.2, frame=False)


def build_turrets(p):
    cap_segs = {0: 8, 1: 4, 2: 4}[p.detail]
    for x in (-10.8, 10.8):
        y = HALL_Y1 + 0.8
        p.box(x - 1.6, x + 1.6, y - 1.6, y + 1.6, 0.15, 22.0, STONE)
        p.lathe([(2.26, 22.0), (0.0, 28.0)], cap_segs, DOME, x, y, math.pi / 4)


def build_minaret(p, mx, my):
    seg = {0: 16, 1: 10, 2: 6}[p.detail]
    prof = [(2.3, 0.15), (2.3, 3.0), (1.85, 3.25), (1.6, 3.7), (1.45, 4.2), (1.4, 21.0)]
    if p.detail < 2:
        prof += [(2.2, 21.0), (2.2, 21.4), (1.4, 21.4), (1.4, 31.0), (2.2, 31.0), (2.2, 31.4), (1.4, 31.4)]
    prof += [(1.4, 38.0), (1.9, 38.0), (1.9, 38.4), (1.2, 38.4)]
    p.lathe(prof, seg, STONE, mx, my)
    p.lathe([(1.2, 38.4), (0.0, 47.0)], seg, DOME, mx, my)  # pencil cap
    if p.detail < 2:
        for z in (21.4, 31.4):
            for k in range(12):
                a = 2 * math.pi * k / 12
                x = mx + 2.05 * math.cos(a)
                y = my + 2.05 * math.sin(a)
                p.box(x - 0.08, x + 0.08, y - 0.08, y + 0.08, z, z + 0.22, LAMP)


def build_quay(p):
    p.box(-40.0, 40.0, 0.0, 32.0, -1.6, 0.15, STONE)
    p.box(-14.0, 14.0, 0.0, 8.0, 0.15, 0.17, PAVE)
    if p.detail == 2:
        return
    step = 2.5 if p.detail == 0 else 5.0
    x = -40.0
    while x <= 40.0 + 1e-6:
        p.box(x - 0.05, x + 0.05, 31.45, 31.55, 0.15, 1.1, IRON)
        x += step
    p.box(-40.0, 40.0, 31.45, 31.55, 1.05, 1.15, IRON)
    for x in (-24.0, -8.0, 8.0, 24.0):
        p.lathe([(0.12, 0.15), (0.09, 0.5), (0.09, 6.4), (0.2, 6.6), (0.2, 6.75)], 8, IRON, x, 1.0)
        if p.detail < 2:
            p.box(x - 0.3, x + 0.3, 1.0 - 0.3, 1.0 + 0.3, 6.75, 7.2, LAMP)


def make_part(detail):
    p = Part(detail)
    build_quay(p)
    build_hall(p)
    build_drum_and_dome(p)
    build_turrets(p)
    build_minaret(p, -MINARET_X, MINARET_Y)
    build_minaret(p, MINARET_X, MINARET_Y)
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
        export_glb(obj, path)
        report["lods"][str(detail)] = {"tris": tris, "materials_used": sorted(per_mat.keys()), "tris_per_material": per_mat,
                                      "file": os.path.relpath(path, REPO).replace("\\", "/")}
        print("[landmark] lod%d tris=%d materials=%s" % (detail, tris, sorted(per_mat.keys())))
        bpy.data.objects.remove(obj)
        bpy.data.meshes.remove(mesh)
    with open(os.path.join(OUT_DIR, "landmark_mosque_report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)


if __name__ == "__main__":
    main()
