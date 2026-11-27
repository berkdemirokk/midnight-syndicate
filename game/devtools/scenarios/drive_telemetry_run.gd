extends Node
## Driving telemetry, not a test. Complete races in the real race scene (race/race_scene.tscn) with an autopilot
## player; every number is measured per physics tick and written as JSON. Race results go to a scratch save
## (user://telemetry_save.json), so the owner's profile is never written. The autopilot is an AIDriver, not a
## human: its skill is a stand-in for a player.
##
## Headless sim (60 Hz, no render):
##   godot --headless --audio-driver Dummy --fixed-fps 60 --path game -s res://devtools/scenarios/drive_telemetry.gd -- --mode=sim --part=matrix --track=bogaz --out=<abs json>
## Rendered start hitch (run under the GPU lock; real frame timing, so no --headless and no --fixed-fps):
##   godot --audio-driver Dummy --resolution 1920x1080 --position 20000,0 --path game -s res://devtools/scenarios/drive_telemetry.gd -- --mode=hitch --out=<abs json>
## --part: restart | matrix | first | fairness | all (sim only). --track: bogaz | city01 (matrix only).

const RACE_SCENE: String = "res://race/race_scene.tscn"
const SCRATCH_SAVE: String = "user://telemetry_save.json"
const TRACK_SCENES: Dictionary = {"bogaz": "res://world/istanbul_bogaz/istanbul_bogaz.tscn", "city01": "res://world/city_01/city_01.tscn"}
const PLAYER_CARS: Array[String] = ["noctra_tayfun", "kestrel_marten", "bosfor_yildirim"]  ## starter, mid, top
const OPPONENT_COUNTS: Array[int] = [3, 7]  ## grid of 4 and grid of 8 (the player takes the last slot)
const MATRIX_LAPS: int = 2
const FIRST_RACE_PLAYER_SKILLS: Array[float] = [0.80, 0.90, 0.97]  ## autopilot stand-ins for the player
const RESTART_RUNS: int = 4  ## the first run plus 3 retries of the same race
const TEAR_M: float = 5.0  ## a one-tick jump above this is a teleport (a reset); 5 m per 1/60 s is 300 km/h
const TICK_HZ: float = 60.0
const MAX_TICKS: int = 54000  ## 900 s of simulated race time; a race not done by then is timed out
const HITCH_LENGTH_S: float = 6.0  ## the rendered run records this long after GO
const HITCH_GUARD_S: float = 90.0
const MACHINE_NOTE: String = "Windows 11 dev PC, NVIDIA RTX 5060 Ti 8 GB, Godot 4.7.2. Not a phone."

var _mode: String = "sim"
var _part: String = "all"
var _track_filter: String = ""
var _out_path: String = ""


func _ready() -> void:
	_read_args()
	_run()


func _read_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			_mode = a.trim_prefix("--mode=")
		elif a.begins_with("--part="):
			_part = a.trim_prefix("--part=")
		elif a.begins_with("--track="):
			_track_filter = a.trim_prefix("--track=")
		elif a.begins_with("--out="):
			_out_path = a.trim_prefix("--out=")


func _run() -> void:
	_clean_scratch_save()
	get_node("/root/GameState").call("open_profile", SCRATCH_SAVE)
	var data: Dictionary = {}
	if _mode == "hitch":
		data = await _hitch()
	else:
		data["sim_tick_hz"] = TICK_HZ
		if _part == "all" or _part == "restart":
			data["restart"] = await _restart_block()
		if _part == "all" or _part == "first":
			data["first_race"] = await _first_race_block()
		if _part == "all" or _part == "matrix":
			data["matrix"] = await _matrix_block()
		if _part == "all" or _part == "fairness":
			data["fairness"] = _fairness_block()
	data["machine"] = MACHINE_NOTE
	data["mode"] = _mode
	data["part"] = _part
	data["cpu"] = OS.get_processor_name()
	data["godot"] = Engine.get_version_info()["string"]
	_write(data)
	get_tree().quit(0)


func _clean_scratch_save() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(SCRATCH_SAVE + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SAVE + suffix))


func _write(data: Dictionary) -> void:
	if _out_path.is_empty():
		push_error("drive_telemetry: --out=<absolute path> is required")
		return
	DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
	var f: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if f == null:
		push_error("drive_telemetry: cannot write %s" % _out_path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("drive_telemetry: wrote %s" % _out_path)


## A sim config: one autopilot player on a real track, rivals all driving the player's model (rival_mix off),
## so the finishing position measures driving and not the car pool.
func _config(track_scene: String, car_id: String, opponents: int, laps: int, tag: String) -> RaceConfig:
	var c := RaceConfig.new()
	c.event_id = "telemetry_" + tag
	c.track_scene = track_scene
	c.car_scene = CarCatalog.scene_path(car_id)
	c.car_spec_path = CarCatalog.spec_path(car_id)
	c.laps = laps
	c.opponent_count = opponents
	c.rival_mix = false
	c.traffic_enabled = false
	c.autopilot = true
	c.autopilot_skill = 0.97
	c.use_garage_paint = false
	c.time_of_day = "night"
	return c


func _spec_top(car_id: String) -> float:
	var spec: CarSpec = load(CarCatalog.spec_path(car_id)) as CarSpec
	return spec.top_speed_kmh if spec != null else -1.0


func _new_state() -> Dictionary:
	return {"done": false, "timed_out": false, "ticks": 0, "finish_time": -1.0, "results": [],
		"laps": [], "lap_times": [], "contact_events": [], "teleports": [], "top": [], "last": [], "last_valid": false,
		"t100": -1.0, "t200": -1.0}


## Hooks a race that exists: lap, finish and contact signals, per-car arrays sized to the grid.
func _attach(scene: RaceScene, st: Dictionary) -> void:
	var n: int = scene.cars.size()
	for i: int in n:
		st["laps"].append(0)
		st["lap_times"].append([])
		st["contact_events"].append(0)
		st["teleports"].append(0)
		st["top"].append(0.0)
		st["last"].append(scene.cars[i].global_position)
		var k: int = i
		scene.cars[i].hit.connect(_on_hit.bind(st, k, scene))
	scene.race.lap_completed.connect(_on_lap.bind(st, scene))
	scene.race.race_finished.connect(_on_finished.bind(st, scene))


func _is_racing(scene: RaceScene) -> bool:
	return scene.race != null and scene.race.state == RaceManager.State.RACING


func _on_hit(_impulse: float, _pos: Vector3, st: Dictionary, k: int, scene: RaceScene) -> void:
	if _is_racing(scene):
		st["contact_events"][k] = int(st["contact_events"][k]) + 1


func _on_lap(car: ArcadeCar, lap: int, lap_time: float, st: Dictionary, scene: RaceScene) -> void:
	var i: int = scene.cars.find(car)
	if i < 0:
		return
	st["laps"][i] = lap
	(st["lap_times"][i] as Array).append(lap_time)


func _on_finished(results: Array[Dictionary], st: Dictionary, scene: RaceScene) -> void:
	st["results"] = results
	st["finish_time"] = scene.race.race_time
	st["done"] = true


func _drive_to_finish(scene: RaceScene, st: Dictionary) -> void:
	while not bool(st["done"]) and int(st["ticks"]) < MAX_TICKS:
		await get_tree().physics_frame
		st["ticks"] = int(st["ticks"]) + 1
		_sample(scene, st)
	st["timed_out"] = not bool(st["done"])


## Once per physics tick: top speed per car, teleports (resets) while racing, and the player's 0-100 and 0-200 times.
func _sample(scene: RaceScene, st: Dictionary) -> void:
	var race: RaceManager = scene.race
	if race == null:
		return
	var racing: bool = race.state == RaceManager.State.RACING
	for i: int in scene.cars.size():
		var car: ArcadeCar = scene.cars[i]
		st["top"][i] = maxf(float(st["top"][i]), car.speed_kmh)
		var last: Vector3 = st["last"][i]
		if racing and bool(st["last_valid"]) and last.distance_to(car.global_position) > TEAR_M:
			st["teleports"][i] = int(st["teleports"][i]) + 1
		st["last"][i] = car.global_position
	st["last_valid"] = racing
	var p: ArcadeCar = scene.player
	if racing and p != null:
		if float(st["t100"]) < 0.0 and p.speed_kmh >= 100.0:
			st["t100"] = race.race_time
		if float(st["t200"]) < 0.0 and p.speed_kmh >= 200.0:
			st["t200"] = race.race_time


func _best(times: Array) -> Variant:
	if times.is_empty():
		return null
	var b: float = float(times[0])
	for t: Variant in times:
		b = minf(b, float(t))
	return snappedf(b, 0.001)


func _record(tag: String, scene: RaceScene, cfg: RaceConfig, st: Dictionary) -> Dictionary:
	var n: int = scene.cars.size()
	var p_idx: int = scene.cars.find(scene.player)
	var per: Array = []
	var stuck_all: int = 0
	var tele_all: int = 0
	var contacts_all: int = 0
	var unfinished: int = 0
	var rival_top_max: float = 0.0
	var player_out: Dictionary = {}
	for i: int in n:
		var car: ArcadeCar = scene.cars[i]
		var d: AIDriver = car.get_node_or_null("AIDriver") as AIDriver
		var stuck: int = d.stuck_count if d != null else 0
		var laps: int = int(st["laps"][i])
		if laps < cfg.laps:
			unfinished += 1
		stuck_all += stuck
		tele_all += int(st["teleports"][i])
		contacts_all += int(st["contact_events"][i])
		if i != p_idx:
			rival_top_max = maxf(rival_top_max, float(st["top"][i]))
		var row: Dictionary = {"slot": i, "is_player": i == p_idx, "skill": snappedf(d.skill, 0.001) if d != null else null,
			"laps": laps, "best_lap_s": _best(st["lap_times"][i]), "top_kmh": snappedf(float(st["top"][i]), 0.1),
			"stuck_recoveries": stuck, "teleports": int(st["teleports"][i]), "contact_events": int(st["contact_events"][i])}
		per.append(row)
	for r: Dictionary in st["results"]:
		if bool(r.get("is_player", false)):
			player_out = {"position": r["position"], "total_time_s": snappedf(float(r["total_time"]), 0.01)}
	var pl: Dictionary = per[p_idx] if p_idx >= 0 else {}
	var track: Track = scene.track
	var t100: Variant = float(st["t100"]) if float(st["t100"]) >= 0.0 else null
	var t200: Variant = float(st["t200"]) if float(st["t200"]) >= 0.0 else null
	return {"tag": tag, "track": cfg.track_scene.get_file(), "car": cfg.car_spec_path.get_file().get_basename(),
		"grid": n, "laps": cfg.laps, "timed_out": bool(st["timed_out"]),
		"all_finished": unfinished == 0 and not bool(st["timed_out"]),
		"race_time_s": snappedf(float(st["finish_time"]), 0.01),
		"track_max_speed_kmh": snappedf(track.max_speed * 3.6, 0.1) if track != null else null,
		"spec_top_kmh": _spec_top(cfg.car_spec_path.get_file().get_basename()),
		"player_position": player_out.get("position", null),
		"player_total_time_s": player_out.get("total_time_s", null),
		"player_lap_s": st["lap_times"][p_idx] if p_idx >= 0 else [],
		"player_best_lap_s": pl.get("best_lap_s", null),
		"player_zero_to_100_s": snappedf(float(t100), 0.01) if t100 != null else null,
		"player_zero_to_200_s": snappedf(float(t200), 0.01) if t200 != null else null,
		"player_top_kmh": pl.get("top_kmh", null),
		"rival_top_kmh_max": snappedf(rival_top_max, 0.1),
		"unfinished_cars": unfinished,
		"stuck_recoveries_all": stuck_all, "stuck_recoveries_player": pl.get("stuck_recoveries", 0),
		"teleports_all": tele_all, "teleports_player": pl.get("teleports", 0),
		"contact_events_all": contacts_all, "contact_events_player": pl.get("contact_events", 0),
		"contact_events_per_lap_all": snappedf(float(contacts_all) / float(maxi(cfg.laps, 1)), 0.01),
		"per_car": per}


func _one_race(tag: String, cfg: RaceConfig) -> Dictionary:
	var scene: RaceScene = (load(RACE_SCENE) as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	add_child(scene)
	await get_tree().process_frame
	var st: Dictionary = _new_state()
	_attach(scene, st)
	await _drive_to_finish(scene, st)
	var rec: Dictionary = _record(tag, scene, cfg, st)
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return rec


func _restart_block() -> Dictionary:
	var cfg: RaceConfig = _config(TRACK_SCENES["bogaz"], "noctra_tayfun", 3, MATRIX_LAPS, "restart")
	var scene: RaceScene = (load(RACE_SCENE) as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var baseline: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var runs: Array = []
	for k: int in RESTART_RUNS:
		if k > 0:
			scene.retry()
			await get_tree().process_frame
			await get_tree().process_frame
		var st: Dictionary = _new_state()
		_attach(scene, st)
		await _drive_to_finish(scene, st)
		var rec: Dictionary = _record("restart_run_%d" % (k + 1), scene, cfg, st)
		rec["nodes_after_finish"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		runs.append(rec)
	scene.queue_free()
	for _i: int in 5:
		await get_tree().process_frame
	return {"baseline_nodes_before_first_race": baseline,
		"nodes_after_scene_freed": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"runs": runs}


func _first_race_block() -> Array:
	var out: Array = []
	for skill: float in FIRST_RACE_PLAYER_SKILLS:
		var cfg: RaceConfig = EventCatalog.config_for("ortakoy_night")
		cfg.car_scene = CarCatalog.scene_path("noctra_tayfun")
		cfg.car_spec_path = CarCatalog.spec_path("noctra_tayfun")
		cfg.use_garage_paint = false
		cfg.autopilot = true
		cfg.autopilot_skill = skill
		var rec: Dictionary = await _one_race("ortakoy_night_autopilot_%.2f" % skill, cfg)
		rec["event"] = "ortakoy_night (first race, starter car, rivals from the event's rival_mix)"
		rec["rival_skills"] = Array(cfg.opponent_skills)
		out.append(rec)
	return out


func _matrix_block() -> Array:
	var out: Array = []
	for key: String in TRACK_SCENES.keys():
		if not _track_filter.is_empty() and key != _track_filter:
			continue
		for car_id: String in PLAYER_CARS:
			for opp: int in OPPONENT_COUNTS:
				var tag: String = "%s_%s_grid%d" % [key, car_id, opp + 1]
				var cfg: RaceConfig = _config(str(TRACK_SCENES[key]), car_id, opp, MATRIX_LAPS, tag)
				out.append(await _one_race(tag, cfg))
	return out


## For every career event: the rival models the game picks (same seed and class as _spawn_cars), against the starter.
func _fairness_block() -> Array:
	var out: Array = []
	var starter_top: float = _spec_top("noctra_tayfun")
	for ev: Dictionary in EventCatalog.EVENTS:
		var id: String = str(ev["id"])
		var cfg: RaceConfig = EventCatalog.config_for(id)
		var rivals: Array[Dictionary] = CarCatalog.rival_models(cfg.opponent_count, hash(cfg.event_id), cfg.rival_class)
		var picks: Array = []
		var faster: int = 0
		for r: Dictionary in rivals:
			var top: float = _spec_top(str(r["id"]))
			if top > starter_top:
				faster += 1
			picks.append({"model": str(r["id"]), "top_kmh": top})
		out.append({"event": id, "tod": cfg.time_of_day, "class_filter": cfg.rival_class,
			"opponents": cfg.opponent_count, "starter_top_kmh": starter_top,
			"rivals_faster_than_starter": faster, "rivals": picks})
	return out


## Rendered run: one 8-car race, frame deltas from grid to GO plus HITCH_LENGTH_S after GO.
func _hitch() -> Dictionary:
	var cfg: RaceConfig = _config(TRACK_SCENES["bogaz"], "noctra_tayfun", 7, MATRIX_LAPS, "hitch")
	var scene: RaceScene = (load(RACE_SCENE) as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	add_child(scene)
	var t0: int = Time.get_ticks_usec()
	var last: int = t0
	var cd_us: int = -1
	var go_us: int = -1
	var frames: Array = []
	while true:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		var dt_ms: float = float(now - last) / 1000.0
		last = now
		var state: int = int(scene.race.state) if scene.race != null else -1
		if cd_us < 0 and state == RaceManager.State.COUNTDOWN:
			cd_us = now
		if go_us < 0 and state == RaceManager.State.RACING:
			go_us = now
		frames.append([snappedf(float(now - t0) / 1000.0, 0.1), snappedf(dt_ms, 0.01), state])
		if go_us >= 0 and float(now - go_us) / 1000000.0 >= HITCH_LENGTH_S:
			break
		if float(now - t0) / 1000000.0 > HITCH_GUARD_S:
			break
	var go_ms: float = float(go_us - t0) / 1000.0 if go_us >= 0 else -1.0
	var cd_ms: float = float(cd_us - t0) / 1000.0 if cd_us >= 0 else -1.0
	var max_grid: float = 0.0
	var max_cd: float = 0.0
	var max_after_go: float = 0.0
	var worst: Array = []
	for f: Array in frames:
		var t: float = float(f[0])
		var dt: float = float(f[1])
		if go_ms < 0.0 or t < go_ms:
			if cd_ms < 0.0 or t < cd_ms:
				max_grid = maxf(max_grid, dt)
			else:
				max_cd = maxf(max_cd, dt)
		elif t - go_ms <= 5000.0:
			max_after_go = maxf(max_after_go, dt)
		if dt > 25.0:
			worst.append(f)
	scene.queue_free()
	return {"machine": MACHINE_NOTE, "mode": "hitch", "vsync_note": "rendered run, default vsync; see frames",
		"adapter": RenderingServer.get_video_adapter_name(),
		"screen_refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"track": cfg.track_scene.get_file(), "grid": 8, "car": "noctra_tayfun",
		"countdown_start_ms": snappedf(cd_ms, 0.1), "go_ms": snappedf(go_ms, 0.1),
		"max_frame_ms_grid_before_countdown": snappedf(max_grid, 0.01),
		"max_frame_ms_countdown": snappedf(max_cd, 0.01),
		"max_frame_ms_first_5s_after_go": snappedf(max_after_go, 0.01),
		"frames_over_25ms": worst, "frames": frames}
