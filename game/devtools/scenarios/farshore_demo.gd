extends "res://devtools/capture_scenario.gd"
## Far shore demo: the Bosphorus track at night and at day, with FarScenery under the track (bridge, hillside lights,
## ferry, water reflections). Three views per time of day:
##   <time>_coast_across.png  1.7 m above the right lane at 22% of the lap, looking out across the water (left)
##   <time>_coast_ahead.png   the same lane at 18%, looking along the road with the bridge ahead and left
##   <time>_bridge_wide.png   from over the water at the bridge centre, looking at the towers and the ferry line
## Options: --only=night or --only=day. The printed line gives the scenery cost and how many flat skyline cards were hidden.

const SCENE: String = "res://race/race_scene.tscn"
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const TRACK: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const SETTLE_FRAMES: int = 30
const PLACE_FRAMES: int = 4  ## placement runs on the first physics tick after setup
const VIEW_FOV: float = 62.0


func run() -> void:
	var only: String = _arg("--only=")
	var times: PackedStringArray = PackedStringArray(["night", "day"]) if only == "" else PackedStringArray([only])
	tree.auto_accept_quit = false
	for t: String in times:
		await _one(t)
		if not is_instance_valid(tree.root):
			return


func _arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func _one(time_id: String) -> void:
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = 2
	cfg.opponent_count = 5
	cfg.track_scene = TRACK
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	cfg.time_of_day = time_id
	var race: RaceScene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	race.config = cfg
	tree.root.add_child(race)
	await cap.wait_frames(SETTLE_FRAMES)
	if race.dev_track_used or race.dev_car_used or race.track == null:
		cap.fail("%s: dev track or car used, or no track" % time_id)
		race.queue_free()
		return
	var trk: Track = race.track
	var fs := FarScenery.new()
	trk.add_child(fs)
	fs.setup(trk, time_id)
	await cap.wait_frames(PLACE_FRAMES)
	var hidden: int = trk.find_children("*" + FarScenery.HIDES_ASSET + "*", "", true, false).size()
	print("farshore_demo: %s cost %s, skyline cards named %s" % [time_id, str(fs.cost()), str(hidden)])
	for view: String in ["coast_across", "coast_ahead", "bridge_wide"]:
		var cam := Camera3D.new()
		cam.fov = VIEW_FOV
		race.add_child(cam)
		cam.global_transform = _view_xf(trk, view)
		cam.make_current()
		await cap.wait_frames(3)
		await cap.shot("%s_%s" % [time_id, view])
		cam.queue_free()
		await cap.wait_frames(2)
	race.queue_free()
	await cap.wait_frames(5)


## Views along the Bosphorus road. Right of the race direction is the land side; the sea is on the left.
func _view_xf(trk: Track, view: String) -> Transform3D:
	var eye: Vector3
	var target: Vector3
	if view == "bridge_wide":
		eye = Vector3(380.0, 18.0, 120.0)
		target = FarScenery.CENTRE + Vector3(0.0, 40.0, 0.0)
	else:
		var s: float = trk.length * (0.22 if view == "coast_across" else 0.18)
		var c: Vector3 = trk.get_point_at(s)
		var fwd: Vector3 = trk.get_tangent_at(s)
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right: Vector3 = fwd.cross(Vector3.UP)
		eye = c + right * (trk.width * 0.25) + Vector3.UP * 1.7
		if view == "coast_across":
			target = eye - right * 400.0 + Vector3.DOWN * 1.5
		else:
			target = eye + fwd * 400.0 - right * 120.0 + Vector3.DOWN * 4.0
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
