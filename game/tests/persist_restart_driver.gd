extends SceneTree
## Cross-process persistence driver for tools/restart_check.py. Not a test: run_tests only runs test_*.gd.
## godot --headless --path game -s res://tests/persist_restart_driver.gd -- --phase=setup|verify|loop --save=<abs> --out=<abs>
## setup: starts a career and writes the expected snapshot. verify: loads the save and writes the actual snapshot.
## loop: saves once per rep point until killed (used to kill a process mid-write).
## Uses its own GameState on the absolute save path given. The GameState autoload still reads
## user://save.json at startup, read only; nothing here writes to it.

## Loaded at runtime, not preloaded: the autoloads must exist before any script that uses them compiles.
const CAR: String = "noctra_vela"
const EVENT: String = "ortakoy_night"
const TIME_TRIAL: String = "midnight_time_trial"


func _initialize() -> void:
	_main.call_deferred()


## Deferred so the autoloads (GameState, CarCatalog users) are compiled and registered first.
func _main() -> void:
	var args: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		var eq: int = a.find("=")
		if a.begins_with("--") and eq > 2:
			args[a.substr(2, eq - 2)] = a.substr(eq + 1)
	var phase: String = args.get("phase", "")
	var save: String = args.get("save", "")
	var out: String = args.get("out", "")
	if save.is_empty() or out.is_empty() or save.begins_with("user://") or save.begins_with("res://"):
		printerr("driver: --save and --out must be absolute OS paths")
		quit(2)
		return
	var gs: Node = (load("res://core/game_state.gd") as GDScript).new()
	gs.open_profile(save)
	match phase:
		"setup":
			var fails: PackedStringArray = _setup(gs)
			_write_json(out, _snapshot(gs))
			for f: String in fails:
				printerr("driver setup: " + f)
			quit(1 if not fails.is_empty() else 0)
		"verify":
			var snap: Dictionary = _snapshot(gs)
			snap["source"] = _source(save)
			_write_json(out, snap)
			quit(0)
		"loop":
			for i: int in 1000000:
				gs.add_rep(1)
			quit(0)
		_:
			printerr("driver: unknown --phase=%s" % phase)
			quit(2)


## The career the verify run must find. Every call is checked, so a refused action fails the setup run.
func _setup(gs: Node) -> PackedStringArray:
	var fails: PackedStringArray = []
	gs.add_cash(50000)
	if not gs.buy_car(CAR, (load("res://vehicles/car_catalog.gd") as GDScript).price(CAR)):
		fails.append("buy_car failed")
	if not gs.set_paint(CAR, Color.from_string("#1e5aa0", Color.BLACK)):
		fails.append("set_paint failed")
	if not gs.set_rim(CAR, Color.from_string("#d4af37", Color.BLACK)):
		fails.append("set_rim failed")
	if not (gs.upgrade(CAR, "engine") and gs.upgrade(CAR, "engine")):
		fails.append("engine upgrades failed")
	gs.record_result(EVENT, 61.0, 2)
	gs.record_result(EVENT, 58.0, 1)
	gs.record_result(TIME_TRIAL, 80.0, 1)
	if not gs.select_car(CAR):
		fails.append("select_car failed")
	return fails


func _snapshot(gs: Node) -> Dictionary:
	return {
		"cash": gs.get_cash(),
		"rep": gs.get_rep(),
		"owned": (gs.profile["owned_cars"] as Array).duplicate(),
		"selected": gs.get_selected_car(),
		"paint": gs.get_setup(CAR)["paint_color"],
		"rim": gs.get_setup(CAR)["rim_color"],
		"engine_level": gs.get_upgrade_level(CAR, "engine"),
		"event_stars": gs.event_stars(EVENT),
		"best_time": gs.best_time(EVENT),
		"best_position": int(gs.profile["career"][EVENT]["best_position"]),
		"time_trial_stars": gs.event_stars(TIME_TRIAL),
		"total_stars": gs.total_stars(),
		"stats": (gs.profile["stats"] as Dictionary).duplicate(),
		"career": (gs.profile["career"] as Dictionary).duplicate(true),
	}


## Which file the load came from: main, then backup, else defaults. Judged from the files on disk.
func _source(save: String) -> String:
	if _parses(save):
		return "main"
	if _parses(save + ".bak"):
		return "backup"
	return "defaults"


func _parses(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return JSON.parse_string(FileAccess.get_file_as_string(path)) is Dictionary


func _write_json(path: String, data: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()
