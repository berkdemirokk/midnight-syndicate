"""Istanbul Maslak per-track props: original Turkish neon signs (invented shop names, ASCII text because Blender's
built-in font has no dotless i / s-cedilla) and an original plaza fountain-sculpture.

Run: "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" --background --factory-startup --python build_props_ist.py
Reuses the kit generator (assets_src/world/kit_props/build_props.py) as a module: same neon text, same GLB export,
same materials (only existing kit material names, so MaterialLibrary binds every surface).
Writes props_out/prop_<id>.glb (+ _lod1) and props_out/catalog.json (same item format as the kit catalog).
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.join(HERE, "..", "..", "kit_props")
sys.path.insert(0, KIT)
import build_props as bp  # noqa: E402  (module level only defines; main() is guarded)

OUT = os.path.join(HERE, "props_out")
os.makedirs(OUT, exist_ok=True)
bp.OUT = OUT
bp.TEXD = os.path.join(OUT, "textures")

CY, MG, AM, RD, WH = "M_Neon_Cyan", "M_Neon_Magenta", "M_Neon_Amber", "M_Neon_Red", "M_Neon_White"

SIGNS = [
    ("sign_box_gece_kahvesi_8m", "box8", [("GECE KAHVESI", AM)]),
    ("sign_box_bogaz_balik_8m", "box8", [("BOGAZ BALIK", CY)]),
    ("sign_box_lale_pasaji_8m", "box8", [("LALE PASAJI", MG)]),
    ("sign_box_yildiz_sinema_4m", "box4", [("YILDIZ SINEMA", AM)]),
    ("sign_box_kule_kitap_4m", "box4", [("KULE KITAP", CY)]),
    ("sign_box_ay_isigi_4m", "box4", [("AY ISIGI", MG)]),
    ("sign_blade_cinar_cay_evi", "blade", [("CINAR", CY), ("CAY EVI", CY)]),
    ("sign_blade_simit_firini", "blade", [("SIMIT", AM), ("FIRINI", RD)]),
    ("sign_blade_zumrut_otel", "blade", [("ZUMRUT", MG), ("OTEL", MG)]),
    ("sign_blade_marti_kafe", "blade", [("MARTI", CY), ("KAFE", AM)]),
]


def p_fountain():
    """Round plaza fountain with a ribbon sculpture: 14 m basin, LED rings, three steel arcs."""
    g = bp.Geo()
    g.merge(bp.cyl(7.0, 0.8, "M_Concrete", sides=28, rings=1))
    g.merge(bp.cyl(6.2, 0.04, "M_Concrete", sides=28, rings=1, z0=0.78))
    water = bp.cyl(6.0, 0.02, "M_Glass", sides=28, rings=1, z0=0.82)
    steel = bp.Geo()
    steel.merge(bp.cyl(0.55, 5.5, "M_Metal_Grey", sides=14, rings=4, r2=0.3, z0=0.8))
    for k in range(3):
        a0 = k * 2.0 * math.pi / 3.0
        pts = []
        for j in range(9):
            t = j / 8.0
            r = 3.6 * (1.0 - t) ** 0.8 + 0.25
            a = a0 + t * 1.6
            pts.append((r * math.cos(a), r * math.sin(a), 0.9 + 6.2 * t ** 0.7))
        steel.merge(bp.tube(pts, 0.11, "M_Metal_Grey", sides=6))
    led = bp.Geo()
    for r, z, tr in ((6.3, 0.86, 0.07), (4.2, 0.9, 0.06), (2.2, 0.95, 0.06)):
        ring = [(r * math.cos(2 * math.pi * i / 28), r * math.sin(2 * math.pi * i / 28), z) for i in range(28)]
        led.merge(bp.tube(ring, tr, CY, sides=5, closed=True))
    led.merge(bp.sphere(0.5, WH, seg=10, rings=6), None) if False else None
    top = bp.put(bp.Geo(), bp.sphere(0.45, WH, seg=10, rings=6), c=(0, 0, 6.5))
    return dict(category="circuit", mount="ground", budget=None, emissive=True,
                parts=[bp.part("fountain_basin", g, 0.02), bp.part("fountain_water", water),
                       bp.part("fountain_steel", steel), bp.part("fountain_led", led), bp.part("fountain_top", top)],
                lights=[bp.light((0, 0, 2.0), [0.1, 0.9, 1.0], 4.0, 20.0),
                        bp.light((0, 0, 6.6), [1.0, 0.95, 0.9], 2.0, 14.0)],
                notes="Plaza fountain with steel ribbon sculpture and cyan LED rings, original design")


def main():
    bp.define_materials()
    reg = {}
    for sid, kind, lines in SIGNS:
        if kind == "blade":
            reg[sid] = bp.blade_sign(sid, lines)
        elif kind == "box4":
            reg[sid] = bp.box_sign(sid, lines, 4.0)
        else:
            reg[sid] = bp.box_sign(sid, lines, 8.0)
    reg["sign_billboard_maslak_kule_12x5"] = bp.billboard_sign("sign_billboard_maslak_kule_12x5", "MASLAK KULE", CY)
    reg["sign_billboard_lale_plaza_12x5"] = bp.billboard_sign("sign_billboard_lale_plaza_12x5", "LALE PLAZA", MG)
    reg["fountain_plaza"] = p_fountain()
    items = []
    for pid, spec in reg.items():
        r = bp.build_prop(pid, spec)
        print("[ist]", pid, r["tris"], r["lod1_tris"])
        items.append({"id": r["id"], "category": r["category"], "file": r["file"], "size": r["size"],
                      "tris": r["tris"], "lod1_tris": r["lod1_tris"], "lod1_file": r["lod1_file"],
                      "collider_tris": r["collider_tris"], "materials": r["materials"], "lights": r["lights"],
                      "emissive": r["emissive"], "mount": r["mount"], "notes": r["notes"]})
    with open(os.path.join(OUT, "catalog.json"), "w", encoding="utf-8") as f:
        json.dump({"coords": "godot_y_up", "source": "assets_src/world/tracks/istanbul_maslak/build_props_ist.py",
                   "items": items}, f, indent=2)
    print("[ist] done", len(items))


main()
