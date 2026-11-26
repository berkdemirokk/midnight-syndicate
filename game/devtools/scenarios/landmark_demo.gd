extends "res://devtools/capture_scenario.gd"
## Landmark demo: the waterfront mosque beside the Bogaz race line, at night and at day, three views on the race
## approach: 150 m before it, 60 m before it, and passing it (camera on the road, aimed at the prayer hall).
## Shots are landmark_<tod>_<view>.png; with --nolandmark the landmark is left out and the shots get a _nolandmark tag,
## so the draw and primitive peaks in each .json can be compared. Options: --tod=night|day (default both).

const SCENE: String = "res://race/race_scene.tscn"
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const TRACK: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const SETTLE_FRAMES: int = 30
const PLACE_FRAMES: int = 4  ## the landmark places itself on the first physics tick after setup
const VIEW_FOV: float = 55.0
const EYE_HEIGHT_M: float = 1.3
## View name -> [metres before the landmark's racing-line point, lateral offset of the camera]
const VIEWS: Dictionary = {"approach150": [150.0, -1.0], "approach60": [60.0, -1.0], "passing": [6.0, -4.0]}


func run() -> void:
	var only: String = _arg("--tod=")
	var tods: PackedStringArray = PackedStringArray(["night", "day"]) if only == "" else PackedStringArray([only])
	tree.auto_accept_quit = false
	for tod: String in tods:
		await _one(tod)
		if not is_instance_valid(tree.root):
			return


func _arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func _one(tod: String) -> void:
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = 2
	cfg.opponent_count = 5
	cfg.track_scene = TRACK
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	cfg.time_of_day = tod
	var race: RaceScene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	race.config = cfg
	tree.root.add_child(race)
	await cap.wait_frames(SETTLE_FRAMES)
	if race.dev_track_used or race.dev_car_used or race.track == null:
		cap.fail("%s: dev track or car used, or no track" % tod)
		race.queue_free()
		return
	var trk: Track = race.track
	var lm: Landmarks = null
	if "--nolandmark" not in OS.get_cmdline_user_args():
		lm = Landmarks.new()
		trk.add_child(lm)
		lm.setup(trk)
		lm.set_night(1.0 if tod == "night" else 0.0)
		await cap.wait_frames(PLACE_FRAMES)
		print("landmark_demo: %s placed at s=%.0f, hall centre %s" % [tod, lm.placed_s, str(lm.hall_centre())])
	var suffix: String = "" if lm != null else "_nolandmark"
	for view: String in VIEWS.keys():
		var cam := Camera3D.new()
		cam.fov = VIEW_FOV
		race.add_child(cam)
		cam.global_transform = _view_xf(trk, lm, view)
		cam.make_current()
		await cap.wait_frames(3)
		await cap.shot("landmark_%s_%s%s" % [tod, view, suffix])
		cam.queue_free()
		await cap.wait_frames(2)
	race.queue_free()
	await cap.wait_frames(5)


## Eye on the road at the view's distance before the landmark's racing-line point, aimed at the prayer hall.
func _view_xf(trk: Track, lm: Landmarks, view: String) -> Transform3D:
	var spec: Array = VIEWS[view]
	var s0: float = Landmarks.PLACE_S_M
	var s: float = s0 - float(spec[0])
	var c: Vector3 = trk.get_point_at(s)
	var fwd: Vector3 = trk.get_tangent_at(s)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	var eye: Vector3 = c + right * float(spec[1]) + Vector3.UP * EYE_HEIGHT_M
	var target: Vector3 = lm.hall_centre() if lm != null else trk.get_point_at(s0) + Vector3.UP * 8.0
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
