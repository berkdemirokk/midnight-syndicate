extends "res://tests/test_case.gd"
## Racing on the real city track (world/city_01): a 6-car one-lap race must finish with every car
## classified, no stuck event in total and no car upside down; a single car over two laps must
## keep each lap within 5 % of the earlier 63.9 s lap. Causes and numbers: docs/design/AI_AND_RACE.md.

const SCENE_PATH: String = "res://world/city_01/city_01.tscn"
const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const HZ: float = 60.0
var CAR_SKILLS: PackedFloat32Array = PackedFloat32Array([1.0, 0.97, 0.94, 0.91, 0.88, 0.85])
const RACE_LIMIT_S: float = 150.0  ## simulated time a 6-car one-lap race may take
const WALL_LIMIT_S: float = 120.0  ## wall-clock time the 6-car race may take on the dev PC at --fixed-fps 60
const MAX_STUCK_TOTAL: int = 0  ## reached in round 2 (progress-based detector, slide braking, car following)
const MIN_UPRIGHT_Y: float = 0.5  ## basis.y.y below this counts as upside down
const BASELINE_LAP_S: float = 63.9  ## solo AI lap before the AI changes of this task
const LAP_LIMIT_S: float = BASELINE_LAP_S * 1.05  ## a lap may be up to 5 % slower than the baseline
const TWO_LAP_LIMIT_S: float = 2.0 * LAP_LIMIT_S

var _results: Array[Dictionary] = []
var _finished_events: int = 0
var _lap_log: Array[Dictionary] = []


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


func _on_finished(results: Array[Dictionary]) -> void:
	_finished_events += 1
	_results = results


func _on_lap(car: ArcadeCar, lap: int, lap_time: float) -> void:
	_lap_log.append({"car": car, "lap": lap, "time": lap_time})


func _load_city() -> CityBuilder:
	var city: CityBuilder = (load(SCENE_PATH) as PackedScene).instantiate() as CityBuilder
	add(city)
	return city


func test_six_car_race_finishes() -> void:
	var city: CityBuilder = await _load_city()
	var manager := RaceManager.new()
	manager.total_laps = 1
	add(manager)
	var cars: Array[ArcadeCar] = []
	var names: PackedStringArray = PackedStringArray()
	for i: int in CAR_SKILLS.size():
		cars.append(_make_car(CAR_SKILLS[i], i + 1))
		names.append("AI %d" % (i + 1))
	manager.race_finished.connect(_on_finished)
	manager.setup(city, cars, null, names)
	manager.start_countdown()
	var limit_ticks: int = roundi(RACE_LIMIT_S * HZ)
	var ticks: int = 0
	var min_up: float = 1.0
	var t0: int = Time.get_ticks_msec()
	while manager.state != RaceManager.State.FINISHED and ticks < limit_ticks:
		await frames(1)
		ticks += 1
		for car: ArcadeCar in cars:
			min_up = minf(min_up, car.global_transform.basis.y.y)
	var wall_s: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var stuck_total: int = 0
	for car: ArcadeCar in cars:
		var d: AIDriver = car.get_node("AIDriver") as AIDriver
		stuck_total += d.stuck_count
	metric("race_time_s", snappedf(manager.race_time, 0.01))
	metric("wall_s", snappedf(wall_s, 0.1))
	metric("stuck_events", stuck_total)
	metric("min_upright_y", snappedf(min_up, 0.0001))
	metric("finish_events", _finished_events)
	check(manager.state == RaceManager.State.FINISHED, "6-car race did not finish in %.0f s" % RACE_LIMIT_S)
	check(_finished_events == 1, "race_finished fired %d times, expected 1" % _finished_events)
	check(_results.size() == cars.size(), "%d cars classified, expected %d" % [_results.size(), cars.size()])
	var seen: Array[bool] = []
	seen.resize(cars.size() + 1)
	seen.fill(false)
	for r: Dictionary in _results:
		var pos: int = int(r["position"])
		if pos < 1 or pos > cars.size() or seen[pos]:
			check(false, "classification has a bad or repeated position %d" % pos)
		else:
			seen[pos] = true
		check(is_finite(float(r["total_time"])) and float(r["total_time"]) > 0.0, "position %d has no finite time" % pos)
	check(stuck_total <= MAX_STUCK_TOTAL, "%d stuck events in the race, limit %d" % [stuck_total, MAX_STUCK_TOTAL])
	check(min_up > MIN_UPRIGHT_Y, "a car went upside down: min basis.y.y %.3f" % min_up)
	check(wall_s < WALL_LIMIT_S, "6-car race took %.1f s wall-clock, limit %.0f s" % [wall_s, WALL_LIMIT_S])
	var nodes: Array[Node] = [manager, city]
	for car: ArcadeCar in cars:
		nodes.append(car)
	await cleanup(nodes)


func test_single_car_two_laps_keep_pace() -> void:
	var city: CityBuilder = await _load_city()
	var car: ArcadeCar = _make_car(1.0, 1)
	var manager := RaceManager.new()
	manager.total_laps = 2
	add(manager)
	manager.lap_completed.connect(_on_lap)
	var cars: Array[ArcadeCar] = [car]
	manager.setup(city, cars, null, PackedStringArray(["Solo"]))
	var driver: AIDriver = car.get_node("AIDriver") as AIDriver
	manager.start_countdown()
	var limit_ticks: int = roundi(TWO_LAP_LIMIT_S * 1.2 * HZ)
	var ticks: int = 0
	while manager.state != RaceManager.State.FINISHED and ticks < limit_ticks:
		await frames(1)
		ticks += 1
	check(manager.state == RaceManager.State.FINISHED, "single car did not finish 2 laps in %.0f s" % (TWO_LAP_LIMIT_S * 1.2))
	check(_lap_log.size() == 2, "single car: %d laps counted, expected 2" % _lap_log.size())
	var lap1: float = float(_lap_log[0]["time"]) if _lap_log.size() > 0 else 0.0
	var lap2: float = float(_lap_log[1]["time"]) if _lap_log.size() > 1 else 0.0
	metric("solo_lap1_s", snappedf(lap1, 0.01))
	metric("solo_lap2_s", snappedf(lap2, 0.01))
	metric("lap_limit_s", snappedf(LAP_LIMIT_S, 0.01))
	metric("stuck_events", driver.stuck_count)
	check(lap1 > 0.0 and lap1 <= LAP_LIMIT_S, "lap 1 took %.2f s, limit %.2f s (5 %% over 63.9 s)" % [lap1, LAP_LIMIT_S])
	check(lap2 > 0.0 and lap2 <= LAP_LIMIT_S, "lap 2 took %.2f s, limit %.2f s (5 %% over 63.9 s)" % [lap2, LAP_LIMIT_S])
	check(driver.stuck_count == 0, "single car was stuck %d times" % driver.stuck_count)
	var nodes: Array[Node] = [manager, car, city]
	await cleanup(nodes)
