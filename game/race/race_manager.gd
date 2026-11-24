class_name RaceManager
extends Node
## CONTRACT STUB written by the lead. The Racing AI / Race Agent implements the body.
## Public names, types and signals below must not change (HUD and menus depend on them).

signal countdown_tick(seconds_left: int)  ## 3, 2, 1, then 0 = GO
signal race_started
signal lap_completed(car: ArcadeCar, lap: int, lap_time: float)
signal position_changed(car: ArcadeCar, position: int)  ## 1-based
signal race_finished(results: Array[Dictionary])  ## sorted; keys: car, name, position, total_time, best_lap, is_player

enum State { GRID, COUNTDOWN, RACING, FINISHED }

@export var total_laps: int = 3
@export var countdown_seconds: int = 3

var state: State = State.GRID
var race_time: float = 0.0
var player_car: ArcadeCar


## Register cars before start_countdown(). The track node follows the Track contract.
func setup(track: Node3D, cars: Array[ArcadeCar], player: ArcadeCar, driver_names: PackedStringArray) -> void:
	pass


func start_countdown() -> void:
	pass


func get_position(car: ArcadeCar) -> int:
	return 1


func get_lap(car: ArcadeCar) -> int:  ## 1-based current lap, clamped to total_laps
	return 1


func get_current_lap_time(car: ArcadeCar) -> float:
	return 0.0


func get_best_lap_time(car: ArcadeCar) -> float:  ## 0.0 when no lap finished
	return 0.0


func get_car_count() -> int:
	return 0


## 0..1 progress of a car around the current lap, for the minimap and gap display.
func get_lap_progress(car: ArcadeCar) -> float:
	return 0.0
