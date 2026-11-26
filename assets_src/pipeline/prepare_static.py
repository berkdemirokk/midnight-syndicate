"""Turns a CC BY vinish.dev building (shop house or mansion) into the street-front contract: <id>_lod0.glb, <id>_lod1.glb
and <id>.json (size and surface counts) for game/world/street_fronts/street_fronts.gd.

Run (Blender, headless, idempotent):
  blender.exe -b --factory-startup -P assets_src/pipeline/prepare_static.py -- <source.glb> <asset_id> <out_dir> [--config=<json>]
Default config: assets_src/pipeline/static_configs/<asset_id>.json.

Convention (every asset, kept for all of them): after the export the FRONT of the building faces -Z in Godot (the street
side), its origin is the middle of the front edge on the ground (X centred on the front wall, Y = 0 at the front wall,
Z = 0 at the ground) and the building stands on the +Z side of its origin. Blender +Y is the front here (glTF export maps
Blender +Y to Godot -Z). The front is found by the area of the shop glass, doors, awnings and signs on each side, or set
with "front": "+Y" / "-Y" / "+X" / "-X" (Blender axes, source frame) in the config.

Materials: every untextured or dropped-to-flat material becomes ONE material "M_Flat" whose colour is the albedo baked into
COLOR_0 (times the baked AO), so the engine multiplies nothing else. Glass becomes ONE material "M_Glass". At most
keep_textured materials keep their textures (their names start with "T_"); signs are always among them. LOD0 keeps the
source triangles (decimated only above lod0_max_tris), LOD1 keeps at most lod1_tris triangles and has two surfaces only
(M_Flat, M_Glass): the textures are averaged into the vertex colours.

Triangle and surface counts are printed; the engine side reads them back from the GLB files.
"""
import json
import math
import os
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bake_vertex_ao as ao  # noqa: E402  (AO bake and the glTF AO export helpers, shared with the other kits)

# Furniture, food, interior and street clutter that vinish.dev puts in front of or behind the glass: it is dropped.
DROP_PREFIXES = ("Interior", "Table", "Chair", "Cake", "Bun_", "Icing", "Choc", "Cherry", "Cup_", "Cap_", "Bottle",
                 "Pole_", "Crate", "Apple", "Orange", "Lemon", "Lime", "Pear", "Can_", "Box_", "Book_", "Pages", "Mirror",
                 "Leather", "Chalkboard", "Tyre", "Wood_Bench", "Hedge", "Paving", "Kerb", "Cross_Green", "Terracotta",
                 "Flower_", "Bloom")  # the florist's display buckets read as blobs on the pavement at 300 m scale
FRONT_WEIGHTS = (("Shop_Glass", 5.0), ("Door", 5.0), ("Awning", 5.0), ("Sign", 4.0), ("Display", 3.0), ("Glass", 1.0))
DIRS = {"+X": Vector((1, 0, 0)), "-X": Vector((-1, 0, 0)), "+Y": Vector((0, 1, 0)), "-Y": Vector((0, -1, 0))}
COPYRIGHT_FMT = '"%s" by vinish.dev (https://vinish.dev/free-3d-models/), CC BY 4.0, modified'
FLAT = "M_Flat"
GLASS = "M_Glass"


def arg_value(argv, key, default=None):
    for a in argv:
        if a.startswith("--%s=" % key):
            return a.split("=", 1)[1]
    return default


def mat_name(me, index):
    if 0 <= index < len(me.materials) and me.materials[index] is not None:
        return me.materials[index].name
    return "-"


def is_glass(name):
    return "Glass" in name


def front_weight(name):
    best = 0.0
    for key, w in FRONT_WEIGHTS:
        if key in name:
            best = max(best, w)
    return best


def _hist(obj):
    h = {}
    for p in obj.data.polygons:
        h[p.material_index] = h.get(p.material_index, 0) + 1
    return h


def tri_count(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


def mat_info(mat):
    """(image or None, base colour rgb) of a glTF-imported material."""
    tex, col = None, (0.8, 0.8, 0.8)
    if mat is None or not mat.use_nodes or mat.node_tree is None:
        return tex, col
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return tex, col
    base = bsdf.inputs["Base Color"]
    col = tuple(float(c) for c in base.default_value[:3])
    if base.is_linked:
        src = base.links[0].from_node
        if src.type == "TEX_IMAGE" and src.image is not None:
            tex = src.image
    return tex, col


def avg_rgb(img):
    import numpy as np
    buf = np.empty(len(img.pixels), dtype=np.float32)
    img.pixels.foreach_get(buf)
    px = buf.reshape(-1, img.channels)[:, :3]
    m = px.mean(axis=0)
    return (float(m[0]), float(m[1]), float(m[2]))


def join_meshes(src_path, asset_id):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src_path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit("no mesh in " + src_path)
    mws = [o.matrix_world.copy() for o in meshes]
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    for o, mw in zip(meshes, mws):
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = asset_id
    obj.data.name = asset_id
    return obj


def pick_front(me, pref):
    if pref in DIRS:
        return pref, {}
    bm = bmesh.new()
    bm.from_mesh(me)
    score = {k: 0.0 for k in DIRS}
    for f in bm.faces:
        w = front_weight(mat_name(me, f.material_index))
        if w <= 0.0:
            continue
        for k, d in DIRS.items():
            if f.normal.dot(d) > 0.7:
                score[k] += f.calc_area() * w
    bm.free()
    return max(score, key=score.get), score


def orient(obj, pref):
    """Rotates about Z so the front is Blender +Y, then puts the front wall at Y = 0 with the ground at Z = 0 and the
    middle of the front wall at X = 0."""
    me = obj.data
    front, score = pick_front(me, pref)
    d = DIRS[front]
    theta = math.pi / 2.0 - math.atan2(d.y, d.x)
    me.transform(Matrix.Rotation(theta, 4, "Z"))
    walls = []  # (area, centre y, [x]) of the upright, non-glass faces that face the street
    for p in me.polygons:
        if p.normal.y > 0.9 and p.area >= 1.0 and not is_glass(mat_name(me, p.material_index)):
            walls.append((p.area, p.center.y, p))
    if not walls:
        raise SystemExit("no front wall found facing " + front)
    walls.sort(key=lambda t: t[1])
    half = sum(a for a, _, _ in walls) / 2.0
    acc, front_y = 0.0, walls[0][1]
    for a, y, _ in walls:
        acc += a
        front_y = y
        if acc >= half:
            break
    xs = []
    for _, _, p in walls:
        for vi in p.vertices:
            v = me.vertices[vi].co
            if abs(v.y - front_y) < 0.5:
                xs.append(v.x)
    x_mid = (min(xs) + max(xs)) / 2.0
    z_min = min(v.co.z for v in me.vertices)
    me.transform(Matrix.Translation(Vector((-x_mid, -front_y, -z_min))))
    print("FRONT %s (scores %s) theta %.1f deg, front wall y %.3f, x mid %.3f" % (
        front, {k: round(v, 1) for k, v in score.items()}, math.degrees(theta), front_y, x_mid))
    return front


def drop_clutter(obj, extra_materials=()):
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    # extra_materials: per-asset config "drop_materials" (roof flues and other props found by material name)
    doomed = [f for f in bm.faces if mat_name(me, f.material_index).startswith(DROP_PREFIXES)
              or mat_name(me, f.material_index) in extra_materials]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(me)
    bm.free()
    me.update()


def set_sign_images(obj, cfg, cfg_dir):
    """Replaces the English sign texture of a material by the Turkish PNG named in the config."""
    for mat_key, rel in cfg.get("signs", {}).items():
        mat = next((m for m in obj.data.materials if m is not None and m.name == mat_key), None)
        if mat is None:
            print("SIGN missing material", mat_key)
            continue
        new_img = bpy.data.images.load(os.path.normpath(os.path.join(cfg_dir, rel)), check_existing=False)
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE":
                n.image = new_img
        print("SIGN", mat_key, "->", rel)


def prepare_materials(obj, keep_textured):
    """Renames the glass and the kept textured materials, returns (albedo of every flat material, kept texture names)."""
    me = obj.data
    glass_idx = [i for i, m in enumerate(me.materials) if m is not None and is_glass(m.name)]
    if glass_idx:
        keep = glass_idx[0]
        for i in glass_idx[1:]:
            for p in me.polygons:
                if p.material_index == i:
                    p.material_index = keep
        me.materials[keep].name = GLASS
    area = {}
    for p in me.polygons:
        n = mat_name(me, p.material_index)
        area[n] = area.get(n, 0.0) + p.area
    textured = []
    albedo = {}
    for i, m in enumerate(me.materials):
        if m is None or m.name == GLASS or m.name not in area:
            continue
        tex, col = mat_info(m)
        if tex is None:
            albedo[m.name] = col
        else:
            textured.append((0 if "Sign" in m.name else 1, -area[m.name], m.name, tex, col))
    textured.sort()
    kept = set()
    for _, _, name, tex, col in textured[:keep_textured]:
        kept.add(name)
    for _, _, name, tex, col in textured:
        if name in kept:
            continue
        albedo[name] = avg_rgb(tex)
    for name in kept:
        m = me.materials[[mm.name if mm else None for mm in me.materials].index(name)]
        m.name = "T_" + name
    return albedo, {"T_" + n for n in kept}


def decimate_to(obj, target):
    """Collapse decimation with triangulated collapses, in passes: one pass at the full ratio stalls at about 2.6k
    triangles on the mansions (open window and wall islands), passes at 30 % and then the rest of the way do not."""
    tris = tri_count(obj.data)
    if tris <= target:
        return tris
    bpy.context.view_layer.objects.active = obj
    for _ in range(8):
        cur = tri_count(obj.data)
        if cur <= target:
            break
        mod = obj.modifiers.new("decimate", "DECIMATE")
        mod.ratio = min(0.6, max(0.3, target / float(cur)))
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
        if tri_count(obj.data) > cur * 0.97:  # no progress: stop instead of looping
            break
    return tri_count(obj.data)


def finalize(obj, albedo, keep_tex):
    """After the AO bake: flat faces get albedo * AO, the glass stays white, kept textures keep AO only; then the
    material slots are rebuilt as M_Flat, M_Glass and the kept T_ materials."""
    me = obj.data
    col = me.color_attributes.get(ao.COLOR_NAME)
    if col is None:
        raise SystemExit("AO attribute missing")
    flat_idx = len(me.materials)
    values = [0.0] * (len(me.loops) * 4)
    col.data.foreach_get("color", values)
    flat_mat = bpy.data.materials.get(FLAT)
    if flat_mat is None:
        flat_mat = bpy.data.materials.new(FLAT)
        flat_mat.use_nodes = True
        flat_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1, 1, 1, 1)
        flat_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    glass_mat = bpy.data.materials.get(GLASS)
    if glass_mat is None:
        glass_mat = bpy.data.materials.new(GLASS)
        glass_mat.use_nodes = True
    slots = [flat_mat, glass_mat]
    slot_of = {}
    for name in keep_tex:
        m = next(mm for mm in me.materials if mm is not None and mm.name == name)
        slot_of[name] = len(slots)
        slots.append(m)
    for p in me.polygons:
        name = mat_name(me, p.material_index)
        if name == GLASS:
            p.material_index = 1
            continue
        if name in slot_of:
            p.material_index = slot_of[name]
            continue
        rgb = albedo.get(name, (0.8, 0.8, 0.8))
        for li in p.loop_indices:
            base = li * 4
            for c in range(3):
                values[base + c] *= rgb[c]
        p.material_index = 0
    col.data.foreach_set("color", values)
    idx = [p.material_index for p in me.polygons]  # clear() resets the polygon slots, so they are written back
    me.materials.clear()
    for m in slots:
        me.materials.append(m)
    for p, i in zip(me.polygons, idx):
        p.material_index = i if i < len(slots) else 0
    me.update()
    return len(slots)


def load_glb_mesh_stats(path):
    with open(path, "rb") as fh:
        data = fh.read()
    _m, _v, length = struct.unpack_from("<III", data, 0)
    off, doc = 12, None
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        if ctype == 0x4E4F534A:
            doc = json.loads(data[off + 8: off + 8 + clen].decode("utf-8"))
        off += 8 + clen
    tris, mats = 0, set()
    for mesh in doc.get("meshes", []):
        for prim in mesh["primitives"]:
            if "indices" in prim:
                tris += doc["accessors"][prim["indices"]]["count"] // 3
            mats.add(doc["materials"][prim["material"]]["name"] if "material" in prim else "-")
    return tris, sorted(mats)


def glb_copyright_ok(path, text):
    """export_copyright writes the asset.copyright line; this reads it back."""
    with open(path, "rb") as fh:
        data = fh.read()
    _m, _v, length = struct.unpack_from("<III", data, 0)
    clen, ctype = struct.unpack_from("<II", data, 12)
    doc = json.loads(data[20: 20 + clen].decode("utf-8"))
    return doc.get("asset", {}).get("copyright", "") == text


def export_glb(path, obj, copyright_text):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_copyright=copyright_text,
        export_materials="EXPORT", export_image_format="AUTO", export_extras=False, export_apply=False,
        export_yup=True, export_cameras=False, export_lights=False, export_vertex_color="ACTIVE",
        export_active_vertex_color_when_no_material=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    src, asset_id, out_dir = argv[0], argv[1], argv[2]
    cfg_path = arg_value(argv, "config", os.path.join(HERE, "static_configs", asset_id + ".json"))
    cfg = json.load(open(cfg_path, encoding="utf-8"))
    cfg_dir = os.path.dirname(os.path.abspath(cfg_path))
    os.makedirs(out_dir, exist_ok=True)
    obj = join_meshes(src, asset_id)
    front = orient(obj, cfg.get("front", "auto"))
    drop_clutter(obj, tuple(cfg.get("drop_materials", [])))
    set_sign_images(obj, cfg, cfg_dir)
    albedo, keep_tex = prepare_materials(obj, int(cfg.get("keep_textured", 6)))
    lod1_src = obj.copy()
    lod1_src.data = obj.data.copy()
    bpy.context.scene.collection.objects.link(lod1_src)
    # LOD0: source triangles, decimated only above lod0_max_tris, AO with the subdivision of the kit
    tris0 = decimate_to(obj, int(cfg.get("lod0_max_tris", 30000)))
    ao.bake_ao([obj], cell_m=float(cfg.get("cell_m", 2.5)))
    surf0 = finalize(obj, albedo, keep_tex)
    # LOD1: decimated copy, AO without subdivision, textures averaged into the colours
    lod1_tris_target = int(cfg.get("lod1_tris", 2500))
    decimate_to(lod1_src, lod1_tris_target)
    ao.bake_ao([lod1_src], cell_m=None)
    albedo1 = dict(albedo)  # textures of the kept materials are averaged into their colours for LOD1
    for name in keep_tex:
        m = bpy.data.materials[name]
        tex = next(n.image for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image is not None)
        albedo1[name] = avg_rgb(tex)
    surf1 = finalize(lod1_src, albedo1, set())
    # mirror: a cheaper copy of LOD1 for the wet-road mirror only (drawn 0 to 55 m there, its triangles count twice)
    mirror = lod1_src.copy()
    mirror.data = lod1_src.data.copy()
    bpy.context.scene.collection.objects.link(mirror)
    decimate_to(mirror, int(cfg.get("mirror_tris", 800)))
    # textures: 1024 px at most
    for img in bpy.data.images:
        if img.size[0] > 1024 or img.size[1] > 1024:
            s = 1024.0 / max(img.size)
            img.scale(max(1, int(img.size[0] * s)), max(1, int(img.size[1] * s)))
    lod0_name = os.path.join(out_dir, asset_id + "_lod0.glb")
    lod1_name = os.path.join(out_dir, asset_id + "_lod1.glb")
    copyright_text = COPYRIGHT_FMT % cfg["title"]
    lod1_src.name = asset_id + "_lod1"
    lod1_src.data.name = asset_id + "_lod1"
    mirror_name = os.path.join(out_dir, asset_id + "_mirror.glb")
    mirror.name = asset_id + "_mirror"
    mirror.data.name = asset_id + "_mirror"
    export_glb(lod0_name, obj, copyright_text)
    export_glb(lod1_name, lod1_src, copyright_text)
    export_glb(mirror_name, mirror, copyright_text)
    t0, m0 = load_glb_mesh_stats(lod0_name)
    t1, m1 = load_glb_mesh_stats(lod1_name)
    tm, mm = load_glb_mesh_stats(mirror_name)
    ok0 = all(glb_copyright_ok(p, copyright_text) for p in (lod0_name, lod1_name, mirror_name))
    dims = obj.dimensions
    meta = dict(id=asset_id, front=front, width_m=round(dims.x, 3), depth_m=round(dims.y, 3), height_m=round(dims.z, 3),
                lod0_tris=t0, lod1_tris=t1, mirror_tris=tm, lod0_surfaces=m0, lod1_surfaces=m1, mirror_surfaces=mm,
                copyright=copyright_text)
    with open(os.path.join(out_dir, asset_id + ".json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=1, ensure_ascii=False)
    print("RESULT", json.dumps(meta, ensure_ascii=False))
    print("CHECK lod0 surfaces %d (%s) tris %d; lod1 surfaces %d (%s) tris %d; copyright ok %s" % (
        len(m0), ",".join(m0), t0, len(m1), ",".join(m1), t1, ok0))
    print("CHECK kept textured %s; source tris before decimation %d, after %d; surfaces built %d / %d" % (
        sorted(keep_tex), tris0, tri_count(obj.data), surf0, surf1))
    hist = {}
    for p in obj.data.polygons:
        hist[p.material_index] = hist.get(p.material_index, 0) + 1
    print("CHECK lod0 polygons per slot %s slots %s" % (hist, [m.name for m in obj.data.materials]))
    if len(m0) > 8 or len(m1) > 2:
        raise SystemExit("surface budget exceeded")


if __name__ == "__main__":
    main()
