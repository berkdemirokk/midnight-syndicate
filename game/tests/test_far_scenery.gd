extends "res://tests/test_case.gd"
## Far scenery: draw and primitive budget of the slice, day has no lights, the ferry loops, and the night sky stays static
## and carries the moon uniforms.

const MAX_DRAWS: int = 16
const MAX_PRIMS: int = 22000


func test_budget_night_and_day() -> void:
	var fs := FarScenery.new()
	add(fs)
	await frames(2)
	fs.setup(null, "night")
	await frames(2)
	var night: Dictionary = fs.cost()
	metric("far_scenery_night_draws", night["draws"])
	metric("far_scenery_night_prims", night["prims"])
	check(int(night["draws"]) <= MAX_DRAWS, "night draws %d > %d" % [night["draws"], MAX_DRAWS])
	check(int(night["prims"]) <= MAX_PRIMS, "night prims %d > %d" % [night["prims"], MAX_PRIMS])
	check(int(night["draws"]) > 0, "night scenery builds nothing")
	fs.setup(null, "day")
	await frames(2)
	var day: Dictionary = fs.cost()
	metric("far_scenery_day_draws", day["draws"])
	metric("far_scenery_day_prims", day["prims"])
	check(int(day["draws"]) <= MAX_DRAWS, "day draws %d > %d" % [day["draws"], MAX_DRAWS])
	check(int(day["prims"]) < int(night["prims"]), "day should cost less than night (no lights)")
	var lights: int = 0
	for n: Node in fs.find_children("*", "MultiMeshInstance3D", true, false):
		lights += 1
	check(lights == 0, "day must have no glow point nodes, got %d" % lights)
	await cleanup([fs])


func test_ferry_loops_on_its_line() -> void:
	var fs := FarScenery.new()
	add(fs)
	await frames(2)
	fs.setup(null, "night")
	await frames(2)
	var ferry: Node3D = fs.get_node("Ferry") as Node3D
	check(ferry != null, "ferry node missing")
	var zs: Array[float] = []
	for i: int in 40:
		fs._process(60.0)  # 40 minutes of ferry time in 40 steps, several out-and-back runs
		zs.append(ferry.position.z)
		check(absf(ferry.position.x - FarScenery.FERRY_X) < 0.01, "ferry left its line")
		check(ferry.position.z >= -FarScenery.FERRY_RUN * 0.5 - 0.01 and ferry.position.z <= FarScenery.FERRY_RUN * 0.5 + 0.01,
				"ferry left its run: z %f" % ferry.position.z)
	var moved: float = 0.0
	for i: int in range(1, zs.size()):
		moved = maxf(moved, absf(zs[i] - zs[i - 1]))
	check(moved > 0.0, "ferry does not move")
	await cleanup([fs])


func test_bridge_towers_and_hill_contract() -> void:
	check(FarScenery.HIDES_ASSET == "skyline_bridge", "HIDES_ASSET must name the flat skyline card")
	check(FarScenery.hill_height(500.0, 0.0) == 0.0, "sea before the far shore must be flat zero")
	check(FarScenery.hill_height(1100.0, 0.0) > 20.0, "far shore should rise")
	check(FarScenery.cable_height(0.0) < FarScenery.cable_height(FarScenery.TOWER_X), "main cable must sag at midspan")
	check(absf(FarScenery.cable_height(FarScenery.TOWER_X) - (FarScenery.DECK_Y + FarScenery.TOWER_H)) < 0.01, "cable must meet tower top")


func test_night_sky_is_static_with_moon() -> void:
	var src: String = FileAccess.get_file_as_string("res://world/materials/night_sky.gdshader")
	check(not ("TIME" in src), "night sky must not use TIME (radiance map is drawn once)")
	for u: String in ["moon_dir", "moon_size", "moon_energy", "cloud_cover", "cloud_strength", "zenith_colour", "glow_colour"]:
		check(u in src, "night sky uniform missing: " + u)
