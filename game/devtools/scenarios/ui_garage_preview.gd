extends "res://devtools/capture_scenario.gd"
## Garage upgrade preview: the stat bars show the gain of the BUY row under the cursor (violet ghost) for engine and
## nitro, at 1920x1080 and iPhone-landscape 2532x1170, English. Temporary save, the player's profile is never written.

const GARAGE: String = "res://ui/garage/garage.tscn"
const TEMP_SAVE: String = "user://capture_garage_preview_save.json"
const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const PHONE_W: int = 2532
const PHONE_H: int = 1170
const SETTLE_FRAMES: int = 40
const TRANSITION_S: float = 1.3  ## preset transitions take 0.9 s
const PREVIEW_PARTS: PackedStringArray = ["engine", "nitro"]


func run() -> void:
	var old_path: String = GameState.save_path
	var old_profile: Dictionary = GameState.profile.duplicate(true)
	GameState.open_profile(TEMP_SAVE)
	GameState.reset_profile()
	Settings.set_language("en")
	var sizes: Array[Vector2i] = [Vector2i(DESKTOP_W, DESKTOP_H), Vector2i(PHONE_W, PHONE_H)]
	for s: Vector2i in sizes:
		cap.set_size(s.x, s.y)
		var g: Variant = await cap.load_scene(GARAGE)
		await cap.wait_seconds(TRANSITION_S)
		g.get_hud().set_active_page("upgrades")
		await cap.wait_frames(SETTLE_FRAMES)
		for part: String in PREVIEW_PARTS:
			g.get_hud().get_buy_button(part).mouse_entered.emit()
			await cap.wait_frames(SETTLE_FRAMES)
			g.orbit.touch()
			await cap.shot("preview_%s_%dx%d" % [part, s.x, s.y])
	GameState.save_path = old_path
	GameState.profile = old_profile
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEMP_SAVE + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE + suffix))
