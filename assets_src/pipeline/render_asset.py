"""Studio turnaround of any GLB: front 3/4, rear 3/4, side and rear views, EEVEE, neutral daylight.
Run: blender -b -P assets_src/pipeline/render_asset.py -- <in.glb> <out_dir> [--size=1280x720] [--forward=+Z|-Y]
Prints triangle count, bounding box and material count as one JSON line (ASSET_REPORT ...)."""
import bpy, sys, os, json, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = os.path.abspath(argv[0]), os.path.abspath(argv[1])
size = next((a.split("=")[1] for a in argv if a.startswith("--size=")), "1280x720")
W, H = (int(v) for v in size.split("x"))
os.makedirs(out, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if not meshes:
    raise SystemExit("no meshes in " + src)
lo = Vector((1e9, 1e9, 1e9)); hi = Vector((-1e9, -1e9, -1e9)); tris = 0
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
    o.data.calc_loop_triangles(); tris += len(o.data.loop_triangles)
centre = (lo + hi) / 2; dim = hi - lo; radius = max(dim) * 0.5
print("ASSET_REPORT " + json.dumps({"file": os.path.basename(src), "tris": tris, "size_m": [round(v, 3) for v in dim],
      "materials": len(bpy.data.materials), "images": len(bpy.data.images), "objects": len(meshes)}))

# ground and light
bpy.ops.mesh.primitive_plane_add(size=radius * 40, location=(centre.x, centre.y, lo.z))
g = bpy.context.object; gm = bpy.data.materials.new("Ground"); gm.use_nodes = True
b = gm.node_tree.nodes["Principled BSDF"]; b.inputs["Base Color"].default_value = (0.22, 0.22, 0.23, 1); b.inputs["Roughness"].default_value = 0.35
g.data.materials.append(gm)
world = bpy.data.worlds.new("W"); bpy.context.scene.world = world; world.use_nodes = True
bg = world.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.55, 0.62, 0.72, 1); bg.inputs[1].default_value = 0.9
def area(name, loc, energy, sz, col=(1, 1, 1)):
    d = bpy.data.lights.new(name, "AREA"); d.energy = energy; d.size = sz; d.color = col
    o = bpy.data.objects.new(name, d); bpy.context.scene.collection.objects.link(o); o.location = loc
    o.rotation_euler = (centre - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
area("Key", centre + Vector((radius * 2.2, -radius * 2.0, radius * 2.6)), 900 * radius * radius, radius * 3)
area("Fill", centre + Vector((-radius * 2.6, -radius * 1.0, radius * 1.4)), 350 * radius * radius, radius * 4, (0.85, 0.92, 1.0))
area("Rim", centre + Vector((0, radius * 3.0, radius * 2.0)), 600 * radius * radius, radius * 2, (1.0, 0.92, 0.82))

sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = W, H
sc.view_settings.view_transform = "Filmic" if "Filmic" in [v.name for v in bpy.types.ColorManagedViewSettings.bl_rna.properties["view_transform"].enum_items] else sc.view_settings.view_transform
cam_d = bpy.data.cameras.new("Cam"); cam_d.lens = 55
cam = bpy.data.objects.new("Cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam
# The longest horizontal axis is the car's length; views are named relative to it.
long_y = dim.y >= dim.x
views = {"front34": (35, 0.28), "rear34": (215, 0.3), "side": (90, 0.12), "rear": (180, 0.22), "front": (0, 0.18), "top34": (140, 0.9)}
for name, (az, elev) in views.items():
    a = math.radians(az + (0 if long_y else 90))
    d = radius * 3.6
    pos = centre + Vector((math.sin(a) * d, -math.cos(a) * d, radius * 2.0 * elev + dim.z * 0.2))
    cam.location = pos
    cam.rotation_euler = (centre - pos).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out, name + ".png")
    bpy.ops.render.render(write_still=True)
print("RENDERED", out)
