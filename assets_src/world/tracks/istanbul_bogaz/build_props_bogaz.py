"""Istanbul Bogaz per-track props: original Turkish neon signs (invented names, ASCII text because Blender's
built-in font has no dotless i / s-cedilla). Same kit generator and materials as the Maslak props.

Run: "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup --python build_props_bogaz.py
Writes props_out/prop_<id>.glb (+ _lod1) and props_out/catalog.json (kit item format).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.join(HERE, "..", "..", "kit_props")
sys.path.insert(0, KIT)
import build_props as bp  # noqa: E402

OUT = os.path.join(HERE, "props_out")
os.makedirs(OUT, exist_ok=True)
bp.OUT = OUT
bp.TEXD = os.path.join(OUT, "textures")

CY, MG, AM, RD, WH = "M_Neon_Cyan", "M_Neon_Magenta", "M_Neon_Amber", "M_Neon_Red", "M_Neon_White"

SIGNS = [
    ("sign_box_iskele_kahvesi_8m", "box8", [("ISKELE KAHVESI", AM)]),
    ("sign_box_kayik_balik_8m", "box8", [("KAYIK BALIK", CY)]),
    ("sign_box_kandil_lokanta_8m", "box8", [("KANDIL LOKANTA", RD)]),
    ("sign_box_mavi_deniz_4m", "box4", [("MAVI DENIZ", CY)]),
    ("sign_box_nar_evi_4m", "box4", [("NAR EVI", MG)]),
    ("sign_blade_nar_meyhane", "blade", [("NAR", MG), ("MEYHANE", AM)]),
    ("sign_blade_deniz_kafe", "blade", [("DENIZ", CY), ("KAFE", AM)]),
]


def main():
    bp.define_materials()
    items = []
    for sid, kind, lines in SIGNS:
        if kind == "blade":
            spec = bp.blade_sign(sid, lines)
        elif kind == "box4":
            spec = bp.box_sign(sid, lines, 4.0)
        else:
            spec = bp.box_sign(sid, lines, 8.0)
        r = bp.build_prop(sid, spec)
        print("[bogaz]", sid, r["tris"], r["lod1_tris"])
        items.append({"id": r["id"], "category": r["category"], "file": r["file"], "size": r["size"],
                      "tris": r["tris"], "lod1_tris": r["lod1_tris"], "lod1_file": r["lod1_file"],
                      "collider_tris": r["collider_tris"], "materials": r["materials"], "lights": r["lights"],
                      "emissive": r["emissive"], "mount": r["mount"], "notes": r["notes"]})
    with open(os.path.join(OUT, "catalog.json"), "w", encoding="utf-8") as f:
        json.dump({"coords": "godot_y_up", "source": "assets_src/world/tracks/istanbul_bogaz/build_props_bogaz.py",
                   "items": items}, f, indent=2)
    print("[bogaz] done", len(items))


main()
