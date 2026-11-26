extends "res://tests/test_case.gd"
## World Tour: Istanbul, track 1: "istanbul_maslak" (world/istanbul_maslak, same CityBuilder as City 01 with other paths).
## Scene build and data checks, a full 1-lap race with 5 AI cars through RaceManager (no stuck loop, every car
## classified, nobody upside down) and the same race through RaceScene + RaceConfig.track_scene (autopilot player + 5
## opponents). Run at --fixed-fps 60 (physics ticks = frames).

const SCENE_PATH: String = "res://world/istanbul_maslak/istanbul_maslak.tscn"
const RACE_SCENE_PATH: String = "res://race/race_scene.tscn"
const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const CENTRE_PATH: String = "res://assets/world/istanbul_maslak/istanbul_maslak_centerline.json"
const LAYOUT_PATH: String = "res://assets/world/istanbul_maslak/istanbul_maslak_layout.json"
const HZ: float = 60.0
const LAP_MIN_M: float = 2000.0  ## brief: about 2.0 to 2.4 km
const LAP_MAX_M: float = 2400.0
const LOAD_LIMIT_MS: float = 8000.0
const AI_COUNT: int = 5
const RACE_LIMIT_S: float = 180.0
const WALL_LIMIT_S: float = 150.0
const MAX_STUCK_TOTAL: int = 8  ## sweep limits of test_city_race: total recoveries and per car
const MAX_STUCK_PER_CAR: int = 3
const MIN_UPRIGHT_Y: float = 0.5
const RACE_MAX_FRAMES: int = 60 * 240
var CAR_SKILLS: PackedFloat32Array = PackedFloat32Array([1.0, 0.97, 0.94, 0.91, 0.88])

var _results: Array[Dictionary] = []
var _finished_events: int = 0


func _on_finished(results: Array[Dictionary]) -> void:
	_finished_events += 1
	_results = results


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


func _load_track() -> CityBuilder:
	var t: CityBuilder = (load(SCENE_PATH) as PackedScene).instantiate() as CityBuilder
	add(t)
	return t


func test_scene_builds_with_real_content() -> void:
	var t0: int = Time.get_ticks_msec()
	var track: CityBuilder = await _load_track()
	var load_ms: float = float(Time.get_ticks_msec() - t0)
	metric("load_ms", snappedf(load_ms, 1.0))
	check(load_ms < LOAD_LIMIT_MS, "scene took %.0f ms to load, limit %.0f" % [load_ms, LOAD_LIMIT_MS])
	var st: Dictionary = track.stats
	metric("first_row", int(st["first_row"]))
	metric("second_row", int(st["second_row_instances"]))
	metric("prop_instances", int(st["prop_instances"]))
	metric("lights_built", int(st["lights"]))
	metric("lights_dropped", int(st["lights_dropped"]))
	metric("crown_strips", int(st.get("crown_strips", 0)))
	metric("track_length_m", snappedf(track.length, 0.1))
	check(int(st["first_row"]) >= 100, "only %d first-row buildings" % int(st["first_row"]))
	check(int(st["missing_props"]) == 0, "%d props missing (new sign files not shipped?)" % int(st["missing_props"]))
	check(int(st.get("crown_strips", 0)) > 0, "LED crowns were not built")
	check(track.length > LAP_MIN_M and track.length < LAP_MAX_M, "track length %.1f m outside %.0f to %.0f" % [track.length, LAP_MIN_M, LAP_MAX_M])
	check(track.get_node("StartGrid").get_child_count() == 8, "grid has %d slots" % track.get_node("StartGrid").get_child_count())
	check(MaterialLibrary.report_unbound().is_empty(), "unbound materials: %s" % str(MaterialLibrary.report_unbound()))
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	var assets: Dictionary = {}
	for d: Variant in layout["instances"]:
		assets[String((d as Dictionary)["asset"])] = true
	check(assets.has("fountain_plaza"), "plaza fountain not in the layout")
	var ist_signs: int = 0
	for a: String in assets.keys():
		if a.begins_with("sign_") and (a.contains("gece") or a.contains("bogaz") or a.contains("lale") or a.contains("kule") or a.contains("yildiz") or a.contains("ay_isigi") or a.contains("cinar") or a.contains("simit") or a.contains("zumrut") or a.contains("marti") or a.contains("maslak")):
			ist_signs += 1
	metric("istanbul_sign_types", ist_signs)
	check(ist_signs >= 6, "only %d Istanbul sign types placed" % ist_signs)
	# the tinted window copies exist and the shared library material was not touched (City 01 keeps its look)
	var shared: ShaderMaterial = MaterialLibrary.get_material("M_WindowAtlas") as ShaderMaterial
	var glow: Vector3 = shared.get_shader_parameter("glow_tint")
	check(glow.x > 0.9 and glow.z < 0.7, "shared M_WindowAtlas glow tint was changed: %s" % str(glow))
	await cleanup([track])


func test_city_builder_defaults_are_city_01() -> void:
	var b := CityBuilder.new()
	check(b.layout_path == "res://assets/world/city_01/city_01_layout.json", "layout_path default changed: %s" % b.layout_path)
	check(b.road_glb == "res://assets/world/city_01/city_01_road.glb", "road_glb default changed")
	check(b.centre_path == "res://assets/world/city_01/city_01_centerline.json", "centre_path default changed")
	check(b.catalog_path == "res://assets/world/kits/buildings/catalog.json", "catalog_path default changed")
	check(b.pane_glow_tint.a == 0.0 and b.pane_albedo_tint.a == 0.0 and b.crown_color.a == 0.0, "City 01 must not get the Maslak glass or crowns")
	b.free()


func test_track_data_matches_layout() -> void:
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CENTRE_PATH))
	var l: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	check(absf(float(c["lap_length"]) - float(l["lap_length"])) < 0.01, "centreline and layout lap length differ")
	var lap: float = float(c["lap_length"])
	check(lap > LAP_MIN_M and lap < LAP_MAX_M, "lap %.1f m" % lap)
	var elev: int = 0
	var tube: int = 0
	for s: Variant in c["samples"]:
		var d: Dictionary = s
		if float((d["pos"] as Array)[1]) > 0.8:
			elev += 1
		if String(d["district_name"]) == "Underpass":
			tube += 1
	metric("elevated_samples", elev)
	metric("tunnel_samples", tube)
	check(elev > 100, "no viaduct section (%d elevated samples)" % elev)
	check(tube > 40, "no tunnel section (%d samples)" % tube)
	check((l["racing"]["grid_slots"] as Array).size() == 8, "8 grid slots expected")


func test_five_ai_cars_finish_one_lap() -> void:
	var track: CityBuilder = await _load_track()
	var manager := RaceManager.new()
	manager.total_laps = 1
	add(manager)
	var cars: Array[ArcadeCar] = []
	var names: PackedStringArray = PackedStringArray()
	for i: int in AI_COUNT:
		cars.append(_make_car(CAR_SKILLS[i], i + 1))
		names.append("AI %d" % (i + 1))
	_finished_events = 0
	_results.clear()
	manager.race_finished.connect(_on_finished)
	manager.setup(track, cars, null, names)
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
	var stuck_worst: int = 0
	for car: ArcadeCar in cars:
		var d: AIDriver = car.get_node("AIDriver") as AIDriver
		stuck_total += d.stuck_count
		stuck_worst = maxi(stuck_worst, d.stuck_count)
	metric("race_time_s", snappedf(manager.race_time, 0.01))
	metric("wall_s", snappedf(wall_s, 0.1))
	metric("stuck_total", stuck_total)
	metric("stuck_worst_car", stuck_worst)
	metric("min_upright_y", snappedf(min_up, 0.0001))
	check(manager.state == RaceManager.State.FINISHED, "5-car race did not finish in %.0f s" % RACE_LIMIT_S)
	check(_finished_events == 1, "race_finished fired %d times" % _finished_events)
	check(_results.size() == AI_COUNT, "%d cars classified, expected %d" % [_results.size(), AI_COUNT])
	for r: Dictionary in _results:
		check(is_finite(float(r["total_time"])) and float(r["total_time"]) > 20.0, "implausible finish time %s" % str(r["total_time"]))
	check(stuck_total <= MAX_STUCK_TOTAL, "%d stuck events, limit %d" % [stuck_total, MAX_STUCK_TOTAL])
	check(stuck_worst <= MAX_STUCK_PER_CAR, "one car needed %d recoveries (limit %d): stuck loop" % [stuck_worst, MAX_STUCK_PER_CAR])
	check(min_up > MIN_UPRIGHT_Y, "a car went upside down: min basis.y.y %.3f" % min_up)
	check(wall_s < WALL_LIMIT_S, "race took %.1f s wall-clock, limit %.0f" % [wall_s, WALL_LIMIT_S])
	var nodes: Array[Node] = [manager, track]
	for car: ArcadeCar in cars:
		nodes.append(car)
	await cleanup(nodes)


func test_race_scene_runs_with_track_scene_config() -> void:
	var prev_profile_path: String = GameState.save_path
	GameState.open_profile("user://test_istanbul_maslak_save.json")
	var cfg := RaceConfig.new()
	cfg.autopilot = true
	cfg.laps = 1
	cfg.opponent_count = AI_COUNT
	cfg.use_garage_paint = false
	cfg.track_scene = SCENE_PATH
	var scene: RaceScene = (load(RACE_SCENE_PATH) as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	add(scene)
	var shown: bool = false
	var min_up: float = 1.0
	for i: int in RACE_MAX_FRAMES:
		await frames(1)
		if scene.results_screen.visible:
			shown = true
			break
		if i % 30 == 0:
			for car: Node in scene.find_children("*", "ArcadeCar", true, false):
				min_up = minf(min_up, (car as ArcadeCar).global_transform.basis.y.y)
	check(shown, "results screen never appeared on istanbul_maslak")
	check(scene.track is CityBuilder and (scene.track as CityBuilder).layout_path.contains("istanbul_maslak"), "race scene did not load the Maslak track")
	check(scene.last_results.size() == AI_COUNT + 1, "results had %d rows, expected %d" % [scene.last_results.size(), AI_COUNT + 1])
	var stuck_total: int = 0
	for car: Node in scene.find_children("AIDriver", "AIDriver", true, false):
		stuck_total += (car as AIDriver).stuck_count
	metric("scene_stuck_total", stuck_total)
	metric("scene_min_upright_y", snappedf(min_up, 0.0001))
	check(min_up > MIN_UPRIGHT_Y, "a car went upside down in the race scene")
	check(stuck_total <= MAX_STUCK_TOTAL, "%d stuck events in the race scene, limit %d" % [stuck_total, MAX_STUCK_TOTAL])
	GameState.open_profile(prev_profile_path)
	await cleanup([scene])
