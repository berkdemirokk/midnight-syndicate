"""Turns the vinish.dev Double Ended Ferry GLB into the Bosphorus ferry of game/world/landmarks/far_scenery.gd: ONE mesh
with TWO surfaces (surface 0 the hull and superstructure, albedo x baked AO in COLOR_0; surface 1 the windows, a dark
glass material that far_scenery.gd makes glow warm at night), at most --tris triangles, about --length metres long,
origin at the waterline amidships (Godot Y = 0 at the water, the hull bottom sunk 2 m), length along Godot Z, the bow at
Godot -Z (the way far_scenery.gd points the ferry while it moves).

Run (Blender, headless, idempotent):
  blender.exe -b --factory-startup -P assets_src/pipeline/prepare_ferry.py -- <source.glb> <out.glb> [--tris=6000] [--length=52]

Output: <out.glb>, plus one JSON line "RESULT {...}" on stdout.
"""
import json
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from bake_vertex_ao import bake_ao, export_glb_ao  # noqa: E402
from prepare_figure import (  # noqa: E402
    arg_value, bake_world, combine_with_ao, decimate_to, rewrite_copyright, sample_albedo, source_copyright, tri_count)

GLASS_SOURCE = "Glass_Dark"  # the source material of the windows, which become surface 1
DRAFT_M = 2.0  # hull bottom below the waterline, m


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    src, out = argv[0], argv[1]
    max_tris = int(arg_value(argv, "tris", "6000"))
    length = float(arg_value(argv, "length", "52.0"))
    credit = source_copyright(src)
    if not credit:
        raise RuntimeError("source has no asset.copyright: refuse to ship without the credit line")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    hull = max(meshes, key=lambda o: len(o.data.polygons))
    for o in meshes:
        if o is not hull:
            bpy.data.objects.remove(o, do_unlink=True)
    bake_world(hull)
    hull.parent = None

    # Scale: the length is the Y extent of the source (76 m for this model); beam and height scale with it.
    ys = [v.co.y for v in hull.data.vertices]
    scale = length / (max(ys) - min(ys))
    for v in hull.data.vertices:
        v.co = v.co * scale
    xs = [v.co.x for v in hull.data.vertices]
    ys = [v.co.y for v in hull.data.vertices]
    zs = [v.co.z for v in hull.data.vertices]
    # Origin: amidships on the length and beam, at the waterline (DRAFT_M above the lowest point of the hull).
    off = Vector((-(max(xs) + min(xs)) * 0.5, -(max(ys) + min(ys)) * 0.5, -(min(zs) + DRAFT_M)))
    for v in hull.data.vertices:
        v.co = v.co + off
    beam = max(xs) - min(xs)
    height = max(zs) - min(zs)

    # Remove the source's own helper geometry glue: weld seams so the collapse decimation can reach the budget.
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(hull.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(hull.data)
    bm.free()

    before = tri_count(hull)
    decimate_to(hull, max_tris)
    src_names = [slot.material.name if slot.material else "" for slot in hull.material_slots]
    glass_flags = [src_names[p.material_index] == GLASS_SOURCE for p in hull.data.polygons]
    sample_albedo(hull)
    ao = bake_ao([hull], cell_m=None, samples=48, distance_m=3.0, floor=0.5)
    combine_with_ao(hull)

    body = bpy.data.materials.new("ferry_body")
    body.use_nodes = True
    bsdf = next(n for n in body.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.6
    glass = bpy.data.materials.new("ferry_glass")
    glass.use_nodes = True
    gsdf = next(n for n in glass.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    gsdf.inputs["Base Color"].default_value = (0.05, 0.08, 0.11, 1.0)
    gsdf.inputs["Roughness"].default_value = 0.15
    hull.data.materials.clear()
    hull.data.materials.append(body)
    hull.data.materials.append(glass)
    for poly, is_glass in zip(hull.data.polygons, glass_flags):
        poly.material_index = 1 if is_glass else 0
        poly.use_smooth = True

    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    export_glb_ao(out, [hull])
    rewrite_copyright(out, credit + ", modified (Bosphorus ferry: scaled, decimated, windows as surface 1)")
    result = {"source_tris": before, "tris": tri_count(hull), "surfaces": len(hull.data.materials),
              "glass_faces": sum(1 for g in glass_flags if g), "length_m": round(max(ys) - min(ys), 2),
              "beam_m": round(beam, 2), "height_m": round(height, 2), "ao": ao[hull.name], "file": out}
    print("RESULT " + json.dumps(result))


if __name__ == "__main__":
    main()
