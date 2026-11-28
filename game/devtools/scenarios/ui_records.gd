extends "res://devtools/capture_scenario.gd"
## Personal records screen at desktop and iPhone-landscape sizes, Turkish and English, on a throwaway profile
## with a few finished events (race, drift, elimination) and two cars.

const SCENE: String = "res://ui/menus/records_screen.tscn"
const PROFILE: String = "user://capture_records.json"
const SETTLE_FRAMES: int = 40
const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const PHONE_W: int = 2532
const PHONE_H: int = 1170


func run() -> void:
	GameState.open_profile(PROFILE)
	GameState.reset_profile()
	GameState.record_result("ortakoy_night", 61.24, 1)
	GameState.record_result("wharf_sprint", 66.4, 1)
	GameState.own_car("noctra_sable")
	GameState.select_car("noctra_sable")
	GameState.record_result("drift_harbour", 60.0, 1, 1250.0)
	GameState.record_result("elim_wharf", 150.0, 2)
	for lang: String in ["tr", "en"]:
		Settings.set_language(lang)
		for phone: bool in [false, true]:
			MSTheme.set_phone(phone)
			var w: int = PHONE_W if phone else DESKTOP_W
			var h: int = PHONE_H if phone else DESKTOP_H
			cap.set_size(w, h)
			await cap.load_scene(SCENE)
			await cap.wait_frames(SETTLE_FRAMES)
			var tag: String = "iphone_%dx%d" % [w, h] if phone else "desktop_%dx%d" % [w, h]
			await cap.shot("%s_%s" % [tag, lang])
	MSTheme.set_phone(false)
	for p: String in [PROFILE, PROFILE + ".bak", PROFILE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
