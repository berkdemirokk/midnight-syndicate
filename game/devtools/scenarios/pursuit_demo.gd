extends "res://devtools/capture_scenario.gd"
## Pursuit evidence on the city track: the real race scene, autopilot player, PursuitMode force-enabled for this run
## only (the kill switch is off in normal builds). Shots: pursuit_police_behind (a police car with its light bar
## on, alongside and just behind the player) and pursuit_roadblock (heat 3, barriers ahead, one lane open, from a
## shot camera above and behind the player), then pursuit_roadblock_close (the same barriers from 7 m at eye height).

const SCENE: String = "res://race/race_scene.tscn"
const TRACK: String = "res://world/city_01/city_01.tscn"
const CAR_SCENE: String = "res://vehicles/kestrel_gtr/kestrel_gtr.tscn"
const CAR_SPEC: String = "res://vehicles/specs/kestrel_gtr.tres"
const OPPONENTS: int = 3
const SETTLE_FRAMES: int = 20
const WAIT_STEP_S: float = 1.0 / 60.0
const WAIT_MAX_S: float = 40.0
const CLOSE_M: float = 0.0  ## the first police car is placed this far behind the player: level with it, in frame
const SIDE_M: float = 3.5  ## lateral offset of that car: the next lane
const HEAT_FOR_ROADBLOCK: int = 3
const ROADBLOCK_WAIT_S: float = 6.0
const ROADBLOCK_NEAR_M: float = 30.0  ## the roadblock shot waits until the barriers are this close
const SHOT_CAM_UP_M: float = 7.0  ## the roadblock shot camera: above and behind the player, so rivals do not hide the barriers
const SHOT_CAM_BACK_M: float = 8.0
const ROADBLOCK_NEAR_WAIT_S: float = 40.0
const CLOSE_CAM_BACK_M: float = 7.0  ## the close-up camera: this far before the barriers, toward the traffic
const CLOSE_CAM_UP_M: float = 1.4
const CLOSE_CAM_SIDE_M: float = -2.0  ## left of the barrier line: the player car drives in the open lane on the right

var _scene: RaceScene
var _go_seen: bool = false


func run() -> void:
	GameState.open_profile("user://pursuit_capture_save.json")  # the escape pays out: keep the real profile out of it
	GameState.reset_profile()
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
	var car: ArcadeCar = pm.police[0]
	# The chase camera sits about 6 m back and looks forward: a car behind the player is out of frame, so put it alongside.
	var track: Track = _scene.track
	var s: float = track.get_progress(_scene.player.global_position) - CLOSE_M
	var t: Vector3 = track.get_tangent_at(s)
	var half: float = track.width * 0.5 - 1.5
	var lat: float = clampf(track.get_lateral_offset(_scene.player.global_position) + SIDE_M, -half, half)
	var p: Vector3 = track.get_point_at(s) + Vector3(-t.z, 0.0, t.x) * lat + Vector3(0.0, PursuitMode.SPAWN_HEIGHT_M, 0.0)
	car.global_transform = Transform3D(Basis.looking_at(t, Vector3.UP), p)
	car.linear_velocity = _scene.player.linear_velocity  # keep pace for the shot instead of starting from rest
	await cap.wait_seconds(0.3)
	var cam: Camera3D = tree.root.get_viewport().get_camera_3d()
	var bar: Node3D = car.get_node("LightBar") as Node3D
	var in_frame: bool = cam != null and cam.is_position_in_frustum(bar.global_position)
	print("PURSUIT_DEMO police=%s player=%s cam=%s light_bar_in_frame=%s" % [car.global_position, _scene.player.global_position, cam.global_position if cam else Vector3.ZERO, in_frame])
	if not in_frame:
		cap.fail("police light bar is not in the camera frame")
		return
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
	# A shot camera above and behind the player: from the chase camera the player car and the rivals hide the barriers.
	var fwd: Vector3 = _scene.track.get_tangent_at(_scene.track.get_progress(_scene.player.global_position))
	var mid: Vector3 = Vector3.ZERO
	for b: Node in pm.roadblock.get_children():
		mid += (b as Node3D).global_position / float(pm.roadblock.get_child_count())
	var cam2 := Camera3D.new()
	cam2.fov = 60.0
	_scene.add_child(cam2)
	cam2.global_position = _scene.player.global_position - fwd * SHOT_CAM_BACK_M + Vector3.UP * SHOT_CAM_UP_M
	cam2.look_at(mid, Vector3.UP)
	cam2.make_current()
	await cap.wait_frames(2)
	var seen: int = 0
	for b: Node in pm.roadblock.get_children():
		var bp: Vector3 = (b as Node3D).global_position
		var vis: bool = cam2 != null and cam2.is_position_in_frustum(bp)
		seen += 1 if vis else 0
		print("PURSUIT_DEMO barrier=%s in_frame=%s dist=%.1f screen=%s" % [bp, vis, bp.distance_to(_scene.player.global_position), cam2.unproject_position(bp) if cam2 else Vector2.ZERO])
	print("PURSUIT_DEMO player=%s cam=%s" % [_scene.player.global_position, cam2.global_position if cam2 else Vector3.ZERO])
	if seen == 0:
		cap.fail("no roadblock barrier in the camera frame")
		return
	await cap.shot("pursuit_roadblock")
	# Close-up from the traffic side at eye height: the barrier profile and its road face must read at this range too.
	var rb_t: Vector3 = _scene.track.get_tangent_at(pm.roadblock.progress)
	cam2.global_position = mid - rb_t * CLOSE_CAM_BACK_M + Vector3.UP * CLOSE_CAM_UP_M + Vector3(-rb_t.z, 0.0, rb_t.x) * CLOSE_CAM_SIDE_M
	cam2.look_at(mid + Vector3.UP * 0.4, Vector3.UP)
	await cap.wait_frames(2)
	await cap.shot("pursuit_roadblock_close")
	# Heat 5: the top of the ladder (police cap 3, all five pips lit, the radar with every car).
	pm.state.heat = 5
	await cap.wait_seconds(1.0)
	await cap.shot("pursuit_heat_5")
	# Escape, real rules: every police car 150 m back, out of sensing range, so the 8 s cooldown runs and the chase ends.
	var fwd_e: Vector3 = _scene.track.get_tangent_at(_scene.track.get_progress(_scene.player.global_position))
	for c: ArcadeCar in pm.police:
		var drv_off: AIDriver = c.get_node_or_null(PursuitMode.DRIVER_NAME) as AIDriver
		if drv_off != null:
			drv_off.enabled = false  # the police must not drive back into sensing range during the cooldown
		c.global_transform = Transform3D(Basis.looking_at(fwd_e, Vector3.UP), _scene.player.global_position - fwd_e * 150.0 + Vector3(0.0, PursuitMode.SPAWN_HEIGHT_M, 0.0))
	waited = 0.0
	while pm.state.phase != PursuitState.Phase.ESCAPED and pm.state.phase != PursuitState.Phase.BUSTED and waited < 15.0:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	print("PURSUIT_DEMO escape phase=%d heat=%d reward=%d waited=%.1f" % [pm.state.phase, pm.state.heat, pm.escape_reward, waited])
	await cap.wait_seconds(0.5)
	await cap.shot("pursuit_escape")
	# Bust banner: shown from the bust state (set directly, the chase is stopped so no reward is paid).
	pm._active = false
	pm.state.phase = PursuitState.Phase.BUSTED
	pm._update_hud()
	await cap.wait_frames(3)
	await cap.shot("pursuit_bust")
