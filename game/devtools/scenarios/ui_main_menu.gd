extends "res://devtools/capture_scenario.gd"
## STREET EMPIRE main screen at desktop and iPhone-landscape sizes, English and Turkish, plus a dragged orbit and the
## profile card. The showroom camera intro takes 2.4 s, so shots wait for it.

const SCENE: String = "res://ui/menus/main_menu.tscn"
const SETTLE_S: float = 3.2
const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const PHONE_W: int = 2556
const PHONE_H: int = 1179


func run() -> void:
	var lang: String = Settings.language
	Settings.language = "en"
	cap.set_size(DESKTOP_W, DESKTOP_H)
	var menu: Node = await cap.load_scene(SCENE)
	await cap.wait_seconds(SETTLE_S)
	await cap.shot("desktop_%dx%d" % [DESKTOP_W, DESKTOP_H])
	var stage: Node = menu.get("stage")
	if stage != null:
		for i: int in 20:
			stage.call("orbit_drag", Vector2(-22.0, 1.5))
			await cap.wait_frames(1)
		await cap.wait_seconds(0.6)
		await cap.shot("desktop_orbit")
	menu.call("open_profile")
	await cap.wait_frames(4)
	await cap.shot("desktop_profile")
	Settings.language = "tr"
	menu = await cap.load_scene(SCENE)
	await cap.wait_seconds(SETTLE_S)
	await cap.shot("desktop_%dx%d_tr" % [DESKTOP_W, DESKTOP_H])
	Settings.language = "en"
	MSTheme.set_phone(true)  # the phone layout (type x1.5, 44 pt targets) is chosen at build time: rebuild the scene
	cap.set_size(PHONE_W, PHONE_H)
	await cap.load_scene(SCENE)
	await cap.wait_seconds(SETTLE_S)
	await cap.shot("iphone_%dx%d" % [PHONE_W, PHONE_H])
	MSTheme.set_phone(false)
	Settings.language = lang
