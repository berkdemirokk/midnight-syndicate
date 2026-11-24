extends "res://devtools/capture_scenario.gd"
## Results screen with six fictional drivers; the player is second.

const SCENE: String = "res://ui/menus/results_screen.tscn"
const MockRace = preload("res://devtools/scenarios/ui_mock_race.gd")
const SETTLE_FRAMES: int = 30
const COUNT_FRAMES: int = 90
const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const PHONE_W: int = 2556
const PHONE_H: int = 1179
const PLAYER_POS: int = 2
const BASE_TIME_S: float = 241.6
const GAP_STEP_S: float = 3.214
const BEST_BASE_S: float = 79.42
const BEST_STEP_S: float = 0.612
const CASH: int = 1800
const REP: int = 120
const NAMES: PackedStringArray = ["Vance Reyes", "Kato Mori", "Ilse Brandt", "Rafa Ortiz", "Nina Kowal", "Sol Vidal"]


func run() -> void:
	cap.set_size(DESKTOP_W, DESKTOP_H)
	var mock_race = MockRace
	tree.root.add_child(mock_race.make_backdrop())
	var screen: ResultsScreen = await cap.load_scene(SCENE) as ResultsScreen
	var results: Array[Dictionary] = []
	for i: int in NAMES.size():
		results.append({
			"name": NAMES[i], "position": i + 1,
			"total_time": BASE_TIME_S + float(i) * GAP_STEP_S,
			"best_lap": BEST_BASE_S + float(i) * BEST_STEP_S,
			"is_player": i + 1 == PLAYER_POS})
	screen.show_results(results, {"cash": CASH, "rep": REP})
	await cap.wait_frames(COUNT_FRAMES)
	await cap.shot("desktop_%dx%d" % [DESKTOP_W, DESKTOP_H])
	cap.set_size(PHONE_W, PHONE_H)
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot("iphone_%dx%d" % [PHONE_W, PHONE_H])
