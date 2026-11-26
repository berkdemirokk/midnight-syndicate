"""Repaints the English shop-sign textures of the CC BY vinish.dev shop houses into Turkish (PIL, run with py -3.10).

  py -3.10 assets_src/pipeline/static_configs/repaint_signs.py

For every entry of SIGNS the sign image is read out of its source GLB (bufferView), its sign band is repainted with the
sign's own background colour and a Turkish word in the sign's light text colour (Arial Bold), and the result is written to
assets_src/pipeline/static_configs/signs/<asset>_<material>.png at the original size. prepare_static.py reads those PNGs.
Plain capitals, no diacritics, because the Arial glyphs are the only font used here.
"""
import json
import os
import struct
import sys
from collections import Counter

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
SRC = os.path.join(ROOT, "assets_src", "third_party", "vinish_env")
OUT = os.path.join(HERE, "signs")
FONT = "C:/Windows/Fonts/arialbd.ttf"

# asset file -> {material name in the GLB: Turkish word}
SIGNS = {
    "cafe-front": {"Sign_Cafe": "KAHVE"},
    "bookshop": {"Sign_Books": "KITAPCI"},
    "barber-shop": {"Sign_Barber": "BERBER"},
    "florist": {"Sign_Flowers": "CICEKCI"},
    "pharmacy": {"Sign_Pharmacy": "ECZANE"},
    "corner-shop": {"Sign_Grocer": "BAKKAL", "Sign_Grocer_Side": "MANAV"},
}


def glb_images(path):
    """Returns {image name: (mime, bytes)} and {material name: image name} of a GLB."""
    with open(path, "rb") as fh:
        data = fh.read()
    _m, _v, length = struct.unpack_from("<III", data, 0)
    off, doc, blob = 12, None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        body = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            doc = json.loads(body.decode("utf-8"))
        elif ctype == 0x004E4942:
            blob = body
        off += 8 + clen
    images = {}
    for i, img in enumerate(doc.get("images", [])):
        bv = doc["bufferViews"][img["bufferView"]]
        start = bv.get("byteOffset", 0)
        images[img.get("name", "image%d" % i)] = (img.get("mimeType", "image/png"), blob[start: start + bv["byteLength"]])
    mat_img = {}
    for mat in doc.get("materials", []):
        tex = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if tex is None:
            continue
        img_index = doc["textures"][tex["index"]]["source"]
        mat_img[mat["name"]] = doc["images"][img_index].get("name", "image%d" % img_index)
    return images, mat_img


def repaint(raw, word):
    import io
    img = Image.open(io.BytesIO(raw)).convert("RGB")
    w, h = img.size
    colours = Counter(img.getdata())
    bg = colours.most_common(1)[0][0]
    light = max(colours, key=lambda c: sum(c))  # lightest colour = the sign's text colour
    if sum(bg) > 600:  # light sign: a white text would vanish, so a dark green lettering
        light = (30, 80, 60)
    out = Image.new("RGB", (w, h), bg)
    draw = ImageDraw.Draw(out)
    inset = max(4, h // 16)
    draw.rectangle([inset, inset, w - inset - 1, h - inset - 1], outline=light, width=max(2, h // 40))
    size = int(h * 0.56)
    font = ImageFont.truetype(FONT, size)
    while draw.textbbox((0, 0), word, font=font)[2] > w * 0.82:
        size -= 2
        font = ImageFont.truetype(FONT, size)
    l, t, r, b = draw.textbbox((0, 0), word, font=font)
    draw.text(((w - (r - l)) / 2 - l, (h - (b - t)) / 2 - t), word, font=font, fill=light)
    return out, bg, light


def main():
    os.makedirs(OUT, exist_ok=True)
    for asset, mats in SIGNS.items():
        images, mat_img = glb_images(os.path.join(SRC, asset + ".glb"))
        for mat, word in mats.items():
            name = mat_img[mat]
            mime, raw = images[name]
            out, bg, light = repaint(raw, word)
            dst = os.path.join(OUT, "%s_%s.png" % (asset.replace("-", "_"), mat))
            out.save(dst)
            print("%s %s -> %s bg=%s text=%s size=%s" % (asset, mat, word, bg, light, out.size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
