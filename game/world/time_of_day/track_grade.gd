class_name TrackGrade
extends RefCounted
## Per-track colour grade on top of the time-of-day preset (docs/design/TIME_OF_DAY.md, "Per-track grade").
## RaceScene calls apply_to_world once the track and its environment exist, after TimeOfDay has written the hour.
## Values are absolute: each call starts from the environment's base, which is what the environment held before the
## last grade. The base is only reused while the environment still holds exactly what that grade wrote; if TimeOfDay
## (or anything else) has written the environment since, the current values become the new base. So a race at another
## hour in the same process is graded from that hour's preset, not from an earlier race's base.
## Split toning goes through the ambient light colour: a procedural LUT on the colour correction texture was tried and
## drew noise on Godot 4.7, so it is not used.

const BASE_META: StringName = &"grade_base"
## Track scene file name -> table key. Anything else (the development circuit, unknown tracks) is not graded.
const TRACK_KEYS: Dictionary = {"city_01": "city", "istanbul_maslak": "maslak", "istanbul_bogaz": "bogaz"}
## Per track and hour. exposure, contrast and saturation multiply the environment's own values.
## ambient: rgb multiplier of the ambient light (the shadows, the street in shade); fog: the depth fog colour, mixed in by fog_mix.
## Every ambient multiplier stays at or under 1.2 (shade only: the sunlit faces are not multiplied) and luma_max is checked in the capture JSON.
const TABLE: Dictionary = {
	"city": {
		"day": {"exposure": 1.0, "contrast": 1.02, "saturation": 1.04, "ambient": Color(0.84, 1.0, 1.14), "fog": Color(0.74, 0.86, 0.88), "fog_mix": 0.2},
		"sunset": {"exposure": 1.0, "contrast": 1.02, "saturation": 1.06, "ambient": Color(0.82, 1.0, 1.14), "fog": Color(0.40, 0.46, 0.52), "fog_mix": 0.2},
		"night": {"exposure": 1.0, "contrast": 1.04, "saturation": 1.1, "ambient": Color(0.78, 1.02, 1.16), "fog": Color(0.10, 0.20, 0.22), "fog_mix": 0.3},
	},
	"maslak": {
		"day": {"exposure": 1.0, "contrast": 1.02, "saturation": 0.86, "ambient": Color(0.88, 0.96, 1.18), "fog": Color(0.72, 0.80, 0.90), "fog_mix": 0.3},
		"sunset": {"exposure": 1.0, "contrast": 1.0, "saturation": 0.9, "ambient": Color(0.9, 0.97, 1.16), "fog": Color(0.45, 0.50, 0.62), "fog_mix": 0.2},
		"night": {"exposure": 1.0, "contrast": 1.02, "saturation": 0.84, "ambient": Color(0.92, 1.0, 1.16), "fog": Color(0.66, 0.74, 0.84), "fog_mix": 0.2},
	},
	"bogaz": {
		"day": {"exposure": 1.0, "contrast": 1.02, "saturation": 1.05, "ambient": Color(1.06, 1.0, 0.94), "fog": Color(0.92, 0.82, 0.66), "fog_mix": 0.3},
		"sunset": {"exposure": 1.0, "contrast": 1.02, "saturation": 1.06, "ambient": Color(1.08, 0.99, 0.92), "fog": Color(0.85, 0.60, 0.45), "fog_mix": 0.25},
		"night": {"exposure": 1.0, "contrast": 1.0, "saturation": 1.04, "ambient": Color(1.06, 1.0, 0.94), "fog": Color(0.50, 0.42, 0.34), "fog_mix": 0.2},
	},
}


## Table key of a track scene path, "" when the track is not graded.
static func key_for(track_scene: String) -> String:
	for file: String in TRACK_KEYS:
		if track_scene.contains(file):
			return TRACK_KEYS[file]
	return ""


## The grade of one track at one hour; empty when there is none.
static func values(track_key: String, tod_id: String) -> Dictionary:
	var by_hour: Dictionary = TABLE.get(track_key, {})
	return by_hour.get(tod_id, {})


## Grades every WorldEnvironment under world for this track and hour. Call after TimeOfDay has set the environment.
## Capture switch: "--no-grade" after the user args gives the BEFORE shots (never passed by the game).
static func apply_to_world(world: Node, track_scene: String, tod_id: String) -> void:
	var v: Dictionary = values(key_for(track_scene), tod_id)
	if v.is_empty() or "--no-grade" in OS.get_cmdline_user_args():
		return
	for n: Node in world.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (n as WorldEnvironment).environment
		if env != null:
			apply(env, v)


static func apply(env: Environment, v: Dictionary) -> void:
	var now: Dictionary = _snapshot(env)
	var stored: Dictionary = env.get_meta(BASE_META, {})
	var b: Dictionary = now
	if not stored.is_empty() and _same(stored["written"], now):
		b = stored["base"]  ## nothing has written the environment since the last grade: keep its base
	env.tonemap_exposure = float(b["exposure"]) * float(v["exposure"])
	env.adjustment_enabled = true
	env.adjustment_contrast = float(b["contrast"]) * float(v["contrast"])
	env.adjustment_saturation = float(b["saturation"]) * float(v["saturation"])
	var amb: Color = b["ambient"]
	var t: Color = v["ambient"]
	env.ambient_light_color = Color(clampf(amb.r * t.r, 0.0, 1.0), clampf(amb.g * t.g, 0.0, 1.0), clampf(amb.b * t.b, 0.0, 1.0), amb.a)
	env.fog_light_color = (b["fog"] as Color).lerp(v["fog"], float(v["fog_mix"]))
	env.set_meta(BASE_META, {"base": b, "written": _snapshot(env)})


static func _snapshot(env: Environment) -> Dictionary:
	return {"exposure": env.tonemap_exposure, "contrast": env.adjustment_contrast,
		"saturation": env.adjustment_saturation, "fog": env.fog_light_color, "ambient": env.ambient_light_color}


static func _same(a: Dictionary, b: Dictionary) -> bool:
	for k: String in ["exposure", "contrast", "saturation"]:
		if not is_equal_approx(float(a[k]), float(b[k])):
			return false
	return (a["fog"] as Color).is_equal_approx(b["fog"]) and (a["ambient"] as Color).is_equal_approx(b["ambient"])
