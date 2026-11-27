extends "res://tests/test_case.gd"
## Day bounce (world/time_of_day/day_bounce.gd): the pure rules (which frontage gets a strip, the gradient), the
## build on the real city at day (two MultiMesh draw calls, one fill light, no shadows), and nothing at night or sunset.

const CITY_PATH: String = "res://world/city_01/city_01.tscn"


func test_faces_road_rule() -> void:
	check(DayBounce.faces_road(Vector3(1, 0, 0), Vector3(5, 0, 0)), "road ahead of the outward edge gets a strip")
	check(not DayBounce.faces_road(Vector3(1, 0, 0), Vector3(-5, 0, 0)), "wall with the road behind it gets none")
	check(not DayBounce.faces_road(Vector3(1, 0, 0), Vector3(0, 0, 0)), "no road vector, no strip")


func test_shade_gradient() -> void:
	check(is_equal_approx(DayBounce.shade_alpha(0.0, 0.5), 0.5), "darkest at the wall")
	check(is_equal_approx(DayBounce.shade_alpha(1.0, 0.5), 0.0), "clear at the outer edge")
	check(DayBounce.shade_alpha(0.5, 0.5) < 0.5 and DayBounce.shade_alpha(0.5, 0.5) > 0.0, "falls off between")
	check(is_equal_approx(DayBounce.shade_alpha(-3.0, 0.5), 0.5), "clamped below 0")


func test_city_day_build() -> void:
	var cfg := RaceConfig.new()
	cfg.autopilot = true
	cfg.opponent_count = 0
	cfg.track_scene = CITY_PATH
	cfg.time_of_day = "day"
	var scene: RaceScene = (load("res://race/race_scene.tscn") as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	add(scene)
	await frames(5)
	var b: Node = scene.track.find_child("DayBounce", true, false)
	check(b != null, "day builds the bounce node")
	if b != null:
		var mmis: int = b.find_children("*", "MultiMeshInstance3D", false, false).size()
		check(mmis == 2, "two strip draw calls (fronts, kerbs), got %d" % mmis)
		var fill: DirectionalLight3D = b.find_child("DayFill", false, false) as DirectionalLight3D
		check(fill != null and not fill.shadow_enabled and fill.light_energy <= 0.5, "warm fill, low and shadowless")
	scene.queue_free()
	await frames(2)
	# night must never build it
	var night_cfg := RaceConfig.new()
	night_cfg.autopilot = true
	night_cfg.opponent_count = 0
	night_cfg.track_scene = CITY_PATH
	var night_scene: RaceScene = (load("res://race/race_scene.tscn") as PackedScene).instantiate() as RaceScene
	night_scene.config = night_cfg
	add(night_scene)
	await frames(5)
	check(night_scene.track.find_child("DayBounce", true, false) == null, "night has no day bounce")
	night_scene.queue_free()
	await frames(2)
