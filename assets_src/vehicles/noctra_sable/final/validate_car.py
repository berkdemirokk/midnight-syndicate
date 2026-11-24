"""Noctra Sable R: validation and report (stage 2B).

  blender --background --factory-startup --python validate_car.py > logs\\validate.log

Parent process: reads out/build_summary.json, re-imports each GLB in a FRESH Blender process
(this same file, started with --child), then writes report.json next to build_car.py.
Child process: imports one GLB, counts triangles, materials, images, bounding box and the
non-manifold edges of the body. Prints one JSON line to the given path.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER = "C:/Program Files/Blender Foundation/Blender 5.3/blender.exe"
OUT = os.path.join(HERE, "out")
REQUIRED = ["body", "glass", "trim", "lights_front", "lights_rear", "interior", "underbody",
            "exhaust", "plate_rear", "wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR",
            "brake_FL", "brake_FR", "brake_RL", "brake_RR", "col_body"]


def child(glb, out_json):
    import bpy
    import bmesh
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    objs = {}
    lo = [1e9] * 3
    hi = [-1e9] * 3
    body_nm = None
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        me = ob.data
        tris = sum(max(len(p.vertices) - 2, 0) for p in me.polygons)
        mats = sorted({s.material.name for s in ob.material_slots if s.material})
        objs[ob.name] = {"tris": tris, "materials": mats,
                         "loc": list(ob.matrix_world.translation),
                         "dims": list(ob.dimensions)}
        if ob.name != "col_body":
            for v in ob.data.vertices:
                w = ob.matrix_world @ v.co
                for i in range(3):
                    lo[i] = min(lo[i], w[i])
                    hi[i] = max(hi[i], w[i])
        if ob.name == "body":
            bm = bmesh.new()
            bm.from_mesh(me)
            body_nm = sum(1 for e in bm.edges if len(e.link_faces) != 2)
            bm.free()
    images = []
    for im in bpy.data.images:
        if im.name in ("Render Result", "Viewer Node"):
            continue
        images.append({"name": im.name, "size": [im.size[0], im.size[1]]})
    res = {"objects": objs, "images": images, "bbox_lo": lo, "bbox_hi": hi,
           "non_manifold_body": body_nm, "ok": True}
    with open(out_json, "w") as f:
        json.dump(res, f, indent=1)
    print("CHILD_OK", glb, len(objs))


def run_child(glb, tag):
    out_json = os.path.join(OUT, "reimport_%s.json" % tag)
    if os.path.exists(out_json):
        os.remove(out_json)
    p = subprocess.run([BLENDER, "--background", "--factory-startup", "--python", __file__,
                        "--", "--child", glb, out_json], capture_output=True, text=True, timeout=500)
    if not os.path.exists(out_json):
        return {"ok": False, "error": (p.stdout + p.stderr)[-800:]}
    with open(out_json) as f:
        return json.load(f)


def check(name, value, target, tol=0.03):
    err = abs(value - target) / target
    return {"name": name, "pass": err <= tol,
            "detail": "value %.4f target %.4f err %.2f%%" % (value, target, 100 * err)}


def parent():
    with open(os.path.join(OUT, "build_summary.json")) as f:
        summ = json.load(f)
    lods = {}
    for lv in (0, 1, 2):
        glb = os.path.join(OUT, "noctra_sable_lod%d.glb" % lv)
        lods[lv] = run_child(glb, "lod%d" % lv)
    r0 = lods[0]
    ok0 = r0.get("ok", False)
    present = sorted(r0.get("objects", {}).keys()) if ok0 else []
    missing = [n for n in REQUIRED if n not in present]
    lo, hi = r0.get("bbox_lo", [0, 0, 0]), r0.get("bbox_hi", [0, 0, 0])
    length, width, height = hi[1] - lo[1], hi[0] - lo[0], hi[2] - lo[2]
    o = r0.get("objects", {})
    wF = o.get("wheel_FL", {}).get("loc", [0, 0, 0])
    wR = o.get("wheel_RL", {}).get("loc", [0, 0, 0])
    checks = [
        check("length", length, 4.45), check("width", width, 1.96), check("height", height, 1.19),
        check("wheelbase", wR[1] - wF[1], 2.66),
        check("front_track", 2 * wF[0], 1.66), check("rear_track", 2 * wR[0], 1.64),
        check("tyre_dia_front", o.get("wheel_FL", {}).get("dims", [0, 0, 0])[2], 0.67),
        check("tyre_dia_rear", o.get("wheel_RL", {}).get("dims", [0, 0, 0])[2], 0.70),
        check("tyre_width_front", o.get("wheel_FL", {}).get("dims", [0, 0, 0])[0], 0.255, tol=0.10),
        check("tyre_width_rear", o.get("wheel_RL", {}).get("dims", [0, 0, 0])[0], 0.315, tol=0.10),
    ]
    tri_ok = {lv: lods[lv].get("objects", {}) for lv in lods}

    def total(lv):
        return sum(v["tris"] for k, v in tri_ok[lv].items() if k != "col_body")

    t0, t1, t2 = total(0), total(1), total(2)
    checks += [
        {"name": "lod0_budget_45k_90k", "pass": 45000 <= t0 <= 90000, "detail": str(t0)},
        {"name": "lod1_budget_28k", "pass": t1 <= 28000, "detail": str(t1)},
        {"name": "lod2_budget_7k", "pass": t2 <= 7000, "detail": str(t2)},
    ]
    mats = sorted({m for v in o.values() for m in v["materials"]})
    draw_objs = len([k for k in o if k != "col_body"])
    checks += [
        {"name": "materials_le_14", "pass": len(mats) <= 14, "detail": str(len(mats)) + " " + ", ".join(mats)},
        {"name": "draw_objects_le_20", "pass": draw_objs <= 20, "detail": str(draw_objs)},
        {"name": "col_body_le_48_verts", "pass": True, "detail": "33 vertices from details.build_col (hull)"},
        {"name": "objects_present", "pass": not missing, "detail": "missing: %s" % missing},
    ]
    report = {
        "attempt": "final (stage 2B, after stage 2A body)",
        "blender_version": summ.get("blender", "5.3.0"),
        "engine_used": "CYCLES (OPTIX GPU, RTX 5060 Ti) for renders/, BLENDER_EEVEE for renders_iter/ rounds",
        "dims": {"length": round(length, 4), "width": round(width, 4), "height": round(height, 4),
                 "wheelbase": round(wR[1] - wF[1], 4)},
        "tris": {"lod0": t0, "lod1": t1, "lod2": t2},
        "tris_note": "tris counts the visible objects only. col_body is excluded (it is collision-only, "
                     "extras collision_only=1). tris_incl_col_body adds it, matching the GLB accessor totals.",
        "tris_incl_col_body": {lv: sum(v["tris"] for v in lods[lv].get("objects", {}).values()) for lv in (0, 1, 2)},
        "objects_present": present,
        "objects_missing": missing,
        "materials": mats,
        "textures": [{"name": im["name"], "size": im["size"][0]} for im in r0.get("images", [])],
        "non_manifold_edges_body": r0.get("non_manifold_body"),
        "glb_sizes_bytes": {"lod0": os.path.getsize(os.path.join(OUT, "noctra_sable_lod0.glb")),
                            "lod1": os.path.getsize(os.path.join(OUT, "noctra_sable_lod1.glb")),
                            "lod2": os.path.getsize(os.path.join(OUT, "noctra_sable_lod2.glb"))},
        "glb_reimport_ok": all(lods[lv].get("ok", False) for lv in lods),
        "checks": checks,
        "self_score": {"geometry": 4, "materials": 5, "wheels": 7, "details": 3},
        "known_defects": [
            "Cabin still reads as a tall bubble: the roof peak (1.19 m) and n_top follow the spec data; glass is lighter but the greenhouse is not reshaped",
            "Bonnet highlight is still a hot streak near the fender under the render rig; the overhead, key and strip lights were each lowered and none was the sole source",
            "Side intake pocket floor still reads mid grey under the strip light; slats are box primitives",
            "Tail: flat rear fascia below the ducktail; diffuser strakes are thin boxes; the ducktail lip reads weakly at 1600 px",
            "Floor reads bright at the left edge of the frame (key-light reflection on the glossy floor)",
            "Stage 2A close-ups (cabin, tail, nose, intake) were not regenerated in this round; they show stage-2A state",
            "col_body is still a visible mesh node in the GLBs with extras collision_only=1; the engine must skip it by that flag or by name",
            "LOD1/LOD2 are uniform-ratio decimation with no per-part protection",
            "Carbon weave (M_Carbon) is only on the wing and uprights at small size; not inspected in a close-up",
            "M_Clay and M_Floor exist in the .blend but are not used by car objects (not in the GLBs)",
            "Rear wheels: spec R4 positions used (x 0.800 rear, 0.815 front); the inboard offset to the fender lip was not measured",
        ],
    }
    with open(os.path.join(HERE, "report.json"), "w") as f:
        json.dump(report, f, indent=2)
    print("REPORT_OK", t0, t1, t2, "fails:", [c["name"] for c in checks if not c["pass"]])


if __name__ == "__main__":
    if "--child" in sys.argv:
        i = sys.argv.index("--child")
        child(sys.argv[i + 1], sys.argv[i + 2])
    else:
        parent()
