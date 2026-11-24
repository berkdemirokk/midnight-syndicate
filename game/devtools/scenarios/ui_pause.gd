extends "res://devtools/capture_scenario.gd"
## Pause overlay over the race backdrop.

const SCENE: String = "res://ui/menus/pause_menu.tscn"
const MockRace = preload("res://devtools/scenarios/ui_mock_race.gd")
const SETTLE_FRAMES: int = 30
const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const PHONE_W: int = 2556
const PHONE_H: int = 1179


func run() -> void:
	cap.set_size(DESKTOP_W, DESKTOP_H)
	var mock_race = MockRace
	tree.root.add_child(mock_race.make_backdrop())
	var pause: PauseMenu = await cap.load_scene(SCENE) as PauseMenu
	pause.pause()
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot("desktop_%dx%d" % [DESKTOP_W, DESKTOP_H])
	cap.set_size(PHONE_W, PHONE_H)
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot("iphone_%dx%d" % [PHONE_W, PHONE_H])
	pause.resume()
