extends "res://tests/test_case.gd"
## Player driver, touch zones and chase camera, on a flat world with a default ArcadeCar.

const FlatWorld = preload("res://tests/helpers/flat_world.gd")
const KMH_PER_MS: float = 3.6
const SETTLE_FRAMES: int = 60
const STRAIGHT_FRAMES: int = 300
const TEST_SPEED_KMH: float = 200.0
const REF_SPEED_KMH: float = 30.0
const STEER_TICKS: int = 6
const HIT_IMPULSE_TEST: float = 8000.0  ## gives 0.4 trauma with the default hit_impulse_full
const SHAKE_SAMPLES: int = 30
const SHAKE_TRAUMA_LOW: float = 0.5
const SHAKE_TRAUMA_HIGH: float = 1.0
const SHAKE_RATIO_LO: float = 3.0  ## trauma squared predicts about 4.2 for 1.0 vs 0.5
const SHAKE_RATIO_HI: float = 5.5
const ORBIT_FRAMES: int = 60
const ORBIT_TOL_M: float = 0.05
const ACTIONS: PackedStringArray = ["accelerate", "brake", "steer_left", "steer_right", "handbrake", "nitro"]

var _car: ArcadeCar = null
var _driver: PlayerDriver = null
var _cam: ChaseCamera = null
var _nodes: Array[Node] = []


func _rig(with_camera: bool) -> void:
	_nodes.append(add(FlatWorld.make_ground()))
	_car = ArcadeCar.new()
	_car.position = Vector3(0.0, 0.8, 0.0)
	_driver = PlayerDriver.new()
	_car.add_child(_driver)
	_nodes.append(add(_car))
	if with_camera:
		_cam = ChaseCamera.new()
		_cam.target = _car
		_nodes.append(add(_cam))


func _finish() -> void:
	for a: String in ACTIONS:
		Input.action_release(a)
	await cleanup(_nodes)
	_nodes.clear()


## Lets the car rest with the driver off (auto accelerate would otherwise drive it away).
func _settle() -> void:
	_driver.enabled = false
	await frames(SETTLE_FRAMES)
	_driver.enabled = true


## Re-runs the camera update with zero delta, so its pose matches the car pose read right after.
## Without this, the camera pose and the car pose can come from different physics ticks.
func _sync_camera() -> void:
	_cam._process(0.0)


func _settings_node() -> Node:
	return tree.root.get_node_or_null("Settings")


func _send_touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = tree.root.get_final_transform() * pos  # viewport px -> the coordinates push_input expects
	ev.pressed = pressed
	tree.root.push_input(ev)


func _send_drag(index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = tree.root.get_final_transform() * pos
	tree.root.push_input(ev)


func _shake_len() -> float:
	return (_cam.global_position - _cam.compute_ideal_position()).length()


## Mean shake displacement over SHAKE_SAMPLES frames, with trauma held at t (decay is about 0.02 per frame).
func _mean_shake(t: float) -> float:
	var sum: float = 0.0
	for _i: int in SHAKE_SAMPLES:
		_cam.trauma = t
		await frames(1)
		sum += _shake_len()
	return sum / SHAKE_SAMPLES


func test_accelerate_gives_full_throttle() -> void:
	_rig(false)
	await _settle()
	var settings: Node = _settings_node()
	metric("settings_autoload_present", settings != null)
	# Manual mode for the release check: the Settings value wins over the fallback when present.
	_driver.auto_accelerate_fallback = false
	if settings != null:
		settings.set("auto_accelerate", false)
	Input.action_press("accelerate")
	await frames(3)
	check_range(_car.input.throttle, 0.999, 1.0, "throttle with accelerate held")
	Input.action_release("accelerate")
	await frames(3)
	check_range(_car.input.throttle, 0.0, 0.001, "throttle after accelerate released (manual mode)")
	_driver.auto_accelerate_fallback = true
	if settings != null:
		settings.set("auto_accelerate", true)
	await frames(2)
	check_range(_car.input.throttle, 0.999, 1.0, "throttle with auto accelerate and no key")
	await _finish()


func test_keyboard_steering_ramps_and_is_slower_at_speed() -> void:
	_rig(false)
	await _settle()
	_car.linear_velocity = Vector3.ZERO
	Input.action_press("steer_right")
	await frames(STEER_TICKS)
	var steer_0: float = _driver.steer
	check(steer_0 > 0.0 and steer_0 < 0.95, "steer ramps, not instant, at standstill")
	Input.action_release("steer_right")
	await frames(30)
	check_range(_driver.steer, -0.001, 0.001, "steer returns to centre after release")

	_car.linear_velocity = Vector3(0.0, 0.0, -REF_SPEED_KMH / KMH_PER_MS)
	await frames(1)
	Input.action_press("steer_right")
	await frames(STEER_TICKS)
	var steer_30: float = _driver.steer
	var speed_30: float = _car.speed_kmh
	Input.action_release("steer_right")
	await frames(30)

	_car.linear_velocity = Vector3(0.0, 0.0, -TEST_SPEED_KMH / KMH_PER_MS)
	await frames(1)
	Input.action_press("steer_right")
	await frames(STEER_TICKS)
	var steer_200: float = _driver.steer
	metric("steer_after_0.1s_at_0kmh", steer_0)
	metric("steer_after_0.1s_at_30kmh", steer_30)
	metric("steer_after_0.1s_at_200kmh", steer_200)
	metric("speed_kmh_during_30kmh_steer", speed_30)
	metric("speed_kmh_during_steer_test", _car.speed_kmh)
	check(steer_200 > 0.0, "steer moves at 200 km/h")
	check(steer_200 < steer_30 and steer_30 < steer_0, "steer slows with speed: 200 km/h < 30 km/h < 0 km/h")
	await _finish()


func test_disabled_driver_clears_input() -> void:
	_rig(false)
	await _settle()
	Input.action_press("accelerate")
	Input.action_press("steer_right")
	Input.action_press("handbrake")
	Input.action_press("nitro")
	await frames(5)
	_driver.enabled = false
	await frames(2)
	check(_car.input.throttle == 0.0, "disabled driver: throttle cleared")
	check(_car.input.brake == 0.0, "disabled driver: brake cleared")
	check(_car.input.steer == 0.0, "disabled driver: steer cleared")
	check(not _car.input.handbrake, "disabled driver: handbrake cleared")
	check(not _car.input.nitro, "disabled driver: nitro cleared")
	await _finish()


func test_chase_camera_behind_car_after_five_seconds() -> void:
	_rig(true)
	await _settle()
	Input.action_press("accelerate")
	var non_finite: bool = false
	for _i: int in STRAIGHT_FRAMES:
		await frames(1)
		if not _cam.global_position.is_finite():
			non_finite = true
	check(not non_finite, "camera position never NaN or inf during 5 s run")
	# Camera and car must be read at the same instant, so the pose compared is one pose.
	_sync_camera()
	var car_xf: Transform3D = _car.get_global_transform_interpolated()
	var car_p: Vector3 = car_xf.origin
	var cam_p: Vector3 = _cam.global_position
	var fwd: Vector3 = -car_xf.basis.z
	var dist: float = cam_p.distance_to(car_p)
	var behind: float = (cam_p - car_p).dot(fwd)
	check_range(dist, 4.0, 8.0, "camera distance to car after 5 s (m)")
	check(behind < -3.0, "camera sits behind the car along its heading")
	check(cam_p.y > car_p.y, "camera above the car")
	var to_car: Vector3 = (car_p - cam_p).normalized()
	var view: Vector3 = -_cam.global_transform.basis.z
	var angle_deg: float = rad_to_deg(acos(clampf(to_car.dot(view), -1.0, 1.0)))
	check_range(angle_deg, 0.0, 10.0, "car angle from view centre (deg)")
	metric("speed_kmh_after_5s", _car.speed_kmh)
	metric("camera_distance_m", dist)
	metric("camera_height_above_car_m", cam_p.y - car_p.y)
	metric("camera_back_m", -behind)
	metric("camera_lateral_m", (cam_p - car_p).dot(car_xf.basis.x))
	metric("car_slip_deg", _car.drift_angle_deg)
	metric("camera_to_ideal_gap_m", cam_p.distance_to(_cam.compute_ideal_position()))
	metric("car_angle_from_view_deg", angle_deg)
	await _finish()


func test_fov_grows_with_speed_and_nitro() -> void:
	_rig(true)
	await _settle()
	var fov_rest: float = _cam.fov
	check_range(fov_rest, 61.5, 62.5, "FOV at rest (deg)")
	Input.action_press("accelerate")
	await frames(STRAIGHT_FRAMES)
	var fov_speed: float = _cam.fov
	metric("fov_rest_deg", fov_rest)
	metric("fov_after_5s_deg", fov_speed)
	check(fov_speed > fov_rest + 1.0, "FOV at speed is above FOV at rest")
	Input.action_press("nitro")
	await frames(60)
	check(_car.nitro_active, "nitro active after holding nitro")
	check(_cam.nitro_kick > 0.9, "nitro kick eased to about 1 while nitro is active")
	var fov_kick: float = _cam.fov - _cam.compute_base_fov()
	metric("fov_nitro_kick_deg", fov_kick)
	check(fov_kick > 4.0, "FOV rises further while nitro is active (deg)")
	check(_cam.fov <= _cam.fov_cap_deg() + 0.001, "FOV stays under the phone cap at speed plus nitro")
	Input.action_release("nitro")
	await frames(180)
	check(_cam.nitro_kick < 0.05, "nitro kick returns to 0 after nitro release")
	check(absf(_cam.fov - _cam.compute_base_fov()) < 1.0, "FOV comes back after nitro release")
	await _finish()


func test_trauma_decays_below_threshold_in_1_5_s() -> void:
	_rig(true)
	await _settle()
	_cam.add_trauma(1.0)
	check(_cam.trauma > 0.99, "trauma is 1 right after add_trauma(1)")
	await frames(90)
	metric("trauma_after_1_5s", _cam.trauma)
	check(_cam.trauma < 0.01, "trauma decays to under 0.01 within 1.5 s")
	await _finish()


func test_hit_and_nitro_add_trauma_automatically() -> void:
	_rig(true)
	await _settle()
	_cam.trauma = 0.0
	_car.hit.emit(HIT_IMPULSE_TEST, Vector3.ZERO)
	check_range(_cam.trauma, 0.39, 0.41, "hit adds trauma from impulse")
	_cam.trauma = 0.0
	_car.hit.emit(1.0e9, Vector3.ZERO)
	check_range(_cam.trauma, _cam.hit_trauma_max - 0.01, _cam.hit_trauma_max + 0.01, "hit trauma capped at hit_trauma_max")
	_cam.trauma = 0.0
	_car.nitro_started.emit()
	check_range(_cam.trauma, _cam.nitro_trauma - 0.01, _cam.nitro_trauma + 0.01, "nitro start adds nitro_trauma")
	await _finish()


func test_target_assigned_after_ready_gets_hit_trauma() -> void:
	_rig(false)
	_cam = ChaseCamera.new()
	_nodes.append(add(_cam))
	await frames(2)
	_cam.target = _car
	_car.hit.emit(HIT_IMPULSE_TEST, Vector3.ZERO)
	check_range(_cam.trauma, 0.39, 0.41, "late target gets hit trauma")
	await _finish()


func test_shake_offset_is_zero_at_rest_and_scales_with_trauma_squared() -> void:
	_rig(true)
	await _settle()
	_cam.trauma = 0.0
	await frames(1)
	check(_shake_len() < 0.001, "no shake offset at zero trauma")
	var mean_low: float = await _mean_shake(SHAKE_TRAUMA_LOW)
	var mean_high: float = await _mean_shake(SHAKE_TRAUMA_HIGH)
	metric("shake_mean_at_0.5_m", mean_low)
	metric("shake_mean_at_1.0_m", mean_high)
	check(mean_high > 0.05, "shake offset is visible at high trauma")
	var ratio: float = mean_high / maxf(mean_low, 0.000001)
	metric("shake_ratio_1_vs_0.5", ratio)
	check_range(ratio, SHAKE_RATIO_LO, SHAKE_RATIO_HI, "shake amplitude ratio ~ trauma squared")
	await _finish()


func test_snap_places_camera_at_ideal_pose() -> void:
	_rig(true)
	await _settle()
	_car.linear_velocity = Vector3(0.0, 0.0, -20.0)
	await frames(30)
	_cam.snap()
	var ideal: Vector3 = _cam.compute_ideal_position()
	var err: float = _cam.global_position.distance_to(ideal)
	metric("snap_error_m", err)
	check(err < 0.01, "snap() puts the camera at the ideal pose")
	check_range(_cam.global_position.distance_to(_car.global_position), 4.0, 8.0, "snap distance to car (m)")
	await _finish()


func test_hood_mode_sits_at_bonnet() -> void:
	_rig(true)
	await _settle()
	_cam.set_mode(ChaseCamera.Mode.HOOD)
	await frames(3)
	_sync_camera()
	var car_xf: Transform3D = _car.get_global_transform_interpolated()
	var err: float = _cam.global_position.distance_to(car_xf * _cam.hood_offset)
	metric("hood_error_m", err)
	check(err < 0.01, "hood camera sits at the bonnet offset")
	check(_cam.global_position.distance_to(car_xf.origin) < 1.5, "hood camera is close to the car")
	await _finish()


func test_orbit_mode_circles_target_at_set_radius() -> void:
	_rig(true)
	await _settle()
	_cam.set_mode(ChaseCamera.Mode.ORBIT)
	await frames(2)
	_sync_camera()
	var p0: Vector3 = _cam.global_position
	await frames(ORBIT_FRAMES)
	_sync_camera()
	var p1: Vector3 = _cam.global_position
	var car_p: Vector3 = _car.get_global_transform_interpolated().origin
	var flat: Vector2 = Vector2(p1.x - car_p.x, p1.z - car_p.z)
	metric("orbit_radius_m", flat.length())
	metric("orbit_height_m", p1.y - car_p.y)
	check_range(flat.length(), _cam.orbit_radius_m - ORBIT_TOL_M, _cam.orbit_radius_m + ORBIT_TOL_M, "orbit radius (m)")
	check_range(p1.y - car_p.y, _cam.orbit_height_m - ORBIT_TOL_M, _cam.orbit_height_m + ORBIT_TOL_M, "orbit height (m)")
	check(p0.distance_to(p1) > 0.3, "orbit camera moves around the car")
	await _finish()


func test_wall_between_car_and_camera_shortens_distance() -> void:
	_rig(true)
	await _settle()
	_driver.enabled = false
	await frames(SETTLE_FRAMES)
	var before: float = _cam.global_position.distance_to(_car.global_position)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 6.0, 0.5)
	cs.shape = box
	wall.add_child(cs)
	wall.position = Vector3(0.0, 3.0, 4.0)
	_nodes.append(add(wall))
	await frames(SETTLE_FRAMES)
	var after: float = _cam.global_position.distance_to(_car.global_position)
	metric("distance_before_wall_m", before)
	metric("distance_with_wall_m", after)
	check(after < before - 1.0, "wall between car and camera shortens the distance by over 1 m")
	check(_cam.global_position.is_finite(), "camera position finite with a wall")
	await _finish()


func test_touch_zones_drive_the_driver() -> void:
	_rig(false)
	var touch := TouchControls.new()
	touch.force_visible = true
	_nodes.append(add(touch))
	touch.bind(_driver)
	await frames(3)
	check(touch.visible, "force_visible shows the touch controls")
	var left: Vector2 = touch.get_zone_rect(TouchControls.Zone.STEER_LEFT).get_center()
	var right: Vector2 = touch.get_zone_rect(TouchControls.Zone.STEER_RIGHT).get_center()
	var brake: Vector2 = touch.get_zone_rect(TouchControls.Zone.BRAKE).get_center()
	var nitro: Vector2 = touch.get_zone_rect(TouchControls.Zone.NITRO).get_center()
	var drift: Vector2 = touch.get_zone_rect(TouchControls.Zone.DRIFT).get_center()
	check(left.x > 0.0 and brake.x > left.x, "steer zone left of brake pedal")
	_send_touch(0, left, true)
	check(_driver.touch_steer == -1.0, "left steer zone gives full left steer")
	_send_touch(1, brake, true)
	check(_driver.touch_brake, "brake pedal touch sets brake")
	check(_driver.touch_steer == -1.0, "steer held while a second finger brakes")
	_send_drag(0, right)
	check(_driver.touch_steer == 1.0, "dragging the finger into the right zone steers right")
	_send_drag(0, brake)
	check(_driver.touch_steer == 1.0, "dragging into the brake zone keeps the last steer zone")
	_send_touch(0, right, false)
	check(_driver.touch_steer == 0.0, "lifting the steer finger centres steer")
	_send_touch(1, brake, false)
	check(not _driver.touch_brake, "lifting the brake finger releases brake")
	_send_touch(2, nitro, true)
	check(_driver.touch_nitro, "nitro zone touch sets nitro")
	_send_touch(2, nitro, false)
	check(not _driver.touch_nitro, "lifting the nitro finger releases nitro")
	_send_touch(3, drift, true)
	check(_driver.touch_handbrake, "drift zone touch sets handbrake")
	_send_touch(3, drift, false)
	check(not _driver.touch_handbrake, "lifting the drift finger releases handbrake")
	var hidden := TouchControls.new()
	hidden.force_visible = false
	_nodes.append(add(hidden))
	await frames(2)
	metric("touch_visible_without_force", hidden.visible)
	check(hidden.visible == DisplayServer.is_touchscreen_available(),
		"touch controls hidden unless a touchscreen is available")
	await _finish()


## Static box at centre, size; layer 1 so the camera wall rays see it.
func _add_box(centre: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.position = centre
	_nodes.append(add(body))
	return body


## Holds the car's yaw rate at yaw for ticks physics frames (the car's yaw damping eats a single kick).
func _hold_yaw(yaw: float, ticks: int) -> void:
	for _i: int in ticks:
		_car.angular_velocity = Vector3(0.0, yaw, 0.0)
		await frames(1)


func test_look_point_moves_toward_corner_inside() -> void:
	_rig(true)
	await _settle()
	await _hold_yaw(1.0, 60)  # positive yaw turns left, so the inside is left
	var xf: Transform3D = _car.get_global_transform_interpolated()
	var lateral_left: float = (_cam._look_point(xf) - xf.origin).dot(xf.basis.x)
	metric("look_side_left_turn", _cam.look_side)
	metric("look_lateral_left_turn_m", lateral_left)
	check(_cam.look_side < -0.5, "left turn: look shift goes left (look_side %.2f)" % _cam.look_side)
	check(lateral_left < -0.3, "left turn: look point is left of the car (%.2f m)" % lateral_left)
	await _hold_yaw(-1.0, 120)
	xf = _car.get_global_transform_interpolated()
	var lateral_right: float = (_cam._look_point(xf) - xf.origin).dot(xf.basis.x)
	check(lateral_right > 0.3, "right turn: look point is right of the car (%.2f m)" % lateral_right)
	await _hold_yaw(0.0, 240)
	check(absf(_cam.look_side) < 0.05, "straight road: look shift returns to centre")
	await _finish()


func test_roll_leans_into_turn_within_limit_and_zero_in_grid() -> void:
	_rig(true)
	await _settle()
	await _hold_yaw(1.0, 60)
	var max_rad: float = deg_to_rad(_cam.max_roll_deg)
	metric("roll_deg_left_turn", rad_to_deg(_cam.roll_rad))
	check(absf(_cam.roll_rad) <= max_rad + 0.0001, "roll stays within max_roll_deg")
	check(_cam.roll_rad < -0.5 * max_rad, "left turn rolls the camera left (negative)")
	var right0: Vector3 = (-_cam.global_transform.basis.z).cross(Vector3.UP).normalized()
	var tilt: float = _cam.global_transform.basis.y.dot(right0)
	check(tilt < -0.02, "camera horizon tilts left on a left turn (tilt %.4f)" % tilt)
	check(absf(tilt) <= sin(max_rad) + 0.001, "applied roll matches roll_rad")
	_cam.set_mode(ChaseCamera.Mode.ORBIT)
	await _hold_yaw(1.0, 240)
	metric("roll_deg_in_grid", rad_to_deg(_cam.roll_rad))
	check(absf(_cam.roll_rad) < 0.0005, "no roll in ORBIT (grid and finish)")
	await _finish()


func test_nitro_ignition_kicks_camera_back_and_eases_out() -> void:
	_rig(true)
	await _settle()
	_car.nitro_started.emit()
	await frames(1)
	metric("kick_back_at_ignition_m", _cam.kick_back_m)
	check_range(_cam.kick_back_m, 0.84, 0.86, "nitro ignition pushes the camera back 0.85 m")
	await frames(24)  # 0.4 s is about 0.36 of nitro_kick_back_s
	metric("kick_back_at_half_m", _cam.kick_back_m)
	check_range(_cam.kick_back_m, 0.56, 0.63, "push-back eases on a smoothstep (0.3 eased at 0.36 of its time)")
	await frames(60)
	check(absf(_cam.kick_back_m) < 0.001, "push-back fully eased after nitro_kick_back_s")
	await _finish()


func test_speed_lowers_camera_and_adds_shake_above_180() -> void:
	_rig(true)
	await _settle()
	await frames(2)
	var h_rest: float = _cam.compute_ideal_position().y - _car.global_position.y
	_car.linear_velocity = Vector3(0.0, 0.0, -70.0)  # 252 km/h
	await frames(30)
	var h_fast: float = _cam.compute_ideal_position().y - _car.global_position.y
	metric("speed_kmh_for_shake", _car.speed_kmh)
	metric("camera_height_drop_m", h_rest - h_fast)
	check(_car.speed_kmh > 200.0, "car reached 200 km/h for the speed test")
	check(h_rest - h_fast > 0.02, "camera lowers with speed (%.3f m)" % (h_rest - h_fast))
	check(h_rest - h_fast <= _cam.speed_drop_m + 0.001, "lowering stays within speed_drop_m")
	_cam.trauma = 0.0
	# Measured on the shake term alone: the spring lag at speed is not shake.
	var mean: float = 0.0
	var peak: float = 0.0
	for _i: int in SHAKE_SAMPLES:
		await frames(1)
		var s: float = _cam._speed_shake_offset(_cam.global_transform.basis).length()
		mean += s
		peak = maxf(peak, s)
	mean /= SHAKE_SAMPLES
	metric("speed_shake_mean_m", mean)
	metric("speed_shake_peak_m", peak)
	check(mean > 0.002, "speed shake is visible above 180 km/h without trauma")
	check(peak <= _cam.speed_shake_m * 1.2 + 0.0005, "speed shake stays subtle (peak %.4f m)" % peak)
	await _finish()


func test_ceiling_keeps_camera_under_roof() -> void:
	_rig(true)
	await _settle()
	var roof_y: float = _car.global_position.y + 1.6
	_add_box(Vector3(0.0, roof_y + 0.2, 0.0), Vector3(60.0, 0.4, 60.0))  # slab bottom at roof_y
	await frames(30)
	_sync_camera()
	metric("camera_y_under_roof_m", roof_y - _cam.global_position.y)
	check(_cam.global_position.y < roof_y - 0.1, "camera stays below the ceiling")
	check(_cam.global_position.y > _car.global_position.y, "camera still above the car under the roof")
	await _finish()


func test_side_wall_limits_camera_swing() -> void:
	_rig(true)
	await _settle()
	_driver.enabled = false
	_add_box(Vector3(1.2, 1.5, 0.0), Vector3(0.3, 3.0, 40.0))  # near face at x = 1.05
	await frames(30)
	var limit: float = _cam._side_limit_right_m
	metric("side_limit_right_m", limit)
	check_range(limit, 0.6, 0.85, "side probe finds the wall face (limit to the right)")
	check(_cam._goal_offset().y <= limit + 0.001, "goal swing stays inside the side wall")
	_sync_camera()
	var xf: Transform3D = _car.get_global_transform_interpolated()
	var lateral: float = (_cam.global_position - xf.origin).dot(xf.basis.x)
	check(lateral < 1.05, "camera is not inside the side wall (lateral %.2f m)" % lateral)
	await _finish()


func test_nitro_ignition_bursts_post_blur_then_settles() -> void:
	var fx := PostFx.new()
	_nodes.append(add(fx))
	await frames(2)
	fx.set_speed(0.0, false)
	await frames(2)
	fx.set_speed(0.0, true)
	await frames(1)
	var mat: ShaderMaterial = fx._rect.material as ShaderMaterial
	var shown: float = mat.get_shader_parameter("blur")
	metric("blur_at_ignition", shown)
	check(shown > fx.get_blur() + 0.3, "nitro ignition adds a blur burst on top of the eased blur")
	await frames(60)
	check(absf(float(mat.get_shader_parameter("blur")) - fx.get_blur()) < 0.01, "blur burst gone about 1 s after ignition")
	await _finish()


func test_finish_orbit_circles_car_at_orbit_radius() -> void:
	_rig(true)
	await _settle()
	_cam.start_finish_orbit()
	check(_cam.mode == ChaseCamera.Mode.ORBIT, "finish orbit sets ORBIT mode")
	await frames(ORBIT_FRAMES)
	_sync_camera()
	var car_p: Vector3 = _car.get_global_transform_interpolated().origin
	var flat: Vector2 = Vector2(_cam.global_position.x - car_p.x, _cam.global_position.z - car_p.z)
	check_range(flat.length(), _cam.orbit_radius_m - ORBIT_TOL_M, _cam.orbit_radius_m + ORBIT_TOL_M, "finish orbit radius (m)")
	await _finish()
