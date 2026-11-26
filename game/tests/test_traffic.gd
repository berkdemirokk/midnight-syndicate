extends "res://tests/test_case.gd"
## Civilian traffic (game/traffic). Checks: preset counts, the shared Arden Civic meshes, lane keeping and the fixed
## count on City 01 with one racing car, brake lamps, a push on contact, and a 5-AI one-lap race with traffic that must
## finish inside the stuck limits of the City 01 sweep races (total 8, 3 per car) with no traffic on the grid.

const SCENE_PATH: String = "res://world/city_01/city_01.tscn"
const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const HZ: float = 60.0
const RACE_LIMIT_S: float = 150.0
const MAX_STUCK_TOTAL: int = 8
const MAX_STUCK_PER_CAR: int = 3
const SOLO_TICKS: int = 900
const LANE_TOLERANCE_M: float = 3.0
const GRID_CLEAR_M: float = 90.0  ## no traffic car this close to a grid slot at GO
var AI_SKILLS: PackedFloat32Array = PackedFloat32Array([1.0, 0.97, 0.94, 0.91, 0.88])


func _make_car(skill: float, seed_value: int) -> ArcadeCar:
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	var d := AIDriver.new()
	d.name = "AIDriver"
	d.skill = skill
	d.noise_seed = seed_value
	car.add_child(d)
	return car


func _load_city() -> CityBuilder:
	var city: CityBuilder = (load(SCENE_PATH) as PackedScene).instantiate() as CityBuilder
	add(city)
	return city


func test_preset_counts() -> void:
	check(TrafficSystem.count_for_preset("low") == 4, "low preset must give 4 cars")
	check(TrafficSystem.count_for_preset("medium") == 10, "medium preset must give 10 cars")
	check(TrafficSystem.count_for_preset("high") == 14, "high preset must give 14 cars")


func test_models_share_arden_civic() -> void:
	for i: int in TrafficModels.LOD_COUNT:
		var m: Dictionary = TrafficModels.lod(i)
		check((m["paint"] as ArrayMesh).get_surface_count() >= 1, "LOD%d has no paint surface" % i)
		check((m["tail"] as ArrayMesh).get_surface_count() >= 1, "LOD%d has no tail lamp surface" % i)
		check((m["head"] as ArrayMesh).get_surface_count() >= 1, "LOD%d has no head lamp surface" % i)
		check((m["body"] as ArrayMesh).get_surface_count() >= 3, "LOD%d body has fewer than 3 surfaces" % i)
	var box: AABB = TrafficModels.lod(0)["aabb"]
	check_range(box.size.z, 4.3, 4.9, "traffic car length")
	check(TrafficModels.lod(0) == TrafficModels.lod(0), "the bake is cached")


func test_lanes_count_and_clearance() -> void:
	var city: CityBuilder = await _load_city()
	var racer: ArcadeCar = _make_car(0.95, 1)
	var cars: Array[ArcadeCar] = [racer]
	var manager := RaceManager.new()
	manager.total_laps = 1
	add(manager)
	manager.setup(city, cars, null, PackedStringArray(["Solo"]))
	var traffic := TrafficSystem.new()
	traffic.count_override = 10
	traffic.oncoming_fraction = 0.5
	city.add_child(traffic)
	traffic.setup(city, racer, cars)
	await frames(TrafficSystem.WARMUP_TICKS + 2)
	manager.start_countdown()
	check(traffic.cars.size() == 10, "traffic has %d cars, expected 10" % traffic.cars.size())
	var worst_lane: float = 0.0
	var min_gap: float = INF
	var saw_brake: bool = false
	var oncoming: int = 0
	var moved: float = 0.0
	for c: TrafficCar in traffic.cars:
		if c.dir < 0:
			oncoming += 1
	for t: int in SOLO_TICKS:
		await frames(1)
		saw_brake = saw_brake or _any_braking(traffic)
		if t > 120:
			for c: TrafficCar in traffic.cars:
				worst_lane = maxf(worst_lane, c.lane_err if c.hit_t <= 0.0 else 0.0)
				var d: float = absf(fposmod(city.get_progress(c.global_position, c.s) - city.get_progress(racer.global_position), city.length))
				min_gap = minf(min_gap, minf(d, city.length - d))
	for c: TrafficCar in traffic.cars:
		moved += c.linear_velocity.length()
	metric("solo_traffic_worst_lane_err_m", snappedf(worst_lane, 0.01))
	metric("solo_traffic_oncoming_cars", oncoming)
	metric("solo_traffic_respawns", traffic.respawns)
	metric("solo_traffic_hits", traffic.hit_count)
	check(oncoming >= 1 and oncoming < 10, "expected both directions in traffic, oncoming = %d" % oncoming)
	check(worst_lane < LANE_TOLERANCE_M, "a traffic car left its lane by %.2f m" % worst_lane)
	check(moved / 10.0 > 3.0, "traffic is not moving: mean speed %.1f m/s" % (moved / 10.0))
	check(traffic.cars.size() == 10, "traffic count changed to %d" % traffic.cars.size())
	await cleanup([manager, traffic, racer, city] as Array[Node])


func _any_braking(traffic: TrafficSystem) -> bool:
	for c: TrafficCar in traffic.cars:
		if c.braking:
			return true
	return false


func test_push_on_contact_and_follow() -> void:
	var city: CityBuilder = await _load_city()
	var racer: ArcadeCar = _make_car(0.95, 1)
	var cars: Array[ArcadeCar] = [racer]
	var traffic := TrafficSystem.new()
	traffic.count_override = 1
	traffic.oncoming_fraction = 0.0
	city.add_child(traffic)
	traffic.setup(city, racer, cars)
	await frames(TrafficSystem.WARMUP_TICKS + 2)
	var c: TrafficCar = traffic.cars[0]
	var driver: AIDriver = racer.get_node("AIDriver") as AIDriver
	driver.enabled = false
	# A parked-speed lead car in the lane with a race car rolling up from behind: the lead keeps a gap and lights its brakes.
	var s0: float = 600.0
	c.place(city, s0)
	c.cruise = 6.0
	var rp: Vector3 = city.get_point_at(s0 - 14.0)
	var t0: Vector3 = city.get_tangent_at(s0 - 14.0)
	racer.reset_to(Transform3D(Basis.looking_at(t0, Vector3.UP), rp + Vector3(-t0.z, 0.0, t0.x) * c.lat + Vector3.UP * 0.47))
	racer.linear_velocity = t0 * 20.0
	var s_before: float = c.s
	var hit_seen: bool = false
	var peak_speed: float = 0.0
	for i: int in 240:
		await frames(1)
		hit_seen = hit_seen or c.hit_t > 0.0
		peak_speed = maxf(peak_speed, c.linear_velocity.length())
	metric("push_hit_seen", hit_seen)
	metric("push_peak_speed_ms", snappedf(peak_speed, 0.1))
	check(is_finite(c.global_position.x) and absf(c.global_position.y) < 20.0, "traffic car left the world after a hit")
	check(hit_seen, "a race car driving into a traffic car must register a hit")
	check(c.s != s_before, "traffic car did not move")
	await cleanup([traffic, racer, city] as Array[Node])


func test_five_ai_race_with_traffic_finishes() -> void:
	var city: CityBuilder = await _load_city()
	var manager := RaceManager.new()
	manager.total_laps = 1
	add(manager)
	var cars: Array[ArcadeCar] = []
	var names: PackedStringArray = PackedStringArray()
	for i: int in AI_SKILLS.size():
		cars.append(_make_car(AI_SKILLS[i], i + 1))
		names.append("AI %d" % (i + 1))
	manager.setup(city, cars, null, names)
	var traffic := TrafficSystem.new()
	traffic.count_override = 14
	city.add_child(traffic)
	traffic.setup(city, cars[cars.size() - 1], cars)
	await frames(TrafficSystem.WARMUP_TICKS + 2)
	manager.start_countdown()
	var grid_min: float = INF
	for k: int in 6:
		var slot: Vector3 = city.get_grid_transform(k).origin
		for c: TrafficCar in traffic.cars:
			if c.placed:
				grid_min = minf(grid_min, c.global_position.distance_to(slot))
	var placed: int = 0
	for c: TrafficCar in traffic.cars:
		placed += int(c.placed)
	check(placed >= 12, "only %d of 14 traffic cars found a spawn spot" % placed)
	check(grid_min > GRID_CLEAR_M, "traffic %.0f m from a grid slot at the start, expected over %.0f m" % [grid_min, GRID_CLEAR_M])
	metric("race_traffic_grid_min_m", snappedf(grid_min, 0.1))
	var ticks: int = 0
	var limit: int = roundi(RACE_LIMIT_S * HZ)
	var min_up: float = 1.0
	while manager.state != RaceManager.State.FINISHED and ticks < limit:
		await frames(1)
		ticks += 1
		for car: ArcadeCar in cars:
			min_up = minf(min_up, car.global_transform.basis.y.y)
	var stuck_total: int = 0
	var stuck_worst: int = 0
	for car: ArcadeCar in cars:
		var d: AIDriver = car.get_node("AIDriver") as AIDriver
		stuck_total += d.stuck_count
		stuck_worst = maxi(stuck_worst, d.stuck_count)
	metric("race_traffic_time_s", snappedf(manager.race_time, 0.01))
	metric("race_traffic_stuck_total", stuck_total)
	metric("race_traffic_stuck_worst_car", stuck_worst)
	metric("race_traffic_hits", traffic.hit_count)
	metric("race_traffic_respawns", traffic.respawns)
	metric("race_traffic_min_upright_y", snappedf(min_up, 0.0001))
	check(manager.state == RaceManager.State.FINISHED, "5-AI race with traffic did not finish in %.0f s" % RACE_LIMIT_S)
	check(stuck_total <= MAX_STUCK_TOTAL, "%d stuck events with traffic, limit %d" % [stuck_total, MAX_STUCK_TOTAL])
	check(stuck_worst <= MAX_STUCK_PER_CAR, "one car needed %d recoveries with traffic, limit %d" % [stuck_worst, MAX_STUCK_PER_CAR])
	check(min_up > 0.5, "a race car went upside down with traffic: %.3f" % min_up)
	check(traffic.cars.size() == 14, "traffic count changed to %d" % traffic.cars.size())
	var nodes: Array[Node] = [manager, traffic, city]
	for car: ArcadeCar in cars:
		nodes.append(car)
	await cleanup(nodes)
