extends "res://devtools/capture_scenario.gd"
## Career screen at desktop and iPhone-landscape sizes, on a throwaway profile with two events done.
## Shots: desktop opens on the first open event (Ortakoy), then the Arden Bay and Police tabs, Turkish Arden Bay;
## iPhone Arden Bay and Police.

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
	var screen: EventSelect = await _open(false) as EventSelect
	await cap.shot("desktop_%dx%d" % [DESKTOP_W, DESKTOP_H])
	screen.select_district(EventSelect.D_ARDEN)
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot("desktop_arden_%dx%d" % [DESKTOP_W, DESKTOP_H])
	screen.select_district(EventSelect.D_POLICE)
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot("desktop_police_%dx%d" % [DESKTOP_W, DESKTOP_H])
	Settings.set_language("tr")
	screen.select_district(EventSelect.D_ARDEN)
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot("desktop_arden_tr_%dx%d" % [DESKTOP_W, DESKTOP_H])
	Settings.set_language("en")
	MSTheme.set_phone(true)  # the phone layout (type x1.5, 44 pt targets) is chosen at build time: rebuild the scene
	cap.set_size(PHONE_W, PHONE_H)
	screen = await _open(true) as EventSelect
	await cap.shot("iphone_%dx%d" % [PHONE_W, PHONE_H])
	screen.select_district(EventSelect.D_ARDEN)
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot("iphone_arden_%dx%d" % [PHONE_W, PHONE_H])
	screen.select_district(EventSelect.D_POLICE)
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot("iphone_police_%dx%d" % [PHONE_W, PHONE_H])
	for p: String in [PROFILE, PROFILE + ".bak", PROFILE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	MSTheme.set_phone(false)


func _open(_phone: bool) -> Node:
	var node: Node = await cap.load_scene(SCENE)
	await cap.wait_frames(SETTLE_FRAMES)
	return node
