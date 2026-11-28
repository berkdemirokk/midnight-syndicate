extends "res://devtools/capture_scenario.gd"
## Results screen with a five-digit cash reward (12400, a stacked multiplier payout) at desktop and iPhone-landscape
## sizes, English and Turkish. Uses the results mock drivers, not the save file.

const Mock = preload("res://devtools/scenarios/ui_results_mock.gd")
const SCENE: String = "res://ui/menus/results_screen.tscn"
const MockRace = preload("res://devtools/scenarios/ui_mock_race.gd")
const SETTLE_FRAMES: int = 30
const COUNT_FRAMES: int = 90
const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const PHONE_W: int = 2556
const PHONE_H: int = 1179
const CASH_REWARD: int = 12400
const REP_REWARD: int = 60
const PROFILE: String = "user://capture_results_cash.json"


func run() -> void:
	var backdrop: CanvasLayer = MockRace.make_backdrop()
	tree.root.add_child(backdrop)
	GameState.open_profile(PROFILE)
	GameState.reset_profile()
	for lang: String in ["en", "tr"]:
		Settings.set_language(lang)
		for phone: bool in [false, true]:
			MSTheme.set_phone(phone)
			cap.set_size(PHONE_W if phone else DESKTOP_W, PHONE_H if phone else DESKTOP_H)
			var screen: ResultsScreen = await cap.load_scene(SCENE) as ResultsScreen
			screen.set_event_id("wharf_sprint")
			screen.show_results(_results(), {"cash": CASH_REWARD, "rep": REP_REWARD, "stars": 2, "new_best": true})
			await cap.wait_frames(COUNT_FRAMES)
			var tag: String = "iphone_%dx%d" % [PHONE_W, PHONE_H] if phone else "desktop_%dx%d" % [DESKTOP_W, DESKTOP_H]
			await cap.shot("cash5_%s_%s" % [tag, lang])
	MSTheme.set_phone(false)
	Settings.set_language("en")
	for p: String in [PROFILE, PROFILE + ".bak", PROFILE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _results() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for i: int in Mock.NAMES.size():
		results.append({
			"name": Mock.NAMES[i], "position": i + 1,
			"total_time": Mock.BASE_TIME_S + float(i) * Mock.GAP_STEP_S,
			"best_lap": Mock.BEST_BASE_S + float(i) * Mock.BEST_STEP_S,
			"paint": Mock.PAINTS[i],
			"is_player": i + 1 == Mock.PLAYER_POS})
	return results
