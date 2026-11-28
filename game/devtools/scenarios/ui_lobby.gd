extends "res://devtools/capture_scenario.gd"
## Online (LAN, experimental) lobby overlay at 1920x1080, Turkish and English: the host view with the join code line
## (server on 127.0.0.1, closed after the shot), and the join view with the Code field after Join was pressed empty.
## No network beyond loopback.

const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const SETTLE_FRAMES: int = 40


func run() -> void:
	cap.set_size(DESKTOP_W, DESKTOP_H)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.06, 0.09)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(backdrop)
	for lang: String in ["tr", "en"]:
		Settings.set_language(lang)
		var host: Control = _lobby()
		await cap.wait_frames(SETTLE_FRAMES)
		host._on_host()
		await cap.wait_frames(SETTLE_FRAMES)
		await cap.shot("host_%s" % lang)
		host._session.close()
		host.queue_free()
		await tree.process_frame
		var join: Control = _lobby()
		await cap.wait_frames(SETTLE_FRAMES)
		join._on_join()
		await cap.wait_frames(SETTLE_FRAMES)
		await cap.shot("join_%s" % lang)
		join.queue_free()
		await tree.process_frame
	Settings.set_language("en")
	backdrop.queue_free()


func _lobby() -> Control:
	var lobby := NetLobbyMenu.new()
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(lobby)
	return lobby
