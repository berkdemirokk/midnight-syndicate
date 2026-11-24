class_name RaceConfig
extends Resource
## Race setup read by race_scene.gd. Tunables for a race live here, not in code.
## The player always takes the last grid slot (slot = opponent_count). Driver names are fictional.

@export var track_scene: String = "res://world/city_01/city_01.tscn"  ## missing file = development circuit
@export var car_scene: String = "res://vehicles/noctra_sable/noctra_sable.tscn"  ## missing file = dev mule
@export var car_spec_path: String = "res://vehicles/specs/noctra_sable.tres"
@export_range(1, 10) var laps: int = 3
@export_range(0, 7) var opponent_count: int = 5  ## the grid has 8 slots, the player takes the last one
@export var opponent_skills: PackedFloat32Array = PackedFloat32Array([0.93, 0.91, 0.89, 0.87, 0.85, 0.83, 0.81])
@export var opponent_names: PackedStringArray = PackedStringArray(["Kade Vorne", "Mira Halloway", "Dex Ormond", "Ilse Crane", "Tomas Vey", "Runa Sable", "Pell Adair"])
@export var opponent_paints: PackedColorArray = PackedColorArray([Color(0.7, 0.13, 0.16), Color(0.85, 0.87, 0.9), Color(0.18, 0.44, 0.25), Color(0.88, 0.65, 0.15), Color(0.35, 0.17, 0.53), Color(0.12, 0.44, 0.7), Color(0.5, 0.5, 0.52)])
@export var player_name: String = "Nova Rike"
@export var player_paint: Color = Color(0.09, 0.13, 0.24)
@export var autopilot: bool = false  ## the player car is driven by an AIDriver (tests and captures)
@export_range(0.8, 1.0) var autopilot_skill: float = 0.97
@export var event_id: String = "dev_circuit"  ## key for GameState.record_result


## Opponent paint by index, cycling through the list. Falls back to the player colour when no list is set.
func opponent_paint(index: int) -> Color:
	if opponent_paints.is_empty():
		return player_paint
	return opponent_paints[index % opponent_paints.size()]


func opponent_skill(index: int) -> float:
	if opponent_skills.is_empty():
		return 0.9
	return opponent_skills[index % opponent_skills.size()]
