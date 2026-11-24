extends "res://tests/test_case.gd"
## Race scene assembly tests (race/race_scene.gd, race/race_config.gd, vehicles/car_factory.gd, car_visual.gd).
## Runs on the development circuit with the autopilot on. Run at --fixed-fps 60 so frames are physics ticks.

const SCENE_PATH: String = "res://race/race_scene.tscn"
const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const MISSING_PATH: String = "res://does_not_exist/none.tscn"
const CITY_TRACK_PATH: String = "res://world/city_01/city_01.tscn"
const GRID_WAIT_FRAMES: int = 60 * 6  ## 1.5 s grid beat plus 3 s countdown, with margin
const RACE_MAX_FRAMES: int = 60 * 240  ## a one-lap race on the dev circuit ends well inside this
const WHEEL_TOL_M: float = 0.001
const SAVE_TEST_PATH: String = "user://test_race_scene_save.json"

var _ticks: Array[int] = []
var _race_started_count: int = 0


func _cfg(autopilot: bool, laps: int, opponents: int) -> RaceConfig:
	var c := RaceConfig.new()
	c.autopilot = autopilot
	c.laps = laps
	c.opponent_count = opponents
	# These tests cover the dev fallbacks on purpose: force them, whatever real assets exist.
	c.track_scene = MISSING_PATH
	c.car_scene = MISSING_PATH
	return c


func _make_scene(cfg: RaceConfig) -> RaceScene:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var scene: RaceScene = packed.instantiate() as RaceScene
	scene.config = cfg
	add(scene)
	return scene


func _on_tick(n: int) -> void:
	_ticks.append(n)


func _on_started() -> void:
	_race_started_count += 1


func test_scene_instantiates_without_errors() -> void:
	var scene: RaceScene = _make_scene(_cfg(false, 1, 5))
	await frames(2)
	check(scene.race != null, "race manager was not created")
	check(scene.track != null and scene.track.length > 1000.0, "track length below 1 km: %s" % str(scene.track.length if scene.track != null else -1.0))
	check(scene.cars.size() == 6, "expected 6 cars, got %d" % scene.cars.size())
	check(scene.player == scene.cars[scene.cars.size() - 1], "player must take the last grid slot")
	check(scene.race != null and scene.race.state == RaceManager.State.GRID, "a new race must start at GRID")
	check(scene.hud != null and scene.pause_menu != null and scene.results_screen != null, "HUD, pause or results missing")
	check(not scene.results_screen.visible, "results screen must start hidden")
	await cleanup([scene])


func test_countdown_runs_and_race_starts() -> void:
	_ticks.clear()
	_race_started_count = 0
	var scene: RaceScene = _make_scene(_cfg(true, 1, 3))
	await frames(2)
	scene.race.countdown_tick.connect(_on_tick)
	scene.race.race_started.connect(_on_started)
	await frames(GRID_WAIT_FRAMES)
	check(_ticks == [3, 2, 1, 0], "countdown ticks were %s, expected [3, 2, 1, 0]" % str(_ticks))
	check(_race_started_count == 1, "race_started fired %d times" % _race_started_count)
	check(scene.race.state == RaceManager.State.RACING, "race state after GO is %d, expected RACING" % scene.race.state)
	check(scene.camera.mode == ChaseCamera.Mode.CHASE, "camera must be in CHASE at GO")
	await cleanup([scene])


func test_autopilot_completes_one_lap_with_results() -> void:
	var prev_profile_path: String = GameState.save_path
	GameState.open_profile(SAVE_TEST_PATH)
	var scene: RaceScene = _make_scene(_cfg(true, 1, 3))
	var shown: bool = false
	for i: int in RACE_MAX_FRAMES:
		await frames(1)
		if scene.results_screen.visible:
			shown = true
			break
	check(shown, "results screen never appeared")
	check(scene.last_results.size() == 4, "results had %d rows, expected 4" % scene.last_results.size())
	var player_seen: bool = false
	for r: Dictionary in scene.last_results:
		if bool(r.get("is_player", false)):
			player_seen = true
			check(float(r.get("total_time", 0.0)) > 20.0, "player lap time implausibly short")
	check(player_seen, "player missing from results")
	var wm_layer: CanvasLayer = scene.find_child("DevWatermarkLayer", true, false) as CanvasLayer
	check(wm_layer != null and wm_layer.layer > RaceScene.OVERLAY_LAYER, "dev watermark must sit above the results overlay")
	metric("results_rows", scene.last_results.size())
	if scene.last_results.size() > 0:
		metric("winner_time_s", float(scene.last_results[0].get("total_time", 0.0)))
	GameState.open_profile(prev_profile_path)
	await cleanup([scene])


func test_pause_toggles_tree_paused() -> void:
	var scene: RaceScene = _make_scene(_cfg(true, 1, 2))
	await frames(2)
	scene.pause_menu.pause()
	check(scene.get_tree().paused, "pause() did not pause the tree")
	scene.pause_menu.resume()
	check(not scene.get_tree().paused, "resume() did not unpause the tree")
	await cleanup([scene])


func test_reset_car_puts_displaced_car_back_on_line() -> void:
	var scene: RaceScene = _make_scene(_cfg(true, 3, 2))
	for i: int in RACE_MAX_FRAMES:
		await frames(1)
		if scene.race.state == RaceManager.State.RACING:
			break
	await frames(120)
	var car: ArcadeCar = scene.player
	var flipped := Transform3D(Basis(Vector3(0.0, 0.0, 1.0), PI), car.global_position + Vector3(25.0, 6.0, 0.0))
	car.reset_to(flipped)
	await frames(30)
	# Sends the real reset_car action, so the wiring in RaceScene._unhandled_input is covered too.
	var ev := InputEventAction.new()
	ev.action = "reset_car"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(1)
	check(car.linear_velocity.length() < 0.01, "reset car still moving: %.3f m/s" % car.linear_velocity.length())
	check(car.global_basis.y.dot(Vector3.UP) > 0.999, "reset car is not upright")
	var lateral: float = absf(scene.track.get_lateral_offset(car.global_position))
	check(lateral < 0.3, "reset car is %.3f m off the line" % lateral)
	var fwd: Vector3 = -car.global_basis.z
	var tangent: Vector3 = scene.track.get_tangent_at(scene.track.get_progress(car.global_position))
	check(fwd.dot(tangent) > 0.99, "reset car does not face forward")
	metric("reset_lateral_m", lateral)
	await cleanup([scene])


func test_retry_gives_fresh_race_at_grid() -> void:
	var scene: RaceScene = _make_scene(_cfg(true, 1, 2))
	for i: int in RACE_MAX_FRAMES:
		await frames(1)
		if scene.race.state == RaceManager.State.RACING:
			break
	var old_race: RaceManager = scene.race
	check(old_race.state == RaceManager.State.RACING, "race did not start before retry")
	scene.retry()
	await frames(2)
	check(scene.race != old_race, "retry kept the old race manager")
	check(scene.race.state == RaceManager.State.GRID, "retried race state %d, expected GRID" % scene.race.state)
	check(not scene.results_screen.visible, "results screen still visible after retry")
	await cleanup([scene])


func test_missing_scenes_use_fallbacks() -> void:
	var c := _cfg(true, 1, 2)
	c.track_scene = MISSING_PATH
	c.car_scene = MISSING_PATH
	var scene: RaceScene = _make_scene(c)
	await frames(30)
	check(scene.dev_track_used, "development circuit was not used for a missing track")
	check(scene.dev_car_used, "dev mule was not used for a missing car")
	check(scene.race != null and scene.race.get_car_count() == 3, "fallback race has the wrong car count")
	await cleanup([scene])


func test_wheels_follow_wheel_positions() -> void:
	var scene: RaceScene = _make_scene(_cfg(true, 1, 2))
	await frames(10)
	var worst_grid: float = _worst_wheel_error(scene.player)
	check(worst_grid < WHEEL_TOL_M, "grid wheel error %.6f m (limit 1 mm)" % worst_grid)
	for i: int in GRID_WAIT_FRAMES:
		await frames(1)
		if scene.race.state == RaceManager.State.RACING:
			break
	await frames(120)
	var worst_race: float = _worst_wheel_error(scene.player)
	check(worst_race < WHEEL_TOL_M, "racing wheel error %.6f m (limit 1 mm)" % worst_race)
	metric("wheel_error_grid_m", worst_grid)
	metric("wheel_error_racing_m", worst_race)
	await cleanup([scene])


func test_paint_sets_body_albedo() -> void:
	var scene: RaceScene = _make_scene(_cfg(true, 1, 1))
	await frames(2)
	var cv: CarVisual = scene.player.get_node("CarVisual") as CarVisual
	cv.set_paint(Color(1.0, 0.0, 0.0))
	var body: MeshInstance3D = scene.player.get_node("Visual/DevCar/body") as MeshInstance3D
	var mat: StandardMaterial3D = body.get_active_material(0) as StandardMaterial3D
	check(mat != null, "body has no duplicated paint material")
	if mat != null:
		check(mat.albedo_color.r > 0.99 and mat.albedo_color.g < 0.01, "paint not applied to body")
	await cleanup([scene])


## Real city track, dev car, so the wet road and the car fill light are the real ones.
func _cfg_city(autopilot: bool, opponents: int) -> RaceConfig:
	var c := RaceConfig.new()
	c.autopilot = autopilot
	c.laps = 1
	c.opponent_count = opponents
	c.track_scene = CITY_TRACK_PATH
	c.car_scene = MISSING_PATH
	return c


func test_planar_reflection_bound_on_real_track_by_preset() -> void:
	var prev_preset: String = Settings.get_preset_id()
	var prev_autosave: bool = Settings.autosave
	Settings.autosave = false
	Settings.set_preset("high")
	var cfg: RaceConfig = _cfg_city(true, 1)
	var scene: RaceScene = _make_scene(cfg)
	await frames(3)
	check(not scene.dev_track_used, "city_01 did not load, so the reflection test would use the dev circuit")
	check(scene._road_mats.size() > 0, "no M_Asphalt wet_asphalt material found on the city road")
	var refl: PlanarReflection = scene.find_child(RaceScene.REFLECTION_NAME, true, false) as PlanarReflection
	check(refl != null, "High: planar reflection node missing on the real track")
	if refl != null:
		check(refl.is_enabled(), "High: planar reflection not enabled")
		check(absf(refl.resolution_fraction - cfg.reflection_fraction_high) < 0.0001, "High: mirror fraction %.3f" % refl.resolution_fraction)
	for m: ShaderMaterial in scene._road_mats:
		check(m.get_shader_parameter("planar_reflection") != null, "High: road material not bound to the mirror texture")
		check(m.get_shader_parameter("planar_enabled") == 1.0, "High: road material mirror flag off")
	var road_meshes: int = 0
	for n: Node in scene.track.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh != null and _has_asphalt(mi):
			road_meshes += 1
			check(mi.layers == RaceScene.ROAD_LAYER_BIT, "road mesh %s is not on the road layer" % mi.name)
	check(road_meshes > 0, "no road mesh carries the wet asphalt material")
	Settings.set_preset("medium")
	await frames(1)
	# Lead decision 2026-11-24: Medium has no planar mirror (draw-call budget 350); it relies on
	# the wet shader's lamp streaks and the reflection probes.
	check(scene.find_child(RaceScene.REFLECTION_NAME, true, false) == null, "Medium: planar reflection must be absent")
	Settings.set_preset("low")
	await frames(1)
	check(scene.find_child(RaceScene.REFLECTION_NAME, true, false) == null, "Low: planar reflection must be absent")
	for m: ShaderMaterial in scene._road_mats:
		check(m.get_shader_parameter("planar_enabled") == 0.0, "Low: road material mirror flag still on")
	Settings.set_preset(prev_preset)
	Settings.autosave = prev_autosave
	await cleanup([scene])


func test_car_fill_light_reaches_only_the_car_layer() -> void:
	var scene: RaceScene = _make_scene(_cfg_city(true, 2))
	await frames(3)
	var fill_bit: int = 1 << RaceScene.CAR_FILL_LAYER
	var fill: OmniLight3D = scene.camera.get_node_or_null(RaceScene.FILL_LIGHT_NAME) as OmniLight3D
	check(fill != null, "car fill light missing under the chase camera")
	if fill != null:
		check(fill.light_cull_mask == fill_bit, "fill light mask %d, expected only the car layer %d" % [fill.light_cull_mask, fill_bit])
		check(not fill.shadow_enabled, "fill light must not cast shadows")
	var car_meshes: int = 0
	for car: ArcadeCar in scene.cars:
		for n: Node in car.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n as MeshInstance3D
			car_meshes += 1
			check((mi.layers & fill_bit) != 0, "car mesh %s is not on the car fill layer" % mi.name)
			check((mi.layers & 1) != 0, "car mesh %s lost its default layer" % mi.name)
	check(car_meshes > 0, "no car meshes found")
	var track_meshes: int = 0
	for n: Node in scene.track.find_children("*", "MeshInstance3D", true, false):
		var tm: MeshInstance3D = n as MeshInstance3D
		track_meshes += 1
		check((tm.layers & fill_bit) == 0, "track mesh %s is on the car fill layer" % tm.name)
	check(track_meshes > 0, "no track meshes found")
	await cleanup([scene])


func test_finished_race_pays_table_rewards() -> void:
	var prev_path: String = GameState.save_path
	GameState.open_profile(SAVE_TEST_PATH)
	var scene: RaceScene = _make_scene(_cfg(true, 1, 3))
	await frames(2)
	var cash0: int = GameState.get_cash()
	var rep0: int = GameState.get_rep()
	scene._on_race_finished(_results(1, 4))
	check(GameState.get_cash() - cash0 == GameState.REWARD_CASH[0], "1st paid %d cash, table says %d" % [GameState.get_cash() - cash0, GameState.REWARD_CASH[0]])
	check(GameState.get_rep() - rep0 == GameState.REWARD_REP[0], "1st paid %d rep, table says %d" % [GameState.get_rep() - rep0, GameState.REWARD_REP[0]])
	check(scene.results_screen.visible, "results screen not shown after the finish")
	cash0 = GameState.get_cash()
	scene._on_race_finished(_results(6, 6))
	check(GameState.get_cash() == cash0, "6th place is past the table and must pay no cash")
	GameState.open_profile(prev_path)
	await cleanup([scene])


func test_nitro_capture_hook_is_off_by_default() -> void:
	check(RaceConfig.new().force_nitro_above_kmh <= 0.0, "force_nitro_above_kmh must default to off")


func _has_asphalt(mi: MeshInstance3D) -> bool:
	for s: int in mi.mesh.get_surface_count():
		var mat: Material = mi.get_surface_override_material(s)
		if mat == null:
			mat = mi.mesh.surface_get_material(s)
		if mat is ShaderMaterial and mat.resource_name == "M_Asphalt":
			return true
	return false


## Finish rows for the reward test: the player takes player_pos, rows in finishing order.
func _results(player_pos: int, rows: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in rows:
		var pos: int = i + 1
		out.append({"name": "Driver %d" % pos, "position": pos, "total_time": 60.0 + float(i), "best_lap": 60.0 + float(i), "is_player": pos == player_pos})
	return out


## Worst difference between each wheel node's car-space origin and CarFactory-independent get_wheel_local_position.
func _worst_wheel_error(car: ArcadeCar) -> float:
	var cv: CarVisual = car.get_node("CarVisual") as CarVisual
	var worst: float = 0.0
	for i: int in 4:
		if not cv.has_wheel(i):
			return INF
		var want: Vector3 = car.get_wheel_local_position(i)
		var got: Vector3 = cv.wheel_car_origin(i)
		worst = maxf(worst, want.distance_to(got))
	return worst
