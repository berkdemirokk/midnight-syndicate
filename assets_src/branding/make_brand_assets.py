"""STREET EMPIRE brand renders: app icon (1024/512/192 + .ico) and the boot splash (1920x1080).

Run from the repo root: py -3.10 assets_src/branding/make_brand_assets.py
Deterministic, PIL only, fonts from game/assets/branding/fonts (SIL OFL). Replaces the Midnight Syndicate renders in
place, so project.godot and export_presets.cfg keep their paths. Rules: docs/brand/BRAND_GUIDELINES.md.
"""
import math
import os
import struct
import io

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FONTS = os.path.join(ROOT, "game", "assets", "branding", "fonts")
OUT = os.path.join(ROOT, "game", "assets", "branding")
GRAPHITE = (16, 18, 22)
DEEP = (7, 8, 10)
RED = (240, 68, 50)
PEARL = (244, 244, 244)
TITANIUM = (196, 200, 206)
LEAN = math.tan(math.radians(8.0))


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def shear(img):
    """Leans a layer 8 degrees to the right around its bottom edge (the wordmark's italic)."""
    w, h = img.size
    pad = int(h * LEAN) + 2
    wide = Image.new("RGBA", (w + pad, h), (0, 0, 0, 0))
    wide.paste(img, (0, 0))
    # PIL affine maps output -> input: x_in = x_out + LEAN * (y_out - h) ... shifted so the baseline stays put
    return wide.transform(wide.size, Image.AFFINE, (1, LEAN, -LEAN * h, 0, 1, 0), resample=Image.BICUBIC)


def studio(w, h, key=(0.5, 0.18), strength=0.16):
    """Graphite with one soft overhead key light and a vignette."""
    img = Image.new("RGB", (w, h), GRAPHITE)
    px = img.load()
    kx, ky = key[0] * w, key[1] * h
    for y in range(h):
        for x in range(w):
            d = math.hypot((x - kx) / w * 1.2, (y - ky) / h * 1.6)
            lift = strength * math.exp(-d * d * 4.0)
            v = math.hypot((x / w - 0.5) * 1.1, (y / h - 0.5) * 1.3)
            dark = 1.0 - 0.55 * v * v
            px[x, y] = tuple(int(min(255, (c + 255 * lift * (t / 255.0)) * dark)) for c, t in zip(GRAPHITE, TITANIUM))
    return img


def wordmark(size, tagline=True):
    """STREET / EMPIRE in Anton, the red blade between, leaning 8 degrees; optional RULE THE CITY line. RGBA."""
    f = font("Anton-Regular.ttf", size)
    asc, desc = f.getmetrics()
    top, base = f.getbbox("E")[1], f.getbbox("E")[3]  # real cap top and baseline of the drawn glyphs
    cap = base - top
    wa = f.getlength("STREET")
    wb = f.getlength("EMPIRE")
    gap = size * 0.10
    blade = size * 0.16
    w = int(wa + wb + gap * 2 + blade + 8)
    h = asc + desc
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text((0, 0), "STREET", font=f, fill=PEARL)
    x = wa + gap
    d.polygon([(x + blade * 0.55, base - cap), (x + blade, base - cap), (x + blade * 0.45, base), (x, base)], fill=RED)
    d.text((x + blade + gap, 0), "EMPIRE", font=f, fill=PEARL)
    layer = shear(layer.crop((0, top - 2, w, base + 2)))
    if not tagline:
        return layer
    tf = font("Manrope-Bold.ttf", max(10, int(size * 0.19)))
    text = "R U L E   T H E   C I T Y"
    tw = tf.getlength(text)
    th = int(size * 0.30)
    out = Image.new("RGBA", (max(layer.width, int(tw + size * 0.5)), layer.height + int(size * 0.14) + th), (0, 0, 0, 0))
    out.paste(layer, (0, 0), layer)
    d = ImageDraw.Draw(out)
    ty = layer.height + int(size * 0.14)
    rule = int(size * 0.29)
    d.rectangle([2, ty + th * 0.38, 2 + rule, ty + th * 0.38 + max(2, size // 48)], fill=RED)
    d.text((rule + size * 0.13, ty), text, font=tf, fill=TITANIUM)
    return out


def icon(size=1024):
    img = studio(size, size, key=(0.5, 0.0), strength=0.22).convert("RGBA")
    f = font("Anton-Regular.ttf", int(size * 0.50))
    asc, desc = f.getmetrics()
    top, base = f.getbbox("E")[1], f.getbbox("E")[3]
    cap = base - top
    ws, we = f.getlength("S"), f.getlength("E")
    blade = size * 0.11
    gap = size * 0.045
    w = int(ws + we + blade + gap * 2 + 4)
    layer = Image.new("RGBA", (w, asc + desc), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text((0, 0), "S", font=f, fill=PEARL)
    x = ws + gap
    d.polygon([(x + blade * 0.55, top), (x + blade, top), (x + blade * 0.45, base), (x, base)], fill=RED)
    d.text((x + blade + gap, 0), "E", font=f, fill=PEARL)
    layer = shear(layer.crop((0, top - 2, w, base + 2)))
    # soft contact shadow under the monogram, then the monogram, optically centred a touch high
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ox = (size - layer.width) // 2
    oy = int(size * 0.47 - layer.height / 2)
    sh.paste((0, 0, 0, 150), (ox + 10, oy + 18), layer)
    img = Image.alpha_composite(img, sh.filter(ImageFilter.GaussianBlur(size * 0.02)))
    img.paste(layer, (ox, oy), layer)
    # thin red floor line under the mark: the showroom's horizon
    d = ImageDraw.Draw(img)
    ly = oy + layer.height + int(size * 0.07)
    d.rectangle([int(size * 0.36), ly, int(size * 0.64), ly + max(2, size // 200)], fill=TITANIUM)
    return img.convert("RGB")


def splash(w=1920, h=1080):
    img = studio(w, h, key=(0.5, 0.3), strength=0.12).convert("RGBA")
    wm = wordmark(150)
    img.paste(wm, ((w - wm.width) // 2, int(h * 0.44 - wm.height / 2)), wm)
    return img.convert("RGB")


def ico(src, path):
    sizes = (16, 24, 32, 48, 64, 128, 256)
    blobs = []
    for n in sizes:
        b = io.BytesIO()
        src.resize((n, n), Image.LANCZOS).save(b, "PNG")
        blobs.append(b.getvalue())
    head = struct.pack("<HHH", 0, 1, len(sizes))
    off = 6 + 16 * len(sizes)
    ents = b""
    for n, b in zip(sizes, blobs):
        ww = 0 if n >= 256 else n
        ents += struct.pack("<BBBBHHII", ww, ww, 0, 0, 1, 32, len(b), off)
        off += len(b)
    with open(path, "wb") as fh:
        fh.write(head + ents + b"".join(blobs))


def main():
    big = icon(1024)
    big.save(os.path.join(OUT, "icon_1024.png"), optimize=True)
    for n in (512, 192):
        big.resize((n, n), Image.LANCZOS).save(os.path.join(OUT, "icon_%d.png" % n), optimize=True)
    ico(big, os.path.join(OUT, "icon.ico"))
    splash().save(os.path.join(OUT, "splash_1920.png"), optimize=True)
    wordmark(240).save(os.path.join(OUT, "wordmark_street_empire.png"), optimize=True)
    print("brand assets written to", OUT)


if __name__ == "__main__":
    main()
