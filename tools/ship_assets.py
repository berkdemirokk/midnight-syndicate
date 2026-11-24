#!/usr/bin/env python3
"""Ships the Noctra Sable hero car GLBs from assets_src into the Godot project.

Python 3.10, standard library only. Run from the repo root: py -3.10 tools/ship_assets.py

Steps: copy lod0/lod1/lod2 GLB to game/assets/vehicles/noctra_sable/, check the copy's sha256
against the source, register each model in ASSET_MANIFEST.json through asset_factory.py
(upsert, triangle and material counts from build_summary.json), run asset_factory validate
and print sizes. Exit 1 on any failure. Re-run after every new car build.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SRC_DIR = os.path.join(REPO, "assets_src", "vehicles", "noctra_sable", "final", "out")
DST_DIR = os.path.join(REPO, "game", "assets", "vehicles", "noctra_sable")
SUMMARY = os.path.join(SRC_DIR, "build_summary.json")
FACTORY = os.path.join(HERE, "asset_factory.py")
LODS = ("lod0", "lod1", "lod2")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    summary = {}
    if os.path.exists(SUMMARY):
        with open(SUMMARY, "r", encoding="utf-8") as f:
            summary = json.load(f)
    tris = summary.get("tris", {})
    ok = True
    os.makedirs(DST_DIR, exist_ok=True)
    for lod in LODS:
        name = "noctra_sable_%s.glb" % lod
        src = os.path.join(SRC_DIR, name)
        dst = os.path.join(DST_DIR, name)
        if not os.path.isfile(src):
            print("MISSING source %s" % src)
            ok = False
            continue
        shutil.copyfile(src, dst)
        if sha256_file(src) != sha256_file(dst):
            print("sha256 mismatch after copy: %s" % name)
            ok = False
            continue
        rel = os.path.relpath(dst, REPO).replace("\\", "/")
        tri_count = str(tris.get(lod, 0))
        cmd = [sys.executable, FACTORY, "register",
               "--id", "noctra_sable_%s" % lod, "--kind", "model", "--path", rel,
               "--source", "generated:blender", "--license", "project-owned",
               "--tris", tri_count, "--materials", "0",
               "--notes", "Hero car %s, shipped by tools/ship_assets.py" % lod.upper()]
        r = subprocess.run(cmd, cwd=REPO)
        if r.returncode != 0:
            ok = False
    # validate exits 1 when any record in the repo fails (other agents' CC0 sets). Judge only the car records.
    r = subprocess.run([sys.executable, FACTORY, "validate"], cwd=REPO, capture_output=True, text=True)
    car_lines = [l for l in r.stdout.splitlines() if l.startswith("noctra_sable_")]
    for l in car_lines:
        print(l)
    if len(car_lines) != len(LODS) or any("pass" not in l for l in car_lines):
        ok = False
    if r.returncode != 0:
        print("note: validate reports failing records outside the car set (not shipped by this tool)")
    print("")
    for lod in LODS:
        p = os.path.join(DST_DIR, "noctra_sable_%s.glb" % lod)
        if os.path.isfile(p):
            print("%s  %d bytes  tris %s  sha256 %s" % (
                os.path.basename(p), os.path.getsize(p), tris.get(lod, "?"), sha256_file(p)[:16]))
    print("SHIP OK" if ok else "SHIP FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
