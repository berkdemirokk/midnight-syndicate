"""Number plates in the Turkish layout (blue band with TR, black characters on white), drawn with our own
stroke glyphs so no font file is involved. The numbers are invented. Writes <car>_lodN_plate_base.png in place,
keeping each file's size. Run: py -3.10 assets_src/vehicles/shared/build_plates.py"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
PLATES = {}  # the project-made cars with a plate per LOD were replaced by licensed models on 2026-11-27 (see below)
SS = 4  # supersampling
G = {  # polylines on a 4 x 8 cell, y down; chamfered corners like a plate typeface
    "0": [[(1, 0), (3, 0), (4, 1), (4, 7), (3, 8), (1, 8), (0, 7), (0, 1), (1, 0)]],
    "1": [[(1, 2), (2.5, 0), (2.5, 8)]],
    "2": [[(0, 1.5), (1, 0), (3, 0), (4, 1), (4, 3), (0, 8), (4, 8)]],
    "3": [[(0, 1), (1, 0), (3, 0), (4, 1), (4, 3), (3, 4), (1.5, 4)], [(3, 4), (4, 5), (4, 7), (3, 8), (1, 8), (0, 7)]],
    "4": [[(3, 8), (3, 0), (0, 5.5), (4, 5.5)]],
    "5": [[(4, 0), (0.5, 0), (0, 3.5), (3, 3.5), (4, 4.5), (4, 7), (3, 8), (1, 8), (0, 7)]],
    "6": [[(3.5, 0), (2, 0), (0, 3), (0, 7), (1, 8), (3, 8), (4, 7), (4, 5), (3, 4), (1, 4), (0, 5)]],
    "7": [[(0, 0), (4, 0), (1.5, 8)]],
    "8": [[(1, 0), (3, 0), (4, 1), (4, 3), (3, 4), (1, 4), (0, 3), (0, 1), (1, 0)],
          [(1, 4), (0, 5), (0, 7), (1, 8), (3, 8), (4, 7), (4, 5), (3, 4)]],
    "9": [[(0.5, 8), (2, 8), (4, 5), (4, 1), (3, 0), (1, 0), (0, 1), (0, 3), (1, 4), (3, 4), (4, 3)]],
    "M": [[(0, 8), (0, 0), (2, 4.5), (4, 0), (4, 8)]],
    "S": [[(4, 1), (3, 0), (1, 0), (0, 1), (0, 3), (1, 4), (3, 4), (4, 5), (4, 7), (3, 8), (1, 8), (0, 7)]],
    "N": [[(0, 8), (0, 0), (4, 8), (4, 0)]],
    "V": [[(0, 0), (2, 8), (4, 0)]],
    "A": [[(0, 8), (2, 0), (4, 8)], [(0.9, 5.5), (3.1, 5.5)]],
    "B": [[(0, 0), (3, 0), (4, 1), (4, 3), (3, 4), (0, 4)], [(3, 4), (4, 5), (4, 7), (3, 8), (0, 8), (0, 0)]],
    "K": [[(0, 0), (0, 8)], [(4, 0), (0, 5)], [(1.6, 3.4), (4, 8)]],
    "G": [[(4, 1), (3, 0), (1, 0), (0, 1), (0, 7), (1, 8), (3, 8), (4, 7), (4, 4.5), (2.2, 4.5)]],
    "T": [[(0, 0), (4, 0)], [(2, 0), (2, 8)]],
    "H": [[(0, 0), (0, 8)], [(4, 0), (4, 8)], [(0, 4), (4, 4)]],
    "R": [[(0, 8), (0, 0), (3, 0), (4, 1), (4, 3), (3, 4), (0, 4)], [(2, 4), (4, 8)]],
    "Y": [[(0, 0), (2, 4)], [(4, 0), (2, 4), (2, 8)]],
}


def text(d, s, x, y, unit, stroke, colour, gap=1.5, space=2.2):
    for ch in s:
        if ch == " ":
            x += unit * space
            continue
        for line in G[ch]:
            pts = [(x + px * unit, y + py * unit) for px, py in line]
            d.line(pts, fill=colour, width=stroke, joint="curve")
            for p in (pts[0], pts[-1]):
                d.ellipse((p[0] - stroke / 2, p[1] - stroke / 2, p[0] + stroke / 2, p[1] + stroke / 2), fill=colour)
        x += unit * (4 + gap)
    return x


def width(s, unit, gap=1.5, space=2.2):
    return sum(unit * space if c == " " else unit * (4 + gap) for c in s) - unit * gap


def plate(number, w=512, h=128):
    W, H = w * SS, h * SS
    im = Image.new("RGB", (W, H), (236, 238, 234))
    d = ImageDraw.Draw(im)
    band = int(W * 0.105)
    d.rectangle((0, 0, band, H), fill=(20, 62, 150))
    tu = band / 16.0
    text(d, "TR", band / 2 - width("TR", tu) / 2, H * 0.66, tu, int(tu * 1.5), (240, 242, 245))
    unit = H * 0.56 / 8.0
    x0 = band + (W - band - width(number, unit)) / 2
    text(d, number, x0, H * 0.22, unit, int(unit * 1.25), (14, 14, 16))
    b = 3 * SS
    d.rectangle((b // 2, b // 2, W - b // 2 - 1, H - b // 2 - 1), outline=(14, 14, 16), width=b)
    return im.resize((w, h), Image.LANCZOS)


for car, number in PLATES.items():
    for lod in range(3):
        p = os.path.join(ROOT, "game", "assets", "vehicles", car, "%s_lod%d_plate_base.png" % (car, lod))
        if not os.path.exists(p):
            continue
        w, h = Image.open(p).size
        plate(number).resize((w, h), Image.LANCZOS).save(p)
        print(p, w, h)

# Pipeline cars (assets_src/pipeline/prepare_vehicle.py): one plate image per car, 512 x 128, read by the config.
PIPELINE_PLATES = {"kestrel_vanta": "34 KV 517", "arden_havoc": "34 AH 208", "noctra_tayfun": "34 NT 077",
                   "noctra_meridian": "34 NM 364", "kestrel_marten": "34 KM 428", "bosfor_yildirim": "34 BY 001",
                   "bosfor_kivilcim": "34 BK 113", "bosfor_serce": "34 BS 226", "arden_ramjet": "34 AR 552", "arden_shaker": "34 AS 719",
                   "noctra_sable": "34 MS 2026", "noctra_vela": "34 NV 707", "arden_bruiser": "06 AB 458",
                   "kestrel_gtr": "35 KG 382", "atmaca_modified": "34 VS 034",
                   "noctra_volta": "34 NV 901", "noctra_sovereign": "34 NS 903", "noctra_titan": "34 NT 905",
                   "bosfor_kartal": "34 KR 141", "bosfor_lale": "34 BA 616", "bosfor_galata": "34 GT 304",
                   "bosfor_moda": "34 MA 211", "bosfor_pera": "34 TR 459", "bosfor_sahil": "34 SH 528"}
PLATE_DIRS = {"atmaca_modified": "bosfor_atmaca"}  # cars whose asset folder is not named after the car id
for car, number in PIPELINE_PLATES.items():
    d = os.path.join(ROOT, "game", "assets", "vehicles", PLATE_DIRS.get(car, car))
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "%s_plate_base.png" % car)
    plate(number).save(p)
    print(p, 512, 128)
