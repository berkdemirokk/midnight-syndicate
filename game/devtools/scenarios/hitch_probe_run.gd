extends Node
## Start-hitch probe (rendered only, not a test). Same race as drive_telemetry --mode=hitch (bogaz, 8 cars, tayfun),
## recorded from the grid to GO + LENGTH seconds, with per-frame timing and an event log of what happened in each
## frame: node additions, Timer timeouts, audio players starting or stopping, light visibility or shadow toggles,
## viewport scale changes, and pipeline compile counters. Lets a spike be matched to the event in the same frame.
##
## --no-mirror: experiment only, stops every SubViewport (the planar mirror) from updating after countdown.
## Usage (under the GPU lock):
##   godot --audio-driver Dummy --resolution 1920x1080 --position 20000,0 --path game -s res://devtools/scenarios/hitch_probe.gd -- --out=<abs json> [--length=60]

const RACE_SCENE: String = "res://race/race_scene.tscn"
const TRACK_SCENE: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const GUARD_S: float = 150.0
const MACHINE_NOTE: String = "Windows 11 dev PC, NVIDIA RTX 5060 Ti 8 GB, Godot 4.7.2. Not a phone."

var _out_path: String = ""
var _no_mirror: bool = false  ## experiment: the SubViewports (planar wet-road mirror) stop updating
var _length_s: float = 60.0
var _events: Array = []  ## [t_ms, kind, detail]
var _added_this_frame: int = 0
var _removed_this_frame: int = 0
var _timers_seen: Dictionary = {}
var _audio_state: Dictionary = {}  ## NodePath -> bool playing
var _light_state: Dictionary = {}  ## NodePath -> "visible|shadow"
var _t0: int = 0
var _armed: bool = false  ## true from countdown start; event logging on


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_path = a.trim_prefix("--out=")
		elif a == "--no-mirror":
			_no_mirror = true
		elif a.begins_with("--length="):
			_length_s = a.trim_prefix("--length=").to_float()
	get_node("/root/GameState").call("open_profile", "user://hitch_probe_save.json")
	_run()


func _now_ms() -> float:
	return float(Time.get_ticks_usec() - _t0) / 1000.0


func _log(kind: String, detail: String) -> void:
	if _armed:
		_events.append([snappedf(_now_ms(), 0.1), kind, detail])


func _on_node_added(n: Node) -> void:
	if not _armed:
		return
	_added_this_frame += 1
	_log("node_added", "%s %s" % [n.get_class(), str(n.get_path())])
	if n is Timer:
		_hook_timer(n as Timer)
	if n is Light3D:
		_light_state[n.get_path()] = _light_key(n as Light3D)


func _on_node_removed(n: Node) -> void:
	if _armed:
		_removed_this_frame += 1
		_log("node_removed", "%s %s" % [n.get_class(), str(n.get_path())])


func _hook_timer(t: Timer) -> void:
	if _timers_seen.has(t):
		return
	_timers_seen[t] = true
	t.timeout.connect(func() -> void: _log("timer", str(t.get_path()) + " wait=" + str(t.wait_time)))


func _light_key(l: Light3D) -> String:
	return "%s|%s" % [str(l.visible), str(l.shadow_enabled)]


func _poll_events() -> void:
	for cls: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for n: Node in get_tree().root.find_children("*", cls, true, false):
			var p: bool = bool(n.get("playing"))
			var key: NodePath = n.get_path()
			if _audio_state.has(key) and bool(_audio_state[key]) != p:
				_log("audio", ("start " if p else "stop ") + str(key))
			_audio_state[key] = p
	for n: Node in get_tree().root.find_children("*", "Light3D", true, false):
		var l: Light3D = n as Light3D
		var k: String = _light_key(l)
		var key2: NodePath = l.get_path()
		if _light_state.has(key2) and str(_light_state[key2]) != k:
			_log("light", "%s %s -> %s" % [str(key2), str(_light_state[key2]), k])
		_light_state[key2] = k


func _run() -> void:
	var cfg: RaceConfig = RaceConfig.new()
	cfg.event_id = "hitch_probe"
	cfg.track_scene = TRACK_SCENE
	cfg.car_scene = CarCatalog.scene_path("noctra_tayfun")
	cfg.car_spec_path = CarCatalog.spec_path("noctra_tayfun")
	cfg.laps = 2
	cfg.opponent_count = 7
	cfg.rival_mix = false
	cfg.traffic_enabled = false
	cfg.autopilot = true
	cfg.autopilot_skill = 0.97
	cfg.use_garage_paint = false
	cfg.time_of_day = "night"
	var scene: RaceScene = (load(RACE_SCENE) as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	add_child(scene)
	_t0 = Time.get_ticks_usec()
	var frames: Array = []
	var cd_ms: float = -1.0
	var go_ms: float = -1.0
	var last: int = Time.get_ticks_usec()
	var prev_draws: int = 0
	while true:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		var dt_ms: float = float(now - last) / 1000.0
		last = now
		var state: int = int(scene.race.state) if scene.race != null else -1
		if not _armed and state == RaceManager.State.COUNTDOWN:
			_armed = true
			cd_ms = _now_ms()
			_log("phase", "countdown")
			for n: Node in get_tree().root.find_children("*", "Timer", true, false):
				_hook_timer(n as Timer)
			for n: Node in get_tree().root.find_children("*", "Light3D", true, false):
				_light_state[(n as Light3D).get_path()] = _light_key(n as Light3D)
		if _armed:
			_poll_events()
			if _no_mirror:
				for vp_node: Node in get_tree().root.find_children("*", "SubViewport", true, false):
					(vp_node as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
		if go_ms < 0.0 and state == RaceManager.State.RACING:
			go_ms = _now_ms()
			_log("phase", "GO")
			scene.race.lap_completed.connect(func(car: ArcadeCar, lap: int, lap_time: float) -> void: _log("lap", "car=%s lap=%d time=%.2f" % [car.name, lap, lap_time]))
			scene.race.race_finished.connect(func(_r: Array) -> void: _log("race", "finished"))
		var spec: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION))
		var surf: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE))
		var draw: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW))
		var vp: Viewport = get_viewport()
		frames.append([snappedf(_now_ms(), 0.1), snappedf(dt_ms, 0.01),
			snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
			snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			spec, surf, draw, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			snappedf(vp.scaling_3d_scale, 0.001), _added_this_frame, state,
			_player_xz(scene)])
		if dt_ms > 25.0 and _armed and scene.player != null:
			_log_nearby(scene, dt_ms)
		_added_this_frame = 0
		_removed_this_frame = 0
		if go_ms >= 0.0 and _now_ms() - go_ms >= _length_s * 1000.0:
			break
		if _now_ms() > GUARD_S * 1000.0:
			break
	_write(cd_ms, go_ms, frames, scene)
	get_tree().quit(0)


## Spike frames only: the nearest visual nodes to the car. Its cost lands in the NEXT measured frame (dt is taken at
## the top of the loop), as does _poll_events() in every frame; treat frames right after a scanned spike as probe echo.
func _log_nearby(scene: RaceScene, dt_ms: float) -> void:
	var at: Vector3 = scene.player.global_position
	var own: String = str(scene.player.get_path())
	var near: Array = []
	var visible_n: int = 0
	for n: Node in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		var v: VisualInstance3D = n as VisualInstance3D
		if not v.is_visible_in_tree():
			continue
		visible_n += 1
		var p: String = str(v.get_path())
		if p.begins_with(own):
			continue
		near.append([snappedf(v.global_position.distance_to(at), 0.1), p.right(140), v.get_class()])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	_events.append([snappedf(_now_ms(), 0.1), "spike_nearby", "dt=%.1f visible=%d" % [dt_ms, visible_n], near.slice(0, 14)])


func _player_xz(scene: RaceScene) -> Array:
	if scene.player == null:
		return []
	var p: Vector3 = scene.player.global_position
	return [snappedf(p.x, 0.1), snappedf(p.z, 0.1), snappedf(scene.player.speed_kmh, 0.1)]


func _write(cd_ms: float, go_ms: float, frames: Array, scene: RaceScene) -> void:
	var data: Dictionary = {"machine": MACHINE_NOTE, "mode": "hitch_probe", "length_s": _length_s,
"adapter": RenderingServer.get_video_adapter_name(),
		"no_mirror": _no_mirror, "countdown_ms": snappedf(cd_ms, 0.1), "go_ms": snappedf(go_ms, 0.1),
		"frame_fields": ["t_ms", "dt_ms", "proc_ms", "phys_ms", "draws", "primitives", "spec_cum", "surf_cum",
			"draw_cum", "nodes", "scale", "nodes_added", "race_state", "player_xz_speed"],
		"frames": frames, "events": _events}
	if _out_path.is_empty():
		push_error("hitch_probe: --out=<absolute path> is required")
		return
	DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
	var f: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	print("hitch_probe: wrote %s" % _out_path)
