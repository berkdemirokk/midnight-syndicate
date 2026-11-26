"""Builds the track-side dressing textures from the ChatGPT pictures in this folder.

Inputs (kept as sources, see ASSET_MANIFEST.json):
  sponsor_boards_01.png   four printed sponsor boards side by side on white
  spectators_front_row_01.png / spectators_back_row_01.png
                          eleven standing spectators each, on a flat pure green (#00FF00) background

Outputs (game/assets/world/kits/event_photo/):
  sponsor_boards_atlas.jpg  2048x256, four boards in cells of 512x256 (cell i = board i)
  crowd_cards_atlas.png     2048x2048 RGBA, 8 x 4 cells of 256x512. Front cell k = k (0..10),
                            back cell k = 16 + k (0..10). Feet on the bottom row of every cell.

Run: py -3.10 assets_src/ai_generated/chatgpt/build_event_photo.py
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "..", "game", "assets", "world", "kits", "event_photo")
PEOPLE = 11
CELL_W, CELL_H = 256, 512
ATLAS_COLS, ATLAS_ROWS = 8, 4
BACK_OFFSET = 16


def load_rgb(name: str) -> np.ndarray:
    return np.asarray(Image.open(os.path.join(HERE, name)).convert("RGB")).astype(np.float32)


def build_boards() -> None:
    rgb = load_rgb("sponsor_boards_01.png")
    # the four boards of the 2172x724 picture (white background; the white board 2 has no edge to detect)
    y0, y1 = 259, 481
    runs = [(0, 542), (548, 1087), (1093, 1632), (1638, 2172)]
    atlas = Image.new("RGB", (2048, 256), (255, 255, 255))
    for i, (x0, x1) in enumerate(runs):
        board = Image.fromarray(rgb[y0:y1, x0:x1].astype(np.uint8)).resize((512, 256), Image.LANCZOS)
        atlas.paste(board, (i * 512, 0))
    os.makedirs(OUT, exist_ok=True)
    atlas.save(os.path.join(OUT, "sponsor_boards_atlas.jpg"), quality=93)
    print("boards", runs, "rows", y0, y1)


def key_green(rgb: np.ndarray) -> np.ndarray:
    """Alpha from green spill: 0 on pure green, 1 on the people. Despills the edge pixels in place."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    spill = g - np.maximum(r, b)
    alpha = np.clip((90.0 - spill) / 60.0, 0.0, 1.0)
    # green edge pixels: pull green down to the other channels so no green fringe is left
    edge = alpha < 1.0
    rgb[..., 1] = np.where(edge & (spill > 0), np.maximum(r, b), g)
    return alpha


def people_runs(alpha: np.ndarray) -> list:
    col = (alpha > 0.5).sum(axis=0)
    on = col > 0.04 * alpha.shape[0]  # a gap column has a few speckles of the key, a person has many pixels
    runs, start = [], None
    for x in range(alpha.shape[1]):
        if on[x] and start is None:
            start = x
        if not on[x] and start is not None:
            runs.append((start, x))
            start = None
    if start is not None:
        runs.append((start, alpha.shape[1]))
    runs = [r for r in runs if r[1] - r[0] > 12]
    # people that touch at the shoulders make one run: split the widest run at its thinnest column
    while len(runs) < PEOPLE:
        i = max(range(len(runs)), key=lambda k: runs[k][1] - runs[k][0])
        x0, x1 = runs[i]
        lo, hi = x0 + (x1 - x0) // 5, x1 - (x1 - x0) // 5
        cut = lo + int(np.argmin(col[lo:hi]))
        runs[i:i + 1] = [(x0, cut), (cut, x1)]
    return runs


def cut_row(name: str, base: int) -> list:
    rgb = load_rgb(name)
    alpha = key_green(rgb)
    runs = people_runs(alpha)
    if len(runs) != PEOPLE:
        sys.exit("%s: expected %d people, found %d: %s" % (name, PEOPLE, len(runs), runs))
    cells = []
    for i, (x0, x1) in enumerate(runs):
        a = Image.fromarray((alpha[:, x0:x1] * 255).astype(np.uint8))
        a = a.filter(ImageFilter.MinFilter(3))  # one pixel inward: no light fringe left from the key
        arr = np.asarray(a)
        rows = np.where((arr > 127).sum(axis=1) > 2)[0]
        ya, yb = int(rows.min()), int(rows.max()) + 1
        person = Image.fromarray(rgb[ya:yb, x0:x1].astype(np.uint8)).convert("RGBA")
        person.putalpha(a.crop((0, ya, x1 - x0, yb)))
        # fit: height 500 px (top margin 6), width at most 250 px, feet on the bottom row of the cell
        scale = min(500.0 / (yb - ya), 250.0 / (x1 - x0))
        nw, nh = max(1, round((x1 - x0) * scale)), max(1, round((yb - ya) * scale))
        person = person.resize((nw, nh), Image.LANCZOS)
        cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        cell.alpha_composite(person, ((CELL_W - nw) // 2, CELL_H - 6 - nh))
        cells.append((base + i, cell))
        print(name, "person", i, "box", (x0, ya, x1, yb), "cell", nw, nh)
    return cells


def build_crowd() -> None:
    atlas = Image.new("RGBA", (ATLAS_COLS * CELL_W, ATLAS_ROWS * CELL_H), (0, 0, 0, 0))
    for index, cell in cut_row("spectators_front_row_01.png", 0) + cut_row("spectators_back_row_01.png", BACK_OFFSET):
        atlas.paste(cell, ((index % ATLAS_COLS) * CELL_W, (index // ATLAS_COLS) * CELL_H))
    atlas.save(os.path.join(OUT, "crowd_cards_atlas.png"), optimize=True)
    print("crowd atlas", atlas.size)


if __name__ == "__main__":
    build_boards()
    build_crowd()
