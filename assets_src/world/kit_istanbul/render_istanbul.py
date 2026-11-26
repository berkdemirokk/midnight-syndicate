"""QA renders for the Istanbul kit (EEVEE, night). Run:
  blender.exe --background --factory-startup --python render_istanbul.py -- <group>
Groups: yali | rows | lod | props | sky | skyline_wide
The GLBs are the truth: they are imported and every M_ slot is hooked to the textures named in materials.json
(QA only, the GLBs carry no images).
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

KIT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(KIT, "out")
REN = os.path.join(KIT, "renders")
ROOT = os.path.abspath(os.path.join(KIT, "..", "..", ".."))
GROUP = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "yali"
# ISTANBUL_QA_DAY=1 renders a daylight sky and sun (files get a _day suffix); default is the night QA.
DAY = os.environ.get("ISTANBUL_QA_DAY") == "1"
os.makedirs(REN, exist_ok=True)


def jload(p):
    with open(p) as fh:
        return json.load(fh)


RECS = {}
for p in (os.path.join(ROOT, "game/assets/world/kits/buildings/materials.json"), os.path.join(OUT, "materials.json")):
    RECS.update(jload(p)["materials"])
PROPS_M = jload(os.path.join(ROOT, "game/assets/world/kits/props/materials.json"))["materials"]
for k, v in PROPS_M.items():
    RECS.setdefault(k, v)


def rgb(v):
    if isinstance(v, str):
        h = v.lstrip("#")
        return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return list(v)[:3]


def lin(c):
    return [x ** 2.2 for x in c]


def img(path, cs="sRGB"):
    im = bpy.data.images.load(path, check_existing=True)
    im.colorspace_settings.name = cs
    return im


def abspath(rel):
    if "kits/istanbul/textures/" in rel:
        return os.path.join(OUT, "textures", os.path.basename(rel))
    return os.path.join(ROOT, rel) if rel.startswith("game/") else os.path.join(OUT, rel)


def qa_material(name):
    rec = RECS.get(name)
    m = bpy.data.materials.new("QA_" + name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    if rec is None:
        bsdf.inputs["Base Color"].default_value = lin([0.3, 0.3, 0.3]) + [1]
        return m
    base = rgb(rec.get("base_color", "#808080"))
    bsdf.inputs["Roughness"].default_value = rec.get("roughness", 0.7)
    bsdf.inputs["Metallic"].default_value = rec.get("metallic", 0.0)
    es = rec.get("emission_strength", 0.0)
    ec = rec.get("emission_color")
    if name in ("M_WindowAtlas", "M_ShopInterior"):
        stem = "window_atlas" if name == "M_WindowAtlas" else "shop_interior"
        bdir = os.path.join(ROOT, "game/assets/world/kits/buildings/textures")
        a = nt.nodes.new("ShaderNodeTexImage")
        a.image = img(os.path.join(bdir, stem + "_basecolor.png"))
        e = nt.nodes.new("ShaderNodeTexImage")
        e.image = img(os.path.join(bdir, stem + "_emissive.png"))
        nt.links.new(a.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(e.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 2.4
        return m
    if name == "M_ShopGlass":
        bsdf.inputs["Base Color"].default_value = lin(base) + [1]
        bsdf.inputs["Alpha"].default_value = 0.22
        m.surface_render_method = "BLENDED"
        return m
    if "texture_file" in rec:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img(abspath(rec["texture_file"]))
        nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(t.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.6
        return m
    texs = rec.get("textures")
    if isinstance(texs, dict) and "basecolor" in texs:
        tile = rec.get("uv_tile_m", 2.0)
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (1 / tile, 1 / tile, 1.0)
        nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img(abspath(texs["basecolor"]))
        nt.links.new(mp.outputs["Vector"], t.inputs["Vector"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1.0
        mix.inputs[7].default_value = lin(base) + [1]
        nt.links.new(t.outputs["Color"], mix.inputs[6])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        if "normal" in texs:
            n = nt.nodes.new("ShaderNodeTexImage")
            n.image = img(abspath(texs["normal"]), "Non-Color")
            nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(n.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        return m
    bsdf.inputs["Base Color"].default_value = lin(base) + [1]
    if es and es > 0 and ec:
        bsdf.inputs["Emission Color"].default_value = lin(rgb(ec)) + [1]
        bsdf.inputs["Emission Strength"].default_value = min(es, 9.0)
    return m


_QA = {}


def qa(name):
    if name not in _QA:
        _QA[name] = qa_material(name)
    return _QA[name]


def import_glb(fn, loc=(0, 0, 0), rot=0.0, lods=(0,)):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, fn))   # always the fresh build, never the shipped copy
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    for o in new:
        if o.type == "MESH":
            n = o.name
            if n.startswith("LOD") and int(n[3]) not in lods or "colonly" in n or "-col" in n:
                o.hide_render = True
                o.hide_viewport = True
            for s in o.material_slots:
                if s.material is not None:
                    s.material = qa(s.material.name.split(".")[0])
    for r in roots:
        # glTF import is Y up: the importer converts to Blender Z up already
        r.location = loc
        r.rotation_euler = (0, 0, rot)
    return roots, new


def setup(w=1600, h=900, samples=48, sky=(0.012, 0.02, 0.05)):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.image_settings.file_format = "PNG"
    sc.eevee.taa_render_samples = samples
    sc.view_settings.view_transform = "Standard"
    wd = bpy.data.worlds.new("Night")
    wd.use_nodes = True
    bg = wd.node_tree.nodes["Background"]
    if DAY:
        sky = (0.42, 0.62, 0.92)
    bg.inputs["Color"].default_value = (sky[0], sky[1], sky[2], 1)
    bg.inputs["Strength"].default_value = 1.0
    sc.world = wd
    return sc


def sun(sc, e=0.5):
    s = bpy.data.lights.new("moon", "SUN")
    s.energy = 3.2 if DAY else e
    s.color = (1.0, 0.96, 0.88) if DAY else (0.7, 0.8, 1.0)
    ob = bpy.data.objects.new("moon", s)
    ob.rotation_euler = (math.radians(50), 0, math.radians(35 if DAY else -25))
    sc.collection.objects.link(ob)


def lamp(sc, loc, e=1500.0, col=(1.0, 0.7, 0.42), size=0.3):
    if DAY:
        return
    L = bpy.data.lights.new("l", "POINT")
    L.energy = e
    L.color = col
    L.shadow_soft_size = size
    ob = bpy.data.objects.new("l", L)
    ob.location = loc
    sc.collection.objects.link(ob)


def cam(sc, loc, target, lens=28.0, ortho=None):
    c = bpy.data.cameras.new("c")
    if ortho:
        c.type = "ORTHO"
        c.ortho_scale = ortho
    else:
        c.lens = lens
    ob = bpy.data.objects.new("c", c)
    ob.location = Vector(loc)
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(ob)
    sc.camera = ob


def ground(sc, x0, x1, y0, y1, name="M_Asphalt_QA", color=(0.035, 0.036, 0.04), rough=0.35):
    me = bpy.data.meshes.new("g")
    me.from_pydata([(x0, y0, 0), (x1, y0, 0), (x1, y1, 0), (x0, y1, 0)], [], [(0, 1, 2, 3)])
    ob = bpy.data.objects.new("g", me)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = list(color) + [1]
    b.inputs["Roughness"].default_value = rough
    me.materials.append(m)
    sc.collection.objects.link(ob)
    return ob


def render(path):
    if DAY:
        path = path.replace(".png", "_day.png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def street_scene(files, spacing, w=1600, h=900, back=26.0, eye=1.6, lens=24.0, look_z=6.0, lods=(0,), rot=0.0):
    sc = setup(w, h)
    sun(sc, 0.35)
    n = len(files)
    x = -spacing * (n - 1) / 2
    for fn in files:
        import_glb(fn, (x, 0, 0), rot, lods)
        x += spacing
    ground(sc, -200, 200, -40, -3.5)
    ground(sc, -200, 200, -3.5, 0.0, "M_Walk_QA", (0.09, 0.09, 0.10), 0.7)
    for lx in (-spacing, 0, spacing):
        lamp(sc, (lx * 0.9, -6.0, 5.5), 2200.0)
        lamp(sc, (lx * 0.9 + 3.0, -5.0, 3.0), 600.0, (1.0, 0.8, 0.55))
    cam(sc, (0, -back, eye), (0, 0, look_z), lens)
    return sc


def main():
    if GROUP == "yali":
        sc = street_scene(["bld_yali_a.glb", "bld_yali_b.glb", "bld_yali_c.glb"], 26.0, back=34.0, lens=26.0, look_z=5.0)
        render(os.path.join(REN, "yali_row_front.png"))
    elif GROUP == "yali_road":                       # road-level eye, 1.2 m, about 24 m from the front
        for v in "abc":
            sc = setup(1600, 900)
            sun(sc, 0.35)
            import_glb("bld_yali_%s.glb" % v)
            ground(sc, -80, 80, -50, 0.0)
            ground(sc, -80, 80, 0.0, 9.0, "M_Walk_QA", (0.09, 0.09, 0.10), 0.7)
            cam(sc, (-3.0, -24.0, 1.2), (0, 0, 5.0), 28.0)
            render(os.path.join(REN, "yali_%s_road.png" % v))
    elif GROUP == "rows_road":
        for v in "abc":
            sc = setup(1600, 900)
            sun(sc, 0.35)
            import_glb("bld_ahsap_row_%s.glb" % v)
            ground(sc, -80, 80, -50, 0.0)
            ground(sc, -80, 80, 0.0, 9.0, "M_Walk_QA", (0.09, 0.09, 0.10), 0.7)
            cam(sc, (-4.0, -26.0, 1.2), (0, 0, 4.5), 28.0)
            render(os.path.join(REN, "rows_%s_road.png" % v))
    elif GROUP == "yali_close":                      # detail check: front of yali a, 12 m away, 1.6 m eye
        sc = setup(1600, 900)
        sun(sc, 0.35)
        import_glb("bld_yali_a.glb")
        ground(sc, -80, 80, -50, 0.0)
        cam(sc, (-4.0, -13.0, 1.6), (1.0, 0.0, 4.5), 35.0)
        render(os.path.join(REN, "yali_a_close.png"))
    elif GROUP == "yali3q":
        for v in "abc":
            sc = setup(1600, 900)
            sun(sc, 0.35)
            import_glb("bld_yali_%s.glb" % v)
            ground(sc, -80, 80, -50, 0.0)
            lamp(sc, (-10, -9, 5.5), 2600.0)
            lamp(sc, (9, -8, 4.0), 1200.0)
            cam(sc, (-19, -22, 2.4), (0, 0, 5.2), 30.0)
            render(os.path.join(REN, "yali_%s_3q.png" % v))
    elif GROUP == "rows":
        sc = street_scene(["bld_ahsap_row_a.glb", "bld_ahsap_row_b.glb", "bld_ahsap_row_c.glb"], 23.0, back=30.0, lens=26.0, look_z=6.0)
        render(os.path.join(REN, "rows_front.png"))
    elif GROUP == "rows3q":
        for v in "abc":
            sc = setup(1600, 900)
            sun(sc, 0.35)
            import_glb("bld_ahsap_row_%s.glb" % v)
            ground(sc, -80, 80, -50, 0.0)
            lamp(sc, (-8, -8, 5.5), 2600.0)
            lamp(sc, (8, -7, 4.0), 1200.0)
            cam(sc, (-16, -19, 2.0), (0, 0, 6.5), 30.0)
            render(os.path.join(REN, "row_%s_3q.png" % v))
    elif GROUP == "lod":
        sc = setup(1600, 700)
        sun(sc, 0.35)
        x = -70.0
        for fn in ("bld_yali_a.glb", "bld_ahsap_row_a.glb"):
            for lod in (0, 1, 2):
                import_glb(fn, (x, 0, 0), 0.0, (lod,))
                x += 26.0
            x += 6.0
        ground(sc, -150, 150, -60, 20)
        lamp(sc, (0, -15, 12), 6000.0, (1.0, 0.85, 0.7))
        cam(sc, (0, -150, 5.0), (0, 0, 5.0), ortho=None, lens=30.0)
        render(os.path.join(REN, "lod_compare.png"))
    elif GROUP == "props":
        sc = setup(1800, 900, sky=(0.02, 0.03, 0.06))
        sun(sc, 0.4)
        items = [("prop_tram_rail_segment.glb", 0.0), ("prop_cobble_strip.glb", 0.0)]
        ground(sc, -60, 60, -30, 30)
        row1 = [("prop_promenade_lamp.glb", -9.0), ("prop_ferry_pier_light.glb", -6.5), ("prop_simit_cart.glb", -3.0),
                ("prop_fish_cart.glb", 0.0)]
        for fn, x in row1:
            import_glb(fn, (x, 0, 0))
        import_glb("prop_seaside_railing.glb", (3.0, 0, 0))
        import_glb("prop_tram_rail_segment.glb", (-6.0, 8.0, 0))
        import_glb("prop_cobble_strip.glb", (-6.0, 4.0, 0))
        lamp(sc, (-9, -3, 4.2), 700.0)
        lamp(sc, (-6.5, -3, 4.9), 500.0, (0.75, 0.86, 1.0))
        lamp(sc, (-3, -3, 1.6), 150.0)
        lamp(sc, (0, -3, 1.8), 200.0, (1.0, 0.6, 0.3))
        lamp(sc, (5, -4, 3.0), 400.0)
        cam(sc, (-3, -12, 3.2), (-1.5, 3.0, 1.4), lens=28.0)
        render(os.path.join(REN, "props_sheet.png"))
    elif GROUP == "props_close":
        sc = setup(1600, 900, sky=(0.02, 0.03, 0.06))
        sun(sc, 0.5)
        ground(sc, -60, 60, -30, 30)
        import_glb("prop_simit_cart.glb", (-1.6, 0, 0))
        import_glb("prop_fish_cart.glb", (1.9, 0, 0))
        lamp(sc, (-1.6, -1.2, 1.5), 90.0)
        lamp(sc, (1.9, -1.2, 1.8), 130.0, (1.0, 0.6, 0.3))
        lamp(sc, (0, -4, 3.0), 300.0)
        cam(sc, (0.2, -8.5, 1.8), (0.2, 0, 1.0), lens=30.0)
        render(os.path.join(REN, "props_carts.png"))
        sc2 = None
    elif GROUP == "tram":
        sc = setup(1600, 900, sky=(0.02, 0.03, 0.06))
        sun(sc, 0.5)
        ground(sc, -60, 60, -30, 30)
        import_glb("prop_tram_rail_segment.glb", (-6.0, 0, 0))
        import_glb("prop_cobble_strip.glb", (-6.0, -4.5, 0))
        import_glb("prop_seaside_railing.glb", (-3.0, 6.0, 0))
        import_glb("prop_promenade_lamp.glb", (4.0, 6.0, 0))
        import_glb("prop_ferry_pier_light.glb", (6.0, 6.0, 0))
        lamp(sc, (4, 5, 4.3), 600.0)
        lamp(sc, (6, 5, 4.8), 500.0, (0.75, 0.86, 1.0))
        lamp(sc, (0, -3, 7), 3000.0, (1.0, 0.85, 0.7))
        cam(sc, (-14, -11, 2.4), (-2, 1.0, 2.0), lens=26.0)
        render(os.path.join(REN, "props_street.png"))
    elif GROUP in ("sky", "skyline_wide"):
        for fn, tag, sc_h in (("prop_skyline_asia_hills.glb", "asia", 60), ("prop_skyline_bridge.glb", "bridge", 60),
                              ("prop_skyline_domes.glb", "domes", 60)):
            sc = setup(1800, 600, sky=(0.03, 0.05, 0.11))
            import_glb(fn)
            dist = 520.0
            cam(sc, (0, -520, 50), (0, 0, 50), lens=34.0)
            render(os.path.join(REN, "skyline_%s.png" % tag))


main()
