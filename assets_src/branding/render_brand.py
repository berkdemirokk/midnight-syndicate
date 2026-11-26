import os
"""Midnight Syndicate icon + splash renderer.
Run: blender -b -P render_brand.py -- <icon|splash> <out_png> [samples]
Uses the game's own LOD0 hero car. Absolute paths on purpose (Blender 5.3).
"""
import bpy, sys, math
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))  # repo root (Blender needs absolute paths)
GLB = ROOT + "/game/assets/vehicles/noctra_sable/noctra_sable_lod0.glb"
argv = sys.argv[sys.argv.index("--") + 1:]
MODE, OUT = argv[0], argv[1]
SAMPLES = int(argv[2]) if len(argv) > 2 else 96


def lin(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return [((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4) for v in c] + [1]


bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=GLB)

# --- car paint: candy red #8E0F1E
for m in bpy.data.materials:
    if m.name.startswith("M_Paint"):
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = lin("#8E0F1E")
        b.inputs["Metallic"].default_value = 0.15
        b.inputs["Roughness"].default_value = 0.22
        for k in ("Coat Weight", "Clearcoat"):
            if k in b.inputs:
                b.inputs[k].default_value = 0.4
        for k in ("Coat Roughness", "Clearcoat Roughness"):
            if k in b.inputs:
                b.inputs[k].default_value = 0.03
    if m.name == "M_Carbon":
        nt = m.node_tree
        b = nt.nodes["Principled BSDF"]
        mx = nt.nodes.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        mx.blend_type = "MULTIPLY"
        mx.inputs[0].default_value = 1.0
        mx.inputs[7].default_value = (0.1, 0.1, 0.12, 1)
        src = b.inputs["Base Color"].links[0].from_socket
        nt.links.new(src, mx.inputs[6])
        nt.links.new(mx.outputs[2], b.inputs["Base Color"])
    if m.name in ("M_LightFront", "M_LightRear"):
        b = m.node_tree.nodes.get("Principled BSDF")
        if b:
            col = (1.0, 0.95, 0.85, 1) if m.name == "M_LightFront" else (1.0, 0.03, 0.06, 1)
            b.inputs["Emission Color"].default_value = col
            b.inputs["Emission Strength"].default_value = 18.0

for _o in [o for o in bpy.data.objects if o.name.startswith("col_")]:
    bpy.data.objects.remove(_o)  # collision hull, not visual
car = bpy.data.objects["body"]
# glTF import: car is long on Y. Which end is the nose? lights_front tells us.
lf = bpy.data.objects["lights_front"]
bb = [lf.matrix_world @ Vector(c) for c in lf.bound_box]
nose_y = sum(v.y for v in bb) / 8
nose_sign = 1 if nose_y > 0 else -1

# --- ground: wet black asphalt mirror
bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0))
g = bpy.context.object
gm = bpy.data.materials.new("Wet")
gm.use_nodes = True
gb = gm.node_tree.nodes["Principled BSDF"]
gb.inputs["Base Color"].default_value = (0.012, 0.014, 0.022, 1)
gb.inputs["Roughness"].default_value = 0.07
gb.inputs["Metallic"].default_value = 0.0
if "Specular IOR Level" in gb.inputs:
    gb.inputs["Specular IOR Level"].default_value = 0.9
g.data.materials.append(gm)
# subtle roughness breakup so the wet road is not a perfect mirror
nt = gm.node_tree
noise = nt.nodes.new("ShaderNodeTexNoise")
noise.inputs["Scale"].default_value = 5
noise.inputs["Detail"].default_value = 8
ramp = nt.nodes.new("ShaderNodeMapRange")
ramp.inputs["From Min"].default_value = 0.35
ramp.inputs["From Max"].default_value = 0.7
ramp.inputs["To Min"].default_value = 0.04
ramp.inputs["To Max"].default_value = 0.32
nt.links.new(noise.outputs["Fac"], ramp.inputs["Value"])
nt.links.new(ramp.outputs["Result"], gb.inputs["Roughness"])

# --- world: dark navy
w = bpy.data.worlds.new("W")
sc.world = w
w.use_nodes = True
bg = w.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = lin("#070B1C")
bg.inputs["Strength"].default_value = 0.35

# --- lights (all relative to the nose direction s)
s = nose_sign


def area(name, loc, color, power, size, target=(0, 0, 0.5), shape="RECTANGLE", sy=None):
    d = bpy.data.lights.new(name, "AREA")
    d.color = color
    d.energy = power
    d.shape = shape
    d.size = size
    if sy:
        d.size_y = sy
    o = bpy.data.objects.new(name, d)
    sc.collection.objects.link(o)
    o.location = loc
    dirv = Vector(target) - Vector(loc)
    o.rotation_euler = dirv.to_track_quat("-Z", "Y").to_euler()
    return o


MAGENTA = (1.0, 0.1, 0.65)
CYAN = (0.05, 0.85, 1.0)
area("rimMag", (-3.5, -s * 7.0, 2.6), MAGENTA, 650, 2.0, (0, 0, 0.7), sy=4.0)
area("redKey", (-6.0, s * 3.0, 2.0), (1.0, 0.85, 0.8), 220, 3, (0, 0, 0.5))
area("rimCyan", (5.5, s * 5.5, 2.4), CYAN, 650, 2.0, (0, 0, 0.7), sy=4.0)
area("key", (3.0, s * 6.5, 4.5), (0.75, 0.82, 1.0), 40, 6, (0, 0, 0.5))
area("top", (0, 0, 5.0), (0.6, 0.65, 1.0), 1, 5, (0, 0, 0.5))
area("fillMag", (-6, s * 4, 0.5), (0.3,0.4,1.0), 18, 4, (0, 0, 0.5))

# neon strips on the ground sides, reflected in the wet road
for name, x, col in (("stripM", -5.8, MAGENTA), ("stripC", 5.8, CYAN)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, 0, 0.05))
    o = bpy.context.object
    o.scale = (0.05, 22, 0.05)
    em = bpy.data.materials.new(name)
    em.use_nodes = True
    eb = em.node_tree.nodes["Principled BSDF"]
    eb.inputs["Base Color"].default_value = (0, 0, 0, 1)
    eb.inputs["Emission Color"].default_value = col + (1,)
    eb.inputs["Emission Strength"].default_value = 8
    o.data.materials.append(em)


def emissive(name, col, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.02, 0.02, 0.03, 1)
    b.inputs["Emission Color"].default_value = col + (1,)
    b.inputs["Emission Strength"].default_value = strength
    return m


ICON_TX, ICON_TZ = 2.1, 2.75
SPL_TX, SPL_TZ = 1.0, 2.35
FONT = None


def text(body, loc, size, mat, extrude=0.02, rot=(math.pi / 2, 0, 0), bold_shear=0.0):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    t = bpy.context.object
    t.data.body = body
    t.data.size = size
    t.data.extrude = extrude
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    t.data.offset_x = 0
    t.data.space_character = 1.0
    t.data.offset = 0.06 if body == 'MS' else 0.02
    t.data.materials.append(mat)
    return t


# --- camera
cam_d = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


if MODE == "icon":
    sc.render.resolution_x = sc.render.resolution_y = 1024
    cam_d.lens = 58
    cam.location = (-5.2, s * 6.2, 0.75)
    aim(cam, (0.0, s * 0.55, 0.95))
else:
    sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
    cam_d.lens = 40
    cam.location = (-5.4, s * 6.6, 0.8)
    aim(cam, (0.1, s * 0.5, 1.05))

cam_d.dof.use_dof = True
cam_d.dof.focus_distance = (cam.location - Vector((0, s * 0.8, 0.5))).length
cam_d.dof.aperture_fstop = 9.0

# --- render
sc.render.engine = "CYCLES"
sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = True
sc.cycles.device = "CPU"
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    sc.cycles.device = "GPU"
except Exception as e:
    print("GPU fallback:", e)
sc.cycles.max_bounces = 8
sc.cycles.glossy_bounces = 6
sc.cycles.sample_clamp_indirect = 6
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Punchy" if "AgX - Punchy" in [l.name for l in []] else "None"
sc.view_settings.exposure = 0.0
sc.render.film_transparent = False
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGB"
sc.render.filepath = OUT

def billboard(t):
    c = t.constraints.new("TRACK_TO")
    c.target = cam
    c.track_axis = "TRACK_Z"
    c.up_axis = "UP_Y"


WHITE = emissive("neonwhite", (1.0, 0.92, 0.97), 9)
MAGM = emissive("neonmag", MAGENTA, 14)
CYAM = emissive("neoncyan", CYAN, 14)
if MODE == "icon":
    # glow layers: cyan and magenta offsets behind a white core read as neon at 60 px
    for dx, dz, m in ((0.09, -0.07, CYAM), (-0.09, 0.07, MAGM), (0, 0, WHITE)):
        t = text("MS", (dx + ICON_TX, -s * 2.0, ICON_TZ + dz), 1.9, m, extrude=0.06)
        t.data.font = bpy.data.fonts.load(FONT) if FONT else t.data.font
        billboard(t)
else:
    bpy.context.view_layer.update()
    q = cam.matrix_world.to_quaternion()
    cf, cu, cr = q @ Vector((0, 0, -1)), q @ Vector((0, 1, 0)), q @ Vector((1, 0, 0))
    base = cam.location + cf * 9.0 + cu * 1.1
    for dx, dz, m in ((0.035, -0.035, CYAM), (-0.035, 0.035, MAGM), (0, 0, WHITE)):
        t = text("MIDNIGHT SYNDICATE", base + cr * dx + cu * dz, 0.42, m, extrude=0.03)
        t.data.offset = 0.0
        t.data.space_character = 1.22
        billboard(t)

bpy.ops.render.render(write_still=True)
print("DONE", OUT)
