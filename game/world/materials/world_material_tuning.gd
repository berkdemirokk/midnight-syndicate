class_name WorldMaterialTuning
extends Resource
## Every number the city material library uses. MaterialLibrary.tuning holds one instance.

## 0 = dry, 1 = soaking. Darkens and smooths every textured surface (walls, paving, kerbs, ground).
@export_range(0.0, 1.0) var wetness: float = 0.35
## Metres per texture repeat for CC0 sets that carry no uv_tile_m of their own.
@export_range(0.5, 20.0) var texture_tile_m: float = 4.0
## Asphalt tile size and the wet-road parameters passed to shaders/wet_asphalt.gdshader.
@export_range(0.5, 20.0) var asphalt_tile_m: float = 4.0
@export_range(0.0, 1.0) var asphalt_puddle_level: float = 0.6
@export_range(0.0, 1.0) var asphalt_rain: float = 0.2
## Multiplies every JSON emission energy for neon, lamp and bulb materials (glow strength).
@export_range(0.0, 4.0) var neon_energy_scale: float = 1.0
## Multiplies window and shop-interior emission (lit windows glow).
@export_range(0.0, 4.0) var window_energy_scale: float = 0.6
## Atlas values below this do not glow. The window atlas is pale blue and orange across most facade cells.
@export_range(0.0, 0.99) var window_glow_threshold: float = 0.6
## How much of the atlas colour survives in window glow (0 grey, 1 raw colour).
@export_range(0.0, 1.0) var window_glow_saturation: float = 0.5
## Faint self-glow on road paint so markings stay readable under headlights at night.
@export_range(0.0, 1.0) var road_paint_glow: float = 0.18
## Shop glass translucency over the emissive interior cards.
@export_range(0.0, 1.0) var glass_alpha: float = 0.35
## Building LOD switch distances (metres). Godot does not import LOD ranges, so apply() sets them on LOD0/1/2.
@export var lod0_end_m: float = 110.0
@export var lod1_end_m: float = 260.0
## Water normal scroll in UV units per second.
@export var water_scroll: Vector2 = Vector2(0.012, 0.007)
