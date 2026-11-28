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
	check(slow["cash"] == 2822 and slow["rep"] == 36 and slow["stars"] == 1, "slow trial gets third-tier reward")
	check(medium["cash"] == 5645 and medium["rep"] == 72 and medium["stars"] == 2, "two-star trial gets second-tier reward")
	check(fast["cash"] == 9408 and fast["rep"] == 120 and fast["stars"] == 3, "three-star trial gets top reward")
	check(gs.profile["stats"]["wins"] == 1, "only top-tier time counts as a win")
	check(gs.event_stars("midnight_time_trial") == 3, "best stars preserved")
	var normal: Dictionary = gs.record_result("wharf_sprint", 70.0, 2)
	check(normal["cash"] == 4704 and normal["rep"] == 60, "position event economy unchanged")
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


## The whole career (every event at 1st or the top star tier) pays between 1.5 and 2 times the cost of all cars and
## full upgrades, so owning everything takes 1.5 to 2 full career runs. tools/economy_sim.py reports the same ratio.
func test_career_cost_ratio_is_in_band() -> void:
	var gs: Node = _fresh()
	var three_star := 0.0
	for ev: Dictionary in EventCatalog.EVENTS:
		three_star += float(ev.get("mult", 1.0)) * gs.REWARD_CASH[0]
	var cost := 0.0
	for car: Dictionary in CarCatalog.DEFAULT_CARS:
		cost += float(car["price"])
		for part: String in gs.UPGRADE_PARTS:
			for lvl: int in gs.MAX_UPGRADE_LEVEL:
				cost += float(gs.upgrade_cost(part, lvl))
	var ratio: float = cost / three_star
	check(ratio >= 1.5 and ratio <= 2.0, "cost of all cars and upgrades is 1.5-2.0 career runs, got %.2f" % ratio)
	gs.free()
	_wipe()


func test_cash_table_falls_with_place() -> void:
	var gs: Node = _fresh()
	var t: PackedInt32Array = gs.REWARD_CASH
	check(t.size() == 4 and t[0] > t[1] and t[1] > t[2] and t[2] > t[3] and t[3] > 0, "cash table falls with place")
	gs.free()
	_wipe()
