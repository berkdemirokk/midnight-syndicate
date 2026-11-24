#!/usr/bin/env python3
"""CITY 01 layout preview (Environment Agent). Blender 5.3, EEVEE, deterministic.

Run:
  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup \
      --python build_layout_preview.py -- [--views top,neon,downtown,waterfront,underpass,market,establish]

Reads  layout_out/city_01_layout.json (godot_y_up) and the GLBs it names.
Writes layout_renders/*.png (1600x900).

Godot (x, y, z) -> Blender (x, -z, y). Instances are linked duplicates of one joined prototype per asset
(LOD0 for buildings, LOD2 for the second row), at the layout transform C * M_godot * C^-1.
"""
import bpy
import json
import math
import os
import re
import sys

from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
LAYOUT = os.path.join(HERE, "layout_out", "city_01_layout.json")
REN = os.path.join(HERE, "layout_renders")
ROAD_GLB = os.path.join(HERE, "road_out", "city_01_road.glb")
ROAD_MATS = os.path.join(HERE, "road_out", "materials.json")
KB = os.path.join(HERE, "..", "kit_buildings", "out")
KP = os.path.join(HERE, "..", "kit_props", "out")
os.makedirs(REN, exist_ok=True)

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
VIEWS = ["top", "neon", "downtown", "waterfront", "underpass", "market", "establish"]
for a in ARGV:
    if a.startswith("--views="):
        VIEWS = a.split("=", 1)[1].split(",")

C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
CI = C.inverted()


def g2b(p):
    return Vector((p[0], -p[2], p[1]))


def hex_lin(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


import time
T0 = time.time()


def log(*a):
    print("[preview %6.1fs]" % (time.time() - T0), *a, flush=True)


# ------------------------------------------------------------------ data
LAY = json.load(open(LAYOUT, encoding="utf-8"))
MAT_SPEC = {}
for path in (os.path.join(KB, "materials.json"), os.path.join(KP, "materials.json")):
    MAT_SPEC.update(json.load(open(path, encoding="utf-8")).get("materials", {}))
for e in json.load(open(ROAD_MATS, encoding="utf-8")).get("materials", []):   # road file is a list
    MAT_SPEC[e["name"]] = {"base_color": e["base_colour_srgb"], "roughness": e["roughness"],
                           "metallic": e["metallic"], "emission_color": e["emissive_srgb"],
                           "emission_strength": e["emissive_strength"]}
MAT_SPEC["M_Asphalt"] = dict(MAT_SPEC["M_Asphalt"], base_color="#0B0C10", roughness=0.07)   # wet, dark, glossy

# ------------------------------------------------------------------ scene
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = 1600
sc.render.resolution_y = 900
sc.render.resolution_percentage = 100
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
sc.eevee.taa_render_samples = 24
try:
    sc.eevee.use_raytracing = True
except Exception:
    pass
world = bpy.data.worlds.new("night")
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
# sky #070A14 for the brief; the fog colour #101A2E stands in for mist (EEVEE fog is unavailable here), so silhouettes read
bg.inputs["Color"].default_value = tuple(hex_lin("#101A2E")) + (1.0,)
bg.inputs["Strength"].default_value = 1.0
sc.world = world
try:
    ng = bpy.data.node_groups.new("glow", "CompositorNodeTree")
    sc.compositing_node_group = ng
    rl = ng.nodes.new("CompositorNodeRLayers")
    gl = ng.nodes.new("CompositorNodeGlare")
    gl.inputs["Type"].default_value = "Bloom"
    gl.inputs["Threshold"].default_value = 0.8
    gl.inputs["Strength"].default_value = 0.35
    gl.inputs["Size"].default_value = 7
    ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    outn = ng.nodes.new("NodeGroupOutput")
    ng.links.new(rl.outputs["Image"], gl.inputs["Image"])
    ng.links.new(gl.outputs["Image"], outn.inputs["Image"])
except Exception as e:
    log("glow unavailable", e)
# mist: EEVEE in 5.3 has no volumetric switch on this build, so the fog is left out (see notes)

# ------------------------------------------------------------------ materials
MAT_CACHE = {}


def canon_name(n):
    return re.sub(r"\.\d{3}$", "", n)


def to_lin(v):
    """Hex strings are sRGB (building and road kits); float lists are already Blender-linear (props kit)."""
    if v is None:
        return [0.0, 0.0, 0.0]
    if isinstance(v, str):
        return hex_lin(v)
    return [float(x) for x in v[:3]]


def make_material(key, base, proto=None):
    spec = MAT_SPEC.get(base, {"base_color": "#808080", "roughness": 0.6, "metallic": 0.0,
                                "emission_color": "#000000", "emission_strength": 0.0})
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = tuple(to_lin(spec["base_color"])) + (1.0,)
    bsdf.inputs["Roughness"].default_value = float(spec.get("roughness", 0.5))
    bsdf.inputs["Metallic"].default_value = float(spec.get("metallic", 0.0))
    ec = spec.get("emission_color")
    bsdf.inputs["Emission Color"].default_value = tuple(to_lin(ec)) + (1.0,)
    bsdf.inputs["Emission Strength"].default_value = float(spec.get("emission_strength", 0.0))

    def tex(path, socket, colour_space="sRGB"):
        if not os.path.exists(path):
            return
        img = bpy.data.images.load(path, check_existing=True)
        try:
            img.colorspace_settings.name = colour_space
        except Exception:
            pass
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img
        nt.links.new(tn.outputs["Color"], bsdf.inputs[socket])

    if base == "M_WindowAtlas":
        tex(os.path.join(KB, "window_atlas_basecolor.png"), "Base Color")
        tex(os.path.join(KB, "window_atlas_emissive.png"), "Emission Color")
    elif base == "M_ShopInterior":
        tex(os.path.join(KB, "shop_interior_basecolor.png"), "Base Color")
        tex(os.path.join(KB, "shop_interior_emissive.png"), "Emission Color")
    elif base == "M_ImpostorAtlas" and proto:
        tex(os.path.join(KB, "impostor_%s_basecolor.png" % proto), "Base Color")
        tex(os.path.join(KB, "impostor_%s_emissive.png" % proto), "Emission Color")
    elif re.match(r"M_Poster_0\d", base):
        tex(os.path.join(KP, "textures", "poster_%s.png" % base[-2:]), "Base Color")
    elif base == "M_Skyline":
        tex(os.path.join(KP, "textures", "skyline_night.png"), "Base Color")
    return m


def canon_mat(name, proto=None):
    base = canon_name(name)
    key = base if proto is None or base not in ("M_ImpostorAtlas",) else base + "@" + proto
    if key not in MAT_CACHE:
        MAT_CACHE[key] = make_material(key, base, proto)
    return MAT_CACHE[key]


# ------------------------------------------------------------------ import helpers
def import_glb(path):
    before = set(bpy.data.objects.keys())
    bpy.ops.import_scene.gltf(filepath=path)
    new = [bpy.data.objects[k] for k in bpy.data.objects.keys() if k not in before]
    meshes = []
    for o in new:
        if o.type == "MESH":
            o.data = o.data.copy()
            o.data.transform(o.matrix_world)          # bake the importer's root transform
            o.matrix_world = Matrix.Identity(4)
            meshes.append(o)
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    return meshes


def join_parts(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    return obj


def remap_slots(obj, proto):
    for slot in obj.material_slots:
        if slot.material is not None:
            slot.material = canon_mat(slot.material.name, proto)


PROTOS = {}      # key -> object
LOG_IMPORT = []


def proto_for(inst):
    asset = inst["asset"]
    lod = "LOD2" if inst["kind"] == "building_lod2_only" else ("LOD0" if inst["kind"] == "building" else None)
    key = (asset, lod or "prop")
    if key in PROTOS:
        return PROTOS[key]
    if lod:
        path = os.path.join(KB, asset + ".glb")
        got = import_glb(path)
        parts = [o for o in got if o.name.startswith(lod) and "colonly" not in o.name]
    else:
        path = os.path.join(REPO, inst["file"]) if not os.path.isabs(inst["file"]) else inst["file"]
        got = import_glb(path)
        parts = [o for o in got if "colonly" not in o.name]
    for o in got:                      # LOD1/LOD2/colliders of the file are not drawn in the preview
        if o not in parts:
            bpy.data.objects.remove(o, do_unlink=True)
    for p in parts:
        remap_slots(p, asset)
    obj = join_parts(parts, "proto_%s_%s" % (asset, lod or "prop"))
    obj.hide_render = True
    obj.hide_viewport = True
    LOG_IMPORT.append((asset, lod or "prop", len(obj.data.polygons)))
    PROTOS[key] = obj
    return obj


# ------------------------------------------------------------------ road
road_objs = import_glb(ROAD_GLB)
for o in list(road_objs):
    if "colonly" in o.name:
        bpy.data.objects.remove(o, do_unlink=True)
        road_objs.remove(o)
for o in road_objs:
    remap_slots(o, None)
    o.name = "road_" + o.name
log("road parts", len(road_objs))

# ------------------------------------------------------------------ instances
SKIP_INST = os.environ.get("SKIP_INST") == "1"
coll = bpy.context.scene.collection
inst_objs = []
if not SKIP_INST:
    for k, inst in enumerate(LAY["instances"]):
        proto = proto_for(inst)
        M = Matrix.Translation(inst["position"]) @ Matrix.Rotation(inst["yaw"], 4, "Y")
        Mb = C @ M @ CI
        o = bpy.data.objects.new("i%05d_%s" % (k, inst["asset"]), proto.data)
        o.matrix_world = Mb
        coll.objects.link(o)
        inst_objs.append((o, inst))
log("protos", len(PROTOS), "instances", len(inst_objs))
log("proto log", LOG_IMPORT[:6], "...")

# ------------------------------------------------------------------ lights
LIGHT_OBJS = []
for k, l in enumerate(LAY["lights"]):
    if l["type"] == "spot":
        ld = bpy.data.lights.new("L%04d" % k, "SPOT")
        ld.spot_size = math.radians(70)
        ld.spot_blend = 0.45
    else:
        ld = bpy.data.lights.new("L%04d" % k, "POINT")
        ld.shadow_soft_size = 0.4
    ld.color = hex_lin(l["color"])
    ld.energy = float(l["energy"]) * 30.0
    try:
        ld.use_shadow = False
    except Exception:
        pass
    try:
        ld.use_custom_distance = True
        ld.cutoff_distance = float(l["range"])
    except Exception:
        pass
    o = bpy.data.objects.new("LIGHT%04d" % k, ld)
    o.location = g2b(l["position"])
    if l.get("direction"):
        dv = Vector((l["direction"][0], -l["direction"][2], l["direction"][1])).normalized()
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = dv.to_track_quat("-Z", "Y")
    coll.objects.link(o)
    LIGHT_OBJS.append(o)
log("lights", len(LIGHT_OBJS))

# ------------------------------------------------------------------ helpers for views
def flat_mat(name, col, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = tuple(hex_lin(col)) + (1.0,)
    b.inputs["Roughness"].default_value = 0.9
    b.inputs["Emission Color"].default_value = tuple(hex_lin(col)) + (1.0,)
    b.inputs["Emission Strength"].default_value = strength
    return m


DOT_MESH = {}


def dot(name, p, r, mat):
    # one shared mesh per radius, linked objects per point (keeps the top map fast)
    key = round(r, 3)
    if key not in DOT_MESH:
        import bmesh
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=r)
        me = bpy.data.meshes.new("dot_%s" % key)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mat)
        DOT_MESH[key] = me
    o = bpy.data.objects.new(name, DOT_MESH[key])
    o.location = g2b(p)
    coll.objects.link(o)
    return o


def label(text, p, size=9.0):
    cu = bpy.data.curves.new("T_" + text, "FONT")
    cu.body = text
    cu.size = size
    o = bpy.data.objects.new("LBL_" + text, cu)
    o.location = Vector((p[0], p[1], 300.0))
    o.data.materials.append(flat_mat("lbl", "#FFFFFF", 4.0))
    coll.objects.link(o)


def camera(name, loc, target=None, direction=None, lens=35.0, ortho=None):
    cd = bpy.data.cameras.new(name)
    cd.clip_start = 0.3
    cd.clip_end = 3000.0
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    else:
        cd.lens = lens
    co = bpy.data.objects.new(name, cd)
    co.location = Vector(loc)
    if target is not None:
        d = (Vector(target) - Vector(loc)).normalized()
    else:
        d = Vector(direction).normalized()
    co.rotation_mode = "QUATERNION"
    co.rotation_quaternion = d.to_track_quat("-Z", "Y")
    coll.objects.link(co)
    sc.camera = co
    return co


def render(name):
    sc.render.filepath = os.path.join(REN, name)
    bpy.ops.render.render(write_still=True)
    log("rendered", name)


def sun(strength=0.06, col="#7F9FD0"):
    sd = bpy.data.lights.new("moon", "SUN")
    sd.energy = strength
    sd.color = hex_lin(col)
    so = bpy.data.objects.new("moon", sd)
    so.rotation_euler = (math.radians(55), 0, math.radians(-30))
    coll.objects.link(so)


RL = LAY["racing"]["racing_line"]
RLB = [g2b(p) for p in RL]


def rline(k):
    k = max(0, min(len(RLB) - 1, k))
    p = RLB[k]
    q = RLB[min(len(RLB) - 1, k + 2)] - RLB[max(0, k - 2)]
    return p, q.normalized()


def street_view(name, k, lens=35.0):
    p, d = rline(k)
    eye = p + Vector((0, 0, 1.3))
    camera(name, eye, direction=d, lens=lens)
    render(name + ".png")


def bay_water():
    """Dark glossy bay on the open-water side of the waterfront, from the quay face (offset 16.5 m) outward."""
    import bmesh
    CLJ = json.load(open(os.path.join(HERE, "road_out", "city_01_centerline.json"), encoding="utf-8"))
    S_ = CLJ["samples"]
    idx = [i for i, s in enumerate(S_) if s["district"] == 2]

    def gp(i, k):
        s = S_[i]
        return [s["pos"][0] - s["right"][0] * k, s["pos"][1] - 0.35, s["pos"][2] - s["right"][2] * k]

    bm = bmesh.new()
    for a, b in zip(idx[:-1], idx[1:]):
        vs = [bm.verts.new(g2b(gp(j, k))) for j, k in ((a, 16.5), (a, 260.0), (b, 260.0), (b, 16.5))]
        bm.faces.new(vs)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new("bay_water")
    bm.to_mesh(me)
    bm.free()
    wm = bpy.data.materials.new("bay_water")
    wm.use_nodes = True
    bw = wm.node_tree.nodes["Principled BSDF"]
    bw.inputs["Base Color"].default_value = tuple(hex_lin("#0B1A2C")) + (1.0,)
    bw.inputs["Roughness"].default_value = 0.04
    me.materials.append(wm)
    o = bpy.data.objects.new("bay_water", me)
    coll.objects.link(o)


# ------------------------------------------------------------------ views
sun(0.05)
bay_water()
if "neon" in VIEWS:
    street_view("neon_strip", 38)
if "downtown" in VIEWS:
    street_view("downtown", 165)
if "waterfront" in VIEWS:
    street_view("waterfront", 300)
if "underpass" in VIEWS:
    street_view("underpass", 395)
if "market" in VIEWS:
    street_view("old_market", 500)
if "establish" in VIEWS:
    p, d = rline(20)                       # 60 m up, 30 m back, looking down the Neon Strip
    eye = p + Vector((0, 0, 60.0)) - d * 30.0          # Blender Z is up
    camera("establish", eye, target=rline(60)[0] + Vector((0, 0, 2.0)), lens=35.0)
    render("establishing_60m.png")
# top map renders last: it overrides object materials and adds dots that would pollute the street views
if "top" in VIEWS:
    # flat district colours per instance (object-level material override), props and lights as dots
    pal = {"neon": "#19E6FF", "downtown": "#7D8CAB", "waterfront": "#3E6E86", "market": "#FFC23D", "parking": "#5C6470"}
    mats = {k: flat_mat("map_" + k, v, 0.55) for k, v in pal.items()}
    for o, inst in inst_objs:
        if inst["kind"].startswith("building"):
            key = "parking" if "parking" in inst["asset"] else inst["district"]
            for slot in o.material_slots:
                slot.link = "OBJECT"
                slot.material = mats.get(key, mats["downtown"])
    dm = flat_mat("map_prop", "#E8E8E8", 1.5)
    for p in LAY["instances"]:
        if p["kind"] == "prop" and p.get("category") in ("lamp", "furniture", "circuit", "sign", "overhead", "poster", "bay"):
            dot("pd", p["position"], 1.2, dm)
    ym = flat_mat("map_light", "#FFE070", 12.0)
    for l in LAY["lights"]:
        dot("ld", l["position"], 1.6, ym)
    for name, x, y in [("START", -95, -6), ("NEON STRIP", -190, -120), ("DOWNTOWN", 170, 470),
                       ("OVERPASS", 330, 430), ("WATERFRONT", 640, 20), ("UNDERPASS", 300, -420),
                       ("OLD MARKET", -150, -380), ("HAIRPIN", -150, -300), ("BAY", 700, -60)]:
        label(name, (x, y, 0), 14.0)
    camera("top", (190.0, 15.0, 1200.0), direction=(0, 0, -1), ortho=1650.0)
    render("top_map.png")

log("done")
