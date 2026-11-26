"""Kestrel GT-R: single deterministic entry point (stage 2B).

  "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup \
      --python build_car.py > logs\\build.log

Order: body (body.py) -> details (details.py, no renders, no dummy wheels) -> wheels and brakes
(wheels.py) -> textures (textures.py, PNG into out/textures) -> materials with textures wired ->
UVs -> LOD0 check -> out/kestrel_gtr.blend -> LOD1 / LOD2 by per-object decimation with a
triangle budget loop -> GLB export of LOD0, LOD1, LOD2 (+Y up, textures embedded, modifiers
applied, tangents) -> out/build_summary.json (read by validate_car.py).
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
import bmesh  # noqa: E402

import body as B  # noqa: E402
import details as D  # noqa: E402
import wheels as W  # noqa: E402
import textures as T  # noqa: E402

OUT = os.path.join(HERE, "out")
TEX = os.path.join(OUT, "textures")
BUDGET = {0: (45000, 85000), 1: (0, 25800), 2: (0, 6800)}  # LOD target (max for LOD1/LOD2)
REQUIRED = ["body", "glass", "trim", "lights_front", "lights_rear", "interior", "underbody",
            "exhaust", "plate_rear", "wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR",
            "brake_FL", "brake_FR", "brake_RL", "brake_RR", "col_body"]
DISPLAY = [n for n in REQUIRED if n != "col_body"]


# ------------------------------------------------------------------ helpers
def _tri_count_mesh(me):
    return sum(max(len(p.vertices) - 2, 0) for p in me.polygons)


def _principled_tex(mat, path, socket, noncolor, normal_strength=None, loc=(-600, 300)):
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = "Non-Color" if noncolor else "sRGB"
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    t.location = loc
    if normal_strength is not None:
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_strength
        nm.location = (loc[0] + 300, loc[1])
        nt.links.new(t.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    else:
        nt.links.new(t.outputs["Color"], bsdf.inputs[socket])
    return t


def box_uv(ob, tile):
    """Box projection in metres: each face projects along its dominant normal axis."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for lp in f.loops:
            c = lp.vert.co
            if ax == 2:
                u, v = c.x, c.y
            elif ax == 0:
                u, v = c.y, c.z
            else:
                u, v = c.x, c.z
            lp[uv].uv = (u / tile, v / tile)
    bm.to_mesh(ob.data)
    bm.free()


def plate_uv(ob):
    """Plate face: U runs toward -X so KESTREL reads correctly from behind the car, V up = +Z."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for lp in f.loops:
            c = lp.vert.co
            lp[uv].uv = (0.5 - c.x / 0.36, 0.5 + (c.z - D.PLATE_Z) / 0.12)
    bm.to_mesh(ob.data)
    bm.free()


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


def visible_objects(objs):
    return [o for o in objs if o.name != "col_body"]


def eval_tris(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    total = 0
    for ob in visible_objects(objs):
        oe = ob.evaluated_get(dg)
        me = oe.to_mesh()
        total += _tri_count_mesh(me)
        oe.to_mesh_clear()
    return total


def export_glb(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True,
        export_apply=True, export_tangents=True, export_image_format="AUTO",
        export_materials="EXPORT", export_cameras=False, export_lights=False,
        export_extras=True)  # col_body carries extras {"collision_only": 1}: engine skips it
    print("EXPORT", path, os.path.getsize(path))


# ------------------------------------------------------------------ body and details
def build_body_and_details(mats_extra):
    body = B.build_shell()
    B.cut_panel_lines(body)
    B.checks(body)
    underbody = B.cut_arches(body)
    B._cut_dlo_edges(body)  # straight window edges: without this the glass edge is a stair-step
    glass = B.split_glazing(body)
    mats = B.make_materials()
    mats.update(D.extra_materials())
    mats["M_Interior"].node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = \
        B._srgb_to_lin(B._lin((0x2A, 0x2D, 0x32)))
    # rim, brake and carbon materials
    m, b = B._principled("M_Rim", B._lin((0x50, 0x55, 0x5E)), 1.0, 0.28)
    mats["M_Rim"] = m
    m, b = B._principled("M_BrakeDisc", B._lin((0x70, 0x74, 0x7A)), 1.0, 0.45)
    mats["M_BrakeDisc"] = m
    m, b = B._principled("M_Caliper", B._lin((0xE0, 0x5A, 0x10)), 0.0, 0.40)
    mats["M_Caliper"] = m
    mats["M_Tire"].node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    # no materials.clear() here: it resets face material indices set by split_glazing (greenhouse)
    body.data.materials.append(mats["M_Paint"])   # slot 0
    body.data.materials.append(mats["M_Trim"])    # slot 1: pocket walls, sills
    body.data.materials.append(mats["M_Pillar"])  # slot 2: greenhouse pillars and rails
    body.data.materials.append(mats["M_Carbon"])  # slot 3: roof panel
    D.body_edit(body, D.pre_slice)
    D.pocket(body, D.p_nose_intake, 0.030, "nose intake")
    D.pocket(body, D.p_bonnet_vent, 0.030, "bonnet vent")
    D.pocket(body, D.p_side_intake, 0.055, "fender gill")
    D.lip_bevel(body)
    D.body_edit(body, D.tail_slice)
    D.pocket(body, D.p_tail_low, 0.035, "diffuser recess")
    D.pocket(body, D.p_tail_band, 0.008, "lamp surround")
    D.body_edit(body, D.sill_and_caps)
    B.finish_shading(body, weighted=False)  # custom smoothed normals are set after triangulation (main)
    for ob in (glass, underbody):
        B.finish_shading(ob)
    glass.data.materials.clear()
    glass.data.materials.append(mats["M_Glass"])
    glass.data.materials.append(mats["M_Trim"])
    underbody.data.materials.clear()
    underbody.data.materials.append(mats["M_Trim"])      # floor
    underbody.data.materials.append(mats["M_Interior"])  # arch liners: dark grey plastic
    trim = D.build_trim(mats, body)
    lights_f = D.build_lights_front(mats)
    lights_r, plate = D.build_lights_rear_plate(mats)
    # plate: slot 0 M_Plate carries the NOCTRA texture, slot 1 M_Trim is the recess frame
    exhaust = D.build_exhaust(mats)
    interior = D.build_interior(mats)
    col = D.build_col(body)
    for ob in (trim, lights_f, lights_r, exhaust, interior):
        B.finish_shading(ob)
    wheels, brakes = W.build_all(mats)
    for ob in wheels + brakes:
        B.finish_shading(ob)
    return {"body": body, "glass": glass, "underbody": underbody, "trim": trim,
            "lights_front": lights_f, "lights_rear": lights_r, "interior": interior,
            "exhaust": exhaust, "plate_rear": plate, "col_body": col,
            **{w.name: w for w in wheels}, **{b.name: b for b in brakes}}, mats


# ------------------------------------------------------------------ textures, UVs, wiring
def textures_and_uvs(objs, mats):
    os.makedirs(TEX, exist_ok=True)
    made = T.make_all(TEX)
    p = {k: v[0] for k, v in made.items()}
    box_uv(objs["body"], 0.20)  # flake tile 0.20 m (see textures.paint_flake)
    box_uv(objs["trim"], 0.024)
    box_uv(objs["lights_front"], 0.05)
    plate_uv(objs["plate_rear"])
    # No flake normal map on the paint: the box-projected tangents flip at every projection seam and the
    # clearcoat turned those seams into thin green/orange contour lines in the engine (reviewer, round 2).
    _principled_tex(mats["M_Carbon"], p["carbon_base"], "Base Color", False)
    _principled_tex(mats["M_Carbon"], p["carbon_normal"], None, True, normal_strength=0.6,
                    loc=(-600, -100))
    _principled_tex(mats["M_Tire"], p["tyre_normal"], None, True, normal_strength=1.0)
    _principled_tex(mats["M_Tire"], p["tyre_base"], "Base Color", False, loc=(-600, -300))
    _principled_tex(mats["M_BrakeDisc"], p["brake_roughness"], "Roughness", True)
    _principled_tex(mats["M_BrakeDisc"], p["brake_normal"], None, True, normal_strength=0.6,
                    loc=(-600, -100))
    _principled_tex(mats["M_Plate"], p["plate_base"], "Base Color", False)
    _principled_tex(mats["M_Lens"], p["lens_normal"], None, True, normal_strength=0.3)
    return made


def build_lod0_check(objs):
    tris = {n: _tri_count_mesh(objs[n].data) for n in objs if n != "col_body"}
    total = sum(tris.values())
    print("LOD0 tris", tris, "total", total)
    lo, hi = BUDGET[0]
    if not (lo <= total <= hi):
        print("LOD0 WARNING triangle total %d outside %d-%d" % (total, lo, hi))
    return tris, total


# ------------------------------------------------------------------ LOD
def make_lod(level, lod0):
    """Replace the LOD0 names with *_src, copy the object set under the public names, decimate
    every visible copy by one ratio found with bisection so the total meets the LOD budget."""
    names = list(lod0.keys())
    for n in names:
        lod0[n].name = n + "__src"
    copies = []
    for n in names:
        if level == 2 and (n == "interior" or n.startswith("brake_")):
            continue
        src = lod0[n]
        c = src.copy()
        c.data = src.data.copy()
        c.name = n
        bpy.context.collection.objects.link(c)
        copies.append(c)
    decs = []
    for c in copies:
        if c.name == "col_body":
            continue
        m = c.modifiers.new("LOD_DECIMATE", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        decs.append(m)
    lo_t, hi_t = BUDGET[level]
    a, b = 0.01, 1.0
    best = a
    for _ in range(14):
        mid = 0.5 * (a + b)
        for m in decs:
            m.ratio = mid
        total = eval_tris(copies)
        if total <= hi_t:
            best = mid
            a = mid
        else:
            b = mid
    for m in decs:
        m.ratio = best
    total = eval_tris(copies)
    print("LOD%d ratio %.4f tris %d (budget %d)" % (level, best, total, hi_t))
    return copies, total


def drop_lod(copies, lod0):
    for c in copies:
        me = c.data
        bpy.data.objects.remove(c, do_unlink=True)
        if me is not None and me.users == 0:
            bpy.data.meshes.remove(me)
    for n, ob in lod0.items():
        ob.name = n


def main():
    os.makedirs(OUT, exist_ok=True)
    clear_scene()
    objs, mats = build_body_and_details(None)
    made = textures_and_uvs(objs, mats)
    for ob in objs.values():  # triangles only: glTF tangents need them
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        bm.to_mesh(ob.data)
        bm.free()
    B.smooth_normals(objs["body"])
    B.analytic_normals(objs["body"])
    tris0, total0 = build_lod0_check(objs)
    # the scene floor and rig materials are not part of the car: keep only car materials used
    for n in ("M_Clay",):
        if n in bpy.data.materials:
            bpy.data.materials.remove(bpy.data.materials[n])
    lod0_objs = [objs[n] for n in REQUIRED]
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "kestrel_gtr.blend"))
    glb = {}
    p0 = os.path.join(OUT, "kestrel_gtr_lod0.glb")
    export_glb(p0, lod0_objs)
    glb[0] = p0
    totals = {0: total0}
    tris_by_level = {0: tris0}
    for level in (1, 2):
        copies, tot = make_lod(level, objs)
        totals[level] = tot
        tris_by_level[level] = {c.name: _tri_count_mesh(c.data) for c in copies if c.name != "col_body"}
        path = os.path.join(OUT, "kestrel_gtr_lod%d.glb" % level)
        export_glb(path, copies)
        glb[level] = path
        drop_lod(copies, objs)
    bpy.ops.object.select_all(action="DESELECT")
    summary = {
        "tris": {"lod0": totals[0], "lod1": totals[1], "lod2": totals[2]},
        "tris_by_object": {str(k): v for k, v in tris_by_level.items()},
        "glb": {str(k): v for k, v in glb.items()},
        "glb_bytes": {str(k): os.path.getsize(v) for k, v in glb.items()},
        "textures": {k: [v[1], v[2]] for k, v in made.items()},
        "materials_car": sorted({s.material.name for ob in lod0_objs for s in ob.material_slots if s.material}),
        "blender": bpy.app.version_string,
    }
    with open(os.path.join(OUT, "build_summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    print("BUILD_DONE", json.dumps(summary["tris"]))


if __name__ == "__main__":
    main()
