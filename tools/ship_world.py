#!/usr/bin/env python3
"""Ship the city_01 world data into game/assets/world (py -3.10 tools/ship_world.py).

Copies the road GLB, the building and prop kits, generated textures, catalogs, material tables,
the centreline and the layout JSON from assets_src/world/ into game/assets/world/. Every shipped
file is registered in ASSET_MANIFEST.json through tools/asset_factory.py (source generated:blender,
licence project-owned). Re-runnable: files are overwritten and records are upserted.

Import options: none set. Godot's default GLB import already turns "-col" and "-colonly" node
suffixes into collision, and no .import file is written by this script.
"""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import asset_factory  # noqa: E402  (tools/asset_factory.py, the single manifest writer)

SRC = os.path.join(REPO, "assets_src", "world")
DST = os.path.join(REPO, "game", "assets", "world")

CITY_FILES = [
    (os.path.join(SRC, "city_01", "road_out", "city_01_road.glb"), "city_01"),
    (os.path.join(SRC, "city_01", "road_out", "city_01_centerline.json"), "city_01"),
    (os.path.join(SRC, "city_01", "road_out", "materials.json"), "city_01/road"),
    (os.path.join(SRC, "city_01", "road_out", "report.json"), "city_01/road"),
    (os.path.join(SRC, "city_01", "layout_out", "city_01_layout.json"), "city_01"),
]


def _kit_files(kit_out, dst_rel):
    """(src, dst_dir) pairs for one kit output folder; PNGs go under textures/."""
    pairs = []
    for name in sorted(os.listdir(kit_out)):
        full = os.path.join(kit_out, name)
        if os.path.isdir(full) or name == "build_log.txt":
            continue
        is_png = name.lower().endswith(".png")
        pairs.append((full, dst_rel + "/textures" if is_png else dst_rel))
    tex_dir = os.path.join(kit_out, "textures")
    if os.path.isdir(tex_dir):
        for name in sorted(os.listdir(tex_dir)):
            pairs.append((os.path.join(tex_dir, name), dst_rel + "/textures"))
    return pairs


def _kind(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".glb":
        return "model"
    if ext == ".png":
        return "texture"
    return "generated"


def _id_for(rel):
    stem = os.path.splitext(rel)[0].replace("\\", "/")
    return "world_" + "".join(c if c.isalnum() else "_" for c in stem).strip("_")


def _copy_and_register(pairs, manifest):
    count = 0
    for src, dst_rel in pairs:
        if not os.path.isfile(src):
            raise SystemExit("missing source: " + src)
        name = os.path.basename(src)
        dst_dir = os.path.join(DST, dst_rel)
        os.makedirs(dst_dir, exist_ok=True)
        dst = os.path.join(dst_dir, name)
        shutil.copy2(src, dst)
        rel_repo = os.path.relpath(dst, REPO).replace("\\", "/")
        kind = _kind(name)
        argv = ["--manifest", manifest, "register", "--id", _id_for(rel_repo[len("game/assets/"):]),
                "--kind", kind, "--path", rel_repo, "--source", "generated:blender",
                "--license", "project-owned", "--notes", "world kit and tracks, shipped by tools/ship_world.py"]
        if kind == "model":
            argv += ["--materials", "0"]
        rc = asset_factory.main(["--root", REPO] + argv)
        if rc not in (0, None):
            raise SystemExit("register refused for %s (rc=%s)" % (rel_repo, rc))
        count += 1
    return count


def track_files(track_id):
    """Road, centreline, layout and the per-track props of a generic track (assets_src/world/tracks/<id>)."""
    base = os.path.join(SRC, "tracks", track_id)
    pairs = [(os.path.join(base, "road_out", track_id + "_road.glb"), track_id),
             (os.path.join(base, "road_out", track_id + "_centerline.json"), track_id),
             (os.path.join(base, "road_out", "materials.json"), track_id + "/road"),
             (os.path.join(base, "road_out", "report.json"), track_id + "/road"),
             (os.path.join(base, "layout_out", track_id + "_layout.json"), track_id)]
    props = os.path.join(base, "props_out")
    if os.path.isdir(props):  # new props join the shared prop kit folder: the builder resolves props by file name
        for name in sorted(os.listdir(props)):
            if name.endswith(".glb"):
                pairs.append((os.path.join(props, name), "kits/props"))
            elif name == "catalog.json":
                pairs.append((os.path.join(props, name), track_id))
    return pairs


def main() -> int:
    manifest = os.path.join(REPO, "ASSET_MANIFEST.json")
    if len(sys.argv) > 2 and sys.argv[1] == "--track":
        n = _copy_and_register(track_files(sys.argv[2]), manifest)
        print("ship_world: track %s, %d files copied and registered" % (sys.argv[2], n))
        return 0
    pairs = [(src, dst_rel) for src, dst_rel in CITY_FILES]
    pairs += _kit_files(os.path.join(SRC, "kit_buildings", "out"), "kits/buildings")
    pairs += _kit_files(os.path.join(SRC, "kit_props", "out"), "kits/props")
    n =_copy_and_register(pairs, manifest)
    print("ship_world: %d files copied and registered under %s" % (n, os.path.relpath(DST, REPO)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
