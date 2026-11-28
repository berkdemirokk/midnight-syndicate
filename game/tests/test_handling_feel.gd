extends "res://tests/test_case.gd"
## Feel numbers across the car classes: launch to 90 % top speed, yaw response after a full-lock step,
## a glancing and a head-on wall hit (speed kept), nitro kick 60 to 120 km/h. Every number is printed (FEEL ...)
## and kept as a metric. Targets are the arcade bands in docs/design/HANDLING_2026-11-28.md.

const FlatWorld = preload("res://tests/helpers/flat_world.gd")
const HZ: float = 60.0
const KMH_PER_MS: float = 3.6
const LAUNCH_CAP_TICKS: int = 60 * 60
const SPEC_NAMES: Array[String] = ["noctra_sable", "noctra_vela", "noctra_tayfun", "kestrel_gtr", "arden_bruiser", "atmaca_stock"]
## 0-100 km/h bands per class (dev PC, headless, 60 Hz): each class keeps its own pull.
const LAUNCH_BAND: Dictionary = {"noctra_sable": [3.6, 4.4], "noctra_vela": [3.6, 4.6], "noctra_tayfun": [3.0, 3.8], "kestrel_gtr": [3.0, 3.9], "arden_bruiser": [4.2, 5.3], "atmaca_stock": [8.0, 10.0]}
## 90 % of top speed from rest (s), pinned to about +-8 % of the 2026-11-28 speed-feel tune (HANDLING doc, "Speed feel").
## Street cars must stay within STREET_TIME90_MAX_S (13 s). A tuning pass moves these bands on purpose.
const TIME90_BAND: Dictionary = {"noctra_sable": [11.9, 13.9], "noctra_vela": [10.5, 12.3], "noctra_tayfun": [11.3, 13.2], "kestrel_gtr": [13.5, 15.8], "arden_bruiser": [11.3, 13.2], "atmaca_stock": [11.8, 13.8]}
## Street cars (all but the Kestrel GT) must also reach 90 % of top speed within the brief target of 13 s.
const STREET_TIME90_MAX_S: float = 13.0


func _spawn(spec_name: String, x: float, z: float = 0.0, y: float = 0.47) -> ArcadeCar:
	var car := ArcadeCar.new()
	car.spec = load("res://vehicles/specs/%s.tres" % spec_name) as CarSpec
	add(car)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
	return car


func _say(key: String, value: float) -> void:
	metric(key, value)
	print("FEEL %s = %.3f" % [key, value])


func _hold(car: ArcadeCar, kmh: float) -> void:
	car.input.throttle = clampf(0.5 + (kmh - car.speed_kmh) * 0.02, 0.0, 1.0)


func _wall_box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = at
	return body


func test_feel_launch_per_class() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	for spec_name: String in SPEC_NAMES:
		var car: ArcadeCar = _spawn(spec_name, 0.0)
		car.input.throttle = 1.0
		var t100: float = -1.0
		var t90: float = -1.0
		var top: float = 0.0
		var target90: float = car.spec.top_speed_kmh * 0.9
		for tick: int in LAUNCH_CAP_TICKS:
			await frames(1)
			if t100 < 0.0 and car.speed_kmh >= 100.0:
				t100 = float(tick + 1) / HZ
			if t90 < 0.0 and car.speed_kmh >= target90:
				t90 = float(tick + 1) / HZ
			top = maxf(top, car.speed_kmh)
		_say(spec_name + "_0_100_s", t100)
		var band: Array = LAUNCH_BAND[spec_name]
		check_range(t100, band[0], band[1], spec_name + " 0-100 km/h (s)")
		var band90: Array = TIME90_BAND[spec_name]
		check_range(t90, band90[0], band90[1], spec_name + " time to 90 % of top (s)")
		if spec_name != "kestrel_gtr":
			check(t90 > 0.0 and t90 <= STREET_TIME90_MAX_S, "%s time to 90 %% of top %.2f s, want <= %.1f" % [spec_name, t90, STREET_TIME90_MAX_S])
		_say(spec_name + "_90pct_top_s", t90)
		_say(spec_name + "_top_kmh", top)
		await cleanup([car])
	await cleanup([ground])


func test_feel_yaw_response() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	for spec_name: String in ["noctra_sable", "kestrel_gtr", "atmaca_stock"]:
		for speed: float in [60.0, 120.0, 180.0]:
			var car: ArcadeCar = _spawn(spec_name, 0.0)
			var guard: int = 0
			while car.speed_kmh < speed and guard < 60 * 40:
				_hold(car, speed)
				await frames(1)
				guard += 1
			car.input.steer = 1.0
			var yaw: Array[float] = []
			for tick: int in 60:
				_hold(car, speed)
				await frames(1)
				yaw.append(absf(car.angular_velocity.y))
			var steady: float = 0.0
			for i: int in range(45, 60):
				steady += yaw[i]
			steady /= 15.0
			var rise: float = -1.0
			for i: int in yaw.size():
				if yaw[i] >= 0.9 * steady:
					rise = float(i + 1) / HZ
					break
			_say("%s_yaw_rise_%d_s" % [spec_name, int(speed)], rise)
			check(rise > 0.0 and rise <= (0.25 if speed < 170.0 else 0.35), "%s yaw rise %.3f s at %d km/h" % [spec_name, rise, int(speed)])
			_say("%s_yaw_steady_%d_rads" % [spec_name, int(speed)], steady)
			await cleanup([car])
	await cleanup([ground])


## Hits a wall at angle_deg from its surface (glancing) with speed_kmh, coasting. Returns speed kept (0..1).
func _wall_hit(spec_name: String, speed_kmh: float, glancing_deg: float) -> float:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var wall: StaticBody3D = null
	var car: ArcadeCar = null
	if glancing_deg > 0.0:
		# wall plane x = 3, car heads +X at glancing_deg from the -Z heading (about 15 deg off the wall)
		wall = _wall_box(Vector3(0.5, 6.0, 300.0), Vector3(3.25, 3.0, 0.0))
		add(wall)
		var yaw_rad: float = -deg_to_rad(glancing_deg)
		car = _spawn(spec_name, -2.0)
		car.reset_to(Transform3D(Basis(Vector3.UP, yaw_rad), Vector3(-2.0, 0.47, 0.0)))
	else:
		# head-on: wall plane z = -30, car heads -Z
		wall = _wall_box(Vector3(300.0, 6.0, 0.5), Vector3(0.0, 3.0, -30.25))
		add(wall)
		car = _spawn(spec_name, 0.0)
	await frames(2)
	var fwd: Vector3 = -car.global_transform.basis.z
	car.linear_velocity = fwd * speed_kmh / KMH_PER_MS
	var pre: float = speed_kmh
	var post_sum: float = 0.0
	var post_n: int = 0
	for tick: int in 150:
		await frames(1)
		if tick >= 100:
			post_sum += car.speed_kmh
			post_n += 1
	var kept: float = (post_sum / maxf(float(post_n), 1.0)) / maxf(pre, 0.001)
	print("FEEL wall end x %.2f z %.2f" % [car.global_position.x, car.global_position.z])
	await cleanup([car, wall, ground])
	return kept


func test_feel_wall_hits() -> void:
	var glance: float = await _wall_hit("noctra_sable", 120.0, 15.0)
	var head: float = await _wall_hit("noctra_sable", 120.0, 0.0)
	var glance_vela: float = await _wall_hit("noctra_vela", 120.0, 15.0)
	_say("sable_glancing_wall_speed_kept_120", glance)
	_say("sable_head_on_wall_speed_kept_120", head)
	_say("vela_glancing_wall_speed_kept_120", glance_vela)
	check(glance >= 0.80, "glancing wall hit kept %.2f of speed, want >= 0.80" % glance)
	check(glance_vela >= 0.80, "vela glancing wall hit kept %.2f of speed, want >= 0.80" % glance_vela)
	check(head >= 0.0 and head < 0.5, "head-on wall hit kept %.2f: a head-on hit must still cost most of the speed" % head)


func test_feel_nitro_kick() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var times: Array[float] = []
	for nitro_on: bool in [false, true]:
		var car: ArcadeCar = _spawn("noctra_sable", 0.0)
		await _run_to_kmh(car, 60.0)
		var t: float = -1.0
		for tick: int in 60 * 20:
			car.input.throttle = 1.0
			car.input.nitro = nitro_on
			await frames(1)
			if car.speed_kmh >= 120.0:
				t = float(tick + 1) / HZ
				break
		times.append(t)
		await cleanup([car])
	_say("sable_60_120_s_no_nitro", times[0])
	_say("sable_60_120_s_nitro", times[1])
	_say("sable_nitro_gain_60_120_s", times[0] - times[1])
	check(times[0] - times[1] >= 0.5, "nitro gain 60-120 km/h %.2f s, want >= 0.5" % (times[0] - times[1]))
	await cleanup([ground])


func _run_to_kmh(car: ArcadeCar, kmh: float) -> void:
	var guard: int = 0
	car.input.throttle = 1.0
	while car.speed_kmh < kmh and guard < 60 * 40:
		await frames(1)
		guard += 1
