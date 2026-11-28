"""Builds the photo tree textures for game/world/greenery from the ChatGPT source pictures.

Input: assets_src/ai_generated/chatgpt/<name>.png (RGBA, tree on a transparent background, ground line at the bottom).
Output (game/assets/world/kits/trees_photo/):
  plane_atlas.png        1024x512 RGBA: two plane trees side by side, each 512x512 (plane_a | plane_b)
  plane_atlas_night.jpg  same layout, 1024x512 RGB: the night pictures, lit crowns on black (the glow map)
  cypress.png            256x512 RGBA
  judas.png              512x512 RGBA

Alpha is cleaned (faint fringe removed) and the colour under the transparent area is bled outward so mipmaps
do not pick up a dark or white halo. Run: py -3.10 assets_src/ai_generated/chatgpt/prepare_photo_trees.py
"""
import os

import numpy as np
from PIL import Image

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(SRC, "..", "..", "..", "game", "assets", "world", "kits", "trees_photo")
TREE_PX = 512  # atlas cell (was 1024): the crown is well under 512 px on screen


def load(name: str) -> np.ndarray:
    return np.array(Image.open(os.path.join(SRC, name + ".png")).convert("RGBA"))


def crop_bounds(arr: np.ndarray) -> tuple:
    """Alpha bounds on x (the picture keeps its own full height: ground line at the bottom)."""
    xs = np.where((arr[:, :, 3] > 8).any(axis=0))[0]
    return int(xs.min()), int(xs.max()) + 1


def clean_alpha(arr: np.ndarray) -> np.ndarray:
    """Removes the faint fringe, then bleeds the colour of solid pixels into the transparent rim."""
    rgba = arr.astype(np.float32)
    a = np.clip((rgba[:, :, 3] - 20.0) * 255.0 / 200.0, 0.0, 255.0)
    solid = (a >= 200.0).astype(np.float32)
    rgb = rgba[:, :, :3]
    weight = box(solid, 6)
    colour = box(rgb * solid[:, :, None], 6) / np.maximum(weight, 1e-6)[:, :, None]
    rgb = np.where(solid[:, :, None] > 0, rgb, colour)
    rgb = np.where((weight > 1e-6)[:, :, None], rgb, 0.0)
    out = np.dstack([rgb, a])
    return np.clip(out, 0, 255).astype(np.uint8)


def box(a: np.ndarray, r: int) -> np.ndarray:
    """Separable box sum over a (2r+1) window, clipped at the edges."""
    out = a
    for axis in (0, 1):
        n = out.shape[axis]
        cs_shape = list(out.shape)
        cs_shape[axis] = 1
        cs = np.concatenate([np.zeros(cs_shape, dtype=np.float64), np.cumsum(out, axis=axis, dtype=np.float64)], axis=axis)
        idx = np.arange(n)
        hi = np.clip(idx + r + 1, 0, n)
        lo = np.clip(idx - r, 0, n)
        out = np.take(cs, hi, axis=axis) - np.take(cs, lo, axis=axis)
    return out


def fit(arr: np.ndarray, out_w: int, out_h: int) -> np.ndarray:
    """Scales the picture to out_h tall and centres it in an out_w x out_h canvas (transparent padding)."""
    h, w = arr.shape[:2]
    s = out_h / float(h)
    nw = max(1, int(round(w * s)))
    img = Image.fromarray(arr).resize((nw, out_h), Image.LANCZOS)
    canvas = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
    canvas.paste(img, ((out_w - nw) // 2, 0))
    return np.array(canvas)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    # Each day picture and its night picture share one x-crop, so the two stay pixel-aligned.
    day_a, night_a = load("plane_a_day"), load("plane_a_night")
    day_b, night_b = load("plane_b_day"), load("plane_b_night")
    ax0, ax1 = crop_bounds(day_a)
    bx0, bx1 = crop_bounds(day_b)
    atlas = np.concatenate([fit(day_a[:, ax0:ax1], TREE_PX, TREE_PX), fit(day_b[:, bx0:bx1], TREE_PX, TREE_PX)], axis=1)
    night = np.concatenate([fit(_night_rgba(night_a, day_a, ax0, ax1), TREE_PX, TREE_PX),
                            fit(_night_rgba(night_b, day_b, bx0, bx1), TREE_PX, TREE_PX)], axis=1)
    atlas = clean_alpha(atlas)
    Image.fromarray(atlas).save(os.path.join(OUT, "plane_atlas.png"), optimize=True)
    Image.fromarray(night[:, :, :3]).save(os.path.join(OUT, "plane_atlas_night.jpg"), quality=90)

    cyp_day = load("cypress_c_day")
    cx0, cx1 = crop_bounds(cyp_day)
    cyp = clean_alpha(fit(cyp_day[:, cx0:cx1], TREE_PX // 2, TREE_PX))
    Image.fromarray(cyp).save(os.path.join(OUT, "cypress.png"), optimize=True)
    judas_day = load("judas_d_day")
    jx0, jx1 = crop_bounds(judas_day)
    judas = clean_alpha(fit(judas_day[:, jx0:jx1], TREE_PX, TREE_PX))
    Image.fromarray(judas).save(os.path.join(OUT, "judas.png"), optimize=True)
    print("written to", os.path.normpath(OUT))


def _night_rgba(night: np.ndarray, day: np.ndarray, x0: int, x1: int) -> np.ndarray:
    """Night picture cut to the day picture's x-range; black where the day picture has no tree."""
    out = night[:, x0:x1].copy()
    outside = day[:, x0:x1, 3] <= 8
    out[outside, :3] = 0
    out[:, :, 3] = 255
    return out


if __name__ == "__main__":
    main()
