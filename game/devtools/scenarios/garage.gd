extends "res://devtools/capture_scenario.gd"
## Garage captures: overview, front, rear34, paint_tab (blue paint applied), upgrades_tab, closeup_wheel at 1920x1080,
## and overview at phone landscape 2556x1179. Runs on a temporary save, so the player's profile is never written.

const GARAGE: String = "res://ui/garage/garage.tscn"
const TEMP_SAVE: String = "user://capture_garage_save.json"
const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const PHONE_W: int = 2556
const PHONE_H: int = 1179
const SETTLE_FRAMES: int = 40
const TRANSITION_S: float = 1.3  ## preset transitions take 0.9 s
const BLUE: Color = Color("0A1A5C")
const CLOSEUP_YAW: float = 0.5
const CLOSEUP_PITCH: float = 4.0
const CLOSEUP_DIST: float = 3.8


func run() -> void:
	var old_path: String = GameState.save_path
	var old_profile: Dictionary = GameState.profile.duplicate(true)
	GameState.open_profile(TEMP_SAVE)
	GameState.reset_profile()
	cap.set_size(DESKTOP_W, DESKTOP_H)
	var g: Variant = await cap.load_scene(GARAGE)
	await cap.wait_frames(SETTLE_FRAMES)
	g.orbit.touch()
	await cap.shot("overview")

	g.go_view("front")
	await cap.wait_seconds(TRANSITION_S)
	g.orbit.touch()
	await cap.shot("front")

	g.go_view("rear34")
	await cap.wait_seconds(TRANSITION_S)
	g.orbit.touch()
	await cap.shot("rear34")

	g.go_view("overview")
	await cap.wait_seconds(TRANSITION_S)
	g.commit_paint(BLUE)
	g.get_hud().set_active_page("paint")
	await cap.wait_frames(SETTLE_FRAMES)
	g.orbit.touch()
	await cap.shot("paint_tab")

	g.get_hud().set_active_page("upgrades")
	await cap.wait_frames(SETTLE_FRAMES)
	g.orbit.touch()
	await cap.shot("upgrades_tab")

	g.get_hud().set_active_page("rims")
	await cap.wait_frames(SETTLE_FRAMES)
	g.orbit.touch()
	await cap.shot("rims_tab")

	g.get_hud().set_active_page("paint")
	g.orbit.set_pose(CLOSEUP_YAW, CLOSEUP_PITCH, CLOSEUP_DIST)
	await cap.wait_frames(SETTLE_FRAMES)
	g.orbit.touch()
	await cap.shot("closeup_wheel")

	cap.set_size(PHONE_W, PHONE_H)
	g.go_view("overview")
	await cap.wait_seconds(TRANSITION_S)
	g.orbit.touch()
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot("overview_%dx%d" % [PHONE_W, PHONE_H])

	GameState.save_path = old_path
	GameState.profile = old_profile
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEMP_SAVE + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE + suffix))
