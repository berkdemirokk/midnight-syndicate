extends "res://devtools/capture_scenario.gd"
## Police pursuit run select (opened from the main menu) at desktop and iPhone-landscape sizes.

const SCENE: String = "res://race/pursuit/pursuit_select.tscn"


func run() -> void:
	cap.set_size(1920, 1080)
	await cap.load_scene(SCENE)
	await cap.wait_frames(30)
	await cap.shot("desktop_1920x1080")
	MSTheme.set_phone(true)
	cap.set_size(2556, 1179)
	await cap.load_scene(SCENE)
	await cap.wait_frames(30)
	await cap.shot("iphone_2556x1179")
	MSTheme.set_phone(false)
