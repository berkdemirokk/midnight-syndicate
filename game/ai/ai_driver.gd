class_name AIDriver
extends Node
## Racing AI for one ArcadeCar, added as a child of the car. Pure pursuit to a look-ahead point on
## the racing line shifted by the lane offset, a speed controller on the track target speed, car
## sensing and avoidance (following, side clearance, passing with abort), stuck recovery and a bounded
## rubber band. Writes car.input every physics tick. Forward is -Z. Every tunable is an export.
## Sensing uses only Track progress and lateral offsets (no physics queries), so it is deterministic.

enum Mode { RACE, REVERSE }

const KMH_PER_MS: float = 3.6
const MIN_LOOK_AHEAD_SQ: float = 1.0  ## m^2, guards the pure-pursuit division
const NOISE_MAIN_WEIGHT: float = 0.6  ## the second noise frequency gets the rest of the weight
const NOISE_HARMONIC: float = 2.3  ## second noise frequency as a multiple of the first
const NOISE_PHASE_STEP: float = 1.7  ## phase of the second frequency relative to the first
const NITRO_MIN_AMOUNT: float = 0.3  ## nitro charge needed before the AI asks for nitro
const COAST_BRAKE: float = 0.5  ## brake while a car that is done racing slows down
const COAST_SPEED_KMH: float = 20.0
const NOISE_BRAKE: int = 0  ## index into the noise phases
const NOISE_STEER: int = 1
const AI_PHYSICS_PRIORITY: int = -1  ## runs before ArcadeCar (priority 0) so the car reads this tick's input
const SIDE_NONE: int = 0  ## pass side when no pass is under way (-1 = left, +1 = right)
const SIDE_BEHIND_M: float = 8.0  ## m, a car this far behind us on the target side can still come alongside
const CORNER_BRAKE_MS: float = 1.0  ## m/s below the current speed that counts as braking into a corner
const CORNER_SAMPLE_M: float = 10.0  ## m, spacing of the curvature samples ahead

class NearCar extends RefCounted:
	var car: ArcadeCar = null
	var along: float = 0.0  ## m along the line from us, positive = ahead
	var dl: float = 0.0  ## m, its lateral offset minus ours, positive = right
	var lat: float = 0.0  ## m, its lateral offset from the line
	var speed: float = 0.0  ## m/s forward
	var ttc: float = INF  ## s to contact when it is ahead and closing, else INF

@export_range(0.8, 1.0) var skill: float = 0.9  ## fraction of the track target speed this driver aims for
@export var lane_offset: float = 0.0  ## m right of the racing line, positive = right
@export var enabled: bool = true
@export var look_ahead_min: float = 8.0  ## m
@export var look_ahead_time: float = 0.45  ## s, look-ahead grows with speed
@export var look_ahead_max: float = 45.0  ## m
@export var target_look_ahead_time: float = 0.6  ## s, the target speed is read this far ahead
@export var target_look_ahead_max: float = 40.0  ## m
@export var throttle_gain: float = 0.5  ## throttle per m/s of speed error
@export var brake_gain: float = 0.2  ## brake per m/s of speed error
@export var nitro_min_gap_ms: float = 5.0  ## m/s (18 km/h): nitro only when this far below the target speed
@export var nitro_max_curvature: float = 0.004  ## 1/m, straights only (radius above 250 m)
@export var nitro_min_start_kmh: float = 0.0  ## 0 = off. Pack-race stuck counts react chaotically to this value (tested 100/140 on 2026-11-24), so rivals keep 0; nitro starts only above this speed: it also raises the speed cap, so it pays most near the top end
@export var nitro_look_m: float = 90.0  ## m, nitro needs the road to stay straight this far ahead (keeps the charge for straights)
@export var shift_stop_curvature: float = 0.008  ## 1/m (radius 125 m): a lane pass starts and continues only while the road in the overtake zone ahead (overtake_range + side_long_range) is gentler than this
@export var kerb_margin: float = 1.5  ## m: a pass whose target offset is this close to a kerb is refused
@export var overtake_range: float = 20.0  ## m, a slower car this close ahead in our lane is passed
@export var overtake_shift: float = 2.5  ## m lane shift to pass
@export var shift_rate: float = 1.5  ## m/s that the lane shift moves
@export var car_width: float = 1.9  ## m, body width: two cars overlap laterally within this plus lane_margin
@export var car_length: float = 4.6  ## m, bumper to bumper gap = centre gap minus this
@export var sense_range: float = 30.0  ## m along the line: cars this close are sensed (sensing list)
@export var lane_margin: float = 0.6  ## m, lateral overlap margin for a car ahead in our lane
@export var side_clearance: float = 0.8  ## m, lateral clearance kept from a car alongside (body gap)
@export var side_long_range: float = 7.0  ## m, a car this close along the track counts as alongside (overlaps longitudinally)
@export var follow_decel: float = 4.0  ## m/s^2, braking that stops short of a car ahead in our lane: the brake needed for the closing speed over the bumper gap, at this deceleration = full brake
@export var ttc_brake: float = 1.5  ## s, a car ahead in our lane closer than this in time is matched in speed unless a side is free
@export var pass_timeout_s: float = 8.0  ## s, a pass that is not finished by then is aborted
@export var pass_cooldown_s: float = 3.0  ## s, after an aborted pass no new pass starts
@export var grid_hold_m: float = 150.0  ## m, cars that start behind the line keep their grid lane for this far
@export var corner_hold_curvature: float = 0.006  ## 1/m (radius 167 m): braking toward a bend this tight freezes lane changes
@export var corner_hold_m: float = 50.0  ## m, how far ahead the corner check looks
@export var edge_margin: float = 1.0  ## m, lane offsets stay this far inside the kerb line
@export var rubber_band_max: float = 0.08  ## largest change of target speed from the rubber band
@export var rubber_band_gap: float = 150.0  ## m, the gap where the rubber band starts and grows to full
@export var brake_noise: float = 0.04  ## fraction of target speed: moves braking points earlier or later
@export var steer_noise: float = 0.03  ## steering input units, smooth noise so drivers differ
@export var noise_rate: float = 0.7  ## 1/s
@export var noise_seed: int = 1  ## set per driver (RaceManager uses the grid slot) so the noise phases differ
@export var stuck_progress_m: float = 2.0  ## m of forward progress along the line that counts as moving
@export var stuck_time: float = 2.0  ## s without stuck_progress_m of forward progress while racing before recovery starts
@export var reverse_time: float = 1.5  ## s of reversing before checking whether the car is free
@export var reset_yaw_deg: float = 40.0  ## heading error still above this after a reverse: teleport back onto the line
@export var follow_range: float = 18.0  ## m, a slower car this close ahead in our lane caps our speed
@export var follow_gap: float = 6.0  ## m, the gap at which we match the speed of the car ahead
@export var follow_gain: float = 0.6  ## m/s allowed per m of gap beyond follow_gap
@export var reset_height: float = 0.47  ## car origin height used when placing it back on the line
@export var reset_advance_m: float = 4.0  ## a reset lands this far ahead of where the car was stuck
@export var reset_clear_m: float = 7.0  ## a reset spot needs this much room to every other car
@export var reset_probe_step_m: float = 8.0  ## if the spot is taken, try this much further ahead
@export var reset_probe_tries: int = 6
@export var repeat_stuck_m: float = 15.0  ## a new stuck event this close to the last one skips the reverse attempt
@export var slide_lift_ms: float = 2.5  ## m/s sideways speed across the track where the throttle starts to ease off (sliding)
@export var slide_cut_ms: float = 4.0  ## m/s sideways speed at which the throttle is fully lifted; ramps in between (no step)
@export var slide_brake_gain: float = 0.15  ## brake per m/s of sideways speed above slide_lift_ms (full brake at about 9 m/s)
@export var bend_bias_start: float = 0.006  ## 1/m: tighter bends than this start to move the lane to the inside
@export var bend_bias_full: float = 0.0075  ## 1/m: the inside bias reaches bend_bias_m at this curvature
@export var bend_bias_m: float = 1.5  ## m: inside lane bias in a tight bend, so a car that runs wide still has room to the kerb

var stuck_count: int = 0  ## recovery starts so far

var _track: Track
var _car: ArcadeCar
var _traffic: Array[ArcadeCar] = []
var _racing: bool = false
var _mode: Mode = Mode.RACE
var _mode_t: float = 0.0
var _idle_t: float = 0.0  ## s since the car last gained stuck_progress_m of forward progress
var _anchor_s: float = -1.0  ## track progress at the last forward gain (or at recovery start)
var _shift: float = 0.0
var _last_s: float = -1.0
var _last_stuck_s: float = -1.0e9  ## lap offset of the previous stuck event (repeat detection)
var _time: float = 0.0
var _phase: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _lane_limit: float = 0.0
var _reference_gap: float = 0.0  ## m of race distance, reference car minus this car (positive = it is ahead)
var _has_reference: bool = false
var _near: Array[NearCar] = []  ## sensing list, reused every tick; the first _near_n entries are valid
var _near_n: int = 0
var _lat_me: float = 0.0  ## this tick: our lateral offset from the line
var _zone_curv: float = 0.0  ## this tick: signed curvature of largest magnitude in the passing zone ahead
var _pass_ok: bool = false  ## this tick: a pass may start (zone not a bend, not held at the grid, not braking into a bend, no cooldown)
var _pass_side: int = SIDE_NONE
var _pass_car: ArcadeCar = null  ## the slower car being passed
var _pass_anchor: float = 0.0  ## our lateral offset when the pass started
var _pass_t: float = 0.0  ## s since the pass started
var _cooldown_t: float = 0.0  ## s left before a new pass may start after an abort
var _go_s: float = 0.0  ## track progress at GO
var _go_lat: float = 0.0  ## lateral offset at GO (the grid lane)
var _grid_hold: bool = false  ## started behind the line: keep the grid lane for grid_hold_m
var _race_m: float = 0.0  ## m along the race since GO, unwrapped (a lap is not wrapped back to zero)
var _race_s_prev: float = 0.0  ## track progress on the last tick, for _race_m
var _follow_brake: float = 0.0  ## this tick: brake (0..1) the car ahead needs from us, from the closing speed and the bumper gap
var _held: bool = false  ## last tick: the car ahead caps our speed (a queue, not a wedge), so it is not counted as stuck


func _init() -> void:
	process_physics_priority = AI_PHYSICS_PRIORITY


func setup(track: Track) -> void:
	_track = track
	_car = get_parent() as ArcadeCar
	if _track == null or _car == null:
		push_error("AIDriver needs a Track and an ArcadeCar parent")
		enabled = false
		return
	_lane_limit = maxf(0.0, track.width * 0.5 - edge_margin)
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	_phase = PackedFloat32Array([rng.randf() * TAU, rng.randf() * TAU])
	_last_s = -1.0
	_shift = 0.0
	_mode = Mode.RACE
	_idle_t = 0.0
	_anchor_s = -1.0
	_clear_pass()
	_cooldown_t = 0.0
	_grid_hold = false


## Cars around this one, for overtaking and side clearance.
func set_traffic(cars: Array[ArcadeCar]) -> void:
	_traffic = cars


## Race distance gap to the reference car (the player) in m, from RaceManager's unwrapped distances.
## Positive = the reference is ahead. Without a call the rubber band is neutral.
func set_reference_gap(gap: float) -> void:
	_reference_gap = gap
	_has_reference = true


## While false the car is only braked gently and the stuck detector is off.
## On GO (true) the grid lane is recorded: a car that starts behind the line keeps it for grid_hold_m.
func set_racing(on: bool) -> void:
	_racing = on
	_mode = Mode.RACE
	_idle_t = 0.0
	_anchor_s = -1.0
	_clear_pass()
	_cooldown_t = 0.0
	if on and _track != null and _car != null:
		var pos: Vector3 = _car.global_position
		_go_s = _track.get_progress(pos)
		_go_lat = _lateral_at(pos, _go_s)
		_grid_hold = _wrap_signed(_go_s) < 0.0
		_race_m = 0.0
		_race_s_prev = _go_s


func _physics_process(delta: float) -> void:
	if _track == null or _car == null:
		return
	_time += delta
	var inp: VehicleInput = _car.input
	if not enabled:
		inp.clear()
		return
	if not _racing:
		inp.clear()
		if _car.speed_kmh > COAST_SPEED_KMH:
			inp.brake = COAST_BRAKE
		return
	if _mode == Mode.REVERSE:
		_tick_reverse(delta)
		return
	var pos: Vector3 = _car.global_position
	var s: float = _track.get_progress(pos, _last_s)
	_last_s = s
	if _anchor_s < 0.0:
		_anchor_s = s
	# Progress-based stuck check: no forward progress along the line for stuck_time while racing.
	# A car held behind traffic is queued, not wedged: the car ahead is what stops it, and that car is counted itself.
	if _held or _wrap_signed(s - _anchor_s) >= stuck_progress_m:
		_anchor_s = s
		_idle_t = 0.0
	else:
		_idle_t += delta
	if _idle_t >= stuck_time:
		stuck_count += 1
		_idle_t = 0.0
		# Stuck again at the same place: reversing did not help last time, go straight to a reset.
		if absf(_wrap_signed(s - _last_stuck_s)) < repeat_stuck_m:
			_last_stuck_s = s
			_reset_to_line()
			_anchor_s = -1.0
			return
		_last_stuck_s = s
		_mode = Mode.REVERSE
		_mode_t = 0.0
		_anchor_s = s
		_tick_reverse(delta)
		return
	var v: float = maxf(_car.forward_speed, 0.0)
	_lat_me = _lateral_at(pos, s)
	_race_m += _wrap_signed(s - _race_s_prev)
	_race_s_prev = s
	_sense(s, v)
	_update_shift(s, v, delta)
	var lane: float
	if _grid_hold and _race_m < grid_hold_m:
		lane = _go_lat
	else:
		lane = lane_offset + _shift + _bend_bias(s)
	lane = _clamp_lane(lane)
	_drive(pos, s, v, lane)


func _drive(pos: Vector3, s: float, v: float, lane: float) -> void:
	var spec: CarSpec = _car.spec
	var inp: VehicleInput = _car.input
	var top_ms: float = spec.top_speed_kmh / KMH_PER_MS
	# Steering: pure pursuit to a look-ahead point on the lane. Positive lateral is right.
	var look: float = clampf(look_ahead_min + look_ahead_time * v, look_ahead_min, look_ahead_max)
	var o: float = s + look
	var c: Vector3 = _track.get_point_at(o)
	var t: Vector3 = _track.get_tangent_at(o)
	var tg: Vector3 = _track.get_tangent_at(s)
	var target: Vector3 = c + Vector3(-t.z, 0.0, t.x) * lane
	var b: Basis = _car.global_transform.basis
	var fwd: Vector3 = Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var rgt: Vector3 = Vector3(b.x.x, 0.0, b.x.z).normalized()
	var d: Vector3 = target - pos
	d.y = 0.0
	var lx: float = d.dot(rgt)
	var lz: float = d.dot(fwd)
	var ld2: float = maxf(lx * lx + lz * lz, MIN_LOOK_AHEAD_SQ)
	var wheel_rad: float = atan(2.0 * spec.wheelbase * lx / ld2)
	var lock_deg: float = lerpf(spec.steer_angle_low_deg, spec.steer_angle_high_deg, clampf(v / top_ms, 0.0, 1.0))
	var steer: float = clampf(wheel_rad / deg_to_rad(lock_deg), -1.0, 1.0)
	steer = clampf(steer + steer_noise * _noise(NOISE_STEER), -1.0, 1.0)
	# Speed: target speed read a little ahead, scaled by skill, rubber band and braking-point noise.
	var ahead: float = s + clampf(target_look_ahead_time * v, 0.0, target_look_ahead_max)
	var want: float = minf(_track.get_target_speed(s), _track.get_target_speed(ahead)) * skill * get_rubber_band()
	want *= 1.0 + brake_noise * _noise(NOISE_BRAKE)
	var cap: float = _traffic_cap(v)
	_held = cap < want
	want = minf(want, cap)
	want = minf(want, top_ms)
	var err: float = want - v
	inp.steer = steer
	inp.handbrake = false
	var lat_v: float = _car.linear_velocity.dot(Vector3(-tg.z, 0.0, tg.x))
	if err >= 0.0:
		inp.throttle = clampf(err * throttle_gain, 0.0, 1.0)
		inp.brake = 0.0
		var ease: float = clampf((slide_cut_ms - absf(lat_v)) / maxf(slide_cut_ms - slide_lift_ms, 0.01), 0.0, 1.0)
		inp.throttle *= ease
	else:
		inp.throttle = 0.0
		inp.brake = clampf(-err * brake_gain, 0.0, 1.0)
	# Sliding sideways: brake too, so the tyres get back the grip the lateral slide is using.
	inp.brake = maxf(inp.brake, clampf((absf(lat_v) - slide_lift_ms) * slide_brake_gain, 0.0, 1.0))
	# Closing on the car ahead: brake for the closing speed, not only toward its speed (no throttle while doing so).
	if _follow_brake > 0.0:
		inp.brake = maxf(inp.brake, clampf(_follow_brake, 0.0, 1.0))
		inp.throttle = 0.0
	# Start nitro above NITRO_MIN_AMOUNT, then keep it running until the charge is gone (the car ends it at 0).
	var charged: bool = _car.nitro_amount > 0.0 if _car.nitro_active else _car.nitro_amount > NITRO_MIN_AMOUNT
	# No nitro while a slower car is in follow range: it would arrive too fast to pass it cleanly.
	var fast_enough: bool = _car.nitro_active or _car.speed_kmh >= nitro_min_start_kmh
	inp.nitro = err > nitro_min_gap_ms and charged and fast_enough and is_inf(cap) and _straight_ahead(s)


func _tick_reverse(delta: float) -> void:
	_mode_t += delta
	var inp: VehicleInput = _car.input
	inp.throttle = 0.0
	inp.brake = 1.0
	inp.steer = 0.0
	inp.handbrake = false
	inp.nitro = false
	if _mode_t < reverse_time:
		return
	# Free only if it gained progress since the recovery started and faces along the line.
	var s: float = _track.get_progress(_car.global_position, _last_s)
	# Reversing moves the car back along the line, so the test is distance moved, not forward progress.
	var free: bool = absf(_wrap_signed(s - _anchor_s)) >= stuck_progress_m and _heading_error_deg(s) <= reset_yaw_deg
	if not free:
		_reset_to_line()  # last resort: teleport back onto the line
	_mode = Mode.RACE
	_idle_t = 0.0
	_anchor_s = -1.0


func _heading_error_deg(s: float) -> float:
	var b: Basis = _car.global_transform.basis
	var fwd: Vector3 = Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var t: Vector3 = _track.get_tangent_at(s).normalized()
	return rad_to_deg(acos(clampf(fwd.dot(t), -1.0, 1.0)))


func _reset_to_line() -> bool:
	# Search near the last known progress: parts of the lap pass close to each other.
	var hint: float = _last_s if _last_s >= 0.0 else _anchor_s
	var s0: float = _track.get_progress(_car.global_position, hint) if hint >= 0.0 else _track.get_progress(_car.global_position)
	# Check every candidate, including the last one (previously it could be used unchecked).
	var s: float = s0 + reset_advance_m
	var found: bool = false
	for k: int in range(maxi(reset_probe_tries, 0) + 1):
		if _spot_free(_track.get_point_at(s)):
			found = true
			break
		s += reset_probe_step_m
	if not found:
		# Stay put instead of teleporting into another car. Normal recovery can retry later.
		_clear_pass()
		_shift = 0.0
		_car.input.clear()
		return false
	var c: Vector3 = _track.get_point_at(s)
	var t: Vector3 = _track.get_tangent_at(s)
	var rgt: Vector3 = Vector3(-t.z, 0.0, t.x)
	_clear_pass()
	_shift = 0.0
	_car.reset_to(Transform3D(Basis(rgt, Vector3.UP, -t), c + Vector3.UP * reset_height))
	_last_s = s
	return true


func _spot_free(p: Vector3) -> bool:
	for other: ArcadeCar in _traffic:
		if other == _car or not is_instance_valid(other):
			continue
		var d: Vector3 = other.global_position - p
		d.y = 0.0
		if d.length() < reset_clear_m:
			return false
	return true


## Sensing: every car within sense_range along the line, with its offset from us, its speed and time to
## contact. Fills _near (reused entries, no allocation after the first ticks). Track queries only.
func _sense(s: float, v: float) -> void:
	_near_n = 0
	for other: ArcadeCar in _traffic:
		if other == _car or not is_instance_valid(other):
			continue
		var op: Vector3 = other.global_position
		var so: float = _track.get_progress(op, s)
		var along: float = _wrap_signed(so - s)
		if absf(along) > sense_range:
			continue
		if _near_n == _near.size():
			_near.append(NearCar.new())
		var n: NearCar = _near[_near_n]
		_near_n += 1
		n.car = other
		n.along = along
		n.lat = _lateral_at(op, so)
		n.dl = n.lat - _lat_me
		n.speed = maxf(other.forward_speed, 0.0)
		var closing: float = v - n.speed
		n.ttc = maxf(along - car_length, 0.0) / closing if (along > 0.0 and closing > 0.05) else INF


## Index in _near of the nearest car ahead in our lane band, or -1.
func _lead_index() -> int:
	var best: int = -1
	var best_along: float = INF
	var band: float = car_width + lane_margin
	for i: int in _near_n:
		var n: NearCar = _near[i]
		if n.along > 0.0 and absf(n.dl) < band and n.along < best_along:
			best = i
			best_along = n.along
	return best


## Speed cap from the cars ahead in our lane. Gap rule: match the car ahead at follow_gap, more gap allows more speed.
## Time rule: a car ahead closer than ttc_brake in time is matched in speed, unless a pass to a free side is possible.
func _traffic_cap(v: float) -> float:
	_follow_brake = 0.0
	if _pass_side != SIDE_NONE:
		return INF  # already passing: the lane shift is the answer, not braking behind the car
	var limit: float = INF
	var band: float = car_width + lane_margin
	for i: int in _near_n:
		var n: NearCar = _near[i]
		if n.along <= 0.0 or absf(n.dl) >= band:
			continue
		if n.along <= follow_range:
			limit = minf(limit, n.speed + follow_gain * (n.along - follow_gap))
		if n.ttc < ttc_brake and not (_pass_ok and _pick_side(n.car, n.dl) != SIDE_NONE):
			limit = minf(limit, n.speed)
		var closing: float = v - n.speed
		if closing > 0.0 and not (_pass_ok and _pick_side(n.car, n.dl) != SIDE_NONE):
			_follow_brake = maxf(_follow_brake, closing * closing / (2.0 * maxf(n.along - car_length, 0.05) * follow_decel))
	return limit


## Lane shift state: starts a pass of a slower car ahead, holds the pass, aborts it, or returns to the lane.
func _update_shift(s: float, v: float, delta: float) -> void:
	_cooldown_t = maxf(_cooldown_t - delta, 0.0)
	_zone_curv = _strongest_curv_ahead(s, overtake_range + side_long_range)
	var frozen: bool = (_grid_hold and _race_m < grid_hold_m) or _corner_braking(s, v)
	# Passes start and continue only where the road ahead is not a tight bend (radius above 125 m).
	_pass_ok = not frozen and absf(_zone_curv) < shift_stop_curvature and _cooldown_t <= 0.0
	if frozen:
		return  # no lane change at the grid or while braking into a tight bend: the shift holds
	var want: float = 0.0
	if _pass_side != SIDE_NONE:
		want = _continue_pass(s, delta)
	elif _pass_ok:
		var lead: int = _lead_index()
		if lead >= 0:
			var n: NearCar = _near[lead]
			if n.along < overtake_range and n.speed < v - 1.0:
				var side: int = _pick_side(n.car, n.dl)
				if side != SIDE_NONE:
					_pass_side = side
					_pass_car = n.car
					_pass_anchor = _lat_me
					_pass_t = 0.0
					want = float(side) * overtake_shift
	# Moving out of the lane is damped by the bend curvature (none here: the pass is refused above);
	# returning to the lane is always at full rate, so a shift is never held into a bend.
	_shift = move_toward(_shift, want, shift_rate * delta)


## One tick of a pass in progress. Returns the wanted shift. Ends the pass when the car is behind us,
## aborts it (back behind the car) when the target side fills or the pass runs too long.
func _continue_pass(s: float, delta: float) -> float:
	_pass_t += delta
	if not is_instance_valid(_pass_car):
		_clear_pass()
		return 0.0
	var along_b: float = _wrap_signed(_track.get_progress(_pass_car.global_position, s) - s)
	if along_b < -side_long_range:
		_clear_pass()  # passed: back to the lane
		return 0.0
	var bend: bool = absf(_zone_curv) >= shift_stop_curvature
	if _pass_t >= pass_timeout_s or bend or not _side_free(_pass_side, _pass_anchor, _pass_car):
		_clear_pass()
		_cooldown_t = pass_cooldown_s  # abort: fall back behind
		return 0.0
	return float(_pass_side) * overtake_shift


func _clear_pass() -> void:
	_pass_side = SIDE_NONE
	_pass_car = null
	_pass_t = 0.0


## Side for passing the car at lateral offset dl (relative to us): the side away from it first. SIDE_NONE if neither is passable.
func _pick_side(blocker: ArcadeCar, dl: float) -> int:
	var prefer: int = -1 if dl >= 0.0 else 1
	if _side_passable(prefer, _lat_me, blocker):
		return prefer
	if _side_passable(-prefer, _lat_me, blocker):
		return -prefer
	return SIDE_NONE


## A pass to this side may start: the target offset keeps kerb_margin from the kerb, and the side is free for
## the whole manoeuvre. (The bend check is in _update_shift: no pass while the zone ahead is a bend at shift_stop_curvature or tighter.)
func _side_passable(side: int, anchor: float, blocker: ArcadeCar) -> bool:
	if absf(anchor + float(side) * overtake_shift) > _track.width * 0.5 - kerb_margin:
		return false
	return _side_free(side, anchor, blocker)


## True when no sensed car other than `exclude` is on the target side: its centre would be closer than
## car_width + side_clearance to the target offset, within the manoeuvre window (behind to ahead).
func _side_free(side: int, anchor: float, exclude: ArcadeCar) -> bool:
	var target: float = anchor + float(side) * overtake_shift
	var need: float = car_width + side_clearance
	for i: int in _near_n:
		var n: NearCar = _near[i]
		if n.car == exclude:
			continue
		if n.along < -(side_long_range + SIDE_BEHIND_M) or n.along > overtake_range + side_long_range:
			continue
		if absf(n.lat - target) < need:
			return false
	return true


## Lane target kept clear of cars alongside: never steer toward a car that overlaps longitudinally, and keep
## side_clearance from it. Then the kerb limit (edge_margin inside the kerb line).
func _clamp_lane(lane: float) -> float:
	var need: float = car_width + side_clearance
	var lo: float = -INF
	var hi: float = INF
	for i: int in _near_n:
		var n: NearCar = _near[i]
		if absf(n.along) >= side_long_range:
			continue
		if n.dl >= 0.0:
			hi = minf(hi, _lat_me + n.dl - need)
		else:
			lo = maxf(lo, _lat_me + n.dl + need)
	var out: float = lane
	if lo > hi:
		out = _lat_me  # cars on both sides: hold the current offset
	else:
		out = clampf(out, lo, hi)
	return clampf(out, -_lane_limit, _lane_limit)


## True while the road ahead brakes hard into a bend: target speed at corner_hold_m ahead is below our speed and
## the curvature in that stretch reaches corner_hold_curvature. Lane changes are frozen then (rule e).
func _corner_braking(s: float, v: float) -> bool:
	if _track.get_target_speed(s + corner_hold_m) > v - CORNER_BRAKE_MS:
		return false
	return absf(_strongest_curv_ahead(s, corner_hold_m)) >= corner_hold_curvature


## Signed curvature of largest magnitude from s to s + dist, sampled every CORNER_SAMPLE_M.
func _strongest_curv_ahead(s: float, dist: float) -> float:
	var best: float = 0.0
	var d: float = 0.0
	while d <= dist:
		var k: float = _track.get_curvature(s + d)
		if absf(k) > absf(best):
			best = k
		d += CORNER_SAMPLE_M
	return best


## Target speed factor: up to +rubber_band_max when the reference car is far ahead of us, down to
## -rubber_band_max when we are far ahead. Uses race distance, so laps count. Never raises the top speed (checked in _drive).
func get_rubber_band() -> float:
	if not _has_reference or rubber_band_gap <= 0.0:
		return 1.0
	var amount: float = clampf((absf(_reference_gap) - rubber_band_gap) / rubber_band_gap, 0.0, 1.0)
	if _reference_gap > 0.0:
		return 1.0 + rubber_band_max * amount
	return 1.0 - rubber_band_max * amount


## Lane bias toward the inside of a tight bend (curvature positive = right turn, so the inside is +lateral).
func _bend_bias(s: float) -> float:
	var k: float = _track.get_curvature(s)
	var amount: float = clampf((absf(k) - bend_bias_start) / (bend_bias_full - bend_bias_start), 0.0, 1.0)
	return signf(k) * amount * bend_bias_m


## True when the road stays under nitro_max_curvature for nitro_look_m ahead of s (sampled every 10 m).
func _straight_ahead(s: float) -> bool:
	var d: float = 0.0
	while d <= nitro_look_m:
		if absf(_track.get_curvature(s + d)) >= nitro_max_curvature:
			return false
		d += 10.0
	return true


func _lateral_at(world: Vector3, s: float) -> float:
	var c: Vector3 = _track.get_point_at(s)
	var t: Vector3 = _track.get_tangent_at(s)
	return Vector3(world.x - c.x, 0.0, world.z - c.z).dot(Vector3(-t.z, 0.0, t.x))


## Signed distance along the loop, wrapped into half a lap either way.
func _wrap_signed(d: float) -> float:
	var half: float = _track.length * 0.5
	return fposmod(d + half, _track.length) - half


## Smooth noise in -1..1 from two sines with a per-driver phase.
func _noise(index: int) -> float:
	var p: float = _phase[index]
	var w: float = noise_rate * _time
	return NOISE_MAIN_WEIGHT * sin(w + p) + (1.0 - NOISE_MAIN_WEIGHT) * sin(NOISE_HARMONIC * w + NOISE_PHASE_STEP * p)


