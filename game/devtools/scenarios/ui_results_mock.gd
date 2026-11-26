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
const PROFILE: String = "user://capture_results_mock.json"
const NAMES: PackedStringArray = ["Vance Reyes", "Kato Mori", "Ilse Brandt", "Rafa Ortiz", "Nina Kowal", "Sol Vidal"]


func run() -> void:
	cap.set_size(DESKTOP_W, DESKTOP_H)
	var mock_race = MockRace
	tree.root.add_child(mock_race.make_backdrop())
	GameState.open_profile(PROFILE)
	await _show()
	await cap.wait_frames(COUNT_FRAMES)
	await cap.shot("desktop_%dx%d" % [DESKTOP_W, DESKTOP_H])
	MSTheme.set_phone(true)
	cap.set_size(PHONE_W, PHONE_H)
	await _show()
	await cap.wait_frames(COUNT_FRAMES)
	await cap.shot("iphone_%dx%d" % [PHONE_W, PHONE_H])
	MSTheme.set_phone(false)


## Builds the screen with six drivers (the player second) on a throwaway career profile: event 1 just finished 2nd.
func _show() -> void:
	var screen: ResultsScreen = await cap.load_scene(SCENE) as ResultsScreen
	var results: Array[Dictionary] = []
	for i: int in NAMES.size():
		results.append({
			"name": NAMES[i], "position": i + 1,
			"total_time": BASE_TIME_S + float(i) * GAP_STEP_S,
			"best_lap": BEST_BASE_S + float(i) * BEST_STEP_S,
			"is_player": i + 1 == PLAYER_POS})
	GameState.reset_profile()
	var rewards: Dictionary = GameState.record_result("wharf_sprint", BASE_TIME_S, PLAYER_POS)
	screen.set_event_id("wharf_sprint")
	screen.show_results(results, rewards)
