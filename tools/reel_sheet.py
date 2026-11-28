"""Turn a gameplay_reel.gd frame folder into a contact sheet (JPG) and an MP4 (ffmpeg, if installed).

Usage: py -3.10 tools/reel_sheet.py <frames_dir> <out_prefix> [--cols 4] [--every 1] [--no-mp4]
Writes <out_prefix>_sheet.jpg (frames in order, labelled with the time in s and the speed from reel_meta.json)
and <out_prefix>.mp4 (at the reel's fps) when ffmpeg is found on PATH or via the FFMPEG_EXE env var.
No download is made: a missing ffmpeg only skips the MP4.
"""
import glob
import json
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw

THUMB_W, THUMB_H = 480, 270


def find_ffmpeg() -> str:
    # PATH first; FFMPEG_EXE env var overrides for a non-PATH install. No download is made.
    return os.environ.get("FFMPEG_EXE") or shutil.which("ffmpeg") or ""


def main() -> int:
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        return 2
    frames_dir, prefix = args[0], args[1]
    cols = int(args[args.index("--cols") + 1]) if "--cols" in args else 4
    every = int(args[args.index("--every") + 1]) if "--every" in args else 1
    files = sorted(glob.glob(os.path.join(frames_dir, "frame_*.jpg")))
    if not files:
        print("no frames in", frames_dir)
        return 1
    meta_path = os.path.join(frames_dir, "reel_meta.json")
    rows = json.load(open(meta_path, encoding="utf-8"))["rows"] if os.path.exists(meta_path) else []
    fps = json.load(open(meta_path, encoding="utf-8")).get("fps", 8.0) if os.path.exists(meta_path) else 8.0
    picked = list(range(0, len(files), every))
    rows_n = (len(picked) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (THUMB_W + 6), rows_n * (THUMB_H + 22)), (12, 12, 16))
    d = ImageDraw.Draw(sheet)
    for k, i in enumerate(picked):
        im = Image.open(files[i]).convert("RGB").resize((THUMB_W, THUMB_H), Image.LANCZOS)
        x, y = (k % cols) * (THUMB_W + 6), (k // cols) * (THUMB_H + 22)
        sheet.paste(im, (x, y + 20))
        label = "frame %d" % i
        if i < len(rows):
            label = "t=%.2fs  %.0f km/h" % (rows[i][0], rows[i][1])
        d.text((x + 6, y + 4), label, fill=(230, 230, 230))
    sheet.save(prefix + "_sheet.jpg", quality=85)
    print("sheet:", prefix + "_sheet.jpg", "frames:", len(picked))
    ff = find_ffmpeg()
    if "--no-mp4" in args:
        return 0
    if not ff:
        print("ffmpeg not found: MP4 skipped")
        return 0
    pattern = os.path.join(frames_dir, "frame_%04d.jpg")
    cmd = [ff, "-y", "-loglevel", "error", "-framerate", str(fps), "-i", pattern,
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23", prefix + ".mp4"]
    subprocess.run(cmd, check=True)
    print("mp4:", prefix + ".mp4")
    return 0


if __name__ == "__main__":
    sys.exit(main())
