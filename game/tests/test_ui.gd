extends "res://tests/test_case.gd"
## UI tests: every scene instantiates headless, the race HUD follows car and race state, menus take focus,
## language switches refresh text, and every I18n key exists in Turkish and English.

const SCENES: Array[String] = [
	"res://ui/hud/race_hud.tscn",
	"res://ui/menus/main_menu.tscn",
	"res://ui/menus/results_screen.tscn",
	"res://ui/menus/pause_menu.tscn",
	"res://ui/menus/settings_menu.tscn",
]
const MOCK_RACE: String = "res://devtools/scenarios/ui_mock_race.gd"
const MAIN_MENU: String = "res://ui/menus/main_menu.tscn"
const RESULTS: String = "res://ui/menus/results_screen.tscn"
const PAUSE: String = "res://ui/menus/pause_menu.tscn"
const UI_DIR: String = "res://ui"
const KEY_PREFIX_RE: String = "\"((menu|hud|ord|results|pause|settings|common)\\.[a-z_]+)\""
const COUNT_UP_FRAMES: int = 90
const PLAYER_POSITION: int = 2
const TOTAL_CARS: int = 6
const TOTAL_LAPS: int = 3

var _saved_autosave: bool = true
var _saved_language: String = "en"


func _begin() -> void:
	_saved_autosave = Settings.autosave
	_saved_language = Settings.language
	Settings.autosave = false
	Settings.set_language("en")


func _end() -> void:
	Settings.set_language(_saved_language)
	Settings.autosave = _saved_autosave


func _collect(node: Node, type_name: String, out: Array) -> void:
	if node.is_class(type_name):
		out.append(node)
	for c: Node in node.get_children():
		_collect(c, type_name, out)


func test_scenes_instantiate() -> void:
	_begin()
	var ok: int = 0
	var nodes: Array[Node] = []
	for path: String in SCENES:
		var packed: PackedScene = load(path) as PackedScene
		check(packed != null, "cannot load " + path)
		if packed == null:
			continue
		var n: Node = packed.instantiate()
		check(n != null, "cannot instantiate " + path)
		if n == null:
			continue
		add(n)
		nodes.append(n)
		ok += 1
	await frames(2)
	metric("scenes_instantiated", ok)
	check(ok == SCENES.size(), "only %d of %d scenes instantiate" % [ok, SCENES.size()])
	await cleanup(nodes)
	_end()


func test_main_menu_focus_and_backdrop() -> void:
	_begin()
	var menu: Node = add(load(MAIN_MENU).instantiate())
	await frames(2)
	var focus: Control = tree.root.gui_get_focus_owner()
	check(focus is Button, "main menu has no focused button after ready")
	if focus != null:
		metric("main_menu_focus", focus.name)
	check(menu.has_method("set_backdrop"), "main menu lacks set_backdrop")
	menu.call("set_backdrop", Node3D.new())
	await frames(1)
	var holder: Control = menu.get("_holder")
	check(holder.get_child_count() == 1, "set_backdrop did not add one SubViewport container")
	await cleanup([menu])
	_end()


func test_language_switch_refreshes_text() -> void:
	_begin()
	var menu: Node = add(load(MAIN_MENU).instantiate())
	await frames(2)
	var en: Array[String] = _button_texts(menu)
	check(en.has("RACE") and en.has("SETTINGS"), "English menu text missing: %s" % str(en))
	Settings.set_language("tr")
	await frames(1)
	var tr: Array[String] = _button_texts(menu)
	check(tr.has("YARIŞ") and tr.has("AYARLAR"), "Turkish menu text not refreshed: %s" % str(tr))
	Settings.set_language("en")
	await cleanup([menu])
	_end()


func _button_texts(root: Node) -> Array[String]:
	var buttons: Array = []
	_collect(root, "Button", buttons)
	var out: Array[String] = []
	for b: Variant in buttons:
		out.append((b as Button).text)
	return out


func test_hud_readout_follows_car_and_race() -> void:
	_begin()
	var race = load(MOCK_RACE).new()
	race.total_laps = TOTAL_LAPS
	race.race_time = 83.456
	race.fake_position = PLAYER_POSITION
	race.fake_cars = TOTAL_CARS
	race.fake_lap = 2
	race.fake_lap_time = 12.5
	race.fake_best = 61.234
	var car := ArcadeCar.new()
	var rival := ArcadeCar.new()
	race.rivals.append(car)
	race.rivals.append(rival)
	var hud: RaceHUD = add(RaceHUD.new()) as RaceHUD
	await frames(1)
	hud.bind(car, race, null)
	var dots: PackedFloat32Array = hud.get("_minimap").get("_dot_t")
	check(dots.size() == 2, "minimap has %d dots, expected 2 (player + one rival)" % dots.size())
	check(hud.find_child("SpeedFx", true, false) is Control, "SpeedFx node missing")
	car.speed_kmh = 187.4
	car.gear = 4
	car.rpm_norm = 0.82
	car.nitro_amount = 0.6
	car.nitro_active = true
	await frames(2)
	var r: Dictionary = hud.get_readout()
	check(r.get("speed", "") == "187", "speed readout = %s, expected 187" % str(r.get("speed")))
	check(r.get("gear", "") == "4", "gear readout = %s, expected 4" % str(r.get("gear")))
	check(r.get("position", "") == "2", "position readout = %s, expected 2" % str(r.get("position")))
	check(r.get("position_suffix", "") == "ND", "position suffix = %s, expected ND" % str(r.get("position_suffix")))
	check(r.get("position_total", "") == "/ 6", "position total = %s" % str(r.get("position_total")))
	check(r.get("lap", "") == "2 / 3", "lap readout = %s, expected 2 / 3" % str(r.get("lap")))
	check(r.get("time", "") == "01:23.45", "race timer = %s, expected 01:23.45" % str(r.get("time")))
	check(r.get("best", "") == "01:01.23", "best lap = %s, expected 01:01.23" % str(r.get("best")))
	check(r.get("lap_time", "") == "00:12.50", "lap time = %s, expected 00:12.50" % str(r.get("lap_time")))
	metric("speed_text", r.get("speed", ""))
	metric("timer_text", r.get("time", ""))

	# Countdown: 3, 2, 1, GO.
	var seq: Array[String] = []
	for n: int in [3, 2, 1, 0]:
		race.countdown_tick.emit(n)
		seq.append(str(hud.get_readout().get("countdown", "")))
	check(seq == ["3", "2", "1", "GO"], "countdown sequence = %s" % str(seq))
	metric("countdown_sequence", ",".join(seq))
	race.race_started.emit()

	# Drift popup appears while drifting and banks on drift_ended.
	car.is_drifting = true
	car.drift_score = 1240.0
	car.drift_started.emit()
	await frames(2)
	r = hud.get_readout()
	check(r.get("drift_visible", false) == true, "drift popup not visible while drifting")
	check(str(r.get("drift", "")).ends_with("1 240"), "drift score text = %s" % str(r.get("drift")))
	car.is_drifting = false
	car.drift_ended.emit(1240.0)
	await frames(2)
	r = hud.get_readout()
	check(r.get("bank_visible", false) == true, "bank flash not shown on drift_ended")
	check(str(r.get("bank", "")).ends_with("1 240"), "bank text = %s" % str(r.get("bank")))
	check(r.get("drift_visible", true) == false, "drift popup still visible after drift ended")

	# Wrong-way: lap progress falls steadily at speed for longer than WRONG_SHOW_S.
	car.speed_kmh = 120.0
	race.fake_progress[car.get_instance_id()] = 0.5
	for i: int in 80:  ## 1.3 s: the HUD samples every 0.25 s and needs 0.5 s of backward samples
		race.fake_progress[car.get_instance_id()] = 0.5 - 0.004 * float(i)
		await frames(1)
	check(hud.get_readout().get("wrong_way", false) == true, "wrong-way warning not shown after reversing at speed")
	race.fake_progress[car.get_instance_id()] = 0.0
	car.speed_kmh = 0.0
	await frames(40)
	check(hud.get_readout().get("wrong_way", true) == false, "wrong-way warning stays up after stopping")

	# Finish: the finished label shows when the race ends.
	var empty: Array[Dictionary] = []
	race.race_finished.emit(empty)
	await frames(1)
	check(hud.get_readout().get("finished_visible", false) == true, "finished label not shown on race_finished")

	check(RaceHUD.group_int(1240) == "1 240", "group_int(1240)")
	check(RaceHUD.group_int(1234567) == "1 234 567", "group_int(1234567)")
	check(RaceHUD.group_int(-5) == "-5", "group_int(-5)")
	check(RaceHUD.fmt_time(-1.0) == "00:00.00", "fmt_time clamps negatives")

	race.free()
	car.free()
	rival.free()
	await cleanup([hud])
	_end()


func test_results_rewards_and_signals() -> void:
	_begin()
	var screen: ResultsScreen = add(load(RESULTS).instantiate()) as ResultsScreen
	await frames(1)
	var results: Array[Dictionary] = []
	var names: PackedStringArray = ["Vance Reyes", "Kato Mori", "Ilse Brandt", "Rafa Ortiz", "Nina Kowal", "Sol Vidal"]
	for i: int in names.size():
		results.append({
			"name": names[i], "position": i + 1, "total_time": 180.0 + i * 3.2,
			"best_lap": 58.0 + i * 0.4, "is_player": i == 1})
	var retried: Array = [false]
	screen.retry_pressed.connect(func() -> void: retried[0] = true)
	screen.show_results(results, {"cash": 1200, "rep": 85})
	await frames(COUNT_UP_FRAMES)
	var rows: VBoxContainer = screen.get("_rows")
	check(rows.get_child_count() == names.size() + 1, "results rows = %d, expected 7 with header" % rows.get_child_count())
	check((screen.get("_cash_val") as Label).text == "1 200", "cash did not count up to 1 200")
	check((screen.get("_rep_val") as Label).text == "85", "rep did not count up to 85")
	(screen.get("_retry_btn") as Button).pressed.emit()
	check(retried[0] == true, "retry_pressed not emitted")
	await cleanup([screen])
	_end()


func test_pause_toggles_tree() -> void:
	_begin()
	var pause: PauseMenu = add(load(PAUSE).instantiate()) as PauseMenu
	await frames(1)
	pause.pause()
	check(tree.paused, "pause() did not pause the tree")
	check(pause.visible, "pause menu not visible when paused")
	pause.resume()
	check(not tree.paused, "resume() did not unpause the tree")
	check(not pause.visible, "pause menu still visible after resume")
	await cleanup([pause])
	_end()


func test_i18n_keys_complete_and_used() -> void:
	_begin()
	var missing: Array[String] = []
	for key: String in I18n.all_keys():
		var entry: Dictionary = I18n.DICT[key]
		for lang: String in ["tr", "en"]:
			if not entry.has(lang) or str(entry[lang]).strip_edges().is_empty():
				missing.append("%s:%s" % [key, lang])
	check(missing.is_empty(), "keys missing a language: %s" % str(missing))
	metric("i18n_keys", I18n.all_keys().size())

	var files: Array[String] = []
	_walk(UI_DIR, files)
	var re := RegEx.new()
	re.compile(KEY_PREFIX_RE)
	var used: Dictionary = {}
	for path: String in files:
		for m: RegExMatch in re.search_all(FileAccess.get_file_as_string(path)):
			used[m.get_string(1)] = path
	var unknown: Array[String] = []
	for key: Variant in used.keys():
		if not I18n.has_key(str(key)):
			unknown.append("%s (%s)" % [str(key), str(used[key])])
	check(unknown.is_empty(), "UI uses keys missing from I18n: %s" % str(unknown))
	metric("i18n_keys_used", used.size())
	_end()


func _walk(dir: String, out: Array[String]) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), out)
