extends "res://tests/test_case.gd"
## Car shop: catalog hides cars whose files are missing, buying spends cash and owns the car, rep gate, selection
## feeds the race config, rival mix is deterministic, old saves load, garage carousel swaps the turntable car.
## Uses a fake catalog entry that reuses the Sable files, so the test works before the other cars land.

const GARAGE: String = "res://ui/garage/garage.tscn"
const TEMP_SAVE: String = "user://test_car_shop_save.json"
const SABLE: String = "noctra_sable"
const STARTER: String = CarCatalog.STARTER


func _open_temp_profile() -> Dictionary:
	var old: Dictionary = {"path": GameState.save_path, "profile": GameState.profile.duplicate(true), "lang": Settings.language, "cars": CarCatalog.cars}
	GameState.open_profile(TEMP_SAVE)
	GameState.reset_profile()
	CarCatalog.cars = [
		{"id": STARTER, "class": "street", "price": 0, "rep": 0},
		{"id": "fake_cheap", "class": "hatch", "price": 3000, "rep": 0, "scene": CarCatalog.scene_path(STARTER), "spec": CarCatalog.spec_path(STARTER)},
		{"id": "fake_rep", "class": "gt", "price": 100, "rep": 500, "scene": CarCatalog.scene_path(STARTER), "spec": CarCatalog.spec_path(STARTER)},
		{"id": "fake_missing", "class": "muscle", "price": 1, "rep": 0},
	]
	return old


func _restore(old: Dictionary) -> void:
	GameState.save_path = str(old["path"])
	GameState.profile = old["profile"]
	Settings.language = str(old["lang"])
	CarCatalog.cars = old["cars"]
	var abs_path: String = ProjectSettings.globalize_path(TEMP_SAVE)
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEMP_SAVE + suffix):
			DirAccess.remove_absolute(abs_path + suffix)


func test_catalog_hides_missing_files() -> void:
	var old: Dictionary = _open_temp_profile()
	var ids: Array[String] = CarCatalog.available_ids()
	check(ids == [STARTER, "fake_cheap", "fake_rep"], "missing-file car is hidden, order kept: %s" % str(ids))
	check(not CarCatalog.is_available("fake_missing") and not CarCatalog.is_available("nope"), "missing and unknown ids are unavailable")
	_restore(old)
	var real: Array[String] = CarCatalog.available_ids()
	check(real.has(STARTER) and real[0] == STARTER, "default catalog always shows the starter first")
	for id: String in real:
		check(not CarCatalog.stats(id).is_empty(), "%s has stats from its spec" % id)


func test_buy_flow() -> void:
	var old: Dictionary = _open_temp_profile()
	GameState.profile["cash"] = 2000
	check(CarCatalog.buy_block("fake_cheap") == "cash", "short cash blocks")
	check(not CarCatalog.buy("fake_cheap") and GameState.get_cash() == 2000 and not GameState.has_car("fake_cheap"), "failed buy changes nothing")
	GameState.profile["cash"] = 5000
	check(CarCatalog.buy("fake_cheap"), "affordable car is bought")
	check(GameState.get_cash() == 2000 and GameState.has_car("fake_cheap"), "cash spent and car owned")
	check(not CarCatalog.buy("fake_cheap") and GameState.get_cash() == 2000, "no double buy")
	check(CarCatalog.buy_block("fake_rep") == "rep", "rep gate blocks")
	GameState.profile["rep"] = 500
	check(CarCatalog.buy_block("fake_rep") == "", "rep met unlocks")
	check(not GameState.buy_car("x", -5), "negative price refused")
	# save round trip keeps the garage
	GameState.open_profile(TEMP_SAVE)
	check(GameState.has_car("fake_cheap"), "owned car survives a reload")
	_restore(old)


func test_old_profile_loads() -> void:
	var old: Dictionary = _open_temp_profile()
	var f: FileAccess = FileAccess.open(TEMP_SAVE, FileAccess.WRITE)
	f.store_string('{"version":1,"cash":1234,"rep":5,"owned_cars":["noctra_sable"],"selected_car":"noctra_sable","car_setups":{"noctra_sable":{"paint_color":"#112233","rim_color":"#c0c0c0","upgrades":{"engine":2}}}}')
	f.close()
	GameState.open_profile(TEMP_SAVE)
	check(GameState.get_cash() == 1234 and GameState.get_selected_car() == SABLE, "old save loads")
	check(GameState.has_car(SABLE), "old save keeps the car it owns")
	check(GameState.get_upgrade_level(SABLE, "engine") == 2, "setup kept")
	CarCatalog.cars.append({"id": SABLE, "class": "street", "price": 2500, "rep": 0})
	check(CarCatalog.race_car_id() == SABLE, "old save still races the car it selected")
	_restore(old)


func test_selection_feeds_race_config() -> void:
	var old: Dictionary = _open_temp_profile()
	GameState.profile["cash"] = 9000
	CarCatalog.buy("fake_cheap")
	GameState.select_car("fake_cheap")
	check(CarCatalog.race_car_id() == "fake_cheap", "selected car races")
	var c: RaceConfig = EventCatalog.config_for("wharf_sprint")
	check(c.car_scene == CarCatalog.scene_path("fake_cheap") and c.car_spec_path == CarCatalog.spec_path("fake_cheap"), "config carries the selected car")
	CarCatalog.cars = [{"id": STARTER, "class": "street", "price": 0, "rep": 0}]  # the car's files vanish
	check(CarCatalog.race_car_id() == STARTER, "unavailable selection falls back to the starter")
	_restore(old)


func test_rival_models() -> void:
	var old: Dictionary = _open_temp_profile()
	var a: Array[Dictionary] = CarCatalog.rival_models(5, 7)
	var b: Array[Dictionary] = CarCatalog.rival_models(5, 7)
	check(a.size() == 5 and a == b, "same seed, same grid")
	var seen: Dictionary = {}
	for r: Dictionary in a:
		seen[r["id"]] = true
		check(ResourceLoader.exists(str(r["scene"])) and ResourceLoader.exists(str(r["spec"])), "rival files exist")
	check(seen.size() == 3, "every available model appears: %s" % str(seen.keys()))
	for r: Dictionary in CarCatalog.rival_models(4, 1, "hatch"):
		check(r["id"] == "fake_cheap", "class filter")
	check(CarCatalog.rival_models(2, 1, "no_such_class")[0]["id"] == STARTER, "empty filter falls back to the starter")
	_restore(old)


func test_garage_carousel() -> void:
	var old: Dictionary = _open_temp_profile()
	GameState.profile["cash"] = 4000
	var g: Node3D = add((load(GARAGE) as PackedScene).instantiate()) as Node3D
	await frames(3)
	check(g.car_id == STARTER, "garage opens on the selected car")
	check(g.step_car(1) == "fake_cheap", "next car")
	var s: Dictionary = g.state()
	check(not bool(s["owned"]) and int(s["price"]) == 3000 and str(s["block"]) == "", "shop state of an unowned car")
	var tab_cars: int = 0
	for n: Node in g.find_children("*", "Node", true, false):
		if n is CarLod:
			tab_cars += 1
	check(tab_cars == 1, "exactly one car on the turntable, got %d" % tab_cars)
	check(not g.commit_paint(Color.BLUE), "unowned car cannot be painted")
	check(g.car_action(), "buy through the garage")
	check(GameState.has_car("fake_cheap") and GameState.get_selected_car() == "fake_cheap" and GameState.get_cash() == 1000, "bought and selected")
	check(g.commit_paint(Color.BLUE), "owned car can be painted")
	check(g.step_car(1) == "fake_rep", "third car")
	check(g.step_car(1) == STARTER, "carousel wraps")
	check(g.car_action() and GameState.get_selected_car() == STARTER, "select an owned car")
	Settings.language = "tr"
	g.get_hud().apply_language()
	check(g.get_hud().find_child("CarAction", true, false).text == GarageText.t("garage.car_selected"), "carousel text follows language")
	g.queue_free()
	await frames(2)
	_restore(old)


func test_rival_pool_prefers_flagged_cars() -> void:
	var old: Dictionary = _open_temp_profile()
	CarCatalog.cars = [
		{"id": STARTER, "class": "street", "price": 0, "rep": 0},
		{"id": "fake_cheap", "class": "hatch", "price": 3000, "rep": 0, "rival": true, "scene": CarCatalog.scene_path(STARTER), "spec": CarCatalog.spec_path(STARTER)},
		{"id": "fake_rep", "class": "gt", "price": 100, "rep": 500, "rival": true, "scene": CarCatalog.scene_path(STARTER), "spec": CarCatalog.spec_path(STARTER)},
	]
	var seen: Dictionary = {}
	for r: Dictionary in CarCatalog.rival_models(6, 3):
		seen[r["id"]] = true
	check(not seen.has(STARTER) and seen.has("fake_cheap") and seen.has("fake_rep"), "two flagged cars: only they race: %s" % str(seen.keys()))
	CarCatalog.cars[2]["rival"] = false
	seen.clear()
	for r: Dictionary in CarCatalog.rival_models(6, 3):
		seen[r["id"]] = true
	check(seen.has(STARTER) and seen.size() == 3, "one flagged car: every available car races: %s" % str(seen.keys()))
	_restore(old)
	for r: Dictionary in CarCatalog.rival_models(12, 5):
		check(bool(CarCatalog.info(str(r["id"])).get("rival", false)), "real rival grid uses flagged cars only: %s" % str(r["id"]))
