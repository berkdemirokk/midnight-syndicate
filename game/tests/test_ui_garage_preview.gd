extends "res://tests/test_case.gd"
## Garage upgrade preview: the stats after one more level rise only for the stats that part affects,
## equal the stats of really owning that level, and a maxed part previews nothing new.

const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"


func test_preview_matches_owning_the_next_level() -> void:
	var spec: CarSpec = load(SPEC_PATH) as CarSpec
	var owned: Dictionary = {"engine": 1, "tires": 0, "nitro": 0, "weight": 0}
	var now: Dictionary = GarageStats.compute(spec, owned)
	var prev: Dictionary = GarageStats.preview_next(spec, owned, "tires")
	var real: Dictionary = GarageStats.compute(spec, {"engine": 1, "tires": 1, "nitro": 0, "weight": 0})
	for s: String in ["speed", "accel", "handling", "nitro"]:
		check(absf(float(prev[s]) - float(real[s])) < 0.000001, "preview of tires equals owning tires 1 (%s)" % s)
	check(float(prev["handling"]) > float(now["handling"]), "tyres preview raises handling")
	check(is_equal_approx(float(prev["speed"]), float(now["speed"])), "tyres preview leaves top speed alone")
	check(is_equal_approx(float(prev["nitro"]), float(now["nitro"])), "tyres preview leaves nitro alone")


func test_preview_of_engine_and_weight_moves_speed_and_acceleration() -> void:
	var spec: CarSpec = load(SPEC_PATH) as CarSpec
	var base: Dictionary = {"engine": 0, "tires": 0, "nitro": 0, "weight": 0}
	var now: Dictionary = GarageStats.compute(spec, base)
	var engine: Dictionary = GarageStats.preview_next(spec, base, "engine")
	check(float(engine["speed"]) > float(now["speed"]), "engine preview raises top speed")
	check(float(engine["accel"]) > float(now["accel"]), "engine preview raises acceleration")
	var weight: Dictionary = GarageStats.preview_next(spec, base, "weight")
	check(float(weight["accel"]) > float(now["accel"]), "weight preview raises acceleration")
	check(is_equal_approx(float(weight["speed"]), float(now["speed"])), "weight preview leaves top speed alone")


func test_maxed_part_previews_its_current_stats() -> void:
	var spec: CarSpec = load(SPEC_PATH) as CarSpec
	var maxed: Dictionary = {"engine": GameState.MAX_UPGRADE_LEVEL, "tires": 0, "nitro": 0, "weight": 0}
	var now: Dictionary = GarageStats.compute(spec, maxed)
	var prev: Dictionary = GarageStats.preview_next(spec, maxed, "engine")
	for s: String in ["speed", "accel", "handling", "nitro"]:
		check(is_equal_approx(float(prev[s]), float(now[s])), "maxed engine previews the same %s" % s)
	check(maxed["engine"] == GameState.MAX_UPGRADE_LEVEL, "preview does not change the level dictionary")
