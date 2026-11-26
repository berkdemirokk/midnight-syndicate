extends "res://tests/test_case.gd"
## Handling feel numbers for the Sable: launch, top speed, braking, skidpad, load transfer,
## steering, drift control, landing. Every number is a metric and also printed (HANDLING ...).

const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const FlatWorld = preload("res://tests/helpers/flat_world.gd")
const HZ: float = 60.0
const G: float = 9.8


func _spawn(x: float, z: float = 0.0, y: float = 0.47) -> ArcadeCar:
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
	return car


func _say(key: String, value: float) -> void:
	metric(key, value)
	print("HANDLING %s = %.3f" % [key, value])


func _hold(car: ArcadeCar, kmh: float) -> void:
	car.input.throttle = clampf(0.5 + (kmh - car.speed_kmh) * 0.02, 0.0, 1.0)


func _run_to(car: ArcadeCar, kmh: float) -> void:
	var guard: int = 0
	car.input.throttle = 1.0
	while car.speed_kmh < kmh and guard < 60 * 40:
		await frames(1)
		guard += 1


func test_launch_and_top_speed() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(0.0)
	car.input.throttle = 1.0
	var t100: float = -1.0
	var top: float = 0.0
	var wander: float = 0.0
	for tick: int in 60 * 45:
		await frames(1)
		if t100 < 0.0 and car.speed_kmh >= 100.0:
			t100 = float(tick + 1) / HZ
		top = maxf(top, car.speed_kmh)
		wander = maxf(wander, absf(car.global_position.x))
	_say("accel_0_100_s", t100)
	_say("top_speed_kmh", top)
	check_range(t100, 3.6, 4.4, "0-100 km/h (s)")
	check_range(top, 274.0, 298.0, "top speed (km/h)")
	check(wander < 1.0, "straight line wander %.2f m" % wander)
	await cleanup([car, ground])


func test_braking_and_pitch() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(0.0)
	await _run_to(car, 100.0)
	car.input.throttle = 0.0
	car.input.brake = 1.0
	var p0: Vector3 = car.global_position
	var front_c: float = 0.0
	var rear_c: float = 0.0
	var stopped: bool = false
	for tick: int in 60 * 10:
		await frames(1)
		if tick == 30:
			front_c = (car.wheel_compression[0] + car.wheel_compression[1]) * 0.5
			rear_c = (car.wheel_compression[2] + car.wheel_compression[3]) * 0.5
		if car.speed_kmh < 0.5:
			stopped = true
			break
	var dist: float = Vector2(car.global_position.x - p0.x, car.global_position.z - p0.z).length()
	_say("brake_100_0_m", dist)
	_say("brake_front_comp", front_c)
	_say("brake_rear_comp", rear_c)
	check(stopped, "did not stop")
	check_range(dist, 28.0, 36.0, "100-0 braking distance (m)")
	check(front_c > rear_c + 0.05, "braking: front %.2f not above rear %.2f (load transfer)" % [front_c, rear_c])
	await cleanup([car, ground])

	# Acceleration shifts load to the rear.
	ground = FlatWorld.make_ground(0.0)
	add(ground)
	car = _spawn(0.0)
	car.input.throttle = 1.0
	await frames(60)
	var fc: float = (car.wheel_compression[0] + car.wheel_compression[1]) * 0.5
	var rc: float = (car.wheel_compression[2] + car.wheel_compression[3]) * 0.5
	_say("accel_front_comp", fc)
	_say("accel_rear_comp", rc)
	check(rc > fc, "acceleration: rear %.2f not above front %.2f" % [rc, fc])
	await cleanup([car, ground])


func test_skidpad() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var best_g: float = 0.0
	var max_slip: float = 0.0
	var max_yaw: float = 0.0
	var outside_ok: bool = true
	var xs: Array[float] = [0.0, 100.0, 200.0]
	var speeds: Array[float] = [70.0, 110.0, 160.0]
	for k: int in 3:
		var car: ArcadeCar = _spawn(xs[k])
		car.input.steer = 1.0
		var guard: int = 0
		while car.speed_kmh < speeds[k] and guard < 60 * 30:
			_hold(car, speeds[k])
			await frames(1)
			guard += 1
		for tick: int in 60 * 4:
			_hold(car, speeds[k])
			await frames(1)
		var lat_sum: float = 0.0
		var n: int = 0
		var prev_v: Vector3 = car.linear_velocity
		var out_c: float = 0.0
		var in_c: float = 0.0
		for tick: int in 60 * 2:
			_hold(car, speeds[k])
			await frames(1)
			var dv: Vector3 = car.linear_velocity - prev_v
			prev_v = car.linear_velocity
			var vh := Vector2(car.linear_velocity.x, car.linear_velocity.z)
			var ah := Vector2(dv.x, dv.z) * HZ
			if vh.length() > 1.0:
				lat_sum += absf(ah.x * vh.y - ah.y * vh.x) / vh.length()
				n += 1
			max_slip = maxf(max_slip, absf(car.drift_angle_deg))
			max_yaw = maxf(max_yaw, absf(car.angular_velocity.y))
			# steering right: right wheels (1, 3) are inside
			out_c += car.wheel_compression[0] + car.wheel_compression[2]
			in_c += car.wheel_compression[1] + car.wheel_compression[3]
		var g_val: float = (lat_sum / maxf(float(n), 1.0)) / G
		_say("skidpad_%d_kmh_lat_g" % int(speeds[k]), g_val)
		best_g = maxf(best_g, g_val)
		if out_c <= in_c:
			outside_ok = false
		await cleanup([car])
	_say("skidpad_best_lat_g", best_g)
	_say("skidpad_max_slip_deg", max_slip)
	check_range(best_g, 1.0, 1.7, "skidpad lateral g")
	check(max_yaw < 1.4, "skidpad yaw rate %.2f rad/s: spin" % max_yaw)
	check(max_slip < 25.0, "skidpad slip %.1f deg" % max_slip)
	check(outside_ok, "cornering: outside wheels not more loaded than inside")
	await cleanup([ground])


func test_steering_feel() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(0.0)
	car.input.steer = 1.0
	await frames(60)
	var lock_slow: float = rad_to_deg(absf(car.steer_angle_rad))
	car.input.steer = 0.0
	var t_return: float = -1.0
	for tick: int in 60:
		await frames(1)
		if rad_to_deg(absf(car.steer_angle_rad)) < lock_slow * 0.1:
			t_return = float(tick + 1) / HZ
			break
	await _run_to(car, 200.0)
	car.input.steer = 1.0
	_hold(car, 200.0)
	await frames(60)
	var lock_fast: float = rad_to_deg(absf(car.steer_angle_rad))
	_say("steer_lock_slow_deg", lock_slow)
	_say("steer_lock_200_deg", lock_fast)
	_say("steer_return_to_10pct_s", t_return)
	check(lock_fast < lock_slow * 0.45, "speed sensitive steering: %.1f vs %.1f deg" % [lock_fast, lock_slow])
	check(t_return > 0.0 and t_return < 0.45, "steering return too slow: %.2f s" % t_return)
	await cleanup([car, ground])


func test_drift_control() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(0.0)
	await _run_to(car, 110.0)
	car.input.throttle = 0.0
	car.input.handbrake = true
	car.input.steer = 1.0
	await frames(30)
	car.input.handbrake = false
	car.input.throttle = 0.8
	var held: int = 0
	var max_angle: float = 0.0
	var max_yaw: float = 0.0
	var min_speed: float = 999.0
	var angles: Array[float] = []
	for tick: int in 60 * 4:
		# a human counter-steers: simple controller holding about 25 deg
		var a: float = car.drift_angle_deg
		var st: float = clampf((25.0 - absf(a)) * 0.05, -1.0, 1.0)
		car.input.steer = (signf(st) * maxf(absf(st), 0.2)) * (signf(a) if a != 0.0 else 1.0)  # a hand is never exactly neutral
		await frames(1)
		var s: float = absf(car.drift_angle_deg)
		if car.is_drifting and s > 12.0 and s < 50.0:
			held += 1
		max_angle = maxf(max_angle, s)
		max_yaw = maxf(max_yaw, absf(car.angular_velocity.y))
		min_speed = minf(min_speed, car.speed_kmh)
		if tick % 30 == 0:
			angles.append(s)
	_say("drift_held_s_of_4", float(held) / HZ)
	_say("drift_max_angle_deg", max_angle)
	_say("drift_max_yaw", max_yaw)
	_say("drift_min_speed_kmh", min_speed)
	check(float(held) / HZ > 2.5, "drift held only %.2f s of 4" % (float(held) / HZ))
	check(max_angle < 52.0, "drift angle %.1f: spin" % max_angle)
	# throttle modulation: lift off then the angle shrinks smoothly, no snap
	car.input.steer = 0.0
	car.input.throttle = 0.0
	var prev: float = absf(car.drift_angle_deg)
	var max_jump: float = 0.0
	var t_straight: float = -1.0
	for tick: int in 60 * 3:
		await frames(1)
		var s2: float = absf(car.drift_angle_deg)
		max_jump = maxf(max_jump, absf(s2 - prev))
		prev = s2
		if t_straight < 0.0 and s2 < 6.0:
			t_straight = float(tick + 1) / HZ
	_say("drift_exit_straight_s", t_straight)
	_say("drift_exit_max_deg_per_tick", max_jump)
	check(t_straight > 0.0 and t_straight < 2.5, "drift exit took %.2f s" % t_straight)
	check(max_jump < 6.0, "drift exit snapped %.1f deg/tick" % max_jump)
	await cleanup([car, ground])


func test_landing() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car: ArcadeCar = _spawn(0.0, 0.0, 4.0)
	car.rotation_degrees = Vector3(-25.0, 0.0, 12.0)
	car.linear_velocity = Vector3(0.0, 0.0, -30.0)
	await frames(180)
	var up_dot: float = car.global_transform.basis.y.dot(Vector3.UP)
	_say("landing_upright_dot", up_dot)
	check(up_dot > 0.97, "car not upright after landing: %.3f" % up_dot)
	check(car.is_grounded, "car not grounded after landing")
	await cleanup([car, ground])
