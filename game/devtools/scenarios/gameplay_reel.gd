extends "res://devtools/capture_scenario.gd"
## Motion review reel: a real race sampled as a JPG frame sequence from GO on, so LOD pops and fades can be judged
## in motion (tools/reel_sheet.py turns the folder into a contact sheet and an MP4). Same race setup as race_city /
## race_bogaz / race_maslak, with traffic on (parked and AI cars are what the LOD switches are judged on).
## Run through the capture harness, under the GPU lock:
##   godot --path game --audio-driver Dummy --resolution 1920x1080 --position 20000,0 res://devtools/capture_boot.tscn -- --capture=gameplay_reel --track=bogaz --side --timeout=240
## Args (after --): --track=bogaz|city|maslak, --fps=8, --seconds=20, --side (static camera 9 m beside the player's car
## at GO, so the field passes it; default is the chase camera).
## Output: evidence/screens/gameplay_reel/<track>_<side|chase>/frame_NNNN.jpg + reel_meta.json, and one real PNG shot.

const RACE_SCENE: String = "res://race/race_scene.tscn"
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const TRACKS: Dictionary = {
	"bogaz": "res://world/istanbul_bogaz/istanbul_bogaz.tscn",
	"city": "res://world/city_01/city_01.tscn",
	"maslak": "res://world/istanbul_maslak/istanbul_maslak.tscn",
}
const OPPONENTS: int = 5
const GUARD_S: float = 150.0
const OUT_W: int = 960
const OUT_H: int = 540
const JPG_QUALITY: float = 0.85
const OUT_REL: String = "../evidence/screens/gameplay_reel/"

var _track_key: String = "bogaz"
var _fps: float = 8.0
var _seconds: float = 20.0
var _side: bool = false


func run() -> void:
	_parse_args()
	if not TRACKS.has(_track_key):
		cap.fail("gameplay_reel: unknown --track=" + _track_key)
		return
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = 2
	cfg.opponent_count = OPPONENTS
	cfg.track_scene = TRACKS[_track_key]
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	cfg.traffic_enabled = true
	cfg.rival_mix = false
	cfg.time_of_day = "night"
	var scene: RaceScene = (load(RACE_SCENE) as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	tree.root.add_child(scene)
	var out_dir: String = ProjectSettings.globalize_path("res://").path_join(OUT_REL + "%s_%s" % [_track_key, "side" if _side else "chase"]).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var meta: Array = []
	var cam: Camera3D = null
	var go_ms: float = -1.0
	var next_ms: float = 0.0
	var started: int = Time.get_ticks_msec()
	while true:
		await cap.wait_frames(1)
		if scene.player == null:
			continue
		if go_ms < 0.0 and scene.race.state == RaceManager.State.RACING:
			go_ms = float(Time.get_ticks_msec())
			if _side:
				cam = Camera3D.new()
				cam.fov = 55.0
				tree.root.add_child(cam)
				var p: Vector3 = scene.player.global_position
				var side_dir: Vector3 = scene.player.global_transform.basis.x.normalized()
				cam.global_position = p + side_dir * 9.0 + Vector3.UP * 1.6
				cam.look_at(p + Vector3.UP * 0.8, Vector3.UP)
				cam.make_current()
		if go_ms >= 0.0:
			var now: float = float(Time.get_ticks_msec()) - go_ms
			if now >= next_ms:
				await RenderingServer.frame_post_draw
				var img: Image = get_viewport().get_texture().get_image()
				img.resize(OUT_W, OUT_H, Image.INTERPOLATE_BILINEAR)
				img.save_jpg("%s/frame_%04d.jpg" % [out_dir, meta.size()], JPG_QUALITY)
				meta.append([snappedf(now / 1000.0, 0.01), snappedf(scene.player.speed_kmh, 0.1)])
				next_ms += 1000.0 / _fps
			if now >= _seconds * 1000.0:
				break
		if float(Time.get_ticks_msec() - started) > GUARD_S * 1000.0:
			cap.fail("gameplay_reel: guard timeout, race never reached RACING")
			return
	await cap.shot("reel_end")
	var data: Dictionary = {"machine": "Windows 11 dev PC, NVIDIA RTX 5060 Ti 8 GB, Godot 4.7.2. Not a phone.",
		"track": _track_key, "side_camera": _side, "fps": _fps, "frame_size": [OUT_W, OUT_H],
		"time_of_day": "night", "frames": meta.size(), "fields": ["t_s", "player_speed_kmh"], "rows": meta}
	var f: FileAccess = FileAccess.open(out_dir + "/reel_meta.json", FileAccess.WRITE)
	if f == null:
		cap.fail("gameplay_reel: cannot write %s/reel_meta.json (error %d)" % [out_dir, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(data))
	f.close()
	print("gameplay_reel: %d frames to %s" % [meta.size(), out_dir])


func _parse_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			_track_key = a.trim_prefix("--track=")
		elif a.begins_with("--fps="):
			_fps = a.trim_prefix("--fps=").to_float()
		elif a.begins_with("--seconds="):
			_seconds = a.trim_prefix("--seconds=").to_float()
		elif a == "--side":
			_side = true
