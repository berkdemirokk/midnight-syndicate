"""City 01 road entry point. The generator is generic now: assets_src/world/tracks/build_road.py + configs/city_01.json.

Run: blender --background --factory-startup --python build_road.py -- [--render]
"""
import os
import runpy
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_TRACKS = os.path.join(_HERE, "..", "tracks")
if "--config" not in sys.argv:
    sys.argv += ["--config", os.path.join(_TRACKS, "configs", "city_01.json")]
runpy.run_path(os.path.join(_TRACKS, "build_road.py"), run_name="__main__")
