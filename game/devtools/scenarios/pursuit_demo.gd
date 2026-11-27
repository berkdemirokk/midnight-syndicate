extends "res://devtools/capture_scenario.gd"
## Pursuit evidence on the city track: the real race scene, autopilot player, PursuitMode force-enabled for this run
## only (the kill switch is off in normal builds). Shots: pursuit_police_behind (a police car with its light bar
## on, alongside and just behind the player) and pursuit_roadblock (heat 3, barriers ahead, one lane open).

const SCENE: String = "res://race/race_scene.tscn"
const TRACK: String = "res://world/city_01/city_01.tscn"
const CAR_SCENE: String = "res://vehicles/kestrel_gtr/kestrel_gtr.tscn"
const CAR_SPEC: String = "res://vehicles/specs/kestrel_gtr.tres"
const OPPONENTS: int = 3
const SETTLE_FRAMES: int = 20
const WAIT_STEP_S: float = 1.0 / 60.0
const WAIT_MAX_S: float = 40.0
const CLOSE_M: float = 2.0  ## the first police car is placed this far behind the player, beside it
const SIDE_M: float = 3.5  ## lateral offset of that car: the next lane
const HEAT_FOR_ROADBLOCK: int = 3
const ROADBLOCK_WAIT_S: float = 6.0
const ROADBLOCK_NEAR_M: float = 70.0  ## the roadblock shot waits until the barriers are this close
const ROADBLOCK_NEAR_WAIT_S: float = 40.0

var _scene: RaceScene
var _go_seen: bool = false


func run() -> void:
	PursuitMode.ENABLED = true
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = 2
	cfg.opponent_count = OPPONENTS
	cfg.track_scene = TRACK
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	cfg.pursuit = true
	_scene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	_scene.config = cfg
	tree.root.add_child(_scene)
	await cap.wait_frames(SETTLE_FRAMES)
	if _scene.dev_car_used or _scene.dev_track_used:
		cap.fail("not the real race with the city track and the Kestrel GT-R")
		return
	_scene.race.race_started.connect(func() -> void: _go_seen = true)
	var waited: float = 0.0
	while not _go_seen and waited < WAIT_MAX_S:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	if not _go_seen:
		cap.fail("race never started")
		return
	var pm: PursuitMode = _scene.find_child("PursuitMode", true, false) as PursuitMode
	if pm == null:
		cap.fail("no PursuitMode node")
		return
	await cap.wait_seconds(1.0)
	if pm.police.is_empty():
		cap.fail("no police car spawned on GO")
		return
	# Bring the first police car into frame: 14 m behind the player, on the same lane, with its light bar on.
	var car: ArcadeCar = pm.police[0]
	# The chase camera looks forward, so a car 14 m straight behind is out of frame: put it alongside, in the next lane.
	var track: Track = _scene.track
	var s: float = track.get_progress(_scene.player.global_position) - CLOSE_M
	var t: Vector3 = track.get_tangent_at(s)
	var half: float = track.width * 0.5 - 1.5
	var lat: float = clampf(track.get_lateral_offset(_scene.player.global_position) + SIDE_M, -half, half)
	var p: Vector3 = track.get_point_at(s) + Vector3(-t.z, 0.0, t.x) * lat + Vector3(0.0, PursuitMode.SPAWN_HEIGHT_M, 0.0)
	car.global_transform = Transform3D(Basis.looking_at(t, Vector3.UP), p)
	await cap.wait_seconds(0.3)
	print("PURSUIT_DEMO police=%s player=%s visible=%s" % [car.global_position, _scene.player.global_position, car.visible])
	await cap.shot("pursuit_police_behind")
	pm.state.heat = HEAT_FOR_ROADBLOCK
	waited = 0.0
	while pm.roadblock == null and waited < ROADBLOCK_WAIT_S:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	if pm.roadblock == null:
		cap.fail("no roadblock at heat %d" % HEAT_FOR_ROADBLOCK)
		return
	waited = 0.0
	while _scene.track.get_point_at(pm.roadblock.progress).distance_to(_scene.player.global_position) > ROADBLOCK_NEAR_M and waited < ROADBLOCK_NEAR_WAIT_S:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	print("PURSUIT_DEMO roadblock=%s player=%s" % [_scene.track.get_point_at(pm.roadblock.progress), _scene.player.global_position])
	await cap.shot("pursuit_roadblock")
