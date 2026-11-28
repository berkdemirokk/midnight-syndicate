extends "res://devtools/capture_scenario.gd"
## Garage car shop captures: shop_owned (starter, carousel disabled or enabled), shop_buy (unowned car, BUY button).
## A fake second car reuses the Sable files, so the carousel shows even before the other cars land. Temporary save.

const GARAGE: String = "res://ui/garage/garage.tscn"
const TEMP_SAVE: String = "user://capture_garage_shop_save.json"


func run() -> void:
	var old_cars: Array[Dictionary] = CarCatalog.cars
	GameState.open_profile(TEMP_SAVE)
	GameState.reset_profile()
	CarCatalog.cars = [
		{"id": CarCatalog.STARTER, "class": "street", "price": 0, "rep": 0},
		{"id": "demo_hatch", "class": "hatch", "price": 8000, "rep": 0, "scene": CarCatalog.scene_path("noctra_sable"), "spec": CarCatalog.spec_path("noctra_sable")},
		{"id": "demo_gt", "class": "gt", "price": 30000, "rep": 800, "scene": CarCatalog.scene_path("noctra_sable"), "spec": CarCatalog.spec_path("noctra_sable")},
	]
	cap.set_size(1920, 1080)
	var g: Variant = await cap.load_scene(GARAGE)
	await cap.wait_frames(40)
	g.orbit.touch()
	await cap.shot("shop_owned")
	g.step_car(1)
	await cap.wait_frames(40)
	g.orbit.touch()
	await cap.shot("shop_buy")
	g.step_car(1)
	await cap.wait_frames(40)
	g.orbit.touch()
	await cap.shot("shop_locked")
	# purchase confirmation: an affordable unowned car (demo_hatch, 8000) opens the modal before anything is spent
	GameState.profile["cash"] = 50000
	g.step_car(-1)
	await cap.wait_frames(40)
	g.get_hud().find_child("CarAction", true, false).pressed.emit()
	await cap.wait_frames(40)
	g.orbit.touch()
	await cap.shot("shop_confirm")
	g.get_hud().find_child("ConfirmCancel", true, false).pressed.emit()
	CarCatalog.cars = old_cars
