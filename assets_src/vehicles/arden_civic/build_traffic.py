"""Arden Civic traffic sedan: body (body.py surface engine) + glass, trim, lights, 4 wheels.
Deterministic. Writes LOD GLBs and report.json, and optionally renders.

  blender --background --factory-startup --python build_traffic.py -- <mode> <outdir>
    mode    build   LOD GLBs into out/ and report.json (no renders)
            eevee   build, then EEVEE preview renders into <outdir> (iteration)
            final   build, then Cycles renders into <outdir> (deliverable)
"""
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np  # noqa: F401  (kept for parity with body.py helpers)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import body as B  # noqa: E402

OUT = os.path.join(HERE, "out")
BUDGET = {0: 7000, 1: 2500, 2: 800}
AXLE_S = {"F": 0.92, "R": 3.67}
TRACK_X = 0.77
WHEEL_R = 0.32
HALF_W = 0.1025  # tyre width 0.205
MAT_ORDER = ["M_Paint", "M_Glass", "M_Trim", "M_LightFront", "M_LightRear", "M_Tire", "M_Rim"]
REAR_Y = 4.60 + B.TAIL_DS - B.Y_OFFSET  # rear fascia plane (blender y)


def Y(s):
    """Station s to blender y."""
    return s - B.Y_OFFSET


def make_mats():
    mats = {}
    m, b = B._principled("M_Paint", B._lin((0x6F, 0x7F, 0x8C)), 0.1, 0.35)  # muted steel blue-grey
    b.inputs["Coat Weight"].default_value = 1.0
    b.inputs["Coat Roughness"].default_value = 0.05
    mats["M_Paint"] = m
    m, b = B._principled("M_Glass", B._lin((0x4A, 0x62, 0x6C)), 0.0, 0.03)
    b.inputs["Alpha"].default_value = 0.35
    m.surface_render_method = "BLENDED"
    mats["M_Glass"] = m
    m, b = B._principled("M_Trim", B._lin((0x0C, 0x0C, 0x0D)), 0.0, 0.5)
    mats["M_Trim"] = m
    m, b = B._principled("M_LightFront", (0.8, 0.85, 0.9), 0.0, 0.2)
    b.inputs["Emission Color"].default_value = (0.85, 0.93, 1.0, 1.0)
    b.inputs["Emission Strength"].default_value = 0.2  # brief: low energy, lamps off by default
    mats["M_LightFront"] = m
    m, b = B._principled("M_LightRear", (0.3, 0.02, 0.02), 0.0, 0.2)
    b.inputs["Emission Color"].default_value = (1.0, 0.05, 0.04, 1.0)
    b.inputs["Emission Strength"].default_value = 1.0
    mats["M_LightRear"] = m
    m, b = B._principled("M_Tire", (0.10, 0.10, 0.11), 0.0, 0.85)
    mats["M_Tire"] = m
    m, b = B._principled("M_Rim", (0.62, 0.64, 0.68), 0.9, 0.3)
    mats["M_Rim"] = m
    mats["M_Floor"] = B._principled("M_Floor", B._lin((0x14, 0x15, 0x1A)), 0.0, 0.3)[0]
    return mats


def _bm_obj(name, bm, mats):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def trim_parts(mats):
    """Lamps, grille, bumpers, plate recess, handles, mirrors, placeholder seats and dash."""
    bt, bf, br, bp = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()
    for sx in (1, -1):
        B._box(bf, (sx * 0.42, Y(0.07), 0.56), 0.44, 0.03, 0.05)  # front lamp unit
        B._box(br, (sx * 0.52, REAR_Y + 0.005, 0.74), 0.44, 0.02, 0.09)  # tail lamp
        B._box(bp, (sx * 0.92, Y(2.00), 0.98), 0.06, 0.10, 0.08)  # mirror (body paint), kept inside 1.90 m overall
        for s in (2.42, 3.22):
            B._box(bt, (sx * 0.905, Y(s), 0.78), 0.02, 0.14, 0.035)  # door handle pad
        B._box(bt, (sx * 0.27, Y(2.10), 0.60), 0.38, 0.50, 0.42)  # front seat (inside shell)
        B._box(bt, (sx * 0.27, Y(3.15), 0.58), 0.38, 0.50, 0.40)  # rear seat
    B._box(bt, (0.0, Y(0.07), 0.50), 0.30, 0.03, 0.06)  # grille band between the lamps
    B._box(bt, (0.0, Y(0.05), 0.26), 1.20, 0.03, 0.05)  # front bumper trim
    B._box(bt, (0.0, REAR_Y + 0.005, 0.26), 1.20, 0.02, 0.05)  # rear bumper trim
    B._box(bt, (0.0, REAR_Y + 0.010, 0.52), 0.40, 0.012, 0.15)  # number plate recess
    B._box(bt, (0.0, Y(1.85), 0.86), 0.70, 0.14, 0.14)  # dash
    return [
        _bm_obj("trim", bt, [mats["M_Trim"]]),
        _bm_obj("lamps_front", bf, [mats["M_LightFront"]]),
        _bm_obj("lamps_rear", br, [mats["M_LightRear"]]),
        _bm_obj("mirrors", bp, [mats["M_Paint"]]),
    ]


def plate_text(mats):
    """ARDEN on the plate, silver, facing aft and reading left to right from behind."""
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.object.text_add(location=(0.0, REAR_Y + 0.016, 0.52),
                            rotation=(math.radians(90), 0.0, math.radians(180)))
    ob = bpy.context.active_object
    ob.name = "plate_text"
    ob.data.body = "ARDEN"
    ob.data.size = 0.07
    ob.data.extrude = 0.002
    ob.data.align_x = "CENTER"
    ob.data.align_y = "CENTER"
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.active_object
    ob.data.materials.clear()
    ob.data.materials.append(mats["M_Rim"])
    return ob


def _spoke(bm, x0, yc, th, rc=0.11, hu=0.075, hv=0.018, hx=0.006):
    """Radial spoke box on the wheel face at x0, angle th in the (y, z) plane."""
    cy, cz = yc + rc * math.cos(th), WHEEL_R + rc * math.sin(th)
    uy, uz = math.cos(th), math.sin(th)
    ty, tz = -uz, uy
    vs = []
    for dx in (-hx, hx):
        for a in (-hu, hu):
            for b in (-hv, hv):
                vs.append(bm.verts.new((x0 + dx, cy + a * uy + b * ty, cz + a * uz + b * tz)))
    return [bm.faces.new([vs[i] for i in q])
            for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3))]


def wheel_obj(name, xc, yc, mats):
    """One revolved tyre (24 segments, M_Tire) with a dished rim on both faces and five outer
    spokes (M_Rim). Axis along x, centre at height WHEEL_R."""
    seg = 24
    prof = ((0.20, -HALF_W), (0.32, -0.07), (0.32, 0.07), (0.20, HALF_W))
    bm = bmesh.new()
    V = []
    for r, xa in prof:
        V.append([bm.verts.new((xc + xa, yc + r * math.cos(2 * math.pi * k / seg),
                                WHEEL_R + r * math.sin(2 * math.pi * k / seg))) for k in range(seg)])
    n = len(prof)
    for i in range(n):
        j = (i + 1) % n
        for k in range(seg):
            k1 = (k + 1) % seg
            bm.faces.new([V[i][k], V[i][k1], V[j][k1], V[j][k]]).material_index = 0
    for ring, (r, xa) in ((V[0], prof[0]), (V[3], prof[3])):
        sg = math.copysign(1.0, xa)
        hub = bm.verts.new((xc + xa - sg * 0.02, yc, WHEEL_R))  # dish: hub 20 mm inboard
        for k in range(seg):
            bm.faces.new([hub, ring[k], ring[(k + 1) % seg]]).material_index = 1
    sgo = math.copysign(1.0, xc)  # outward face
    for q in range(5):
        th = 2 * math.pi * q / 5 + math.pi / 5
        for f in _spoke(bm, xc + sgo * (HALF_W - 0.014), yc, th):
            f.material_index = 1
    return _bm_obj(name, bm, [mats["M_Tire"], mats["M_Rim"]])


def wheels(mats):
    out = []
    for sx in (1, -1):
        for tag in ("F", "R"):
            out.append(wheel_obj("wheel_%s%s" % ("L" if sx > 0 else "R", tag),
                                 sx * TRACK_X, Y(AXLE_S[tag]), mats))
    return out


def build_body(mats):
    body = B.build_shell()
    B.cut_panel_lines(body)
    rows = B.checks(body)  # dimension guard, raises if off by more than 3 percent
    under = B.cut_arches(body)
    B._cut_dlo_edges(body)
    glass = B.split_glazing(body)
    body.data.materials.clear()
    body.data.materials.append(mats["M_Paint"])
    body.data.materials.append(mats["M_Trim"])
    glass.data.materials.clear()
    glass.data.materials.append(mats["M_Glass"])
    under.data.materials.clear()
    under.data.materials.append(mats["M_Trim"])
    return [body, glass, under], rows


def smooth_apply(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    for m in list(ob.modifiers):  # bake the smoothing modifier so GLB export keeps it
        bpy.ops.object.modifier_apply(modifier=m.name)


def join_all(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    ob.data.name = name
    return ob


def order_mats(ob):
    me = ob.data
    remap = [MAT_ORDER.index(m.name) for m in me.materials]
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)  # weld body/underbody/glass seams
    bm.to_mesh(me)
    bm.free()
    me.update()
    idx = [remap[p.material_index] for p in me.polygons]
    # Blender 5.3: materials.clear() resets every face's material_index to 0 (verified), which
    # collapsed the whole car onto M_Paint. Re-slot in place instead, then set the indices.
    while len(me.materials) < len(MAT_ORDER):
        me.materials.append(None)
    for i, n in enumerate(MAT_ORDER):
        me.materials[i] = bpy.data.materials[n]
    for p, k in zip(me.polygons, idx):
        p.material_index = k


def tri_count(ob):
    me = ob.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def decimated_copy(src, name, target):
    """Collapse-decimate a copy of src until its triangle count is within [0.85, 1.0] of target."""
    ratio = min(1.0, target / tri_count(src))
    last = None
    for _ in range(8):
        me = src.data.copy()
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        bpy.context.view_layer.objects.active = ob
        mod = ob.modifiers.new("decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
        n = tri_count(ob)
        print("DECIMATE %s ratio %.4f tris %d target %d" % (name, ratio, n, target))
        if target * 0.85 <= n <= target:
            if last is not None:
                bpy.data.objects.remove(last, do_unlink=True)
            return ob
        if last is not None:
            bpy.data.objects.remove(last, do_unlink=True)
        last = ob
        ratio = min(1.0, ratio * target / n * 0.99)
    print("DECIMATE %s: budget window not hit, kept %d tris" % (name, tri_count(last)))
    return last


def transfer_normals(dst, src):
    """Copy the full-resolution shading normals onto a decimated LOD: collapse decimation leaves
    streaks and wrinkles on the smooth body otherwise."""
    bpy.context.view_layer.objects.active = dst
    for p in dst.data.polygons:
        p.use_smooth = True
    mod = dst.modifiers.new("normals", "DATA_TRANSFER")
    mod.object = src
    mod.use_loop_data = True
    mod.data_types_loops = {"CUSTOM_NORMAL"}
    mod.loop_mapping = "POLYINTERP_NEAREST"
    try:
        bpy.ops.object.modifier_apply(modifier=mod.name)
    except RuntimeError as e:
        print("NORMAL TRANSFER failed:", e)
        dst.modifiers.remove(mod)


def make_lod(src, lvl):
    name = "arden_civic_lod%d" % lvl
    if tri_count(src) <= BUDGET[lvl]:
        ob = bpy.data.objects.new(name, src.data.copy())
        bpy.context.collection.objects.link(ob)
        return ob, False
    ob = decimated_copy(src, name, BUDGET[lvl])
    transfer_normals(ob, src)
    return ob, True


def export_glb(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=False)


def set_cycles(sc, samples):
    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.device = "CPU"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for dev_type in ("OPTIX", "CUDA", "HIP", "METAL", "ONEAPI"):
            try:
                prefs.compute_device_type = dev_type
                prefs.get_devices()
                gpus = [d for d in prefs.devices if d.type != "CPU"]
                if gpus:
                    for d in prefs.devices:
                        d.use = d.type != "CPU"
                    sc.cycles.device = "GPU"
                    print("GPU device", dev_type, [d.name for d in gpus])
                    break
            except Exception as ex:  # reported, falls back to CPU
                print("GPU probe", dev_type, str(ex)[:160])
    except Exception as ex:
        print("cycles prefs", str(ex)[:160])
    print("Cycles device", sc.cycles.device)


def render(mode, outdir, mats):
    sc, cam, tgt = B.setup_scene({"M_Floor": mats["M_Floor"]})
    os.makedirs(outdir, exist_ok=True)
    B.RENDER_DIR = outdir
    if mode == "final":
        set_cycles(sc, 96)
        views = ["front34", "rear34", "side", "top"]
    else:
        views = ["front34", "rear34", "side", "top"]
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.render.resolution_percentage = 100
    paths = B.render_views(sc, cam, {k: B.VIEWS[k] for k in views})
    B.contact_sheet([paths[k] for k in views], os.path.join(outdir, "contact_sheet.png"))
    return paths


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    mode = argv[0] if argv else "build"
    outdir = argv[1] if len(argv) > 1 else os.path.join(HERE, "renders")
    os.makedirs(OUT, exist_ok=True)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    mats = make_mats()
    body_parts, rows = build_body(mats)
    parts = body_parts + trim_parts(mats) + [plate_text(mats)] + wheels(mats)
    for ob in parts:
        if ob.type == "MESH" and ob.name not in ("plate_text",):
            smooth_apply(ob)
    full = join_all(parts, "arden_full")
    order_mats(full)
    print("FULL tris", tri_count(full))

    lods = {}
    report_lods = {}
    for lvl in (0, 1, 2):
        ob, dec = make_lod(full, lvl)
        n = tri_count(ob)
        used = sorted({ob.data.materials[p.material_index].name for p in ob.data.polygons})
        lods[lvl] = ob
        report_lods[lvl] = {"tris": n, "budget": BUDGET[lvl], "within_budget": n <= BUDGET[lvl],
                            "decimated": dec, "verts": len(ob.data.vertices), "materials": used}
        print("LOD%d tris %d budget %d decimated %s" % (lvl, n, BUDGET[lvl], dec))

    d = lods[0].dimensions
    bpy.data.objects.remove(full, do_unlink=True)
    for lvl in (0, 1, 2):
        path = os.path.join(OUT, "arden_civic_lod%d.glb" % lvl)
        export_glb(lods[lvl], path)
        print("GLB", path)
    for lvl in (1, 2):
        bpy.data.objects.remove(lods[lvl], do_unlink=True)

    report = {
        "name": "arden_civic",
        "units": "metres, blender Z up (glTF Y up in the GLBs)",
        "dims_lod0": {"width_x": round(d.x, 3), "length_y": round(d.y, 3), "height_z": round(d.z, 3),
                      "brief": {"width_x": 1.80, "length_y": 4.60, "height_z": 1.45}},
        "lods": report_lods,
        "materials": MAT_ORDER,
        "checks": [{"name": r[0], "value": r[1], "target": r[2], "err_pct": r[3], "ok": r[4]} for r in rows],
        "checks_dims_lod0_ok": bool(abs(d.x - 1.80) / 1.80 <= 0.03 and abs(d.y - 4.60) / 4.60 <= 0.03
                                    and abs(d.z - 1.45) / 1.45 <= 0.03),
    }
    with open(os.path.join(HERE, "report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
    print("REPORT", json.dumps(report["dims_lod0"]), json.dumps({k: v["tris"] for k, v in report_lods.items()}))

    if mode in ("eevee", "final"):
        paths = render(mode, outdir, mats)
        print("RENDERS", paths)
    print("BUILD_DONE", mode)


if __name__ == "__main__":
    main()
