extends "res://tests/test_case.gd"
## The first event a new player meets (EventCatalog's first entry, always open) has to be short and winnable in the
## starter car. Measured on 2026-11-27 with the autopilot as a stand-in for a newcomer: with the old recipe (two laps,
## rivals at 0.80 to 0.76 drawn from every car class) the grid held a 352 km/h hypercar. The autopilot is a cautious
## overtaker, so "first or second from the back of the grid" is the bar here; a person who passes can win.
## The race runs on a temporary profile: nothing is written to the player's save.

const SCENE_PATH: String = "res://race/race_scene.tscn"
const TEMP_SAVE: String = "user://test_first_race.json"
const NEWCOMER_SKILL: float = 0.72  ## share of the track's target speed the stand-in drives at
const MAX_FRAMES: int = 9000  ## 150 s: the lap takes about 55 s after the countdown
const MAX_RACE_S: float = 90.0


func test_first_event_is_one_short_lap_against_starter_class_cars() -> void:
	var id: String = EventCatalog.id_at(0)
	var cfg: RaceConfig = EventCatalog.config_for(id)
	check(EventCatalog.is_open(id) and GameState.is_event_unlocked(id), "the first event is open on a fresh profile")
	check(cfg.laps == 1 and not cfg.traffic_enabled, "the first race is one lap without traffic (laps %d)" % cfg.laps)
	check(cfg.time_of_day == "night", "the first race shows the game's night look")
	var starter_class: String = CarCatalog.class_id(CarCatalog.STARTER)
	for r: Dictionary in CarCatalog.rival_models(cfg.opponent_count, hash(id), cfg.rival_class):
		check(CarCatalog.class_id(str(r["id"])) == starter_class, "first-race rival %s is not a %s-class car" % [r["id"], starter_class])


func test_a_newcomer_pace_finishes_first_or_second() -> void:
	var old_path: String = GameState.save_path
	var old_profile: Dictionary = GameState.profile.duplicate(true)
	GameState.open_profile(TEMP_SAVE)
	GameState.reset_profile()
	var cfg: RaceConfig = EventCatalog.config_for(EventCatalog.id_at(0))
	check(cfg.car_scene == CarCatalog.scene_path(CarCatalog.STARTER), "a fresh profile races the starter car")
	cfg.autopilot = true
	cfg.autopilot_skill = NEWCOMER_SKILL
	var scene: RaceScene = (load(SCENE_PATH) as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	add(scene)
	var n: int = 0
	while n < MAX_FRAMES and (scene.race == null or scene.race.state != RaceManager.State.FINISHED):
		await frames(30)
		n += 30
	check(scene.race != null and scene.race.state == RaceManager.State.FINISHED, "the first race did not finish in %d frames" % MAX_FRAMES)
	for r: Dictionary in scene.last_results:
		if bool(r["is_player"]):
			metric("first_race_position", int(r["position"]))
			metric("first_race_time_s", snappedf(float(r["total_time"]), 0.1))
			check(int(r["position"]) <= 2, "a %.2f-pace driver finishes %d of %d in the first race" % [NEWCOMER_SKILL, r["position"], scene.last_results.size()])
			check(float(r["total_time"]) <= MAX_RACE_S, "the first race takes %.0f s, more than %.0f" % [r["total_time"], MAX_RACE_S])
	check(GameState.event_stars(cfg.event_id) >= 2, "a podium in the first race earns two stars or more")
	await cleanup([scene])
	GameState.open_profile(old_path)
	GameState.profile = old_profile
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE + ".bak"))
