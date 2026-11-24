"""Evidence renders for the CITY 01 props kit (Blender 5.3, EEVEE).

Run:  blender.exe --background --factory-startup --python render_props.py -- <scene>
scene: contact | signs | corner | bay
Imports the real GLBs from out/, re-binds every M_ slot from the shared material library
(the same bmat() used by build_props.py) and renders 1600x900 PNGs into renders/.
"""
import glob
import json
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_props as bp  # noqa: E402  (module-level code only defines things; main() is guarded)

OUT = bp.OUT
RENDERS = os.path.join(HERE, "renders")
os.makedirs(RENDERS, exist_ok=True)
CC0 = r"C:\Users\berk\car race\game\assets\textures\cc0"


def argv_scene():
    if "--" in sys.argv:
        args = sys.argv[sys.argv.index("--") + 1:]
        if args:
            return args[0]
    return "contact"


def reset_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


def setup_render(path_png):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 900
    sc.render.resolution_percentage = 100
    sc.render.filepath = path_png
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.eevee.taa_render_samples = 48
    try:
        sc.eevee.use_raytracing = True
    except Exception:
        pass
    world = bpy.data.worlds.new("night")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.012, 0.018, 0.032, 1.0)
    bg.inputs["Strength"].default_value = 1.0
    sc.world = world
    # glow: Blender 5.3 keeps the compositor in a node group and the Glare type is an input socket
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
        out = ng.nodes.new("NodeGroupOutput")
        ng.links.new(rl.outputs["Image"], gl.inputs["Image"])
        ng.links.new(gl.outputs["Image"], out.inputs["Image"])
    except Exception as e:  # pragma: no cover
        print("[render] glow node unavailable:", e)


def tex_material(name, rel_dir, rough=0.5, scale=(1.0, 1.0, 1.0)):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = scale
    img = bpy.data.images.load(os.path.join(CC0, rel_dir, "basecolor.jpg"), check_existing=True)
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = img
    nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], tn.inputs["Vector"])
    nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    return m


def flat_material(name, col, rough=0.5, metal=0.0, emit=None, estr=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (emit[0], emit[1], emit[2], 1.0)
        b.inputs["Emission Strength"].default_value = estr
    return m


def add_plane(name, size_x, size_y, loc, rot_x_deg, mat):
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=loc)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (size_x, size_y, 1.0)
    ob.rotation_euler = (math.radians(rot_x_deg), 0, 0)
    ob.data.materials.append(mat)
    bpy.context.view_layer.update()
    return ob


def add_area(loc, size, energy, color, rot_x=0.0, rot_z=0.0):
    ld = bpy.data.lights.new("fill", "AREA")
    ld.energy = energy
    ld.color = color
    ld.size = size
    ob = bpy.data.objects.new("fill", ld)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (math.radians(rot_x), 0, math.radians(rot_z))
    return ob


def add_sun(rot_x, rot_z, strength, color):
    ld = bpy.data.lights.new("sun", "SUN")
    ld.energy = strength
    ld.color = color
    ld.use_shadow = False
    ob = bpy.data.objects.new("sun", ld)
    bpy.context.scene.collection.objects.link(ob)
    ob.rotation_euler = (math.radians(rot_x), 0, math.radians(rot_z))
    return ob


def add_point(loc, energy, color, radius=0.2):
    ld = bpy.data.lights.new("pt", "POINT")
    ld.energy = energy
    ld.color = color
    ld.shadow_soft_size = radius
    ob = bpy.data.objects.new("pt", ld)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    return ob


def add_camera(loc, target, lens=35.0):
    cd = bpy.data.cameras.new("cam")
    cd.lens = lens
    cd.clip_end = 2000.0
    ob = bpy.data.objects.new("cam", cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    d = Vector(target) - Vector(loc)
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = ob
    return ob


def add_text(txt, loc, rot_x=90.0, rot_z=0.0, size=0.5, mat=None):
    cu = bpy.data.curves.new("lab", "FONT")
    cu.body = txt
    cu.extrude = 0.01
    ob = bpy.data.objects.new("lab", cu)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (math.radians(rot_x), 0, math.radians(rot_z))
    ob.scale = (size, size, size)
    if mat is not None:
        ob.data.materials.append(mat)
    return ob


def import_prop(pid, loc, rot_z=0.0, scale=1.0):
    path = os.path.join(OUT, "prop_%s.glb" % pid)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    for o in new:
        if o.type == "MESH":
            for slot in o.material_slots:
                if slot.material is not None:
                    base = slot.material.name.split(".")[0]
                    if base in bp.MATS:
                        slot.material = bp.bmat(base)
    for r in roots:
        r.location = Vector(loc)
        r.rotation_euler = (0, 0, math.radians(rot_z))
        r.scale = (scale, scale, scale)
    return roots


def fit_scale(pid, cell):
    # read the catalog size (Godot axes) to choose a legibility scale for the contact sheet
    cat = json.load(open(os.path.join(OUT, "catalog.json"), encoding="utf-8"))
    for it in cat["items"]:
        if it["id"] == pid:
            s = max(it["size"])
            return min(cell / s, 3.0)
    return 1.0


def scene_contact():
    reset_scene()
    setup_render(os.path.join(RENDERS, "contact_sheet.png"))
    ground = bp.MATS  # noqa
    dark = flat_material("M_Ground", (0.02, 0.022, 0.03), 0.22)
    add_plane("ground", 200, 200, (0, 0, 0), 0, dark)
    add_sun(60, 0, 2.2, (0.75, 0.85, 1.0))
    add_sun(35, 180, 0.5, (0.6, 0.7, 1.0))
    cat = json.load(open(os.path.join(OUT, "catalog.json"), encoding="utf-8"))
    ids = [it["id"] for it in cat["items"]]
    cell = 11.0
    cols = 7
    lab = flat_material("M_Label", (0.9, 0.9, 0.9), 0.5, 0.0, (0.9, 0.9, 0.9), 2.0)
    for i, pid in enumerate(ids):
        col = i % cols
        row = i // cols
        cx = (col - (cols - 1) / 2.0) * cell
        cy = -row * cell
        sc = fit_scale(pid, cell * 0.8)
        if pid == "skyline_card":
            sc = 0.02
        import_prop(pid, (cx, cy, 0.0), 0.0, sc)
        add_text(pid, (cx - cell * 0.46, cy - 4.6, 0.02), 90.0, 0.0, 0.75, lab)
    add_camera((0, -78, 150), (0, -30, 6), 50)
    bpy.context.scene.render.filepath = os.path.join(RENDERS, "contact_sheet.png")
    bpy.ops.render.render(write_still=True)


def scene_signs():
    reset_scene()
    setup_render(os.path.join(RENDERS, "neon_sign_wall.png"))
    bpy.context.scene.render.filepath = os.path.join(RENDERS, "neon_sign_wall.png")
    brick = tex_material("M_Brick", "dark_brick_wall", 0.8, (0.25, 0.25, 0.25))
    wall = add_plane("brick_wall", 80, 30, (0, 0, 15), 90, brick)
    gutter = flat_material("M_Ground", (0.02, 0.022, 0.03), 0.2)
    add_plane("ground", 200, 200, (0, -10, 0), 0, gutter)
    add_sun(60, 0, 2.4, (0.75, 0.85, 1.0))
    place = [
        ("sign_blade_kirin_noodle_bar", -26, 3.2, 0), ("sign_blade_hotel_arden", -18.5, 3.2, 0),
        ("sign_blade_pixel_arcade", -11, 3.2, 0), ("sign_blade_syndicate_club", -4, 3.2, 0),
        ("sign_blade_kapi_doner", 3.5, 3.2, 0),
        ("sign_box_lumen_cinema_4m", -20, 8.0, 0), ("sign_box_volt_energy_4m", -11, 8.0, 0),
        ("sign_box_orbit_records_8m", 0.5, 8.0, 0), ("sign_box_blue_heron_sushi_8m", 13, 8.0, 0),
        ("sign_arrow_night_owl_diner", -25, 13.0, 0), ("sign_open24h_moto_garage", -14, 13.0, 0),
        ("sign_billboard_zenith_tower_12x5", 19, 12.0, 0),
    ]
    for pid, x, z, rz in place:
        import_prop(pid, (x, 0.0, z), rz, 1.0)
    roof = flat_material("M_Roof", (0.05, 0.05, 0.06), 0.8)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(19.0, -4.0, 11.7))
    rb = bpy.context.active_object
    rb.name = "roof_slab"
    rb.scale = (26.0, 8.0, 0.6)
    rb.data.materials.append(roof)
    add_camera((8.0, -46.0, 9.0), (-4.0, 0.0, 9.0), 26)
    bpy.ops.render.render(write_still=True)
    bpy.context.scene.render.filepath = os.path.join(RENDERS, "neon_blade_signs.png")
    add_camera((4.0, -9.0, 3.4), (-16.0, -0.5, 3.4), 35)
    bpy.ops.render.render(write_still=True)


def scene_corner():
    reset_scene()
    setup_render(os.path.join(RENDERS, "street_corner.png"))
    asph = tex_material("M_Road", "asphalt_02", 0.22, (0.2, 0.2, 0.2))
    paver = tex_material("M_Pavers", "concrete_pavers_02", 0.5, (0.5, 0.5, 0.5))
    brick = tex_material("M_Brick", "dark_brick_wall", 0.8, (0.3, 0.3, 0.3))
    add_plane("road", 80, 20, (0, -12, 0), 0, asph)
    add_plane("sidewalk", 80, 3.5, (0, 1.75, 0.02), 0, paver)
    add_plane("facade", 80, 14, (0, 3.6, 7.0), 90, brick)
    add_sun(62, 0, 2.2, (0.75, 0.85, 1.0))
    add_point((-3.5, -0.6, 8.5), 600, (0.5, 0.82, 1.0), 0.1)
    for pid, x, y, rz in [("lamp_sodium", -6.0, 1.2, 0.0), ("traffic_light", 1.0, -0.4, 0.0),
                          ("bus_shelter", 6.5, 1.1, 0.0), ("litter_bin", -10.5, 1.0, 0.0),
                          ("bench", 10.5, 1.2, 0.0), ("jersey_barrier", -1.5, -0.8, 0.0),
                          ("chevron_board", 4.0, -4.0, 0.0), ("traffic_cone", -4.5, -1.8, 0.0),
                          ("lamp_led_double", 13.5, 1.2, 0.0)]:
        import_prop(pid, (x, y, 0.0), rz, 1.0)
    add_camera((-1.0, -17.0, 5.0), (0.5, 2.0, 4.5), 28)
    bpy.ops.render.render(write_still=True)


def scene_bay():
    reset_scene()
    setup_render(os.path.join(RENDERS, "bay_backdrop.png"))
    water = flat_material("M_Water", (0.01, 0.03, 0.06), 0.05, 0.0)
    add_plane("water", 2000, 2000, (0, 0, -0.2), 0, water)
    quay = tex_material("M_Quay", "concrete_pavers_02", 0.6, (0.3, 0.3, 0.3))
    add_plane("quay", 200, 40, (0, -20, 0), 0, quay)
    add_sun(60, 0, 2.2, (0.75, 0.85, 1.0))
    import_prop("container_stack", (-24.0, -14.0, 0.0), 0.0, 1.0)
    import_prop("gantry_crane", (14.0, -18.0, 0.0), 0.0, 1.0)
    import_prop("skyline_card", (0.0, 210.0, 0.0), 0.0, 1.0)
    add_camera((-10, -75, 22), (2, -5, 12), 30)
    bpy.ops.render.render(write_still=True)


def scene_signs_close():
    reset_scene()
    setup_render(os.path.join(RENDERS, "neon_arrow_and_24h_closeup.png"))
    brick = tex_material("M_Brick", "dark_brick_wall", 0.8, (0.25, 0.25, 0.25))
    add_plane("brick_wall", 20, 10, (0, 0, 1.5), 90, brick)
    add_sun(60, 0, 2.4, (0.75, 0.85, 1.0))
    import_prop("sign_arrow_night_owl_diner", (-1.5, 0.0, 0.0), 0.0, 1.0)
    import_prop("sign_open24h_moto_garage", (1.7, 0.0, 0.0), 0.0, 1.0)
    add_camera((0.1, -6.5, 1.2), (0.1, 0.0, 1.0), 35)
    bpy.ops.render.render(write_still=True)


SCENES = {"contact": scene_contact, "signs": scene_signs, "corner": scene_corner, "bay": scene_bay,
          "signs_close": scene_signs_close}

if __name__ == "__main__":
    bp.define_materials()
    SCENES[argv_scene()]()
    print("[render] done", argv_scene())
