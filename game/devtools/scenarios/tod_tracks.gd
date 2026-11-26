extends "res://devtools/capture_scenario.gd"
## Time of day on every track: the real race scene, autopilot player, 5 rivals, one chase-view shot 10 s after GO
## for each track (City 01, Maslak, Bogaz) at day, sunset and night. Shots are named <track>_<tod> (plus _<preset>
## when the preset is not high), e.g. city_day.png, maslak_sunset_low.png.
## Optional user args: --only=<track>:<tod> (one combination, e.g. --only=maslak:day), --tracks=city,maslak,
## --tods=day,night. Fails when the dev track, dev mule or DevWatermark shows up, or the race never starts.

const SCENE: String = "res://race/race_scene.tscn"
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const TRACKS: Dictionary = {
	"city": "res://world/city_01/city_01.tscn",
	"maslak": "res://world/istanbul_maslak/istanbul_maslak.tscn",
	"bogaz": "res://world/istanbul_bogaz/istanbul_bogaz.tscn",
}
const TODS: PackedStringArray = ["day", "sunset", "night"]
const OPPONENTS: int = 5
const SETTLE_FRAMES: int = 20
const WAIT_MAX_S: float = 30.0
const RACING_SHOT_S: float = 10.0

var _scene: RaceScene
var _go_ms: int = 0
var _go_seen: bool = false


func run() -> void:
	var tracks: PackedStringArray = _list_arg("--tracks=", PackedStringArray(TRACKS.keys()))
	var tods: PackedStringArray = _list_arg("--tods=", TODS)
	var only: String = _arg("--only=")
	if only != "":
		tracks = PackedStringArray([only.get_slice(":", 0)])
		tods = PackedStringArray([only.get_slice(":", 1)])
	tree.auto_accept_quit = false
	for t: String in tracks:
		for tod_id: String in tods:
			await _one(t, tod_id)
			if not is_instance_valid(tree.root):
				return


func _one(track_key: String, tod_id: String) -> void:
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = 2
	cfg.opponent_count = OPPONENTS
	cfg.track_scene = String(TRACKS[track_key])
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	cfg.time_of_day = tod_id
	_go_seen = false
	_scene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	_scene.config = cfg
	tree.root.add_child(_scene)
	await cap.wait_frames(SETTLE_FRAMES)
	if _scene.dev_track_used or _scene.dev_car_used or _scene.find_child("DevWatermark", true, false) != null:
		cap.fail("%s/%s: dev track, dev mule or DevWatermark present" % [track_key, tod_id])
		_scene.queue_free()
		return
	_scene.race.race_started.connect(_on_go)
	var waited: float = 0.0
	while not _go_seen and waited < WAIT_MAX_S:
		await cap.wait_seconds(0.1)
		waited += 0.1
	if not _go_seen:
		cap.fail("%s/%s: race never started" % [track_key, tod_id])
		_scene.queue_free()
		return
	var since_go: float = (Time.get_ticks_msec() - _go_ms) / 1000.0
	if since_go < RACING_SHOT_S:
		await cap.wait_seconds(RACING_SHOT_S - since_go)
	var suffix: String = "" if Settings.get_preset_id() == "high" else "_" + Settings.get_preset_id()
	var sun: Light3D = _scene.track.find_child("Sun", true, false) as Light3D
	print("tod_tracks: %s/%s sun=%s shadow=%s" % [track_key, tod_id, str(sun != null), str(sun != null and sun.shadow_enabled)])
	if "--casters" in OS.get_cmdline_user_args():
		_print_casters()
	await cap.shot("%s_%s%s" % [track_key, tod_id, suffix])
	if "--sky" in OS.get_cmdline_user_args():
		await _sky_shot("%s_%s%s_sky" % [track_key, tod_id, suffix])
	_scene.queue_free()
	await cap.wait_frames(5)


## Diagnostic (--casters): shadow casters of the scene grouped by their top two ancestors under the race scene.
func _print_casters() -> void:
	var groups: Dictionary = {}
	for n: Node in _scene.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n as GeometryInstance3D
		if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or not gi.is_visible_in_tree():
			continue
		var rel: PackedStringArray = String(_scene.get_path_to(gi)).split("/")
		var key: String = "/".join(rel.slice(0, 4 if "Geometry" in rel else 3))
		groups[key] = int(groups.get(key, 0)) + 1
	for k: String in groups:
		print("tod_tracks: casters %s = %d" % [k, groups[k]])


## Diagnostic (--sky): a wide camera 4 m above the player, looking along the car and 25 degrees up, so the sky,
## the sun and the skyline show without the HUD.
func _sky_shot(shot_name: String) -> void:
	var cam := Camera3D.new()
	cam.fov = 80.0
	tree.root.add_child(cam)
	var p: Vector3 = _scene.player.global_position
	var fwd: Vector3 = -_scene.player.global_transform.basis.z
	fwd.y = 0.0
	cam.global_position = p + Vector3.UP * 4.0
	cam.look_at(cam.global_position + fwd.normalized() * 10.0 + Vector3.UP * 5.0)
	cam.current = true
	_scene.hud.visible = false
	await cap.wait_frames(3)
	await cap.shot(shot_name)
	cam.queue_free()
	_scene.camera.make_current()
	_scene.hud.visible = true


func _on_go() -> void:
	_go_seen = true
	_go_ms = Time.get_ticks_msec()


func _arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func _list_arg(prefix: String, fallback: PackedStringArray) -> PackedStringArray:
	var v: String = _arg(prefix)
	return PackedStringArray(v.split(",")) if v != "" else fallback
