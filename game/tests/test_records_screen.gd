extends "res://tests/test_case.gd"
## Personal records: best time, best drift score, stars and the car of the best result, kept across reloads.
## Temporary profiles only. The records screen gets the profile through its store field.

const GS: GDScript = preload("res://core/game_state.gd")
const DRIFT: String = "drift_harbour"
const RACE: String = "ortakoy_night"
const CAR_A: String = "noctra_sable"


func _path(tag: String) -> String:
	return "user://test_records_%s.json" % tag


func _wipe(path: String) -> void:
	for p: String in [path, path + ".bak", path + ".tmp", path + ".bak.tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _open(path: String) -> Node:
	var gs: Node = GS.new()
	gs.open_profile(path)
	return gs


func test_best_score_and_car_are_kept() -> void:
	var path := _path("keep")
	_wipe(path)
	var gs: Node = _open(path)
	gs.own_car(CAR_A)
	gs.select_car(CAR_A)
	gs.record_result(DRIFT, 60.0, 1, 1250.0)
	check(gs.career_record(DRIFT)["best_score"] == 1250.0, "the drift score is recorded")
	check(gs.career_record(DRIFT)["car"] == CAR_A, "the car of the best score is recorded")
	gs.select_car(CarCatalog.STARTER)
	gs.record_result(DRIFT, 60.0, 1, 900.0)
	var rec: Dictionary = gs.career_record(DRIFT)
	check(rec["best_score"] == 1250.0 and rec["car"] == CAR_A, "a lower score changes neither the best nor the car")
	gs.record_result(RACE, 61.2, 1)
	gs.record_result(RACE, 70.0, 2)
	check(is_equal_approx(float(gs.career_record(RACE)["best_time"]), 61.2), "race keeps the best time")
	check(gs.career_record(RACE)["car"] == CarCatalog.STARTER, "race records the car that drove it")
	check(gs.career_record("never_raced").is_empty(), "an event never finished has no record")
	gs.free()
	var again: Node = _open(path)
	check(again.career_record(DRIFT)["best_score"] == 1250.0, "the drift score survives a reload")
	check(again.career_record(DRIFT)["car"] == CAR_A, "the car survives a reload")
	again.free()
	_wipe(path)


func test_old_career_records_load_with_new_fields() -> void:
	var path := _path("old")
	_wipe(path)
	_write_text_file(path, JSON.stringify({"version": 2, "career": {RACE: {"best_time": 61.0, "best_position": 1, "stars": 2}}}))
	var gs: Node = _open(path)
	var rec: Dictionary = gs.career_record(RACE)
	check(is_equal_approx(float(rec["best_time"]), 61.0) and rec["stars"] == 2, "the old record keeps its values")
	check(rec["best_score"] == 0.0 and rec["car"] == "", "the new fields default to empty")
	gs.free()
	_wipe(path)


func test_records_screen_rows_and_values() -> void:
	var path := _path("screen")
	_wipe(path)
	var gs: Node = _open(path)
	gs.record_result(RACE, 61.24, 1)
	gs.record_result(DRIFT, 60.0, 1, 1250.0)
	var screen := RecordsScreen.new()
	screen.store = gs
	add(screen)
	await frames(2)
	check(screen.row_count() == EventCatalog.count(), "one row per career event")
	check(RecordsScreen.best_text(RACE, gs.career_record(RACE)) == RaceHUD.fmt_time(61.24), "race row shows the best time")
	check(RecordsScreen.best_text(DRIFT, gs.career_record(DRIFT)).find("1250") >= 0, "drift row shows the best score")
	check(RecordsScreen.best_text("wharf_sprint", {}) == I18n.t("records.none"), "an unplayed event shows the empty value")
	await cleanup([screen as Node])
	gs.free()
	_wipe(path)


func test_records_screen_empty_profile_has_note() -> void:
	var path := _path("empty")
	_wipe(path)
	var gs: Node = _open(path)
	var screen := RecordsScreen.new()
	screen.store = gs
	add(screen)
	await frames(2)
	check(screen.row_count() == EventCatalog.count() + 1, "an empty profile adds the no-race note")
	await cleanup([screen as Node])
	gs.free()
	_wipe(path)


func _write_text_file(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
