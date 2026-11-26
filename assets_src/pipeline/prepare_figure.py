"""Turns one vinish.dev casual-people GLB into a crowd figure for the spectator crowd: LOD0 (<= 1100 triangles) and
LOD1 (<= 300) GLBs, ONE material, the albedo (sampled from the source textures at each corner) multiplied by baked
ambient occlusion in COLOR_0, feet on the ground, facing Godot -Z (Blender +Y), the source copyright kept with ", modified".

Run (Blender, headless, idempotent; one figure per run):
  blender.exe -b --factory-startup -P assets_src/pipeline/prepare_figure.py -- <source.glb> <id> <out_dir> [--lod0=1100] [--lod1=300]

Output: <out_dir>/crowd_<id>_lod0.glb and crowd_<id>_lod1.glb, plus one JSON line "RESULT {...}" on stdout.

Source convention (probed on man-in-hoodie.glb and woman-in-summer-dress.glb in Blender 5.3): one skinned body mesh in
its neutral standing pose, the body's material slots carry the textures (Face_* has the face), plus an armature and a
80-triangle helper sphere that are dropped. No bone-named mesh nodes exist in these sources, so no arm posing is done:
the figures ship in the source's neutral pose (the pose option is not implemented).
"""
import bmesh
import json
import math
import os
import struct
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from bake_vertex_ao import COLOR_NAME, bake_ao, export_glb_ao  # noqa: E402

ALBEDO = "Albedo"
FINAL = "Col"
SAMPLE_AO_FLOOR = 0.5


def arg_value(argv, key, default):
    for a in argv:
        if a.startswith("--%s=" % key):
            return a.split("=", 1)[1]
    return default


def bake_world(obj):
    """Moves the object matrix into its vertices (no operator, so no selection context is needed)."""
    mw = obj.matrix_world.copy()
    for v in obj.data.vertices:
        v.co = mw @ v.co
    obj.matrix_world = Matrix.Identity(4)


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def decimate_to(obj, target):
    """Collapse decimation, retried with a smaller ratio until the triangle count is at or under target."""
    tris0 = tri_count(obj)
    base = obj.data.copy()
    ratio = min(1.0, target / float(tris0))
    for _ in range(12):
        obj.data = base.copy()
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
        n = tri_count(obj)
        if n <= target:
            return n
        ratio *= (target / float(n)) * 0.98
    raise RuntimeError("decimate could not reach %d triangles" % target)


_IMG_CACHE = {}


def _pixels(img):
    key = img.name
    if key not in _IMG_CACHE:
        w, h = img.size
        _IMG_CACHE[key] = (w, h, img.pixels[:])
    return _IMG_CACHE[key]


def _base_source(mat):
    """(image, tint) for the Principled Base Color of a material, or (None, rgb default) when it has no texture.
    The glTF importer puts a MIX (multiply) node between the texture and the socket: its unlinked colour is the tint."""
    if mat is None or not mat.use_nodes:
        return None, (0.8, 0.8, 0.8)
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return None, (0.8, 0.8, 0.8)
    sock = bsdf.inputs["Base Color"]
    default = tuple(sock.default_value)[:3]
    node = sock.links[0].from_node if sock.is_linked else None
    tint = (1.0, 1.0, 1.0)
    for _ in range(3):
        if node is None:
            return None, default
        if node.type == "TEX_IMAGE":
            return (node.image, tint) if node.image else (None, default)
        for inp in node.inputs:
            if not inp.is_linked and inp.type == "RGBA":
                tint = tuple(inp.default_value)[:3]
        linked = [inp for inp in node.inputs if inp.is_linked and inp.type == "RGBA"]
        node = linked[0].links[0].from_node if linked else None
    return None, default


def sample_albedo(obj):
    """Writes the source albedo at every corner into the colour attribute ALBEDO (linear, alpha 1)."""
    me = obj.data
    uv = me.uv_layers.active.data
    flat = [1.0] * (4 * len(me.loops))
    src = {}
    for i, slot in enumerate(obj.material_slots):
        src[i] = _base_source(slot.material)
    for poly in me.polygons:
        img, tint = src.get(poly.material_index, (None, (0.8, 0.8, 0.8)))
        for li in poly.loop_indices:
            if img is None:
                r, g, b = tint
            else:
                w, h, px = _pixels(img)
                u, v = uv[li].uv
                x = min(w - 1, max(0, int((u % 1.0) * w)))
                y = min(h - 1, max(0, int((v % 1.0) * h)))
                k = (y * w + x) * 4
                r, g, b = px[k] * tint[0], px[k + 1] * tint[1], px[k + 2] * tint[2]
            flat[4 * li:4 * li + 4] = [r, g, b, 1.0]
    attr = me.color_attributes.new(ALBEDO, "FLOAT_COLOR", "CORNER")
    attr.data.foreach_set("color", flat)


def combine_with_ao(obj):
    """ALBEDO x AO into one attribute FINAL (active), the only colour attribute the export writes."""
    me = obj.data
    n4 = 4 * len(me.loops)
    alb = [0.0] * n4
    ao = [0.0] * n4
    me.color_attributes[ALBEDO].data.foreach_get("color", alb)
    me.color_attributes[COLOR_NAME].data.foreach_get("color", ao)
    out = [alb[i] * ao[i] if i % 4 < 3 else 1.0 for i in range(n4)]
    me.color_attributes.remove(me.color_attributes[COLOR_NAME])
    me.color_attributes.remove(me.color_attributes[ALBEDO])
    attr = me.color_attributes.new(FINAL, "FLOAT_COLOR", "CORNER")
    attr.data.foreach_set("color", out)
    me.color_attributes.active_color_index = me.color_attributes.find(FINAL)
    me.color_attributes.render_color_index = me.color_attributes.find(FINAL)


def one_material(obj, name):
    obj.data.materials.clear()
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.material_index = 0
        poly.use_smooth = True


def rewrite_copyright(path, text):
    """Sets asset.copyright inside a GLB without touching the binary chunk."""
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + jlen].decode("utf-8"))
    doc.setdefault("asset", {})["copyright"] = text
    body = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    body += b" " * ((4 - len(body) % 4) % 4)
    rest = data[20 + jlen:]
    out = struct.pack("<I", 0x46546C67) + struct.pack("<I", 2) + struct.pack("<I", 12 + 8 + len(body) + len(rest))
    out += struct.pack("<I", len(body)) + b"JSON" + body + rest
    open(path, "wb").write(out)


def source_copyright(path):
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    return json.loads(data[20:20 + jlen].decode("utf-8")).get("asset", {}).get("copyright", "")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    src, fig_id, out_dir = argv[0], argv[1], argv[2]
    budgets = {"lod0": int(arg_value(argv, "lod0", "1100")), "lod1": int(arg_value(argv, "lod1", "300"))}
    credit = source_copyright(src)
    if not credit:
        raise RuntimeError("source has no asset.copyright: refuse to ship without the credit line")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    body = max(meshes, key=lambda o: len(o.data.polygons))
    bpy.context.view_layer.objects.active = body
    for mod in list(body.modifiers):
        if mod.type == "ARMATURE":
            bpy.ops.object.modifier_apply(modifier=mod.name)
    for o in list(bpy.data.objects):
        if o is not body:
            bpy.data.objects.remove(o, do_unlink=True)
    bake_world(body)
    body.parent = None
    # The vinish sources stand facing Blender -Y (Godot +Z). A half turn makes the figure face Godot -Z: checked on the
    # output, the dark hair of the head must sit behind the skin (on the +Y side).
    for v in body.data.vertices:
        v.co = Vector((-v.co.x, -v.co.y, v.co.z))
    # Feet on Z = 0, centred on the origin in X and Y.
    xs = [v.co.x for v in body.data.vertices]
    ys = [v.co.y for v in body.data.vertices]
    zs = [v.co.z for v in body.data.vertices]
    off = Vector((-(max(xs) + min(xs)) * 0.5, -(max(ys) + min(ys)) * 0.5, -min(zs)))
    for v in body.data.vertices:
        v.co = v.co + off
    height = max(zs) - min(zs)
    # Welded seams: open boundaries (sleeve and hem cuts) stop the collapse decimation short of the budget.
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(body.data)
    bm.free()
    base_mesh = body.data.copy()

    os.makedirs(out_dir, exist_ok=True)
    result = {"id": fig_id, "source": os.path.basename(src), "height_m": round(height, 3)}
    for lod, target in sorted(budgets.items()):
        obj = bpy.data.objects.new("crowd_%s_%s" % (fig_id, lod), base_mesh.copy())
        bpy.context.collection.objects.link(obj)
        result["%s_tris" % lod] = decimate_to(obj, target)
        sample_albedo(obj)
        ao = bake_ao([obj], cell_m=None, samples=48, distance_m=0.5, floor=SAMPLE_AO_FLOOR)
        result["%s_ao" % lod] = ao[obj.name]
        combine_with_ao(obj)
        one_material(obj, "crowd_%s" % fig_id)
        out = os.path.join(out_dir, "crowd_%s_%s.glb" % (fig_id, lod))
        for o in list(bpy.data.objects):
            if o is not obj:
                o.select_set(False)
        export_glb_ao(out, [obj])
        rewrite_copyright(out, credit + ", modified (crowd figure %s, %s)" % (fig_id, lod))
        result["%s_file" % lod] = out
        bpy.data.objects.remove(obj, do_unlink=True)
    print("RESULT " + json.dumps(result))


if __name__ == "__main__":
    main()
