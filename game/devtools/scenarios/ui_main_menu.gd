extends "res://devtools/capture_scenario.gd"
## Main menu at desktop and iPhone-landscape sizes.

const SCENE: String = "res://ui/menus/main_menu.tscn"
const SETTLE_FRAMES: int = 40
const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const PHONE_W: int = 2556
const PHONE_H: int = 1179


func run() -> void:
	cap.set_size(DESKTOP_W, DESKTOP_H)
	await cap.load_scene(SCENE)
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot("desktop_%dx%d" % [DESKTOP_W, DESKTOP_H])
	cap.set_size(PHONE_W, PHONE_H)
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot("iphone_%dx%d" % [PHONE_W, PHONE_H])
