extends "res://devtools/capture_scenario.gd"
## In-engine race evidence on City 01: the real race scene, the real track and the real car, 5 opponents, 2 laps,
## autopilot player (deterministic). No staging: the car's speed and nitro come from the game itself.
## Shots, in race order: grid, countdown_2, racing_10s, pack, drift (handbrake input only), underpass,
## racing_nitro (lap 2, car above 180 km/h with nitro_active, only if it happens), results.
## Fails if the dev track, dev mule or DevWatermark shows up.
## Extra run: --stop-after-10s stops after the racing_10s shot and names it racing_10s_<preset> (for Low/Medium).

const SCENE: String = "res://race/race_scene.tscn"
const CITY_SCENE: String = "res://world/city_01/city_01.tscn"
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const OPPONENTS: int = 5
const LAP_LENGTH_M: float = 2203.225  ## city_01_layout.json lap_length
const LAPS: int = 2  ## the spec race
const SETTLE_FRAMES: int = 20
const POLL_FRAMES: int = 1
const WAIT_STEP_S: float = 1.0 / 60.0
const TICK_TWO: int = 2
const GRID_SHOT_DELAY_S: float = 0.4
const RACING_SHOT_S: float = 10.0
const PACK_WAIT_MAX_S: float = 25.0
const PACK_MIN_RIVALS: int = 2  ## rivals inside the frame, within PACK_RANGE_M
const PACK_RANGE_M: float = 80.0
const DRIFT_LEAD_M: float = 40.0  ## the drift starts this far before the corner apex
const DRIFT_SEARCH_MIN_M: float = 60.0
const DRIFT_SEARCH_MAX_M: float = 600.0
const DRIFT_SEARCH_STEP_M: float = 5.0
const DRIFT_TURN_LOOK_M: float = 25.0  ## heading change measured over this distance gives the turn direction
const DRIFT_APPROACH_M: float = 10.0  ## the approach counts as reached within this distance
const DRIFT_THROTTLE: float = 1.0
const DRIFT_HOLD_S: float = 1.8  ## steer input held this long through the corner
const DRIFT_HANDBRAKE_S: float = 0.5  ## handbrake only at the entry (as a player does), then throttle holds the slide
const DRIFT_SHOT_MIN_DEG: float = 15.0  ## shot as soon as the slide is this big
const DRIFT_SHOT_AT_S: float = 1.4  ## fallback moment if the slide never gets that big
const DRIFT_WAIT_MAX_S: float = 40.0
const NITRO_MIN_KMH: float = 180.0  ## speed lines fade in from 180 km/h; the lap-2 nitro bursts end before 200
const PLAYER_NITRO_START_KMH: float = 140.0  ## lap-2 autopilot policy for the nitro shot
const NITRO_LAP: int = 2  ## the nitro shot is taken on lap 2 only
const NITRO_WAIT_MAX_S: float = 240.0  ## bounded; the wait also ends when the results screen shows
const TUNNEL_IN_M: float = 1560.0  ## underpass lights span s 1467 to 1803 m; shot taken inside, past the entry
const TUNNEL_OUT_M: float = 1760.0
const UNDERPASS_WAIT_MAX_S: float = 60.0
const RESULTS_WAIT_MAX_S: float = 240.0  ## counted in poll steps; at high fps the steps run faster than wall time
const RESULTS_SETTLE_S: float = 2.0
const GRID_BACK_M: float = 15.0  ## grid camera: behind the grid centre, 30 degrees off the rear axis
const GRID_SIDE_M: float = 9.0
const GRID_UP_M: float = 7.0
const GRID_FOV_DEG: float = 60.0

var _scene: RaceScene
var _track: Track
var _saw_two: bool = false
var _go_seen: bool = false
var _lap1_done: bool = false
var _top_kmh: float = 0.0
var _lap2_top_kmh: float = 0.0
var _lap2_nitro_seen: bool = false
var _hits: int = 0
var _grid_cam: Camera3D = null
var _go_ms_value: int = 0


func run() -> void:
	var cfg := RaceConfig.new()
	cfg.autopilot = true
	cfg.laps = LAPS
	cfg.opponent_count = OPPONENTS
	cfg.track_scene = CITY_SCENE
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	var packed: PackedScene = load(SCENE) as PackedScene
	_scene = packed.instantiate() as RaceScene
	_scene.config = cfg
	tree.root.add_child(_scene)
	await cap.wait_frames(SETTLE_FRAMES)
	if not _is_real_race():
		return
	var short_run: bool = _has_arg("--stop-after-10s")
	_track = _scene.track
	_print_speed_profile()
	tree.process_frame.connect(_track_top_speed)
	_scene.player.hit.connect(_on_player_hit)
	# An unexplained window close request ended earlier runs silently (exit 0, no capture summary).
	# The capture is non-interactive, so the scenario ignores it; Capture's own quit still works.
	tree.auto_accept_quit = false
	tree.root.close_requested.connect(func() -> void: print("race_city: WM close requested (ignored)"))
	tree.root.focus_exited.connect(func() -> void: print("race_city: window lost focus"))
	tree.root.tree_exiting.connect(func() -> void: print("race_city: tree exiting at %.1f s" % (Time.get_ticks_msec() / 1000.0)))
	_scene.race.countdown_tick.connect(_on_tick)
	_scene.race.race_started.connect(_on_go)
	_scene.race.lap_completed.connect(_on_lap_completed)
	await cap.wait_seconds(GRID_SHOT_DELAY_S)
	if not short_run:
		await _grid_shot()
	var waited: float = 0.0
	while not _saw_two and waited < PACK_WAIT_MAX_S:
		await cap.wait_frames(POLL_FRAMES)
		waited += WAIT_STEP_S
	if not _saw_two:
		cap.fail("countdown never reached 2")
		return
	if not short_run:
		await cap.shot("countdown_2")
	_end_grid_cam()
	waited = 0.0
	while not _go_seen and waited < PACK_WAIT_MAX_S:
		await cap.wait_frames(POLL_FRAMES)
		waited += WAIT_STEP_S
	if not _go_seen:
		cap.fail("race never started")
		return
	var since_go: float = (Time.get_ticks_msec() - _go_ms_value) / 1000.0
	if since_go < RACING_SHOT_S:
		await cap.wait_seconds(RACING_SHOT_S - since_go)
	if short_run:
		await cap.shot("racing_10s_%s" % _preset_arg())
		return
	await cap.shot("racing_10s")
	if not await _pack_shot():
		return
	await _drift_shot()
	await _underpass_shot()
	await _nitro_lap2_shot()
	await _results_shot()


## Fails the run when the dev track, the dev mule or the dev watermark is in play.
func _is_real_race() -> bool:
	if _scene.dev_track_used or _scene.dev_car_used or _scene.find_child("DevWatermark", true, false) != null:
		cap.fail("dev track, dev mule or DevWatermark present: not the real race")
		return false
	if _scene.config_used.track_scene != CITY_SCENE or _scene.config_used.car_scene != CAR_SCENE:
		cap.fail("race config is not City 01 with the Noctra Sable")
		return false
	return true


func _rivals_in_view() -> int:
	var cam: ChaseCamera = _scene.camera
	var n: int = 0
	for c: ArcadeCar in _scene.cars:
		if c == _scene.player:
			continue
		var d: float = c.global_position.distance_to(_scene.player.global_position)
		if d <= PACK_RANGE_M and cam.is_position_in_frustum(c.global_position):
			n += 1
	return n


func _pack_shot() -> bool:
	var waited: float = 0.0
	while _rivals_in_view() < PACK_MIN_RIVALS:
		if waited >= PACK_WAIT_MAX_S:
			cap.fail("fewer than %d rivals in view within %.0f s" % [PACK_MIN_RIVALS, PACK_WAIT_MAX_S])
			return false
		await cap.wait_frames(POLL_FRAMES)
		waited += WAIT_STEP_S
	print("race_city: pack shot with %d rivals in view" % _rivals_in_view())
	await cap.shot("pack")
	return true


## Grid view: a fixed camera behind and to the side of the grid centre, looking down the grid.
## The chase camera (orbit mode) sat inside the parking structure at the grid, so it is not used here.
func _grid_shot() -> void:
	var c: Vector3 = Vector3.ZERO
	for car: ArcadeCar in _scene.cars:
		c += car.global_position
	c /= float(_scene.cars.size())
	var fwd: Vector3 = _track.get_tangent_at(_track.get_progress(c))
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side: Vector3 = fwd.cross(Vector3.UP).normalized()
	var cam := Camera3D.new()
	cam.fov = GRID_FOV_DEG
	tree.root.add_child(cam)
	cam.global_position = c - fwd * GRID_BACK_M + side * GRID_SIDE_M + Vector3.UP * GRID_UP_M
	cam.look_at(c + fwd * 8.0 + Vector3.UP * 1.0)
	cam.current = true
	await cap.shot("grid")
	_grid_cam = cam


func _end_grid_cam() -> void:
	if is_instance_valid(_grid_cam):
		_grid_cam.queue_free()
	_grid_cam = null
	_scene.camera.make_current()


func _on_player_hit(impulse: float, _world_pos: Vector3) -> void:
	_hits += 1
	if _hits <= 5:
		print("race_city: player hit impulse=%.0f at s=%.0f" % [impulse, _progress()])


func _track_top_speed() -> void:
	if _scene != null and _scene.player != null:
		_top_kmh = maxf(_top_kmh, _scene.player.speed_kmh)
		if _lap1_done:
			_lap2_top_kmh = maxf(_lap2_top_kmh, _scene.player.speed_kmh)


## Diagnostics only: where the track allows the highest speed (the straights).
func _print_speed_profile() -> void:
	var best: float = 0.0
	var best_s: float = 0.0
	var over_200: int = 0
	var s: float = 0.0
	while s < LAP_LENGTH_M:
		var v: float = _track.get_target_speed(s)
		if v > best:
			best = v
			best_s = s
		if v * 3.6 >= NITRO_MIN_KMH:
			over_200 += 1
		s += 10.0
	print("race_city: track max target %.1f km/h at s=%.0f; samples at or over %.0f km/h: %d" % [best * 3.6, best_s, NITRO_MIN_KMH, over_200])


## Distance along the lap from s to target, always 0..LAP_LENGTH_M.
func _ahead_m(s: float, target: float) -> float:
	return fposmod(target - s, LAP_LENGTH_M)


func _progress() -> float:
	return _track.get_progress(_scene.player.global_position)


## Sharpest corner 60 to 600 m ahead. The player gets handbrake and steer input for 1 s through it, with the
## autopilot paused. Input only: the car's position and velocity are not touched. The autopilot resumes afterwards.
func _drift_shot() -> void:
	var here: float = _progress()
	var best_s: float = -1.0
	var best_k: float = 0.0
	var s: float = here + DRIFT_SEARCH_MIN_M
	while s < here + DRIFT_SEARCH_MAX_M:
		var k: float = absf(_track.get_curvature(s))
		if k > best_k:
			best_k = k
			best_s = s
		s += DRIFT_SEARCH_STEP_M
	if best_s < 0.0:
		cap.fail("no corner found for the drift shot")
		return
	var lead_s: float = best_s - DRIFT_LEAD_M
	var waited: float = 0.0
	while _ahead_m(_progress(), lead_s) > DRIFT_APPROACH_M and waited < DRIFT_WAIT_MAX_S:
		await cap.wait_frames(POLL_FRAMES)
		waited += WAIT_STEP_S
	var t_in: Vector3 = _track.get_tangent_at(best_s)
	var t_out: Vector3 = _track.get_tangent_at(best_s + DRIFT_TURN_LOOK_M)
	var steer: float = signf(-t_in.cross(t_out).y)  ## a right turn gives cross.y < 0 with forward -Z; steer +1 = right
	print("race_city: drift at s=%.0f m curvature=%.4f steer=%.0f" % [best_s, best_k, steer])
	var inp: VehicleInput = _scene.player.input
	_scene.player_ai.set_physics_process(false)
	var start_ms: int = Time.get_ticks_msec()
	var shot_done: bool = false
	var drift_seen: bool = false
	var max_angle: float = 0.0
	while float(Time.get_ticks_msec() - start_ms) / 1000.0 < DRIFT_HOLD_S:
		var t_s: float = float(Time.get_ticks_msec() - start_ms) / 1000.0
		inp.handbrake = t_s < DRIFT_HANDBRAKE_S
		inp.throttle = 0.0 if inp.handbrake else DRIFT_THROTTLE
		inp.brake = 0.0
		inp.steer = steer
		inp.nitro = false
		if _scene.player.is_drifting:
			drift_seen = true
		max_angle = maxf(max_angle, absf(_scene.player.drift_angle_deg))
		var big_slide: bool = _scene.player.is_drifting and absf(_scene.player.drift_angle_deg) >= DRIFT_SHOT_MIN_DEG
		if not shot_done and (big_slide or t_s >= DRIFT_SHOT_AT_S):
			await cap.shot("drift")
			shot_done = true
			continue
		await cap.wait_frames(POLL_FRAMES)
	print("race_city: drift loop done")
	inp.clear()
	_scene.player_ai.set_physics_process(true)
	print("race_city: drift detected=%s max_slip_deg=%.1f" % [drift_seen, max_angle])
	if not shot_done:
		cap.fail("drift shot never taken")


## Lap 2 only: the shot is taken when the car is above NITRO_MIN_KMH with nitro_active, as the game produces them.
## Nothing is forced. If the condition never happens before the results screen, no shot is taken.
func _nitro_lap2_shot() -> void:
	var waited: float = 0.0
	while not _scene.results_screen.visible and waited < NITRO_WAIT_MAX_S:
		var car: ArcadeCar = _scene.player
		if _lap1_done and car.speed_kmh >= NITRO_MIN_KMH and car.nitro_active:
			print("race_city: nitro shot at %.1f km/h on lap 2" % car.speed_kmh)
			await cap.shot("racing_nitro")
			_lap2_nitro_seen = true
			return
		await cap.wait_frames(POLL_FRAMES)
		waited += WAIT_STEP_S
	print("race_city: NO nitro shot: no lap-2 moment above %.0f km/h with nitro_active; lap-2 top %.1f km/h" % [NITRO_MIN_KMH, _lap2_top_kmh])


func _underpass_shot() -> void:
	var waited: float = 0.0
	while waited < UNDERPASS_WAIT_MAX_S:
		var s: float = _progress()
		if s >= TUNNEL_IN_M and s <= TUNNEL_OUT_M and _scene.player.is_grounded:
			break
		await cap.wait_frames(POLL_FRAMES)
		waited += WAIT_STEP_S
	var s_now: float = _progress()
	if s_now < TUNNEL_IN_M or s_now > TUNNEL_OUT_M:
		cap.fail("player never inside the underpass within %.0f s" % UNDERPASS_WAIT_MAX_S)
		return
	print("race_city: underpass shot at s=%.0f m" % s_now)
	await cap.shot("underpass")


func _results_shot() -> void:
	var waited: float = 0.0
	while not _scene.results_screen.visible and waited < RESULTS_WAIT_MAX_S:
		await cap.wait_frames(POLL_FRAMES)
		waited += WAIT_STEP_S
	if not _scene.results_screen.visible:
		cap.fail("results screen never appeared")
		return
	await cap.wait_seconds(RESULTS_SETTLE_S)
	print("race_city: run summary top_kmh=%.1f lap2_top_kmh=%.1f lap2_nitro_shot=%s hits=%d" % [_top_kmh, _lap2_top_kmh, str(_lap2_nitro_seen), _hits])
	await cap.shot("results")


func _has_arg(name: String) -> bool:
	return name in OS.get_cmdline_user_args()


func _preset_arg() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--preset="):
			return arg.trim_prefix("--preset=")
	return "high"


func _on_tick(seconds_left: int) -> void:
	if seconds_left == TICK_TWO:
		_saw_two = true


func _on_go() -> void:
	_go_seen = true
	_go_ms_value = Time.get_ticks_msec()


func _on_lap_completed(car: ArcadeCar, lap: int, _lap_time: float) -> void:
	if car == _scene.player and lap == 1:
		_lap1_done = true
		# Lap 2: the player's autopilot saves its nitro for the top end (input policy only; the car's
		# speed and position are never touched). Rivals keep the default policy.
		if _scene.player_ai != null:
			_scene.player_ai.nitro_min_start_kmh = PLAYER_NITRO_START_KMH
		print("race_city: player finished lap 1 at %.1f s after GO, top so far %.1f km/h" % [(Time.get_ticks_msec() - _go_ms_value) / 1000.0, _top_kmh])
