"""Kestrel GT-R: render rig for out/kestrel_gtr.blend (stage 2B).

  blender --background --factory-startup --python render_car.py -- <engine> <outdir> [views] [samples]
    engine   eevee | cycles
    outdir   folder for the PNGs, e.g. renders_iter\\r1 or renders
    views    optional comma list; default all seven views
    samples  optional sample count (EEVEE 48 default, Cycles 96)

Rig: body.py setup_scene (dark studio, glossy floor, key / strip / rim / top / rear fill lights),
1600 x 900, 60 mm camera except the close-ups. Writes a contact sheet when all six base views
are rendered: front34, rear34, side, top, wheel_closeup, front_low.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import body as B  # noqa: E402

VIEWS = {  # name: (camera, target, lens)
    "front34": ((-6.4, -6.9, 1.00), (0.0, 0.0, 0.58), 60),
    "rear34": ((6.4, 6.9, 1.00), (0.0, 0.0, 0.58), 60),
    "side": ((9.4, 0.0, 0.85), (0.0, 0.0, 0.58), 60),
    "top": ((0.0, 0.01, 11.5), (0.0, 0.0, 0.0), 60),
    "front_low": ((-2.3, -7.6, 0.35), (0.0, 0.0, 0.58), 60),
    "rear_low": ((2.3, 7.6, 0.35), (0.0, 0.0, 0.58), 60),
    "cabin_side": ((3.4, 0.5, 1.05), (0.0, 0.5, 0.95), 85),
    "tail_closeup": ((1.9, 5.0, 0.95), (0.0, 2.3, 0.65), 85),
    "nose_closeup": ((-1.5, -4.7, 0.8), (0.0, -2.2, 0.4), 85),
    "arch_front_side": ((3.0, -1.375, 0.55), (0.0, -1.375, 0.45), 70),
    "arch_rear_34": ((2.6, 3.4, 0.9), (0.8, 1.375, 0.4), 70),
    "wheel_closeup": ((2.7, -3.3, 0.85), (0.82, -1.375, 0.36), 85),
}
SHEET = ["front34", "rear34", "side", "top", "wheel_closeup", "front_low"]


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    engine = argv[0] if len(argv) > 0 else "eevee"
    outdir = argv[1] if len(argv) > 1 else os.path.join(HERE, "renders_iter", "r0")
    views = argv[2].split(",") if len(argv) > 2 and argv[2] else list(VIEWS)
    samples = int(argv[3]) if len(argv) > 3 else (96 if engine == "cycles" else 48)
    return engine, outdir, views, samples


def set_engine(sc, engine, samples):
    if engine == "cycles":
        sc.render.engine = "CYCLES"
        sc.cycles.samples = samples
        sc.cycles.use_denoising = True
        sc.cycles.device = "GPU"
        prefs = bpy.context.preferences.addons["cycles"].preferences
        got = False
        for dev_type in ("OPTIX", "CUDA", "HIP", "METAL", "ONEAPI"):
            try:
                prefs.compute_device_type = dev_type
                prefs.get_devices()
                gpus = [d for d in prefs.devices if d.type != "CPU"]
                if gpus:
                    for d in prefs.devices:
                        d.use = d.type != "CPU"
                    got = True
                    print("GPU device", dev_type, [d.name for d in gpus])
                    break
            except Exception as ex:  # reported, falls back to CPU
                print("GPU probe", dev_type, str(ex)[:160])
        if not got:
            sc.cycles.device = "CPU"
            print("GPU not available, Cycles on CPU")
    else:
        sc.render.engine = "BLENDER_EEVEE"
        sc.eevee.taa_render_samples = samples
        for attr in ("use_raytracing",):
            if hasattr(sc.eevee, attr):
                setattr(sc.eevee, attr, True)


def main():
    engine, outdir, views, samples = parse_args()
    # A relative outdir means relative to this folder (Blender resolved it against the drive root).
    if not os.path.isabs(outdir):
        outdir = os.path.join(HERE, outdir)
    os.makedirs(outdir, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, "out", "kestrel_gtr.blend"))
    floor_mat = B._principled("M_Floor", B._lin((0x14, 0x15, 0x1A)), 0.0, 0.3)[0]
    mats = {"M_Floor": floor_mat}
    sc, cam, tgt = B.setup_scene(mats)
    set_engine(sc, engine, samples)
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.render.resolution_percentage = 100
    done = {}
    for name in views:
        cp, tp, lens = VIEWS[name]
        cam.location = Vector(cp)
        tgt.location = Vector(tp)
        cam.data.lens = lens
        bpy.context.view_layer.update()
        path = os.path.join(outdir, name + ".png")
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        done[name] = path
        print("RENDERED", engine, name, path)
    if all(n in done for n in SHEET):
        B.contact_sheet([done[n] for n in SHEET], os.path.join(outdir, "contact_sheet.png"))
    print("RENDER_DONE", engine, outdir)


if __name__ == "__main__":
    main()
