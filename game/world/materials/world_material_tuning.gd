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
@export_range(0.0, 4.0) var window_energy_scale: float = 0.8
## Atlas values below this do not glow. The window atlas is pale blue and orange across most facade cells.
@export_range(0.0, 0.99) var window_glow_threshold: float = 0.6
## How much of the atlas colour survives in window glow (0 grey, 1 raw colour).
@export_range(0.0, 1.0) var window_glow_saturation: float = 0.15
## Faint self-glow on road paint. Keep near zero: at 0.18 under the blue ambient the markings read
## as bright blue plastic, brighter than anything lit around them.
@export_range(0.0, 1.0) var road_paint_glow: float = 0.05
## Worn wet paint is grey-white, not white.
@export_range(0.0, 1.0) var road_paint_albedo: float = 0.42
@export_range(0.0, 1.0) var road_paint_roughness: float = 0.35
## Window panes are glass: dark, glossy, slightly metallic so probes and lamps reflect in them.
## (At albedo x2.2 the pane atlas lit up as lavender plaster blocks on the towers.)
@export_range(0.0, 4.0) var pane_albedo_scale: float = 0.22
@export_range(0.0, 1.0) var pane_roughness: float = 0.12
@export_range(0.0, 1.0) var pane_metallic: float = 0.55
## Window cells for the glow on panes (metres, width x storey height) and the share of lit-capable
## cells that are on. Splits floor-wide tower panes into separate lit windows.
@export var pane_cell_size_m: Vector2 = Vector2(2.4, 3.6)
@export_range(0.0, 1.0) var pane_lit_fraction: float = 0.45
## Shop interiors are the brightest windows at street level.
@export_range(0.0, 4.0) var shop_energy_scale: float = 0.9
## Far-building impostor albedo (walls and windows baked together).
@export_range(0.0, 4.0) var impostor_albedo_scale: float = 0.8
## Shop glass translucency over the emissive interior cards.
@export_range(0.0, 1.0) var glass_alpha: float = 0.35
## Building LOD switch distances (metres). Godot does not import LOD ranges, so apply() sets them on LOD0/1/2.
@export var lod0_end_m: float = 110.0
@export var lod1_end_m: float = 260.0
## Water normal scroll in UV units per second.
@export var water_scroll: Vector2 = Vector2(0.012, 0.007)
## Multiplies the window and shop atlas albedo tint. The JSON base colour (#202838) is near black, so unlit
## facades read as black slabs under the night ambient. Raised so walls read as dark blue-grey.
@export_range(1.0, 4.0) var facade_albedo_scale: float = 3.0
## Colour of the window glow (sodium-warm). Cool and magenta come from the neon signs, not the windows.
@export var window_glow_tint: Color = Color(1.0, 0.78, 0.5)
## Multiplies the energy of ceiling strips and tunnel lights (JSON energy 5 blew out to white bands).
@export_range(0.0, 1.0) var ceiling_energy_scale: float = 0.06

## Underpass ceiling fixture: HDR energy of the lit dashes, dash length and period along the tunnel (m),
## and the tunnel direction the dashes run along. Energy 3 blooms without going flat white.
@export_range(0.0, 16.0) var tunnel_light_energy: float = 0.4
@export var tunnel_run_dir: Vector3 = Vector3(-0.985, 0.0, 0.17)
@export_range(0.1, 10.0) var tunnel_light_lit_m: float = 1.2
@export_range(0.2, 20.0) var tunnel_light_period_m: float = 1.8
## Underpass wall stripe: painted, lit by the tunnel lights, not emissive.
@export var tunnel_stripe_colour: Color = Color("#B8901E")
@export_range(0.0, 1.0) var tunnel_stripe_roughness: float = 0.5
## Kerb: lighter wet concrete so the road edge catches lamp light. Sidewalk: a little lighter than asphalt.
@export_range(0.5, 3.0) var kerb_albedo_scale: float = 1.8
@export_range(0.5, 3.0) var sidewalk_albedo_scale: float = 1.2
## Far skyline card (M_Skyline): its emissive texture is a whole night skyline at 1.6, which blew out to white across the bay.
@export_range(0.0, 2.0) var skyline_emission_scale: float = 0.35
## M_Skyline now runs through window_atlas.gdshader: dark card, lit windows above the threshold.
@export var skyline_tint: Color = Color(0.42, 0.45, 0.55)
@export_range(0.0, 8.0) var skyline_window_energy: float = 2.2
## Roof bitumen albedo multiplier: near-black roofs under the night ambient read as holes in the skyline.
@export_range(1.0, 4.0) var roof_albedo_scale: float = 3.0
## Multiplies the concrete wall albedo (M_Concrete_Wall, the textured facade walls). Dark brick walls read as
## black slabs from 60 m; raised so the walls read as buildings under the night ambient.
@export_range(1.0, 4.0) var wall_albedo_scale: float = 2.2
