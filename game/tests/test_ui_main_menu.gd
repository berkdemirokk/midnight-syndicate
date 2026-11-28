extends "res://tests/test_case.gd"
## Main menu layout: every button is at least 88 px tall, RACE is the tallest entry, and the light sweep is present.

const MAIN_MENU: String = "res://ui/menus/main_menu.tscn"


func test_menu_buttons_are_touch_size_and_race_leads() -> void:
	var menu: Node = add((load(MAIN_MENU) as PackedScene).instantiate())
	await frames(2)
	for b: Button in [menu.get("_garage_btn"), menu.get("_pursuit_btn"), menu.get("_records_btn"), menu.get("_settings_btn"), menu.get("_quit_btn")]:
		check(b.custom_minimum_size.y >= 88.0, "%s is at least 88 px tall" % b.text)
	var race: Button = menu.get("_race_btn")
	check(race.custom_minimum_size.y > (menu.get("_garage_btn") as Button).custom_minimum_size.y, "RACE is taller than the other entries")
	check(menu.find_child("LightSweep", false, false) != null, "the light sweep is on the menu")
	await cleanup([menu as Node])
