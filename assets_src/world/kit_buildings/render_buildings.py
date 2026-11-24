"""QA renders for the building kit (EEVEE, night). Run through build_buildings.py -- render <group>.

Groups: beauty (one street-level shot per type, 14 m road between camera and facade),
sheet (elevation line-up of all variant-a LOD0 buildings), close (shopfront, window reveal, rooftop).
The GLBs are the truth: they are imported, then each named M_ slot is hooked to the CC0 set or
generated texture of the same name. Textures exist only in these QA materials, never in the GLBs.
"""
import json
import math
import os

import bpy
from mathutils import Vector

W_PX, H_PX = 1600, 900


def _img(path, colorspace="sRGB"):
    im = bpy.data.images.load(path, check_existing=True)
    try:
        im.colorspace_settings.name = colorspace
    except Exception:
        pass
    return im


def _qa_textured(name, basecolor, normal=None, rough=None, tile=None, emit=None, emit_strength=0.0,
                 flat=None):
    m = bpy.data.materials.new("QA_" + name)
    m.use_nodes = True
    nt = m.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = (flat.get("rough", flat.get("roughness", 0.8))) if flat else 0.8
    if tile is not None:
        tc = nodes.new("ShaderNodeTexCoord")
        mp = nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (1.0 / tile, 1.0 / tile, 1.0)
        links.new(tc.outputs["UV"], mp.inputs["Vector"])
    if basecolor:
        it = nodes.new("ShaderNodeTexImage")
        it.image = _img(basecolor, "sRGB")
        if tile is not None:
            links.new(mp.outputs["Vector"], it.inputs["Vector"])
        links.new(it.outputs["Color"], bsdf.inputs["Base Color"])
    if rough:
        ir = nodes.new("ShaderNodeTexImage")
        ir.image = _img(rough, "Non-Color")
        if tile is not None:
            links.new(mp.outputs["Vector"], ir.inputs["Vector"])
        links.new(ir.outputs["Color"], bsdf.inputs["Roughness"])
    if normal:
        inr = nodes.new("ShaderNodeTexImage")
        inr.image = _img(normal, "Non-Color")
        if tile is not None:
            links.new(mp.outputs["Vector"], inr.inputs["Vector"])
        nm = nodes.new("ShaderNodeNormalMap")
        links.new(inr.outputs["Color"], nm.inputs["Color"])
        links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if emit:
        ie = nodes.new("ShaderNodeTexImage")
        ie.image = _img(emit, "sRGB")
        links.new(ie.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    return m


def _qa_flat(name, rec):
    m = bpy.data.materials.new("QA_" + name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    h = rec["base_color"].lstrip("#")
    rgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    bsdf.inputs["Base Color"].default_value = [c ** 2.2 for c in rgb] + [1.0]
    bsdf.inputs["Roughness"].default_value = rec["roughness"]
    bsdf.inputs["Metallic"].default_value = rec["metallic"]
    if rec["emission_strength"] > 0:
        e = rec["emission_color"].lstrip("#")
        erg = [int(e[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
        bsdf.inputs["Emission Color"].default_value = [c ** 2.2 for c in erg] + [1.0]
        bsdf.inputs["Emission Strength"].default_value = rec["emission_strength"]
    return m


def qa_library(root, out, mats_doc, cc0_extra):
    lib = {}
    for name, rec in mats_doc["materials"].items():
        if name == "M_CollisionOnly":
            continue
        if "textures" in rec:
            t = rec["textures"]
            lib[name] = _qa_textured(name, os.path.join(root, t["basecolor"]), os.path.join(root, t["normal"]),
                                     os.path.join(root, t["roughness"]), tile=rec["uv_tile_m"])
        elif name == "M_WindowAtlas":
            lib[name] = _qa_textured(name, os.path.join(out, "window_atlas_basecolor.png"), emit=os.path.join(out, "window_atlas_emissive.png"),
                                     emit_strength=3.0, flat=rec)
        elif name == "M_ShopInterior":
            lib[name] = _qa_textured(name, os.path.join(out, "shop_interior_basecolor.png"), emit=os.path.join(out, "shop_interior_emissive.png"),
                                     emit_strength=2.0, flat=rec)
        elif name == "M_ShopGlass":
            # QA only: the engine glass is translucent, so the lit interior card shows through
            lib[name] = _qa_flat(name, rec)
            bsdf = lib[name].node_tree.nodes["Principled BSDF"]
            bsdf.inputs["Alpha"].default_value = 0.22
            try:
                lib[name].surface_render_method = "BLENDED"
            except Exception:
                pass
        else:
            lib[name] = _qa_flat(name, rec)
    for name, (cc, tile) in cc0_extra.items():
        base = os.path.join(root, "game/assets/textures/cc0", cc)
        lib[name] = _qa_textured(name, os.path.join(base, "basecolor.jpg"), os.path.join(base, "normal.jpg"),
                                 os.path.join(base, "roughness.jpg"), tile=tile)
    return lib


def clear_all():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def setup_render(samples=32):
    sc = bpy.context.scene
    try:
        sc.render.engine = "BLENDER_EEVEE"
    except Exception:
        pass
    sc.render.resolution_x = W_PX
    sc.render.resolution_y = H_PX
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    try:
        sc.eevee.taa_render_samples = samples
    except Exception:
        pass
    try:
        sc.view_settings.view_transform = "AgX"
    except Exception:
        pass
    wd = bpy.data.worlds.new("NightWorld")
    wd.use_nodes = True
    bg = wd.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.004, 0.006, 0.014, 1.0)
    bg.inputs["Strength"].default_value = 1.0
    sc.world = wd
    return sc


def add_sun(sc):
    sun = bpy.data.lights.new("KeyCool", "SUN")
    sun.energy = 0.45
    sun.color = (0.75, 0.85, 1.0)
    sun.angle = math.radians(4)
    ob = bpy.data.objects.new("KeyCool", sun)
    ob.rotation_euler = (math.radians(58), 0.0, math.radians(-30))
    sc.collection.objects.link(ob)


def add_lamp(sc, name, loc, energy=900.0, color=(1.0, 0.7, 0.42)):
    L = bpy.data.lights.new(name, "POINT")
    L.energy = energy
    L.color = color
    L.shadow_soft_size = 0.3
    ob = bpy.data.objects.new(name, L)
    ob.location = loc
    sc.collection.objects.link(ob)


def add_camera(sc, loc, target, lens=28.0, ortho=None):
    cam = bpy.data.cameras.new("Cam")
    if ortho:
        cam.type = "ORTHO"
        cam.ortho_scale = ortho
    else:
        cam.lens = lens
    ob = bpy.data.objects.new("Cam", cam)
    ob.location = Vector(loc)
    d = Vector(target) - Vector(loc)
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(ob)
    sc.camera = ob
    return ob


def street_planes(mod, sc, qa):
    b = mod.Builder()
    b.poly([(-80, -17.5, 0), (80, -17.5, 0), (80, -3.5, 0), (-80, -3.5, 0)], (0, 0, 1), "M_Asphalt_Main")
    b.poly([(-80, -3.5, 0.0), (80, -3.5, 0.0), (80, 0.0, 0.0), (-80, 0.0, 0.0)], (0, 0, 1), "M_Sidewalk_Tile")
    b.poly([(-80, -21.0, 0), (80, -21.0, 0), (80, -17.5, 0), (-80, -17.5, 0)], (0, 0, 1), "M_Sidewalk_Tile")
    o = mod.mesh_object("QA_street", b, None)
    for slot in o.material_slots:
        if slot.material is not None and slot.material.name in qa:
            slot.material = qa[slot.material.name]
    return o


def import_building(path, qa, tag):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    root = [o for o in new if o.parent is None and o.type == "EMPTY"][0]
    for o in new:
        if o.type == "MESH":
            name = o.name
            if name.endswith("colonly") or name in ("LOD1", "LOD2"):
                o.hide_render = True
                o.hide_viewport = True
                continue
            for slot in o.material_slots:
                if slot.material is None:
                    continue
                base = slot.material.name.split(".")[0]
                if base == "M_ImpostorAtlas":
                    slot.material = qa["imp_" + tag]
                elif base in qa:
                    slot.material = qa[base]
        elif o.type == "EMPTY" and o is not root:
            o.hide_render = True
    return root, new


def render_to(sc, path):
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)


def run(args, mod):
    group = args[0] if args else "beauty"
    root = mod.ROOT
    out = mod.OUT
    rend = mod.REN
    os.makedirs(rend, exist_ok=True)
    with open(os.path.join(out, "materials.json"), "r") as fh:
        mats_doc = json.load(fh)
    clear_all()
    sc = setup_render(32)
    mod.CC0_SLOTS["M_Asphalt_Main"] = ("asphalt_02", 4.0, 0.6, 0.0, "#202020")
    mod.CC0_SLOTS["M_Sidewalk_Tile"] = ("concrete_pavement_03", 2.0, 0.8, 0.0, "#888888")
    qa_extra = {"M_Asphalt_Main": ("asphalt_02", 4.0), "M_Sidewalk_Tile": ("concrete_pavement_03", 2.0)}
    qa = qa_library(root, out, mats_doc, qa_extra)
    for bld in mats_doc["materials"]:
        pass
    cat = json.load(open(os.path.join(out, "catalog.json"), "r"))
    entries = {e["id"]: e for e in cat["buildings"]}

    def fresh_scene(extra_loc=None):
        clear_all()
        for k in list(bpy.data.lights.keys()):
            pass
        add_sun(sc)
        for x in (-12.0, 0.0, 12.0):
            add_lamp(sc, "Lamp%d" % int(x), (x, -1.8, 6.0))
        street_planes(mod, sc, qa)

    if group == "beauty":
        for ent in cat["buildings"]:
            if not ent["id"].endswith("_a"):
                continue
            fresh_scene()
            tag = ent["id"]
            qa["imp_" + tag] = _qa_textured("Imp_" + tag, os.path.join(out, "impostor_%s_basecolor.png" % tag),
                                            emit=os.path.join(out, "impostor_%s_emissive.png" % tag), emit_strength=2.0,
                                            flat=dict(rough=0.8))
            import_building(os.path.join(out, tag + ".glb"), qa, tag)
            tgt = (0.0, 12.0, min(max(ent["height"] * 0.12, 7.0), 18.0))   # street level: shopfronts, kerb, lower tower
            add_camera(sc, (0.0, -20.5, 1.6), tgt, lens=28.0)
            render_to(sc, os.path.join(rend, "beauty_%s.png" % ent["type"]))
            if ent["type"].startswith("bld_downtown"):
                # tall framing: a 28 mm frame needs about 200 m back to hold the whole tower (crown included)
                clear_all()
                add_sun(sc)
                g = mod.Builder()
                g.poly([(-400, -400, 0), (400, -400, 0), (400, 20, 0), (-400, 20, 0)], (0, 0, 1), "M_Asphalt_Main")
                go = mod.mesh_object("QA_far_ground", g, None)
                for slot in go.material_slots:
                    if slot.material is not None and slot.material.name in qa:
                        slot.material = qa[slot.material.name]
                import_building(os.path.join(out, tag + ".glb"), qa, tag)
                dist = max(200.0, 1.6 * ent["height"])   # keeps base and crown inside the 28 mm frame
                add_camera(sc, (0.0, -dist, 1.6), (0.0, 0.0, 0.5 * ent["height"] + 1.6), lens=28.0)
                render_to(sc, os.path.join(rend, "beauty_full_%s.png" % ent["type"]))
    elif group == "sheet":
        fresh_scene()
        x = 0.0
        xs = []
        for ent in cat["buildings"]:
            if not ent["id"].endswith("_a"):
                continue
            tag = ent["id"]
            qa["imp_" + tag] = _qa_textured("Imp_" + tag, os.path.join(out, "impostor_%s_basecolor.png" % tag),
                                            emit=os.path.join(out, "impostor_%s_emissive.png" % tag), emit_strength=2.0,
                                            flat=dict(rough=0.8))
            root_o, _ = import_building(os.path.join(out, tag + ".glb"), qa, tag)
            xs.append(x + ent["width"] / 2.0)
            root_o.location = (x + ent["width"] / 2.0, 0.0, 0.0)
            x += ent["width"] + 10.0
        centre = (x - 10.0) / 2.0
        add_camera(sc, (centre, -320.0, 90.0), (centre, 0.0, 90.0), ortho=max((x - 10.0) * 1.06, 340.0))
        render_to(sc, os.path.join(rend, "lineup_elevation.png"))
    elif group == "close":
        tag = "bld_neon_01_a"
        fresh_scene()
        qa["imp_" + tag] = _qa_textured("Imp_" + tag, os.path.join(out, "impostor_%s_basecolor.png" % tag),
                                        emit=os.path.join(out, "impostor_%s_emissive.png" % tag), emit_strength=2.0,
                                        flat=dict(rough=0.8))
        import_building(os.path.join(out, tag + ".glb"), qa, tag)
        add_camera(sc, (-4.3, -7.0, 2.4), (-4.3, 0.0, 3.0), lens=35.0)
        render_to(sc, os.path.join(rend, "close_shopfront.png"))
        tag = "bld_neon_03_a"
        fresh_scene()
        qa["imp_" + tag] = _qa_textured("Imp_" + tag, os.path.join(out, "impostor_%s_basecolor.png" % tag),
                                        emit=os.path.join(out, "impostor_%s_emissive.png" % tag), emit_strength=2.0,
                                        flat=dict(rough=0.8))
        import_building(os.path.join(out, tag + ".glb"), qa, tag)
        add_camera(sc, (-7.0, -7.5, 10.0), (-4.0, 0.0, 13.0), lens=35.0)
        render_to(sc, os.path.join(rend, "close_window_reveal.png"))
        add_camera(sc, (3.0, -14.0, 60.0), (0.0, 6.0, 66.0), lens=35.0)
        render_to(sc, os.path.join(rend, "close_rooftop.png"))
    print("DONE", group)
