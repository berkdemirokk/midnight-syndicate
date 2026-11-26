"""Dev: body shell + glazing only, quick EEVEE views. blender -b --factory-startup --python dev_body.py -- outdir views"""
import os
import sys
import math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
import body as B  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
outdir = os.path.join(HERE, argv[0])
os.makedirs(outdir, exist_ok=True)
views = argv[1].split(",") if len(argv) > 1 else ["front34", "side", "rear34", "top"]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
body = B.build_shell()
B.cut_panel_lines(body)
B.checks(body)
under = B.cut_arches(body)
B._cut_dlo_edges(body)
glass = B.split_glazing(body)
mats = B.make_materials()
for ob in (body, glass, under):
    B.finish_shading(ob)
pil = B._principled("M_Pillar", B._lin((8, 8, 10)), 0, .12)[0]
trim = mats["M_Trim"]
for m in (mats["M_Paint"], trim, pil, mats["M_Paint"]):
    body.data.materials.append(m)
glass.data.materials.clear()
glass.data.materials.append(mats["M_Glass"])
glass.data.materials.append(trim)
under.data.materials.clear()
under.data.materials.append(trim)
under.data.materials.append(mats["M_Interior"])
for sx in (1, -1):
    for ay, r, w, xw in ((-1.425, .345, .275, .795), (1.425, .358, .315, .79)):
        bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=r, depth=w, location=(sx * xw, ay, r),
                                            rotation=(0, math.pi / 2, 0))
        bpy.context.active_object.data.materials.append(mats["M_Tire"])
sc, cam, tgt = B.setup_scene(mats)
V = {"front34": ((-6.4, -6.9, 1.0), (0, 0, .6), 60), "rear34": ((6.4, 6.9, 1.0), (0, 0, .6), 60),
     "side": ((9.5, 0, .85), (0, 0, .6), 60), "top": ((0, .01, 11), (0, 0, 0), 60),
     "front": ((-1.5, -8, .8), (0, 0, .6), 60), "rear": ((1.5, 8, .9), (0, 0, .7), 60),
     "cabin": ((-4.5, -3.5, 2.0), (0, .3, .9), 70), "frontside": ((6, -5, 0.9), (0, -1, .6), 60)}
for n in views:
    cp, tp, lens = V[n]
    cam.location = Vector(cp)
    tgt.location = Vector(tp)
    cam.data.lens = lens
    bpy.context.view_layer.update()
    sc.render.filepath = os.path.join(outdir, n + ".png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", n)
