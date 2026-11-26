"""Event kit textures (Python 3.10 + Pillow, deterministic, original art only, no downloads).

Run:  py -3.10 assets_src/world/kit_event/gen_event_textures.py
Writes game/assets/world/kits/event/:
  banner_atlas.png    1024x1024, 4 rows of 256: rows 0-2 race banners (original sponsor names), row 3 concrete
  crowd_atlas.png     512x1024, 4x4 cells of 128x256: 16 standing spectators, alpha kept
  flag_tr.png         512x512, red flag 3:2 in rows 85..426 (white crescent and star), the rest red
  awning_atlas.png    512x512: TL stripes (canopy top), TR warm cream (underside), BL dark metal (frame)
  awning_glow.png     512x512 emission mask: only TR is lit
  light_pool.png      256x256 warm radial pool, alpha falloff, for additive quads
Fonts: Windows system Impact (banner lettering is drawn into the texture, the font is not shipped).
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "game", "assets", "world", "kits", "event")
IMPACT = "C:/Windows/Fonts/impact.ttf"


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name), "PNG", optimize=True)
    print("[textures] wrote", name, img.size)


def fit_font(path, text, max_w, start):
    size = start
    while size > 8:
        f = ImageFont.truetype(path, size)
        box = f.getbbox(text)
        if box[2] - box[0] <= max_w:
            return f
        size -= 2
    return ImageFont.truetype(path, 8)


def italic_text(tile, text, font, fill, centre, shear=0.22, stroke=0, stroke_fill=None):
    """Lettering on its own layer, sheared to a race-poster slant, then pasted on the tile."""
    layer = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text(centre, text, font=font, fill=fill, anchor="mm", stroke_width=stroke, stroke_fill=stroke_fill)
    w, h = tile.size
    layer = layer.transform((w, h), Image.AFFINE, (1, shear, -shear * h / 2, 0, 1, 0), resample=Image.BICUBIC)
    tile.alpha_composite(layer)


def concrete_tile(w, h, rng):
    tile = Image.new("RGBA", (w, h), (120, 118, 112, 255))
    px = tile.load()
    for _ in range(w * h // 5):
        x, y = rng.randrange(w), rng.randrange(h)
        k = rng.randint(-22, 14)
        r, g, b, _a = px[x, y]
        px[x, y] = (max(0, min(255, r + k)), max(0, min(255, g + k)), max(0, min(255, b + k)), 255)
    d = ImageDraw.Draw(tile)
    for _ in range(6):  # rain streaks and a darker footing line
        x = rng.randrange(w)
        d.line([(x, 0), (x + rng.randint(-6, 6), h)], fill=(90, 88, 84, 255), width=2)
    d.rectangle([0, h - 18, w, h], fill=(64, 62, 60, 255))
    return tile


def banner_atlas():
    rng = random.Random(7)
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 255))
    W = 1024
    # Row 0: deep red, gold rules, white lettering
    b0 = Image.new("RGBA", (W, 256), (150, 18, 26, 255))
    d = ImageDraw.Draw(b0)
    d.rectangle([0, 16, W, 26], fill=(230, 180, 70, 255))
    d.rectangle([0, 230, W, 240], fill=(230, 180, 70, 255))
    t0 = "ISTANBUL STREET RACING"
    italic_text(b0, t0, fit_font(IMPACT, t0, 900, 150), (255, 250, 240, 255), (W // 2, 128),
                stroke=3, stroke_fill=(60, 0, 6, 255))
    # Row 1: near-black with cyan neon lettering
    b1 = Image.new("RGBA", (W, 256), (10, 12, 22, 255))
    d = ImageDraw.Draw(b1)
    for x in range(0, W, 64):
        d.line([(x, 0), (x + 40, 256)], fill=(20, 26, 44, 255), width=3)
    t1 = "MIDNIGHT SYNDICATE"
    italic_text(b1, t1, fit_font(IMPACT, t1, 900, 160), (120, 240, 255, 255), (W // 2, 128),
                stroke=4, stroke_fill=(10, 60, 90, 255))
    # Row 2: sponsor strip, three invented names on warm cream
    b2 = Image.new("RGBA", (W, 256), (232, 220, 196, 255))
    d = ImageDraw.Draw(b2)
    d.rectangle([0, 0, W, 24], fill=(30, 30, 34, 255))
    d.rectangle([0, 232, W, 256], fill=(30, 30, 34, 255))
    names = [("BOSFOR TYRES", (24, 24, 28, 255)), ("ATMACA OIL", (176, 34, 30, 255)),
             ("LALE ENERGY", (28, 96, 74, 255))]
    for i, (txt, col) in enumerate(names):
        cx = int(W * (0.17 + 0.33 * i))
        italic_text(b2, txt, fit_font(IMPACT, txt, 300, 96), col, (cx, 128), shear=0.18)
    # Row 3: concrete body of the barrier
    b3 = concrete_tile(W, 256, rng)
    for i, b in enumerate([b0, b1, b2, b3]):
        atlas.paste(b, (0, i * 256))
    save(atlas, "banner_atlas.png")


def figure(cell_w, cell_h, rng):
    """One standing spectator silhouette: clothing colour variety, lighter face and hands."""
    im = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = cell_w // 2
    shirt = rng.choice([(200, 52, 48), (40, 90, 170), (230, 200, 70), (60, 140, 90), (235, 235, 235),
                        (30, 30, 36), (150, 70, 160), (240, 120, 40), (90, 170, 200)])
    trouser = rng.choice([(38, 40, 52), (70, 62, 52), (30, 52, 92), (90, 90, 96)])
    skin = rng.choice([(224, 178, 140), (196, 144, 106), (150, 104, 74), (240, 200, 166)])
    hair = rng.choice([(24, 18, 14), (70, 46, 26), (120, 90, 50), (150, 150, 150), (10, 10, 10)])
    s = rng.uniform(0.82, 1.06)
    top = int(cell_h * 0.05)
    head_r = int(cell_w * 0.11 * s)
    hy = top + head_r
    d.ellipse([cx - head_r, hy - head_r, cx + head_r, hy + head_r], fill=skin + (255,))
    if rng.random() < 0.6:  # hair
        d.chord([cx - head_r - 1, hy - head_r - 2, cx + head_r + 1, hy + head_r * 0.2], 180, 360, fill=hair + (255,))
    if rng.random() < 0.15:  # cap brim
        d.rectangle([cx - head_r - 4, hy - head_r * 0.7, cx + head_r + 14, hy - head_r * 0.5], fill=(180, 30, 30, 255))
    neck = hy + head_r
    sh_w = int(cell_w * 0.27 * s)
    torso_bottom = int(cell_h * 0.56)
    d.polygon([(cx - sh_w, neck + 4), (cx + sh_w, neck + 4), (cx + sh_w - 4, torso_bottom),
               (cx - sh_w + 4, torso_bottom)], fill=shirt + (255,))
    arm_w = max(3, int(cell_w * 0.06))
    arm_end = torso_bottom + int(cell_h * 0.1)
    for side in (-1, 1):
        ax = cx + side * (sh_w + arm_w // 2)
        d.line([(ax, neck + 10), (ax + side * 2, arm_end)], fill=shirt + (255,), width=arm_w)
        d.ellipse([ax - 3 + side * 2, arm_end - 3, ax + 3 + side * 2, arm_end + 6], fill=skin + (255,))
    leg_w = int(cell_w * 0.12)
    bottom = cell_h - int(cell_h * 0.03)
    for side in (-1, 1):
        lx = cx + side * int(cell_w * 0.09)
        d.rectangle([lx - leg_w // 2, torso_bottom - 2, lx + leg_w // 2, bottom - 8], fill=trouser + (255,))
        d.rectangle([lx - leg_w // 2 - 2, bottom - 8, lx + leg_w // 2 + 3, bottom], fill=(18, 16, 16, 255))
    return im


def crowd_atlas():
    rng = random.Random(23)
    atlas = Image.new("RGBA", (512, 1024), (0, 0, 0, 0))
    for i in range(16):
        f = figure(128, 256, rng)
        atlas.alpha_composite(f, ((i % 4) * 128, (i // 4) * 256))
    save(atlas, "crowd_atlas.png")


def star_points(cx, cy, r_out, r_in, n=5, rot=-math.pi / 2):
    pts = []
    for k in range(2 * n):
        r = r_out if k % 2 == 0 else r_in
        a = rot + k * math.pi / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def flag():
    """Red flag, 3:2, hoist on the left. White crescent with its convex side to the hoist and its mouth to the
    fly; the five-point star sits in the crescent's mouth. Proportions follow the national flag's layout."""
    S = 4  # supersampling for clean edges
    W, H = 512 * S, 512 * S
    fh = 341 * S
    fw = 512 * S
    top = (H - fh) // 2
    red = (227, 10, 23, 255)
    im = Image.new("RGBA", (W, H), red)
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    R = fh * 0.25  # outer radius of the crescent: a diameter of half the flag height
    cx, cy = fw * 0.34, top + fh * 0.5
    md.ellipse([cx - R, cy - R, cx + R, cy + R], fill=255)
    inner_r = R * 0.8
    off = R * 0.25
    md.ellipse([cx + off - inner_r, cy - inner_r, cx + off + inner_r, cy + inner_r], fill=0)
    md.polygon(star_points(cx + R * 0.5, cy, R * 0.42, R * 0.42 * 0.382), fill=255)
    white = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    im = Image.composite(white, im, mask)
    im = im.resize((512, 512), Image.LANCZOS)
    save(im, "flag_tr.png")


def awning():
    atlas = Image.new("RGBA", (512, 512), (40, 40, 44, 255))
    d = ImageDraw.Draw(atlas)
    stripe_w = 512 // 2 // 8
    for i in range(8):  # TL canopy top: red and cream stripes
        col = (178, 36, 40, 255) if i % 2 == 0 else (236, 222, 196, 255)
        d.rectangle([i * stripe_w, 0, (i + 1) * stripe_w - 1, 255], fill=col)
    d.rectangle([256, 0, 511, 255], fill=(232, 196, 130, 255))  # TR underside, warm cream
    d.rectangle([256, 256, 511, 511], fill=(92, 60, 40, 255))  # BR wood: tables and chairs
    save(atlas, "awning_atlas.png")
    glow = Image.new("RGBA", (512, 512), (0, 0, 0, 255))
    ImageDraw.Draw(glow).rectangle([256, 0, 511, 255], fill=(255, 176, 92, 255))
    save(glow, "awning_glow.png")


def light_pool():
    n = 256
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    px = im.load()
    for y in range(n):
        for x in range(n):
            r = math.hypot((x - n / 2) / (n / 2), (y - n / 2) / (n / 2))
            a = max(0.0, 1.0 - r) ** 2.2
            px[x, y] = (255, 178, 96, int(255 * a))
    save(im, "light_pool.png")


if __name__ == "__main__":
    banner_atlas()
    crowd_atlas()
    flag()
    awning()
    light_pool()
