extends "res://tests/test_case.gd"
## GameState: save/load round trip, backup recovery, validation, spending, upgrades, migration, results.
## Every test uses its own user:// file, never the real save.

const GS: GDScript = preload("res://core/game_state.gd")


func _path(tag: String) -> String:
	return "user://test_game_state_%s.json" % tag


func _wipe(path: String) -> void:
	for p: String in [path, path + ".bak", path + ".tmp", path + ".bak.tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _write_text(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _open(path: String) -> Node:
	var gs: Node = GS.new()
	gs.open_profile(path)
	return gs


func _close(gs: Node) -> void:
	gs.free()


func test_round_trip() -> void:
	var path := _path("round")
	_wipe(path)
	var gs: Node = _open(path)
	gs.add_cash(250)
	gs.add_rep(40)
	gs.own_car("kestrel_v8")
	gs.set_paint("kestrel_v8", Color(0.8, 0.1, 0.2))
	gs.upgrade(CarCatalog.STARTER, "engine")
	gs.select_car("kestrel_v8")
	var cash: int = gs.get_cash()
	_close(gs)

	var again: Node = _open(path)
	check(again.get_cash() == cash, "cash survives reload")
	check(again.get_rep() == 40, "rep survives reload")
	check(again.has_car("kestrel_v8"), "owned car survives reload")
	check(again.get_selected_car() == "kestrel_v8", "selected car survives reload")
	check(again.get_upgrade_level(CarCatalog.STARTER, "engine") == 1, "upgrade level survives reload")
	check(again.get_setup("kestrel_v8")["paint_color"] == Color(0.8, 0.1, 0.2).to_html(false), "paint survives reload")
	metric("cash_after_round_trip", cash)
	_close(again)
	_wipe(path)


func test_corrupt_main_restores_backup() -> void:
	var path := _path("bak")
	_wipe(path)
	var gs: Node = _open(path)
	gs.add_rep(1)
	gs.spend_cash(1000)
	_close(gs)
	check(FileAccess.file_exists(path + ".bak"), "backup written on second save")

	_write_text(path, "{{ broken json")
	var restored: Node = _open(path)
	check(restored.get_cash() == 5000, "cash from backup (5000), got %d" % restored.get_cash())
	check(restored.get_rep() == 1, "rep from backup, got %d" % restored.get_rep())
	_close(restored)
	_wipe(path)


func test_both_corrupt_gives_defaults() -> void:
	var path := _path("both")
	_wipe(path)
	var gs: Node = _open(path)
	gs.add_rep(7)
	gs.spend_cash(10)
	_close(gs)
	_write_text(path, "not json at all")
	_write_text(path + ".bak", "[1, 2, 3]")

	var fresh: Node = _open(path)
	check(fresh.get_cash() == 5000, "defaults: starter cash")
	check(fresh.get_rep() == 0, "defaults: rep 0")
	check(fresh.has_car(CarCatalog.STARTER), "defaults: starter car owned")
	check(fresh.get_selected_car() == CarCatalog.STARTER, "defaults: starter car selected")
	_close(fresh)
	_wipe(path)


func test_bad_types_are_sanitised() -> void:
	var path := _path("types")
	_wipe(path)
	_write_text(path, JSON.stringify({
		"version": 1,
		"cash": "lots",
		"rep": -50,
		"owned_cars": 5,
		"selected_car": "missing",
		"car_setups": "x",
		"career": {"ev": {"best_time": "fast", "stars": 99}},
		"stats": {"races": "many"},
	}))
	var gs: Node = _open(path)
	check(gs.get_cash() == 5000, "non-number cash falls back to starter")
	check(gs.get_rep() == 0, "negative rep clamps to 0")
	check(gs.has_car(CarCatalog.STARTER), "empty garage gets the starter car")
	check(gs.get_selected_car() == CarCatalog.STARTER, "selected car falls back to an owned car")
	check(gs.get_setup(CarCatalog.STARTER)["upgrades"]["engine"] == 0, "missing setup gets defaults")
	var career: Dictionary = gs.profile["career"]
	check(career["ev"]["best_time"] == 0.0, "bad best_time becomes 0")
	check(career["ev"]["stars"] == 3, "stars clamp to 3")
	_close(gs)
	_wipe(path)


func test_spend_more_than_cash_fails() -> void:
	var path := _path("spend")
	_wipe(path)
	var gs: Node = _open(path)
	var before: int = gs.get_cash()
	check(not gs.spend_cash(before + 1), "spend above cash returns false")
	check(gs.get_cash() == before, "failed spend changes nothing")
	check(gs.spend_cash(before), "spend exactly the cash succeeds")
	check(gs.get_cash() == 0, "cash is zero after spending all")
	check(not gs.spend_cash(-5), "negative spend rejected")
	_close(gs)
	_wipe(path)


func test_upgrade_costs_and_max_level() -> void:
	var path := _path("upgrade")
	_wipe(path)
	var gs: Node = _open(path)
	gs.add_cash(100000)
	var base: int = gs.get_cash()
	var spent: int = 0
	for level: int in 5:
		var cost: int = gs.upgrade_cost("engine", level)
		check(cost == 800 * (level + 1), "engine level %d costs %d" % [level, cost])
		check(gs.upgrade(CarCatalog.STARTER, "engine"), "upgrade to level %d succeeds" % (level + 1))
		spent += cost
	check(gs.get_upgrade_level(CarCatalog.STARTER, "engine") == 5, "engine reaches max level 5")
	check(gs.get_cash() == base - spent, "cash drops by the sum of costs")
	check(not gs.upgrade(CarCatalog.STARTER, "engine"), "upgrade above max level fails")
	check(gs.get_cash() == base - spent, "failed max-level upgrade costs nothing")
	check(not gs.upgrade("kestrel_v8", "engine"), "upgrade on unowned car fails")
	check(not gs.upgrade(CarCatalog.STARTER, "turbo"), "unknown part fails")
	metric("engine_max_total_cost", spent)
	_close(gs)
	_wipe(path)


func test_migration_from_version_0() -> void:
	var path := _path("v0")
	_wipe(path)
	_write_text(path, JSON.stringify({"cash": 1234, "cars": ["noctra_sable", "rival_gt"], "selected_car": "rival_gt"}))
	var gs: Node = _open(path)
	check(gs.get_cash() == 1234, "v0 cash kept")
	check(gs.has_car("rival_gt"), "v0 'cars' renamed to owned_cars")
	check(gs.get_selected_car() == "rival_gt", "v0 selected car kept")
	check(gs.profile["version"] == 2, "migrated to the current version")
	check(gs.has_car(CarCatalog.STARTER), "old save gets the new starter car")
	check(not gs.profile.has("cars"), "old 'cars' key removed")
	_close(gs)


func test_migration_moves_old_starter_to_new() -> void:
	var path := _path("v1_sable")
	_wipe(path)
	_write_text(path, JSON.stringify({"version": 1, "cash": 500, "owned_cars": ["noctra_sable"], "selected_car": "noctra_sable"}))
	var gs: Node = _open(path)
	check(gs.has_car("noctra_sable"), "old starter stays owned")
	check(gs.get_selected_car() == CarCatalog.STARTER, "a save in the old starter moves to the new one")
	check(gs.get_cash() == 500, "cash kept")
	_close(gs)
	_wipe(path)


func test_record_result_keeps_best_time() -> void:
	var path := _path("result")
	_wipe(path)
	var gs: Node = _open(path)
	var r1: Dictionary = gs.record_result("ev_harbor", 42.5, 2)
	check(r1["cash"] == 4704, "2nd place pays 4704")
	check(r1["new_best"] == true, "first run is a new best")
	check(r1["stars"] == 2, "2nd place earns 2 stars")

	var r2: Dictionary = gs.record_result("ev_harbor", 50.0, 1)
	check(r2["new_best"] == false, "slower run is not a new best")
	check(r2["stars"] == 3, "1st place earns 3 stars")

	var r3: Dictionary = gs.record_result("ev_harbor", 40.0, 5)
	check(r3["new_best"] == true, "faster run is a new best")
	check(r3["cash"] == 0, "5th place is past the reward table and pays nothing")
	check(r3["stars"] == 0, "5th place earns no stars")
	var rec: Dictionary = gs.profile["career"]["ev_harbor"]
	check(is_equal_approx(rec["best_time"], 40.0), "best time is the fastest run, got %f" % rec["best_time"])
	check(rec["best_position"] == 1, "best position is the best finish")
	check(rec["stars"] == 3, "stars keep the best value")
	check(gs.record_result("", 10.0, 1).is_empty(), "empty event id rejected")
	check(gs.record_result("ev_harbor", 0.0, 1).is_empty(), "zero time rejected")
	check(gs.record_result("ev_harbor", NAN, 1).is_empty(), "NaN time rejected")
	check(gs.record_result("ev_harbor", INF, 1).is_empty(), "infinite time rejected")
	check(gs.record_result("ev_harbor", 10.0, 0).is_empty(), "position 0 rejected")
	check(is_equal_approx(gs.profile["career"]["ev_harbor"]["best_time"], 40.0), "rejected results change nothing")
	metric("best_time_harbor", rec["best_time"])

	_close(gs)
	var again: Node = _open(path)
	var saved: Dictionary = again.profile["career"]["ev_harbor"]
	check(is_equal_approx(saved["best_time"], 40.0), "best time survives reload")
	_close(again)
	_wipe(path)


## A blocked backup path skips the backup but still commits the verified new save.
func test_blocked_backup_preserves_primary() -> void:
	var path := _path("blocked_backup")
	var blocked: String = ProjectSettings.globalize_path(path + ".bak")
	if DirAccess.dir_exists_absolute(blocked):
		DirAccess.remove_absolute(blocked)
	_wipe(path)
	var gs: Node = _open(path)
	gs.add_rep(7)
	var original: String = FileAccess.get_file_as_string(path)
	check(DirAccess.make_dir_absolute(blocked) == OK, "backup obstruction created")
	gs.profile["rep"] = 99
	check(gs.save_profile(), "save succeeds when the backup path is blocked")
	check(FileAccess.get_file_as_string(path) != original, "primary holds the new save")
	check(not FileAccess.file_exists(path + ".tmp"), "save moves its staging file into place")
	check(DirAccess.dir_exists_absolute(blocked), "backup obstruction is not deleted")
	_close(gs)
	var restored: Node = _open(path)
	check(restored.get_rep() == 99, "new save is readable after reload")
	_close(restored)
	DirAccess.remove_absolute(blocked)
	_wipe(path)


## Failure staging the next backup must retain BOTH previously valid copies.
func test_blocked_backup_stage_preserves_both_copies() -> void:
	var path := _path("blocked_backup_stage")
	var blocked: String = ProjectSettings.globalize_path(path + ".bak.tmp")
	if DirAccess.dir_exists_absolute(blocked):
		DirAccess.remove_absolute(blocked)
	_wipe(path)
	var gs: Node = _open(path)
	gs.add_rep(7)
	gs.add_rep(2)
	var original: String = FileAccess.get_file_as_string(path)
	var backup: String = FileAccess.get_file_as_string(path + ".bak")
	check(not original.is_empty() and not backup.is_empty(), "both valid copies exist")
	check(DirAccess.make_dir_absolute(blocked) == OK, "backup staging obstruction created")
	gs.profile["rep"] = 99
	check(gs.save_profile(), "save succeeds when backup staging is blocked")
	check(FileAccess.get_file_as_string(path) != original, "primary holds the new save")
	check(FileAccess.get_file_as_string(path + ".bak") == backup, "previous backup unchanged")
	_close(gs)
	DirAccess.remove_absolute(blocked)
	_wipe(path)
