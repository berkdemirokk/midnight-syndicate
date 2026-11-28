extends "res://tests/test_case.gd"
## Progression survives a restart, in-process: one GameState writes, a fresh one reads the same file.
## A torn, missing or stale main file falls back to the backup. The cross-process proof is tools/restart_check.py.
## Every test uses its own user:// file, never the real save.

const GS: GDScript = preload("res://core/game_state.gd")
const CAR: String = "noctra_vela"
const EVENT: String = "ortakoy_night"
const TIME_TRIAL: String = "midnight_time_trial"


func _path(tag: String) -> String:
	return "user://test_persist_%s.json" % tag


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


func _snapshot(gs: Node) -> Dictionary:
	return {
		"cash": gs.get_cash(),
		"rep": gs.get_rep(),
		"owned": (gs.profile["owned_cars"] as Array).duplicate(),
		"selected": gs.get_selected_car(),
		"setups": (gs.profile["car_setups"] as Dictionary).duplicate(true),
		"career": (gs.profile["career"] as Dictionary).duplicate(true),
		"stats": (gs.profile["stats"] as Dictionary).duplicate(),
	}


## Parsed JSON object at path, or {} when missing or not an object.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func test_full_career_survives_restart() -> void:
	var path := _path("career")
	_wipe(path)
	var gs: Node = _open(path)
	gs.add_cash(50000)
	check(gs.buy_car(CAR, CarCatalog.price(CAR)), "buy the car at its catalogue price")
	check(gs.set_paint(CAR, Color.from_string("#1e5aa0", Color.BLACK)), "paint is set")
	check(gs.set_rim(CAR, Color.from_string("#d4af37", Color.BLACK)), "rim is set")
	check(gs.upgrade(CAR, "engine") and gs.upgrade(CAR, "engine"), "two engine upgrades")
	gs.record_result(EVENT, 61.0, 2)
	gs.record_result(EVENT, 58.0, 1)
	gs.record_result(TIME_TRIAL, 80.0, 1)
	check(gs.select_car(CAR), "new car is selected")
	var before: Dictionary = _snapshot(gs)
	_close(gs)

	var again: Node = _open(path)
	check(_snapshot(again) == before, "every progression field matches after restart")
	# 5000 start + 50000 grant - 8000 car - 800 - 1600 upgrades + 900 (2nd) + 1500 (1st) + 720 (time trial, 2 stars)
	check(again.get_cash() == 47720, "cash is 47720 after restart, got %d" % again.get_cash())
	check(again.has_car(CAR) and again.has_car(CarCatalog.STARTER), "both owned cars survive")
	check(again.get_selected_car() == CAR, "selected car survives")
	check(again.get_setup(CAR)["paint_color"] == "1e5aa0", "paint survives, got %s" % again.get_setup(CAR)["paint_color"])
	check(again.get_setup(CAR)["rim_color"] == "d4af37", "rim survives, got %s" % again.get_setup(CAR)["rim_color"])
	check(again.get_upgrade_level(CAR, "engine") == 2, "engine level 2 survives")
	check(again.event_stars(EVENT) == 3, "event stars survive, got %d" % again.event_stars(EVENT))
	check(is_equal_approx(again.best_time(EVENT), 58.0), "best time survives, got %f" % again.best_time(EVENT))
	check(again.event_stars(TIME_TRIAL) == 2, "time trial stars survive, got %d" % again.event_stars(TIME_TRIAL))
	check(again.total_stars() == 5, "total stars is 5, got %d" % again.total_stars())
	var stats: Dictionary = again.profile["stats"]
	check(stats["races"] == 3 and stats["wins"] == 1, "stats races 3 wins 1, got %s" % str(stats))
	check(stats["cash_earned"] == 3120, "cash_earned is 3120, got %d" % stats["cash_earned"])
	metric("cash_after_restart", again.get_cash())
	metric("total_stars", again.total_stars())
	_close(again)
	_wipe(path)


func test_second_restart_keeps_new_progress() -> void:
	var path := _path("second")
	_wipe(path)
	var gs: Node = _open(path)
	gs.add_rep(3)
	_close(gs)
	var mid: Node = _open(path)
	check(mid.get_rep() == 3, "rep 3 after first restart")
	mid.add_cash(100)
	mid.record_result(EVENT, 70.0, 3)
	var expected: Dictionary = _snapshot(mid)
	_close(mid)
	var last: Node = _open(path)
	check(_snapshot(last) == expected, "progress from the second session survives the third open")
	_close(last)
	_wipe(path)


func test_torn_main_recovers_previous_save() -> void:
	var path := _path("torn")
	_wipe(path)
	var gs: Node = _open(path)
	gs.add_rep(5)
	var previous: Dictionary = _snapshot(gs)
	gs.add_rep(3)
	_close(gs)
	check(FileAccess.file_exists(path + ".bak"), "backup holds the save before the last one")

	# A crash mid-write leaves a cut-off main file.
	var text: String = FileAccess.get_file_as_string(path)
	_write_text(path, text.substr(0, text.length() / 2))
	var recovered: Node = _open(path)
	check(_snapshot(recovered) == previous, "torn main restores the previous save")
	check(recovered.get_rep() == 5, "rep 5 from backup, got %d" % recovered.get_rep())
	_close(recovered)
	_wipe(path)


func test_missing_main_recovers_backup() -> void:
	var path := _path("missing")
	_wipe(path)
	var gs: Node = _open(path)
	gs.add_rep(4)
	gs.add_rep(2)
	_close(gs)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var recovered: Node = _open(path)
	check(recovered.get_rep() == 4, "missing main restores backup (rep 4), got %d" % recovered.get_rep())
	_close(recovered)
	_wipe(path)


func test_stale_staging_file_is_ignored() -> void:
	var path := _path("stale_tmp")
	_wipe(path)
	var gs: Node = _open(path)
	gs.add_rep(6)
	_close(gs)
	# Leftover from an earlier crash: valid JSON with different numbers must never be loaded.
	_write_text(path + ".tmp", JSON.stringify({"version": 2, "cash": 1, "rep": 999}))
	var loaded: Node = _open(path)
	check(loaded.get_rep() == 6, "leftover .tmp ignored, rep 6 loaded, got %d" % loaded.get_rep())
	loaded.add_rep(1)
	_close(loaded)
	var again: Node = _open(path)
	check(again.get_rep() == 7, "next save replaces the leftover .tmp, got %d" % again.get_rep())
	_close(again)
	_wipe(path)


func test_recovered_profile_keeps_backup_clean() -> void:
	var path := _path("recover_save")
	_wipe(path)
	var gs: Node = _open(path)
	gs.add_rep(5)
	gs.add_rep(3)
	_close(gs)
	_write_text(path, "{{ cut off")
	var recovered: Node = _open(path)
	check(recovered.get_rep() == 5, "recovered from backup, got %d" % recovered.get_rep())
	recovered.add_rep(2)
	_close(recovered)
	var main: Dictionary = _read_json(path)
	var bak: Dictionary = _read_json(path + ".bak")
	check(int(main.get("rep", -1)) == 7, "main holds the recovered save plus the new rep, got %s" % str(main.get("rep")))
	check(int(bak.get("rep", -1)) == 5, "backup still holds the last good save (5), got %s" % str(bak.get("rep")))
	_wipe(path)
