"""Rebuilds the licensed cars from their source GLBs (plain Python, it starts Blender for each car).

Run from the repo root:
  py -3.10 assets_src/pipeline/rebuild_vehicles.py [car_id ...]        no ids = every config in vehicle_configs/

For each config it runs prepare_vehicle.py in Blender (LOD0, LOD1, LOD2 and <car_id>_prepare_stats.json) and then
refreshes the car's three records in ASSET_MANIFEST.json (bytes, sha256, tris, material_count). Afterwards run
  godot --headless --audio-driver Dummy --path game --import
  py -3.10 tools/asset_factory.py validate
  py -3.10 tools/asset_factory.py licenses      (THIRD_PARTY_LICENSES.md carries the sha256 of every car file)
and the tests. A car whose LOD1 or LOD2 reaches beyond its LOD0 box fails the run. Config keys this script reads: source_file (default: assets_src/third_party/vinish_cars/<source_title
in lower case with dashes>.glb) and out_dir (default: game/assets/vehicles/<car_id>).
Blender: the BLENDER environment variable, else the default install path of Blender 5.3 on Windows.
"""
import glob
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from asset_factory import Manifest  # noqa: E402  the lock and the atomic write of every manifest writer
BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.3\blender.exe")


def load_config(car_id):
    with open(os.path.join(HERE, "vehicle_configs", car_id + ".json"), encoding="utf-8") as fh:
        return json.load(fh)


def paths(cfg):
    src = cfg.get("source_file") or "assets_src/third_party/vinish_cars/%s.glb" % cfg["source_title"].lower().replace(" ", "-")
    out = cfg.get("out_dir") or "game/assets/vehicles/%s" % cfg["car_id"]
    return src, out


def build(car_id):
    cfg = load_config(car_id)
    src, out = paths(cfg)
    if not os.path.exists(os.path.join(ROOT, src)):
        print("%s: source %s is missing" % (car_id, src))
        return False
    run = subprocess.run([BLENDER, "-b", "--factory-startup", "-P", os.path.join(HERE, "prepare_vehicle.py"), "--", src, car_id, out],
                         cwd=ROOT, capture_output=True, text=True, errors="replace")
    lines = (run.stdout + run.stderr).splitlines()
    summary = " | ".join(ln for ln in lines if ln.startswith("LOD"))
    problems = [ln for ln in lines if "Traceback" in ln or "Error" in ln or "unmapped" in ln or ln.startswith("WARN LOD")]
    print("%s exit %d %s" % (car_id, run.returncode, summary))
    if run.returncode != 0 and lines:
        problems.append(lines[-1])  # the SystemExit message of prepare_vehicle.py
    for ln in problems[:8]:
        print("   " + ln)
    return run.returncode == 0 and not any("Traceback" in ln or "unmapped" in ln for ln in problems)


def refresh_manifest(car_ids):
    done = 0
    with Manifest(os.path.join(ROOT, "ASSET_MANIFEST.json")) as man:
        by_id = {r["id"]: r for r in man.data["records"]}
        for car_id in car_ids:
            cfg = load_config(car_id)
            _src, out = paths(cfg)
            with open(os.path.join(ROOT, out, car_id + "_prepare_stats.json"), encoding="utf-8") as fh:
                stats = json.load(fh)
            for lod in cfg.get("lods", [0, 1, 2]):
                rec = by_id.get("%s_lod%d" % (car_id, lod))
                if rec is None:
                    print("   no manifest record %s_lod%d: register it with tools/asset_factory.py" % (car_id, lod))
                    continue
                with open(os.path.join(ROOT, rec["path"]), "rb") as fh:
                    data = fh.read()
                rec.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), tris=stats["lod%d" % lod]["tris"],
                           material_count=stats["lod%d" % lod]["material_count"])
                done += 1
    print("manifest: %d records refreshed" % done)


def main():
    ids = sys.argv[1:] or sorted(os.path.basename(f)[:-5] for f in glob.glob(os.path.join(HERE, "vehicle_configs", "*.json")))
    ok = [car_id for car_id in ids if build(car_id)]
    refresh_manifest(ok)
    return 0 if len(ok) == len(ids) else 1


if __name__ == "__main__":
    sys.exit(main())
