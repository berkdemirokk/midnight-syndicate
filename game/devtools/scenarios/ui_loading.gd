extends "res://devtools/capture_scenario.gd"
## STREET EMPIRE loading card (the card Router shows inside its scene-change fade) at desktop and iPhone size.

const CARD: String = "res://ui/menus/loading_card.gd"


func _show() -> Control:
	var root := Control.new()
	root.theme = MSTheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(root)
	root.add_child((load(CARD) as Script).new() as Control)
	return root


func run() -> void:
	cap.set_size(1920, 1080)
	var a: Control = _show()
	await cap.wait_frames(20)
	await cap.shot("desktop_1920x1080")
	a.queue_free()
	MSTheme.set_phone(true)
	cap.set_size(2556, 1179)
	var b: Control = _show()
	await cap.wait_frames(20)
	await cap.shot("iphone_2556x1179")
	b.queue_free()
	MSTheme.set_phone(false)
