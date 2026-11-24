extends SceneTree
## Diagnostic (not a test): one AI car, skill 1.0, two laps on city_01. Logs nitro charge, nitro state,
## speed and track progress every tick, then prints and writes per lap: max speed and where it happened,
## nitro seconds, and 50 m bins of speed and nitro use along the lap.
## Options: --skill=<0.8..1.0>, --laps=<n>, --out=<file name in evidence/logs>.
## godot --headless --fixed-fps 60 --path game -s res://ai/diag_nitro.gd

const SCENE_PATH: String = "res://world/city_01/city_01.tscn"
const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const MAX_TICKS: int = 60 * 400
const BIN_M: float = 50.0


class Monitor extends Node:
	var city: CityBuilder
	var manager: RaceManager
	var car: ArcadeCar
	var driver: AIDriver
	var out_name: String = "nitro_trace.json"
	var tick: int = 0
	var done: bool = false
	var rows: Array = []  ## [tick, lap, s_m, kmh, nitro_amount, nitro_active, throttle, brake]
	var laps: Array = []  ## per lap: max kmh, s at max, nitro seconds, nitro starts
	var cur_lap: int = 1
	var lap_max_kmh: float = 0.0
	var lap_max_s: float = 0.0
	var lap_nitro_s: float = 0.0
	var lap_nitro_starts: int = 0
	var lap_start_amount: float = 1.0
	var bin_kmh: Dictionary = {}  ## lap:bin -> max kmh
	var bin_nitro: Dictionary = {}  ## lap:bin -> nitro ticks
	var last_active: bool = false
	var last_s: float = -1.0

	func _physics_process(delta: float) -> void:
		if done:
			return
		tick += 1
		var s: float = city.get_progress(car.global_position, last_s)
		last_s = s
		var lap: int = manager.get_lap(car)
		if lap != cur_lap and manager.state == RaceManager.State.RACING:
			_close_lap()
			cur_lap = lap
		var kmh: float = car.speed_kmh
		var active: bool = car.nitro_active
		if active and not last_active:
			lap_nitro_starts += 1
		last_active = active
		if active:
			lap_nitro_s += delta
		if kmh > lap_max_kmh:
			lap_max_kmh = kmh
			lap_max_s = s
		var b: int = int(s / BIN_M)
		var key: String = "%d:%d" % [cur_lap, b]
		bin_kmh[key] = maxf(float(bin_kmh.get(key, 0.0)), kmh)
		if active:
			bin_nitro[key] = int(bin_nitro.get(key, 0)) + 1
		if tick % 2 == 0:
			rows.append([tick, cur_lap, snappedf(s, 0.1), snappedf(kmh, 0.1), snappedf(car.nitro_amount, 0.001), 1 if active else 0, snappedf(car.input.throttle, 0.01), snappedf(car.input.brake, 0.01)])
		if manager.state == RaceManager.State.FINISHED or tick >= MAX_TICKS:
			_close_lap()
			_finish_run()

	func _close_lap() -> void:
		laps.append({"lap": cur_lap, "max_kmh": snappedf(lap_max_kmh, 0.1), "max_at_s_m": snappedf(lap_max_s, 1.0),
			"nitro_s": snappedf(lap_nitro_s, 0.01), "nitro_starts": lap_nitro_starts,
			"nitro_amount_at_lap_start": snappedf(lap_start_amount, 0.001)})
		lap_max_kmh = 0.0
		lap_max_s = 0.0
		lap_nitro_s = 0.0
		lap_nitro_starts = 0
		lap_start_amount = car.nitro_amount

	func _finish_run() -> void:
		done = true
		var bins: Array = []
		for k: String in bin_kmh.keys():
			var parts: PackedStringArray = k.split(":")
			bins.append({"lap": int(parts[0]), "bin_start_m": int(parts[1]) * BIN_M, "max_kmh": snappedf(float(bin_kmh[k]), 0.1), "nitro_ticks": int(bin_nitro.get(k, 0))})
		bins.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["lap"] * 100000.0 + a["bin_start_m"] < b["lap"] * 100000.0 + b["bin_start_m"])
		var profile: Array = []
		var ps: float = 0.0
		while ps < city.length:
			profile.append([snappedf(ps, 1.0), snappedf(city.get_target_speed(ps) * 3.6, 0.1), snappedf(city.get_curvature(ps), 0.00001)])
			ps += 10.0
		var out: Dictionary = {"track_length_m": snappedf(city.length, 0.1), "race_time_s": snappedf(manager.race_time, 0.01),
			"ticks": tick, "laps": laps, "bins": bins, "profile_cols": "s_m,target_kmh,curvature", "profile": profile,
			"row_cols": "tick,lap,s_m,kmh,nitro_amount,nitro_active,throttle,brake", "rows": rows}
		var path: String = ProjectSettings.globalize_path("res://").path_join("../evidence/logs/" + out_name).simplify_path()
		var fa := FileAccess.open(path, FileAccess.WRITE)
		if fa != null:
			fa.store_string(JSON.stringify(out))
			fa.close()
		for l: Dictionary in laps:
			print("DIAG lap %d: max %.1f km/h at s %.0f m, nitro %.2f s in %d starts, charge at lap start %.3f" % [l["lap"], l["max_kmh"], l["max_at_s_m"], l["nitro_s"], l["nitro_starts"], l["nitro_amount_at_lap_start"]])
		print("DIAG length %.1f m, race %.2f s, ticks %d" % [city.length, manager.race_time, tick])
		get_tree().quit(0)


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	var skill: float = 1.0
	var laps: int = 2
	var out_name: String = "nitro_trace.json"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--skill="):
			skill = float(a.trim_prefix("--skill="))
		if a.begins_with("--laps="):
			laps = int(a.trim_prefix("--laps="))
		if a.begins_with("--out="):
			out_name = a.trim_prefix("--out=")
	var city: CityBuilder = (load(SCENE_PATH) as PackedScene).instantiate() as CityBuilder
	root.add_child(city)
	var manager := RaceManager.new()
	manager.total_laps = laps
	root.add_child(manager)
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	root.add_child(car)
	var d := AIDriver.new()
	d.name = "AIDriver"
	d.skill = skill
	car.add_child(d)
	var cars: Array[ArcadeCar] = [car]
	manager.setup(city, cars, null, PackedStringArray(["Solo"]))
	var mon := Monitor.new()
	mon.process_physics_priority = 1
	mon.city = city
	mon.manager = manager
	mon.car = car
	mon.driver = d
	mon.out_name = out_name
	root.add_child(mon)
	manager.start_countdown()
