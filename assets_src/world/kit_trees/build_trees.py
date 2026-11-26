"""Tree kit generator (Blender 5.3, deterministic, procedural only, no downloads).

Run:  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup --python build_trees.py
Needs assets_src/world/kit_trees/gen_leaf_atlas.py to have written game/assets/world/kits/trees/leaf_atlas.png first.

Species (Blender metres, Z up; the glTF export turns Z into Godot Y):
  plane   cinar / plane tree, broad crown, 11 m
  judas   erguvan / Judas tree, pink-magenta bloom, 5.6 m
  cypress servi / Italian cypress, narrow, 9.2 m
  street  small planter tree, 4.2 m

Per species three GLBs:
  tree_<sp>_lod0.glb  surface 0 = bark, surface 1 = leaves, <= 3500 tris
  tree_<sp>_lod1.glb  surface 0 = bark, surface 1 = leaves, <= 900 tris
  tree_<sp>_lod2.glb  one surface = leaves, 2 crossed cards (4 tris), UVs into impostor_<sp>.png
impostor_<sp>.png (1024x512) = LOD0 rendered from -Y (left half) and from -X (right half), alpha kept.
Vertex colour RGB = fake ambient occlusion (dark inside and underneath), vertex colour A unused.
"""
import math
import os
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_DIR = os.path.join(REPO, "game", "assets", "world", "kits", "trees")
RENDERS = os.path.join(HERE, "out", "renders")
ATLAS = os.path.join(OUT_DIR, "leaf_atlas.png")
TRI_LIMIT = {0: 3500, 1: 900, 2: 4}
RENDER_PX = 512

# Atlas quadrant per species, as (u0, v0) in Blender UV space (v up). Each quadrant is 0.5 x 0.5.
QUADRANT = {"plane": (0.0, 0.5), "judas": (0.5, 0.5), "cypress": (0.0, 0.0), "street": (0.5, 0.0)}

SPECIES = {
    "plane": dict(seed=11, height=11.0, trunk_h=4.5, trunk_r=0.24, cy=7.2, crown_r=4.6, crown_rz=3.3,
                  branches=7, branch_len=3.0, clusters0=320, clusters1=150, card=(1.15, 1.0),
                  bark=(0.62, 0.6, 0.55), mottle=0.18),
    "judas": dict(seed=23, height=5.6, trunk_h=1.3, trunk_r=0.12, cy=3.4, crown_r=2.5, crown_rz=1.6,
                  branches=6, branch_len=1.8, clusters0=260, clusters1=120, card=(0.8, 0.7),
                  bark=(0.27, 0.2, 0.18), mottle=0.1),
    "cypress": dict(seed=37, height=9.2, trunk_h=0.9, trunk_r=0.1, cy=5.3, crown_r=1.25, crown_rz=4.0,
                    branches=3, branch_len=0.8, clusters0=260, clusters1=130, card=(0.45, 0.8),
                    bark=(0.3, 0.22, 0.16), mottle=0.1),
    "street": dict(seed=41, height=4.2, trunk_h=1.6, trunk_r=0.08, cy=2.9, crown_r=1.5, crown_rz=1.1,
                   branches=4, branch_len=1.1, clusters0=150, clusters1=70, card=(0.6, 0.55),
                   bark=(0.42, 0.36, 0.3), mottle=0.12),
}


def log(*a):
    print("[trees]", *a)


# ----------------------------------------------------------------------------- scene and materials

def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.render.resolution_x = RENDER_PX
    scene.render.resolution_y = RENDER_PX
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("TreeRenderWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.85, 0.88, 0.92, 1.0)
    bg.inputs["Strength"].default_value = 1.1
    scene.world = world
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 2.5
    sun_obj = bpy.data.objects.new("Sun", sun)
    scene.collection.objects.link(sun_obj)
    sun_obj.rotation_euler = (math.radians(50), 0.0, math.radians(35))
    return scene


def _node_material(name, leaf):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Roughness"].default_value = 0.75 if leaf else 0.9
    if leaf:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(ATLAS, check_existing=True)
        uvn = nodes.new("ShaderNodeUVMap")
        uvn.uv_map = "UVMap"
        mix = nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        links.new(uvn.outputs["UV"], tex.inputs["Vector"])
        links.new(tex.outputs["Color"], mix.inputs[6])
        links.new(attr.outputs["Color"], mix.inputs[7])
        links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.surface_render_method = "DITHERED"
    else:
        links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def make_materials():
    # Slot 0 = bark, slot 1 = leaves. The GLB keeps this order and Godot gets surfaces in the same order.
    return _node_material("Bark", False), _node_material("Leaf", True)


# ----------------------------------------------------------------------------- geometry helpers

def tube(bm, pts, radii, sides, mat, colour_of):
    """Open tube along pts with capped ends. colour_of(frac) gives the RGBA vertex colour (frac 0 base, 1 tip)."""
    rings = []
    n = len(pts)
    col = bm.verts.layers.float_color.get("Col")
    for i, p in enumerate(pts):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == n - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        t.normalize()
        ref = Vector((1.0, 0.0, 0.0)) if abs(t.x) < 0.9 else Vector((0.0, 1.0, 0.0))
        u = t.cross(ref)
        u.normalize()
        v = t.cross(u)
        v.normalize()
        ring = []
        for k in range(sides):
            a = 2.0 * math.pi * k / sides
            vert = bm.verts.new(p + (u * math.cos(a) + v * math.sin(a)) * radii[i])
            vert[col] = colour_of(i / float(n - 1))
            ring.append(vert)
        rings.append(ring)
    for i in range(n - 1):
        for k in range(sides):
            a, b = rings[i][k], rings[i][(k + 1) % sides]
            c, d = rings[i + 1][(k + 1) % sides], rings[i + 1][k]
            bm.faces.new((a, b, c, d)).material_index = mat
    bm.faces.new(rings[0]).material_index = mat
    bm.faces.new(rings[-1]).material_index = mat


def bark_colour(rgb, mottle, rnd):
    k = 1.0 + rnd.uniform(-mottle, mottle)
    r, g, b = (c * k for c in rgb)

    def colour_of(frac):
        f = 0.55 + 0.45 * frac  # darker at the base
        return (r * f, g * f, b * f, 1.0)
    return colour_of


def wood(bm, sp, rnd, sides, seg, nbr, twigs):
    """Trunk, main branches and twigs (bark slot 0)."""
    th, r0 = sp["trunk_h"], sp["trunk_r"]
    tube(bm, [Vector((rnd.uniform(-0.04, 0.04), rnd.uniform(-0.04, 0.04), th * k / seg)) for k in range(seg + 1)],
         [r0 * (1.0 - 0.35 * k / seg) for k in range(seg + 1)], sides, 0, bark_colour(sp["bark"], sp["mottle"], rnd))
    for _ in range(nbr):
        z0 = th * rnd.uniform(0.55, 0.95) if th > 1.0 else th * rnd.uniform(0.3, 0.7)
        yaw = rnd.uniform(0.0, 2.0 * math.pi)
        pitch = math.radians(rnd.uniform(28.0, 62.0))
        d = Vector((math.cos(yaw) * math.cos(pitch), math.sin(yaw) * math.cos(pitch), math.sin(pitch)))
        length = sp["branch_len"] * rnd.uniform(0.75, 1.1)
        bend = Vector((rnd.uniform(-0.15, 0.15), rnd.uniform(-0.15, 0.15), rnd.uniform(0.0, 0.2))) * length
        start = Vector((0.0, 0.0, z0))

        def point(t, s0=start, dd=d, ln=length, bd=bend):
            return s0 + dd * (ln * t) + bd * math.sin(math.pi * t)
        pts = [point(k / float(seg)) for k in range(seg + 1)]
        radii = [r0 * 0.75 * (1.0 - 0.7 * k / seg) for k in range(seg + 1)]
        tube(bm, pts, radii, sides, 0, bark_colour(sp["bark"], sp["mottle"], rnd))
        for _ in range(twigs):
            t0 = rnd.uniform(0.4, 0.8)
            base = point(t0)
            d2 = (d + Vector((rnd.uniform(-0.8, 0.8), rnd.uniform(-0.8, 0.8), rnd.uniform(-0.2, 0.6)))).normalized()
            tl = length * 0.45
            tpts = [base + d2 * (tl * k / 2.0) for k in range(3)]
            tube(bm, tpts, [r0 * 0.3, r0 * 0.2, r0 * 0.05], max(4, sides - 2), 0, bark_colour(sp["bark"], sp["mottle"], rnd))


def ao_of(sp, rnd):
    """Vertex colour: dark deep inside the crown and under it, lighter at the outer shell and on top."""
    cy, rx, rz = sp["cy"], sp["crown_r"], sp["crown_rz"]

    def ao(p):
        rel = p - Vector((0.0, 0.0, cy))
        rr = math.sqrt((rel.x / rx) ** 2 + (rel.y / rx) ** 2 + (rel.z / rz) ** 2)
        inner = min(1.0, max(0.0, (rr - 0.3) / 0.7))
        under = min(1.0, max(0.0, -rel.z / rz))
        top = min(1.0, max(0.0, rel.z / rz))
        v = (0.26 + 0.74 * inner) * (1.0 - 0.34 * under) * (0.9 + 0.1 * top) * (0.95 + 0.05 * rnd.random())
        tint = rnd.uniform(-0.04, 0.04)
        return (min(1.0, v * (1.0 + tint)), min(1.0, v), min(1.0, v * (1.0 - tint)), 1.0)
    return ao


def card(bm, centre, rot, hw, hh, key, rnd, ao):
    """One leaf card: quad in the local XZ plane, rotated by rot, UV into the species' atlas quadrant."""
    uv_layer = bm.loops.layers.uv.get("UVMap")
    u0, v0 = QUADRANT[key]
    jit = rnd.uniform(0.0, 0.02)
    corners = [Vector((-hw, 0.0, -hh)), Vector((hw, 0.0, -hh)), Vector((hw, 0.0, hh)), Vector((-hw, 0.0, hh))]
    uvs = [(u0 + jit, v0 + jit), (u0 + 0.5 - jit, v0 + jit), (u0 + 0.5 - jit, v0 + 0.5 - jit), (u0 + jit, v0 + 0.5 - jit)]
    verts = []
    col = bm.verts.layers.float_color.get("Col")
    for c in corners:
        p = centre + rot @ c
        vert = bm.verts.new(p)
        vert[col] = ao(p)
        verts.append(vert)
    face = bm.faces.new(verts)
    face.material_index = 1
    for loop, uv in zip(face.loops, uvs):
        loop[uv_layer].uv = uv


def crown(bm, sp, rnd, count, lod):
    """Leaf-cluster cards. LOD0: crossed pair per cluster (4 tris). LOD1: one card per cluster (2 tris)."""
    ao = ao_of(sp, rnd)
    hw, hh = sp["card"]
    scale = 1.0 if lod == 0 else 1.2
    for _ in range(count):
        v = Vector((rnd.gauss(0.0, 1.0), rnd.gauss(0.0, 1.0), rnd.gauss(0.0, 1.0)))
        v.normalize()
        f = 0.35 + 0.65 * rnd.random() ** 0.6
        centre = Vector((v.x * sp["crown_r"] * f, v.y * sp["crown_r"] * f, sp["cy"] + v.z * sp["crown_rz"] * f))
        yaw = rnd.uniform(0.0, 2.0 * math.pi)
        tilt = rnd.uniform(-0.6, 0.6)
        turns = (0.0, math.pi / 2.0) if lod == 0 else (0.0,)
        for dy in turns:
            rot = Matrix.Rotation(yaw + dy, 4, "Z") @ Matrix.Rotation(tilt, 4, "X")
            card(bm, centre, rot, hw * scale, hh * scale, sp["key"], rnd, ao)


def impostor_cards(bm, sp):
    """LOD2: two crossed cards that span the square the impostor was rendered in (side S = max(width, height))."""
    h = sp["height"]
    s = max(2.0 * (sp["crown_r"] + 0.8), h)
    z0, z1 = h * 0.5 - s * 0.5, h * 0.5 + s * 0.5
    col = bm.verts.layers.float_color.get("Col")
    uv_layer = bm.loops.layers.uv.get("UVMap")
    white = (1.0, 1.0, 1.0, 1.0)
    # card A in the XZ plane (seen from -Y): left edge u=0, right edge u=0.5
    # card B in the YZ plane (seen from -X): image right is -Y, so y=+s/2 is u=0.5 and y=-s/2 is u=1
    cards = [
        ([Vector((-s * 0.5, 0.0, z0)), Vector((s * 0.5, 0.0, z0)), Vector((s * 0.5, 0.0, z1)), Vector((-s * 0.5, 0.0, z1))],
         [(0.0, 0.0), (0.5, 0.0), (0.5, 1.0), (0.0, 1.0)]),
        ([Vector((0.0, s * 0.5, z0)), Vector((0.0, -s * 0.5, z0)), Vector((0.0, -s * 0.5, z1)), Vector((0.0, s * 0.5, z1))],
         [(0.5, 0.0), (1.0, 0.0), (1.0, 1.0), (0.5, 1.0)]),
    ]
    for pts, uvs in cards:
        verts = []
        for p in pts:
            vert = bm.verts.new(p)
            vert[col] = white
            verts.append(vert)
        face = bm.faces.new(verts)
        face.material_index = 0
        for loop, uv in zip(face.loops, uvs):
            loop[uv_layer].uv = uv


def make_object(name, bm, bark, leaf):
    me = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    # The exporter writes COLOR_0 from the active layer; keep only "Col" (bark tone and fake AO), otherwise
    # Godot gets a default white COLOR_0 and the baked colours land in COLOR_1.
    ca = me.color_attributes
    for a in [a for a in ca if a.name != "Col"]:
        ca.remove(a)
    assert ca.get("Col") is not None, "%s lost its Col colour layer" % name
    ca.active_color_name = "Col"
    ca.render_color_index = ca.find("Col")
    me.materials.append(bark)
    me.materials.append(leaf)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def export_glb(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
        export_image_format="NONE", export_materials="EXPORT", export_vertex_color="ACTIVE",
        export_cameras=False, export_lights=False, export_extras=False)


def new_bm():
    bm = bmesh.new()
    bm.verts.layers.float_color.new("Col")
    bm.loops.layers.uv.new("UVMap")
    return bm


def render_view(scene, loc, rot, ortho, path):
    cam_data = bpy.data.cameras.new("ImpostorCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho
    cam = bpy.data.objects.new("ImpostorCam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = loc
    cam.rotation_euler = rot
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)


def compose(path_a, path_b, out_path):
    ia = bpy.data.images.load(path_a, check_existing=False)
    ib = bpy.data.images.load(path_b, check_existing=False)
    w, h = ia.size
    a = np.empty(w * h * 4, dtype=np.float32)
    b = np.empty(w * h * 4, dtype=np.float32)
    ia.pixels.foreach_get(a)
    ib.pixels.foreach_get(b)
    comb = np.concatenate([a.reshape(h, w, 4), b.reshape(h, w, 4)], axis=1)
    img = bpy.data.images.new("ImpostorAtlas", width=2 * w, height=h, alpha=True)
    img.pixels.foreach_set(comb.ravel())
    img.filepath_raw = out_path
    img.file_format = "PNG"
    img.save()
    for im in (ia, ib, img):
        bpy.data.images.remove(im)


def render_impostor(scene, sp, key, obj0):
    h = sp["height"]
    s = max(2.0 * (sp["crown_r"] + 0.8), h)
    a_path = os.path.join(RENDERS, "%s_front.png" % key)
    b_path = os.path.join(RENDERS, "%s_side.png" % key)
    render_view(scene, Vector((0.0, -30.0, h * 0.5)), (math.radians(90.0), 0.0, 0.0), s, a_path)
    render_view(scene, Vector((-30.0, 0.0, h * 0.5)), (math.radians(90.0), 0.0, math.radians(-90.0)), s, b_path)
    compose(a_path, b_path, os.path.join(OUT_DIR, "impostor_%s.png" % key))


def build_species(scene, key, sp, bark, leaf, report):
    sp["key"] = key
    rnd = random.Random(sp["seed"])
    # LOD0: full wood, crossed leaf cards. Rendered for the impostor before it is removed.
    bm = new_bm()
    wood(bm, sp, rnd, sides=7, seg=4, nbr=sp["branches"], twigs=2)
    crown(bm, sp, rnd, sp["clusters0"], 0)
    obj0 = make_object("tree_%s_lod0" % key, bm, bark, leaf)
    tris0 = tri_count(obj0)
    assert tris0 <= TRI_LIMIT[0], "%s LOD0 %d tris" % (key, tris0)
    export_glb(obj0, os.path.join(OUT_DIR, "tree_%s_lod0.glb" % key))
    render_impostor(scene, sp, key, obj0)
    bpy.data.objects.remove(obj0, do_unlink=True)

    # LOD1: slim wood, one card per cluster
    bm = new_bm()
    wood(bm, sp, rnd, sides=5, seg=2, nbr=3, twigs=0)
    crown(bm, sp, rnd, sp["clusters1"], 1)
    obj1 = make_object("tree_%s_lod1" % key, bm, bark, leaf)
    tris1 = tri_count(obj1)
    assert tris1 <= TRI_LIMIT[1], "%s LOD1 %d tris" % (key, tris1)
    export_glb(obj1, os.path.join(OUT_DIR, "tree_%s_lod1.glb" % key))
    bpy.data.objects.remove(obj1, do_unlink=True)

    # LOD2: two crossed impostor cards, leaf slot only
    bm = new_bm()
    impostor_cards(bm, sp)
    obj2 = make_object("tree_%s_lod2" % key, bm, bark, leaf)
    tris2 = tri_count(obj2)
    assert tris2 <= TRI_LIMIT[2], "%s LOD2 %d tris" % (key, tris2)
    export_glb(obj2, os.path.join(OUT_DIR, "tree_%s_lod2.glb" % key))
    bpy.data.objects.remove(obj2, do_unlink=True)

    report[key] = {"lod0_tris": tris0, "lod1_tris": tris1, "lod2_tris": tris2, "height_m": sp["height"]}
    log(key, report[key])


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(RENDERS, exist_ok=True)
    if not os.path.isfile(ATLAS):
        raise SystemExit("leaf_atlas.png missing: run gen_leaf_atlas.py first")
    scene = setup_scene()
    bark, leaf = make_materials()
    report = {}
    for key, sp in SPECIES.items():
        build_species(scene, key, dict(sp), bark, leaf, report)
    import json
    with open(os.path.join(HERE, "out", "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    log("done")


if __name__ == "__main__":
    main()
