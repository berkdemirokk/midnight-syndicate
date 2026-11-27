#!/usr/bin/env python3
"""Retired on 2026-11-27. It copied the project-made Kestrel GT GLBs from assets_src over
game/assets/vehicles/kestrel_gtr/ and registered them as project-owned. That folder holds a licensed CC BY 4.0 model
now (docs/design/CAR_INTEGRATION.md, last sections): running the old steps would put the old model back under the
licensed car's path and erase its licence record. The old Blender sources stay in assets_src/vehicles/ (not shipped).

Rebuild the cars of the game with: py -3.10 assets_src/pipeline/rebuild_vehicles.py [car_id ...]
"""
import sys

sys.exit(__doc__)
