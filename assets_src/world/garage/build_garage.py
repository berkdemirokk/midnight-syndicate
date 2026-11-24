"""MIDNIGHT SYNDICATE - garage room (Environment Agent).

Run:
  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup \
      --python assets_src/world/garage/build_garage.py -- all [--samples N]
Modes: build (geometry, GLB, json), render (renders only), all (both).
Deterministic: no random seeds other than a fixed one.
Blender units = metres. Room X[-8,8] Y[-6,6] Z[0,4.6]. Car nose toward -Y.
"""
import bpy
import bmesh
import json
import math
import os
import random
import struct
import sys
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(HERE, "out")
REN = os.path.join(HERE, "renders")
TEX = os.path.join(REPO, "game", "assets", "textures", "cc0")
os.makedirs(OUT, exist_ok=True)
os.makedirs(REN, exist_ok=True)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
MODE = ARGS[0] if ARGS else "all"
SAMPLES = int(ARGS[ARGS.index("--samples") + 1]) if "--samples" in ARGS else 96
ONLY = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else None

# name, CC0 texture id (or None), linear base colour, roughness, metallic,
# emission colour (or None), emission strength, UV tiling in metres
MATS = [
    ("M_Floor_Epoxy", None, (0.030, 0.031, 0.034), 0.10, 0.0, None, 0.0, 8.0),  # flat polished epoxy, no CC0 map (no joints, no pebbling)
    ("M_Paint_Line", None, (0.75, 0.52, 0.04), 0.40, 0.0, None, 0.0, 1.0),
    ("M_Steel_Brushed", None, (0.55, 0.57, 0.60), 0.28, 1.0, None, 0.0, 1.0),
    ("M_Concrete_Wall", "concrete_wall_006", (0.13, 0.13, 0.14), 0.85, 0.0, None, 0.0, 3.0),
    ("M_Metal_Ribbed", "corrugated_iron_03", (0.09, 0.11, 0.13), 0.42, 0.7, None, 0.0, 1.5),
    ("M_Beam_Dark", None, (0.035, 0.036, 0.040), 0.55, 0.35, None, 0.0, 1.0),
    ("M_Light_Emit", None, (0.85, 0.94, 1.0), 0.40, 0.0, (0.85, 0.94, 1.0), 20.0, 1.0),
    ("M_Warm_Emit", None, (1.0, 0.55, 0.20), 0.40, 0.0, (1.0, 0.50, 0.18), 8.0, 1.0),
    ("M_Neon_Magenta", None, (1.0, 0.05, 0.70), 0.30, 0.0, (1.0, 0.08, 0.75), 9.0, 1.0),
    ("M_Neon_Cyan", None, (0.10, 0.90, 1.0), 0.30, 0.0, (0.10, 0.90, 1.0), 7.0, 1.0),
    ("M_Door_Slats", "corrugated_iron", (0.10, 0.11, 0.13), 0.50, 0.7, None, 0.0, 1.0),
    ("M_Wood_Bench", "dark_wooden_planks", (0.06, 0.03, 0.015), 0.70, 0.0, None, 0.0, 1.0),
    ("M_Paint_Blue", "blue_metal_plate", (0.02, 0.06, 0.15), 0.45, 0.5, None, 0.0, 1.0),
    ("M_Rubber", None, (0.012, 0.012, 0.013), 0.85, 0.0, None, 0.0, 1.0),
    ("M_Paint_Red", None, (0.25, 0.012, 0.008), 0.50, 0.0, None, 0.0, 1.0),
    ("M_Pegboard_Tan", None, (0.45, 0.31, 0.16), 0.80, 0.0, None, 0.0, 0.5),
]
# generated (project-owned) textures, written to out/textures/ and bound by name
GEN_TEX = {"M_Pegboard_Tan": "textures/pegboard_holes.png"}
AX = {
    "Z": Matrix.Identity(4),
    "X": Matrix.Rotation(math.pi / 2, 4, "Y"),
    "Y": Matrix.Rotation(math.pi / 2, 4, "X"),
}
MM = {}


def log(*a):
    print("[garage]", *a, flush=True)


# ---------------------------------------------------------------- scene / materials
def reset_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for d in list(coll):
            coll.remove(d)


def make_mat(spec):
    name, tid, base, rough, metal, ecol, estr, tile = spec
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if ecol:
        bsdf.inputs["Emission Color"].default_value = (*ecol, 1.0)
        bsdf.inputs["Emission Strength"].default_value = estr
    m["cc0_id"] = tid or ""
    m["tile_m"] = tile
    m["spec_rough"] = rough
    m["spec_base"] = list(base)
    return m


def make_pegboard_png(path):
    """Project-owned pegboard: tan board, 16 mm holes on a 50 mm grid (512 px = 0.5 m tile)."""
    W = H = 512
    img = bpy.data.images.new("pegboard_holes", W, H, alpha=False)
    px = [0.0] * (W * H * 4)
    for y in range(H):
        for x in range(W):
            cx, cy = (x % 64) - 32, (y % 64) - 32
            hole = cx * cx + cy * cy < 36
            v = (0.035, 0.025, 0.015) if hole else (0.78, 0.60, 0.38)
            k = (y * W + x) * 4
            px[k:k + 4] = [v[0], v[1], v[2], 1.0]
    img.pixels.foreach_set(px)
    img.colorspace_settings.name = "sRGB"
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def attach_textures(m):
    """Render-only: CC0 maps are bound here, after the GLB was exported without images."""
    tid = m.get("cc0_id", "")
    gen = GEN_TEX.get(m.name)
    if not tid and not gen:
        return
    nt = m.node_tree
    nd, ln = nt.nodes, nt.links
    bsdf = next(n for n in nd if n.type == "BSDF_PRINCIPLED")
    tile = m["tile_m"]
    uvn = nd.new("ShaderNodeUVMap")
    mp = nd.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1.0 / tile, 1.0 / tile, 1.0 / tile)
    ln.new(uvn.outputs["UV"], mp.inputs["Vector"])

    def tex(fname, cs):
        im = bpy.data.images.load(os.path.join(TEX, tid, fname), check_existing=True)
        im.colorspace_settings.name = cs
        n = nd.new("ShaderNodeTexImage")
        n.image = im
        ln.new(mp.outputs["Vector"], n.inputs["Vector"])
        return n

    if gen:
        n = nd.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(os.path.join(OUT, gen), check_existing=True)
        n.image.colorspace_settings.name = "sRGB"
        ln.new(mp.outputs["Vector"], n.inputs["Vector"])
        ln.new(n.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = m["spec_rough"]
        return

    col = tex("basecolor.jpg", "sRGB")
    tint = nd.new("ShaderNodeMixRGB")
    tint.blend_type = "MULTIPLY"
    tint.inputs["Fac"].default_value = 1.0
    tint.inputs["Color2"].default_value = (*[min(1.0, c * 2.2) for c in m["spec_base"]], 1.0)
    ln.new(col.outputs["Color"], tint.inputs["Color1"])
    ln.new(tint.outputs["Color"], bsdf.inputs["Base Color"])
    rgh = tex("roughness.jpg", "Non-Color")
    rm = nd.new("ShaderNodeMath")
    rm.operation = "MULTIPLY"
    rm.inputs[1].default_value = 2.0 * m["spec_rough"]
    ln.new(rgh.outputs["Color"], rm.inputs[0])
    ln.new(rm.outputs["Value"], bsdf.inputs["Roughness"])
    nrm = tex("normal.jpg", "Non-Color")
    nmap = nd.new("ShaderNodeNormalMap")
    nmap.inputs["Strength"].default_value = 0.3 if m.name == "M_Floor_Epoxy" else 1.0  # polished: little bump
    ln.new(nrm.outputs["Color"], nmap.inputs["Color"])
    ln.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])


# ---------------------------------------------------------------- mesh helpers
def uv_world(bm):
    layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for lp in f.loops:
            c = lp.vert.co
            if ax == 0:
                lp[layer].uv = (c.y, c.z)
            elif ax == 1:
                lp[layer].uv = (c.x, c.z)
            else:
                lp[layer].uv = (c.x, c.y)


def finish(name, bm, mat):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    uv_world(bm)  # every primitive gets UVs, so no piece samples texel (0,0)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for mt in mat:
        me.materials.append(mt)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def box(name, x0, y0, z0, x1, y1, z1, mat, bev=0.012, seg=2, uv=True):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    cx, cy, cz = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
    sx, sy, sz = x1 - x0, y1 - y0, z1 - z0
    for v in bm.verts:
        v.co = Vector((cx + v.co.x * sx, cy + v.co.y * sy, cz + v.co.z * sz))
    b = min(bev, 0.45 * min(sx, sy, sz))
    if b > 0.002:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=b, offset_type="OFFSET",
                        segments=seg, profile=0.5, affect="EDGES", clamp_overlap=True)
    if uv:
        uv_world(bm)
    return finish(name, bm, [mat])


def revolve(name, prof, mats, S, M, idx=lambda i: 0):
    """Revolve a closed (r, z) profile around local Z, transformed by M."""
    bm = bmesh.new()
    P = len(prof)
    rings = []
    for k in range(S):
        a = 2 * math.pi * k / S
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new(M @ Vector((r * ca, r * sa, z))) for (r, z) in prof])
    for k in range(S):
        k2 = (k + 1) % S
        for i in range(P):
            i2 = (i + 1) % P
            if prof[i][0] == 0 and prof[i2][0] == 0:
                continue
            f = bm.faces.new([rings[k][i], rings[k2][i], rings[k2][i2], rings[k][i2]])
            f.material_index = idx(i)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    return finish(name, bm, mats)


def cyl(name, cx, cy, cz, r, h, mat, axis="Z", S=20):
    prof = [(0.0, -h / 2), (r, -h / 2), (r, h / 2), (0.0, h / 2)]
    return revolve(name, prof, [mat], S, Matrix.Translation((cx, cy, cz)) @ AX[axis])


def tyre_prof(ri=0.20, ro=0.33, hw=0.11, rc=0.045, n=3):
    corners = [
        (ro - rc, hw - rc, 0, 90),
        (ri + rc, hw - rc, 90, 180),
        (ri + rc, -(hw - rc), 180, 270),
        (ro - rc, -(hw - rc), 270, 360),
    ]
    pts = []
    for cx, cz, a0, a1 in corners:
        for j in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * j / n)
            pts.append((cx + rc * math.cos(a), cz + rc * math.sin(a)))
    return pts


def tyre(name, cx, cy, cz, axis, mat):
    return revolve(name, tyre_prof(), [mat], 24, Matrix.Translation((cx, cy, cz)) @ AX[axis])


def prism_yz(name, pts, x0, x1, mat):
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for (y, z) in pts]
    b = [bm.verts.new((x1, y, z)) for (y, z) in pts]
    n = len(pts)
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([a[i], a[j], b[j], b[i]])
    return finish(name, bm, [mat])


def text_obj(name, body, width, depth, mat, euler, centre):
    """Blender built-in font, converted to mesh, scaled in XY to a target width."""
    bpy.ops.object.text_add(location=(0, 0, 0))
    ob = bpy.context.active_object
    cu = ob.data
    cu.body = body
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.size = 1.0
    cu.extrude = depth / 2.0
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.active_object
    me = ob.data
    tb = bmesh.new()
    tb.from_mesh(me)
    uv_world(tb)
    tb.to_mesh(me)
    tb.free()
    vs = [v.co for v in me.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c = (mn + mx) / 2
    s = width / (mx.x - mn.x)
    R = Euler(tuple(math.radians(a) for a in euler)).to_matrix().to_4x4()
    M = Matrix.Translation(Vector(centre)) @ R @ Matrix.Diagonal((s, s, 1.0, 1.0)) @ Matrix.Translation(-c)
    me.transform(M)
    me.materials.clear()
    me.materials.append(mat)
    ob.name = name
    me.name = name
    return ob


# ---------------------------------------------------------------- scene content
def build_room():
    M = {s[0]: make_mat(s) for s in MATS}
    MM.update(M)
    CON, MET, DARK = M["M_Concrete_Wall"], M["M_Metal_Ribbed"], M["M_Beam_Dark"]
    PAINT, STEEL, BLUE = M["M_Paint_Line"], M["M_Steel_Brushed"], M["M_Paint_Blue"]
    RUB, RED, WOOD = M["M_Rubber"], M["M_Paint_Red"], M["M_Wood_Bench"]
    PEG = M["M_Pegboard_Tan"]
    LIGHT, WARM = M["M_Light_Emit"], M["M_Warm_Emit"]
    MAG, CYAN = M["M_Neon_Magenta"], M["M_Neon_Cyan"]
    DOOR, EPOXY = M["M_Door_Slats"], M["M_Floor_Epoxy"]

    # --- floor, collider, paint, turntable
    box("floor", -8, -6, -0.3, 8, 6, 0, EPOXY, bev=0.01)
    box("floor-colonly", -8, -6, -0.3, 8, 6, -0.002, EPOXY, bev=0, uv=False)
    box("paint_bay_L", -4.2, -5.0, 0, -4.1, 5.0, 0.004, PAINT, bev=0)
    box("paint_bay_R", 4.1, -5.0, 0, 4.2, 5.0, 0.004, PAINT, bev=0)
    box("paint_bay_back", -4.2, -5.0, 0, 4.2, -4.9, 0.004, PAINT, bev=0)
    box("paint_bay_front", -4.2, 4.9, 0, 4.2, 5.0, 0.004, PAINT, bev=0)
    box("paint_threshold", -3.5, -5.75, 0, 3.5, -5.55, 0.004, PAINT, bev=0)
    tt_prof = [(0.0, 0.0), (2.45, 0.0), (2.45, 0.045), (2.36, 0.045), (2.36, 0.065), (0.0, 0.065)]
    revolve("turntable", tt_prof, [STEEL, EPOXY], 48, Matrix.Identity(4),
            idx=lambda i: 1 if i in (3, 4) else 0)

    # --- walls (lower concrete band, upper ribbed metal band)
    for nm, xa, xb, rx in (("L", -8.3, -8.0, -8.0), ("R", 8.0, 8.3, 7.94)):
        box(f"wall_{nm}_low", xa, -6.3, 0, xb, 6.3, 1.8, CON, bev=0.02)
        box(f"wall_{nm}_up", xa, -6.3, 1.8, xb, 6.3, 4.6, MET, bev=0.02)
        for i in range(40):
            y = -5.85 + 0.3 * i
            if nm == "R" and -4.7 < y < -1.3:  # pegboard sits on this wall here
                continue
            box(f"rib_{nm}_{i}", rx, y, 1.8, rx + 0.06, y + 0.06, 4.6, MET, bev=0, uv=False)
    box("wall_F_low", -8.3, 6.0, 0, 8.3, 6.3, 1.8, CON, bev=0.02)
    box("wall_F_up", -8.3, 6.0, 1.8, 8.3, 6.3, 4.6, MET, bev=0.02)
    for i, z in enumerate((2.0, 2.3, 2.6, 2.9, 4.3)):
        box(f"rib_F_{i}", -8.0, 5.94, z, 8.0, 6.0, z + 0.05, MET, bev=0, uv=False)
    # back wall with roll-up door opening x[-3.5,3.5] z[0,4.0]
    box("back_low_L", -8.3, -6.3, 0, -3.5, -6.0, 1.8, CON, bev=0.02)
    box("back_up_L", -8.3, -6.3, 1.8, -3.5, -6.0, 4.6, MET, bev=0.02)
    box("back_low_R", 3.5, -6.3, 0, 8.3, -6.0, 1.8, CON, bev=0.02)
    box("back_up_R", 3.5, -6.3, 1.8, 8.3, -6.0, 4.6, MET, bev=0.02)
    box("back_header", -3.5, -6.3, 4.0, 3.5, -6.0, 4.6, MET, bev=0.02)
    for i in range(14):
        x = -7.7 + 0.3 * i
        box(f"rib_B_{i}", x, -6.0, 1.8, x + 0.06, -5.94, 4.6, MET, bev=0, uv=False)
    # columns with chamfers
    for sx in (-7.5, 7.5):
        for yc in (-5.4, 0.0, 5.4):
            box(f"column_{sx:+.1f}_{yc:+.1f}", sx - 0.25, yc - 0.25, 0, sx + 0.25, yc + 0.25, 4.6, DARK, bev=0.05)

    # --- ceiling, beams, lights, duct
    box("ceiling", -8.3, -6.3, 4.6, 8.3, 6.3, 4.9, DARK, bev=0.02)
    for yc in (-4.5, -1.5, 1.5, 4.5):
        box(f"beam_{yc:+.1f}", -7.95, yc - 0.15, 4.15, 7.95, yc + 0.15, 4.6, DARK, bev=0.02)
    for i, x in enumerate((-3.6, -1.8, 0.0, 1.8, 3.6)):
        box(f"light_strip_y{i}", x - 0.06, -4.4, 4.03, x + 0.06, 4.4, 4.11, LIGHT, bev=0.012, seg=2)
        box(f"light_frame_y{i}", x - 0.12, -4.46, 4.0, x + 0.12, 4.46, 4.03, DARK, bev=0.01)
        for yy in (-4.3, 4.3):  # hanger rods up to the beam
            cyl(f"light_rod_y{i}_{yy:+.0f}", x, yy, 4.36, 0.012, 0.5, DARK, S=6)
    for i, y in enumerate((-5.0, 5.0)):
        box(f"light_strip_x{i}", -7.5, y - 0.06, 4.03, 7.5, y + 0.06, 4.11, LIGHT, bev=0.012, seg=2)
        box(f"light_frame_x{i}", -7.5, y - 0.12, 4.0, 7.5, y + 0.12, 4.03, DARK, bev=0.01)
        for xx in (-6.0, -2.0, 2.0, 6.0):
            cyl(f"light_rod_x{i}_{xx:+.0f}", xx, y, 4.36, 0.012, 0.5, DARK, S=6)
    box("duct", -5.6, -5.8, 3.7, -4.6, 5.8, 4.05, MET, bev=0.03)
    for i, y0 in enumerate((-3.0, 0.0, 3.0)):
        box(f"duct_bracket_{i}", -5.25, y0 - 0.04, 4.05, -4.95, y0 + 0.04, 4.6, MET, bev=0, uv=False)
    cyl("warm_tube_L", -5.8, -5.9, 0.45, 0.03, 3.6, WARM, axis="X")
    cyl("warm_tube_R", 5.9, -5.9, 0.45, 0.03, 3.4, WARM, axis="X")

    # --- roll-up door, ramp, neon sign
    # roll-up curtain, raised 2.0 m: 19 bevelled slats on a 0.1 m pitch, dark gaps between them
    box("door_housing", -3.7, -5.98, 3.9, 3.7, -5.4, 4.05, DOOR, bev=0.03)
    for i in range(19):
        z = 2.0 + 0.1 * i
        box(f"door_slat_{i:02d}", -3.5, -6.06, z, 3.5, -5.94, z + 0.084, DOOR, bev=0.014, seg=2)
    box("door_bottom_bar", -3.56, -6.1, 1.9, 3.56, -5.9, 2.02, DARK, bev=0.02)
    for xs in (-3.5, 3.5):
        box(f"door_seal_{xs:+.1f}", xs - 0.02, -6.1, 0.0, xs + 0.02, -6.04, 1.9, DARK, bev=0.005)
    box("door_guide_L", -3.62, -6.05, 0, -3.5, -5.9, 4.0, DARK, bev=0.01)
    box("door_guide_R", 3.5, -6.05, 0, 3.62, -5.9, 4.0, DARK, bev=0.01)
    prism_yz("ramp_down", [(-6.3, 0.0), (-9.0, -2.7), (-9.0, -3.0), (-6.3, -0.3)], -3.5, 3.5, M["M_Concrete_Wall"])
    box("ramp_lip_paint", -3.5, -6.5, -0.02, 3.5, -6.3, 0.02, PAINT, bev=0)  # yellow lip, reads through the gap
    box("sign_panel", 3.8, -6.0, 2.75, 7.6, -5.95, 3.75, DARK, bev=0.02)
    text_obj("sign_syndicate", "SYNDICATE GARAGE", 3.3, 0.03, MAG, (90, 0, 180), (5.7, -5.92, 3.25))
    box("sign_underline", 4.1, -5.97, 2.84, 7.3, -5.93, 2.9, CYAN, bev=0.005)
    text_obj("stencil_bay01_front", "BAY 01", 2.4, 0.02, PAINT, (90, 0, 0), (0.0, 5.9, 2.9))
    text_obj("logo_noctra_right", "NOCTRA", 2.2, 0.02, PAINT, (90, 0, -90), (7.96, 2.6, 2.6))  # clear of columns

    # --- left wall dressing (x < 0): tool chest, parts shelf, folded lift, cable run, extinguisher
    box("tool_chest_body", -7.9, -4.9, 0.1, -7.2, -3.9, 0.9, BLUE, bev=0.02)
    box("tool_chest_plinth", -7.85, -4.85, 0, -7.25, -3.95, 0.1, DARK, bev=0)
    for i, (z0, z1) in enumerate(((0.12, 0.30), (0.32, 0.50), (0.52, 0.70), (0.72, 0.88))):
        box(f"chest_drawer_{i}", -7.2, -4.84, z0, -7.16, -3.96, z1, BLUE, bev=0.005)
        cyl(f"chest_handle_{i}", -7.13, -4.4, (z0 + z1) / 2, 0.012, 0.4, STEEL, axis="Y", S=12)
    box("shelf_back", -7.92, -3.5, 0, -7.86, -1.5, 2.2, BLUE, bev=0)
    for i, z in enumerate((0.04, 0.8, 1.5, 2.15)):
        box(f"shelf_board_{i}", -7.9, -3.5, z, -7.4, -1.5, z + 0.04, BLUE, bev=0.005)
    rnd = random.Random(11)
    for si, z in enumerate((0.08, 0.84, 1.54)):
        for yi, yc in enumerate((-3.25, -2.6, -1.95)):
            if rnd.random() < 0.2:
                continue
            sx, sy, sz = rnd.uniform(0.2, 0.36), rnd.uniform(0.2, 0.34), rnd.uniform(0.15, 0.3)
            xc = -7.65 + rnd.uniform(-0.08, 0.08)
            box(f"shelf_box_{si}{yi}", xc - sx / 2, yc - sy / 2, z, xc + sx / 2, yc + sy / 2, z + sz,
                WOOD, bev=0.006, seg=1)
    box("lift_post_1", -7.6, 1.2, 0, -7.3, 1.5, 3.6, DARK, bev=0.01)
    box("lift_post_2", -7.6, 3.5, 0, -7.3, 3.8, 3.6, DARK, bev=0.01)
    box("lift_arm_folded", -7.3, 1.5, 2.0, -7.2, 3.5, 2.15, DARK, bev=0.01)
    box("lift_foot_1", -7.65, 1.1, 0, -7.25, 1.6, 0.04, DARK, bev=0)
    box("lift_foot_2", -7.65, 3.4, 0, -7.25, 3.9, 0.04, DARK, bev=0)
    box("cable_tray", -7.98, -6.0, 3.85, -7.78, 6.0, 3.95, DARK, bev=0.004)
    cyl("conduit", -7.88, 0.0, 3.1, 0.04, 12.0, MET, axis="Y", S=14)
    cyl("cable_a", -7.9, 0.0, 3.99, 0.015, 12.0, RUB, axis="Y", S=8)
    cyl("cable_b", -7.9, 0.0, 3.94, 0.015, 12.0, RUB, axis="Y", S=8)
    box("jack_body", -6.9, -1.0, 0.12, -6.3, -0.2, 0.34, RED, bev=0.02)
    box("jack_handle", -6.55, -0.2, 0.34, -6.45, 0.5, 0.5, DARK, bev=0.01)
    cyl("jack_wheel_1", -6.6, -0.95, 0.06, 0.06, 0.05, RUB, axis="X", S=14)
    cyl("jack_wheel_2", -6.6, -0.3, 0.06, 0.06, 0.05, RUB, axis="X", S=14)
    box("drain_plate", -6.5, 3.7, 0, -5.9, 4.3, 0.012, STEEL, bev=0.003)
    for i in range(5):
        y = 3.8 + 0.1 * i
        box(f"drain_slot_{i}", -6.45, y, 0.012, -5.95, y + 0.03, 0.02, DARK, bev=0, uv=False)
    cyl("extinguisher_body", -7.0, 5.82, 0.65, 0.09, 0.7, RED, S=16)
    cyl("extinguisher_valve", -7.0, 5.82, 1.02, 0.03, 0.05, STEEL, S=10)

    # --- right wall dressing (x > 0): workbench, vice, pegboard, tyre rack, wheels, oil drum
    box("bench_top", 7.15, -4.6, 0.88, 7.9, -1.4, 0.93, WOOD, bev=0.01)
    box("bench_cabinet", 7.2, -4.5, 0, 7.85, -1.5, 0.88, BLUE, bev=0.01)
    for i, (z0, z1) in enumerate(((0.08, 0.30), (0.33, 0.55), (0.58, 0.80))):
        box(f"bench_drawer_{i}", 7.16, -4.45, z0, 7.2, -1.55, z1, DARK, bev=0.004)
        cyl(f"bench_handle_{i}", 7.14, -3.0, (z0 + z1) / 2, 0.012, 0.5, STEEL, axis="Y", S=12)
    box("vice_body", 7.3, -4.45, 0.93, 7.55, -4.0, 1.15, STEEL, bev=0.01)
    box("vice_jaw", 7.15, -4.5, 0.93, 7.3, -3.95, 1.1, STEEL, bev=0.01)
    box("pegboard", 7.94, -4.6, 1.2, 7.98, -1.4, 2.6, PEG, bev=0.003)
    for i, yc in enumerate((-4.4, -4.1, -3.8, -3.5, -3.2, -2.9, -2.6, -2.3, -2.0, -1.7)):
        z = 1.4 + 0.1 * (i % 4)
        if i % 3 == 0:  # spanner silhouette
            box(f"peg_tool_{i}", 7.9, yc, z, 7.94, yc + 0.22, z + 0.4, STEEL, bev=0, uv=False)
        elif i % 3 == 1:  # hammer silhouette
            box(f"peg_tool_{i}", 7.9, yc, z, 7.94, yc + 0.05, z + 0.4, STEEL, bev=0, uv=False)
            box(f"peg_head_{i}", 7.9, yc - 0.04, z + 0.36, 7.94, yc + 0.1, z + 0.5, STEEL, bev=0, uv=False)
        else:  # screwdriver silhouette
            cyl(f"peg_tool_{i}", 7.92, yc, z + 0.2, 0.012, 0.4, STEEL, axis="Z", S=8)
    for yy in (1.0, 3.95):
        box(f"rack_post_{yy}_a", 6.9, yy, 0, 6.95, yy + 0.05, 1.6, BLUE, bev=0.005)
        box(f"rack_post_{yy}_b", 7.85, yy, 0, 7.9, yy + 0.05, 1.6, BLUE, bev=0.005)
    box("rack_shelf_low", 6.9, 1.0, 0.05, 7.9, 4.0, 0.1, BLUE, bev=0.005)
    box("rack_shelf_high", 6.9, 1.0, 0.7, 7.9, 4.0, 0.75, BLUE, bev=0.005)
    n = 0
    for zc in (0.43, 1.08):
        for yc in (1.45, 2.15, 2.85, 3.55):
            tyre(f"tyre_rack_{n}", 7.5, yc, zc, "X", RUB)
            n += 1
    for k in range(3):
        z = 0.11 + 0.22 * k
        tyre(f"tyre_stack_{k}", 6.5, 4.6, z, "Z", RUB)
        cyl(f"wheel_rim_{k}", 6.5, 4.6, z, 0.2, 0.16, STEEL, S=20)
        cyl(f"wheel_hub_{k}", 6.5, 4.6, z, 0.05, 0.2, STEEL, S=12)
    cyl("oil_drum", 6.4, -5.0, 0.44, 0.29, 0.88, RED, S=20)
    cyl("oil_drum_lid", 6.4, -5.0, 0.88, 0.30, 0.03, STEEL, S=20)
    # oil stains on the epoxy, outside the turntable and clear of the car
    for i, (sx, sy, r) in enumerate(((-3.3, -2.6, 0.55), (3.5, 3.2, 0.42), (-5.0, 1.8, 0.7), (2.2, -5.0, 0.35))):
        cyl(f"oil_stain_{i}", sx, sy, 0.001, r, 0.002, DARK, S=18)

    # --- more workshop dressing (kept to |x| > 5.8)
    # left: compressor, gas bottles, wooden crates
    box("compressor_base", -7.85, 4.0, 0, -7.2, 5.1, 0.1, DARK, bev=0.01)
    cyl("compressor_tank", -7.52, 4.55, 0.45, 0.26, 0.85, STEEL, axis="Y", S=18)
    box("compressor_motor", -7.7, 4.7, 0.72, -7.34, 5.05, 0.98, RED, bev=0.02)
    for i, gy in enumerate((-1.0, -0.6)):
        cyl(f"gas_bottle_{i}", -7.35, gy, 0.5, 0.1, 1.0, STEEL, S=14)
        cyl(f"gas_cap_{i}", -7.35, gy, 1.02, 0.05, 0.05, DARK, S=10)
    box("crate_low", -7.0, -3.3, 0, -6.4, -2.6, 0.55, WOOD, bev=0.012)
    box("crate_high", -6.95, -3.25, 0.55, -6.45, -2.65, 1.05, WOOD, bev=0.012)
    # right: work lamp over the bench, stool, toolbox and cans on the bench, floor tyres and cans
    box("bench_toolbox", 7.25, -3.6, 0.93, 7.8, -2.6, 1.1, RED, bev=0.02)
    cyl("bench_can_1", 7.45, -2.2, 1.0, 0.09, 0.18, BLUE, S=14)
    cyl("bench_can_2", 7.6, -2.0, 1.0, 0.09, 0.18, STEEL, S=14)
    cyl("work_lamp_rod", 7.65, -2.9, 3.6, 0.02, 1.8, DARK, S=6)
    box("work_lamp_arm", 7.55, -2.95, 2.4, 7.75, -2.85, 2.7, DARK, bev=0.01)
    box("work_lamp_head", 7.3, -3.2, 2.2, 7.8, -2.6, 2.3, WARM, bev=0.02)
    cyl("stool_post", 6.4, -2.8, 0.31, 0.03, 0.6, STEEL, S=8)
    cyl("stool_seat", 6.4, -2.8, 0.64, 0.2, 0.08, RUB, S=16)
    for k, z in enumerate((0.11, 0.33, 0.55)):
        tyre(f"tyre_floor_{k}", 5.95, -3.9, z, "Z", RUB)
    cyl("paint_can_f1", 5.85, -5.3, 0.12, 0.13, 0.24, BLUE, S=14)
    cyl("paint_can_f2", 5.85, -5.3, 0.4, 0.13, 0.24, RED, S=14)
    # --- reference stand-in (render only, never exported; mid grey so its shape reads)
    REF = make_mat(("REF_Standin", None, (0.16, 0.17, 0.19), 0.5, 0.0, None, 0.0, 1.0))
    box("REF_standin_car", -0.95, -2.15, 0.065, 0.95, 2.15, 1.36, REF, bev=0.04)
    log("objects", len(bpy.data.objects))


# ---------------------------------------------------------------- export and data
def geo_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH" and not o.name.startswith("REF_")]


def tri_count(objs):
    t = 0
    for o in objs:
        for p in o.data.polygons:
            t += max(0, len(p.vertices) - 2)
    return t


def export_glb(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_image_format="NONE", export_lights=False, export_cameras=False,
                              export_apply=False)


def glb_json(path):
    with open(path, "rb") as fh:
        head = fh.read(20)
        _, _, _ = struct.unpack("<4sII", head[:12])
        clen, ctype = struct.unpack("<I4s", head[12:20])
        return json.loads(fh.read(clen).decode("utf-8"))


def g(p):
    """Blender (x, y, z) -> Godot (x, z, -y)."""
    return [round(p[0], 3), round(p[2], 3), round(-p[1], 3)]


def write_json_files(objs):
    mats = []
    for spec in MATS:
        name, tid, base, rough, metal, ecol, estr, tile = spec
        mats.append({
            "name": name,
            "cc0_texture_id": tid,
            "base_color_linear": list(base),
            "roughness": rough,
            "metallic": metal,
            "emissive_color_linear": list(ecol) if ecol else [0, 0, 0],
            "emissive_strength": estr,
            "uv_tiling_m": tile,
            "uv_note": "UV = world metres (box projection); engine repeats by 1/uv_tiling_m",
            "generated_texture": GEN_TEX.get(name),
        })
    with open(os.path.join(OUT, "materials.json"), "w", encoding="utf-8") as fh:
        json.dump({"materials": mats, "generated_textures": sorted(set(GEN_TEX.values())),
                   "uv_units": "metres"}, fh, indent=2)

    lights = []
    for i, x in enumerate((-3.6, -1.8, 0.0, 1.8, 3.6)):
        lights.append({"name": f"ceiling_strip_y{i}", "type": "area", "position": g((x, 0, 4.07)),
                       "size": [0.1, 0.08, 8.8], "colour": [0.85, 0.94, 1.0], "energy_hint": 20.0,
                       "note": "long axis along car length (Blender Y -> Godot Z)"})
    for i, y in enumerate((-5.0, 5.0)):
        lights.append({"name": f"ceiling_strip_x{i}", "type": "area", "position": g((0, y, 4.07)),
                       "size": [15.0, 0.08, 0.1], "colour": [0.85, 0.94, 1.0], "energy_hint": 20.0})
    lights.append({"name": "warm_tube_back_L", "type": "area", "position": g((-5.8, -5.9, 0.45)),
                   "size": [3.6, 0.06, 0.06], "colour": [1.0, 0.55, 0.2], "energy_hint": 6.0})
    lights.append({"name": "warm_tube_back_R", "type": "area", "position": g((5.9, -5.9, 0.45)),
                   "size": [3.4, 0.06, 0.06], "colour": [1.0, 0.55, 0.2], "energy_hint": 6.0})
    lights.append({"name": "work_lamp_bench", "type": "area", "position": g((7.55, -2.9, 2.2)),
                   "size": [0.5, 0.06, 0.6], "colour": [1.0, 0.7, 0.4], "energy_hint": 5.0,
                   "note": "warm work lamp over the workbench (emissive in GLB)"})
    lights.append({"name": "neon_sign_magenta", "type": "area", "position": g((5.7, -5.92, 3.25)),
                   "size": [3.3, 0.03, 0.5], "colour": [1.0, 0.08, 0.75], "energy_hint": 18.0})
    lights.append({"name": "neon_sign_underline", "type": "area", "position": g((5.7, -5.95, 2.87)),
                   "size": [3.2, 0.04, 0.06], "colour": [0.10, 0.90, 1.0], "energy_hint": 20.0})
    layout = {
        "coords": "godot_y_up",
        "conversion": "godot = (blender_x, blender_z, -blender_y)",
        "room_size_m": {"width_x": 16.0, "depth_z": 12.0, "height_y": 4.6},
        "turntable": {"centre": [0.0, 0.0, 0.0], "radius_m": 2.45, "node": "turntable",
                      "plate_top_height_m": 0.065},
        "car_stand": {"forward": [0, 0, -1], "note": "car nose toward Godot -Z (Blender -Y)"},
        "lights": lights,
        "reflection_probe": {"centre": [0.0, 2.3, 0.0], "half_extents": [8.0, 2.3, 6.0]},
        "camera_orbit": {"target": [0.0, 0.7, 0.0], "min_distance_m": 3.2, "max_distance_m": 5.4,
                         "min_pitch_deg": -2.0, "max_pitch_deg": 40.0,
                         "note": "keeps camera inside room: max height ~4.1 m, max radius ~4.1 m from walls"},
    }
    with open(os.path.join(OUT, "garage_layout.json"), "w", encoding="utf-8") as fh:
        json.dump(layout, fh, indent=2)


def write_report(objs, glb_path):
    j = glb_json(glb_path)
    mats_used = sorted({m.name for o in objs for m in o.data.materials if m})
    lo = [min(o.bound_box[k][a] for o in objs for k in range(8)) for a in range(3)]
    hi = [max(o.bound_box[k][a] for o in objs for k in range(8)) for a in range(3)]
    no_uv = sum(1 for o in objs if not o.data.uv_layers)
    report = {
        "exported_bounds_blender_m": {"min": [round(v, 3) for v in lo], "max": [round(v, 3) for v in hi]},
        "exported_bounds_note": "ramp_down runs outside the back wall and below floor level (Blender z min = -3.0); "
                                "walls are 0.3 m thick. Room interior is x[-8,8] y[-6,6] z[0,4.6].",
        "primitives_without_uv": no_uv,
        "triangles": tri_count(objs),
        "triangle_budget": 60000,
        "object_count": len(objs),
        "material_slots": len(mats_used),
        "material_slot_budget": 16,
        "materials": mats_used,
        "glb_bytes": os.path.getsize(glb_path),
        "glb_images": len(j.get("images", [])),
        "glb_textures": len(j.get("textures", [])),
        "glb_meshes": len(j.get("meshes", [])),
        "room_m": {"x": 16.0, "y": 12.0, "z": 4.6},
        "collider": "floor-colonly",
        "turntable_object": "turntable",
    }
    with open(os.path.join(OUT, "report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
    log("REPORT", json.dumps(report))


# ---------------------------------------------------------------- render
def setup_render(samples):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"
    sc.cycles.device = "GPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPTIX"
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 900
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.exposure = 0.0
    wd = bpy.data.worlds.new("garage_world")
    wd.use_nodes = True
    wd.node_tree.nodes["Background"].inputs[0].default_value = (0.004, 0.005, 0.008, 1.0)
    sc.world = wd


def add_camera(name, loc, target, lens):
    cd = bpy.data.cameras.new(name)
    cd.lens = lens
    ob = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = Vector(loc)
    d = Vector(target) - Vector(loc)
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return ob


VIEWS = [
    ("wide", (6.4, 5.5, 2.0), (-1.0, -4.0, 1.2), 20, False),
    ("turntable", (3.6, -4.2, 1.5), (0.0, 0.0, 0.6), 35, True),
    ("back_wall", (2.0, 4.6, 1.9), (2.4, -6.0, 2.1), 26, False),
    ("dressing_left", (4.6, -0.6, 1.5), (-7.9, -0.8, 0.9), 24, False),
    ("dressing_right", (-4.6, 0.6, 1.5), (7.9, 0.8, 0.9), 24, False),
    ("ceiling_lights", (0.0, -3.6, 1.6), (0.0, 5.0, 2.8), 20, False),
]


def render_views(samples):
    """Lit by the GLB emissive fixtures only (no render-only fills), so the evidence matches the asset."""
    setup_render(samples)
    for name, loc, tgt, lens, show_ref in VIEWS:
        if ONLY and name not in ONLY:
            continue
        for o in bpy.context.scene.objects:
            if o.name.startswith("REF_"):
                o.hide_render = not show_ref
        cam = add_camera("cam_" + name, loc, tgt, lens)
        bpy.context.scene.camera = cam
        bpy.context.scene.render.filepath = os.path.join(REN, name + ".png")
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam, do_unlink=True)
        log("rendered", name)


def main():
    reset_scene()
    os.makedirs(os.path.join(OUT, "textures"), exist_ok=True)
    make_pegboard_png(os.path.join(OUT, GEN_TEX["M_Pegboard_Tan"]))
    build_room()
    objs = geo_objects()
    if MODE in ("build", "all"):
        glb = os.path.join(OUT, "garage_room.glb")
        export_glb(glb, objs)
        write_json_files(objs)
        write_report(objs, glb)
    if MODE in ("render", "all"):
        for m in MM.values():
            attach_textures(m)
        render_views(SAMPLES)
    log("done", MODE)


main()
