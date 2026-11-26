extends "res://devtools/capture_scenario.gd"
## Greenery demo: each track at day with Greenery added to the race scene's track, two views per track:
##   <track>_roadside.png  1.7 m above the pavement, looking down the road at 30% of the lap
##   <track>_wide.png      9 m up beside the road, looking along it at 60% of the lap
## --notrees skips Greenery and writes <track>_<view>_notrees.png, so the draw and primitive peaks in each .json
## can be compared with the trees on. Options: --only=city|maslak|bogaz, --preset=high|low (harness flag).

const SCENE: String = "res://race/race_scene.tscn"
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const TRACKS: Dictionary = {
	"city": "res://world/city_01/city_01.tscn",
	"maslak": "res://world/istanbul_maslak/istanbul_maslak.tscn",
	"bogaz": "res://world/istanbul_bogaz/istanbul_bogaz.tscn",
}
const SETTLE_FRAMES: int = 30
const PLACE_FRAMES: int = 4  ## placement runs on the first physics tick after setup
const VIEW_FOV: float = 62.0


func run() -> void:
	var only: String = _arg("--only=")
	var keys: PackedStringArray = PackedStringArray(TRACKS.keys()) if only == "" else PackedStringArray([only])
	var notrees: bool = "--notrees" in OS.get_cmdline_user_args()
	tree.auto_accept_quit = false
	for k: String in keys:
		await _one(k, notrees)
		if not is_instance_valid(tree.root):
			return


func _arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func _one(key: String, notrees: bool) -> void:
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = 2
	cfg.opponent_count = 5
	cfg.track_scene = String(TRACKS[key])
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	cfg.time_of_day = "day"
	var race: RaceScene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	race.config = cfg
	tree.root.add_child(race)
	await cap.wait_frames(SETTLE_FRAMES)
	if race.dev_track_used or race.dev_car_used or race.track == null:
		cap.fail("%s: dev track or car used, or no track" % key)
		race.queue_free()
		return
	var trk: Track = race.track
	if not notrees:
		var g := Greenery.new()
		trk.add_child(g)
		g.setup(trk)
		await cap.wait_frames(PLACE_FRAMES)
		print("greenery_demo: %s placed %d trees %s rejected %s" % [key, g.placed_count(), str(g.species_counts()), str(g.rejected)])
	var suffix: String = "_notrees" if notrees else ""
	var preset_tag: String = "" if Settings.get_preset_id() == "high" else "_" + Settings.get_preset_id()
	for view: String in ["roadside", "wide"]:
		var cam := Camera3D.new()
		cam.fov = VIEW_FOV
		race.add_child(cam)
		cam.global_transform = _view_xf(trk, view)
		cam.make_current()
		await cap.wait_frames(3)
		await cap.shot("%s_%s%s%s" % [key, view, suffix, preset_tag])
		cam.queue_free()
		await cap.wait_frames(2)
	race.queue_free()
	await cap.wait_frames(5)


## Roadside: driver height in the right lane at 30% of the lap, looking forward, so the trees on both sides show.
## Wide: 14 m up over the road centre at 60% of the lap, looking down the road.
func _view_xf(trk: Track, view: String) -> Transform3D:
	var roadside: bool = view == "roadside"
	var s: float = trk.length * (0.3 if roadside else 0.6)
	var c: Vector3 = trk.get_point_at(s)
	var fwd: Vector3 = trk.get_tangent_at(s)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	var eye: Vector3
	var target: Vector3
	if roadside:
		eye = c + right * (trk.width * 0.25) + Vector3.UP * 1.7
		target = eye + fwd * 40.0 + Vector3.DOWN * 1.5
	else:
		eye = c + Vector3.UP * 14.0 - fwd * 10.0
		target = c + fwd * 60.0
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
