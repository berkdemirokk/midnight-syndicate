extends "res://devtools/capture_scenario.gd"
## Civilian traffic on City 01: the real race scene (autopilot player, 5 AI) with a TrafficSystem added to its World
## node from here, without touching race_scene.gd. Shots: grid, racing_10s, traffic_ahead (a same-direction car 15 to
## 45 m ahead of the player), oncoming (an oncoming car 15 to 60 m ahead), traffic_hit (a traffic car pushed by a race
## car, if it happens within the wait). Every shot json holds draw calls and primitives with traffic on.
## Run: -- --capture=traffic_demo [--preset=low|medium|high]

const SCENE: String = "res://race/race_scene.tscn"
const CITY_SCENE: String = "res://world/city_01/city_01.tscn"
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const SETTLE_FRAMES: int = 20
const POLL_FRAMES: int = 6
const POLL_STEP_S: float = 0.1
const GRID_SHOT_DELAY_S: float = 0.6
const GO_WAIT_MAX_S: float = 20.0
const RACING_SHOT_S: float = 10.0
const FIND_MAX_S: float = 60.0
const AHEAD_MIN_M: float = 15.0
const AHEAD_MAX_M: float = 45.0
const ONCOMING_MAX_M: float = 60.0
const CONE_COS: float = 0.9  ## the car must sit this close to the camera axis (cosine)
const HIT_WAIT_MAX_S: float = 40.0

var _scene: RaceScene
var _traffic: TrafficSystem
var _go: bool = false


func run() -> void:
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = 2
	cfg.opponent_count = 5
	cfg.track_scene = CITY_SCENE
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	_scene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	_scene.config = cfg
	tree.root.add_child(_scene)
	await cap.wait_frames(SETTLE_FRAMES)
	if _scene.dev_track_used or _scene.dev_car_used:
		cap.fail("dev track or dev mule in play: not the real race")
		return
	_traffic = TrafficSystem.new()
	_traffic.name = "Traffic"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--traffic="):
			_traffic.count_override = int(arg.trim_prefix("--traffic="))  # 0 = baseline without traffic
	_scene.track.get_parent().add_child(_traffic)
	_traffic.setup(_scene.track, _scene.player, _scene.cars)
	_scene.race.race_started.connect(func() -> void: _go = true)
	print("traffic_demo: preset %s, %d traffic cars" % [Settings.get_preset_id(), _traffic.cars.size()])
	await cap.wait_seconds(GRID_SHOT_DELAY_S)
	await cap.shot("grid")
	var waited: float = 0.0
	while not _go and waited < GO_WAIT_MAX_S:
		await cap.wait_seconds(POLL_STEP_S)
		waited += POLL_STEP_S
	if not _go:
		cap.fail("race never started")
		return
	await cap.wait_seconds(RACING_SHOT_S)
	await cap.shot("racing_10s")
	if "--short" in OS.get_cmdline_user_args():  # budget runs: 10 s shot and a 240-frame measure only
		await cap.measure("traffic_perf", 240)
		return
	if await _wait_for(_find_ahead.bind(1)):
		await cap.shot("traffic_ahead")
	else:
		print("traffic_demo: no same-direction car in frame within %.0f s" % FIND_MAX_S)
	if await _wait_for(_find_ahead.bind(-1)):
		await cap.shot("oncoming")
	else:
		print("traffic_demo: no oncoming car in frame within %.0f s" % FIND_MAX_S)
	if await _wait_for(_find_hit, HIT_WAIT_MAX_S):
		await cap.shot("traffic_hit")
	else:
		print("traffic_demo: no push seen within %.0f s" % HIT_WAIT_MAX_S)
	await cap.measure("traffic_perf", 240)
	if not _traffic.cars.is_empty():
		await _closeup("closeup_tail", 1, Vector3(0.0, 1.9, 6.5), true)
	print("traffic_demo: hits %d respawns %d" % [_traffic.hit_count, _traffic.respawns])


## Parks a capture camera on a traffic car of direction dir (offset in the car's space, looking at its middle) and
## shoots it with the traffic controller paused, so the lamp state set here stays.
func _closeup(shot_name: String, dir: int, offset: Vector3, brake: bool) -> void:
	var pick: TrafficCar = null
	for c: TrafficCar in _traffic.cars:
		if c.placed and c.dir == dir and c.visible:
			pick = c
			break
	if pick == null:
		print("traffic_demo: no car of direction %d for %s" % [dir, shot_name])
		return
	_traffic.set_physics_process(false)
	pick._set_brake(brake)
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.current = true
	pick.add_child(cam)
	cam.position = offset
	cam.look_at(pick.global_position + Vector3.UP * 0.8)
	await cap.wait_frames(3)
	await cap.shot(shot_name)
	cam.current = false
	cam.queue_free()
	_traffic.set_physics_process(true)


func _wait_for(cond: Callable, limit_s: float = FIND_MAX_S) -> bool:
	var waited: float = 0.0
	while waited < limit_s:
		if cond.call():
			return true
		await cap.wait_frames(POLL_FRAMES)
		waited += POLL_STEP_S
	return false


## A traffic car of direction dir in front of the player camera, 15 m to AHEAD_MAX_M (60 m when oncoming).
func _find_ahead(dir: int) -> bool:
	var cam: Camera3D = tree.root.get_viewport().get_camera_3d()
	if cam == null:
		return false
	var limit: float = AHEAD_MAX_M if dir > 0 else ONCOMING_MAX_M
	for c: TrafficCar in _traffic.cars:
		if not c.placed or c.dir != dir:
			continue
		var to: Vector3 = c.global_position - cam.global_position
		var d: float = to.length()
		if d < AHEAD_MIN_M or d > limit:
			continue
		if to.normalized().dot(-cam.global_transform.basis.z) > CONE_COS:
			return true
	return false


func _find_hit() -> bool:
	var cam: Camera3D = tree.root.get_viewport().get_camera_3d()
	if cam == null:
		return false
	for c: TrafficCar in _traffic.cars:
		if c.hit_t > 0.0 and c.global_position.distance_to(cam.global_position) < ONCOMING_MAX_M:
			var to: Vector3 = (c.global_position - cam.global_position).normalized()
			if to.dot(-cam.global_transform.basis.z) > 0.5:
				return true
	return false
