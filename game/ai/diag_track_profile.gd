extends SceneTree
## Diagnostic (not a test): prints curvature and target speed of the test circuit (tests/helpers/test_track.gd)
## every 10 m over a range of track progress. Options: --from=<m> --to=<m> (default 100 to 300).
## godot --headless --fixed-fps 60 --path game -s res://ai/diag_track_profile.gd -- --from=150 --to=260

const TestTrack = preload("res://tests/helpers/test_track.gd")


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	var from_m: float = 100.0
	var to_m: float = 300.0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--from="):
			from_m = float(a.trim_prefix("--from="))
		if a.begins_with("--to="):
			to_m = float(a.trim_prefix("--to="))
	var track: Track = TestTrack.build()
	root.add_child(track)
	var s: float = from_m
	while s <= to_m:
		print("PROFILE s=%.0f curv=%.5f target_kmh=%.1f" % [s, track.get_curvature(s), track.get_target_speed(s) * 3.6])
		s += 10.0
	quit(0)
