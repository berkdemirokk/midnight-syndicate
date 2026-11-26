extends "res://tests/test_case.gd"
## Istanbul Bogaz: AI rivals must stay on the road, not on the seaside promenade or the sidewalk beside it.
## A 5-AI one-lap race; every few frames each car's lateral offset from the centreline is checked against the
## road half-width plus a margin (the kerb is 0.3 m wide, so a wheel may touch it but the body stays on the road).
## Also checks that every grid slot is on the road. Run at --fixed-fps 60 (physics ticks = frames).

const SCENE_PATH: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const CENTRE_PATH: String = "res://assets/world/istanbul_bogaz/istanbul_bogaz_centerline.json"
const HZ: float = 60.0
const AI_COUNT: int = 5
const RACE_LIMIT_S: float = 180.0
const SAMPLE_EVERY: int = 5
const EDGE_MARGIN_M: float = 1.0
const MAX_STUCK_TOTAL: int = 8
const MAX_STUCK_PER_CAR: int = 3
var CAR_SKILLS: PackedFloat32Array = PackedFloat32Array([1.0, 0.97, 0.94, 0.91, 0.88])


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


## Lateral offset from the road centreline (not the racing line), and the road half-width there.
func _centre_offset(p: Vector3, pos: PackedVector3Array, right: PackedVector3Array, half: PackedFloat32Array) -> Vector2:
	var best: int = 0
	var best_d: float = INF
	for k: int in pos.size():
		var d: float = (pos[k].x - p.x) * (pos[k].x - p.x) + (pos[k].z - p.z) * (pos[k].z - p.z)
		if d < best_d:
			best_d = d
			best = k
	return Vector2(absf((p - pos[best]).dot(right[best])), half[best])


func test_ai_cars_stay_on_the_road() -> void:
	var track: CityBuilder = (load(SCENE_PATH) as PackedScene).instantiate() as CityBuilder
	add(track)
	await frames(1)
	var centre: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CENTRE_PATH))
	var pos := PackedVector3Array()
	var right := PackedVector3Array()
	var half := PackedFloat32Array()
	for sv: Variant in centre["samples"]:
		var sd: Dictionary = sv
		var pa: Array = sd["pos"]
		var ra: Array = sd["right"]
		pos.append(Vector3(float(pa[0]), float(pa[1]), float(pa[2])))
		right.append(Vector3(float(ra[0]), 0.0, float(ra[2])))
		half.append(float(sd["width"]) * 0.5)
	var grid_over: float = -INF
	for i: int in 8:
		var gv: Vector2 = _centre_offset(track.get_grid_transform(i).origin, pos, right, half)
		grid_over = maxf(grid_over, gv.x - gv.y)
	metric("grid_worst_over_edge_m", snappedf(grid_over, 0.01))
	check(grid_over < 0.0, "a grid slot is %.2f m past the road edge" % grid_over)
	var manager := RaceManager.new()
	manager.total_laps = 1
	add(manager)
	var cars: Array[ArcadeCar] = []
	var names: PackedStringArray = PackedStringArray()
	for i: int in AI_COUNT:
		cars.append(_make_car(CAR_SKILLS[i], i + 1))
		names.append("AI %d" % (i + 1))
	manager.setup(track, cars, null, names)
	manager.start_countdown()
	var limit_ticks: int = roundi(RACE_LIMIT_S * HZ)
	var ticks: int = 0
	var worst: float = -INF
	var worst_s: float = 0.0
	var worst_car: int = -1
	while manager.state != RaceManager.State.FINISHED and ticks < limit_ticks:
		await frames(1)
		ticks += 1
		if ticks % SAMPLE_EVERY != 0:
			continue
		for i: int in cars.size():
			var p: Vector3 = cars[i].global_position
			var lv: Vector2 = _centre_offset(p, pos, right, half)
			var lat: float = lv.x - lv.y  # how far the car centre is past the road edge (negative = on the road)
			if lat > worst:
				worst = lat
				worst_s = track.get_progress(p)
				worst_car = i
	var stuck_total: int = 0
	var stuck_worst: int = 0
	for car: ArcadeCar in cars:
		var d: AIDriver = car.get_node("AIDriver") as AIDriver
		stuck_total += d.stuck_count
		stuck_worst = maxi(stuck_worst, d.stuck_count)
	metric("worst_past_edge_m", snappedf(worst, 0.01))
	metric("worst_at_s", snappedf(worst_s, 1.0))
	metric("worst_car", worst_car)
	metric("stuck_total", stuck_total)
	check(manager.state == RaceManager.State.FINISHED, "5-car race did not finish in %.0f s" % RACE_LIMIT_S)
	check(worst <= EDGE_MARGIN_M, "car %d was %.2f m past the road edge at s=%.0f, limit %.2f" % [worst_car, worst, worst_s, EDGE_MARGIN_M])
	check(stuck_total <= MAX_STUCK_TOTAL, "%d stuck events, limit %d" % [stuck_total, MAX_STUCK_TOTAL])
	check(stuck_worst <= MAX_STUCK_PER_CAR, "one car needed %d recoveries (limit %d)" % [stuck_worst, MAX_STUCK_PER_CAR])
	var nodes: Array[Node] = [manager, track]
	for car: ArcadeCar in cars:
		nodes.append(car)
	await cleanup(nodes)
