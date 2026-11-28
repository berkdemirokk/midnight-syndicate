"""Street trees from licensed models: vinish.dev, CC BY 4.0 (Blender 5.3, deterministic, no network).

Run once per species, after the source GLB is in assets_src/third_party/vinish_env/:
  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b --factory-startup -P prepare_licensed_trees.py -- <species> <tmp_dir>
  species: plane | judas | cypress | street   (tmp_dir: scratch folder for debug renders, outside the repo)

Writes into game/assets/world/kits/trees/:
  tree_<sp>_lod0.glb  surface 0 = bark, surface 1 = leaves; bark decimated, every leaf card kept
  tree_<sp>_lod1.glb  same surface order; fewer bark triangles and whole leaf cards removed
  tree_<sp>_lod2.glb  one surface, two crossed cards (4 tris) UV-mapped into impostor_<sp>.png
  leaf_<sp>.png       the model's own leaf texture, alpha kept (magnolia: blossom and leaf side by side)
  bark_<sp>.png       the model's own bark texture (tiled UVs; the engine material samples it)
  impostor_<sp>.png   512x256: LOD0 rendered unlit from -Y (left half) and from -X (right half), alpha kept
Vertex colour RGB = baked ambient occlusion (dark under and inside the crown). The LICENSED_TREE line feeds greenery.gd.
"""
import bmesh
import bpy
import json
import math
import os
import random
import sys

import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SRC_DIR = os.path.join(REPO, "assets_src", "third_party", "vinish_env")
OUT_DIR = os.path.join(REPO, "game", "assets", "world", "kits", "trees")
TRI_LIMIT = {0: 3500, 1: 900, 2: 4}
RENDER_PX = 256  # impostor cell: 256 per crossed card (was 512)

SPECIES = {
    # target_h: height in metres after scaling (greenery draws 0.9-1.15 x around the plant's street size)
    # bark0 / bark1: bark triangle budget at LOD0 / LOD1; keep1: share of leaf cards kept at LOD1
    "plane": dict(src="plane-tree.glb", title="Plane Tree", target_h=12.0, drop_mats=("Seed",), drop_objs=(),
                  bark0=2000, bark1=400, keep1=0.3, seed=11),
    "judas": dict(src="magnolia-tree.glb", title="Magnolia Tree", target_h=5.6, drop_mats=(), drop_objs=(),
                  bark0=2500, bark1=350, keep1=0.5, seed=23),
    "cypress": dict(src="italian-cypress.glb", title="Italian Cypress", target_h=10.0, drop_mats=(), drop_objs=(),
                    bark0=900, bark1=300, keep1=0.4, seed=37),
    "street": dict(src="young-staked-tree.glb", title="Young Staked Tree", target_h=5.0, drop_mats=(),
                   drop_objs=("Stakes",), bark0=900, bark1=300, keep1=0.6, seed=41),
}


def log(*a):
    print("[licensed-trees]", *a)


def clamp01(v):
    return min(1.0, max(0.0, v))


def credit(cfg):
    return '"%s" by vinish.dev (https://vinish.dev/free-3d-models/), CC BY 4.0, modified' % cfg["title"]


# ----------------------------------------------------------------------------- source

def texture_of(mat_name):
    """The model's own texture of a material: the first image node that is not a normal map."""
    for n in bpy.data.materials[mat_name].node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image and "normal" not in n.image.name.lower():
            return n.image
    raise SystemExit("no texture in material " + mat_name)


def gather(objs, cfg):
    """Triangles as lists of 3 (world position, uv) corners. Bark and leaves kept apart; dropped parts skipped."""
    bark, leaf, leaf_names = [], [], []
    for o in objs:
        if o.name in cfg["drop_objs"]:
            continue
        me = o.data
        uvl = me.uv_layers.active.data
        me.calc_loop_triangles()
        for lt in me.loop_triangles:
            slot = me.materials[lt.material_index]
            mat = slot.name if slot else ""
            if any(d in mat for d in cfg["drop_mats"]):
                continue
            corners = [(o.matrix_world @ me.vertices[lt.vertices[k]].co, Vector(uvl[lt.loops[k]].uv)) for k in range(3)]
            if "Bark" in mat:
                bark.append(corners)
            else:
                if mat not in leaf_names:
                    leaf_names.append(mat)
                leaf.append((leaf_names.index(mat), corners))
    return bark, leaf, leaf_names


def image_array(im):
    px = np.empty(im.size[0] * im.size[1] * 4, dtype=np.float32)
    im.pixels.foreach_get(px)
    return px.reshape(im.size[1], im.size[0], 4)


def save_png(arr, path):
    h, w = arr.shape[0], arr.shape[1]
    im = bpy.data.images.new("export_tmp", width=w, height=h, alpha=True)
    im.pixels.foreach_set(np.ascontiguousarray(arr, dtype=np.float32).ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


# ----------------------------------------------------------------------------- geometry

def make_bm(tris):
    """One bmesh from triangles; coincident corners welded, UVs kept per loop."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    for corners in tris:
        vs = [bm.verts.new(co) for co, _ in corners]
        try:
            f = bm.faces.new(vs)
        except ValueError:
            continue
        for loop, (_, t) in zip(f.loops, corners):
            loop[uv].uv = t
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    degenerate = [f for f in bm.faces if f.calc_area() < 1e-10]
    bmesh.ops.delete(bm, geom=degenerate, context="FACES")
    bm.verts.index_update()
    bm.faces.index_update()
    return bm


def card_islands(bm):
    """Leaf cards: faces linked by a shared vertex form one card (the models build each card on its own corners)."""
    bm.verts.index_update()
    bm.faces.index_update()
    parent = list(range(len(bm.faces)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    seen = {}
    for f in bm.faces:
        for v in f.verts:
            if v.index in seen:
                parent[find(f.index)] = find(seen[v.index])
            else:
                seen[v.index] = f.index
    groups = {}
    for f in bm.faces:
        groups.setdefault(find(f.index), []).append(f)
    return list(groups.values())


def thin_cards(bm, keep, rng):
    """Remove whole cards at random: a kept card keeps its full shape, a removed one leaves no sliver."""
    gone = []
    for card in card_islands(bm):
        if rng.random() >= keep:
            gone.extend(card)
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bm.faces.index_update()


def bm_to_object(name, bm, mat):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def obj_tris(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def decimate_to(obj, target):
    cur = obj_tris(obj)
    if cur <= target:
        return
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = max(0.01, target / cur)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def ao_colours(me, zb, zt, rmax):
    """Vertex colour = fake AO. Leaves: dark low and inside, bright at the top and the outer edge. Bark: dark at the foot."""
    n = len(me.vertices)
    leaf_v = set()
    for poly in me.polygons:
        if poly.material_index == 1:
            leaf_v.update(poly.vertices)
    col = np.ones((n, 4), dtype=np.float32)
    for i, v in enumerate(me.vertices):
        if i in leaf_v:
            hf = clamp01((v.co.z - zb) / max(1e-4, zt - zb))
            d = clamp01(math.hypot(v.co.x, v.co.y) / max(1e-4, rmax))
            ao = 0.42 + 0.58 * clamp01(0.55 * hf + 0.45 * d)
        else:
            ao = 0.5 + 0.35 * clamp01(v.co.z / max(1e-4, zb))
        col[i, 0] = col[i, 1] = col[i, 2] = ao
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    attr.data.foreach_set("color", col.ravel())
    me.color_attributes.active_color_name = "Col"
    me.color_attributes.render_color_index = me.color_attributes.find("Col")


def export_glb(obj, path, copyright_text):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
        export_image_format="NONE", export_materials="EXPORT", export_vertex_color="ACTIVE",
        export_cameras=False, export_lights=False, export_extras=False, export_copyright=copyright_text)


def join(a, b):
    bpy.ops.object.select_all(action="DESELECT")
    a.select_set(True)
    b.select_set(True)
    bpy.context.view_layer.objects.active = a
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def lod_object(name, bark_obj, leaf_obj, bark_target, keep, seed, zb, zt, rmax):
    """Joined LOD mesh: slot 0 bark (decimated to bark_target), slot 1 leaves (keep share of the cards)."""
    bo = bark_obj.copy()
    bo.data = bark_obj.data.copy()
    bpy.context.scene.collection.objects.link(bo)
    lo = leaf_obj.copy()
    lo.data = leaf_obj.data.copy()
    bpy.context.scene.collection.objects.link(lo)
    decimate_to(bo, bark_target)
    if keep < 1.0:
        bm = bmesh.new()
        bm.from_mesh(lo.data)
        thin_cards(bm, keep, random.Random(seed))
        bm.to_mesh(lo.data)
        bm.free()
    joined = join(bo, lo)
    joined.name = name
    joined.data.name = name
    ao_colours(joined.data, zb, zt, rmax)
    return joined


# ----------------------------------------------------------------------------- impostor

def impostor_cards(bm, h, side):
    """LOD2: two crossed cards spanning the side x side square the impostor was rendered in, centred on the crown."""
    z0, z1 = h * 0.5 - side * 0.5, h * 0.5 + side * 0.5
    uv_layer = bm.loops.layers.uv.new("UVMap")
    col = bm.verts.layers.float_color.new("Col")
    white = (1.0, 1.0, 1.0, 1.0)
    # card A in the XZ plane (seen from -Y): left edge u=0, right edge u=0.5
    # card B in the YZ plane (seen from -X): image right is -Y, so y=+side/2 is u=0.5 and y=-side/2 is u=1
    cards = [
        ([Vector((-side * 0.5, 0.0, z0)), Vector((side * 0.5, 0.0, z0)), Vector((side * 0.5, 0.0, z1)), Vector((-side * 0.5, 0.0, z1))],
         [(0.0, 0.0), (0.5, 0.0), (0.5, 1.0), (0.0, 1.0)]),
        ([Vector((0.0, side * 0.5, z0)), Vector((0.0, -side * 0.5, z0)), Vector((0.0, -side * 0.5, z1)), Vector((0.0, side * 0.5, z1))],
         [(0.5, 0.0), (1.0, 0.0), (1.0, 1.0), (0.5, 1.0)]),
    ]
    for pts, uvs in cards:
        vs = []
        for p in pts:
            vert = bm.verts.new(p)
            vert[col] = white
            vs.append(vert)
        face = bm.faces.new(vs)
        face.material_index = 0
        for loop, uv in zip(face.loops, uvs):
            loop[uv_layer].uv = uv


def emission_material(name, image, alpha):
    """Unlit albedo (texture x fake AO, the same mix as foliage.gdshader) for the impostor render. The game lights the cards."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    uvn = nt.nodes.new("ShaderNodeUVMap")
    uvn.uv_map = "UVMap"
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 0.65
    nt.links.new(uvn.outputs["UV"], tex.inputs["Vector"])
    nt.links.new(tex.outputs["Color"], mix.inputs[6])
    nt.links.new(attr.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], emit.inputs["Color"])
    if alpha:
        clear = nt.nodes.new("ShaderNodeBsdfTransparent")
        shader_mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(tex.outputs["Alpha"], shader_mix.inputs["Fac"])
        nt.links.new(clear.outputs["BSDF"], shader_mix.inputs[1])
        nt.links.new(emit.outputs["Emission"], shader_mix.inputs[2])
        nt.links.new(shader_mix.outputs["Shader"], out.inputs["Surface"])
    else:
        nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


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


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.render.resolution_x = RENDER_PX
    scene.render.resolution_y = RENDER_PX
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.world = None
    return scene


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


def bmesh_of_material(obj, mat_index):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    dead = [f for f in bm.faces if f.material_index != mat_index]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    return bm


# ----------------------------------------------------------------------------- main

def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    key, tmp = argv[0], argv[1]
    cfg = SPECIES[key]
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(tmp, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC_DIR, cfg["src"]))
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bark_tris, leaf_tris, leaf_names = gather(objs, cfg)
    assert bark_tris and leaf_tris, "%s: needs bark and leaves" % key

    # Normalise: trunk foot at the origin on z = 0, height = target_h.
    zfoot = min(c[0].z for t in bark_tris for c in t)
    foot = sorted([c[0] for t in bark_tris for c in t if c[0].z < zfoot + 0.25], key=lambda p: p.x)
    fx = foot[len(foot) // 2].x
    fy = sorted(p.y for p in foot)[len(foot) // 2]
    zmax = max(c[0].z for t in bark_tris for c in t)
    zmax = max(zmax, max(c[0].z for _, t in leaf_tris for c in t))
    raw_h = zmax - zfoot
    s = cfg["target_h"] / raw_h

    def norm(p):
        return Vector(((p.x - fx) * s, (p.y - fy) * s, (p.z - zfoot) * s))

    bark_tris = [[(norm(c[0]), c[1]) for c in t] for t in bark_tris]
    leaf_tris = [(i, [(norm(c[0]), c[1]) for c in t]) for i, t in leaf_tris]
    leaf_pts = [c[0] for _, t in leaf_tris for c in t]
    zb = min(p.z for p in leaf_pts)
    zt = max(p.z for p in leaf_pts)
    rmax = max(math.hypot(p.x, p.y) for p in leaf_pts)
    radii = sorted(math.hypot(p.x, p.y) for p in leaf_pts)
    r90 = radii[int(0.9 * (len(radii) - 1))]
    height = cfg["target_h"]

    # Leaf textures: one image per leaf material, side by side in one atlas; UVs move into their cell.
    n_leaf = len(leaf_names)
    arrays = [image_array(texture_of(m)) for m in leaf_names]
    atlas = np.concatenate(arrays, axis=1) if n_leaf > 1 else arrays[0]
    save_png(atlas, os.path.join(OUT_DIR, "leaf_%s.png" % key))
    leaf_corners = []
    for idx, t in leaf_tris:
        leaf_corners.append([(co, Vector(((idx + clamp01(uv.x)) / n_leaf, clamp01(uv.y)))) for co, uv in t])

    # Bark texture: the first bark material's image. UVs are tiled and stay as the model made them.
    bark_img = None
    for o in objs:
        for m in o.data.materials:
            if m and "Bark" in m.name and bark_img is None:
                for nd in m.node_tree.nodes:
                    if nd.type == "TEX_IMAGE" and nd.image and "normal" not in nd.image.name.lower():
                        bark_img = nd.image
                        break
    assert bark_img is not None, "%s: no bark texture" % key
    save_png(image_array(bark_img), os.path.join(OUT_DIR, "bark_%s.png" % key))

    bm_bark = make_bm(bark_tris)
    bark_obj = bm_to_object("bark", bm_bark, bpy.data.materials.new("Bark"))
    bm_leaf = make_bm(leaf_corners)
    n_cards = len(card_islands(bm_leaf))
    leaf_obj = bm_to_object("leaves", bm_leaf, bpy.data.materials.new("Leaf"))
    log(key, "raw height", round(raw_h, 3), "scale", round(s, 4), "bark tris", obj_tris(bark_obj),
        "leaf tris", obj_tris(leaf_obj), "leaf cards", n_cards)

    # LOD0: bark decimated, all leaf cards.
    lod0 = lod_object("tree_%s_lod0" % key, bark_obj, leaf_obj, cfg["bark0"], 1.0, cfg["seed"], zb, zt, rmax)
    tris0 = obj_tris(lod0)
    assert tris0 <= TRI_LIMIT[0], "%s LOD0 %d tris" % (key, tris0)
    export_glb(lod0, os.path.join(OUT_DIR, "tree_%s_lod0.glb" % key), credit(cfg))

    # LOD2 impostor, rendered from LOD0 before the LOD0 object is discarded.
    side = max(2.0 * rmax * 1.03, height * 1.03)
    scene = setup_render()
    lod0.data.materials.clear()
    leaf_atlas_img = bpy.data.images.load(os.path.join(OUT_DIR, "leaf_%s.png" % key), check_existing=False)
    lod0.data.materials.append(emission_material("ImpBark", bark_img, alpha=False))
    lod0.data.materials.append(emission_material("ImpLeaf", leaf_atlas_img, alpha=True))
    a_path = os.path.join(tmp, "%s_front.png" % key)
    b_path = os.path.join(tmp, "%s_side.png" % key)
    render_view(scene, Vector((0.0, -30.0, height * 0.5)), (math.radians(90.0), 0.0, 0.0), side, a_path)
    render_view(scene, Vector((-30.0, 0.0, height * 0.5)), (math.radians(90.0), 0.0, math.radians(-90.0)), side, b_path)
    compose(a_path, b_path, os.path.join(OUT_DIR, "impostor_%s.png" % key))
    bpy.data.images.remove(leaf_atlas_img)
    bpy.data.objects.remove(lod0, do_unlink=True)

    # LOD1: slim bark, thinned cards.
    lod1 = lod_object("tree_%s_lod1" % key, bark_obj, leaf_obj, cfg["bark1"], cfg["keep1"], cfg["seed"] + 7, zb, zt, rmax)
    tris1 = obj_tris(lod1)
    assert tris1 <= TRI_LIMIT[1], "%s LOD1 %d tris" % (key, tris1)
    export_glb(lod1, os.path.join(OUT_DIR, "tree_%s_lod1.glb" % key), credit(cfg))

    # LOD2 geometry: two crossed cards, one leaf surface.
    bm2 = bmesh.new()
    impostor_cards(bm2, height, side)
    lod2_me = bpy.data.meshes.new("tree_%s_lod2" % key)
    bm2.to_mesh(lod2_me)
    bm2.free()
    lod2_me.materials.append(bpy.data.materials.new("Leaf"))
    lod2 = bpy.data.objects.new("tree_%s_lod2" % key, lod2_me)
    bpy.context.scene.collection.objects.link(lod2)
    tris2 = obj_tris(lod2)
    assert tris2 == 4, "%s LOD2 %d tris" % (key, tris2)
    export_glb(lod2, os.path.join(OUT_DIR, "tree_%s_lod2.glb" % key), credit(cfg))

    report = {"species": key, "height_m": round(height, 3), "scale": round(s, 4),
              "crown_r90_m": round(r90, 3), "crown_rmax_m": round(rmax, 3), "impostor_side_m": round(side, 3),
              "lod0_tris": tris0, "lod1_tris": tris1, "lod2_tris": tris2, "leaf_images": leaf_names,
              "leaf_atlas_px": [int(atlas.shape[1]), int(atlas.shape[0])], "leaf_cards_all": n_cards,
              "zb": round(zb, 3), "zt": round(zt, 3)}
    print("LICENSED_TREE " + json.dumps(report))


if __name__ == "__main__":
    main()
