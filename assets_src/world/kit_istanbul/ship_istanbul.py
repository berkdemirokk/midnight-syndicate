#!/usr/bin/env python3
"""Ship the Istanbul kit: py -3.10 assets_src/world/kit_istanbul/ship_istanbul.py
Copies out/ -> game/assets/world/kits/istanbul (GLBs and JSON flat, PNGs under textures/), copies the LOD2
impostor atlases also to kits/buildings/textures/ (MaterialLibrary._impostor reads them there), and registers
every file in ASSET_MANIFEST.json (generated:blender, project-owned). Re-runnable."""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools"))
import asset_factory  # noqa: E402

OUT = os.path.join(HERE, "out")
DST = os.path.join(REPO, "game", "assets", "world", "kits", "istanbul")
BTEX = os.path.join(REPO, "game", "assets", "world", "kits", "buildings", "textures")
MANIFEST = os.path.join(REPO, "ASSET_MANIFEST.json")


def reg(path, kind):
    rel = os.path.relpath(path, REPO).replace("\\", "/")
    ident = "istanbul_kit_" + "".join(c if c.isalnum() else "_" for c in rel[len("game/assets/world/"):]).strip("_")
    argv = ["--root", REPO, "--manifest", MANIFEST, "register", "--id", ident, "--kind", kind, "--path", rel,
            "--source", "generated:blender", "--license", "project-owned",
            "--notes", "World Tour Istanbul kit (assets_src/world/kit_istanbul)"]
    if kind == "model":
        argv += ["--materials", "0"]
    if asset_factory.main(argv) != 0:
        raise SystemExit("register failed: " + rel)


def main():
    os.makedirs(os.path.join(DST, "textures"), exist_ok=True)
    for name in sorted(os.listdir(OUT)):
        full = os.path.join(OUT, name)
        if os.path.isdir(full):
            continue
        shutil.copy2(full, os.path.join(DST, name))
        reg(os.path.join(DST, name), "model" if name.endswith(".glb") else "generated")
    for name in sorted(os.listdir(os.path.join(OUT, "textures"))):
        shutil.copy2(os.path.join(OUT, "textures", name), os.path.join(DST, "textures", name))
        reg(os.path.join(DST, "textures", name), "texture")
        if name.startswith("impostor_"):
            shutil.copy2(os.path.join(OUT, "textures", name), os.path.join(BTEX, name))
            reg(os.path.join(BTEX, name), "texture")


if __name__ == "__main__":
    main()
