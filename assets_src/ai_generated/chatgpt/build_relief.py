"""Relief (normal) maps for the photo fronts, derived from each picture itself: dark recesses (window glass, door
openings, shadow lines) read as set back, bright trim as proud. Run from the repo root: py -3.10 <this file>.
Writes game/assets/world/kits/photo_fronts/<name>_normal.png (1024x512) for every <name>.jpg that has no _night."""
import glob
import os

import numpy as np
from PIL import Image, ImageFilter

DIR = 'game/assets/world/kits/photo_fronts'
STRENGTH = 3.0
for path in sorted(glob.glob(DIR + '/*.jpg')):
    name = os.path.basename(path)[:-4]
    if name.endswith('_night'):
        continue
    grey = Image.open(path).convert('L').resize((1024, 512), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.2))
    h = np.asarray(grey, dtype=np.float32) / 255.0
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * STRENGTH
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * STRENGTH
    n = np.dstack([-dx, dy, np.ones_like(h)])  # +Y up in the texture (OpenGL style, as Godot expects)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255.0 + 0.5).astype(np.uint8), 'RGB').save('%s/%s_normal.png' % (DIR, name))
    print('ok', name)
