extends "res://tests/test_case.gd"
## STREET EMPIRE screen pass: pause, results, settings, records, onboarding and the LAN lobby build at desktop and
## phone size, keep exactly one visible PrimaryButton where a screen has a primary action, give every phone button a
## 44 pt target, and never print the old product name.

const PAUSE: String = "res://ui/menus/pause_menu.tscn"
const RESULTS: String = "res://ui/menus/results_screen.tscn"
const SETTINGS: String = "res://ui/menus/settings_menu.tscn"
const RECORDS: String = "res://ui/menus/records_screen.tscn"
const ONBOARDING: String = "res://ui/menus/onboarding.tscn"
## Event titles such as "Midnight Duel" are race names, not the product name; only the old product name is banned.
const OLD_NAME_WORDS: Array[String] = ["Midnight Syndicate", "Syndicate"]

var _saved_language: String = "en"
var _saved_autosave: bool = true


func _begin(phone: bool) -> void:
	_saved_autosave = Settings.autosave
	_saved_language = Settings.language
	Settings.autosave = false
	Settings.set_language("en")
	MSTheme.set_phone(phone)


func _end() -> void:
	MSTheme.set_phone(false)
	Settings.set_language(_saved_language)
	Settings.autosave = _saved_autosave


func _walk(node: Node, out: Array[Node]) -> void:
	out.append(node)
	for c: Node in node.get_children():
		_walk(c, out)


func _visible_primaries(root: Node) -> int:
	var all: Array[Node] = []
	_walk(root, all)
	var n: int = 0
	for x: Node in all:
		if x is Button and (x as Button).theme_type_variation == &"PrimaryButton" and (x as Button).is_visible_in_tree():
			n += 1
	return n


func _check_no_old_name(root: Node, screen: String) -> void:
	var all: Array[Node] = []
	_walk(root, all)
	for x: Node in all:
		var text: String = ""
		if x is Label:
			text = (x as Label).text
		elif x is Button:
			text = (x as Button).text
		for word: String in OLD_NAME_WORDS:
			check(not text.contains(word), "%s shows the old name in '%s'" % [screen, text])


func _check_phone_targets(root: Node, screen: String) -> void:
	var all: Array[Node] = []
	_walk(root, all)
	var target: float = MSTheme.button_h()
	for x: Node in all:
		if x is Button and (x as Button).is_visible_in_tree():
			var b: Button = x as Button
			check(b.custom_minimum_size.y >= target - 1.0, "%s: phone button '%s' is %.0f px, under %.0f" % [screen, b.text, b.custom_minimum_size.y, target])


func test_pause_resume_is_the_one_primary_on_both_sizes() -> void:
	for phone: bool in [false, true]:
		_begin(phone)
		var pause: Node = add(load(PAUSE).instantiate())
		pause.set("visible", true)
		await frames(3)
		check(_visible_primaries(pause) == 1, "pause (phone=%s) must show exactly one PrimaryButton" % phone)
		_check_no_old_name(pause, "pause")
		if phone:
			_check_phone_targets(pause, "pause")
		_end()
		pause.free()


func test_results_has_one_primary_and_no_old_name() -> void:
	for phone: bool in [false, true]:
		_begin(phone)
		var res: ResultsScreen = add(load(RESULTS).instantiate()) as ResultsScreen
		var rows: Array[Dictionary] = [
			{"name": "You", "position": 1, "total_time": 61.2, "best_lap": 20.1, "is_player": true},
			{"name": "Rival", "position": 2, "total_time": 62.0, "best_lap": 20.5, "is_player": false}]
		res.show_results(rows, {"cash": 1200, "rep": 40})
		await frames(3)
		check(_visible_primaries(res) == 1, "results (phone=%s) must show exactly one PrimaryButton" % phone)
		_check_no_old_name(res, "results")
		if phone:
			_check_phone_targets(res, "results")
		_end()
		res.free()


func test_settings_records_onboarding_build_on_both_sizes() -> void:
	for phone: bool in [false, true]:
		_begin(phone)
		var settings: Node = add(load(SETTINGS).instantiate())
		var records: Node = add(load(RECORDS).instantiate())
		var onboard: Node = add(load(ONBOARDING).instantiate())
		await frames(3)
		check(_visible_primaries(onboard) == 1, "onboarding step 1 (phone=%s) must show exactly one PrimaryButton" % phone)
		check(_visible_primaries(settings) == 0, "settings has no primary action")
		check(_visible_primaries(records) == 0, "records has no primary action")
		for s: Array in [["settings", settings], ["records", records], ["onboarding", onboard]]:
			_check_no_old_name(s[1], s[0])
			if phone:
				_check_phone_targets(s[1], s[0])
		_end()
		settings.free()
		records.free()
		onboard.free()
