class_name ArcadeCar
extends RigidBody3D
## Arcade car on a RigidBody3D: four raycast springs and per-wheel tyre forces. Forward is -Z.
## Spring and tyre forces act at each ray contact, applied as a central force plus the torque
## (contact - centre of mass) x force. Every tunable lives in spec (CarSpec).
## Public names, types and signals are a contract (ARCHITECTURE.md).

signal drift_started
signal drift_ended(score: float)
signal nitro_started
signal nitro_ended
signal hit(impulse: float, world_pos: Vector3)

const WHEEL_COUNT: int = 4
const FL: int = 0
const FR: int = 1
const RL: int = 2
const RR: int = 3
const FRONT_COUNT: int = 2
const KMH_PER_MS: float = 3.6
const DIV_EPS: float = 1e-6  ## numeric guard for normalisation and division by a tiny value, not a tunable
const MIN_DIVISOR: float = 0.01  ## floor for speeds, radii and travel used as divisors, not a tunable
const BODY_LAYER: int = 2
const BODY_MASK: int = 11  ## world 1 + vehicles 2 + props 8
const RAY_MASK: int = 9  ## world 1 + props 8

@export var spec: CarSpec

## Written every physics tick by a driver node (player, AI, police). Never null after _ready.
var input: VehicleInput = VehicleInput.new()

# Read-only state for camera, HUD, VFX, audio, AI:
var speed_kmh: float = 0.0
var forward_speed: float = 0.0  ## m/s along -Z, negative when reversing
var is_grounded: bool = false
var grounded_wheels: int = 0
var is_drifting: bool = false
var drift_angle_deg: float = 0.0  ## signed slip angle of the body
var drift_score: float = 0.0  ## score of the current drift chain
var nitro_amount: float = 1.0  ## 0..1
var nitro_active: bool = false
var gear: int = 1
var rpm_norm: float = 0.0  ## 0..1
var wheel_contact: Array[bool] = [false, false, false, false]  ## FL, FR, RL, RR
var wheel_compression: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])  ## 0..1
var wheel_spin_rad: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var wheel_slip: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])  ## 0..1, for smoke and skid audio
var steer_angle_rad: float = 0.0  ## wheel angle, positive = right

var _gravity: float = 9.8
var _frozen: bool = false
var _mounts: PackedVector3Array = PackedVector3Array()  ## car-local ray origins FL, FR, RL, RR
var _ray: PhysicsRayQueryParameters3D = null
var _hit_point: PackedVector3Array = PackedVector3Array()
var _hit_normal: PackedVector3Array = PackedVector3Array()
var _distance: PackedFloat32Array = PackedFloat32Array()  ## mount to ground along the ray
var _compression: PackedFloat32Array = PackedFloat32Array()  ## spring compression in m, positive = squashed
var _spring: PackedFloat32Array = PackedFloat32Array()  ## spring normal force in N after clamps
var _drift_exit_t: float = 0.0
var _gear_dip_t: float = 0.0


func _ready() -> void:
	if spec == null:
		spec = CarSpec.new()
	if spec.engine_force_curve == null:
		spec.engine_force_curve = CarSpec.make_default_force_curve()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	mass = spec.mass_kg
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = spec.max_contacts_reported
	collision_layer = BODY_LAYER
	collision_mask = BODY_MASK
	_ensure_collider()

	var ray_len: float = spec.suspension_rest + spec.suspension_travel
	var hw_f: float = spec.track_front * 0.5
	var hw_r: float = spec.track_rear * 0.5
	var z_f: float = -spec.wheelbase * 0.5
	var z_r: float = spec.wheelbase * 0.5
	var y: float = spec.mount_height
	_mounts = PackedVector3Array([
		Vector3(-hw_f, y, z_f), Vector3(hw_f, y, z_f),
		Vector3(-hw_r, y, z_r), Vector3(hw_r, y, z_r)])
	_hit_point.resize(WHEEL_COUNT)
	_hit_normal.resize(WHEEL_COUNT)
	_distance.resize(WHEEL_COUNT)
	_compression.resize(WHEEL_COUNT)
	_spring.resize(WHEEL_COUNT)
	for i: int in WHEEL_COUNT:
		_hit_normal[i] = Vector3.UP
		_distance[i] = ray_len

	# Centre of mass: static load sets the ground height at rest, the spec sets the height above it.
	var static_compression: float = mass * _gravity / WHEEL_COUNT / maxf(spec.spring_stiffness, MIN_DIVISOR)
	var ground_local_y: float = y - (spec.suspension_rest - static_compression)
	var cg_z: float = spec.wheelbase * (0.5 - spec.weight_front)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, ground_local_y + spec.center_of_mass_height, cg_z)

	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = RAY_MASK
	_ray.collide_with_areas = false
	var ex: Array[RID] = [get_rid()]
	_ray.exclude = ex


func _ensure_collider() -> void:
	for c: Node in get_children():
		if c is CollisionShape3D:
			return
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = spec.body_size
	cs.shape = box
	add_child(cs)


func _physics_process(delta: float) -> void:
	var b: Basis = global_transform.basis
	var up: Vector3 = b.y
	var fwd_car: Vector3 = -b.z
	var com: Vector3 = global_transform * center_of_mass
	var v: Vector3 = linear_velocity
	var w: Vector3 = angular_velocity
	var v_long: float = v.dot(fwd_car)
	var v_lat: float = v.dot(b.x)
	var speed_ms: float = v.length()
	var kmh: float = speed_ms * KMH_PER_MS
	var top_ms: float = maxf(spec.top_speed_kmh / KMH_PER_MS, MIN_DIVISOR)
	var throttle: float = 0.0
	var brake: float = 0.0
	var steer_in: float = 0.0
	var handbrake: bool = false
	var nitro_key: bool = false
	if not _frozen:
		throttle = clampf(input.throttle, 0.0, 1.0)
		brake = clampf(input.brake, 0.0, 1.0)
		steer_in = clampf(input.steer, -1.0, 1.0)
		handbrake = input.handbrake
		nitro_key = input.nitro

	# 1. Raycast suspension: contact point, normal and distance per wheel.
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_len: float = spec.suspension_rest + spec.suspension_travel
	var grounded: int = 0
	for i: int in WHEEL_COUNT:
		var mount_w: Vector3 = global_transform * _mounts[i]
		_ray.from = mount_w
		_ray.to = mount_w - up * ray_len
		var hit: Dictionary = space.intersect_ray(_ray)
		wheel_contact[i] = not hit.is_empty()
		if wheel_contact[i]:
			_hit_point[i] = hit["position"]
			_hit_normal[i] = hit["normal"]
			_distance[i] = mount_w.distance_to(_hit_point[i])
			grounded += 1
		else:
			_distance[i] = ray_len

	# 2. Spring-damper with bump stop, then anti-roll per axle, clamped to [0, max].
	var k: float = spec.spring_stiffness
	var c: float = spec.spring_damping
	for i: int in WHEEL_COUNT:
		_compression[i] = 0.0
		_spring[i] = 0.0
		if not wheel_contact[i]:
			continue
		var x: float = spec.suspension_rest - _distance[i]
		var s_rate: float = (v + w.cross(_hit_point[i] - com)).dot(_hit_normal[i])
		var f: float = k * x - c * s_rate
		if x > spec.suspension_travel:
			f += spec.bump_stop_stiffness * (x - spec.suspension_travel)
		_compression[i] = x
		_spring[i] = f
	# Anti-roll: the more compressed side of an axle gets extra force, the other side loses it.
	if wheel_contact[FL] and wheel_contact[FR]:
		var arb_f: float = spec.anti_roll * (_compression[FL] - _compression[FR])
		_spring[FL] += arb_f
		_spring[FR] -= arb_f
	if wheel_contact[RL] and wheel_contact[RR]:
		var arb_r: float = spec.anti_roll * (_compression[RL] - _compression[RR])
		_spring[RL] += arb_r
		_spring[RR] -= arb_r
	var travel: float = maxf(spec.suspension_travel, MIN_DIVISOR)
	for i: int in WHEEL_COUNT:
		if not wheel_contact[i]:
			wheel_compression[i] = 0.0
			continue
		_spring[i] = clampf(_spring[i], 0.0, spec.max_spring_force)
		wheel_compression[i] = clampf(_compression[i] / travel, 0.0, 1.0)
		if _spring[i] > 0.0:
			_apply_at(_hit_point[i], _hit_normal[i] * _spring[i], com)

	# 3. Slip angle and drift state.
	var slip: float = 0.0
	if speed_ms > spec.drift_min_speed_ms:
		slip = rad_to_deg(atan2(-v_lat, absf(v_long)))
	drift_angle_deg = slip
	if is_drifting:
		drift_score += spec.drift_score_rate * (absf(slip) / maxf(spec.drift_score_slip_norm_deg, MIN_DIVISOR)) \
			* (kmh / maxf(spec.drift_score_speed_norm_kmh, MIN_DIVISOR)) * delta
		if absf(slip) < spec.drift_min_angle_deg:
			_drift_exit_t += delta
		else:
			_drift_exit_t = 0.0
		if _drift_exit_t >= spec.drift_exit_time or kmh < spec.drift_entry_speed_kmh * spec.drift_stop_fraction:
			is_drifting = false
			drift_ended.emit(drift_score)
	elif grounded >= 2 and kmh > spec.drift_entry_speed_kmh and (handbrake or absf(slip) > spec.drift_entry_slip_deg):
		is_drifting = true
		drift_score = 0.0
		_drift_exit_t = 0.0
		drift_started.emit()

	# 4. Steering: speed-sensitive lock, first-order follow, counter-steer assist while drifting.
	var over: float = 0.0
	if is_drifting:
		over = clampf((absf(slip) - spec.drift_max_angle_deg * spec.counter_steer_start)
			/ maxf(spec.drift_max_angle_deg * (1.0 - spec.counter_steer_start), MIN_DIVISOR), 0.0, 1.0)
	var t_speed: float = clampf(absf(v_long) / top_ms, 0.0, 1.0)
	var max_steer: float = deg_to_rad(lerpf(spec.steer_angle_low_deg, spec.steer_angle_high_deg, t_speed))
	var steer_cmd: float = steer_in
	if over > 0.0:
		steer_cmd = lerpf(steer_in, -signf(slip), over * spec.counter_steer_assist)
	steer_angle_rad = lerpf(steer_angle_rad, steer_cmd * max_steer, clampf(spec.steer_speed * delta, 0.0, 1.0))

	# 5. Nitro: start on key with enough charge, drain while active, refill otherwise.
	var nitro_go: bool = nitro_key and nitro_amount > 0.0 and (nitro_active or nitro_amount >= spec.nitro_min_to_start)
	if nitro_go != nitro_active:
		nitro_active = nitro_go
		if nitro_go:
			nitro_started.emit()
		else:
			nitro_ended.emit()
	if nitro_active:
		nitro_amount = maxf(0.0, nitro_amount - delta / maxf(spec.nitro_capacity_s, MIN_DIVISOR))
	else:
		var refill: float = spec.nitro_refill_drift if is_drifting else spec.nitro_refill_passive
		nitro_amount = minf(1.0, nitro_amount + refill * delta)

	# 6. Longitudinal demand on the rear axle (drive, reverse) and the body (brake, engine brake).
	var eng: float = 0.0
	var brake_total: float = 0.0
	if throttle > 0.0:
		var cap_ms: float = top_ms * (spec.nitro_top_speed_mult if nitro_active else 1.0)
		if v_long < cap_ms:
			var ratio: float = clampf(v_long / top_ms, 0.0, 1.0)
			eng = spec.engine_force * spec.engine_force_curve.sample(ratio) * throttle
			if nitro_active:
				eng *= spec.nitro_force_mult
	elif brake > 0.0 and v_long < spec.reverse_engage_ms:
		if -v_long < spec.reverse_speed_kmh / KMH_PER_MS:
			eng = -spec.engine_force * spec.reverse_force_share * brake
	if brake > 0.0 and v_long >= spec.reverse_engage_ms:
		brake_total = spec.brake_force * brake
	var eb_total: float = spec.engine_brake if (throttle <= 0.0 and brake <= 0.0) else 0.0

	# 7. Tyre forces per wheel: lateral grip with a friction circle, then longitudinal forces.
	var mw: float = mass / WHEEL_COUNT
	var rear_mult: float = spec.drift_rear_grip_mult if (is_drifting or handbrake) else 1.0
	var roll_each: float = spec.rolling_resistance / WHEEL_COUNT
	var sat_peak: float = tan(deg_to_rad(spec.peak_slip_deg))
	for i: int in WHEEL_COUNT:
		if not wheel_contact[i] or _spring[i] <= 0.0:
			wheel_slip[i] = 0.0
			continue
		var front: bool = i < FRONT_COUNT
		var n: Vector3 = _hit_normal[i]
		var cp: Vector3 = _hit_point[i]
		var load_n: float = _spring[i]
		var f0: Vector3 = _safe_normalize(fwd_car - n * fwd_car.dot(n), fwd_car)
		var steer_w: float = steer_angle_rad if front else 0.0
		var fwd_w: Vector3 = f0.rotated(n, -steer_w)
		var side: Vector3 = _safe_normalize(fwd_w.cross(n), b.x)
		var vc: Vector3 = v + w.cross(cp - com)
		var vl: float = vc.dot(fwd_w)
		var vs: float = vc.dot(side)
		var mu: float = spec.grip_front if front else spec.grip_rear * rear_mult
		var fmax: float = mu * load_n
		var sat: float = maxf(maxf(spec.lateral_stiffness, absf(vl) * sat_peak), DIV_EPS)
		var f_lat: float = -fmax * clampf(vs / sat, -1.0, 1.0)
		var cap_long: float = sqrt(maxf(0.0, fmax * fmax - f_lat * f_lat))
		if not front and is_drifting and throttle > 0.0:
			cap_long = maxf(cap_long, load_n * spec.drift_throttle_grip)
		var share: float = spec.brake_front_share if front else 1.0 - spec.brake_front_share
		var f_long: float = _resist(brake_total * share * 0.5, vl, delta, mw)
		f_long += _resist(roll_each, vl, delta, mw)
		if not front:
			f_long += eng * 0.5
			f_long += _resist(eb_total * 0.5, vl, delta, mw)
		f_long = clampf(f_long, -cap_long, cap_long)
		_apply_at(cp, side * f_lat + fwd_w * f_long, com)
		wheel_slip[i] = clampf(absf(f_lat) / maxf(fmax, MIN_DIVISOR), 0.0, 1.0)

	# 8. Body forces: drag, downforce, upright and yaw damping, arcade air assists.
	apply_central_force(-v * (spec.drag * speed_ms))
	apply_central_force(-up * (spec.downforce * speed_ms * speed_ms))
	var tilt_axis: Vector3 = _safe_normalize(up.cross(Vector3.UP), Vector3.ZERO)
	var tilt: float = acos(clampf(up.dot(Vector3.UP), -1.0, 1.0))
	var w_tilt: Vector3 = w - up * w.dot(up)
	apply_torque(tilt_axis * (spec.upright_stiffness * tilt) - w_tilt * spec.upright_damping)
	apply_torque(-up * (spec.yaw_damping * mass * w.dot(up) * (1.0 + spec.drift_yaw_damp_mult * over)))
	if grounded == 0:
		apply_central_force(Vector3.DOWN * (mass * _gravity * (spec.airborne_gravity_mult - 1.0)))
		apply_torque(up * (-steer_in * spec.air_control_torque))

	# 9. Read-outs for camera, HUD, VFX, audio and AI.
	speed_kmh = kmh
	forward_speed = v_long
	grounded_wheels = grounded
	is_grounded = grounded > 0
	_update_gear_and_rpm(kmh, v_long, delta)
	for i: int in WHEEL_COUNT:
		var radius: float = maxf(spec.wheel_radius_front if i < FRONT_COUNT else spec.wheel_radius_rear, MIN_DIVISOR)
		wheel_spin_rad[i] = wrapf(wheel_spin_rad[i] + (v_long / radius) * delta, 0.0, TAU)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var best: float = 0.0
	var best_local: Vector3 = Vector3.ZERO
	for i: int in state.get_contact_count():
		var imp: float = state.get_contact_impulse(i).length()
		if imp > best:
			best = imp
			best_local = state.get_contact_local_position(i)
	if best >= spec.hit_min_impulse:
		hit.emit(best, to_global(best_local))


## Teleport, zero velocities, reset drift and (optionally) nitro.
func reset_to(xf: Transform3D, refill_nitro: bool = true) -> void:
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()
	if is_drifting:
		is_drifting = false
		drift_ended.emit(drift_score)
	drift_score = 0.0
	_drift_exit_t = 0.0
	if nitro_active:
		nitro_active = false
		nitro_ended.emit()
	if refill_nitro:
		nitro_amount = 1.0
	steer_angle_rad = 0.0
	_gear_dip_t = 0.0


## While frozen the car holds its place on the grid and ignores input (engine may still rev).
func set_frozen_for_grid(frozen: bool) -> void:
	_frozen = frozen
	freeze = frozen
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Local-space wheel centre for visuals, index 0..3 = FL, FR, RL, RR.
func get_wheel_local_position(index: int) -> Vector3:
	if index < 0 or index >= WHEEL_COUNT or _mounts.size() < WHEEL_COUNT:
		return Vector3.ZERO
	var m: Vector3 = _mounts[index]
	var radius: float = spec.wheel_radius_front if index < FRONT_COUNT else spec.wheel_radius_rear
	return Vector3(m.x, m.y - _distance[index] + radius, m.z)


func _update_gear_and_rpm(kmh: float, v_long: float, delta: float) -> void:
	_gear_dip_t = maxf(0.0, _gear_dip_t - delta)
	if v_long < -spec.reverse_engage_ms:
		gear = 0
		rpm_norm = clampf(-v_long / maxf(spec.reverse_speed_kmh / KMH_PER_MS, MIN_DIVISOR), 0.0, 1.0)
		return
	var band: float = maxf(spec.top_speed_kmh / float(maxi(spec.gear_count, 1)), MIN_DIVISOR)
	var g: int = clampi(int(kmh / band) + 1, 1, maxi(spec.gear_count, 1))
	if g > gear and gear >= 1:
		_gear_dip_t = spec.gear_dip_s
	gear = g
	var frac: float = clampf((kmh - float(g - 1) * band) / band, 0.0, 1.0)
	if _gear_dip_t > 0.0:
		frac *= spec.gear_dip_mult
	rpm_norm = frac


## Force that opposes the wheel's motion, limited so it cannot reverse the motion within one tick.
func _resist(mag: float, v_wheel: float, delta: float, mw: float) -> float:
	var limit: float = absf(v_wheel) * mw / maxf(delta, DIV_EPS)
	return -signf(v_wheel) * minf(absf(mag), limit)


## Central force plus the torque of its offset from the centre of mass.
func _apply_at(point: Vector3, force: Vector3, com: Vector3) -> void:
	apply_central_force(force)
	apply_torque((point - com).cross(force))


func _safe_normalize(v: Vector3, fallback: Vector3) -> Vector3:
	if v.length_squared() < DIV_EPS:
		return fallback
	return v.normalized()
