extends "res://tests/test_case.gd"
## Drift and elimination career modes: the scoring, elimination and star rules as pure logic, the new ladder entries,
## and a headless autopilot run of each mode through RaceScene to its results. Runs on a temp profile, so the real
## save is never touched.

const SCENE_PATH: String = "res://race/race_scene.tscn"
const TEMP_SAVE: String = "user://test_modes_save.json"
const RUN_LIMIT_FRAMES: int = 20000  ## a 3-lap elimination on city 01 is about 3 minutes of game time at 60 fps


func _open_temp_profile() -> Dictionary:
	var old: Dictionary = {"path": GameState.save_path, "profile": GameState.profile.duplicate(true)}
	GameState.open_profile(TEMP_SAVE)
	GameState.reset_profile()
	return old


func _restore_profile(old: Dictionary) -> void:
	GameState.save_path = str(old["path"])
	GameState.profile = old["profile"]
	var abs_path: String = ProjectSettings.globalize_path(TEMP_SAVE)
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEMP_SAVE + suffix):
			DirAccess.remove_absolute(abs_path + suffix)


## Runs one career event with the autopilot player until the race is FINISHED. The scene stays in the tree.
## on_racing (optional) runs once, on the first frame the race is RACING.
func _run_event(id: String, on_racing: Callable = Callable()) -> RaceScene:
	var cfg: RaceConfig = EventCatalog.config_for(id)
	cfg.autopilot = true
	var scene: RaceScene = (load(SCENE_PATH) as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	add(scene)
	var n: int = 0
	while scene.race != null and scene.race.state != RaceManager.State.FINISHED and n < RUN_LIMIT_FRAMES:
		if on_racing.is_valid() and scene.race.state == RaceManager.State.RACING:
			on_racing.call(scene)
			on_racing = Callable()
		await frames(1)
		n += 1
	metric("frames_%s" % id, n)
	return scene


# --- ladder and configs -----------------------------------------------------

func test_mode_events_are_on_the_ladder() -> void:
	check(EventCatalog.count() == 35, "30 events, four mode events and the Bosphorus escape (merged 2026-11-28), got %d" % EventCatalog.count())
	check(EventCatalog.previous_id("drift_harbour") == "istanbul_championship", "drift_harbour must follow the championship")
	check(EventCatalog.mode_of("drift_harbour") == RaceConfig.MODE_DRIFT and EventCatalog.is_score_event("drift_harbour"), "drift_harbour mode")
	check(EventCatalog.mode_of("drift_bogaz") == RaceConfig.MODE_DRIFT, "drift_bogaz mode")
	check(EventCatalog.mode_of("elim_wharf") == RaceConfig.MODE_ELIMINATION, "elim_wharf mode")
	check(EventCatalog.mode_of("elim_maslak") == RaceConfig.MODE_ELIMINATION, "elim_maslak mode")
	check(EventCatalog.mode_of("wharf_sprint") == RaceConfig.MODE_RACE, "original events stay race mode")
	for id: String in ["drift_harbour", "drift_bogaz", "elim_wharf", "elim_maslak"]:
		check(I18n.t(EventCatalog.name_key(id)) != EventCatalog.name_key(id), "%s has no name text" % id)


func test_drift_config_is_timed_and_solo() -> void:
	var d: RaceConfig = EventCatalog.config_for("drift_harbour")
	check(d.mode == RaceConfig.MODE_DRIFT, "drift config mode")
	check_range(d.time_limit_s, 59.9, 60.1, "drift_harbour time limit")
	check(d.opponent_count == 0, "drift has no rivals, got %d" % d.opponent_count)


func test_elimination_config_has_cars_minus_one_laps() -> void:
	var e: RaceConfig = EventCatalog.config_for("elim_wharf")
	check(e.mode == RaceConfig.MODE_ELIMINATION and e.opponent_count == 3 and e.laps == 3, "elim_wharf: 4 cars, 3 laps")
	var m: RaceConfig = EventCatalog.config_for("elim_maslak")
	check(m.opponent_count == 4 and m.laps == 4, "elim_maslak: 5 cars, 4 laps")


# --- stars and rewards ------------------------------------------------------

func test_drift_stars_follow_the_score() -> void:
	check(EventCatalog.stars_for("drift_harbour", 60.0, 1, 1200.0) == 3, "1200 points, 3 stars")
	check(EventCatalog.stars_for("drift_harbour", 60.0, 1, 700.0) == 2, "700 points, 2 stars")
	check(EventCatalog.stars_for("drift_harbour", 60.0, 1, 300.0) == 1, "300 points, 1 star")
	check(EventCatalog.stars_for("drift_harbour", 60.0, 1, 50.0) == 1, "a finished session earns at least 1 star")
	check(EventCatalog.stars_for("drift_harbour", 0.0, 1, 1200.0) == 0, "no time, no stars")
	check(EventCatalog.stars_for("drift_bogaz", 75.0, 1, 1400.0) == 3, "bogaz top threshold")


func test_elimination_stars_follow_the_place() -> void:
	check(EventCatalog.stars_for("elim_wharf", 120.0, 1) == 3, "winner of an elimination: 3 stars")
	check(EventCatalog.stars_for("elim_wharf", 120.0, 3) == 2, "top three: 2 stars")
	check(EventCatalog.stars_for("elim_wharf", 120.0, 4) == 1, "last place still earns a star")


func test_drift_reward_uses_the_star_tier() -> void:
	var old: Dictionary = _open_temp_profile()
	var r: Dictionary = GameState.record_result("drift_harbour", 60.0, 1, 700.0)
	# 2 stars pay the second tier (2400) times the event multiplier 2.0
	check(int(r.get("stars", 0)) == 2, "700 points should give 2 stars, got %s" % str(r.get("stars")))
	check(int(r.get("cash", 0)) == 4800, "drift cash = 2400 x 2.0, got %s" % str(r.get("cash")))
	check(GameState.event_stars("drift_harbour") == 2, "stars saved to the career")
	_restore_profile(old)


func test_elimination_reward_uses_the_place() -> void:
	var old: Dictionary = _open_temp_profile()
	var r: Dictionary = GameState.record_result("elim_wharf", 100.0, 4)
	check(int(r.get("cash", 0)) == 1000, "4th place cash = 400 x 2.5, got %s" % str(r.get("cash")))
	check(GameState.best_time("elim_wharf") == 0.0 and not bool(r.get("new_best", true)), "an early elimination is not a best time")
	_restore_profile(old)


# --- race manager rules (pure: no cars needed) ------------------------------

func test_elimination_places_and_lap_rules() -> void:
	check(RaceManager.elimination_place(4, 1) == 4, "first out of four is last")
	check(RaceManager.elimination_place(4, 3) == 2, "third out of four is second")
	check(RaceManager.elimination_place(5, 4) == 2, "fourth out of five is second")
	var race := RaceManager.new()
	race.mode = RaceConfig.MODE_ELIMINATION
	var a := RaceManager.Racer.new()
	a.laps = 1
	a.distance = 300.0
	var b := RaceManager.Racer.new()
	b.laps = 0
	b.distance = 120.0
	var active: Array[RaceManager.Racer] = [a, b]
	race.race_time = 50.0
	check(not race._elimination_due(active), "a car still on the lap blocks the elimination")
	check(race._last_place(active) == b, "the car furthest back is last")
	race.race_time = 50.0 + RaceManager.ELIM_GRACE_S + 1.0
	check(race._elimination_due(active), "after the grace period the last place goes anyway")
	b.laps = 1
	race._eliminated_count = 0
	check(race._elimination_due(active), "every car across the line: the lap is over")
	race._eliminated_count = 1
	check(not race._elimination_due(active), "the next lap is not over yet")
	race.free()


func test_drift_chains_bank_only_while_racing() -> void:
	var race := RaceManager.new()
	race.mode = RaceConfig.MODE_DRIFT
	race.time_limit_s = 60.0
	race.state = RaceManager.State.RACING
	race._on_drift_ended(120.0)
	race._on_drift_ended(80.0)
	check(is_equal_approx(race.drift_score_now(), 200.0), "two chains bank to 200, got %s" % str(race.drift_score_now()))
	race.state = RaceManager.State.FINISHED
	race._on_drift_ended(500.0)
	check(is_equal_approx(race.drift_score_now(), 200.0), "chains after the end do not count")
	race.free()


# --- headless full runs -----------------------------------------------------

func test_drift_event_runs_timed_to_a_scored_result() -> void:
	var old: Dictionary = _open_temp_profile()
	# The autopilot does not drift: bank one chain through the real car signal, as ArcadeCar does when a drift ends.
	var scene: RaceScene = await _run_event("drift_harbour", func(s: RaceScene) -> void: s.player.drift_ended.emit(700.0))
	check(scene.race != null and scene.race.state == RaceManager.State.FINISHED, "drift session did not end")
	var results: Array[Dictionary] = scene.last_results
	check(results.size() == 1, "drift is solo, got %d rows" % results.size())
	if results.size() == 1:
		var me: Dictionary = results[0]
		check(bool(me.get("is_player", false)), "the only row is the player")
		check_range(float(me.get("total_time", 0.0)), 59.9, 60.1, "drift session length")
		var score: float = float(me.get("score", -1.0))
		check(score >= 700.0, "the banked chain reaches the result, got %s" % str(score))
		metric("drift_score_autopilot", score)
		check(GameState.event_stars("drift_harbour") == EventCatalog.stars_for("drift_harbour", 60.0, 1, score), "stars follow the banked score")
	await cleanup([scene])
	_restore_profile(old)


func test_elimination_event_places_every_car() -> void:
	var old: Dictionary = _open_temp_profile()
	var scene: RaceScene = await _run_event("elim_wharf")
	check(scene.race != null and scene.race.state == RaceManager.State.FINISHED, "elimination race did not end")
	var results: Array[Dictionary] = scene.last_results
	check(results.size() == 4, "four cars, got %d rows" % results.size())
	var seen: Dictionary = {}
	var outs: Dictionary = {}
	var survivors: int = 0
	for r: Dictionary in results:
		var pos: int = int(r.get("position", 0))
		var out: int = int(r.get("out_lap", 0))
		check(not seen.has(pos), "place %d used twice" % pos)
		seen[pos] = true
		if out > 0:
			check(not outs.has(out), "lap %d eliminates two cars" % out)
			outs[out] = true
			check(pos == RaceManager.elimination_place(4, out), "car out at lap %d placed %d" % [out, pos])
		else:
			survivors += 1
		if bool(r.get("is_player", false)):
			metric("elim_player_out_lap", out)
			metric("elim_player_place", pos)
	check(survivors >= 1, "someone is still in at the end")
	if survivors == 1:
		check(outs.size() == 3, "three eliminations when one car is left, got %d" % outs.size())
	await cleanup([scene])
	_restore_profile(old)
