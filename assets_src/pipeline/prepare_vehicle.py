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
import bpy
import json
import os
import sys
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
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


def make_material(name, cfg, src_images):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    v = SPEC[name]
    set_in(bsdf, "Base Color", v["base"])
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
    if name == "M_Plate" and cfg.get("plate_image"):
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(cfg["plate_image"], check_existing=True)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    src = cfg.get("texture_from", {}).get(name)
    for kind, img in src_images.get(src, {}).items() if src else []:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        if kind == "normal":
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(tex.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        elif kind == "base" and name == "M_Carbon":
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def source_images():
    """Source material name -> {'normal': image, 'base': image}: the first image texture of each kind in that material."""
    out = {}
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        found = {}
        for n in mat.node_tree.nodes:
            if n.bl_idname == "ShaderNodeTexImage" and n.image is not None:
                kind = "normal" if "normal" in n.image.name.lower() else "base"
                found.setdefault(kind, n.image)
        out[mat.name] = found
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


def build_lod(src, cfg, level, out_dir, stats):
    load_source(src)
    imgs = source_images()
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
    mats_used = {}
    buckets = {}  # node name -> {"verts": [...], "faces": [(vert_indices, target_material, smooth)], "map": {}}

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
            ov = by_obj_mat.get(o.name + "|" + src_mat, nodes_map.get(src_mat))
            if ov == "drop":
                continue
            wheel_obj = o.name.startswith("Wheel_")
            if wheel_obj and target not in ("M_Tire", "M_BrakeDisc", "M_Caliper"):
                target = cfg.get("wheel_fill_lod%d" % level, "M_Rim")  # wheel parts: tyre, rim, nuts, hub
            routed = wheel_obj or target in ("M_BrakeDisc", "M_Caliper")
            if routed and not wheel_obj and (f.center - centres[nearest_wheel(f.center)][0]).length > BRAKE_REACH_M:
                target, routed = "M_Trim", False  # caliper-coloured body part far from every wheel: it stays body
            if routed:
                w = nearest_wheel(f.center)  # brake parts from the Body (calipers) go to the nearest wheel
                node = ("brake_" if target in ("M_BrakeDisc", "M_Caliper") else "wheel_") + w[-2:]
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
                    b["verts"].append(me.vertices[vi].co.copy())
                idx.append(b["map"][key])
            b["faces"].append((idx, target, f.use_smooth))
            mats_used[target] = mats_used.get(target, 0) + 1

    for mname in mats_used:
        if mname not in KNOWN:
            raise SystemExit("target %s is not an engine material name" % mname)
    materials = {m: make_material(m, cfg, imgs) for m in mats_used}
    for o in list(bpy.data.objects):  # the source objects are replaced by the engine nodes built below
        bpy.data.objects.remove(o, do_unlink=True)

    for name in sorted(buckets):
        b = buckets[name]
        origin = centres[name.replace("brake_", "wheel_")][0] if name[:6] in ("wheel_", "brake_") else Vector((0, 0, 0))
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bverts = [bm.verts.new(v - origin) for v in b["verts"]]
        slot_of, slot_mats = {}, []
        for mname in sorted(set(t for _, t, _ in b["faces"])):
            slot_of[mname] = len(slot_mats)
            slot_mats.append(materials[mname])
        for idx, target, smooth in b["faces"]:
            try:
                f = bm.faces.new([bverts[i] for i in idx])
            except ValueError:
                continue  # degenerate or duplicate after merging
            f.material_index = slot_of[target]
            f.smooth = smooth
        bm.to_mesh(me)
        bm.free()
        if name == "plate_rear":
            plate_uv(me)
        for m in slot_mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        ob.location = origin

    for name in WHEELS + ["brake_" + w[-2:] for w in WHEELS]:
        if name not in bpy.data.objects:
            print("WARN node %s empty in LOD%d" % (name, level))

    dec = cfg.get("decimate", {}).get(str(level), {})
    for ob in list(bpy.data.objects):
        kind = "wheel" if ob.name.startswith(("wheel_", "brake_")) else "default"
        ratio = dec.get(ob.name, dec.get(kind, 1.0))
        if ratio < 1.0 and len(ob.data.polygons) > 0:
            bpy.context.view_layer.objects.active = ob
            mod = ob.modifiers.new("dec", "DECIMATE")
            mod.decimate_type = "COLLAPSE"
            mod.ratio = ratio
            mod.use_symmetry = not ob.name.startswith(("wheel_", "brake_"))  # symmetry collapse left wheel_RL invalid
            mod.symmetry_axis = "X"
            bpy.ops.object.modifier_apply(modifier=mod.name)

    make_col_body(["body", "trim", "underbody"])

    tris = {}
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            ob.data.calc_loop_triangles()
            tris[ob.name] = len(ob.data.loop_triangles)
    total = sum(tris.values())
    surfaces = sum(len(ob.data.materials) for ob in bpy.data.objects if ob.type == "MESH")
    slots = {ob.name: [m.name for m in ob.data.materials] for ob in bpy.data.objects if ob.type == "MESH"}
    stats["lod%d" % level] = {"tris": total, "tris_by_node": tris, "slots_by_node": slots, "surfaces": surfaces,
                              "materials": sorted(mats_used), "material_count": len(mats_used)}
    print("LOD%d tris=%d surfaces=%d materials=%d" % (level, total, surfaces, len(mats_used)))
    export(os.path.join(out_dir, "%s_lod%d.glb" % (cfg["car_id"], level)), cfg)


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
    for level in cfg.get("lods", [0, 1, 2]):
        build_lod(src, cfg, level, out_dir, stats)
    with open(os.path.join(out_dir, car_id + "_prepare_stats.json"), "w", encoding="utf-8") as fh:
        json.dump(stats, fh, indent=1)


main()
