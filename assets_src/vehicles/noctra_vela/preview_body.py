"""Noctra Vela: fast body-only preview (shell, arches, glazing, four plain wheels) for silhouette work.

  blender --background --factory-startup --python preview_body.py -- <outdir> [views]
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
    "front34": ((-5.6, -6.0, 1.00), (0.0, 0.0, 0.62), 60),
    "rear34": ((5.6, 6.0, 1.00), (0.0, 0.0, 0.62), 60),
    "side": ((8.2, 0.0, 0.80), (0.0, 0.0, 0.62), 60),
    "top": ((0.0, 0.01, 10.0), (0.0, 0.0, 0.0), 60),
    "front_low": ((-2.0, -6.8, 0.35), (0.0, 0.0, 0.62), 60),
    "cabin": ((3.4, -0.3, 1.2), (0.0, 0.1, 1.0), 70),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    outdir = argv[0] if argv else os.path.join(HERE, "renders_iter", "p0")
    views = argv[1].split(",") if len(argv) > 1 else list(VIEWS)
    os.makedirs(outdir, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    body = B.build_shell()
    B.cut_panel_lines(body)
    B.checks(body)
    under = B.cut_arches(body)
    B._cut_dlo_edges(body)
    glass = B.split_glazing(body)
    for ob in (body, glass, under):
        B.finish_shading(ob)
    mats = B.make_materials()
    pillar, pb = B._principled("M_Pillar", B._lin((0x08, 0x08, 0x0A)), 0.0, 0.12)
    body.data.materials.append(mats["M_Paint"])
    body.data.materials.append(mats["M_Trim"])
    body.data.materials.append(pillar)
    glass.data.materials.append(mats["M_Glass"])
    glass.data.materials.append(mats["M_Trim"])
    under.data.materials.append(mats["M_Trim"])
    under.data.materials.append(mats["M_Interior"])
    for sx in (1, -1):
        for ay, x in ((-1.275, 0.775), (1.275, 0.765)):
            bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.32, depth=0.225,
                                                location=(sx * x, ay, 0.32), rotation=(0, math.pi / 2, 0))
            bpy.context.active_object.data.materials.append(mats["M_Tire"])
    if os.environ.get("TRI"):
        import bmesh
        for ob in (body, glass, under):
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            bmesh.ops.triangulate(bm, faces=list(bm.faces))
            bm.to_mesh(ob.data)
            bm.free()
    sc, cam, tgt = B.setup_scene(mats)
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    for name in views:
        cp, tp, lens = VIEWS[name]
        cam.location, tgt.location, cam.data.lens = Vector(cp), Vector(tp), lens
        bpy.context.view_layer.update()
        sc.render.filepath = os.path.join(outdir, name + ".png")
        bpy.ops.render.render(write_still=True)
    print("PREVIEW_DONE", outdir)


if __name__ == "__main__":
    main()
