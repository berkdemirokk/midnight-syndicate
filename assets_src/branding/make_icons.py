"""Downsizes icon_1024.png (Blender image scale) and packs icon.ico with stdlib only.
Run: blender -b -P make_icons.py
"""
import bpy, struct, os

D = "C:/Users/berk/car race/.claude/worktrees/wf_ae85d2d9-ad8-2/game/assets/branding"
SRC = D + "/icon_1024.png"


def scaled(size, out):
    img = bpy.data.images.load(SRC)
    img.scale(size, size)  # bilinear; fine for these sizes
    img.file_format = "PNG"
    img.filepath_raw = out
    s = bpy.context.scene
    s.render.image_settings.color_mode = "RGB"
    img.save()
    bpy.data.images.remove(img)


for n in (512, 192):
    scaled(n, "%s/icon_%d.png" % (D, n))
ico_sizes = (16, 24, 32, 48, 64, 128, 256)
for n in ico_sizes:
    scaled(n, "%s/_ico_%d.png" % (D, n))

blobs = [open("%s/_ico_%d.png" % (D, n), "rb").read() for n in ico_sizes]
head = struct.pack("<HHH", 0, 1, len(ico_sizes))
off = 6 + 16 * len(ico_sizes)
ents = b""
for n, b in zip(ico_sizes, blobs):
    w = 0 if n >= 256 else n
    ents += struct.pack("<BBBBHHII", w, w, 0, 0, 1, 32, len(b), off)
    off += len(b)
open(D + "/icon.ico", "wb").write(head + ents + b"".join(blobs))
for n in ico_sizes:
    os.remove("%s/_ico_%d.png" % (D, n))
print("ICONS DONE")
