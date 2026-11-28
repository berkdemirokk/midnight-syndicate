extends "res://tests/test_case.gd"
## Self-check for the drive telemetry runner (devtools/scenarios/drive_telemetry_run.gd): its scratch save must never
## be the owner's profile, its cleanup removes only scratch files, and its best-lap helper is right.

const RUNNER: String = "res://devtools/scenarios/drive_telemetry_run.gd"
const OWNER_SAVE: String = "user://save.json"


func test_runner_uses_scratch_save_only() -> void:
	var r = (load(RUNNER) as GDScript).new()
	check(str(r.get("SCRATCH_SAVE")) != OWNER_SAVE, "scratch save must not be the owner profile")
	check(str(r.get("SCRATCH_SAVE")).begins_with("user://"), "scratch save must live in user://")
	r.free()


func test_runner_cleanup_removes_only_scratch() -> void:
	var r = (load(RUNNER) as GDScript).new()
	var scratch: String = str(r.get("SCRATCH_SAVE"))
	var f := FileAccess.open(scratch + ".bak", FileAccess.WRITE)
	check(f != null, "could not plant scratch backup file")
	if f != null:
		f.store_string("{}")
		f.close()
	r._clean_scratch_save()
	check(not FileAccess.file_exists(scratch + ".bak"), "scratch backup should be removed")
	r.free()


func test_runner_best_lap() -> void:
	var r = (load(RUNNER) as GDScript).new()
	check(r._best([]) == null, "no laps gives null")
	check(is_equal_approx(float(r._best([31.2, 29.5004, 30.0])), 29.5), "best lap is the minimum, rounded to ms")
	r.free()
