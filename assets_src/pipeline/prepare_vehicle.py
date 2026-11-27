"""Turns a CC BY vehicle GLB into the game's car contract: LOD0/LOD1/LOD2 GLBs with the engine node names,
the engine material names, wheel origins at the wheel centres, a convex col_body and the copyright line.

Run (Blender, headless, idempotent):
  blender.exe -b --factory-startup -P assets_src/pipeline/prepare_vehicle.py -- <source.glb> <car_id> <out_dir> [--config=<json>]
Default config: assets_src/pipeline/vehicle_configs/<car_id>.json. Every source material must be mapped (the run fails otherwise).

Convention (probed on game/assets/vehicles/kestrel_gtr/kestrel_gtr_lod0.glb in Blender 5.3): after glTF import the nose
is -Y, Z is up, wheel origins are the wheel centres, wheels touch Z = 0, and the axle midpoint sits on Y = 0.
The vinish sources match this already (metres, scale 1), so only the axle midpoint is moved to Y = 0.
"""
import bmesh
import math
import bpy
import json
import os
import struct
import sys
import tempfile
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from bake_vertex_ao import _occluded  # noqa: E402  cosine-weighted hemisphere test against a BVH (the kit baker's)
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
WHEELS = ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]
WHEEL_SRC = ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]
WHEEL_PARTS = ("M_Tire", "M_Rim", "M_BrakeDisc", "M_Caliper")  # routed to the nearest wheel by geometry
BRAKE_REACH_M = 0.42  # a disc or caliper face further than this from every wheel centre is body, not brake
DEFAULT_NODE = {
    "M_Paint": "body", "M_Trim": "trim", "M_Carbon": "trim", "M_Glass": "glass", "M_Lens": "lights_front",
    "M_LightFront": "lights_front", "M_LightRear": "lights_rear", "M_Interior": "interior", "M_Chrome": "exhaust",
    "M_Plate": "plate_rear",
}
KNOWN = ["M_Paint", "M_Glass", "M_Lens", "M_LightFront", "M_LightRear", "M_Carbon", "M_Rim", "M_Tire",
         "M_BrakeDisc", "M_Caliper", "M_Trim", "M_Chrome", "M_Interior", "M_Plate"]

# Engine materials whose faces carry the source material's colour as a vertex colour (COLOR_0). A source car has about
# 60 materials (chrome, projector glass, amber lamps, tan leather, yellow calipers) and the contract has 14, so a plain
# merge paints every part of a group one flat colour. The vertex colour keeps the part colours with no extra surface and
# no extra draw call. Faces of every other material get white: their look is a texture or the player's choice.
VC_TARGETS = ("M_Trim", "M_Chrome", "M_Interior", "M_BrakeDisc", "M_Caliper", "M_Rim")
VC_FLOOR = 0.012  # pure black parts keep a little diffuse, or they read as holes in the body
RIM_SHADE_MIN = 0.5  # darkest wheel part against the bright alloy: M_Rim carries a shade, the player picks the colour
# (0.16 was tried: a wheel in the default gunmetal read as a black disc; the baked shade below gives the depth)
# Baked shade (ambient occlusion) multiplied into those vertex colours: the Mobile renderer has no SSAO, and without it
# a wheel barrel, a grille opening and a footwell are as bright as the part in front of them.
AO_SAMPLES = 24
AO_DISTANCE_M = 0.45  # reach: wheel barrels, grille and lamp housings, footwells, sills over the road
AO_FLOOR = 0.28  # darkest shade
AO_FLOOR_BRAKE = 0.55  # discs and calipers sit deep in the wheel; a coloured caliper has to stay readable
AO_EPS_M = 0.004  # ray origin off the surface
AO_CLEAR = ("M_Glass", "M_Lens")  # see-through parts do not shade what is behind them
# Source colours that do not work as a flat colour. Screens: the mean of a lit map screen is a mid grey, and a grey
# rectangle on the dash reads as a blank panel through the rear window; a dark glass blue reads as a display.
COLOUR_FIXES = {"Screens": (0.015, 0.03, 0.06)}
SPOKE_ZONE = (0.22, 0.5)  # share of the tyre radius where only spokes are: outside the nuts, inside the lip
RIM_REF_SHARE = 0.08  # fallback only: the brightest wheel colour that covers at least this share of the rim area
# A metal's base colour is its mirror tint, not a paint. Where the far LODs (and a few LOD0 parts) fold a metal into a
# matt engine material, that tint as albedo is light grey plastic (chrome 0.77 on a grille at 6 m), so it is dimmed.
MATT_TARGETS = ("M_Trim", "M_Interior")
METAL_MIN = 0.6  # source metallicFactor from which a material counts as a metal
METAL_AS_MATT = 0.18
# The collapse (with symmetry) now and then throws a vertex far off the part: a 1 m spike out of a flank, a fin under
# the road (found in four LOD2 files), and at 6 % it leaves body corners 5 to 25 cm off. A vertex further than this
# from the part before the collapse is put back onto it. Deleting its faces was tried: 4 vertices cost 60 body faces.
STRAY_TOL_M = 0.04
LOD_BOX_MARGIN_M = 0.1  # a far LOD may not reach further than this beyond the LOD0 box (the run fails otherwise)

# Values from docs/art/CAR_01_BRIEF.md (materials table). The engine re-styles most of them by name at run time.
SPEC = {
    "M_Paint": dict(base=(1, 1, 1, 1), metallic=0.85, roughness=0.32, coat=1.0, coat_rough=0.04),
    "M_Glass": dict(base=(0.035, 0.05, 0.06, 1), roughness=0.03, alpha=0.35, metallic=0.0),
    "M_Trim": dict(base=(0.03, 0.03, 0.035, 1), roughness=0.55),
    "M_Carbon": dict(base=(0.08, 0.08, 0.09, 1), roughness=0.35, coat=0.6, coat_rough=0.2),
    "M_Rim": dict(base=(0.314, 0.333, 0.369, 1), metallic=1.0, roughness=0.28),
    "M_Tire": dict(base=(0.02, 0.02, 0.022, 1), roughness=0.85),
    "M_LightFront": dict(base=(0.87, 0.92, 1, 1), emission=(0.87, 0.92, 1, 1), emission_strength=6.0),
    "M_LightRear": dict(base=(0.6, 0.02, 0.02, 1), emission=(1.0, 0.1, 0.1, 1), emission_strength=4.0),
    "M_Lens": dict(base=(1, 1, 1, 1), roughness=0.05, alpha=0.25, metallic=0.0),
    "M_BrakeDisc": dict(base=(0.45, 0.45, 0.47, 1), metallic=1.0, roughness=0.4),
    "M_Caliper": dict(base=(0.95, 0.76, 0.0, 1), roughness=0.4),
    "M_Interior": dict(base=(0.05, 0.05, 0.055, 1), roughness=0.7),
    "M_Chrome": dict(base=(0.9, 0.9, 0.92, 1), metallic=1.0, roughness=0.12),
    "M_Plate": dict(base=(1, 1, 1, 1), roughness=0.5),
}


def arg_value(argv, key, default=None):
    for a in argv:
        if a.startswith("--%s=" % key):
            return a.split("=", 1)[1]
    return default


def set_in(bsdf, name, value):
    if name in bsdf.inputs:
        bsdf.inputs[name].default_value = value
    else:
        print("WARN no Principled input", name)


def make_material(name, cfg):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    v = SPEC[name]
    # the colour of these lives in the vertex colours (VC_TARGETS); M_Rim keeps its base, its vertex colour is a shade
    set_in(bsdf, "Base Color", (1, 1, 1, 1) if name in VC_TARGETS and name != "M_Rim" else v["base"])
    set_in(bsdf, "Metallic", v.get("metallic", 0.0))
    set_in(bsdf, "Roughness", v.get("roughness", 0.5))
    if "alpha" in v:
        set_in(bsdf, "Alpha", v["alpha"])
        m.surface_render_method = "BLENDED"
    if "coat" in v:
        set_in(bsdf, "Coat Weight", v["coat"])
        set_in(bsdf, "Coat Roughness", v["coat_rough"])
    if "emission" in v:
        set_in(bsdf, "Emission Color", v["emission"])
        set_in(bsdf, "Emission Strength", v["emission_strength"])
    # M_LightRear with a tail_cell: the mesh gets the atlas UVs (tail_uv) and the engine sets the two shared atlas
    # pictures (car_materials.gd). They are not embedded here: every GLB carried its own copy, 18 files of 3 MB.
    if name == "M_Plate" and cfg.get("plate_image"):
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(cfg["plate_image"], check_existing=True)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    # No source texture is carried over: the nodes built here have no source UVs. The engine gives M_Carbon its weave
    # and M_Tire its tyre picture by projection (car_materials.gd).
    return m


def srgb_to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def luminance(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def image_mean(js, data, bin0, img_i, alpha_mode="OPAQUE", cutoff=0.5):
    """Mean linear RGB of one image embedded in the GLB. For a cut-out or blended material the mean is weighted by
    what is opaque: a wire mesh that is 40 % wire is 40 % of the wire colour over the dark behind it."""
    img = js["images"][img_i]
    if "bufferView" not in img:
        return (1.0, 1.0, 1.0)
    bv = js["bufferViews"][img["bufferView"]]
    start = bin0 + bv.get("byteOffset", 0)
    ext = ".png" if img.get("mimeType") == "image/png" else ".jpg"
    tmp = os.path.join(tempfile.gettempdir(), "ms_vc_%d_%d%s" % (os.getpid(), img_i, ext))
    with open(tmp, "wb") as fh:
        fh.write(data[start:start + bv["byteLength"]])
    im = bpy.data.images.load(tmp)
    px = np.empty(im.size[0] * im.size[1] * 4, dtype=np.float32)
    im.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    rgb = srgb_to_linear(px[:, :3])
    if alpha_mode == "MASK":
        rgb = rgb * (px[:, 3:4] >= cutoff)
    elif alpha_mode == "BLEND":
        rgb = rgb * px[:, 3:4]
    rgb = rgb.mean(axis=0)
    bpy.data.images.remove(im)
    os.remove(tmp)
    return tuple(float(c) for c in rgb)


def source_colours(path):
    """Two dicts by source material name: linear RGB (the glTF base colour factor times the mean of its base colour
    texture) and the metallic factor. Read from the GLB itself, so it does not depend on how Blender names the
    imported images."""
    with open(path, "rb") as fh:
        data = fh.read()
    jlen = struct.unpack("<I", data[12:16])[0]
    js = json.loads(data[20:20 + jlen])
    bin0 = 20 + jlen + 8
    means, out, metallic = {}, {}, {}
    for m in js.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        col = list(pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0]))[:3]
        tex = pbr.get("baseColorTexture")
        img_i = js["textures"][tex["index"]].get("source") if tex is not None else None
        if img_i is not None:
            key = (img_i, m.get("alphaMode", "OPAQUE"), m.get("alphaCutoff", 0.5))
            if key not in means:
                means[key] = image_mean(js, data, bin0, *key)
            col = [c * t for c, t in zip(col, means[key])]
        out[m.get("name", "")] = tuple(col)
        metallic[m.get("name", "")] = float(pbr.get("metallicFactor", 1.0))  # the glTF default is 1
    return out, metallic


def face_colour(target, col, rim_ref):
    """Vertex colour (RGBA) of a face: the source colour for VC_TARGETS, a shade against the main alloy for M_Rim,
    white for everything else."""
    if target not in VC_TARGETS:
        return (1.0, 1.0, 1.0, 1.0)
    if target == "M_Rim":
        s = min(max(luminance(col) / rim_ref, RIM_SHADE_MIN), 1.0) if rim_ref > 1e-6 else 1.0
        return (s, s, s, 1.0)
    return (max(col[0], VC_FLOOR), max(col[1], VC_FLOOR), max(col[2], VC_FLOOR), 1.0)


def bake_part_ao(buckets):
    """Shade per bucket vertex in [AO_FLOOR, 1] for the vertices of VC_TARGETS faces (1 for the rest). The body nodes
    are tested against the whole car and the road (z = 0); a wheel and its brake only against each other, because they
    turn and the shade has to turn with them. Returns {bucket name: [shade per bucket vertex]}."""
    def group_of(name):
        return name[-2:] if name[:6] in ("wheel_", "brake_") else "body"

    def tree(names):
        verts, polys = [], []
        for nm in names:
            base = len(verts)
            verts += buckets[nm]["verts"]
            polys += [[base + i for i in idx] for idx, target, *_ in buckets[nm]["faces"] if target not in AO_CLEAR and len(idx) >= 3]
        return BVHTree.FromPolygons(verts, polys) if polys else None

    groups = {}
    for name in buckets:
        groups.setdefault(group_of(name), []).append(name)
    trees = {g: tree(sorted(buckets) if g == "body" else names) for g, names in groups.items()}
    out = {}
    for name, b in buckets.items():
        g = group_of(name)
        normal = [Vector((0.0, 0.0, 0.0)) for _ in b["verts"]]
        wanted = set()
        for idx, target, *_ in b["faces"]:
            if len(idx) < 3:
                continue
            c = (b["verts"][idx[1]] - b["verts"][idx[0]]).cross(b["verts"][idx[2]] - b["verts"][idx[0]])  # area-weighted
            for i in idx:
                normal[i] += c
            if target in VC_TARGETS:
                wanted.update(idx)
        shade = [1.0] * len(b["verts"])
        if trees[g] is not None:
            ground = 0.0 if g == "body" else -1.0e9
            for vi in wanted:
                if normal[vi].length < 1e-12:
                    continue
                n = normal[vi].normalized()
                rot = ((vi * 0.6180339887) % 1.0) * 2.0 * math.pi
                occ = _occluded(b["verts"][vi] + n * AO_EPS_M, n, trees[g], AO_SAMPLES, AO_DISTANCE_M, ground, rot)
                shade[vi] = max(AO_FLOOR_BRAKE if name.startswith("brake_") else AO_FLOOR, 1.0 - occ)
        out[name] = shade
    return out


def load_source(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    for o in bpy.data.objects:  # bake node transforms into the mesh: world-space geometry, identity object transform
        o.data = o.data.copy()  # the GLB shares one mesh between Wheel_FL/FR and between Wheel_RL/RR: make each unique
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
        o.parent = None


def wheel_centres():
    """Wheel centre (bbox centre of each source wheel mesh) and size, Blender space."""
    out = {}
    for src, dst in zip(WHEEL_SRC, WHEELS):
        o = bpy.data.objects.get(src)
        if o is None:
            raise SystemExit("source has no node %s" % src)
        vs = [v.co for v in o.data.vertices]
        mn = Vector((min(p.x for p in vs), min(p.y for p in vs), min(p.z for p in vs)))
        mx = Vector((max(p.x for p in vs), max(p.y for p in vs), max(p.z for p in vs)))
        out[dst] = ((mn + mx) / 2, mx - mn)
    return out


SMOOTH_COS = math.cos(math.radians(40.0))  # corners across an edge sharper than 40 degrees keep their own normal


def smooth_paint(verts, faces):
    """LOD0 only: area-weighted vertex normals for the M_Paint faces of one bucket. Neighbours across an edge
    sharper than 40 degrees (panel gaps) do not blend. Returns {face index: [normal per corner]}."""
    face_n, vfaces = {}, {}
    for fi, (idx, target, *_) in enumerate(faces):
        if target != "M_Paint" or len(idx) < 3:
            continue
        c = (verts[idx[1]] - verts[idx[0]]).cross(verts[idx[2]] - verts[idx[0]])
        if c.length < 1e-12:
            continue
        face_n[fi] = (c.normalized(), c.length * 0.5)
        for vi in idx:
            vfaces.setdefault(vi, []).append(fi)
    out = {}
    for fi, (n, _) in face_n.items():
        corners = []
        for vi in faces[fi][0]:
            acc = Vector((0.0, 0.0, 0.0))
            for gi in vfaces[vi]:
                ng, ag = face_n[gi]
                if n.dot(ng) >= SMOOTH_COS:
                    acc += ng * ag
            corners.append(acc.normalized() if acc.length > 1e-12 else n)
        out[fi] = corners
    return out


def pull_back_strays(ob, before):
    """Moves the vertices of ob that lie further than STRAY_TOL_M from the surface it had before the collapse back
    onto that surface (before: its BVH, object space). Returns how many moved."""
    moved = 0
    for v in ob.data.vertices:
        co, _normal, _index, dist = before.find_nearest(v.co)
        if co is not None and dist > STRAY_TOL_M:
            v.co = co
            moved += 1
    return moved


def build_lod(src, cfg, level, out_dir, stats, colours, metallic):
    load_source(src)
    centres = wheel_centres()
    shift = Vector((0.0, -(centres["wheel_FL"][0].y + centres["wheel_RL"][0].y) / 2, 0.0))
    for o in bpy.data.objects:
        o.data.transform(Matrix.Translation(shift))
    centres = {k: (c + shift, s) for k, (c, s) in centres.items()}

    # per-level overrides: "drop" removes the faces; a node name moves them; by_obj moves a whole source object
    nodes_map = dict(cfg.get("nodes", {}))
    nodes_map.update(cfg.get("nodes_lod%d" % level, {}))
    by_obj = dict(cfg.get("nodes_by_object", {}))
    by_obj.update(cfg.get("nodes_by_object_lod%d" % level, {}))
    by_obj_mat = dict(cfg.get("by_object_material", {}))
    by_obj_mat.update(cfg.get("by_object_material_lod%d" % level, {}))
    mats_map = dict(cfg["materials"])
    mats_map.update(cfg.get("materials_lod%d" % level, {}))  # fewer surfaces at the far LODs
    mats_by_obj = dict(cfg.get("materials_by_object", {}))  # "Object|SourceMaterial": engine material, when it differs
    mats_by_obj.update(cfg.get("materials_by_object_lod%d" % level, {}))
    # "drop_ahead_lodN": {source material: metres}: its faces further forward of the axle midpoint than that are left
    # out at this LOD (the Vela's auxiliary lamp glasses share the head lamp lens material, which glows from LOD1 on).
    drop_ahead = cfg.get("drop_ahead_lod%d" % level, {})
    # "lift_mm_lodN": {source material: millimetres}: its faces move out along the vertex normals at this LOD. A second
    # paint (stripes) is a shell 1 to 4 mm over the paint; the collapsed body under it moves by more than that and
    # buries a third of the stripes. Only for a material whose faces share no vertex with another material.
    lift = {k: v / 1000.0 for k, v in cfg.get("lift_mm_lod%d" % level, {}).items()}
    mats_used = {}
    rim_area = {}  # source colour -> face area among the M_Rim faces
    rim_face = {}  # source colour -> area of the M_Rim faces that look away from the car: the wheel face (spokes)
    buckets = {}  # node name -> {"verts": [...], "faces": [(vert_indices, target_material, smooth, normals, colour)], "map": {}}

    def nearest_wheel(co):
        return min(WHEELS, key=lambda w: (centres[w][0] - co).length)

    for o in list(bpy.data.objects):
        me = o.data
        for f in me.polygons:
            slot = o.material_slots[f.material_index] if f.material_index < len(o.material_slots) else None
            src_mat = slot.material.name if slot and slot.material else "<none>"
            if src_mat not in mats_map:
                raise SystemExit("unmapped source material: %s (object %s)" % (src_mat, o.name))
            target = mats_by_obj.get(o.name + "|" + src_mat, mats_map[src_mat])
            col = colours.get(src_mat, (1.0, 1.0, 1.0))
            if target == "M_Plate" and f.center.y < 0.0 and cfg.get("front_plate_material"):
                target = cfg["front_plate_material"]  # nose-side plate: a second plate would stretch the rear plate UVs
                col = SPEC["M_Trim"]["base"][:3]  # and it stays a dark recess: in the plate's own colour it is a blank plate
            ov = by_obj_mat.get(o.name + "|" + src_mat, nodes_map.get(src_mat))
            if ov == "drop" or -f.center.y > drop_ahead.get(src_mat, math.inf):  # the nose is -Y
                continue
            wheel_obj = o.name.startswith("Wheel_")
            if wheel_obj and target not in ("M_Tire", "M_BrakeDisc", "M_Caliper"):
                target = cfg.get("wheel_fill_lod%d" % level, "M_Rim")  # wheel parts: tyre, rim, nuts, hub
            routed = wheel_obj or target in ("M_BrakeDisc", "M_Caliper")
            if routed and not wheel_obj and (f.center - centres[nearest_wheel(f.center)][0]).length > BRAKE_REACH_M:
                target, routed = "M_Trim", False  # caliper-coloured body part far from every wheel: it stays body
            if target in MATT_TARGETS and metallic.get(src_mat, 0.0) >= METAL_MIN:
                col = tuple(c * METAL_AS_MATT for c in col)
            if routed:
                w = nearest_wheel(f.center)  # brake parts from the Body (calipers) go to the nearest wheel
                node = ("brake_" if target in ("M_BrakeDisc", "M_Caliper") else "wheel_") + w[-2:]
                if target == "M_Rim":  # the axle is X: +X wheels look to +X
                    wc, ws = centres[w]
                    r = math.hypot(f.center.y - wc.y, f.center.z - wc.z) / (max(ws.y, ws.z) * 0.5)
                    if SPOKE_ZONE[0] <= r <= SPOKE_ZONE[1]:
                        out_x = f.normal.x if wc.x >= 0.0 else -f.normal.x
                        rim_face[col] = rim_face.get(col, 0.0) + f.area * max(0.0, out_x)
            elif ov:
                node = ov
            elif o.name in by_obj:
                node = by_obj[o.name]
            else:
                node = DEFAULT_NODE.get(target, "trim")
            if node == "drop":  # a whole source object dropped at this LOD (by_object)
                continue
            b = buckets.setdefault(node, {"verts": [], "faces": [], "map": {}})
            idx = []
            for vi in f.vertices:
                key = (o.name, vi)
                if key not in b["map"]:
                    b["map"][key] = len(b["verts"])
                    b["verts"].append(me.vertices[vi].co + me.vertices[vi].normal * lift.get(src_mat, 0.0))
                idx.append(b["map"][key])
            # corner normals of the source: they carry the hard panel gaps and creases (lost otherwise: soft, wrinkled flanks)
            if target == "M_Rim":
                rim_area[col] = rim_area.get(col, 0.0) + f.area
            b["faces"].append((idx, target, f.use_smooth, [me.corner_normals[li].vector.copy() for li in f.loop_indices], col))
            mats_used[target] = mats_used.get(target, 0) + 1
    # The wheel face takes the rim colour the player picks at full strength; darker parts (pockets, caps, an inner
    # barrel behind bright spokes) go darker. The face is the colour with the most area looking away from the car in
    # the spoke zone: "the brightest sizeable colour" picked the barrel on black-spoke wheels, and all outward area
    # picked a polished lip; both halved the picked colour on the spokes.
    rim_ref, rim_total = 0.0, sum(rim_area.values())
    if rim_face and max(rim_face.values()) > 0.0:
        rim_ref = luminance(max(rim_face, key=rim_face.get))
    else:
        for c, a in rim_area.items():
            if a >= RIM_REF_SHARE * rim_total:
                rim_ref = max(rim_ref, luminance(c))

    part_ao = bake_part_ao(buckets)
    for mname in mats_used:
        if mname not in KNOWN:
            raise SystemExit("target %s is not an engine material name" % mname)
    tail = tail_boxes(buckets) if cfg.get("tail_cell") is not None else None
    if cfg.get("tail_cell") is not None and tail is None:
        print("WARN LOD%d tail lights skipped: rear light faces too few or one-sided" % level)
    mcfg = cfg if tail or cfg.get("tail_cell") is None else dict(cfg, tail_cell=None)
    materials = {m: make_material(m, mcfg) for m in mats_used}
    for o in list(bpy.data.objects):  # the source objects are replaced by the engine nodes built below
        bpy.data.objects.remove(o, do_unlink=True)

    for name in sorted(buckets):
        b = buckets[name]
        origin = centres[name.replace("brake_", "wheel_")][0] if name[:6] in ("wheel_", "brake_") else Vector((0, 0, 0))
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bverts = [bm.verts.new(v - origin) for v in b["verts"]]
        slot_of, slot_mats = {}, []
        for mname in sorted(set(f[1] for f in b["faces"])):
            slot_of[mname] = len(slot_mats)
            slot_mats.append(materials[mname])
        loop_normals, loop_cols = [], []
        paint_norms = smooth_paint(b["verts"], b["faces"]) if level == 0 else {}
        # Far LODs: one mean shade for the whole rim. The collapse to 12 % of the wheel smears the per-corner pocket
        # shade over the spoke faces (blotchy rims, left and right wheels different, measured on the LOD1 files).
        rim_flat = None
        if level > 0:
            vals = [part_ao[name][i] for idx, target, *_ in b["faces"] if target == "M_Rim" for i in idx]
            rim_flat = sum(vals) / len(vals) if vals else None
        for fi, (idx, target, smooth, norms, col) in enumerate(b["faces"]):
            try:
                f = bm.faces.new([bverts[i] for i in idx])
            except ValueError:
                continue  # degenerate or duplicate after merging
            f.material_index = slot_of[target]
            f.smooth = True
            loop_normals.extend(paint_norms.get(fi, norms))
            base = face_colour(target, col, rim_ref)
            for i in idx:
                k = part_ao[name][i] if target in VC_TARGETS else 1.0
                if target == "M_Rim" and rim_flat is not None:
                    k = rim_flat
                loop_cols.extend((base[0] * k, base[1] * k, base[2] * k, 1.0))
        bm.to_mesh(me)
        if len(loop_cols) == 4 * len(me.loops):
            attr = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
            attr.data.foreach_set("color", loop_cols)
            me.color_attributes.active_color = attr
            me.color_attributes.render_color_index = 0
        else:
            print("WARN %s: %d colours for %d loops, no vertex colours" % (name, len(loop_cols) // 4, len(me.loops)))
        if len(loop_normals) == len(me.loops):
            me.normals_split_custom_set(loop_normals)
        else:
            print("WARN %s: %d source normals for %d loops, normals left to Blender" % (name, len(loop_normals), len(me.loops)))
        bm.free()
        if name == "plate_rear":
            plate_uv(me)
        if tail and "M_LightRear" in slot_of:
            tail_uv(me, tail, cfg["tail_cell"], slot_of["M_LightRear"])
        for m in slot_mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        ob.location = origin

    for name in WHEELS + ["brake_" + w[-2:] for w in WHEELS]:
        if name not in bpy.data.objects:
            print("WARN node %s empty in LOD%d" % (name, level))

    dec = cfg.get("decimate", {}).get(str(level), {})
    strays = {}
    for ob in list(bpy.data.objects):
        kind = "wheel" if ob.name.startswith(("wheel_", "brake_")) else "default"
        ratio = dec.get(ob.name, dec.get(kind, 1.0))
        if ratio < 1.0 and len(ob.data.polygons) > 0:
            before = BVHTree.FromPolygons([v.co.copy() for v in ob.data.vertices], [tuple(p.vertices) for p in ob.data.polygons])
            bpy.context.view_layer.objects.active = ob
            mod = ob.modifiers.new("dec", "DECIMATE")
            mod.decimate_type = "COLLAPSE"
            mod.ratio = ratio
            mod.use_symmetry = not ob.name.startswith(("wheel_", "brake_"))  # symmetry collapse left wheel_RL invalid
            mod.symmetry_axis = "X"
            bpy.ops.object.modifier_apply(modifier=mod.name)
            moved = pull_back_strays(ob, before)
            if moved:
                strays[ob.name] = moved
            # Decimation scrambles the carried normals: smooth shading with hard edges above 35 degrees instead.
            for poly in ob.data.polygons:
                poly.use_smooth = True
            ob.data.set_sharp_from_angle(angle=math.radians(35.0))

    make_col_body(["body", "trim", "underbody"])

    tris = {}
    pts = []
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            ob.data.calc_loop_triangles()
            tris[ob.name] = len(ob.data.loop_triangles)
            if ob.name != "col_body":
                pts += [ob.matrix_world @ v.co for v in ob.data.vertices]
    box = [[min(p[a] for p in pts) for a in range(3)], [max(p[a] for p in pts) for a in range(3)]]  # Blender axes
    total = sum(tris.values())
    surfaces = sum(len(ob.data.materials) for ob in bpy.data.objects if ob.type == "MESH")
    slots = {ob.name: [m.name for m in ob.data.materials] for ob in bpy.data.objects if ob.type == "MESH"}
    # LOD0 only: one empty node per tail pipe outlet, where the nitro flames start (car_fx.gd finds them by name).
    # "tail_pipes" in the config: [x, up, z] of each outlet in the source file's glTF axes (the nose is +z). Only
    # pipes that leave at the tail: flames at the Bruiser's side pipes were hidden from the chase camera by its rear
    # fenders (tried straight back and 35 and 55 degrees outwards), so that car has none and gets the default.
    pipes = cfg.get("tail_pipes", []) if level == 0 else []
    for i, (x, up, z) in enumerate(pipes):
        tip = bpy.data.objects.new("exhaust_tip_%d" % i, None)
        bpy.context.collection.objects.link(tip)
        tip.location = Vector((x, -z, up)) + shift
    stats["lod%d" % level] = {"tris": total, "tris_by_node": tris, "slots_by_node": slots, "surfaces": surfaces,
                              "materials": sorted(mats_used), "material_count": len(mats_used), "box": box,
                              "stray_verts_moved": strays, "tail_pipes": len(pipes)}
    print("LOD%d tris=%d surfaces=%d materials=%d strays=%s" % (level, total, surfaces, len(mats_used), strays or "none"))
    export(os.path.join(out_dir, "%s_lod%d.glb" % (cfg["car_id"], level)), cfg)


# Tail-light atlas: 2 x 3 cells of six tail-light units on a black ground, and a pixel-aligned lit picture (lenses and
# LED strips only). Sources: assets_src/ai_generated/chatgpt/tail_atlas_day.png and tail_atlas_lit.png; shipped once as
# game/assets/vehicles/shared/tail_atlas_day.jpg and tail_atlas_lit.jpg.
TAIL_ASPECT = (1536 / 2) / (1024 / 3)  # one cell is 768 x 341 px
TAIL_MIN_FACES = 12  # per side (left/right of the car): fewer faces and the light is too small to read


def tail_boxes(buckets):
    """Per side (L: x >= 0, R: x < 0) the rear light faces' extent in X and Z, or None when a side is too small."""
    pts = {"L": [], "R": []}
    count = {"L": 0, "R": 0}
    for b in buckets.values():
        for idx, target, *_ in b["faces"]:
            if target != "M_LightRear":
                continue
            cs = [b["verts"][i] for i in idx]
            side = "L" if sum(c.x for c in cs) / len(cs) >= 0.0 else "R"
            count[side] += 1
            pts[side] += cs
    out = {}
    for side in ("L", "R"):
        if count[side] < TAIL_MIN_FACES or not pts[side]:
            return None
        xs = [p.x for p in pts[side]]
        zs = [p.z for p in pts[side]]
        out[side] = (min(xs), max(xs), min(zs), max(zs))
    return out


def tail_uv(me, boxes, cell, slot):
    """Planar rear view on the M_LightRear polygons: u runs right to left across the light (+X to -X), v bottom to
    top. The frame keeps the atlas cell aspect (no stretch) and contains the light's extent."""
    col, row = cell % 2, cell // 2
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        if poly.material_index != slot:
            continue
        x0, x1, z0, z1 = boxes["L" if poly.center.x >= 0.0 else "R"]
        w = max(x1 - x0, (z1 - z0) * TAIL_ASPECT)
        h = w / TAIL_ASPECT
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        for li in poly.loop_indices:
            c = me.vertices[me.loops[li].vertex_index].co
            lu = (cx + w / 2 - c.x) / w
            lv = (c.z - (cz - h / 2)) / h
            uv.data[li].uv = ((col + lu) / 2, (2 - row + lv) / 3)


def plate_uv(me):
    """Planar UVs for the plate: seen from behind, u runs right to left (+X to -X), v bottom to top."""
    uv = me.uv_layers.new(name="UVMap")
    xs = [v.co.x for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    for loop in me.loops:
        c = me.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = ((x1 - c.x) / max(x1 - x0, 1e-6), (c.z - z0) / max(z1 - z0, 1e-6))


def make_col_body(node_names):
    pts = []
    for n in node_names:
        ob = bpy.data.objects.get(n)
        if ob is not None:
            pts += [ob.matrix_world @ v.co for v in ob.data.vertices]
    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in pts]
    res = bmesh.ops.convex_hull(bm, input=verts)
    bmesh.ops.delete(bm, geom=list(set(res["geom_interior"]) | set(res["geom_unused"])), context="VERTS")
    me = bpy.data.meshes.new("col_body")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("col_body", me)
    bpy.context.collection.objects.link(ob)
    for _ in range(4):  # collapse to at most 48 vertices (brief); the ratio aims just under that, no coarser
        if len(me.vertices) <= 48:
            break
        bpy.context.view_layer.objects.active = ob
        mod = ob.modifiers.new("hull", "DECIMATE")
        mod.ratio = min(0.95, 46.0 / len(me.vertices))
        bpy.ops.object.modifier_apply(modifier=mod.name)
    print("col_body verts %d" % len(me.vertices))


def export(path, cfg):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in bpy.data.objects:
        ob.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_copyright=cfg["copyright"],
        export_materials="EXPORT", export_extras=False, export_apply=False, export_yup=True,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False,  # COLOR_0: the source part colours (VC_TARGETS)
    )
    print("EXPORTED", path)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    src, car_id, out_dir = argv[0], argv[1], argv[2]
    cfg_path = arg_value(argv, "config", os.path.join(HERE, "vehicle_configs", car_id + ".json"))
    with open(cfg_path, encoding="utf-8") as fh:
        cfg = json.load(fh)
    if cfg["car_id"] != car_id:
        raise SystemExit("config car_id %s is not %s" % (cfg["car_id"], car_id))
    if cfg.get("plate_image") and not os.path.isabs(cfg["plate_image"]):
        cfg["plate_image"] = os.path.join(ROOT, cfg["plate_image"])
    os.makedirs(out_dir, exist_ok=True)
    stats = {"car_id": car_id, "source": src}
    colours, metallic = source_colours(src)
    colours.update(COLOUR_FIXES)
    print("COLOURS " + ", ".join("%s %.2f/%.2f/%.2f" % (k, v[0], v[1], v[2]) for k, v in sorted(colours.items())))
    colours.update({k: tuple(v) for k, v in cfg.get("source_colours", {}).items()})  # hand-set part colours (linear RGB)
    for level in cfg.get("lods", [0, 1, 2]):
        build_lod(src, cfg, level, out_dir, stats, colours, metallic)
    with open(os.path.join(out_dir, car_id + "_prepare_stats.json"), "w", encoding="utf-8") as fh:
        json.dump(stats, fh, indent=1)
    if "lod0" in stats:
        lo0, hi0 = stats["lod0"]["box"]
        for key in ("lod1", "lod2"):
            lo, hi = stats.get(key, stats["lod0"])["box"]
            out = max([lo0[a] - lo[a] for a in range(3)] + [hi[a] - hi0[a] for a in range(3)])
            if out > LOD_BOX_MARGIN_M:
                raise SystemExit("%s %s reaches %.2f m beyond the LOD0 box" % (car_id, key, out))


main()
