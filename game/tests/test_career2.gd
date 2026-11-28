extends "res://tests/test_case.gd"
## Career variety: reverse-direction variants (Track.set_reversed through RaceConfig.reverse_route), chapters and boss
## races in the catalog, their texts, the no-duplicate rule for neighbours in the ladder, and save compatibility (ids,
## order and rewards of the existing events are unchanged). Every reverse event loads and one AI lap finishes on it.

const CITY: String = "res://world/city_01/city_01.tscn"
const BOGAZ_TRACK: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const MASLAK_TRACK: String = "res://world/istanbul_maslak/istanbul_maslak.tscn"
const AI_COUNT: int = 2
const RACE_LIMIT_S: float = 240.0
const HZ: float = 60.0
const REVERSE_IDS: Array[String] = ["neon_strip_circuit", "overpass_duel", "wharf_duel", "wharf_endurance", "bogaz_circuit", "bogaz_duel", "bogaz_night_duel", "maslak_duel", "maslak_elite", "maslak_rush"]

var _results: Array[Dictionary] = []
var _finished_events: int = 0


func _on_finished(results: Array[Dictionary]) -> void:
	_finished_events += 1
	_results = results


func _track_key(ev: Dictionary) -> String:
	return str(ev.get("track", CITY))


func test_save_compatible_ladder() -> void:
	check(EventCatalog.count() >= 43, "at least the 43 original events")
	check(EventCatalog.id_at(0) == "ortakoy_night", "showcase stays first")
	check(EventCatalog.id_at(6) == "syndicate_final" and EventCatalog.id_at(7) == "maslak_sprint", "Arden Bay final opens the tour")
	check(EventCatalog.next_id("wharf_sprint") == "neon_strip_circuit", "ladder order kept")
	check(EventCatalog.next_id("istanbul_championship") == "drift_harbour", "mode events follow the championship")
	check(is_equal_approx(EventCatalog.reward_multiplier("bogaz_circuit"), 3.5), "reverse variant keeps its reward multiplier")
	check(is_equal_approx(EventCatalog.reward_multiplier("bogaz_duel"), 2.5), "boss duel keeps its reward multiplier")
	check(EventCatalog.config_for("bogaz_duel").laps == 1, "boss duel keeps its laps")


func test_reverse_events_spread_and_unique() -> void:
	var reverse_count: int = 0
	var tracks: Dictionary = {}
	for i: int in EventCatalog.count():
		var ev: Dictionary = EventCatalog.find(EventCatalog.id_at(i))
		if bool(ev.get("reverse", false)):
			reverse_count += 1
			tracks[_track_key(ev)] = true
	check(reverse_count >= 10, "at least 10 reverse events, got %d" % reverse_count)
	check(tracks.size() == 3, "reverse events cover all three tracks, got %d" % tracks.size())
	for id: String in REVERSE_IDS:
		check(EventCatalog.find(id).get("reverse", false), "%s is a reverse variant" % id)
		check(EventCatalog.config_for(id).reverse_route, "%s config reverses the route" % id)
	check(not EventCatalog.config_for("wharf_sprint").reverse_route, "forward events keep the authored direction")
	for i: int in range(1, EventCatalog.count()):
		var a: Dictionary = EventCatalog.find(EventCatalog.id_at(i - 1))
		var b: Dictionary = EventCatalog.find(EventCatalog.id_at(i))
		var ka: String = "%s|%s|%s|%s" % [_track_key(a), a.get("reverse", false), EventCatalog.mode_of(EventCatalog.id_at(i - 1)), a.get("tod", "")]
		var kb: String = "%s|%s|%s|%s" % [_track_key(b), b.get("reverse", false), EventCatalog.mode_of(EventCatalog.id_at(i)), b.get("tod", "")]
		check(ka != kb, "consecutive duplicate at %s / %s" % [EventCatalog.id_at(i - 1), EventCatalog.id_at(i)])


func test_chapters_and_bosses() -> void:
	var last_of: Dictionary = {}
	var boss_of: Dictionary = {}
	for i: int in EventCatalog.count():
		var id: String = EventCatalog.id_at(i)
		var ch: int = EventCatalog.chapter_of(id)
		if ch > 0:
			last_of[ch] = id
		if EventCatalog.is_boss(id):
			boss_of[ch] = id
	check(last_of.size() == 4, "four chapters")
	for ch: int in [1, 2, 3, 4]:
		check(boss_of.get(ch, "") == last_of.get(ch, "?"), "chapter %d ends with its boss" % ch)
		check(I18n.t("chapter.%d.name" % ch) != "chapter.%d.name" % ch, "chapter %d has a name" % ch)
		if ch > 1:
			check(EventCatalog.chapter_of(EventCatalog.id_at(EventCatalog.index_of(last_of[ch - 1]) + 1)) == ch, "chapters %d and %d are contiguous" % [ch - 1, ch])
	for ch: int in [1, 2, 3]:
		check((EventCatalog.find(boss_of[ch])["skills"] as Array).size() == 1, "boss of chapter %d is a one-rival duel" % ch)
	check(I18n.t("event.boss") != "event.boss", "boss tag has text")


func test_chapter_headers_in_select() -> void:
	var starts: Array[int] = []
	for i: int in EventCatalog.count():
		if EventSelect.is_chapter_start(i):
			starts.append(i)
	check(starts == [0, 5, 13, 21, 30], "headers at chapters 1-4 and the tail, got %s" % str(starts))
	for i: int in starts:
		var key: String = EventCatalog.chapter_name_key(EventCatalog.chapter_of(EventCatalog.id_at(i)))
		check(I18n.t(key) != key, "header %d has text" % i)


func test_reverse_names_in_both_languages() -> void:
	var saved: String = Settings.language
	for id: String in REVERSE_IDS:
		var key: String = EventCatalog.name_key(id)
		check(key == "event.%s.reverse.name" % id, "reverse name key for " + id)
		Settings.set_language("tr")
		check(I18n.t(key).begins_with("Ters Yön"), "Turkish reverse name for " + id)
		Settings.set_language("en")
		check(I18n.t(key).begins_with("Reverse"), "English reverse name for " + id)
	check(EventCatalog.name_key("wharf_sprint") == "event.wharf_sprint.name", "forward names unchanged")
	Settings.set_language(saved)


func _make_car(skill: float, seed_value: int) -> ArcadeCar:
	var car := ArcadeCar.new()
	car.spec = load("res://vehicles/specs/noctra_sable.tres") as CarSpec
	add(car)
	var d := AIDriver.new()
	d.name = "AIDriver"
	d.skill = skill
	d.noise_seed = seed_value
	car.add_child(d)
	return car


func test_reverse_events_ai_finish() -> void:
	for id: String in REVERSE_IDS:
		var cfg: RaceConfig = EventCatalog.config_for(id)
		var scene: PackedScene = load(cfg.track_scene) as PackedScene
		check(scene != null, "%s track loads" % id)
		if scene == null:
			continue
		var track: Track = scene.instantiate() as Track
		add(track)
		await frames(1)
		track.set_reversed(cfg.reverse_route)
		var manager := RaceManager.new()
		manager.total_laps = 1
		add(manager)
		var cars: Array[ArcadeCar] = []
		var names: PackedStringArray = PackedStringArray()
		for i: int in AI_COUNT:
			cars.append(_make_car(cfg.opponent_skill(i), i + 1))
			names.append("AI %d" % (i + 1))
		_finished_events = 0
		_results.clear()
		manager.race_finished.connect(_on_finished)
		manager.setup(track, cars, null, names)
		manager.start_countdown()
		var limit_ticks: int = roundi(RACE_LIMIT_S * HZ)
		var ticks: int = 0
		while manager.state != RaceManager.State.FINISHED and ticks < limit_ticks:
			await frames(1)
			ticks += 1
		metric("reverse_ai_lap_s_" + id, snappedf(manager.race_time, 0.01))
		check(manager.state == RaceManager.State.FINISHED, "%s: AI lap did not finish in %.0f s" % [id, RACE_LIMIT_S])
		check(_finished_events == 1 and _results.size() == AI_COUNT, "%s: %d cars classified" % [id, _results.size()])
		var nodes: Array[Node] = [manager, track]
		for car: ArcadeCar in cars:
			nodes.append(car)
		await cleanup(nodes)
