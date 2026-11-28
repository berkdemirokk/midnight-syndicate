extends "res://tests/test_case.gd"
## Polish regressions: touch labels in both languages, garage touch targets, minimap hides eliminated rivals,
## and the cash reward table used by the results screen.

const MiniMapScript: GDScript = preload("res://ui/hud/minimap.gd")
const TouchScript: GDScript = preload("res://vehicles/touch/touch_controls.gd")


func test_touch_labels_follow_language() -> void:
	var old: String = Settings.language
	var touch: Node = TouchScript.new()
	Settings.language = "tr"
	check(touch._label(TouchScript.Zone.BRAKE) == "FREN", "brake label is Turkish")
	check(touch._label(TouchScript.Zone.NITRO) == "NİTRO", "nitro label is Turkish")
	check(touch._label(TouchScript.Zone.DRIFT) == "DRİFT", "drift label is Turkish")
	Settings.language = "en"
	check(touch._label(TouchScript.Zone.BRAKE) == "BRAKE", "brake label is English")
	check(touch._label(TouchScript.Zone.STEER_LEFT) == "<", "steer arrows stay glyphs")
	Settings.language = old
	touch.free()


func test_garage_touch_targets_at_least_88px() -> void:
	check(GarageHud.TOUCH_H >= 88.0, "garage BUY and carousel buttons are at least 88 px tall")


func test_minimap_hides_eliminated_rival() -> void:
	var mm: RefCounted = MiniMapScript.new()
	mm.set_dot_count(2)
	mm.set_dot(0, 0.2, true)
	mm.set_dot(1, 0.5, false, false)
	check(mm.dot_shown(0), "player dot always shown")
	check(not mm.dot_shown(1), "eliminated rival dot hidden")
	mm.set_dot(1, 0.5, false)
	check(mm.dot_shown(1), "rival dot shown again when still racing")


func test_cash_reward_table() -> void:
	check(GameState.REWARD_CASH == PackedInt32Array([5600, 3360, 1680, 560]), "cash reward table 5600/3360/1680/560 (x1.4 for the 18-car roster)")
