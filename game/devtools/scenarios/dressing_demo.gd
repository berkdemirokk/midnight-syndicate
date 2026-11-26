extends "res://devtools/capture_scenario.gd"
## Event dressing demo on the Bosphorus track (istanbul_bogaz) in the real race scene, with EventDressing added to
## the track. Views, each one shot per time of day:
##   bogaz_<tod>_roadside   driver height in the right lane at 30% of the lap, looking forward
##   bogaz_<tod>_crowd      on the road 4.5 m from the nearest spectator card, over the barrier, looking at the crowd
##   bogaz_<tod>_wide       14 m up over the road at 60% of the lap, looking down the road
##   bogaz_<tod>_barrier    close: 3.5 m off a barrier face, the banner square to the camera
##   bogaz_<tod>_flag       close: a flag pole from the road side, the cloth waving
##   bogaz_<tod>_cafe       land side, 6 m back from the nearest terrace, looking at the awning
## Options: --tod=day|sunset|night (default: day and night), --noevent (no EventDressing, for the draw and primitive
## peaks without it), --only=<view>. Shots land in evidence/screens/dressing_demo/ with a perf json each.

const SCENE: String = "res://race/race_scene.tscn"
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const TRACK: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const SETTLE_FRAMES: int = 30
const PLACE_FRAMES: int = 4  ## placement runs on the first physics tick after setup
const VIEW_FOV: float = 62.0
const VIEWS_ALL: PackedStringArray = ["roadside", "crowd", "wide", "barrier", "flag", "cafe"]


func run() -> void:
	var tods: PackedStringArray = PackedStringArray(["day", "night"])
	var arg_tod: String = _arg("--tod=")
	if arg_tod != "":
		tods = PackedStringArray([arg_tod])
	var views: PackedStringArray = VIEWS_ALL
	var only: String = _arg("--only=")
	if only != "":
		views = PackedStringArray([only])
	tree.auto_accept_quit = false
	for tod_id: String in tods:
		await _one(tod_id, views)
		if not is_instance_valid(tree.root):
			return


func _arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func _one(tod_id: String, views: PackedStringArray) -> void:
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = 2
	cfg.opponent_count = 5
	cfg.track_scene = TRACK
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	cfg.time_of_day = tod_id
	var race: RaceScene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	race.config = cfg
	tree.root.add_child(race)
	await cap.wait_frames(SETTLE_FRAMES)
	if race.dev_track_used or race.dev_car_used or race.track == null:
		cap.fail("%s: dev track or car used, or no track" % tod_id)
		race.queue_free()
		return
	var trk: Track = race.track
	var noevent: bool = "--noevent" in OS.get_cmdline_user_args()
	var suffix: String = "_noevent" if noevent else ""
	var d: EventDressing = null
	if not noevent:
		d = EventDressing.new()
		trk.add_child(d)
		d.setup(trk, tod_id)
		await cap.wait_frames(PLACE_FRAMES)
		print("dressing_demo: %s placed %d %s rejected %s" % [tod_id, d.placed_count(), str(d.kind_counts()),
			str(d.rejected)])
	for view: String in views:
		if d == null and view not in ["roadside", "crowd", "wide"]:
			continue
		var cam := Camera3D.new()
		cam.fov = VIEW_FOV
		race.add_child(cam)
		cam.global_transform = _view_xf(trk, d, view)
		cam.make_current()
		await cap.wait_frames(3)
		await cap.shot("bogaz_%s_%s%s" % [tod_id, view, suffix])
		cam.queue_free()
		await cap.wait_frames(2)
	race.queue_free()
	await cap.wait_frames(5)


## The placement of a kind nearest to arc length s (null when there is none, or no dressing).
func _nearest(d: EventDressing, prefix: String, s: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	if d == null:
		return best
	for p: Dictionary in d.placements:
		if String(p.kind).begins_with(prefix) and absf(float(p.s) - s) < best_d:
			best_d = absf(float(p.s) - s)
			best = p
	return best


func _view_xf(trk: Track, d: EventDressing, view: String) -> Transform3D:
	var s: float = trk.length * 0.3
	if view == "crowd":
		s = trk.length * 0.45
	elif view == "wide":
		s = trk.length * 0.6
	elif view == "barrier" or view == "flag" or view == "cafe":
		s = trk.length * 0.45
	var c: Vector3 = trk.get_point_at(s)
	var fwd: Vector3 = trk.get_tangent_at(s)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	var edge: float = trk.width * 0.5
	var eye: Vector3
	var target: Vector3
	match view:
		"roadside":
			eye = c + right * (trk.width * 0.25) + Vector3.UP * 1.7
			target = eye + fwd * 40.0 + Vector3.DOWN * 1.5
		"crowd":
			var g: Dictionary = _nearest(d, "crowd", s)
			if g.is_empty():
				return Transform3D.IDENTITY
			var face0: Vector3 = g.face
			eye = (g.pos as Vector3) + face0 * 4.5 + Vector3.UP * 1.4  # on the road side, over the barrier
			target = (g.pos as Vector3) + Vector3.UP * 1.0
		"barrier":
			var b: Dictionary = _nearest(d, "barrier", s)
			if b.is_empty():
				return Transform3D.IDENTITY
			var face: Vector3 = b.face
			eye = (b.pos as Vector3) + face * 3.5 + Vector3.UP * 1.2
			target = (b.pos as Vector3) + Vector3.UP * 0.5
		"flag":
			var f: Dictionary = _nearest(d, "flag", s)
			if f.is_empty():
				return Transform3D.IDENTITY
			var face2: Vector3 = f.face
			eye = (f.pos as Vector3) + face2 * 6.0 + Vector3.UP * 2.2
			target = (f.pos as Vector3) + Vector3.UP * 3.8
		"cafe":
			var k: Dictionary = _nearest(d, "cafe", s)
			if k.is_empty():
				return Transform3D.IDENTITY
			var face3: Vector3 = k.face
			eye = (k.pos as Vector3) - face3 * 6.0 + Vector3.UP * 2.0
			target = (k.pos as Vector3) + Vector3.UP * 1.0
		_:
			eye = c + Vector3.UP * 14.0 - fwd * 10.0
			target = c + fwd * 60.0
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
