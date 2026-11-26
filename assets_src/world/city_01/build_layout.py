"""City 01 layout entry point. The generator is generic now: assets_src/world/tracks/build_layout.py + configs/city_01.json.

Run: py -3.10 build_layout.py
"""
import os
import runpy
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_TRACKS = os.path.join(_HERE, "..", "tracks")
if "--config" not in sys.argv:
    sys.argv += ["--config", os.path.join(_TRACKS, "configs", "city_01.json")]
runpy.run_path(os.path.join(_TRACKS, "build_layout.py"), run_name="__main__")
