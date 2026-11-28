extends "res://tests/test_case.gd"
## Pursuit entry: the main menu button opens the pursuit select, the select lists the open pursuit runs and starts
## them with a pursuit config, and normal races never get the pursuit flag.

const MAIN_MENU: String = "res://ui/menus/main_menu.tscn"
const SELECT: String = "res://race/pursuit/pursuit_select.tscn"


func test_menu_button_opens_the_pursuit_select() -> void:
	var menu: MainMenu = (load(MAIN_MENU) as PackedScene).instantiate() as MainMenu
	var calls: Array = []
	menu.nav = func(scene: String, _params: Dictionary) -> void: calls.append(scene)
	add(menu)
	await frames(2)
	var btn: Button = menu.get("_pursuit_btn") as Button
	check(btn != null and btn.text == I18n.t("menu.pursuit"), "the menu has a pursuit button with its label")
	check(btn.custom_minimum_size.y >= 88.0, "the pursuit button is at least 88 px tall")
	btn.pressed.emit()
	check(calls == [SELECT], "the pursuit button opens the select screen")
	await cleanup([menu as Node])


func test_select_lists_the_open_pursuit_runs_and_starts_one() -> void:
	var ids: Array[String] = PursuitSelect.run_ids()
	check(ids.size() >= 5, "the select lists the open pursuit runs (%d)" % ids.size())
	for id: String in ids:
		var ev: Dictionary = EventCatalog.find(id)
		check(bool(ev.get("pursuit", false)) and bool(ev.get("open", false)), "%s is an open pursuit run" % id)
	check(ids.has("pursuit_wharf_escape") and ids.has("pursuit_bogaz_survive"), "the new open runs are listed")
	var screen: PursuitSelect = (load(SELECT) as PackedScene).instantiate() as PursuitSelect
	var calls: Array = []
	screen.nav = func(scene: String, params: Dictionary) -> void: calls.append([scene, params])
	add(screen)
	await frames(2)
	var rows: int = screen.find_children("Run_*", "Button", true, false).size()
	check(rows == ids.size(), "one button per run (%d)" % rows)
	var first: Button = screen.find_child("Run_pursuit_wharf_escape", true, false) as Button
	check(first != null and not first.disabled, "a run button is present and unlocked")
	screen.start_run("pursuit_wharf_escape")
	check(calls.size() == 1 and calls[0][0] == EventSelect.RACE_SCENE, "a run goes to the race scene")
	var cfg: RaceConfig = (calls[0][1] as Dictionary).get(RaceScene.CONFIG_PARAM) if calls.size() == 1 else null
	check(cfg != null and cfg.pursuit and cfg.event_id == "pursuit_wharf_escape", "the run starts with its pursuit config")
	screen.back()
	check(calls.size() == 2 and calls[1][0] == MAIN_MENU, "back returns to the main menu")
	await cleanup([screen as Node])


func test_normal_races_never_get_pursuit() -> void:
	var checked: int = 0
	for ev: Dictionary in EventCatalog.EVENTS:
		if bool(ev.get("pursuit", false)):
			continue
		var cfg: RaceConfig = EventCatalog.config_for(str(ev["id"]))
		check(not cfg.pursuit and not cfg.pursuit_event, "%s has no pursuit" % str(ev["id"]))
		checked += 1
	check(checked > 30, "checked %d normal events" % checked)
	check(RaceConfig.new().pursuit == false, "a default race config has no pursuit")
