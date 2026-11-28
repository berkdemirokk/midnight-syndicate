"""Baked contact AO for a track road GLB (Blender 5.3, Cycles, run headless).

The wet asphalt shader has no SSAO on Mobile, so the road gets its contact darkening from a texture. This script:

  1. imports the road GLB and gives every road mesh object (all but the "ground" and the water / ground materials) a
     second UV map "UV2": one atlas shared by the whole road, so kerbs, wall bases and the carriageway all sit in
     one 1024 px image;
  2. bakes Cycles ambient occlusion (distance 3 m) into that image; the rest of the scene, ground included, occludes;
  3. saves the bake as a greyscale PNG next to the GLB (<name>_ao.png, 1 = open sky) and re-exports the GLB with
     TEXCOORD_1 added and COLOR_0 (the authored puddle / wear colours) unchanged.

The shader samples the PNG with UV2 (wet_asphalt.gdshader, ao_tex). MaterialLibrary.bind_road_ao() loads it.

Usage (Blender 5.3 background, after --):
  blender -b --factory-startup --python bake_road_ao.py -- <in.glb> <out.glb> <out_ao.png> [res=1024] [samples=64]
Prints one line "ROAD_AO_JSON {...}" with the round-trip checks: TEXCOORD_1 and COLOR_0 counts per primitive.
Shortcut: one atlas for the whole road at 1024 px (about 0.3 m per texel), upgrade to per-chunk atlases if the
contact darkening reads too soft at the kerbs on the Mobile sheets.
"""
import json
import math
import os
import struct
import sys

import bpy

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
IN_GLB, OUT_GLB, OUT_PNG = ARGV[0], ARGV[1], ARGV[2]
RES = int(ARGV[3]) if len(ARGV) > 3 else 1024
SAMPLES = int(ARGV[4]) if len(ARGV) > 4 else 64
SKIP_MATS = {"M_Ground", "M_Water"}
SKIP_NAMES = {"ground"}
AO_DISTANCE_M = 3.0
MARGIN = 0.003


def log(*a):
    print("[bake_road_ao]", *a, flush=True)


def glb_primitive_stats(path):
    """Counts primitives with TEXCOORD_1 and COLOR_0, read back from the exported GLB JSON chunk."""
    with open(path, "rb") as fh:
        head = fh.read(20)
        _m, _v, _len, clen, _ctype = struct.unpack("<IIIII", head)
        doc = json.loads(fh.read(clen).decode("utf-8"))
    prims = [p for m in doc.get("meshes", []) for p in m["primitives"]]
    uv2 = sum(1 for p in prims if "TEXCOORD_1" in p["attributes"])
    col = sum(1 for p in prims if "COLOR_0" in p["attributes"])
    return dict(primitives=len(prims), with_uv2=uv2, with_color0=col)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=IN_GLB)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]

    def is_road(o):
        if o.name in SKIP_NAMES or not o.data.polygons:
            return False
        names = {s.material.name for s in o.material_slots if s.material is not None}
        return not (names & SKIP_MATS)

    road = [o for o in meshes if is_road(o)]
    log("meshes", len(meshes), "road", len(road))

    # 1. UV2: one atlas over every road object, unwrapped in one multi-object edit session
    for o in road:
        me = o.data
        if "UV2" not in me.uv_layers:
            me.uv_layers.new(name="UV2")
        me.uv_layers.active = me.uv_layers["UV2"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in road:
        o.select_set(True)
    bpy.context.view_layer.objects.active = road[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=MARGIN, correct_aspect=False)
    bpy.ops.uv.pack_islands(margin=MARGIN)
    bpy.ops.object.mode_set(mode="OBJECT")
    log("UV2 atlas done")

    # 2. bake target: one image node in every material the road uses, set active
    img = bpy.data.images.new("road_ao", RES, RES, alpha=False)
    img.colorspace_settings.name = "Non-Color"
    seen = set()
    for o in road:
        for slot in o.material_slots:
            m = slot.material
            if m is None or m.name in seen:
                continue
            seen.add(m.name)
            m.use_nodes = True
            node = m.node_tree.nodes.new("ShaderNodeTexImage")
            node.name = "AO_BAKE"
            node.image = img
            m.node_tree.nodes.active = node

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = False
    try:
        scene.cycles.device = "GPU"
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.refresh_devices()
        for d in prefs.devices:
            d.use = d.type != "CPU"
    except Exception as exc:  # no GPU backend: CPU bake still works, just slower
        log("GPU not used:", exc)
        scene.cycles.device = "CPU"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("AO_WORLD")
    scene.world.light_settings.distance = AO_DISTANCE_M

    bpy.ops.object.select_all(action="DESELECT")
    for o in road:
        o.select_set(True)
    bpy.context.view_layer.objects.active = road[0]
    bpy.ops.object.bake(type="AO", target="IMAGE_TEXTURES", use_clear=True, margin=4, margin_type="EXTEND")
    log("bake done")

    img.filepath_raw = OUT_PNG
    img.file_format = "PNG"
    img.save()
    pixels = list(img.pixels)[0::4]
    log("ao min/mean/max", round(min(pixels), 3), round(sum(pixels) / len(pixels), 3), round(max(pixels), 3))

    # 3. remove the bake nodes, export
    for o in road:
        for slot in o.material_slots:
            m = slot.material
            if m is None or m.node_tree is None:
                continue
            for n in [n for n in m.node_tree.nodes if n.name == "AO_BAKE"]:
                m.node_tree.nodes.remove(n)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB, export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
        export_tangents=True, export_materials="EXPORT", export_image_format="NONE", export_cameras=False,
        export_lights=False, export_extras=False, export_vertex_color="ACTIVE",
        export_active_vertex_color_when_no_material=True)
    stats = glb_primitive_stats(OUT_GLB)
    print("ROAD_AO_JSON " + json.dumps(dict(glb=os.path.basename(OUT_GLB), png=os.path.basename(OUT_PNG),
                                            res=RES, samples=SAMPLES, road_objects=len(road), **stats)), flush=True)


main()
