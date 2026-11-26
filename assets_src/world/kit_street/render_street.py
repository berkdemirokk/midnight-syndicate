"""Contact sheet of the street kit (Blender 5.3, EEVEE). Imports out/*.glb (LOD0), lays them out in rows and renders
renders/contact_street.png (1800x1000). Run: blender --background --factory-startup --python render_street.py"""
import glob
import math
import os

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
os.makedirs(os.path.join(HERE, "renders"), exist_ok=True)

files = sorted(f for f in glob.glob(os.path.join(OUT, "prop_*.glb")) if "_lod1" not in f)
skip = ("alley_floor", "cables_hang", "fire_escape", "glow_pool")
files = [f for f in files if not any(k in f for k in skip)]
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)

COLS = 7
GAP = 3.2
for i, f in enumerate(files):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    new = [o for o in bpy.data.objects if o not in before]
    root = [o for o in new if o.parent is None][0]
    root.location = Vector(((i % COLS) * GAP, -(i // COLS) * GAP, 0))
bpy.ops.mesh.primitive_plane_add(size=80, location=(10, -5, -0.01))
gm = bpy.data.materials.new("floor")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.1, 0.1, 0.12, 1)
gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
bpy.context.object.data.materials.append(gm)
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 1800, 900
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.04, 0.05, 0.08, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
sc.world = w
for loc, e in (((6, -12, 9), 600), ((14, 4, 8), 400)):
    ld = bpy.data.lights.new("l", "POINT")
    ld.energy = e
    o = bpy.data.objects.new("l", ld)
    o.location = loc
    sc.collection.objects.link(o)
sun = bpy.data.lights.new("s", "SUN")
sun.energy = 1.5
so = bpy.data.objects.new("s", sun)
so.rotation_euler = (math.radians(50), 0, math.radians(30))
sc.collection.objects.link(so)
cam = bpy.data.cameras.new("c")
cam.lens = 40
co = bpy.data.objects.new("c", cam)
co.location = (9.5, -20, 6.5)
co.rotation_euler = (math.radians(68), 0, 0)
sc.collection.objects.link(co)
sc.camera = co
sc.render.filepath = os.path.join(HERE, "renders", "contact_street.png")
bpy.ops.render.render(write_still=True)
print("[render] wrote", sc.render.filepath, "props", len(files))
