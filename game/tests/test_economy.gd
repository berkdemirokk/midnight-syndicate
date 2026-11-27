extends "res://tests/test_case.gd"
## Economy regressions, isolated from the real save.
const GS: GDScript = preload("res://core/game_state.gd")
const PATH: String = "user://test_economy_chatgpt.json"

func _fresh() -> Node:
	_wipe()
	var gs: Node = GS.new()
	gs.open_profile(PATH)
	return gs

func _wipe() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + suffix))

func test_time_trial_rewards_follow_stars() -> void:
	var gs: Node = _fresh()
	var slow: Dictionary = gs.record_result("midnight_time_trial", 130.0, 1)
	var medium: Dictionary = gs.record_result("midnight_time_trial", 80.0, 1)
	var fast: Dictionary = gs.record_result("midnight_time_trial", 70.0, 1)
	check(slow["cash"] == 360 and slow["rep"] == 36 and slow["stars"] == 1, "slow trial gets third-tier reward")
	check(medium["cash"] == 720 and medium["rep"] == 72 and medium["stars"] == 2, "two-star trial gets second-tier reward")
	check(fast["cash"] == 1200 and fast["rep"] == 120 and fast["stars"] == 3, "three-star trial gets top reward")
	check(gs.profile["stats"]["wins"] == 1, "only top-tier time counts as a win")
	check(gs.event_stars("midnight_time_trial") == 3, "best stars preserved")
	var normal: Dictionary = gs.record_result("wharf_sprint", 70.0, 2)
	check(normal["cash"] == 600 and normal["rep"] == 60, "position event economy unchanged")
	gs.free()
	_wipe()

func test_economy_caps_before_integer_addition() -> void:
	var gs: Node = _fresh()
	gs.add_cash(9223372036854775807)
	gs.add_rep(9223372036854775807)
	check(gs.get_cash() == gs.MAX_CASH, "large cash reward saturates without integer overflow")
	check(gs.get_rep() == gs.MAX_CASH, "large rep reward saturates without integer overflow")
	gs.profile["stats"] = {"races": gs.MAX_CASH, "wins": gs.MAX_CASH, "cash_earned": gs.MAX_CASH}
	gs.record_result("wharf_sprint", 70.0, 1)
	for key: String in ["races", "wins", "cash_earned"]:
		check(gs.profile["stats"][key] == gs.MAX_CASH, "stat saturates: " + key)
	gs.free()
	_wipe()
