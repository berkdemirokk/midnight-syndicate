"""Event kit geometry (Blender 5.3, deterministic, procedural only, no downloads).

Run:  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup --python build_event.py
Needs gen_event_textures.py to have written game/assets/world/kits/event/*.png first.

Blender metres, Z up. glTF export maps Blender (x, y, z) to Godot (x, z, -y), so the road-facing side of every
piece (Blender -Y) lands on Godot +Z, the same side the placement code aims with its basis Z.

Pieces (one GLB each, materials are set in Godot by event_dressing.gd):
  event_barrier_0.glb, _1, _2  4 m concrete jersey barrier, 0.8 m high. Road face carries one banner row of
                               banner_atlas.png (rows 0, 1, 2); the rest of the barrier uses row 3 (concrete).
  event_flag.glb               surface 0: pole 6 m, 8 sides. surface 1: flag 1.2 x 0.8 m (3:2), 12 x 4 grid,
                               UV.x = 0 at the pole (hoist) and 1 at the fly, pinned for flag_wave.gdshader.
  event_awning.glb             4 m x 2.2 m striped canopy at 2.35 to 2.6 m on two posts. UVs into awning_atlas.png:
                               TL canopy top, TR underside (glows through awning_glow.png), BL frame.
  event_cafe_set.glb           one table and two chairs, 1.8 m wide, wood (BR quadrant) and frame (BL).
Atlas UV rects: image top is v = 1 (Blender UV convention, exported flipped as glTF expects).
"""
import math
import os

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "game", "assets", "world", "kits", "event")

# (u0, v0, u1, v1) regions of awning_atlas.png
RECT_TL = (0.0, 0.5, 0.5, 1.0)  # stripes, canopy top
RECT_TR = (0.5, 0.5, 1.0, 1.0)  # warm underside
RECT_BL = (0.0, 0.0, 0.5, 0.5)  # dark frame
RECT_BR = (0.5, 0.0, 1.0, 0.5)  # wood
# banner_atlas.png rows, 4 rows of 0.25 from the top: row r spans v in [1 - (r + 1) / 4, 1 - r / 4]
RECT_CONCRETE = (0.0, 0.0, 1.0, 0.25)


def banner_rect(row):
    return (0.0, 1.0 - (row + 1) / 4.0, 1.0, 1.0 - row / 4.0)


def uv_at(rect, s, t):
    return (rect[0] + (rect[2] - rect[0]) * s, rect[1] + (rect[3] - rect[1]) * t)


class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def poly(self, pts, uvs):
        verts = [self.bm.verts.new(p) for p in pts]
        try:
            face = self.bm.faces.new(verts)
        except ValueError:  # duplicate or degenerate face: skip it
            return
        for loop, uv in zip(face.loops, uvs):
            loop[self.uv].uv = uv

    def fan(self, pts, uvs):
        for i in range(1, len(pts) - 1):
            self.poly([pts[0], pts[i], pts[i + 1]], [uvs[0], uvs[i], uvs[i + 1]])

    def quad_rect(self, a, b, c, d, rect):
        """Quad a b c d (in order) with the whole UV rect mapped across it."""
        self.poly([a, b, c, d], [uv_at(rect, 0, 0), uv_at(rect, 1, 0), uv_at(rect, 1, 1), uv_at(rect, 0, 1)])

    def box(self, lo, hi, rect):
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        p = {
            "000": (x0, y0, z0), "100": (x1, y0, z0), "110": (x1, y1, z0), "010": (x0, y1, z0),
            "001": (x0, y0, z1), "101": (x1, y0, z1), "111": (x1, y1, z1), "011": (x0, y1, z1),
        }
        self.quad_rect(p["000"], p["010"], p["110"], p["100"], rect)  # bottom
        self.quad_rect(p["001"], p["101"], p["111"], p["011"], rect)  # top
        self.quad_rect(p["000"], p["100"], p["101"], p["001"], rect)  # front (-Y)
        self.quad_rect(p["010"], p["011"], p["111"], p["110"], rect)  # back (+Y)
        self.quad_rect(p["000"], p["001"], p["011"], p["010"], rect)  # left (-X)
        self.quad_rect(p["100"], p["110"], p["111"], p["101"], rect)  # right (+X)

    def cylinder(self, cx, cy, z0, z1, r, n, rect):
        ring0 = [(cx + r * math.cos(k * 2 * math.pi / n), cy + r * math.sin(k * 2 * math.pi / n)) for k in range(n)]
        for k in range(n):
            a, b = ring0[k], ring0[(k + 1) % n]
            s0, s1 = k / n, (k + 1) / n
            self.poly([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)],
                      [uv_at(rect, s0, 0), uv_at(rect, s1, 0), uv_at(rect, s1, 1), uv_at(rect, s0, 1)])
        top = [(x, y, z1) for x, y in ring0]
        bot = [(x, y, z0) for x, y in ring0]
        uvs = [uv_at(rect, 0.5 + 0.5 * math.cos(k * 2 * math.pi / n), 0.5 + 0.5 * math.sin(k * 2 * math.pi / n))
               for k in range(n)]
        self.fan(top, uvs)
        self.fan(bot[::-1], uvs[::-1])

    def finish(self, name):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def barrier(row):
    """Jersey barrier, 4 m long along X, road face at -Y. Profile (y, z): base -0.30 at 0, top -0.12 at 0.8."""
    b = Builder()
    L = 2.0
    front_lo, front_hi = (-0.30, 0.0), (-0.12, 0.8)
    back_lo, back_hi = (0.30, 0.0), (0.12, 0.8)
    banner = banner_rect(row)
    # road face: banner row across the whole face, u along the length
    b.quad_rect((-L, front_lo[0], front_lo[1]), (L, front_lo[0], front_lo[1]),
                (L, front_hi[0], front_hi[1]), (-L, front_hi[0], front_hi[1]), banner)
    b.quad_rect((-L, front_hi[0], 0.8), (L, front_hi[0], 0.8), (L, back_hi[0], 0.8), (-L, back_hi[0], 0.8),
                RECT_CONCRETE)  # top
    b.quad_rect((-L, back_hi[0], 0.8), (L, back_hi[0], 0.8), (L, back_lo[0], 0.0), (-L, back_lo[0], 0.0),
                RECT_CONCRETE)  # back
    for x in (-L, L):  # end caps, pentagon-ish profile as a fan
        pts = [(x, front_lo[0], 0.0), (x, back_lo[0], 0.0), (x, back_hi[0], 0.8), (x, front_hi[0], 0.8)]
        b.fan(pts, [uv_at(RECT_CONCRETE, 0.1, 0.1)] * 4)
    return b.finish("event_barrier_%d" % row)


def flag():
    """One object, two material slots: 0 = pole (8 sides, 6 m), 1 = cloth (1.2 x 0.8 m, 3:2, 12 x 4 grid).
    Cloth UV.x is 0 at the pole and 1 at the fly; UV.y spans the flag rows of flag_tr.png."""
    b = Builder()
    b.cylinder(0.0, 0.0, 0.0, 6.0, 0.035, 8, RECT_BL)
    n_pole = len(b.bm.faces)
    nx, nz = 12, 4
    fly, top_z, bot_z = 1.2, 4.2, 3.4
    v_top, v_bot = 0.834, 0.168  # flag rows 85..426 of the 512 px flag_tr.png
    for i in range(nx):
        for j in range(nz):
            x0, x1 = fly * i / nx, fly * (i + 1) / nx
            z0, z1 = top_z - (top_z - bot_z) * (j + 1) / nz, top_z - (top_z - bot_z) * j / nz
            u0, u1 = i / nx, (i + 1) / nx
            va0 = v_bot + (v_top - v_bot) * (z0 - bot_z) / (top_z - bot_z)
            va1 = v_bot + (v_top - v_bot) * (z1 - bot_z) / (top_z - bot_z)
            b.poly([(x0, 0.0, z0), (x1, 0.0, z0), (x1, 0.0, z1), (x0, 0.0, z1)],
                   [(u0, va0), (u1, va0), (u1, va1), (u0, va1)])
    ob = b.finish("event_flag")
    ob.data.materials.append(bpy.data.materials.new("M_EventPole"))
    ob.data.materials.append(bpy.data.materials.new("M_EventFlag"))
    for poly in ob.data.polygons:
        poly.material_index = 0 if poly.index < n_pole else 1
    return ob


def awning():
    b = Builder()
    L = 2.0
    y_front, y_back = -1.15, 0.95
    z_front, z_back = 2.35, 2.6
    b.quad_rect((-L, y_front, z_front), (L, y_front, z_front), (L, y_back, z_back), (-L, y_back, z_back),
                RECT_TL)  # canopy top, stripes
    b.quad_rect((-L, y_back, z_back - 0.05), (L, y_back, z_back - 0.05), (L, y_front, z_front - 0.05),
                (-L, y_front, z_front - 0.05), RECT_TR)  # underside, glows
    b.box((-L, y_front - 0.02, z_front - 0.08), (L, y_front + 0.04, z_front), RECT_TR)  # front lip
    for x in (-L + 0.1, L - 0.1):
        b.box((x - 0.04, y_front - 0.04, 0.0), (x + 0.04, y_front + 0.04, z_front - 0.05), RECT_BL)
    return b.finish("event_awning")


def cafe_set():
    b = Builder()
    b.cylinder(0.0, 0.0, 0.0, 0.02, 0.22, 8, RECT_BL)  # table foot
    b.cylinder(0.0, 0.0, 0.02, 0.72, 0.03, 6, RECT_BL)  # table column
    b.cylinder(0.0, 0.0, 0.72, 0.76, 0.35, 10, RECT_BR)  # table top
    for x in (-0.6, 0.6):
        for lx, ly in ((-0.18, -0.18), (0.18, -0.18), (-0.18, 0.18), (0.18, 0.18)):
            b.cylinder(x + lx, ly, 0.0, 0.45, 0.02, 4, RECT_BL)  # chair legs
        b.box((x - 0.21, -0.21, 0.43), (x + 0.21, 0.21, 0.47), RECT_BR)  # seat
        b.box((x - 0.21, 0.19, 0.47), (x + 0.21, 0.23, 1.0), RECT_BR)  # back
    return b.finish("event_cafe_set")


def export(ob, name):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    path = os.path.join(OUT, name)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_materials="EXPORT")
    print("[event] wrote", path)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    clear_scene()
    for row in range(3):
        export(barrier(row), "event_barrier_%d.glb" % row)
    export(flag(), "event_flag.glb")
    export(awning(), "event_awning.glb")
    export(cafe_set(), "event_cafe_set.glb")


if __name__ == "__main__":
    main()
