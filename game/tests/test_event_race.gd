extends "res://tests/test_case.gd"
## A career event as the game starts it: rivals in mixed car models, ambient traffic on, autopilot player.
## The race must start, run without script errors (the runner fails on those) and keep every car upright.
## It stops long before the finish, so nothing is written to the profile.

const SCENE_PATH: String = "res://race/race_scene.tscn"
const RUN_FRAMES: int = 900  ## countdown plus about 10 s of racing


func test_event_race_runs_with_mixed_rivals_and_traffic() -> void:
	var cfg: RaceConfig = EventCatalog.config_for("wharf_sprint")
	check(cfg != null and cfg.rival_mix and cfg.traffic_enabled, "wharf_sprint should mix rival models and run traffic")
	cfg.autopilot = true
	var scene: RaceScene = (load(SCENE_PATH) as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	add(scene)
	await frames(RUN_FRAMES)
	check(scene.race != null and scene.race.state == RaceManager.State.RACING, "event race did not reach RACING")
	check(scene.get_node_or_null("World/Traffic") != null or scene.find_child("Traffic", true, false) != null, "traffic system missing")
	var models: Dictionary = {}
	var moving: int = 0
	for car: ArcadeCar in scene.cars:
		var visual: Node = car.get_node_or_null("Visual")
		if visual != null and visual.get_child_count() > 0:
			models[visual.get_child(0).scene_file_path] = true
		check(car.global_transform.basis.y.dot(Vector3.UP) > 0.5, "a car is on its side or roof")
		if car.speed_kmh > 20.0:
			moving += 1
	metric("count_car_models_on_grid", models.size())
	metric("count_cars_moving", moving)
	check(models.size() >= 2 or CarCatalog.available_ids().size() < 2, "rivals all drive the same model")
	check(moving >= scene.cars.size() - 1, "only %d of %d cars are moving after 10 s" % [moving, scene.cars.size()])
	await cleanup([scene])
