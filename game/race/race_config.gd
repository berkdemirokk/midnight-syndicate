class_name RaceConfig
extends Resource
## Race setup read by race_scene.gd. Tunables for a race live here, not in code.
## The player always takes the last grid slot (slot = opponent_count). Driver names are fictional.

@export var track_scene: String = "res://world/city_01/city_01.tscn"  ## missing file = development circuit
@export var car_scene: String = "res://vehicles/noctra_tayfun/noctra_tayfun.tscn"  ## missing file = dev mule
@export var car_spec_path: String = "res://vehicles/specs/noctra_tayfun.tres"
@export_range(1, 10) var laps: int = 3
@export_range(0, 7) var opponent_count: int = 5  ## the grid has 8 slots, the player takes the last one
@export var opponent_skills: PackedFloat32Array = PackedFloat32Array([0.93, 0.91, 0.89, 0.87, 0.85, 0.83, 0.81])
@export var opponent_names: PackedStringArray = PackedStringArray(["Kade Vorne", "Mira Halloway", "Dex Ormond", "Ilse Crane", "Tomas Vey", "Runa Sable", "Pell Adair"])
## Saturated mid-value paints that read under the night car fill light. All distinct; the player keeps candy red.
@export var opponent_paints: PackedColorArray = PackedColorArray([Color("#1F5BFF"), Color("#FF6A13"), Color("#7BE000"), Color("#E8ECF2"), Color("#8A3BFF"), Color("#F2C200"), Color("#12B5A5")])
@export var player_name: String = "Nova Rike"
@export var player_paint: Color = Color("#8E0F1E")  ## candy red (car brief); used when the profile has no saved paint
## true: the player car wears the paint saved in the garage (GameState), false: always player_paint.
@export var use_garage_paint: bool = true
@export var autopilot: bool = false  ## the player car is driven by an AIDriver (tests and captures)
@export_range(0.8, 1.0) var autopilot_skill: float = 0.97
@export var time_of_day: String = "night"  ## "day", "sunset" or "night" (TimeOfDay presets); unknown values race at night
@export var event_id: String = "dev_circuit"  ## key for GameState.record_result
@export_range(0.1, 1.0, 0.01) var reflection_fraction_high: float = 0.4  ## wet road mirror size, High preset
@export_range(20.0, 400.0, 1.0) var reflection_max_distance_m: float = 60.0 ## mirror far clip, High preset (100 m put the replay orbit at 470k primitives)
@export_range(5.0, 60.0, 0.5) var rival_lod1_start_m: float = 6.0 ## rival cars drop from LOD0 to LOD1 here (18 m put 513k primitives in the replay orbit) (the player keeps CarLod's default)
@export_range(10.0, 120.0, 0.5) var rival_lod2_start_m: float = 35.0 ## rivals drop to LOD2 here (CarLod default 70): 28k -> 7k triangles each
## Low preset only: rivals switch earlier (LOD1 is 14 draws per car, LOD2 8), the Low budget is 250 draws.
@export_range(3.0, 60.0, 0.5) var rival_lod1_start_low_m: float = 6.0
@export_range(5.0, 120.0, 0.5) var rival_lod2_start_low_m: float = 16.0
@export_range(0.1, 1.0, 0.01) var reflection_fraction_medium: float = 0.2  ## unused: Medium has no mirror since 2026-11-24 (draw-call budget); kept for a future Medium+ preset
@export_range(0.0, 4.0, 0.01) var car_fill_energy: float = 1.0 ## fill light on the car layer only, see RaceScene.CAR_FILL_LAYER
@export var car_fill_color: Color = Color(0.82, 0.9, 1.0)
@export_range(1.0, 60.0, 0.5) var car_fill_range_m: float = 25.0
## Warm rim from behind the car toward the camera, car layer only: edges of the body catch it, so the paint colour
## still reads when the violet sky and the cool fill dominate the reflections.
@export_range(0.0, 4.0, 0.01) var car_rim_energy: float = 0.5
@export var car_rim_color: Color = Color(1.0, 0.86, 0.78)
@export_range(0.0, 80.0, 1.0) var car_rim_elevation_deg: float = 28.0
@export var traffic_enabled: bool = false  ## ambient civilian traffic (TrafficSystem); career events switch it on
@export var rival_mix: bool = false  ## rivals drive a mix of the available car models (CarCatalog), else the player's model
@export var rival_class: String = ""  ## with rival_mix: only rival models of this catalog class ("street", ...); empty = every rival model
@export var force_nitro_above_kmh: float = -1.0  ## capture only: autopilot nitro gate opens above this speed; 0 or less = off
@export var net_hold_grid: bool = false  ## online race (net/): the grid waits for the server start message; no AI opponents are spawned


## Opponent paint by index, cycling through the list. Falls back to the player colour when no list is set.
func opponent_paint(index: int) -> Color:
	if opponent_paints.is_empty():
		return player_paint
	return opponent_paints[index % opponent_paints.size()]


func opponent_skill(index: int) -> float:
	if opponent_skills.is_empty():
		return 0.9
	return opponent_skills[index % opponent_skills.size()]
