"""Studio renders of one built variant (Cycles or EEVEE), same rig idea as the hero car's render_car.py.

  blender --background --factory-startup --python render_atmaca.py -- <variant> <engine> <outdir> [views] [samples]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
VIEWS = {  # name: (camera, target, lens)
    "front34": ((-5.6, -5.9, 1.05), (0.0, 0.0, 0.62), 55),
    "rear34": ((5.6, 5.9, 1.05), (0.0, 0.0, 0.62), 55),
    "side": ((8.2, 0.0, 0.85), (0.0, 0.0, 0.66), 55),
    "front_low": ((-2.0, -6.4, 0.35), (0.0, 0.0, 0.62), 55),
    "wheel": ((2.4, -3.0, 0.7), (0.74, -1.225, 0.33), 80),
}


def area(sc, name, loc, rot, size, energy, col, sy=None):
    l = bpy.data.lights.new(name, "AREA")
    l.energy, l.color, l.shape = energy, col, "RECTANGLE"
    l.size, l.size_y = size, (sy or size)
    o = bpy.data.objects.new(name, l)
    o.location, o.rotation_euler = loc, rot
    sc.collection.objects.link(o)


def setup(sc, floor_mat):
    sc.render.image_settings.file_format = "PNG"
    sc.world = bpy.data.worlds.new("studio")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.012, 0.014, 0.02, 1)
    fl = bpy.data.meshes.new("floor")
    ob = bpy.data.objects.new("floor", fl)
    sc.collection.objects.link(ob)
    fl.from_pydata([(-30, -30, 0), (30, -30, 0), (30, 30, 0), (-30, 30, 0)], [], [(0, 1, 2, 3)])
    fl.materials.append(floor_mat)
    r = math.radians
    area(sc, "key", (-4.2, -4.6, 2.8), (r(66), 0, r(-35)), 12, 90, (1.0, 0.96, 0.9))
    area(sc, "front_fill", (-3.6, -6.0, 1.4), (r(80), 0, r(-30)), 4.0, 260, (0.92, 0.95, 1.0))
    area(sc, "strip", (4.2, 0.0, 1.9), (0, r(90), 0), 0.8, 700, (1, 1, 1), 9.0)
    area(sc, "rim", (3.0, 5.5, 3.0), (r(-60), 0, r(150)), 3.0, 700, (1.0, 0.8, 0.6))
    area(sc, "top", (0, 0, 6.0), (0, 0, 0), 6.0, 60, (1, 1, 1), 10.0)
    area(sc, "rearfill", (0.0, 6.0, 1.3), (r(-90), 0, 0), 4.0, 360, (1.0, 0.95, 0.9))
    area(sc, "sidefill", (7.0, 0.5, 1.5), (0, r(90), 0), 4.0, 300, (0.95, 0.97, 1.0))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    tgt = bpy.data.objects.new("tgt", None)
    sc.collection.objects.link(tgt)
    c = cam.constraints.new("TRACK_TO")
    c.target, c.track_axis, c.up_axis = tgt, "TRACK_NEGATIVE_Z", "UP_Y"
    return cam, tgt


def engine(sc, eng, samples):
    if eng == "cycles":
        sc.render.engine = "CYCLES"
        sc.cycles.samples = samples
        sc.cycles.use_denoising = True
        sc.cycles.device = "GPU"
        prefs = bpy.context.preferences.addons["cycles"].preferences
        got = False
        for t in ("OPTIX", "CUDA", "HIP", "METAL", "ONEAPI"):
            try:
                prefs.compute_device_type = t
                prefs.get_devices()
                g = [d for d in prefs.devices if d.type != "CPU"]
                if g:
                    for d in prefs.devices:
                        d.use = d.type != "CPU"
                    got = True
                    print("GPU", t)
                    break
            except Exception as ex:
                print("probe", t, str(ex)[:100])
        if not got:
            sc.cycles.device = "CPU"
    else:
        sc.render.engine = "BLENDER_EEVEE"
        sc.eevee.taa_render_samples = samples


def main():
    a = sys.argv[sys.argv.index("--") + 1:]
    variant, eng, outdir = a[0], a[1], a[2]
    views = a[3].split(",") if len(a) > 3 and a[3] else ["front34", "rear34", "side"]
    samples = int(a[4]) if len(a) > 4 else (96 if eng == "cycles" else 32)
    os.makedirs(outdir, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, "out", "atmaca_%s.blend" % variant))
    sc = bpy.context.scene
    floor = bpy.data.materials.get("M_Floor")
    cam, tgt = setup(sc, floor)
    engine(sc, eng, samples)
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.render.resolution_percentage = 100
    for o in bpy.data.objects:
        if o.name == "col_body":
            o.hide_render = True
    for v in views:
        cp, tp, lens = VIEWS[v]
        cam.location, tgt.location, cam.data.lens = Vector(cp), Vector(tp), lens
        bpy.context.view_layer.update()
        sc.render.filepath = os.path.join(outdir, "%s_%s.png" % (variant, v))
        bpy.ops.render.render(write_still=True)
        print("RENDERED", sc.render.filepath)


if __name__ == "__main__":
    main()
