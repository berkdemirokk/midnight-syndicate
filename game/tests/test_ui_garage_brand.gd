extends "res://tests/test_case.gd"
## Garage configurator layer: buying a car or an upgrade opens a confirmation and spends nothing until CONFIRM, CANCEL
## and Escape keep the cash, the collection strip lists the available cars and a card jumps to its car, and the
## PAINT / RIMS / UPGRADES tabs and the one primary RACE button exist. Same temporary-save setup as test_garage.gd.

const GARAGE: String = "res://ui/garage/garage.tscn"
const TEMP_SAVE: String = "user://test_ui_garage_brand_save.json"
const CAR: String = "noctra_sable"  ## unowned, 2500, no rep needed
const CAR_PRICE: int = 2500
const ENGINE_COST: int = 800


func _open_temp_profile() -> Dictionary:
	var old: Dictionary = {"path": GameState.save_path, "profile": GameState.profile.duplicate(true), "lang": Settings.language}
	GameState.open_profile(TEMP_SAVE)
	GameState.reset_profile()
	GameState.profile["cash"] = 5000
	return old


func _restore(old: Dictionary) -> void:
	GameState.save_path = str(old["path"])
	GameState.profile = old["profile"]
	Settings.language = str(old["lang"])
	var abs_path: String = ProjectSettings.globalize_path(TEMP_SAVE)
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEMP_SAVE + suffix):
			DirAccess.remove_absolute(abs_path + suffix)


func _spawn_garage() -> Variant:
	var packed: PackedScene = load(GARAGE) as PackedScene
	return add(packed.instantiate()) as Node3D


func _cancel_event() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	return ev


func test_buying_car_asks_before_spending() -> void:
	var old: Dictionary = _open_temp_profile()
	var g: Variant = _spawn_garage()
	await frames(2)
	g.show_car(CAR)
	await frames(2)
	var hud: GarageHud = g.get_hud()
	var cash0: int = GameState.get_cash()
	var asked: Array = []
	hud.car_action_pressed.connect(func() -> void: asked.append(true))
	hud.find_child("CarAction", true, false).pressed.emit()
	check(hud.confirm_open(), "buying an unowned car opens the confirmation")
	check(asked.is_empty(), "the car is not bought before CONFIRM")
	check(GameState.get_cash() == cash0 and not GameState.has_car(CAR), "nothing is spent or owned while the confirmation is open")
	var info: Dictionary = hud.confirm_info()
	check(int(info.get("cost", -1)) == CAR_PRICE, "confirmation shows the price, got %s" % str(info.get("cost")))
	check(int(info.get("balance", -1)) == cash0 - CAR_PRICE, "confirmation shows the balance after the price")
	hud.find_child("ConfirmCancel", true, false).pressed.emit()
	check(not hud.confirm_open(), "CANCEL closes the confirmation")
	check(GameState.get_cash() == cash0 and not GameState.has_car(CAR), "CANCEL keeps the cash")
	check(asked.is_empty(), "CANCEL does not buy")
	hud.find_child("CarAction", true, false).pressed.emit()
	hud._unhandled_input(_cancel_event())
	check(not hud.confirm_open() and GameState.get_cash() == cash0, "Escape cancels the confirmation and keeps the cash")
	hud.find_child("CarAction", true, false).pressed.emit()
	hud.find_child("ConfirmOk", true, false).pressed.emit()
	check(GameState.has_car(CAR) and GameState.get_selected_car() == CAR, "CONFIRM buys and selects the car")
	check(GameState.get_cash() == cash0 - CAR_PRICE, "CONFIRM spends exactly the price")
	await cleanup([g])
	_restore(old)


func test_upgrade_asks_before_spending() -> void:
	var old: Dictionary = _open_temp_profile()
	var g: Variant = _spawn_garage()
	await frames(2)
	var hud: GarageHud = g.get_hud()
	var car_id: String = g.car_id
	var cash0: int = GameState.get_cash()
	hud.get_buy_button("engine").pressed.emit()
	check(hud.confirm_open(), "an affordable upgrade opens the confirmation")
	check(GameState.get_upgrade_level(car_id, "engine") == 0 and GameState.get_cash() == cash0, "upgrade not bought before CONFIRM")
	hud.find_child("ConfirmCancel", true, false).pressed.emit()
	check(GameState.get_upgrade_level(car_id, "engine") == 0 and GameState.get_cash() == cash0, "CANCEL keeps the level and the cash")
	hud.get_buy_button("engine").pressed.emit()
	hud.find_child("ConfirmOk", true, false).pressed.emit()
	check(GameState.get_upgrade_level(car_id, "engine") == 1, "CONFIRM buys the next level")
	check(GameState.get_cash() == cash0 - ENGINE_COST, "CONFIRM spends the level cost")
	await cleanup([g])
	_restore(old)


func test_collection_strip_and_tabs() -> void:
	var old: Dictionary = _open_temp_profile()
	var g: Variant = _spawn_garage()
	await frames(2)
	var hud: GarageHud = g.get_hud()
	var ids: Array[String] = CarCatalog.available_ids()
	check(hud.get_strip_ids() == ids, "the strip lists CarCatalog.available_ids() in order")
	var target: String = ids[ids.size() - 1]
	hud.get_strip_button(target).pressed.emit()
	check(g.car_id == target, "a card jumps to its car, got %s" % g.car_id)
	for page: String in ["paint", "rims", "upgrades"]:
		check(hud.get_tab_button(page) != null, "tab %s exists" % page)
	check(hud.get_race_button().theme_type_variation == &"PrimaryButton", "RACE is the one primary button")
	await cleanup([g])
	_restore(old)
