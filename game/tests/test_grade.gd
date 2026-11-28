extends "res://tests/test_case.gd"
## Per-track grade (world/time_of_day/track_grade.gd): track keys, a complete table with no ambient multiplier above 1.1,
## an absolute and repeatable environment grade (no stacking across races), and no change for an ungraded track.

const CITY_TRACK: String = "res://world/city_01/city_01.tscn"
const MASLAK_TRACK: String = "res://world/istanbul_maslak/istanbul_maslak.tscn"
const BOGAZ_TRACK: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const MULT_MAX: float = 1.2001  ## 1.2 as a float32 colour channel: no ambient multiplier above it
const KEYS: PackedStringArray = ["exposure", "contrast", "saturation", "ambient", "fog", "fog_mix"]


func test_track_keys() -> void:
	check(TrackGrade.key_for(CITY_TRACK) == "city", "city_01 is graded as city")
	check(TrackGrade.key_for(MASLAK_TRACK) == "maslak", "istanbul_maslak is graded as maslak")
	check(TrackGrade.key_for(BOGAZ_TRACK) == "bogaz", "istanbul_bogaz is graded as bogaz")
	check(TrackGrade.key_for("res://devtools/dev_track.tscn") == "", "an unknown track is not graded")
	check(TrackGrade.key_for("") == "", "no track is not graded")


func test_table_complete_and_safe() -> void:
	for k: String in TrackGrade.TRACK_KEYS.values():
		for tod: String in TimeOfDay.IDS:
			var v: Dictionary = TrackGrade.values(k, tod)
			check(not v.is_empty(), "%s/%s has a grade" % [k, tod])
			for key: String in KEYS:
				check(v.has(key), "%s/%s has %s" % [k, tod, key])
			if v.is_empty():
				continue
			var a: Color = v["ambient"]
			check(maxf(a.r, maxf(a.g, a.b)) <= MULT_MAX, "%s/%s ambient %s stays under %s" % [k, tod, str(a), MULT_MAX])
			check(float(v["exposure"]) <= 1.0 and float(v["exposure"]) > 0.0, "%s/%s exposure is not raised" % [k, tod])
	check(TrackGrade.values("city", "noon").is_empty(), "an unknown hour has no grade")


func test_environment_grade_is_absolute() -> void:
	var env := Environment.new()
	env.tonemap_exposure = 1.2
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0
	env.ambient_light_color = Color(0.5, 0.5, 0.5)
	var v: Dictionary = TrackGrade.values("maslak", "night")
	TrackGrade.apply(env, v)
	var once: float = env.adjustment_saturation
	TrackGrade.apply(env, v)
	check(absf(env.adjustment_saturation - once) < 0.0001, "a second grade does not stack (%s, %s)" % [str(once), str(env.adjustment_saturation)])
	check(absf(env.adjustment_saturation - float(v["saturation"])) < 0.0001, "saturation is the table value")
	check(absf(env.tonemap_exposure - 1.2) < 0.0001, "exposure keeps the environment base")
	var amb: Color = v["ambient"]
	check(absf(env.ambient_light_color.b - 0.5 * amb.b) < 0.0001, "ambient is the base times the table tint, not stacked")
	check(env.adjustment_enabled, "adjustments are on")


func test_ungraded_track_untouched() -> void:
	var root := Node3D.new()
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.adjustment_enabled = false
	root.add_child(we)
	add(root)
	TrackGrade.apply_to_world(root, "res://devtools/dev_track.tscn", "day")
	check(not we.environment.adjustment_enabled, "an ungraded track leaves the environment alone")
	TrackGrade.apply_to_world(root, BOGAZ_TRACK, "sunset")
	check(we.environment.adjustment_enabled, "a graded track changes the environment")
	await cleanup([root])
