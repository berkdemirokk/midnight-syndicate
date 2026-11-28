extends "res://devtools/capture_scenario.gd"
## Settings screen at desktop (1920x1080) and iPhone (2532x1170) sizes, every tab. The first shot of each size is
## the GRAPHICS tab under the plain name, so it lines up with the earlier single-page capture in before/after sheets.

const SCENE: String = "res://ui/menus/settings_menu.tscn"
const SETTLE_FRAMES: int = 30
const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const PHONE_W: int = 2532
const PHONE_H: int = 1170
const TAB_SUFFIX: Array[String] = ["", "_controls", "_audio", "_language", "_about"]


func run() -> void:
	await _capture_all("desktop_%dx%d" % [DESKTOP_W, DESKTOP_H], DESKTOP_W, DESKTOP_H)
	MSTheme.set_phone(true)  # the phone layout (type x1.5, 44 pt targets) is chosen at build time: rebuild the scene
	await _capture_all("iphone_%dx%d" % [PHONE_W, PHONE_H], PHONE_W, PHONE_H)
	MSTheme.set_phone(false)


func _capture_all(prefix: String, w: int, h: int) -> void:
	for i: int in TAB_SUFFIX.size():
		cap.set_size(w, h)
		var menu: Node = await cap.load_scene(SCENE)
		menu.call("show_tab", i)
		await cap.wait_frames(SETTLE_FRAMES)
		await cap.shot(prefix + TAB_SUFFIX[i])
