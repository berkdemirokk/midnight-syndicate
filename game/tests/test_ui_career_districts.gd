extends "res://tests/test_case.gd"
## Career districts: every event in exactly one district, district star totals equal GameState, a locked event cannot
## start, keyboard moves between cards and districts, the district lock state, and every name is localized.

const PROFILE: String = "user://test_ui_career_districts_profile.json"
const SELECT: String = "res://ui/menus/event_select.tscn"

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


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code as Key
	ev.physical_keycode = code as Key
	ev.pressed = true
	return ev


func _screen() -> EventSelect:
	return add((load(SELECT) as PackedScene).instantiate()) as EventSelect


func test_every_event_in_exactly_one_district() -> void:
	var counts: Array[int] = [0, 0, 0, 0, 0]
	var seen: Dictionary = {}
	for i: int in EventCatalog.count():
		var id: String = EventCatalog.id_at(i)
		var d: int = EventSelect.district_of(id)
		check(d >= 0 and d < EventSelect.DISTRICT_COUNT, "district in range: " + id)
		if d >= 0 and d < EventSelect.DISTRICT_COUNT:
			counts[d] += 1
		check(not seen.has(id), "event listed twice: " + id)
		seen[id] = d
		if bool(EventCatalog.find(id).get("pursuit", false)):
			check(d == EventSelect.D_POLICE, "pursuit event outside Police: " + id)
		else:
			check(d != EventSelect.D_POLICE, "non-pursuit event in Police: " + id)
	var total: int = 0
	for c: int in counts:
		total += c
	check(total == EventCatalog.count(), "district lists add up to %d events, got %d" % [EventCatalog.count(), total])
	check(seen.size() == EventCatalog.count(), "every event appears exactly once")
	metric("district_event_counts", counts)


func test_district_star_totals_match_game_state() -> void:
	_begin()
	GameState.record_result("ortakoy_night", 60.0, 1)
	GameState.record_result("wharf_sprint", 66.4, 2)
	GameState.record_result("drift_harbour", 70.0, 1, 1500.0)
	GameState.record_result("pursuit_wharf_escape", 90.0, 1)
	var screen: EventSelect = _screen()
	await frames(3)
	var grand: int = 0
	for d: int in EventSelect.DISTRICT_COUNT:
		var manual: int = 0
		var n: int = 0
		for i: int in EventCatalog.count():
			var id: String = EventCatalog.id_at(i)
			if EventSelect.district_of(id) == d:
				manual += GameState.event_stars(id)
				n += 1
		check(screen.get_district_stars(d) == manual, "district %d stars %d, GameState says %d" % [d, screen.get_district_stars(d), manual])
		check(screen.get_district_max_stars(d) == n * GameState.MAX_STARS, "district %d max stars" % d)
		grand += screen.get_district_stars(d)
	check(grand == GameState.total_stars(), "district totals add up to the career total")
	check(grand > 0, "test earned stars")
	cleanup([screen])
	await frames(2)
	_end()


func test_locked_event_cannot_start() -> void:
	_begin()
	var screen: EventSelect = _screen()
	await frames(3)
	var id: String = "harbour_run"
	check(not GameState.is_event_unlocked(id), "harbour run starts locked on a new profile")
	screen.select(EventCatalog.index_of(id))
	check(screen.get_selected_id() == id, "locked event can be browsed")
	check(not screen.is_start_enabled(), "start disabled on a locked event")
	check(screen.build_start_params().is_empty(), "locked event gives no start params")
	screen.start_race()
	check(screen.get_selected_id() == id, "start on a locked event changes nothing")
	cleanup([screen])
	await frames(2)
	_end()


func test_keyboard_moves_between_cards_and_districts() -> void:
	_begin()
	var screen: EventSelect = _screen()
	await frames(3)
	var rows: Array[Button] = screen.get("_row_btns")
	screen.select(EventCatalog.index_of("wharf_sprint"))
	await frames(2)
	check(screen.get_district() == EventSelect.D_ARDEN, "wharf sprint is in Arden Bay")
	rows[EventCatalog.index_of("wharf_sprint")].grab_focus()
	await frames(1)
	screen._input(_key(KEY_DOWN))
	check(screen.get_selected_id() == "neon_strip_circuit", "down moves to the next card of the district")
	screen._input(_key(KEY_RIGHT))
	check(screen.get_district() == EventSelect.D_ORTAKOY, "right switches to Ortakoy")
	var focus: Control = tree.root.gui_get_focus_owner()
	var fi: int = rows.find(focus)
	check(fi >= 0 and EventSelect.district_of(EventCatalog.id_at(fi)) == EventSelect.D_ORTAKOY, "focus follows the district")
	screen._input(_key(KEY_LEFT))
	check(screen.get_district() == EventSelect.D_ARDEN, "left switches back to Arden Bay")
	cleanup([screen])
	await frames(2)
	_end()


func test_district_lock_state_follows_progress() -> void:
	_begin()
	var screen: EventSelect = _screen()
	await frames(3)
	check(screen.is_district_open(EventSelect.D_ARDEN), "Arden Bay is open")
	check(screen.is_district_open(EventSelect.D_ORTAKOY), "Ortakoy is open (showcase)")
	check(screen.is_district_open(EventSelect.D_POLICE), "Police has open runs")
	check(not screen.is_district_open(EventSelect.D_MASLAK), "Maslak locked until the Arden Bay final earns a star")
	GameState.record_result("syndicate_final", 200.0, 1)
	check(screen.is_district_open(EventSelect.D_MASLAK), "Maslak opens after the Arden Bay final")
	cleanup([screen])
	await frames(2)
	_end()


func test_names_and_district_labels_localized() -> void:
	_begin()
	for lang: String in ["tr", "en"]:
		Settings.set_language(lang)
		for d: int in EventSelect.DISTRICT_COUNT:
			check(I18n.t(EventSelect.DISTRICT_KEYS[d]) != EventSelect.DISTRICT_KEYS[d], "district label %s " % lang + str(d))
		for i: int in EventCatalog.count():
			var key: String = EventCatalog.name_key(EventCatalog.id_at(i))
			check(I18n.t(key) != key, "event name %s %s" % [lang, key])
	_end()
