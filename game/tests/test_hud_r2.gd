extends "res://tests/test_case.gd"
## HUD pass: live lap delta and its sign, delta text format, and the segmented nitro ring fill maths.

const EPS: float = 0.0001


func test_lap_delta_sign_and_progress() -> void:
	# 60 s best lap: at half the lap the best lap is at 30 s. 28 s elapsed is 2 s ahead (negative).
	check(is_equal_approx(RaceHUD.lap_delta(28.0, 60.0, 0.5), -2.0), "ahead of the best lap is negative")
	check(is_equal_approx(RaceHUD.lap_delta(33.0, 60.0, 0.5), 3.0), "behind the best lap is positive")
	check(is_equal_approx(RaceHUD.lap_delta(0.0, 60.0, 0.0), 0.0), "lap start is level with the best")
	check(is_equal_approx(RaceHUD.lap_delta(70.0, 60.0, 1.7), 10.0), "progress above 1 is clamped to the lap end")
	check(is_equal_approx(RaceHUD.lap_delta(5.0, 60.0, -0.2), 5.0), "negative progress is clamped to zero")


func test_fmt_delta_signed_two_decimals() -> void:
	check(RaceHUD.fmt_delta(0.42) == "+0.42", "fmt_delta(0.42) is +0.42")
	check(RaceHUD.fmt_delta(-0.18) == "-0.18", "fmt_delta(-0.18) is -0.18")
	check(RaceHUD.fmt_delta(0.0) == "+0.00", "fmt_delta(0) is +0.00")
	check(RaceHUD.fmt_delta(-12.345) == "-12.35", "fmt_delta rounds to two decimals")


func test_nitro_segment_fills_in_order() -> void:
	var f: PackedFloat32Array = NitroBar.segment_fills(0.6, 10)
	check(f.size() == 10, "ten segments")
	for s: int in 6:
		check(absf(f[s] - 1.0) < EPS, "segment %d full at 60 percent tank" % s)
	check(absf(f[6]) < EPS and absf(f[9]) < EPS, "segments above 60 percent are empty")
	var p: PackedFloat32Array = NitroBar.segment_fills(0.25, 10)
	check(absf(p[0] - 1.0) < EPS and absf(p[1] - 1.0) < EPS, "two full segments at 25 percent")
	check(absf(p[2] - 0.5) < EPS, "third segment half filled at 25 percent")
	check(absf(NitroBar.segment_fills(0.0, 10)[0]) < EPS, "empty tank fills nothing")
	check(absf(NitroBar.segment_fills(1.0, 10)[9] - 1.0) < EPS, "full tank fills the last segment")
	check(absf(NitroBar.segment_fills(3.0, 10)[9] - 1.0) < EPS, "over-full input is clamped")
