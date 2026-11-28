"""Blender: CC0 Poly Haven street props (assets_src/third_party/polyhaven_models/<id>/, fetched 2026-11-28 with the
owner's approval) -> mobile GLBs in game/assets/world/props_cc0/. Each prop: all meshes joined into one object, decimated
to a triangle budget (LOD0) plus a coarser LOD1 copy, textures kept at 1k, origin at the base centre, +Y up in
Godot. Usage:
  blender -b --python assets_src/third_party/process_polyhaven_props.py -- <repo_root>
"""
import os
import sys

import bpy

PROPS = {  # out name: (source id, LOD0 triangles, LOD1 triangles)
    "cafe_set": ("outdoor_table_chair_set_01", 3000, 700),
    "planter_box": ("planter_box_01", 1800, 400),
    "planter_box_b": ("planter_box_02", 1800, 400),
    "potted_plant": ("potted_plant_02", 3000, 700),
    "trash_can": ("metal_trash_can", 1600, 400),
    "fire_hydrant": ("fire_hydrant", 1600, 400),
    "utility_box": ("utility_box_01", 900, 250),
    "utility_box_b": ("utility_box_02", 900, 250),
    "street_seating": ("modular_street_seating", 3000, 700),
    "wooden_bench": ("painted_wooden_bench", 630, 300),
    "wooden_crate": ("wooden_crate_01", 800, 200),
    "plastic_crate": ("plastic_crate_01", 1000, 250),
    "trash_bag": ("trashbag", 900, 250),
    "road_barrier": ("concrete_road_barrier", 1500, 400),
    "street_lamp": ("street_lamp_02", 2500, 600),
}
TEX_PX = 512


def clear() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def tri_count(obj) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def build(root: str, name: str, src: str, lod0: int, lod1: int) -> None:
    clear()
    folder = os.path.join(root, "assets_src", "third_party", "polyhaven_models", src)
    gltf = os.path.join(folder, src + "_1k.gltf")
    bpy.ops.import_scene.gltf(filepath=gltf)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.parent = None
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # origin at the base centre
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    cx, cy, z0 = (min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0, min(zs)
    for v in obj.data.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= z0
    obj.location = (0.0, 0.0, 0.0)
    # textures stay at the 1k source size (props are seen at 2-15 m; 512 px blurred them)
    out_dir = os.path.join(root, "game", "assets", "world", "props_cc0")
    os.makedirs(out_dir, exist_ok=True)
    base = tri_count(obj)
    for suffix, target in (("", lod0),):  # one GLB: Godot generates the mesh LODs on import (no texture copies)
        dup = obj.copy()
        dup.data = obj.data.copy()
        bpy.context.collection.objects.link(dup)
        if base > target:
            m = dup.modifiers.new("dec", "DECIMATE")
            m.ratio = max(0.002, target / float(base))
            bpy.context.view_layer.objects.active = dup
            bpy.ops.object.select_all(action="DESELECT")
            dup.select_set(True)
            bpy.ops.object.modifier_apply(modifier="dec")
        dup.name = name + suffix
        bpy.ops.object.select_all(action="DESELECT")
        dup.select_set(True)
        path = os.path.join(out_dir, name + suffix + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                                  export_apply=True, export_image_format="JPEG")
        w = max(xs) - min(xs)
        d = max(ys) - min(ys)
        print("PROP %s%s tris %d -> %d size %.2f x %.2f x %.2f m" % (name, suffix, base, tri_count(dup), w, d, max(zs) - z0))
        bpy.data.objects.remove(dup)


def main() -> None:
    root = sys.argv[sys.argv.index("--") + 1]
    only = sys.argv[sys.argv.index("--") + 2:] or list(PROPS)
    for name in only:
        src, lod0, lod1 = PROPS[name]
        build(root, name, src, lod0, lod1)


main()
