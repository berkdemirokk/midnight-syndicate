extends Node
## Long-session soak measurement. Not a test, no gameplay change: runs the real race scene (race/race_scene.tscn)
## back to back in ONE process, autopilot player, istanbul_bogaz, grid 6, 2 laps, night.
##   --mode=sim    headless (60 Hz fixed, no render): N races, memory and object counts per race.
##   --mode=render rendered, under the GPU lock: repeat races for --minutes, frame time per minute and memory per minute.
## Headless:
##   godot --headless --audio-driver Dummy --fixed-fps 60 --path game res://devtools/soak_boot.tscn -- --mode=sim --races=10 --out=<abs json>
## Rendered (preset high, real frame timing, no --headless, no --fixed-fps):
##   godot --audio-driver Dummy --resolution 1920x1080 --position 20000,0 --path game res://devtools/soak_boot.tscn -- --mode=render --minutes=16 --out=<abs json>

const RACE_SCENE: String = "res://race/race_scene.tscn"
const TRACK: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const SCRATCH_SAVE: String = "user://soak_save.json"
const CAR_ID: String = "noctra_tayfun"
const OPPONENTS: int = 5  ## grid of 6 (the player takes the last slot)
const LAPS: int = 2
const SETTLE_FRAMES: int = 10
const TEARDOWN_FRAMES: int = 30
const MAX_TICKS: int = 54000  ## 900 s of simulated race time
const SLOW_MS: float = 33.0
const BYTES_PER_MB: float = 1048576.0
const RENDER_ABORT_GRACE_S: float = 150.0  ## a race still running this long after the soak window is cut
const MACHINE_NOTE: String = "Windows 11 dev PC, NVIDIA RTX 5060 Ti 8 GB, Godot 4.7.2. Desktop numbers, not a phone."

var _mode: String = "sim"
var _races: int = 10
var _minutes: float = 16.0
var _out: String = ""
var _render_on: bool = false
var _t0_ms: float = 0.0
var _last_minute: int = -1
var _frame_ms := PackedFloat64Array()
var _frame_minute := PackedInt32Array()
var _minute_mem: Array = []


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			_mode = a.trim_prefix("--mode=")
		elif a.begins_with("--races="):
			_races = int(a.trim_prefix("--races="))
		elif a.begins_with("--minutes="):
			_minutes = float(a.trim_prefix("--minutes="))
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	if _out.is_empty():
		push_error("soak: --out=<absolute path> is required")
		get_tree().quit(1)
		return
	_run()


func _run() -> void:
	_clean_scratch_save()
	var gs: Node = get_node("/root/GameState")
	gs.call("open_profile", SCRATCH_SAVE)
	var data: Dictionary = {"mode": _mode, "machine": MACHINE_NOTE, "cpu": OS.get_processor_name(),
		"godot": Engine.get_version_info()["string"], "car": CAR_ID, "track": TRACK.get_file(), "grid": OPPONENTS + 1,
		"laps": LAPS, "time_of_day": "night"}
	if _mode == "render":
		var st: Node = get_node("/root/Settings")
		st.set("autosave", false)
		st.call("set_preset", "high")
		st.call("attach_viewport", get_tree().root)
		data["preset"] = "high"
		data["adapter"] = RenderingServer.get_video_adapter_name()
		data["renderer"] = RenderingServer.get_current_rendering_method()
		data["screen_refresh_hz"] = DisplayServer.screen_get_refresh_rate()
		data["run_minutes_target"] = _minutes
		data["vsync_note"] = "frame cap is project run/max_fps=60 (project.godot), not vsync; vsync left at project default; frame times are real frame deltas"
		data.merge(await _render_soak())
	else:
		data["races"] = await _sim_soak()
		data["flags"] = _flags(data["races"])
	_write(data)
	get_tree().quit(0)


func _clean_scratch_save() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(SCRATCH_SAVE + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SAVE + suffix))


func _write(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var f: FileAccess = FileAccess.open(_out, FileAccess.WRITE)
	if f == null:
		push_error("soak: cannot write %s" % _out)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("soak: wrote %s" % _out)


func _config(tag: String) -> RaceConfig:
	var c := RaceConfig.new()
	c.event_id = "soak_" + tag
	c.track_scene = TRACK
	c.car_scene = CarCatalog.scene_path(CAR_ID)
	c.car_spec_path = CarCatalog.spec_path(CAR_ID)
	c.laps = LAPS
	c.opponent_count = OPPONENTS
	c.rival_mix = false
	c.traffic_enabled = false
	c.autopilot = true
	c.autopilot_skill = 0.97
	c.use_garage_paint = false
	c.time_of_day = "night"
	return c


## Memory and object counters right now. Video memory reads 0 when the renderer is absent (headless).
func _mem() -> Dictionary:
	return {"static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / BYTES_PER_MB, 0.01),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / BYTES_PER_MB, 0.01)}


## One full race in the real scene. Stops early at abort_ms (wall clock) and records it as timed out.
func _race(tag: String, cfg: RaceConfig, abort_ms: float) -> Dictionary:
	var before: Dictionary = _mem()
	var scene: RaceScene = (load(RACE_SCENE) as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	add_child(scene)
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	var st: Dictionary = {"done": false, "results": [], "ticks": 0}
	scene.race.race_finished.connect(func(results: Array[Dictionary]) -> void:
		st["done"] = true
		st["results"] = results)
	while not bool(st["done"]) and int(st["ticks"]) < MAX_TICKS and float(Time.get_ticks_msec()) < abort_ms:
		await get_tree().physics_frame
		st["ticks"] = int(st["ticks"]) + 1
	var player_pos: Variant = null
	for r: Dictionary in st["results"]:
		if bool(r.get("is_player", false)):
			player_pos = r["position"]
	var race_time: float = float(scene.race.race_time) if scene.race != null else -1.0
	var at_finish: Dictionary = _mem()
	scene.queue_free()
	for i: int in TEARDOWN_FRAMES:
		await get_tree().process_frame
	var after_free: Dictionary = _mem()
	return {"tag": tag, "timed_out": not bool(st["done"]), "ticks": int(st["ticks"]),
		"race_time_s": snappedf(race_time, 0.01), "player_position": player_pos,
		"before": before, "at_finish": at_finish, "after_free": after_free}


func _sim_soak() -> Array:
	var out: Array = []
	for k: int in _races:
		var tag: String = "sim_%02d" % (k + 1)
		out.append(await _race(tag, _config(tag), INF))
		print("soak: %s done, objects %d nodes %d" % [tag, out[-1]["after_free"]["objects"], out[-1]["after_free"]["nodes"]])
	return out


func _render_soak() -> Dictionary:
	_t0_ms = float(Time.get_ticks_msec())
	_render_on = true
	var run_ms: float = _minutes * 60000.0
	var races: Array = []
	var k: int = 0
	while float(Time.get_ticks_msec()) - _t0_ms < run_ms:
		k += 1
		var tag: String = "render_%02d" % k
		var abort_ms: float = _t0_ms + run_ms + RENDER_ABORT_GRACE_S * 1000.0
		races.append(await _race(tag, _config(tag), abort_ms))
		print("soak: %s done after %.0f s" % [tag, (float(Time.get_ticks_msec()) - _t0_ms) / 1000.0])
	_render_on = false
	var wall_s: float = (float(Time.get_ticks_msec()) - _t0_ms) / 1000.0
	return {"wall_seconds": snappedf(wall_s, 0.1), "frames_total": _frame_ms.size(),
		"per_minute": _per_minute(), "minute_memory": _minute_mem, "races": races}


## Frame deltas collected in _process while the render soak runs.
func _process(delta: float) -> void:
	if not _render_on:
		return
	var elapsed_ms: float = float(Time.get_ticks_msec()) - _t0_ms
	var minute: int = int(elapsed_ms / 60000.0)
	_frame_ms.append(delta * 1000.0)
	_frame_minute.append(minute)
	if minute > _last_minute:
		_last_minute = minute
		var snap: Dictionary = _mem()
		snap["minute"] = minute
		_minute_mem.append(snap)


## Frames arrive in minute order, so each minute is one contiguous slice of _frame_ms. (Packed arrays are value
## types: appending through a dictionary entry does not update the stored array, so the buckets stayed empty.)
func _per_minute() -> Array:
	var out: Array = []
	var n: int = _frame_ms.size()
	var start: int = 0
	for i: int in range(1, n + 1):
		if i == n or _frame_minute[i] != _frame_minute[start]:
			out.append(_minute_stats(_frame_minute[start], _frame_ms.slice(start, i)))
			start = i
	return out


func _minute_stats(minute: int, arr: PackedFloat64Array) -> Dictionary:
	var sorted: PackedFloat64Array = arr.duplicate()
	sorted.sort()
	var slow: int = 0
	for v: float in arr:
		if v > SLOW_MS:
			slow += 1
	return {"minute": minute, "frames": arr.size(), "frame_ms_p50": _pct(sorted, 0.50),
		"frame_ms_p95": _pct(sorted, 0.95), "frame_ms_p99": _pct(sorted, 0.99),
		"frame_ms_max": snappedf(sorted[sorted.size() - 1], 0.01), "frames_over_33ms": slow}

func _pct(sorted: PackedFloat64Array, p: float) -> float:
	if sorted.is_empty():
		return -1.0
	var idx: int = clampi(int(ceil(p * sorted.size())) - 1, 0, sorted.size() - 1)
	return snappedf(sorted[idx], 0.01)


## Monotonic growth check over the per-race series (after the scene is freed). Flags a series that never falls and ends higher.
func _flags(races: Array) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["static_mb", "objects", "nodes", "orphan_nodes", "resources"]:
		var series: Array = []
		for r: Dictionary in races:
			series.append(float(r["after_free"][key]))
		var mono: bool = true
		for i: int in range(1, series.size()):
			if series[i] < series[i - 1]:
				mono = false
		var growth: float = series[-1] - series[0] if not series.is_empty() else 0.0
		out[key] = {"first": series[0] if not series.is_empty() else null, "last": series[-1] if not series.is_empty() else null,
			"growth": snappedf(growth, 0.01), "non_decreasing": mono, "flag_monotonic_growth": mono and growth > 0.0}
	return out

