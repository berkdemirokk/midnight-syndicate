extends "res://tests/test_case.gd"
## Per-track grade (world/time_of_day/track_grade.gd): track keys, a complete table with no ambient multiplier above 1.2,
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


## A base is only reused while the environment still holds what the grade wrote. TimeOfDay writing a new hour in between
## must start a new base: the sunset grade is the sunset preset times the table, not stacked on the day grade.
func test_base_follows_timeofday_write() -> void:
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	TimeOfDay.preset("day").apply_environment(env, sun, 40.0)
	TrackGrade.apply(env, TrackGrade.values("bogaz", "day"))
	var sunset: TimeOfDay = TimeOfDay.preset("sunset")
	sunset.apply_environment(env, sun, 40.0)
	var v: Dictionary = TrackGrade.values("bogaz", "sunset")
	TrackGrade.apply(env, v)
	var t: Color = v["ambient"]
	var base: Color = sunset.ambient_color
	var want_amb := Color(clampf(base.r * t.r, 0.0, 1.0), clampf(base.g * t.g, 0.0, 1.0), clampf(base.b * t.b, 0.0, 1.0), base.a)
	check(env.ambient_light_color.is_equal_approx(want_amb), "sunset ambient is the sunset preset times the table (%s vs %s)" % [str(env.ambient_light_color), str(want_amb)])
	var want_fog: Color = sunset.fog_color.lerp(v["fog"], float(v["fog_mix"]))
	check(env.fog_light_color.is_equal_approx(want_fog), "sunset fog is the sunset preset mixed toward the table fog")
	check(absf(env.tonemap_exposure - sunset.exposure * float(v["exposure"])) < 0.0001, "sunset exposure is the preset times the table")
	check(absf(env.adjustment_saturation - sunset.grade_saturation * float(v["saturation"])) < 0.0001, "sunset saturation is the preset times the table")
	sun.free()


## The order RaceScene uses: TimeOfDay writes the hour, then the track grade is applied to the world's environment.
func test_hook_order_matches_race_scene() -> void:
	var root := Node3D.new()
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	root.add_child(we)
	add(root)
	var sun := DirectionalLight3D.new()
	var tod: TimeOfDay = TimeOfDay.preset("day")
	tod.apply_environment(we.environment, sun, 40.0)
	TrackGrade.apply_to_world(root, MASLAK_TRACK, tod.id)
	var v: Dictionary = TrackGrade.values("maslak", "day")
	var t: Color = v["ambient"]
	var base: Color = tod.ambient_color
	var want := Color(clampf(base.r * t.r, 0.0, 1.0), clampf(base.g * t.g, 0.0, 1.0), clampf(base.b * t.b, 0.0, 1.0), base.a)
	check(we.environment.ambient_light_color.is_equal_approx(want), "maslak day ambient after the race order")
	check(we.environment.adjustment_enabled, "maslak day grade is on after the race order")
	sun.free()
	await cleanup([root])
