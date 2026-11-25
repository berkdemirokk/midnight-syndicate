extends "res://tests/test_case.gd"
## City 01 engine assembly (world/city_01): scene build, track data, ground under the line, side walls,
## one AI lap on the real track, eight cars on the grid, materials, counts and the light budget.
## Run at --fixed-fps 60 (physics ticks = frames). Metrics are recorded with metric().

const SCENE_PATH: String = "res://world/city_01/city_01.tscn"
const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const HZ: float = 60.0
const GROUND_SAMPLES: int = 60
const ROAD_HIT_TOL_M: float = 1.0
const SPAWN_LIFT_M: float = 0.5  ## spec: a car spawned 0.5 m above a grid slot
const WALL_SAMPLES_PER_SIDE: int = 6
const WALL_PUSH_MPS: float = 22.0
const WALL_RUN_S: float = 2.0
const CORRIDOR_MAX_M: float = 22.0  ## building line about 10.5 m out; waterfront quay railings about 19.8 m out
const CORRIDOR_FALL_M: float = 2.0  ## a body this far below the line has fallen off the circuit
const CENTRE_PATH: String = "res://assets/world/city_01/city_01_centerline.json"
const CATALOG_PATH: String = "res://assets/world/kits/buildings/catalog.json"
const CENTRE_SEARCH: int = 40  ## samples either side of the progress index searched for the nearest centre point
const LAP_LIMIT_S: float = 150.0
const LATERAL_MAX_M: float = 7.0
const GRID_MIN_GAP_M: float = 2.0
const GRID_SETTLE_S: float = 2.0
const LOAD_LIMIT_MS: float = 5000.0
const LAYOUT_LAP_M: float = 2203.225
const PROBE_LIMIT: int = 8
const LIGHT_LIMIT: int = 8

var _lap_log: Array[Dictionary] = []


func _load_city(parked_cars: int = -1) -> CityBuilder:
	var city: CityBuilder = (load(SCENE_PATH) as PackedScene).instantiate() as CityBuilder
	if parked_cars >= 0:
		city.parked_car_count = parked_cars
	add(city)
	await frames(2)
	return city


func _up_ray(city: Node3D, from_y: float, p: Vector3, down_m: float) -> Dictionary:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(p.x, from_y, p.z), Vector3(p.x, from_y - down_m, p.z), 1)
	return city.get_world_3d().direct_space_state.intersect_ray(q)


func _on_lap(car: ArcadeCar, lap: int, lap_time: float) -> void:
	_lap_log.append({"car": car, "lap": lap, "time": lap_time})


## Road centre samples from the centreline data shipped with the city: [pos, right] pairs, 2 m apart.
func _load_centre() -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CENTRE_PATH))
	var out: Array = []
	for v: Variant in data["samples"]:
		var d: Dictionary = v
		out.append([_v3(d["pos"]), _v3(d["right"])])
	return out


## Signed metres from the road centre (positive = right), nearest sample found near the racing progress.
func _centre_lateral(city: CityBuilder, centre: Array, p: Vector3) -> float:
	var n: int = centre.size()
	var step: float = city.length / float(n)
	var c: int = roundi(city.get_progress(p) / step)
	var best: int = 0
	var best_d: float = INF
	for k: int in range(-CENTRE_SEARCH, CENTRE_SEARCH + 1):
		var i: int = posmod(c + k, n)
		var q: Vector3 = centre[i][0]
		var d2: float = Vector2(p.x - q.x, p.z - q.z).length_squared()
		if d2 < best_d:
			best_d = d2
			best = i
	var s: Vector3 = centre[best][0]
	var r: Vector3 = centre[best][1]
	return Vector3(p.x - s.x, 0.0, p.z - s.z).dot(Vector3(r.x, 0.0, r.z))


static func _v3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func test_scene_builds_and_counts() -> void:
	var city: CityBuilder = await _load_city()
	check(city != null, "city_01.tscn did not instantiate as CityBuilder")
	if city == null:
		return
	var s: Dictionary = city.stats
	metric("load_time_ms", snappedf(city.load_time_ms, 0.1))
	check(city.load_time_ms < LOAD_LIMIT_MS, "scene load took %.0f ms" % city.load_time_ms)
	check(int(s["first_row"]) == 148, "first-row buildings %d, expected 148" % int(s["first_row"]))
	check(int(s["second_row_instances"]) == 51, "second-row LOD2 boxes %d, expected 51" % int(s["second_row_instances"]))
	check(int(s["missing_props"]) == 0, "%d props missing from the kit" % int(s["missing_props"]))
	check(int(s["probes"]) == 37, "reflection probes %d, expected 37" % int(s["probes"]))
	check(int(s["occluders"]) == int(s["first_row"]), "occluders %d for %d first-row buildings" % [int(s["occluders"]), int(s["first_row"])])
	check(MaterialLibrary.report_unbound().is_empty(), "unbound materials: %s" % str(MaterialLibrary.report_unbound()))
	var instances: int = int(s["first_row"]) + int(s["second_row_instances"]) + int(s["prop_instances"])
	var multimeshes: int = int(s["second_row_multimeshes"]) + int(s["prop_multimeshes"])
	metric("count_instances", instances)
	metric("count_multimeshes", multimeshes)
	metric("count_prop_colliders", int(s["prop_colliders"]))
	metric("count_occluders", int(s["occluders"]))
	metric("count_probes", int(s["probes"]))
	metric("count_lights_built", int(s["lights"]))
	metric("count_lights_dropped", int(s["lights_dropped"]))
	metric("count_unbound_materials", MaterialLibrary.report_unbound().size())
	# Recount the light budget from the nodes that were actually built.
	var lights: Array = []
	for n: Node in city.get_node("Lighting").get_children():
		if n is SpotLight3D:
			lights.append({"type": "spot", "pos": (n as Node3D).global_position, "range": (n as SpotLight3D).spot_range})
		elif n is OmniLight3D:
			lights.append({"type": "omni", "pos": (n as Node3D).global_position, "range": (n as OmniLight3D).omni_range})
	var worst: Dictionary = CityLights.worst_per_volume(lights, city.light_volumes)
	metric("light_worst_per_mesh_omni", int(worst["omni"]))
	metric("light_worst_per_mesh_spot", int(worst["spot"]))
	check(int(worst["omni"]) <= LIGHT_LIMIT and int(worst["spot"]) <= LIGHT_LIMIT,
		"a mesh is touched by more than 8 of one light type: %s" % str(worst))
	# Probes touching one volume (AABB overlap), same rule as the light budget.
	var probe_boxes: Array[AABB] = []
	for n: Node in city.get_node("Lighting/ReflectionProbes").get_children():
		var rp: ReflectionProbe = n as ReflectionProbe
		probe_boxes.append(AABB((rp.global_position - rp.size * 0.5), rp.size))
	var worst_probes: int = 0
	for v: AABB in city.light_volumes:
		var k: int = 0
		for b: AABB in probe_boxes:
			if b.intersects(v):
				k += 1
		worst_probes = maxi(worst_probes, k)
	metric("probe_worst_per_mesh", worst_probes)
	check(worst_probes <= PROBE_LIMIT, "a mesh is touched by %d reflection probes" % worst_probes)
	metric("light_budget_log", city.light_report.get("log", PackedStringArray()).size())
	var nodes: Array[Node] = [city]
	await cleanup(nodes)


func test_track_data_and_grid() -> void:
	var city: CityBuilder = await _load_city()
	var rel: float = absf(city.length - LAYOUT_LAP_M) / LAYOUT_LAP_M
	metric("track_length_m", snappedf(city.length, 0.01))
	metric("track_length_rel_err", snappedf(rel, 0.0001))
	check(rel <= 0.01, "track length %.1f m vs layout %.1f m (%.2f%%)" % [city.length, LAYOUT_LAP_M, rel * 100.0])
	var closed: float = city.get_point_at(city.length).distance_to(city.get_point_at(0.0))
	check(closed < 0.5, "racing line is not closed: gap %.2f m" % closed)
	for i: int in 8:
		var g: Transform3D = city.get_grid_transform(i)
		var t: Vector3 = city.get_tangent_at(city.get_progress(g.origin))
		check((-g.basis.z).dot(t) > 0.99, "Grid%d does not face the race direction" % i)
	var nodes: Array[Node] = [city]
	await cleanup(nodes)


func test_ground_under_the_line() -> void:
	var city: CityBuilder = await _load_city()
	var hits: int = 0
	var worst_dy: float = 0.0
	for i: int in GROUND_SAMPLES:
		var s: float = city.length * float(i) / float(GROUND_SAMPLES)
		var p: Vector3 = city.get_point_at(s)
		var r: Dictionary = _up_ray(city, p.y + 3.0, p, 6.0)
		if not r.is_empty():
			hits += 1
			worst_dy = maxf(worst_dy, absf((r["position"] as Vector3).y - p.y))
	metric("ground_hits", hits)
	metric("ground_worst_dy_m", snappedf(worst_dy, 0.01))
	check(hits == GROUND_SAMPLES, "ground missing under %d of %d line samples" % [GROUND_SAMPLES - hits, GROUND_SAMPLES])
	var grid_hits: int = 0
	for i: int in 8:
		var g: Transform3D = city.get_grid_transform(i)
		var spawn: Vector3 = g.origin + Vector3.UP * SPAWN_LIFT_M
		var r: Dictionary = _up_ray(city, spawn.y, spawn, 2.0)
		if not r.is_empty() and absf((r["position"] as Vector3).y - (spawn.y - SPAWN_LIFT_M - CityBuilder.GRID_REST_M)) < ROAD_HIT_TOL_M:
			grid_hits += 1
	check(grid_hits == 8, "grid slots without road within %.1f m below a spawn 0.5 m above: %d of 8 found" % [ROAD_HIT_TOL_M, grid_hits])
	var nodes: Array[Node] = [city]
	await cleanup(nodes)


func test_side_walls_hold() -> void:
	var city: CityBuilder = await _load_city()
	var track: Track = city
	var worst: Dictionary = {"left": 0.0, "right": 0.0}
	var spheres: Array[Node] = []
	for side: int in [-1, 1]:
		var key: String = "left" if side < 0 else "right"
		for k: int in WALL_SAMPLES_PER_SIDE:
			var s: float = city.length * (float(k) + 0.5) / float(WALL_SAMPLES_PER_SIDE)
			var c: Vector3 = track.get_point_at(s)
			var t: Vector3 = track.get_tangent_at(s)
			var right: Vector3 = Vector3(-t.z, 0.0, t.x)
			var body := RigidBody3D.new()
			body.collision_layer = 2
			body.collision_mask = 1
			body.mass = 1.0
			var shape := CollisionShape3D.new()
			var ball := SphereShape3D.new()
			ball.radius = 0.4
			shape.shape = ball
			body.add_child(shape)
			body.position = c + Vector3.UP * 0.8
			add(body)
			spheres.append(body)
			await frames(1)
			body.linear_velocity = right * float(side) * WALL_PUSH_MPS
			await frames(roundi(WALL_RUN_S * HZ))
			var lat: float = absf(track.get_lateral_offset(body.global_position))
			worst[key] = maxf(float(worst[key]), lat)
			var fell: bool = body.global_position.y < c.y - CORRIDOR_FALL_M
			check(lat <= CORRIDOR_MAX_M and not fell, "%s push at %.0f m left the corridor: %.1f m, height %.1f m" % [key, s, lat, body.global_position.y])
			body.queue_free()
			await frames(1)
	metric("wall_max_lateral_left_m", snappedf(float(worst["left"]), 0.1))
	metric("wall_max_lateral_right_m", snappedf(float(worst["right"]), 0.1))
	var nodes: Array[Node] = [city]
	await cleanup(nodes)


func test_single_ai_lap() -> void:
	var city: CityBuilder = await _load_city()
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	var d := AIDriver.new()
	d.name = "AIDriver"
	d.skill = 1.0
	d.lane_offset = 0.0
	d.noise_seed = 1
	car.add_child(d)
	var manager := RaceManager.new()
	manager.total_laps = 1
	add(manager)
	manager.lap_completed.connect(_on_lap)
	var cars: Array[ArcadeCar] = [car]
	manager.setup(city, cars, null, PackedStringArray(["Solo"]))
	manager.start_countdown()
	var max_lat: float = 0.0  ## from the road centreline: the road is 14 m wide
	var max_lat_s: float = 0.0
	var max_line: float = 0.0  ## from the racing line, which is shifted up to 3.5 m from the centre
	var ticks: int = 0
	var stuck_seen: int = 0
	var stuck_at: Array = []
	var centre: Array = _load_centre()
	while manager.state != RaceManager.State.FINISHED and ticks < roundi(LAP_LIMIT_S * HZ):
		await frames(1)
		ticks += 1
		var p: Vector3 = car.global_position
		var lat: float = absf(_centre_lateral(city, centre, p))
		if lat > max_lat:
			max_lat = lat
			max_lat_s = city.get_progress(p)
			metric("ai_max_lat_at_s", snappedf(max_lat_s, 0.1))
		max_line = maxf(max_line, absf(city.get_lateral_offset(p)))
		if d.stuck_count > stuck_seen:
			stuck_seen = d.stuck_count
			metric("ai_stuck_at_s_%d" % stuck_seen, snappedf(city.get_progress(p), 0.1))
			stuck_at.append(snappedf(city.get_progress(p), 0.1))
	check(manager.state == RaceManager.State.FINISHED, "AI car did not finish a lap in %.0f s" % LAP_LIMIT_S)
	var lap_time: float = float(_lap_log[0]["time"]) if _lap_log.size() > 0 else 0.0
	metric("ai_lap_time_s", snappedf(lap_time, 0.01))
	metric("ai_max_abs_lateral_m", snappedf(max_lat, 0.01))
	metric("ai_max_abs_line_offset_m", snappedf(max_line, 0.01))
	metric("ai_stuck_events", d.stuck_count)
	check(_lap_log.size() == 1, "AI lap count %d, expected 1" % _lap_log.size())
	check(max_lat < LATERAL_MAX_M, "AI car left the road: max lateral %.2f m from the centre at s=%.1f" % [max_lat, max_lat_s])
	check(d.stuck_count == 0, "AI car was stuck %d times at s=%s" % [d.stuck_count, str(stuck_at)])
	var nodes: Array[Node] = [manager, car, city]
	await cleanup(nodes)


func test_eight_cars_on_grid() -> void:
	var city: CityBuilder = await _load_city()
	var manager := RaceManager.new()
	manager.total_laps = 1
	add(manager)
	var cars: Array[ArcadeCar] = []
	for i: int in 8:
		var car := ArcadeCar.new()
		car.spec = load(SPEC_PATH) as CarSpec
		add(car)
		cars.append(car)
	manager.setup(city, cars, null, PackedStringArray())
	for car: ArcadeCar in cars:
		car.set_frozen_for_grid(false)
	await frames(roundi(GRID_SETTLE_S * HZ))
	var min_gap: float = INF
	var worst_rest: float = 0.0
	for i: int in cars.size():
		var p: Vector3 = cars[i].global_position
		var ground: Dictionary = _up_ray(city, p.y + 1.0, p, 3.0)
		if ground.is_empty():
			check(false, "grid car %d has no road below it" % i)
			continue
		var rest: float = p.y - (ground["position"] as Vector3).y
		worst_rest = maxf(worst_rest, absf(rest - CityBuilder.GRID_REST_M))
		for j: int in range(i + 1, cars.size()):
			min_gap = minf(min_gap, p.distance_to(cars[j].global_position))
	metric("grid_min_gap_m", snappedf(min_gap, 0.01))
	metric("grid_rest_error_m", snappedf(worst_rest, 0.01))
	check(min_gap >= GRID_MIN_GAP_M, "grid cars closer than %.1f m: %.2f m" % [GRID_MIN_GAP_M, min_gap])
	check(worst_rest < 0.3, "grid cars not resting on the road: error %.2f m" % worst_rest)
	var nodes: Array[Node] = [manager, city]
	for car: ArcadeCar in cars:
		nodes.append(car)
	await cleanup(nodes)


## Every building footprint and every box collider of the props must stay outside the corridor (kerb line + 0.5 m).
## Sampled every 2 m along the centreline and across the corridor in 0.5 m steps, at car height.
func test_no_collider_in_corridor() -> void:
	var city: CityBuilder = await _load_city()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var sizes: Dictionary = {}
	for b: Variant in catalog["buildings"]:
		var bd: Dictionary = b
		sizes[String(bd["id"])] = bd["collider"]
	# Boxes as {xf: inverse world transform, half: half size, skip: false}. Buildings from the built nodes.
	var boxes: Array[Dictionary] = []
	for n: Node in city.get_node("Geometry/FirstRow").get_children():
		var asset: String = String(n.name).left(-4)
		if not sizes.has(asset):
			continue
		var c: Dictionary = sizes[asset]
		var cen: Vector3 = _v3(c["center"])
		var sz: Vector3 = _v3(c["size"])
		var g: Transform3D = (n as Node3D).global_transform * Transform3D(Basis(), cen)
		boxes.append({"inv": g.affine_inverse(), "half": sz * 0.5, "pos": g.origin, "name": String(n.name)})
	var prop_boxes: int = 0
	var prop_skipped: int = 0
	for body: Node in city.get_node("Geometry").get_children():
		if not String(body.name).begins_with("Colliders_"):
			continue
		for cs: Node in body.get_children():
			if not cs is CollisionShape3D:
				continue
			var shape: Shape3D = (cs as CollisionShape3D).shape
			if not shape is BoxShape3D:
				prop_skipped += 1
				continue
			var g: Transform3D = (cs as Node3D).global_transform
			boxes.append({"inv": g.affine_inverse(), "half": (shape as BoxShape3D).size * 0.5, "pos": g.origin, "name": "prop " + String(cs.name)})
			prop_boxes += 1
	var cdata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CENTRE_PATH))
	var samples: Array = cdata["samples"]
	var edges: Array = cdata["edges"]
	var hits: int = 0
	var first_hit: String = ""
	var checked: int = 0
	for i: int in samples.size():
		var sp: Vector3 = _v3((samples[i] as Dictionary)["pos"])
		var sr: Vector3 = _v3((samples[i] as Dictionary)["right"])
		var e: Dictionary = edges[i]
		var half: float = maxf(Vector2(_v3(e["left_kerb"]).x - sp.x, _v3(e["left_kerb"]).z - sp.z).length(),
			Vector2(_v3(e["right_kerb"]).x - sp.x, _v3(e["right_kerb"]).z - sp.z).length()) + 0.5
		var near: Array[Dictionary] = []
		for b: Dictionary in boxes:
			var bp: Vector3 = b["pos"]
			if Vector2(bp.x - sp.x, bp.z - sp.z).length() < 40.0:
				near.append(b)
		var t: float = -half
		while t <= half:
			var p: Vector3 = sp + sr * t
			p.y = sp.y + 0.5
			checked += 1
			for b: Dictionary in near:
				var l: Vector3 = (b["inv"] as Transform3D) * p
				var h: Vector3 = b["half"]
				if absf(l.x) <= h.x and absf(l.y) <= h.y and absf(l.z) <= h.z:
					hits += 1
					if first_hit == "":
						first_hit = "%s at sample %d, lateral %.1f m" % [String(b["name"]), i, t]
					break
			t += 0.5
	metric("corridor_points_checked", checked)
	metric("corridor_hits", hits)
	metric("corridor_pushes", (city.stats["corridor_pushes"] as Array).size())
	metric("prop_box_colliders", prop_boxes)
	metric("prop_nonbox_colliders_skipped", prop_skipped)
	check(hits == 0, "%d corridor samples inside a collider, first: %s" % [hits, first_hit])
	var nodes: Array[Node] = [city]
	await cleanup(nodes)


## Parked cars (off by default until a low-poly traffic car exists; the placement is tested with 90):
## 60 to 120 on the kerb side, no colliders, and every car corner outside the corridor margin.
func test_street_dressing() -> void:
	var city: CityBuilder = await _load_city()
	var rows: Array = city.stats["dressing"]
	var centre: Array = _load_centre()
	var corridor_bad: int = 0
	var lane_short: int = 0
	var kerb_bad: int = 0
	var n_bollard_wf: int = 0
	var n_bench_wf: int = 0
	var n_lamp_wf: int = 0
	var n_shelter_dt: int = 0
	var n_stack: int = 0
	var n_crane: int = 0
	for row: Dictionary in rows:
		var kit: String = row["kit"]
		var district: String = row["district"]
		var walks: bool = not (kit in ["container_stack", "gantry_crane"])
		var lat: float = _centre_lateral(city, centre, _v3(row["pos"]))
		if float(row["worst_margin"]) > -city.dress_clear_m + 0.01:
			corridor_bad += 1
		if walks and absf(lat) < 7.0:
			kerb_bad += 1  # a sidewalk prop inside the kerb line
		if walks and float(row["walk_m"]) < city.dress_walk_m - 0.01:
			lane_short += 1
		if kit == "bollard" and district == "waterfront":
			n_bollard_wf += 1
		if kit == "bench" and district == "waterfront":
			n_bench_wf += 1
		if kit == "lamp_sodium" and district == "waterfront":
			n_lamp_wf += 1
		if kit == "bus_shelter" and district == "downtown":
			n_shelter_dt += 1
		if kit == "container_stack":
			n_stack += 1
		if kit == "gantry_crane":
			n_crane += 1
	metric("dressing_placed", rows.size())
	metric("dressing_missed", str(city.stats["dressing_missed"]))
	metric("dressing_bollards_waterfront", n_bollard_wf)
	metric("dressing_benches_waterfront", n_bench_wf)
	metric("dressing_lamps_waterfront", n_lamp_wf)
	metric("dressing_shelters_downtown", n_shelter_dt)
	metric("waterfront_lamps_kept", str(city.stats["waterfront_lamps_kept"]))
	check(corridor_bad == 0, "%d dressing props reach into the corridor" % corridor_bad)
	check(kerb_bad == 0, "%d sidewalk props sit inside the kerb line" % kerb_bad)
	check(lane_short == 0, "%d sidewalk props leave less than %.1f m of walking lane" % [lane_short, city.dress_walk_m])
	check(n_bollard_wf >= 60, "waterfront quay bollards %d, expected at least 60 (every 6 m)" % n_bollard_wf)
	check(n_bench_wf >= 8, "waterfront benches %d, expected at least 8" % n_bench_wf)
	check(n_lamp_wf >= 3, "waterfront sodium lamps added %d, expected at least 3" % n_lamp_wf)
	check(n_shelter_dt >= 1, "downtown bus shelters %d, expected at least 1" % n_shelter_dt)
	check(n_stack == 2 and int(city.stats["dressing_counts"].get("gantry_crane", 0)) == 1,
		"waterfront lot: %d container stacks and %d cranes, expected 2 and 1" % [n_stack, n_crane])
	var nodes: Array[Node] = [city]
	await cleanup(nodes)


func test_parked_cars_outside_corridor() -> void:
	var city: CityBuilder = await _load_city(90)
	var s: Dictionary = city.stats
	var count: int = int(s["parked_cars"])
	metric("parked_cars", count)
	metric("parked_candidates", int(s["parked_candidates"]))
	metric("parked_worst_margin_m", snappedf(float(s["parked_worst_margin_m"]), 0.01))
	check(count >= 60 and count <= 120, "parked cars %d, expected 60 to 120" % count)
	check(float(s["parked_worst_margin_m"]) <= city.parked_worst_limit_m,
		"a parked car corner is %.2f m into the corridor margin" % float(s["parked_worst_margin_m"]))
	var colliders: int = city.get_node("Geometry/ParkedCars").find_children("*", "CollisionShape3D", true, false).size()
	check(colliders == 0, "parked cars have %d colliders, expected none" % colliders)
	var nodes: Array[Node] = [city]
	await cleanup(nodes)
