extends "res://tests/test_case.gd"
## Career ladder: catalog data, RaceConfig recipes, star rules, rewards, unlocks, the event select screen and the
## results screen's NEXT EVENT button. Uses a throwaway user:// profile on the GameState autoload and restores it.

const PROFILE: String = "user://test_events_profile.json"
const SELECT: String = "res://ui/menus/event_select.tscn"
const RESULTS: String = "res://ui/menus/results_screen.tscn"

var _saved_path: String = ""
var _saved_language: String = "en"
var _saved_autosave: bool = true


func _begin() -> void:
	_saved_path = GameState.save_path
	_saved_language = Settings.language
	_saved_autosave = Settings.autosave
	Settings.autosave = false
	Settings.set_language("en")
	_wipe()
	GameState.open_profile(PROFILE)
	GameState.reset_profile()


func _end() -> void:
	_wipe()
	GameState.open_profile(_saved_path)
	Settings.set_language(_saved_language)
	Settings.autosave = _saved_autosave


func _wipe() -> void:
	for p: String in [PROFILE, PROFILE + ".bak", PROFILE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_catalog_shape() -> void:
	check(EventCatalog.count() == 43, "original eleven events, nineteen extended tour events, four mode events, the Bosphorus escape and eight pursuit events")
	for id: String in ["maslak_sprint", "bogaz_circuit", "maslak_night", "bogaz_final"]:
		var c: RaceConfig = EventCatalog.config_for(id)
		check(c != null and ResourceLoader.exists(c.track_scene) and c.track_scene.contains("istanbul"), "%s races on an Istanbul track" % id)
		check(I18n.t(EventCatalog.name_key(id)) != EventCatalog.name_key(id), "%s has a name" % id)
	check(EventCatalog.config_for("wharf_sprint").track_scene.contains("city_01"), "Arden Bay events keep City 01")
	var ids: Dictionary = {}
	for i: int in EventCatalog.count():
		var id: String = EventCatalog.id_at(i)
		check(not ids.has(id), "duplicate id " + id)
		ids[id] = true
		var ev: Dictionary = EventCatalog.find(id)
		check(int(ev["laps"]) >= 1 and int(ev["laps"]) <= 10, "laps in range for " + id)
		check((ev["skills"] as Array).size() <= 7, "at most 7 rivals for " + id)
		for key: String in ["name"]:
			var k: String = "event.%s.%s" % [id, key]
			check(I18n.has_key(k), "missing text key " + k)
		check(EventCatalog.reward_multiplier(id) >= 1.0, "multiplier for " + id)
	check(EventCatalog.reward_multiplier("syndicate_final") > EventCatalog.reward_multiplier("wharf_sprint"), "rewards grow along the ladder")
	check(EventCatalog.previous_id("ortakoy_night") == "" and EventCatalog.is_open("ortakoy_night"), "the showcase comes first and is always open")
	check(EventCatalog.next_id("syndicate_final") == "maslak_sprint", "the Arden Bay final opens the Istanbul tour")
	check(EventCatalog.next_id("bogaz_final") == "maslak_time_trial", "original finale leads to extended tour")
	check(EventCatalog.next_id("istanbul_championship") == "drift_harbour", "the championship leads to the mode events")
	check(EventCatalog.next_id("wharf_sprint") == "neon_strip_circuit", "ladder order")
	check(EventCatalog.next_id("dev_circuit") == "", "unknown id has no next")


func test_config_for() -> void:
	var c: RaceConfig = EventCatalog.config_for("midnight_time_trial")
	check(c != null and c.opponent_count == 0 and c.laps == 1 and c.event_id == "midnight_time_trial", "time trial config")
	var d: RaceConfig = EventCatalog.config_for("overpass_duel")
	check(d.opponent_count == 1 and d.opponent_skill(0) >= 0.95, "duel is one strong rival")
	var f: RaceConfig = EventCatalog.config_for("syndicate_final")
	check(f.laps == 3 and f.opponent_count == 5, "final is 3 laps, 5 rivals")
	check(f.opponent_skill(0) > EventCatalog.config_for("harbour_run").opponent_skill(0), "final is harder than harbour run")
	check(EventCatalog.config_for("wharf_sprint").opponent_skill(0) < f.opponent_skill(4), "sprint is easier than the final")
	check(EventCatalog.config_for("nope") == null, "unknown id gives null")
	for i: int in EventCatalog.count():
		var cfg: RaceConfig = EventCatalog.config_for(EventCatalog.id_at(i))
		check(cfg.opponent_skills.size() == cfg.opponent_count, "skills match rivals for " + cfg.event_id)


func test_stars_and_rewards() -> void:
	_begin()
	check(EventCatalog.stars_for("wharf_sprint", 70.0, 1) == 3, "1st = 3 stars")
	check(EventCatalog.stars_for("wharf_sprint", 70.0, 3) == 2, "podium = 2 stars")
	check(EventCatalog.stars_for("wharf_sprint", 70.0, 6) == 1, "finish = 1 star")
	check(EventCatalog.stars_for("midnight_time_trial", 70.0, 1) == 3, "fast trial = 3 stars")
	check(EventCatalog.stars_for("midnight_time_trial", 80.0, 1) == 2, "medium trial = 2 stars")
	check(EventCatalog.stars_for("midnight_time_trial", 95.0, 1) == 1, "slow trial = 1 star")
	check(EventCatalog.stars_for("midnight_time_trial", 130.0, 1) == 1, "any trial finish = at least 1 star (opens the next event)")
	var r: Dictionary = GameState.record_result("syndicate_final", 200.0, 1)
	check(int(r["cash"]) == 12000 and int(r["rep"]) == 300 and int(r["stars"]) == 3, "final win pays x3")
	var legacy: Dictionary = GameState.record_result("dev_circuit", 100.0, 1)
	check(int(legacy["cash"]) == 4000 and int(legacy["stars"]) == 3, "unknown event keeps base rewards")
	var t: Dictionary = GameState.record_result("midnight_time_trial", 130.0, 1)
	check(int(t["stars"]) == 1, "slow trial still records 1 star")
	check(GameState.event_stars("midnight_time_trial") == 1, "1 star stored")
	_end()


func test_unlock_rules() -> void:
	_begin()
	check(GameState.is_event_unlocked("wharf_sprint"), "first event open")
	check(not GameState.is_event_unlocked("neon_strip_circuit"), "second locked at start")
	check(GameState.is_event_unlocked("dev_circuit"), "dev circuit always open")
	GameState.record_result("wharf_sprint", 70.0, 5)
	check(GameState.is_event_unlocked("neon_strip_circuit"), "1 star opens the next event")
	check(not GameState.is_event_unlocked("midnight_time_trial"), "only one step opens")
	GameState.record_result("neon_strip_circuit", 150.0, 4)
	check(not GameState.is_event_unlocked("overpass_duel"), "the duel stays shut until the trial is finished")
	GameState.record_result("midnight_time_trial", 130.0, 1)  # a slow finish still earns 1 star
	check(GameState.is_event_unlocked("overpass_duel"), "any trial finish opens the next event")
	GameState.record_result("midnight_time_trial", 99.0, 1)
	check(GameState.is_event_unlocked("overpass_duel"), "trial under 1-star time unlocks the duel")
	check(GameState.total_stars() == 3, "total stars add up")
	check(is_equal_approx(GameState.best_time("midnight_time_trial"), 99.0), "best time kept")
	_end()


func test_event_select_screen() -> void:
	_begin()
	GameState.record_result("wharf_sprint", 66.0, 1)
	var screen: EventSelect = (load(SELECT) as PackedScene).instantiate() as EventSelect
	add(screen)
	await frames(3)
	check(screen.get_row_count() == EventCatalog.count(), "one row per event")
	check(screen.get_selected_id() == "ortakoy_night", "opens on the first unfinished unlocked event (the showcase)")
	check(screen.is_start_enabled(), "start enabled on an unlocked event")
	var params: Dictionary = screen.build_start_params()
	var cfg: RaceConfig = params.get(RaceScene.CONFIG_PARAM) as RaceConfig
	check(cfg != null and cfg.event_id == "ortakoy_night" and cfg.track_scene.contains("istanbul_bogaz") and cfg.time_of_day == "night", "start params carry the RaceConfig")
	screen.select(EventCatalog.index_of("harbour_run"))
	check(screen.get_selected_id() == "harbour_run" and not screen.is_start_enabled(), "locked event disables start")
	check(screen.build_start_params().is_empty(), "locked event gives no params")
	# Turkish text renders without unknown keys.
	Settings.set_language("tr")
	await frames(2)
	check(I18n.t(EventCatalog.name_key("harbour_run")) == "Liman Koşusu", "turkish event name")
	var draws: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	metric("event_select_draw_calls_headless", draws)
	cleanup([screen])
	await frames(2)
	_end()


func test_results_next_event() -> void:
	_begin()
	var screen: ResultsScreen = (load(RESULTS) as PackedScene).instantiate() as ResultsScreen
	add(screen)
	await frames(2)
	var rows: Array[Dictionary] = [{"name": "Nova Rike", "position": 1, "total_time": 70.0, "best_lap": 70.0, "is_player": true}]
	screen.set_event_id("wharf_sprint")
	screen.show_results(rows, GameState.record_result("wharf_sprint", 70.0, 1))
	check(screen.get_next_event_id() == "neon_strip_circuit", "next event offered after a star")
	screen.set_event_id("syndicate_final")
	screen.show_results(rows, {})
	check(screen.get_next_event_id() == "", "no next event after the final")
	screen.set_event_id("neon_strip_circuit")  # event 2 has no star yet, so event 3 is locked
	screen.show_results(rows, {})
	check(screen.get_next_event_id() == "", "locked next event is not offered")
	screen.set_event_id("")
	screen.show_results(rows, {})
	check(screen.get_next_event_id() == "", "no event id means no next button")
	cleanup([screen])
	await frames(2)
	_end()


func test_extended_tour_preserves_original_ids_and_unlocks() -> void:
	_begin()
	var originals: Array[String] = ["ortakoy_night", "wharf_sprint", "neon_strip_circuit", "midnight_time_trial", "overpass_duel", "harbour_run", "syndicate_final", "maslak_sprint", "bogaz_circuit", "maslak_night", "bogaz_final"]
	for i: int in originals.size():
		check(EventCatalog.id_at(i) == originals[i], "original event id/order unchanged")
	check(not GameState.is_event_unlocked("maslak_time_trial"), "extension initially locked")
	GameState.record_result("bogaz_final", 210.0, 1)
	check(GameState.is_event_unlocked("maslak_time_trial"), "old finale result unlocks extension")
	for i: int in range(originals.size(), EventCatalog.count()):
		var id: String = EventCatalog.id_at(i)
		var cfg: RaceConfig = EventCatalog.config_for(id)
		check(cfg != null and ResourceLoader.exists(cfg.track_scene), "valid track for " + id)
		check(GameState.is_event_unlocked(id), "extension unlocks in order: " + id)
		var result: Dictionary = GameState.record_result(id, 70.0 if EventCatalog.is_time_event(id) else 210.0, 1)
		check(int(result["stars"]) >= 1, "finish earns star: " + id)
		for lang: String in ["tr", "en"]:
			Settings.set_language(lang)
			check(I18n.t(EventCatalog.name_key(id)) != EventCatalog.name_key(id), "localized " + id + " " + lang)
	_end()


func test_long_career_list_keeps_selected_row_visible() -> void:
	_begin()
	var screen: EventSelect = (load(SELECT) as PackedScene).instantiate() as EventSelect
	add(screen)
	await frames(3)
	check(screen.get_row_count() == 43, "all career events exist")
	var capacity: int = EventSelect.PHONE_WINDOW_ROWS if MSTheme.phone else EventSelect.DESKTOP_WINDOW_ROWS
	for i: int in [0, 11, 30, 0]:
		screen.select(i)
		await frames(2)
		check(screen.get_selected_id() == EventCatalog.id_at(i), "selection reachable: %d" % i)
		check(screen.is_selected_row_visible(), "selected row visible: %d" % i)
		check(screen.get_visible_row_count() == mini(capacity, screen.get_district_event_count()), "bounded event window in its district")
	cleanup([screen])
	await frames(2)
	_end()
