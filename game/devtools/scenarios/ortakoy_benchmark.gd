extends "res://devtools/capture_scenario.gd"
## Graphics benchmark: one car and the first 100 m of the Ortakoy coast (start grid to the mosque), by day and by
## night. The day shots are the honest ones: no darkness, bloom or haze to hide the geometry.
## Shots (bench_<tod>_<view>.png): hero (low chase view, no HUD), car34 (car close-up, no HUD), street (eye level
## along the land side, no HUD), mosque (the landmark from the road, no HUD) and gameplay (HUD on, 3 s after GO).
## Options: --tod=day|night (default both).

const SCENE: String = "res://race/race_scene.tscn"
const CAR_SCENE: String = "res://vehicles/kestrel_vanta/kestrel_vanta.tscn"
const CAR_SPEC: String = "res://vehicles/specs/kestrel_vanta.tres"
const TRACK: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const SETTLE_FRAMES: int = 40
const GAMEPLAY_S: float = 3.0
const WAIT_MAX_S: float = 20.0


func run() -> void:
	var only: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--tod="):
			only = a.trim_prefix("--tod=")
	var tods: PackedStringArray = PackedStringArray(["day", "night"]) if only == "" else PackedStringArray([only])
	tree.auto_accept_quit = false
	for tod: String in tods:
		await _one(tod)


func _one(tod: String) -> void:
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = 2
	cfg.opponent_count = 2
	cfg.track_scene = TRACK
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	cfg.time_of_day = tod
	var race: RaceScene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	race.config = cfg
	tree.root.add_child(race)
	await cap.wait_frames(SETTLE_FRAMES)
	if race.dev_track_used or race.dev_car_used or race.track == null or race.player == null:
		cap.fail("%s: dev track or car used, or no track" % tod)
		race.queue_free()
		return
	var car: Node3D = race.player
	var fwd: Vector3 = -car.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	var at: Vector3 = car.global_position
	var lm: Landmarks = race.find_child("Landmarks", true, false) as Landmarks
	var hall: Vector3 = lm.hall_centre() if lm != null else at + fwd * 100.0 + Vector3.UP * 8.0
	race.hud.visible = false
	# view -> [eye, target, fov]
	var views: Dictionary = {
		"hero": [at - fwd * 5.2 - right * 0.6 + Vector3.UP * 0.75, at + fwd * 30.0 + Vector3.UP * 3.5, 62.0],
		"car34": [at + fwd * 3.6 + right * 2.6 + Vector3.UP * 0.6, at + Vector3.UP * 0.1, 45.0],
		"street": [at + fwd * 8.0 + right * 1.0 + Vector3.UP * 0.9, at + fwd * 60.0 + right * 9.0 + Vector3.UP * 5.0, 60.0],
		"mosque": [at + fwd * 25.0 + right * 3.0 + Vector3.UP * 0.9, hall, 55.0],
	}
	for view: String in views.keys():
		var v: Array = views[view]
		var cam := Camera3D.new()
		cam.fov = float(v[2])
		race.add_child(cam)
		cam.global_transform = Transform3D(Basis.looking_at((v[1] as Vector3) - (v[0] as Vector3), Vector3.UP), v[0] as Vector3)
		cam.make_current()
		await cap.wait_frames(4)
		await cap.shot("bench_%s_%s" % [tod, view])
		cam.queue_free()
		await cap.wait_frames(2)
	race.hud.visible = true
	var waited: float = 0.0
	while race.race.state != RaceManager.State.RACING and waited < WAIT_MAX_S:
		await cap.wait_seconds(0.1)
		waited += 0.1
	await cap.wait_seconds(GAMEPLAY_S)
	await cap.shot("bench_%s_gameplay" % tod)
	race.queue_free()
	await cap.wait_frames(5)
