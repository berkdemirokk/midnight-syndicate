extends "res://tests/test_case.gd"
## Bosphorus escape (career event "bogaz_escape" on istanbul_bogaz at night): reachable from the career menu, localized,
## opts in to police pursuit without the global kill switch, leaves the other events police-free, and an autopilot run
## ends in a result (finish, escape or bust) with no reward for a bust.

const SCENE_PATH: String = "res://race/race_scene.tscn"
const MISSING_PATH: String = "res://does_not_exist/none.tscn"
const EVENT_ID: String = "bogaz_escape"
const TEMP_SAVE: String = "user://test_escape_save.json"  ## the run must not touch the real profile
const RUN_TIMEOUT_S: float = 400.0  ## a 2-lap Bosphorus run with police; a stuck run fails here
const STEP_S: float = 1.0 / 60.0


func _make_scene(cfg: RaceConfig) -> RaceScene:
	var scene: RaceScene = (load(SCENE_PATH) as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	add(scene)
	return scene


func test_event_is_reachable_and_localized() -> void:
	check(not EventCatalog.find(EVENT_ID).is_empty(), "the event is in the catalog")
	check(GameState.is_event_unlocked(EVENT_ID), "an open event is unlocked from the start")
	var cfg: RaceConfig = EventCatalog.config_for(EVENT_ID)
	check(cfg != null, "the event has a RaceConfig")
	if cfg == null:
		return
	check(cfg.track_scene.contains("istanbul_bogaz"), "the event races on the Bosphorus track")
	check(cfg.time_of_day == "night", "the event is at night")
	check(cfg.pursuit and cfg.pursuit_event, "the event opts in to pursuit")
	check(ResourceLoader.exists(cfg.track_scene), "the Bosphorus track scene exists")
	var saved: String = Settings.language
	for lang: String in ["tr", "en"]:
		Settings.set_language(lang)
		var text: String = I18n.t(EventCatalog.name_key(EVENT_ID))
		check(text != EventCatalog.name_key(EVENT_ID), "event name is translated (%s)" % lang)
	Settings.set_language("tr")
	check(I18n.t(EventCatalog.name_key(EVENT_ID)) == "Boğaz kaçışı", "Turkish event name")
	Settings.set_language("en")
	check(I18n.t(EventCatalog.name_key(EVENT_ID)) == "Bosphorus escape", "English event name")
	Settings.set_language(saved)


func test_other_events_do_not_opt_in() -> void:
	for i: int in EventCatalog.count():
		var id: String = EventCatalog.id_at(i)
		if id == EVENT_ID:
			continue
		var cfg: RaceConfig = EventCatalog.config_for(id)
		check(cfg != null and not cfg.pursuit and not cfg.pursuit_event, "normal event is police-free: " + id)


func test_event_flag_opens_gate_with_kill_switch_off() -> void:
	var was: bool = PursuitMode.ENABLED
	PursuitMode.ENABLED = false
	var cfg := RaceConfig.new()
	cfg.autopilot = false
	cfg.laps = 1
	cfg.opponent_count = 2
	cfg.track_scene = MISSING_PATH
	cfg.car_scene = MISSING_PATH
	cfg.pursuit = true
	cfg.pursuit_event = true
	var scene: RaceScene = _make_scene(cfg)
	await frames(2)
	check(scene.find_child("PursuitMode", true, false) != null, "the event flag passes the gate with ENABLED false")
	await cleanup([scene])
	PursuitMode.ENABLED = was


## Deterministic bust on the real event scene: the result screen comes up with no standings, stars, cash or record,
## and a later race_finished is ignored.
func test_bust_shows_result_without_reward() -> void:
	var was: bool = PursuitMode.ENABLED
	PursuitMode.ENABLED = false
	var old: Dictionary = {"path": GameState.save_path, "profile": GameState.profile.duplicate(true)}
	GameState.open_profile(TEMP_SAVE)
	GameState.reset_profile()
	var cash_before: int = GameState.get_cash()
	var cfg: RaceConfig = EventCatalog.config_for(EVENT_ID)
	cfg.autopilot = true
	var scene: RaceScene = _make_scene(cfg)
	await frames(30)
	var pm: PursuitMode = scene.find_child("PursuitMode", true, false) as PursuitMode
	check(pm != null, "the event starts the pursuit")
	if pm != null:
		pm.state.phase = PursuitState.Phase.BUSTED
		pm._finish()
		check(scene._pursuit_busted, "race_scene takes the bust")
		check(not scene.race.is_physics_processing(), "the race stops for the player")
		check(not scene.results_screen.visible, "the BUSTED banner shows first")
		await frames(int(ceil((scene.PURSUIT_BUST_SHOW_S + 0.5) / STEP_S)))
		check(scene.results_screen.visible, "a bust shows the results screen")
		check(scene.last_results.is_empty(), "a bust has no race standings")
		check(scene.results_screen._subtitle.text == I18n.t("pursuit.busted.result"), "a bust says no reward, retry")
		var fake: Array[Dictionary] = [{"car": scene.player, "name": "p", "position": 1, "total_time": 60.0, "best_lap": 30.0, "is_player": true}]
		scene.race.race_finished.emit(fake)
		await frames(2)
		check(scene.last_results.is_empty(), "a race_finished after the bust is ignored")
		check(GameState.event_stars(EVENT_ID) == 0, "a bust records no stars")
		check(GameState.get_cash() == cash_before, "a bust pays no reward")
	await cleanup([scene])
	GameState.save_path = str(old["path"])
	GameState.profile = old["profile"]
	var abs_path: String = ProjectSettings.globalize_path(TEMP_SAVE)
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEMP_SAVE + suffix):
			DirAccess.remove_absolute(abs_path + suffix)
	PursuitMode.ENABLED = was


func test_escape_event_runs_to_a_result() -> void:
	var was: bool = PursuitMode.ENABLED
	PursuitMode.ENABLED = false  # the event alone switches pursuit on
	var old: Dictionary = {"path": GameState.save_path, "profile": GameState.profile.duplicate(true)}
	GameState.open_profile(TEMP_SAVE)
	GameState.reset_profile()
	var cash_before: int = GameState.get_cash()
	var cfg: RaceConfig = EventCatalog.config_for(EVENT_ID)
	cfg.autopilot = true
	var scene: RaceScene = _make_scene(cfg)
	var flags: Dictionary = {"finished": false, "busted": false}
	await frames(30)
	scene.race.race_finished.connect(func(_r: Array[Dictionary]) -> void: flags["finished"] = true)
	var pm: PursuitMode = scene.find_child("PursuitMode", true, false) as PursuitMode
	check(pm != null, "the event starts the pursuit")
	if pm != null:
		pm.busted.connect(func() -> void: flags["busted"] = true)
	var waited: float = 0.0
	while not (flags["finished"] or flags["busted"]) and waited < RUN_TIMEOUT_S:
		await frames(1)
		waited += STEP_S
	check(flags["finished"] or flags["busted"], "the run ends in a finish or a bust, waited %.0f s" % waited)
	if flags["busted"] and not flags["finished"]:
		await frames(int(ceil((scene.PURSUIT_BUST_SHOW_S + 0.5) / STEP_S)))
		check(scene.results_screen.visible, "a bust shows the results screen")
		check(scene.last_results.is_empty(), "a bust has no race standings")
		check(GameState.event_stars(EVENT_ID) == 0, "a bust records no stars")
		check(GameState.get_cash() == cash_before, "a bust pays no reward")
	else:
		check(scene.results_screen.visible, "a finish shows the results screen")
		check(GameState.event_stars(EVENT_ID) >= 1, "a finish records at least one star")
	print("ESCAPE_EVENT_RUN finished=%s busted=%s waited=%.1fs stars=%d" % [flags["finished"], flags["busted"], waited, GameState.event_stars(EVENT_ID)])
	await cleanup([scene])
	GameState.save_path = str(old["path"])
	GameState.profile = old["profile"]
	var abs_path: String = ProjectSettings.globalize_path(TEMP_SAVE)
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEMP_SAVE + suffix):
			DirAccess.remove_absolute(abs_path + suffix)
	PursuitMode.ENABLED = was
