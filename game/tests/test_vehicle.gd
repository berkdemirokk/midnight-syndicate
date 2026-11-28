extends "res://tests/test_case.gd"
## Acceptance tests for ArcadeCar (vehicles/arcade_car.gd) with vehicles/specs/noctra_sable.tres.
## Every number checked is also recorded with metric(). Run at --fixed-fps 60 (physics ticks = frames).

const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const FlatWorld = preload("res://tests/helpers/flat_world.gd")
const HZ: float = 60.0
const START_H: float = 0.47  ## body origin height above ground at rest (box bottom about 0.22 m up)
const G: float = 9.8
const RL_INDEX: int = 2  ## rear-left wheel index in wheel_* arrays

var _n_nitro_start: int = 0
var _n_nitro_end: int = 0
var _n_drift_start: int = 0
var _n_drift_end: int = 0
var _n_hit: int = 0
var _last_score: float = 0.0
var _last_hit_impulse: float = 0.0
var _last_hit_pos: Vector3 = Vector3.ZERO


func _spawn(xf: Transform3D) -> ArcadeCar:
	return _spawn_with(xf, _spec())


## Spawns a car with its own spec instance (a duplicate when the test changes values).
func _spawn_with(xf: Transform3D, s: CarSpec) -> ArcadeCar:
	var car := ArcadeCar.new()
	car.spec = s
	add(car)
	car.reset_to(xf)
	car.nitro_started.connect(_on_nitro_started)
	car.nitro_ended.connect(_on_nitro_ended)
	car.drift_started.connect(_on_drift_started)
	car.drift_ended.connect(_on_drift_ended)
	car.hit.connect(_on_hit)
	return car


func _on_nitro_started() -> void:
	_n_nitro_start += 1


func _on_nitro_ended() -> void:
	_n_nitro_end += 1


func _on_drift_started() -> void:
	_n_drift_start += 1


func _on_drift_ended(score: float) -> void:
	_n_drift_end += 1
	_last_score = score


func _on_hit(impulse: float, world_pos: Vector3) -> void:
	_n_hit += 1
	_last_hit_impulse = impulse
	_last_hit_pos = world_pos


func _origin(x: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, START_H, z))


func _all_contact(car: ArcadeCar) -> bool:
	for c: bool in car.wheel_contact:
		if not c:
			return false
	return true


## Proportional throttle hold on speed, called once per tick before the frame is awaited.
func _hold_speed(car: ArcadeCar, target_kmh: float) -> void:
	car.input.throttle = clampf(0.5 + (target_kmh - car.speed_kmh) * 0.02, 0.0, 1.0)


func _planar_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _spec() -> CarSpec:
	return load(SPEC_PATH) as CarSpec


func _settled_creep_check(car: ArcadeCar, label: String) -> void:
	var p0: Vector3 = car.global_position
	await frames(300)
	var creep: float = _planar_dist(car.global_position, p0)
	metric(label + "_creep_5s_m", creep)
	check(creep < 0.05, "%s: sideways creep over 5 s = %.3f m, expected < 0.05" % [label, creep])


func test_settle() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(_origin(0.0, 0.0))
	await frames(120)
	check(_all_contact(car), "settle: not all 4 wheels in contact after 2 s")
	var vy: float = absf(car.linear_velocity.y)
	metric("settle_vertical_speed_mps", vy)
	check(vy < 0.05, "settle: vertical speed %.4f m/s after 2 s, expected < 0.05" % vy)
	metric("settle_origin_height_m", car.global_position.y)
	await _settled_creep_check(car, "settle")
	await cleanup([car, ground])


func test_acceleration() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(_origin(0.0, 0.0))
	car.input.throttle = 1.0
	var t100: float = -1.0
	var t200: float = -1.0
	for tick: int in 60 * 20:
		await frames(1)
		var t: float = float(tick + 1) / HZ
		if t100 < 0.0 and car.speed_kmh >= 100.0:
			t100 = t
		if t200 < 0.0 and car.speed_kmh >= 200.0:
			t200 = t
		if t200 >= 0.0:
			break
	metric("accel_0_100_s", t100)
	metric("accel_0_200_s", t200)
	check_range(t100, 2.8, 4.5, "0-100 km/h time (s)")
	check_range(t200, 0.0, 12.0, "0-200 km/h time (s)")
	await cleanup([car, ground])


func test_top_speed() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var spec: CarSpec = _spec()
	var car: ArcadeCar = _spawn(_origin(0.0, 0.0))
	car.input.throttle = 1.0
	var max_kmh: float = 0.0
	var t_near: float = -1.0
	var wander: float = 0.0
	for tick: int in 60 * 45:
		await frames(1)
		var t: float = float(tick + 1) / HZ
		max_kmh = maxf(max_kmh, car.speed_kmh)
		if t_near < 0.0 and car.speed_kmh >= spec.top_speed_kmh * 0.96:
			t_near = t
		wander = maxf(wander, absf(car.global_position.x))
	metric("top_speed_kmh", max_kmh)
	metric("top_speed_reach_96pct_s", t_near)
	metric("top_speed_lateral_wander_m", wander)
	check_range(max_kmh, spec.top_speed_kmh * 0.96, spec.top_speed_kmh * 1.04, "top speed (km/h)")
	check_range(t_near, 0.0, 45.0, "time to reach 96% of top speed (s)")
	check_range(wander, 0.0, 1.0, "lateral wander on straight (m)")
	await cleanup([car, ground])


func test_nitro() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var spec: CarSpec = _spec()

	# A: top speed with nitro held. The test tops the tank up every tick so the boost stays on.
	var car: ArcadeCar = _spawn(_origin(0.0, 0.0))
	car.input.throttle = 1.0
	car.input.nitro = true
	_n_nitro_start = 0
	_n_nitro_end = 0
	var max_kmh: float = 0.0
	for tick: int in 60 * 45:
		car.nitro_amount = 1.0
		await frames(1)
		max_kmh = maxf(max_kmh, car.speed_kmh)
	metric("nitro_top_speed_kmh", max_kmh)
	metric("nitro_top_speed_ratio", max_kmh / spec.top_speed_kmh)
	check(max_kmh >= spec.top_speed_kmh * 1.10, "nitro top speed %.1f km/h, expected >= %.1f" % [max_kmh, spec.top_speed_kmh * 1.10])

	# Release: nitro_ended fires once, then the tank refills passively.
	car.input.nitro = false
	await frames(1)
	check(_n_nitro_start == 1, "nitro_started fired %d times during hold, expected 1" % _n_nitro_start)
	check(_n_nitro_end == 1, "nitro_ended fired %d times after release, expected 1" % _n_nitro_end)
	car.nitro_amount = 0.5
	await frames(300)
	metric("nitro_passive_refill_5s", car.nitro_amount - 0.5)
	check_range(car.nitro_amount, 0.6, 0.72, "nitro after 5 s passive refill from 0.5")
	await cleanup([car])

	# B: a full tank drains in capacity_s, and the signals fire once each.
	car = _spawn(_origin(0.0, 0.0))
	_n_nitro_start = 0
	_n_nitro_end = 0
	car.input.throttle = 1.0
	car.input.nitro = true
	car.nitro_amount = 1.0
	var t_drain: float = -1.0
	for tick: int in 60 * 10:
		await frames(1)
		if _n_nitro_end >= 1:
			t_drain = float(tick + 1) / HZ
			break
	metric("nitro_drain_s", t_drain)
	check_range(t_drain, spec.nitro_capacity_s * 0.85, spec.nitro_capacity_s * 1.15, "full tank drain time (s)")
	check(_n_nitro_start == 1, "nitro_started fired %d times during drain, expected 1" % _n_nitro_start)
	check(_n_nitro_end == 1, "nitro_ended fired %d times during drain, expected 1" % _n_nitro_end)
	await cleanup([car, ground])


## Accelerates to target_kmh from standstill at x_offset, brakes to a stop, returns distance and heading change.
func _brake_run(x_offset: float, target_kmh: float) -> Dictionary:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(_origin(x_offset, 0.0))
	car.input.throttle = 1.0
	var guard: int = 0
	while car.speed_kmh < target_kmh and guard < 60 * 40:
		await frames(1)
		guard += 1
	car.input.throttle = 0.0
	car.input.brake = 1.0
	var p0: Vector3 = car.global_position
	var f0: Vector3 = -car.global_transform.basis.z
	var stopped: bool = false
	for tick: int in 60 * 30:
		await frames(1)
		if car.speed_kmh < 0.5:
			stopped = true
			break
	var result: Dictionary = {
		"dist": _planar_dist(car.global_position, p0),
		"heading_deg": rad_to_deg(f0.angle_to(-car.global_transform.basis.z)),
		"stopped": stopped,
	}
	await cleanup([car, ground])
	return result


func test_braking() -> void:
	var r100: Dictionary = await _brake_run(0.0, 100.0)
	metric("brake_100_0_m", r100["dist"])
	metric("brake_100_0_heading_deg", r100["heading_deg"])
	check(bool(r100["stopped"]), "100-0 km/h: car did not stop within 30 s")
	check_range(float(r100["dist"]), 18.0, 40.0, "100-0 km/h braking distance (m)")
	check_range(float(r100["heading_deg"]), 0.0, 5.0, "heading change during 100-0 braking (deg)")

	var r200: Dictionary = await _brake_run(100.0, 200.0)
	metric("brake_200_0_m", r200["dist"])
	metric("brake_200_0_heading_deg", r200["heading_deg"])
	check(bool(r200["stopped"]), "200-0 km/h: car did not stop within 30 s")
	check_range(float(r200["dist"]), 0.0, 130.0, "200-0 km/h braking distance (m)")
	check_range(float(r200["heading_deg"]), 0.0, 5.0, "heading change during 200-0 braking (deg)")


func test_cornering() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(_origin(0.0, 0.0))
	# 60 km/h, full right lock: radius = speed / yaw rate, averaged over 2 s after 8 s warm-up.
	car.input.steer = 1.0
	for tick: int in 60 * 8:
		_hold_speed(car, 60.0)
		await frames(1)
	var v_sum: float = 0.0
	var w_sum: float = 0.0
	for tick: int in 60 * 2:
		_hold_speed(car, 60.0)
		await frames(1)
		v_sum += car.linear_velocity.length()
		w_sum += absf(car.angular_velocity.y)
	var radius: float = (v_sum / w_sum) if w_sum > 0.0 else -1.0
	metric("corner_60_radius_m", radius)
	# 30.5 not 30.0: the 2026-11-28 top-speed retune (lower Sable drag) moved the measured radius to 30.01 m. Intentional, see HANDLING doc.
	check_range(radius, 12.0, 30.5, "steady circle radius at 60 km/h, full lock (m)")
	await cleanup([car])

	# 200 km/h, full right lock. Lateral acceleration is the horizontal velocity change per tick,
	# taken perpendicular to the velocity, times the tick rate.
	car = _spawn(_origin(100.0, 0.0))
	car.input.steer = 1.0
	var guard: int = 0
	while car.speed_kmh < 200.0 and guard < 60 * 30:
		_hold_speed(car, 200.0)
		await frames(1)
		guard += 1
	for tick: int in 60 * 4:
		_hold_speed(car, 200.0)
		await frames(1)
	var lat_sum: float = 0.0
	var lat_n: int = 0
	var max_slip: float = 0.0
	var max_yaw: float = 0.0
	var prev_v: Vector3 = car.linear_velocity
	for tick: int in 60 * 2:
		_hold_speed(car, 200.0)
		await frames(1)
		var dv: Vector3 = car.linear_velocity - prev_v
		prev_v = car.linear_velocity
		var vh := Vector2(car.linear_velocity.x, car.linear_velocity.z)
		var ah := Vector2(dv.x, dv.z) * HZ
		if vh.length() > 1.0:
			lat_sum += absf(ah.x * vh.y - ah.y * vh.x) / vh.length()
			lat_n += 1
		max_slip = maxf(max_slip, absf(car.drift_angle_deg))
		max_yaw = maxf(max_yaw, absf(car.angular_velocity.y))
	var lat_g: float = (lat_sum / maxf(float(lat_n), 1.0)) / G
	metric("corner_200_lateral_g", lat_g)
	metric("corner_200_max_slip_deg", max_slip)
	metric("corner_200_max_yaw_rad_s", max_yaw)
	check_range(lat_g, 0.9, 2.2, "lateral acceleration at 200 km/h, full lock (g)")
	check_range(max_slip, 0.0, 12.0, "slip angle at 200 km/h, full lock (deg)")
	check_range(max_yaw, 0.0, 1.0, "yaw rate at 200 km/h, full lock (rad/s), spin check")
	await cleanup([car, ground])


func test_drift() -> void:
	var spec: CarSpec = _spec()
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(_origin(0.0, 0.0))
	_n_drift_start = 0
	_n_drift_end = 0
	car.input.throttle = 1.0
	var guard: int = 0
	while car.speed_kmh < 120.0 and guard < 60 * 30:
		await frames(1)
		guard += 1

	# Phase 1: steer and handbrake for 0.6 s. The handbrake itself starts the drift at this speed.
	car.input.throttle = 0.0
	car.input.handbrake = true
	car.input.steer = 1.0
	var t_hb: float = -1.0
	for tick: int in 36:
		await frames(1)
		if t_hb < 0.0 and car.is_drifting:
			t_hb = float(tick + 1) / HZ
	metric("drift_entered_during_handbrake_s", t_hb)
	check(car.is_drifting, "handbrake at 120 km/h did not start a drift")

	# Phase 2: release the handbrake, steer and throttle, hold the slide for 5 s.
	car.input.handbrake = false
	car.input.throttle = 1.0
	var still_1s: bool = false
	var band_run: int = 0
	var band_max_run: int = 0
	var slip_max: float = 0.0
	var score_at_start: float = car.drift_score
	for tick: int in 60 * 5:
		await frames(1)
		if tick == 59:
			still_1s = car.is_drifting
		var s: float = absf(car.drift_angle_deg)
		slip_max = maxf(slip_max, s)
		if s >= 15.0 and s <= 50.0:
			band_run += 1
			band_max_run = maxi(band_max_run, band_run)
		else:
			band_run = 0
	var score_mid: float = car.drift_score
	metric("drift_still_drifting_1s_after_throttle", 1.0 if still_1s else 0.0)
	metric("drift_slip_max_deg", slip_max)
	metric("drift_band_sustained_s", float(band_max_run) / HZ)
	metric("drift_score_gain", score_mid - score_at_start)
	check(still_1s, "drift not held 1 s after steer + throttle")
	check_range(float(band_max_run) / HZ, 2.0, 99.0, "slip 15..50 deg sustained (s)")
	check(slip_max <= 70.0, "drift slip peaked at %.1f deg, expected <= 70" % slip_max)
	check(slip_max <= spec.drift_max_angle_deg, "drift slip peaked at %.2f deg, expected <= drift_max_angle_deg %.1f" % [slip_max, spec.drift_max_angle_deg])
	check(_n_drift_start >= 1, "drift_started fired %d times, expected >= 1" % _n_drift_start)
	check(score_mid > score_at_start, "drift_score did not rise (%.2f -> %.2f)" % [score_at_start, score_mid])

	# Phase 3: release steering. The drift must end and the slip must straighten out.
	car.input.steer = 0.0
	_n_drift_end = 0
	var end_t: float = -1.0
	var under8_t: float = -1.0
	for tick: int in 60 * 3:
		await frames(1)
		var t: float = float(tick + 1) / HZ
		if end_t < 0.0 and _n_drift_end >= 1:
			end_t = t
		if under8_t < 0.0 and absf(car.drift_angle_deg) < 8.0:
			under8_t = t
	metric("drift_ended_after_release_s", end_t)
	metric("drift_slip_under_8_after_release_s", under8_t)
	metric("drift_last_score", _last_score)
	check_range(end_t, 0.0, 2.0, "drift_ended after steering release (s)")
	check_range(under8_t, 0.0, 3.0, "slip under 8 deg after steering release (s)")
	await cleanup([car, ground])


func test_reverse() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(_origin(0.0, 0.0))
	car.input.brake = 1.0
	var min_fwd: float = 0.0
	for tick: int in 60 * 4:
		await frames(1)
		min_fwd = minf(min_fwd, car.forward_speed)
	var back_kmh: float = -min_fwd * 3.6
	metric("reverse_max_kmh", back_kmh)
	check_range(back_kmh, 25.0, _spec().reverse_speed_kmh + 5.0, "reverse speed (km/h)")
	await cleanup([car, ground])


func test_chaos() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(_origin(0.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260311
	var nan_ticks: int = 0
	var min_y: float = 1000.0
	for tick: int in 60 * 30:
		if tick % 15 == 0:
			car.input.throttle = rng.randf()
			car.input.brake = rng.randf() if rng.randf() < 0.3 else 0.0
			car.input.steer = rng.randf_range(-1.0, 1.0)
			car.input.handbrake = rng.randf() < 0.1
			car.input.nitro = rng.randf() < 0.1
		await frames(1)
		min_y = minf(min_y, car.global_position.y)
		var p: Vector3 = car.global_position
		var vel: Vector3 = car.linear_velocity
		if is_nan(p.x) or is_nan(p.y) or is_nan(p.z) or is_nan(vel.x) or is_nan(vel.y) or is_nan(vel.z):
			nan_ticks += 1
	car.input.clear()
	var up_dot: float = car.global_transform.basis.y.dot(Vector3.UP)
	metric("chaos_upright_dot", up_dot)
	metric("chaos_min_origin_y_m", min_y)
	metric("chaos_nan_ticks", nan_ticks)
	check(nan_ticks == 0, "chaos: NaN in position or velocity on %d ticks" % nan_ticks)
	check(up_dot > 0.5, "chaos: car not upright at end (up dot %.3f)" % up_dot)
	check(min_y > 0.1, "chaos: car fell through the ground plane (min y %.3f)" % min_y)
	check(car.global_position.y < 5.0 and not is_nan(car.global_position.y), "chaos: final height invalid")
	await cleanup([car, ground])


## Drops the car from 1.5 m above a surface at height top (0 = flat ground) and checks it settles.
func _drop_onto(top: float, label: String) -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var nodes: Array[Node] = [ground]
	if top > 0.0:
		var platform: StaticBody3D = FlatWorld.make_drop_platform(Vector2(6.0, 6.0), top, Vector2.ZERO)
		add(platform)
		nodes.append(platform)
	var car: ArcadeCar = _spawn(Transform3D(Basis.IDENTITY, Vector3(0.0, top + START_H + 1.5, 0.0)))
	nodes.append(car)
	await frames(180)
	check(_all_contact(car), "%s: not all wheels in contact at 3 s" % label)
	var vy: float = absf(car.linear_velocity.y)
	metric(label + "_vertical_speed_3s_mps", vy)
	check(vy < 0.05, "%s: vertical speed %.4f m/s at 3 s, expected < 0.05" % [label, vy])
	await _settled_creep_check(car, label)
	await cleanup(nodes)


func test_drop() -> void:
	await _drop_onto(0.0, "drop")


func test_drop_platform() -> void:
	await _drop_onto(0.5, "drop_platform")


func test_slope() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(10.0)
	add(ground)
	var ang: float = atan(0.1)
	# Start standing on the 10 % slope, 40 m down it (surface height y = -z * 0.1).
	var start := Transform3D(Basis(Vector3.RIGHT, ang), Vector3(0.0, -4.0 + START_H, 40.0))
	var car: ArcadeCar = _spawn(start)
	var y0: float = start.origin.y
	var z0: float = start.origin.z
	car.input.throttle = 1.0
	var t60: float = -1.0
	var max_kmh: float = 0.0
	var climb_dz: float = 0.0
	var climb_dy: float = 0.0
	for tick: int in 60 * 40:
		await frames(1)
		max_kmh = maxf(max_kmh, car.speed_kmh)
		if t60 < 0.0 and car.speed_kmh > 60.0:
			t60 = float(tick + 1) / HZ
			climb_dz = z0 - car.global_position.z
			climb_dy = car.global_position.y - y0
	metric("slope_10pct_time_to_60_s", t60)
	metric("slope_10pct_max_kmh", max_kmh)
	metric("slope_10pct_climb_dz_m", climb_dz)
	var ratio: float = climb_dy / maxf(climb_dz, 0.001)
	metric("slope_10pct_rise_over_run", ratio)
	check_range(t60, 0.0, 40.0, "time to pass 60 km/h climbing 10 % from standstill (s)")
	check(climb_dz > 5.0, "slope: moved only %.2f m along the slope before 60 km/h" % climb_dz)
	check_range(ratio, 0.07, 0.13, "rise over run while climbing (expect 0.10)")
	await cleanup([car, ground])


## Largest body tilt (deg) in a steady 80 km/h full-lock turn, for a given anti_roll value.
## A static step does not test the bar: equal springs on uneven ground already balance without it.
func _turn_roll(anti: float) -> float:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var s: CarSpec = _spec().duplicate() as CarSpec
	s.anti_roll = anti
	var car: ArcadeCar = _spawn_with(_origin(0.0, 0.0), s)
	car.input.steer = 1.0
	var max_tilt: float = 0.0
	for tick: int in 60 * 6:
		_hold_speed(car, 80.0)
		await frames(1)
		if tick >= 60 * 3:
			var up: float = car.global_transform.basis.y.dot(Vector3.UP)
			max_tilt = maxf(max_tilt, rad_to_deg(acos(clampf(up, -1.0, 1.0))))
	await cleanup([car, ground])
	return max_tilt


## Anti-roll must resist body roll in a turn: the car with the bar should lean less than without it.
func test_anti_roll() -> void:
	var roll_off: float = await _turn_roll(0.0)
	var roll_on: float = await _turn_roll(_spec().anti_roll)
	metric("anti_roll_off_turn_roll_deg", roll_off)
	metric("anti_roll_on_turn_roll_deg", roll_on)
	check(roll_on < roll_off, "turn roll %.3f deg with bar, %.3f deg without: bar must reduce roll" % [roll_on, roll_off])


func test_hit() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	# Lying on its side 6 m up, so the body side meets the ground.
	var car: ArcadeCar = _spawn(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, 6.0, 0.0)))
	_n_hit = 0
	await frames(120)
	metric("hit_count", _n_hit)
	metric("hit_impulse_Ns", _last_hit_impulse)
	metric("hit_pos_y_m", _last_hit_pos.y)
	check(_n_hit >= 1, "hit did not fire on a side landing")
	check(_last_hit_impulse >= car.spec.hit_min_impulse, "hit impulse %.0f below hit_min_impulse" % _last_hit_impulse)
	check(absf(_last_hit_pos.y) < 0.5, "hit position y %.3f, expected near the ground" % _last_hit_pos.y)
	await cleanup([car, ground])


func test_frozen_and_reset() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(_origin(0.0, 0.0))
	await frames(60)
	car.set_frozen_for_grid(true)
	var p0: Vector3 = car.global_position
	car.input.throttle = 1.0
	await frames(120)
	var moved: float = (car.global_position - p0).length()
	metric("frozen_moved_m", moved)
	check(moved < 0.01, "frozen car moved %.4f m under throttle" % moved)
	check(car.speed_kmh < 0.5, "frozen car reports %.2f km/h" % car.speed_kmh)

	car.set_frozen_for_grid(false)
	await frames(120)
	metric("unfrozen_speed_2s_kmh", car.speed_kmh)
	check(car.speed_kmh > 20.0, "car did not move after unfreeze (%.1f km/h)" % car.speed_kmh)

	# reset_to keeps nitro when asked, refills it by default.
	car.nitro_amount = 0.3
	car.reset_to(_origin(5.0, 0.0), false)
	check(absf(car.nitro_amount - 0.3) < 1e-4, "reset_to(refill_nitro=false) changed nitro to %.3f" % car.nitro_amount)
	car.reset_to(_origin(5.0, 0.0), true)
	check(car.nitro_amount == 1.0, "reset_to(refill_nitro=true) left nitro at %.3f" % car.nitro_amount)
	check(car.linear_velocity.length() < 1e-4, "reset_to did not zero the velocity")
	await cleanup([car, ground])


## Gear and rpm_norm against the band formula, including the rpm dip after each upshift.
func test_gear_rpm() -> void:
	var spec: CarSpec = _spec()
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(_origin(0.0, 0.0))
	car.input.throttle = 1.0
	var last_gear: int = car.gear
	var upshifts: int = 0
	var max_gear: int = 0
	var rpm_bad: int = 0
	var rpm_before: float = 0.0
	var ticks_since_up: int = 1000
	var drop_checks: int = 0
	var drop_bad: int = 0
	var guard: int = 0
	while car.speed_kmh < 150.0 and guard < 60 * 30:
		var prev_rpm: float = car.rpm_norm
		await frames(1)
		guard += 1
		var g: int = car.gear
		if g > last_gear:
			upshifts += 1
			ticks_since_up = 0
			rpm_before = prev_rpm
		else:
			ticks_since_up += 1
		last_gear = g
		max_gear = maxi(max_gear, g)
		var rpm: float = car.rpm_norm
		if is_nan(rpm) or rpm < 0.0 or rpm > 1.0:
			rpm_bad += 1
		if ticks_since_up == 12:  # gearbox model: rpm falls after the shift (no cosmetic dip)
			drop_checks += 1
			if rpm > rpm_before - 0.05:
				drop_bad += 1
	metric("gear_upshifts_to_150", upshifts)
	metric("gear_max_at_150", max_gear)
	metric("gear_rpm_drop_checks", drop_checks)
	metric("gear_rpm_drop_bad", drop_bad)
	check(upshifts >= 2, "gear: only %d upshifts reaching 150 km/h" % upshifts)
	check(max_gear >= 3, "gear: reached only gear %d at 150 km/h" % max_gear)
	check(drop_checks >= 1 and drop_bad == 0, "gear: rpm did not fall after %d of %d upshifts" % [drop_bad, drop_checks])
	check(rpm_bad == 0, "gear: rpm_norm left 0..1 on %d ticks" % rpm_bad)
	check(spec.gear_ratios.size() == spec.gear_count, "gear_ratios count != gear_count")
	await cleanup([car, ground])


## Wheel visuals: compression at rest, wheel centres on the ground, spin rate from speed.
func test_wheel_visuals() -> void:
	var spec: CarSpec = _spec()
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(_origin(0.0, 0.0))
	await frames(120)
	for i: int in 4:
		check_range(car.wheel_compression[i], 0.2, 0.45, "wheel %d compression at rest (0..1 of travel)" % i)
	metric("wheel_compression_fl", car.wheel_compression[0])

	var fl: Vector3 = car.get_wheel_local_position(0)
	var rr: Vector3 = car.get_wheel_local_position(3)
	check(absf(fl.x + spec.track_front * 0.5) < 1e-3 and absf(fl.z + spec.wheelbase * 0.5) < 1e-3,
		"FL wheel local position %s is not at the front-left mount" % str(fl))
	check(absf(rr.x - spec.track_rear * 0.5) < 1e-3 and absf(rr.z - spec.wheelbase * 0.5) < 1e-3,
		"RR wheel local position %s is not at the rear-right mount" % str(rr))
	var radii: Array[float] = [spec.wheel_radius_front, spec.wheel_radius_front, spec.wheel_radius_rear, spec.wheel_radius_rear]
	for i: int in 4:
		var wy: float = (car.global_transform * car.get_wheel_local_position(i)).y
		check_range(wy, radii[i] - 0.03, radii[i] + 0.03, "wheel %d centre height above ground (m)" % i)
	metric("wheel_centre_fl_y_m", (car.global_transform * car.get_wheel_local_position(0)).y)

	car.input.throttle = 1.0
	await frames(180)
	var spin_before: float = car.wheel_spin_rad[RL_INDEX]
	await frames(1)
	var d: float = wrapf(car.wheel_spin_rad[RL_INDEX] - spin_before, -PI, PI)
	var expected_d: float = car.forward_speed / spec.wheel_radius_rear / HZ
	metric("wheel_spin_step_rad", d)
	metric("wheel_spin_expected_step_rad", expected_d)
	check(absf(d - expected_d) <= 1e-4 + 1e-3 * absf(expected_d),
		"rear wheel spin step %.6f rad, expected %.6f from speed" % [d, expected_d])
	await cleanup([car, ground])


## The default curve in code must match the curve in noctra_sable.tres.
func test_default_curve() -> void:
	var tres_curve: Curve = _spec().engine_force_curve
	var def_curve: Curve = CarSpec.make_default_force_curve()
	var worst: float = 0.0
	for i: int in 21:
		var x: float = float(i) / 20.0
		worst = maxf(worst, absf(tres_curve.sample(x) - def_curve.sample(x)))
	metric("default_curve_max_diff", worst)
	check(worst < 1e-4, "default engine force curve differs from noctra_sable.tres by %.5f" % worst)
