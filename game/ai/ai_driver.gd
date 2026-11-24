class_name AIDriver
extends Node
## Racing AI for one ArcadeCar, added as a child of the car. Pure pursuit to a look-ahead point on
## the racing line shifted by the lane offset, a speed controller on the track target speed, lane
## shifts to pass slower cars, stuck recovery and a bounded rubber band. Writes car.input every
## physics tick. Forward is -Z. Every tunable is an export.

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
@export var nitro_min_gap_ms: float = 10.0  ## m/s (36 km/h): nitro only when this far below the target speed
@export var nitro_max_curvature: float = 0.004  ## 1/m, straights only (radius above 250 m)
@export var overtake_range: float = 20.0  ## m, a slower car this close ahead in our lane is passed
@export var overtake_shift: float = 2.5  ## m lane shift to pass
@export var shift_rate: float = 1.5  ## m/s that the lane shift moves
@export var block_lane_width: float = 3.0  ## m, cars within this lateral distance share a lane
@export var side_long_range: float = 7.0  ## m, a car this close along the track counts as alongside
@export var side_lat_range: float = 3.2  ## m, lateral distance that counts as alongside
@export var edge_margin: float = 1.5  ## m, lane offsets stay this far inside the track edge
@export var rubber_band_max: float = 0.08  ## largest change of target speed from the rubber band
@export var rubber_band_gap: float = 150.0  ## m, the gap where the rubber band starts and grows to full
@export var brake_noise: float = 0.04  ## fraction of target speed: moves braking points earlier or later
@export var steer_noise: float = 0.03  ## steering input units, smooth noise so drivers differ
@export var noise_rate: float = 0.7  ## 1/s
@export var noise_seed: int = 1  ## set per driver (RaceManager uses the grid slot) so the noise phases differ
@export var stuck_speed_kmh: float = 5.0
@export var stuck_time: float = 2.5  ## s under stuck_speed_kmh while racing before recovery starts
@export var reverse_time: float = 1.5  ## s of reversing before checking whether the car is free
@export var reset_height: float = 0.47  ## car origin height used when placing it back on the line

var stuck_count: int = 0  ## recovery starts so far

var _track: Track
var _car: ArcadeCar
var _traffic: Array[ArcadeCar] = []
var _racing: bool = false
var _mode: Mode = Mode.RACE
var _mode_t: float = 0.0
var _stuck_t: float = 0.0
var _shift: float = 0.0
var _last_s: float = -1.0
var _time: float = 0.0
var _phase: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _lane_limit: float = 0.0
var _reference_gap: float = 0.0  ## m of race distance, reference car minus this car (positive = it is ahead)
var _has_reference: bool = false


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
	_stuck_t = 0.0


## Cars around this one, for overtaking and side clearance.
func set_traffic(cars: Array[ArcadeCar]) -> void:
	_traffic = cars


## Race distance gap to the reference car (the player) in m, from RaceManager's unwrapped distances.
## Positive = the reference is ahead. Without a call the rubber band is neutral.
func set_reference_gap(gap: float) -> void:
	_reference_gap = gap
	_has_reference = true


## While false the car is only braked gently and the stuck detector is off.
func set_racing(on: bool) -> void:
	_racing = on
	_mode = Mode.RACE
	_stuck_t = 0.0


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
	_stuck_t = _stuck_t + delta if _car.speed_kmh < stuck_speed_kmh else 0.0
	if _stuck_t >= stuck_time:
		_mode = Mode.REVERSE
		_mode_t = 0.0
		_stuck_t = 0.0
		stuck_count += 1
		_tick_reverse(delta)
		return
	var v: float = maxf(_car.forward_speed, 0.0)
	_update_shift(s, _lateral_at(pos, s), delta)
	var lane: float = clampf(lane_offset + _shift, -_lane_limit, _lane_limit)
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
	want = minf(want, top_ms)
	var err: float = want - v
	inp.steer = steer
	inp.handbrake = false
	if err >= 0.0:
		inp.throttle = clampf(err * throttle_gain, 0.0, 1.0)
		inp.brake = 0.0
	else:
		inp.throttle = 0.0
		inp.brake = clampf(-err * brake_gain, 0.0, 1.0)
	inp.nitro = err > nitro_min_gap_ms \
		and absf(_track.get_curvature(ahead)) < nitro_max_curvature \
		and _car.nitro_amount > NITRO_MIN_AMOUNT


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
	if _car.speed_kmh < stuck_speed_kmh:
		_reset_to_line()
	_mode = Mode.RACE
	_stuck_t = 0.0


func _reset_to_line() -> void:
	var s: float = _track.get_progress(_car.global_position)
	var c: Vector3 = _track.get_point_at(s)
	var t: Vector3 = _track.get_tangent_at(s)
	var rgt: Vector3 = Vector3(-t.z, 0.0, t.x)
	var lane: float = clampf(lane_offset + _shift, -_lane_limit, _lane_limit)
	_car.reset_to(Transform3D(Basis(rgt, Vector3.UP, -t), c + rgt * lane + Vector3.UP * reset_height))
	_last_s = -1.0


## Lane shift to pass a slower car ahead in our lane, away from a car alongside on that side.
func _update_shift(s: float, lat_me: float, delta: float) -> void:
	var want: float = 0.0
	var left_busy: bool = false
	var right_busy: bool = false
	var blocked: bool = false
	var blocker_dl: float = 0.0
	var my_speed: float = _car.forward_speed
	for other: ArcadeCar in _traffic:
		if other == _car or not is_instance_valid(other):
			continue
		var op: Vector3 = other.global_position
		var so: float = _track.get_progress(op, s)
		var along: float = _wrap_signed(so - s)
		var dl: float = _lateral_at(op, so) - lat_me
		if absf(along) < side_long_range and absf(dl) < side_lat_range:
			if dl > 0.0:
				right_busy = true
			else:
				left_busy = true
		if not blocked and along > 0.0 and along < overtake_range \
				and absf(dl) < block_lane_width and other.forward_speed < my_speed - 1.0:
			blocked = true
			blocker_dl = dl
	if blocked:
		var prefer: int = -1 if blocker_dl >= 0.0 else 1
		var prefer_busy: bool = left_busy if prefer < 0 else right_busy
		var other_busy: bool = right_busy if prefer < 0 else left_busy
		if not prefer_busy:
			want = float(prefer) * overtake_shift
		elif not other_busy:
			want = float(-prefer) * overtake_shift
	_shift = move_toward(_shift, want, shift_rate * delta)


## Target speed factor: up to +rubber_band_max when the reference car is far ahead of us, down to
## -rubber_band_max when we are far ahead. Uses race distance, so laps count. Never raises the top speed (checked in _drive).
func get_rubber_band() -> float:
	if not _has_reference or rubber_band_gap <= 0.0:
		return 1.0
	var amount: float = clampf((absf(_reference_gap) - rubber_band_gap) / rubber_band_gap, 0.0, 1.0)
	if _reference_gap > 0.0:
		return 1.0 + rubber_band_max * amount
	return 1.0 - rubber_band_max * amount


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
