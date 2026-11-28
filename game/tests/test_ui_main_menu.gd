extends "res://tests/test_case.gd"
## Main menu layout: every button is at least 88 px tall, PLAY is the tallest (primary) entry, CAREER and QUICK RACE
## are there, the showroom exists with a GPU, and QUICK RACE picks an unlocked race that is not a pursuit run.

const MAIN_MENU: String = "res://ui/menus/main_menu.tscn"


func test_menu_buttons_are_touch_size_and_race_leads() -> void:
	var menu: Node = add((load(MAIN_MENU) as PackedScene).instantiate())
	await frames(2)
	for b: Button in [menu.get("_quick_btn"), menu.get("_garage_btn"), menu.get("_pursuit_btn"), menu.get("_records_btn"), menu.get("_settings_btn"), menu.get("_quit_btn")]:
		check(b.custom_minimum_size.y >= 88.0, "%s is at least 88 px tall" % b.text)
	var race: Button = menu.get("_race_btn")
	check(race.custom_minimum_size.y > (menu.get("_garage_btn") as Button).custom_minimum_size.y, "RACE is taller than the other entries")
	# STREET EMPIRE main screen (owner brief 2026-11-28: "prominent PLAY action", the car in a 3D showroom):
	# PLAY is the primary and starts the featured event; CAREER and QUICK RACE are nav entries; the showroom replaces
	# the 2D light sweep and hero stage (headless runs have no GPU, so the showroom is off there).
	check(race.text == I18n.t("menu.race") and race.theme_type_variation == &"PrimaryButton", "the primary entry is PLAY")
	check((menu.get("_career_btn") as Button).text == I18n.t("menu.career"), "CAREER is on the menu")
	check((menu.get("_quick_btn") as Button).text == I18n.t("menu.quick_race"), "QUICK RACE is on the menu")
	check(menu.get("stage") != null or not MainMenu.showroom_enabled, "the selected car showroom is on the menu when a GPU is there")
	await cleanup([menu as Node])


func test_quick_race_picks_an_unlocked_ladder_race() -> void:
	var id: String = MainMenu.quick_race_id()
	check(id != "", "QUICK RACE finds a race")
	check(GameState.is_event_unlocked(id) and not EventCatalog.is_open(id), "%s is an unlocked ladder race" % id)
	check(not bool(EventCatalog.find(id).get("pursuit", false)), "QUICK RACE never starts a pursuit run")
