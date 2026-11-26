extends "res://devtools/capture_scenario.gd"
## Career event select at desktop and iPhone-landscape sizes, on a throwaway profile with two events done.

const SCENE: String = "res://ui/menus/event_select.tscn"
const PROFILE: String = "user://capture_event_select.json"
const SETTLE_FRAMES: int = 40
const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const PHONE_W: int = 2556
const PHONE_H: int = 1179


func run() -> void:
	GameState.open_profile(PROFILE)
	GameState.reset_profile()
	GameState.record_result("wharf_sprint", 66.4, 1)
	GameState.record_result("neon_strip_circuit", 135.2, 3)
	cap.set_size(DESKTOP_W, DESKTOP_H)
	await cap.load_scene(SCENE)
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot("desktop_%dx%d" % [DESKTOP_W, DESKTOP_H])
	MSTheme.set_phone(true)  # the phone layout (type x1.5, 44 pt targets) is chosen at build time: rebuild the scene
	cap.set_size(PHONE_W, PHONE_H)
	await cap.load_scene(SCENE)
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot("iphone_%dx%d" % [PHONE_W, PHONE_H])
	for p: String in [PROFILE, PROFILE + ".bak", PROFILE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	MSTheme.set_phone(false)
