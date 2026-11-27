extends "res://tests/test_case.gd"
## Police pursuit (race/pursuit/): opt-in gating, spawn caps per heat, spawn spot behind the player, despawn,
## roadblock layout and placement, bust and escape through PursuitState on a real race scene (dev circuit, player
## parked on the grid). Every test switches PursuitMode.ENABLED on and restores it.

const SCENE_PATH: String = "res://race/race_scene.tscn"
const MISSING_PATH: String = "res://does_not_exist/none.tscn"
const STEP_S: float = 1.0 / 60.0
const SPAWN_BEHIND_MIN_M: float = 70.0
const SPAWN_BEHIND_MAX_M: float = 90.0


func _cfg(pursuit: bool) -> RaceConfig:
	var c := RaceConfig.new()
	c.autopilot = false
	c.laps = 1
	c.opponent_count = 2
	c.pursuit = pursuit
	# The dev circuit and the dev car: no real asset needed, same as test_race_scene.
	c.track_scene = MISSING_PATH
	c.car_scene = MISSING_PATH
	return c


func _make_scene(cfg: RaceConfig) -> RaceScene:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var scene: RaceScene = packed.instantiate() as RaceScene
	scene.config = cfg
	add(scene)
	return scene


func _pursuit_of(scene: RaceScene) -> PursuitMode:
	return scene.find_child("PursuitMode", true, false) as PursuitMode


func _progress(scene: RaceScene, p: Vector3) -> float:
	return scene.track.get_progress(p)


func test_normal_race_has_no_police_node() -> void:
	var was: bool = PursuitMode.ENABLED
	PursuitMode.ENABLED = true
	var scene: RaceScene = _make_scene(_cfg(false))
	await frames(2)
	check(_pursuit_of(scene) == null, "pursuit false must not add a PursuitMode node")
	check(scene.cars.size() == 3, "normal race car count changed: %d" % scene.cars.size())
	await cleanup([scene])
	PursuitMode.ENABLED = was


func test_kill_switch_blocks_config_flag() -> void:
	var was: bool = PursuitMode.ENABLED
	PursuitMode.ENABLED = false
	var scene: RaceScene = _make_scene(_cfg(true))
	await frames(2)
	check(_pursuit_of(scene) == null, "ENABLED false must block a pursuit race")
	await cleanup([scene])
	PursuitMode.ENABLED = was


func test_pursuit_race_adds_one_node_with_player() -> void:
	var was: bool = PursuitMode.ENABLED
	PursuitMode.ENABLED = true
	var scene: RaceScene = _make_scene(_cfg(true))
	await frames(2)
	var pm: PursuitMode = _pursuit_of(scene)
	check(pm != null, "pursuit race must add a PursuitMode node")
	check(pm != null and pm.player == scene.player, "PursuitMode must follow the race player")
	check(scene.race.get_car_count() == scene.cars.size(), "police must not join the race car list")
	await cleanup([scene])
	PursuitMode.ENABLED = was


func test_max_police_per_heat() -> void:
	var expected: Array[int] = [1, 2, 2, 3, 3]
	for h: int in range(1, 6):
		check(PursuitMode.max_police_for_heat(h) == expected[h - 1], "heat %d cap %d" % [h, PursuitMode.max_police_for_heat(h)])
	check(PursuitMode.max_police_for_heat(0) == 0, "heat 0 must allow no police")


func test_spawn_counts_per_heat() -> void:
	var was: bool = PursuitMode.ENABLED
	PursuitMode.ENABLED = true
	var scene: RaceScene = _make_scene(_cfg(true))
	await frames(2)
	var pm: PursuitMode = _pursuit_of(scene)
	for h: int in range(1, 6):
		pm.state.heat = h
		pm.top_up()
		check(pm.police.size() == PursuitMode.max_police_for_heat(h), "heat %d: %d police, expected %d" % [h, pm.police.size(), PursuitMode.max_police_for_heat(h)])
	await cleanup([scene])
	PursuitMode.ENABLED = was


func test_police_spawn_behind_player() -> void:
	var was: bool = PursuitMode.ENABLED
	PursuitMode.ENABLED = true
	var scene: RaceScene = _make_scene(_cfg(true))
	await frames(2)
	var pm: PursuitMode = _pursuit_of(scene)
	pm.state.heat = 3
	pm.top_up()
	check(pm.police.size() == 2, "heat 3 should have 2 police, got %d" % pm.police.size())
	var s_player: float = _progress(scene, scene.player.global_position)
	for c: ArcadeCar in pm.police:
		var behind: float = -scene.track.get_progress(c.global_position) + s_player
		var d: float = fposmod(behind + scene.track.length * 0.5, scene.track.length) - scene.track.length * 0.5
		check(d >= SPAWN_BEHIND_MIN_M and d <= SPAWN_BEHIND_MAX_M, "police spawned %.1f m behind, expected %.0f..%.0f" % [d, SPAWN_BEHIND_MIN_M, SPAWN_BEHIND_MAX_M])
	await cleanup([scene])
	PursuitMode.ENABLED = was


func test_despawn_far_behind() -> void:
	var was: bool = PursuitMode.ENABLED
	PursuitMode.ENABLED = true
	var scene: RaceScene = _make_scene(_cfg(true))
	await frames(2)
	var pm: PursuitMode = _pursuit_of(scene)
	pm.start()
	pm.state.heat = 5
	pm.top_up()
	check(pm.police.size() == 3, "heat 5 should spawn 3 police, got %d" % pm.police.size())
	var far: ArcadeCar = pm.police[0]
	var s_player: float = scene.track.get_progress(scene.player.global_position)
	var p: Vector3 = scene.track.get_point_at(s_player - PursuitMode.DESPAWN_M - 50.0)
	far.global_position = p + Vector3(0.0, PursuitMode.SPAWN_HEIGHT_M, 0.0)
	var before: int = pm.police.size()
	pm._spawn_t = INF  # no replacement spawn in this step
	pm.step(STEP_S)
	check(pm.police.size() == before - 1, "police 300 m back should be removed: %d -> %d" % [before, pm.police.size()])
	check(not pm.police.has(far), "the far police car is still listed")
	await cleanup([scene])
	PursuitMode.ENABLED = was


func test_roadblock_layout_leaves_a_lane_open() -> void:
	check(Roadblock.layout(5.0).is_empty(), "a 5 m road must not get a roadblock")
	for w: float in [14.0, 10.0, 8.0]:
		var offs: PackedFloat32Array = Roadblock.layout(w)
		check(offs.size() >= Roadblock.MIN_BARRIERS and offs.size() <= Roadblock.MAX_BARRIERS, "width %.0f: %d barriers" % [w, offs.size()])
		if offs.is_empty():
			continue
		var right_edge: float = offs[offs.size() - 1] + Roadblock.BARRIER_WIDTH_M * 0.5
		check(w * 0.5 - right_edge >= Roadblock.OPEN_LANE_M, "width %.0f: open lane %.2f m" % [w, w * 0.5 - right_edge])
		check(offs[0] - Roadblock.BARRIER_WIDTH_M * 0.5 >= -w * 0.5, "width %.0f: barrier past the left kerb" % w)
	metric("roadblock_layout_14m", Array(Roadblock.layout(14.0)))


func test_roadblock_placement_is_safe() -> void:
	var was: bool = PursuitMode.ENABLED
	PursuitMode.ENABLED = true
	var scene: RaceScene = _make_scene(_cfg(true))
	await frames(2)
	var pm: PursuitMode = _pursuit_of(scene)
	pm.start()
	pm.state.heat = 3
	# Set the player's progress directly: step() would also place a roadblock by itself at heat 3.
	pm._player_s = scene.track.get_progress(scene.player.global_position)
	check(pm.try_roadblock(), "heat 3 roadblock should place on the dev circuit")
	check(pm.roadblock != null, "roadblock not stored")
	if pm.roadblock != null:
		var ahead: float = fposmod(pm.roadblock.progress - pm._player_s + scene.track.length * 0.5, scene.track.length) - scene.track.length * 0.5
		check(ahead >= 150.0 - 1.0 and ahead <= 200.0 + 1.0, "roadblock %.1f m ahead, expected 150..200" % ahead)
		check(not pm.try_roadblock(), "a second roadblock must not stack on the first")
		var min_car: float = INF
		for b: Node in pm.roadblock.get_children():
			var body: Node3D = b as Node3D
			for c: ArcadeCar in scene.cars:
				min_car = minf(min_car, body.global_position.distance_to(c.global_position))
		check(min_car >= Roadblock.CLEAR_M, "barrier %.1f m from a car" % min_car)
		metric("roadblock_min_car_m", min_car)
	# A car on the barrier line means no barrier at all.
	var centre: Vector3 = scene.track.get_point_at(pm._player_s + 160.0)
	check(Roadblock.build(scene.track, pm._player_s + 160.0, PackedVector3Array([centre])) == null, "barrier built on top of a car")
	await cleanup([scene])
	PursuitMode.ENABLED = was


func test_bust_when_parked_next_to_police() -> void:
	var was: bool = PursuitMode.ENABLED
	PursuitMode.ENABLED = true
	var scene: RaceScene = _make_scene(_cfg(true))
	await frames(2)
	var pm: PursuitMode = _pursuit_of(scene)
	pm.start()
	pm.top_up()
	check(pm.police.size() == 1, "heat 1 should spawn one police car")
	# No physics frames run between these steps, so the parked player and the placed police stay put.
	var car: ArcadeCar = pm.police[0]
	car.global_position = scene.player.global_position + Vector3(0.0, 0.0, 2.0)
	for i: int in 300:
		pm.step(STEP_S)
		if pm.state.phase == PursuitState.Phase.BUSTED:
			break
	check(pm.state.phase == PursuitState.Phase.BUSTED, "parked player beside police should be busted, phase %d" % pm.state.phase)
	check((pm._hud as PursuitHud)._banner.text == "BUSTED", "BUSTED banner missing")
	var drv: AIDriver = car.get_node_or_null(PursuitMode.DRIVER_NAME) as AIDriver
	check(drv != null and not drv.enabled, "police driver must stop after the bust")
	await cleanup([scene])
	PursuitMode.ENABLED = was


func test_escape_pays_cash() -> void:
	var was: bool = PursuitMode.ENABLED
	PursuitMode.ENABLED = true
	var scene: RaceScene = _make_scene(_cfg(true))
	await frames(2)
	var pm: PursuitMode = _pursuit_of(scene)
	pm.start()
	# No police at all: the chase cools down at once and escapes after ESCAPE_TIME_S. Spawning is switched off here.
	pm._spawn_t = INF
	var cash_before: int = GameState.get_cash()
	for i: int in 600:
		pm.step(STEP_S)
		if pm.state.phase == PursuitState.Phase.ESCAPED:
			break
	check(pm.state.phase == PursuitState.Phase.ESCAPED, "no police for 10 s should escape, phase %d" % pm.state.phase)
	check(pm.escape_reward == PursuitMode.ESCAPE_REWARD_PER_HEAT, "escape reward %d" % pm.escape_reward)
	check(GameState.get_cash() == cash_before + PursuitMode.ESCAPE_REWARD_PER_HEAT, "escape cash not added")
	GameState.profile["cash"] = cash_before
	check((pm._hud as PursuitHud)._banner.text.begins_with("ESCAPED"), "ESCAPED banner missing")
	await cleanup([scene])
	PursuitMode.ENABLED = was
