extends "res://devtools/capture_scenario.gd"
## Draw-call and primitive attribution on City 01. Real race (same config as race_city/race_replay), simulation
## frozen with Engine.time_scale = 0 at each moment so every row measures the same frame, then each category is
## hidden in turn (restored after) and re-measured with PerfProbe (peak and min over PROBE_FRAMES).
## Moments: grid_intro (countdown camera mid-move), grid (fixed grid camera), pack (~10 s after GO, rivals in view),
## results, replay_orbit (finish orbit of the replay). Pick a subset with --moments=pack,results.
## --track=city|bogaz (default city). Output: evidence/screens/draw_breakdown/<preset>_<moment>.json, one baseline shot per moment, rows on stdout.

const SCENE: String = "res://race/race_scene.tscn"
const CITY_SCENE: String = "res://world/city_01/city_01.tscn"
const TRACKS: Dictionary = {
	"city": "res://world/city_01/city_01.tscn",
	"bogaz": "res://world/istanbul_bogaz/istanbul_bogaz.tscn",
}
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const OPPONENTS: int = 5
const LAPS: int = 1
const SETTLE_FRAMES: int = 20
const PROBE_FRAMES: int = 60
const WAIT_MAX_S: float = 240.0
const RACING_S: float = 10.0
const PACK_MIN_RIVALS: int = 2
const PACK_RANGE_M: float = 80.0
const GRID_BACK_M: float = 15.0
const GRID_SIDE_M: float = 9.0
const GRID_UP_M: float = 7.0
const GRID_FOV_DEG: float = 60.0
const OUT_DIR_REL: String = "../evidence/screens/draw_breakdown/"
const ALL_MOMENTS: PackedStringArray = ["grid_intro", "grid", "pack", "results", "replay_orbit"]

var _scene: RaceScene
var _probe: PerfProbe = PerfProbe.new()
var _moments: PackedStringArray = ALL_MOMENTS
var _track_key: String = "city"
var _tick_three: bool = false
var _go_ms: int = 0
var _rows: Array[Dictionary] = []


func run() -> void:
	_parse_moments()
	if not TRACKS.has(_track_key):
		cap.fail("draw_breakdown: unknown --track=" + _track_key)
		return
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = LAPS
	cfg.opponent_count = OPPONENTS
	cfg.track_scene = TRACKS[_track_key]
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	_scene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	_scene.config = cfg
	tree.root.add_child(_scene)
	await cap.wait_frames(SETTLE_FRAMES)
	if _scene.dev_track_used or _scene.dev_car_used:
		cap.fail("dev track or dev car in use: not the real race")
		return
	tree.auto_accept_quit = false
	_scene.race.countdown_tick.connect(func(s: int) -> void: _tick_three = _tick_three or s == 3)
	_scene.race.race_started.connect(func() -> void: _go_ms = Time.get_ticks_msec())
	_print_env()
	# countdown -> intro mid-move (the countdown camera is the chase camera's intro)
	var t0: int = Time.get_ticks_msec()
	while not _tick_three and _since(t0) < WAIT_MAX_S:
		await cap.wait_frames(1)
	while _scene.camera.intro_active() and _scene.camera.intro_progress() < 0.5 and _since(t0) < WAIT_MAX_S:
		await cap.wait_frames(1)
	if "grid_intro" in _moments:
		await _moment("grid_intro")
	# fixed grid camera as in race_city
	var gcam: Camera3D = _make_grid_cam()
	if "grid" in _moments:
		await _moment("grid")
	gcam.queue_free()
	_scene.camera.make_current()
	if _need_race():
		t0 = Time.get_ticks_msec()
		while _go_ms == 0 and _since(t0) < WAIT_MAX_S:
			await cap.wait_frames(1)
		var since_go: float = (Time.get_ticks_msec() - _go_ms) / 1000.0
		if since_go < RACING_S:
			await cap.wait_seconds(RACING_S - since_go)
		t0 = Time.get_ticks_msec()
		while _rivals_in_view() < PACK_MIN_RIVALS and _since(t0) < 30.0:
			await cap.wait_frames(1)
		print("draw_breakdown: pack with %d rivals in view" % _rivals_in_view())
		if "pack" in _moments:
			await _moment("pack")
	if "results" in _moments or "replay_orbit" in _moments:
		t0 = Time.get_ticks_msec()
		while not _scene.results_screen.visible and _since(t0) < WAIT_MAX_S:
			await cap.wait_frames(1)
		if not _scene.results_screen.visible:
			cap.fail("results screen never appeared")
			return
		await cap.wait_seconds(2.0)
		if "results" in _moments:
			await _moment("results")
		if "replay_orbit" in _moments:
			await _replay_orbit()


func _need_race() -> bool:
	return "pack" in _moments or "results" in _moments or "replay_orbit" in _moments


func _since(t0_ms: int) -> float:
	return (Time.get_ticks_msec() - t0_ms) / 1000.0


func _parse_moments() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			_track_key = arg.trim_prefix("--track=")
		if arg.begins_with("--moments="):
			_moments = arg.trim_prefix("--moments=").split(",")


func _preset() -> String:
	## City keeps the old file names; other tracks are prefixed (e.g. bogaz_high_pack.json).
	return Settings.get_preset_id() if _track_key == "city" else _track_key + "_" + Settings.get_preset_id()


func _replay_orbit() -> void:
	_scene.results_screen._replay_btn.pressed.emit()
	await cap.wait_frames(2)
	var rp: ReplayPlayer = _scene.replay
	if rp == null:
		print("draw_breakdown: replay_orbit SKIPPED: REPLAY did not start")
		return
	rp.seek(maxf(rp.duration_s() - 2.5, 0.0))
	await cap.wait_seconds(0.5)
	var d: ReplayDirector = rp.director()
	var t0: int = Time.get_ticks_msec()
	while d.kind != ReplayDirector.Kind.ORBIT and _since(t0) < 2.0 and rp.time_s() < rp.duration_s() - 0.3:
		await cap.wait_frames(1)
	if d.kind != ReplayDirector.Kind.ORBIT:
		print("draw_breakdown: replay_orbit SKIPPED: director not in ORBIT (kind %d, t=%.1f/%.1f)" % [d.kind, rp.time_s(), rp.duration_s()])
		return
	await _moment("replay_orbit")
	rp.exit_replay()


## Freezes the sim, prints the tree summary, measures the baseline then every category, writes the JSON.
func _moment(moment: String) -> void:
	Engine.time_scale = 0.0
	await cap.wait_frames(5)
	await cap.shot("%s_%s" % [_preset(), moment])
	print("draw_breakdown: ===== %s / %s =====" % [_preset(), moment])
	_print_tree_summary()
	var base: Dictionary = await _probe.measure(tree, PROBE_FRAMES)
	var rows: Array[Dictionary] = [_row("BASELINE", base, base)]
	print(_fmt(rows[0]))
	for c: Array in _categories():
		var label: String = c[0]
		var undo: Callable = (c[1] as Callable).call()
		if not undo.is_valid():
			continue
		var r: Dictionary = await _probe.measure(tree, PROBE_FRAMES)
		undo.call()
		var row: Dictionary = _row(label, base, r)
		rows.append(row)
		print(_fmt(row))
	# 2D-only remainder: the whole 3D world switched off. Shows what the canvas (HUD, UI) alone costs.
	tree.root.disable_3d = true
	var r2d: Dictionary = await _probe.measure(tree, PROBE_FRAMES)
	tree.root.disable_3d = false
	var row2d: Dictionary = _row("[2D ONLY] viewport disable_3d (absolute draws remaining)", base, r2d)
	rows.append(row2d)
	print(_fmt(row2d))
	_write_json(moment, base, rows)
	Engine.time_scale = 1.0
	await cap.wait_frames(2)


func _row(label: String, base: Dictionary, r: Dictionary) -> Dictionary:
	return {
		"category": label,
		"draws_peak": int(r["draw_calls"]), "draws_min": int(r["draw_calls_min"]), "prims_peak": int(r["primitives"]),
		"d_draws_peak": int(base["draw_calls"]) - int(r["draw_calls"]),
		"d_draws_min": int(base["draw_calls_min"]) - int(r["draw_calls_min"]),
		"d_prims": int(base["primitives"]) - int(r["primitives"]),
		"objects": int(r["objects"]),
	}


func _fmt(row: Dictionary) -> String:
	return "draw_breakdown: ROW | %-58s | peak %4d (d %4d) | min %4d (d %4d) | prims %7d (d %7d)" % [
		row["category"], row["draws_peak"], row["d_draws_peak"], row["draws_min"], row["d_draws_min"], row["prims_peak"], row["d_prims"]]


func _write_json(moment: String, base: Dictionary, rows: Array[Dictionary]) -> void:
	var dir: String = ProjectSettings.globalize_path("res://").path_join(OUT_DIR_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(dir.path_join("%s_%s.json" % [_preset(), moment]), FileAccess.WRITE)
	if f == null:
		cap.fail("cannot write json")
		return
	f.store_string(JSON.stringify({"preset": _preset(), "moment": moment, "adapter": base["adapter"], "viewport": base["viewport_size"], "rows": rows}, "  "))
	f.close()


## ---- categories --------------------------------------------------------------------------------------------------

func _categories() -> Array[Array]:
	var track: Node = _scene.track
	var geo: Node = track.get_node_or_null("Geometry")
	var cars: Array[Node] = []
	var rivals: Array[Node] = []
	for c: ArcadeCar in _scene.cars:
		cars.append(c)
		if c != _scene.player:
			rivals.append(c)
	var out: Array[Array] = []
	out.append(["cars: all rivals (not player)", _hider(rivals)])
	out.append(["cars: player", _hider([_scene.player])])
	for lod: String in ["LOD0", "LOD1", "LOD2"]:
		out.append(["car LOD %s (all cars incl. player)" % lod, _hider(_named_under(cars, lod))])
	out.append(["car FX (CarFx particles/smoke/sparks/flame)", _hider(_with_class(cars, "CarFx"))])
	out.append(["car lights (headlights etc, all cars)", _hider(_lights_under(cars))])
	if geo != null:
		out.append(["city: road + start grid", _hider(_children_named(geo, ["Road", "FallFloor"]) + _nodes([track.get_node_or_null("StartGrid")]))])
		var first: Node = geo.get_node_or_null("FirstRow")
		out.append(["city: ALL building geometry (FirstRow+SecondRow)", _hider(_nodes([first, geo.get_node_or_null("SecondRow")]))])
		out.append(["city: FirstRow buildings LOD0", _hider(_named_under(_nodes([first]), "LOD0"))])
		out.append(["city: FirstRow buildings LOD1", _hider(_named_under(_nodes([first]), "LOD1"))])
		out.append(["city: FirstRow buildings LOD2", _hider(_named_under(_nodes([first]), "LOD2"))])
		out.append(["city: SecondRow skyline/impostor MultiMeshes", _hider(_nodes([geo.get_node_or_null("SecondRow")]))])
		out.append(["props: layout prop MultiMeshes (Props)", _hider(_nodes([geo.get_node_or_null("Props")]))])
		out.append(["dressing props (Dressing)", _hider(_nodes([geo.get_node_or_null("Dressing")]))])
		out.append(["parked cars (ParkedCars)", _hider(_nodes([geo.get_node_or_null("ParkedCars")]))])
		out.append(["signs/neon (name contains sign|neon|billboard; overlaps props/dressing)", _hider(_by_name_words(geo, ["sign", "neon", "billboard"]))])
	var lighting: Node = track.get_node_or_null("Lighting")
	out.append(["lights: city (Lighting, non-directional)", _hider(_city_lights(lighting))])
	out.append(["lights: ALL Light3D in scene (incl. moon, cars, cam fill/rim)", _hider(_all_lights())])
	out.append(["lights: camera fill/rim only", _hider(_lights_under([_scene.camera]))])
	out.append(["lights: all shadows off (shadow_enabled=false)", _shadows_off()])
	out.append(["lights: moon (directional) hidden", _hider(_directional())])
	out.append(["reflection probes", _hider(_nodes([lighting.get_node_or_null("ReflectionProbes") if lighting else null]))])
	out.append(["rain (RainFx)", _hider(_with_class([_scene], "RainFx"))])
	out.append(["speed lines (SpeedLines)", _hider(_nodes([_scene._speed_lines]))])
	out.append(["HUD (RaceHUD CanvasLayer)", _hider(_nodes([_scene.hud]))])
	out.append(["overlay (pause + results CanvasLayer)", _hider(_nodes([_scene._overlay]))])
	out.append(["ALL CanvasLayers + replay UI (2D off)", _hider(_all_canvas_layers())])
	out.append(["planar reflection: disabled (mirror pass off)", _reflection_off()])
	out.append(["env: glow off", _env_set("glow_enabled", false)])
	out.append(["env: sky off (background -> colour)", _env_set("background_mode", Environment.BG_COLOR)])
	out.append(["env: fog off", _env_set("fog_enabled", false)])
	out.append(["env: volumetric fog off", _env_set("volumetric_fog_enabled", false)])
	return out


## Returns a Callable that hides the given nodes and returns the undo Callable (invalid when there is nothing to hide).
func _hider(nodes: Array) -> Callable:
	return func() -> Callable:
		var saved: Array = []
		for n: Variant in nodes:
			if is_instance_valid(n) and "visible" in n and n.visible:
				saved.append(n)
		if saved.is_empty():
			return Callable()
		for n: Variant in saved:
			n.visible = false
		return func() -> void:
			for n: Variant in saved:
				if is_instance_valid(n):
					n.visible = true


func _shadows_off() -> Callable:
	return func() -> Callable:
		var saved: Array = []
		for l: Node in _all_lights():
			if (l as Light3D).shadow_enabled:
				saved.append(l)
		if saved.is_empty():
			return Callable()
		for l: Variant in saved:
			l.shadow_enabled = false
		return func() -> void:
			for l: Variant in saved:
				if is_instance_valid(l):
					l.shadow_enabled = true


func _reflection_off() -> Callable:
	return func() -> Callable:
		var rf: PlanarReflection = _scene._reflection
		if rf == null or not rf.is_enabled():
			return Callable()
		rf.set_enabled(false)
		return func() -> void: rf.set_enabled(true)


func _env_set(prop: String, value: Variant) -> Callable:
	return func() -> Callable:
		var env: Environment = _world_env()
		if env == null or env.get(prop) == value:
			return Callable()
		var prev: Variant = env.get(prop)
		env.set(prop, value)
		return func() -> void: env.set(prop, prev)


func _world_env() -> Environment:
	var we: WorldEnvironment = _first_of_type(_scene, "WorldEnvironment") as WorldEnvironment
	return we.environment if we != null else null


## ---- node lookups -----------------------------------------------------------------------------------------------

func _walk(n: Node, out: Array[Node]) -> void:
	out.append(n)
	for c: Node in n.get_children():
		_walk(c, out)


func _all_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	_walk(root, out)
	return out


func _nodes(list: Array) -> Array:
	var out: Array = []
	for n: Variant in list:
		if n != null and is_instance_valid(n):
			out.append(n)
	return out


func _children_named(parent: Node, names: Array) -> Array:
	var out: Array = []
	for n: String in names:
		var c: Node = parent.get_node_or_null(n)
		if c != null:
			out.append(c)
	return out


func _named_under(roots: Array, node_name: String) -> Array:
	var out: Array = []
	for r: Variant in roots:
		if r == null:
			continue
		for n: Node in _all_nodes(r):
			if String(n.name) == node_name:
				out.append(n)
	return out


func _with_class(roots: Array, global_class: String) -> Array:
	var out: Array = []
	for r: Variant in roots:
		for n: Node in _all_nodes(r):
			var s: Script = n.get_script() as Script
			if s != null and s.get_global_name() == global_class:
				out.append(n)
	return out


func _first_of_type(root: Node, type_name: String) -> Node:
	for n: Node in _all_nodes(root):
		if n.is_class(type_name):
			return n
	return null


func _by_name_words(root: Node, words: Array) -> Array:
	var out: Array = []
	for n: Node in _all_nodes(root):
		if not (n is MeshInstance3D or n is MultiMeshInstance3D):
			continue
		var lower: String = String(n.name).to_lower()
		for w: String in words:
			if lower.contains(w):
				out.append(n)
				break
	return out


func _all_lights() -> Array:
	var out: Array = []
	for n: Node in _all_nodes(tree.root):
		if n is Light3D:
			out.append(n)
	return out


func _lights_under(roots: Array) -> Array:
	var out: Array = []
	for r: Variant in roots:
		for n: Node in _all_nodes(r):
			if n is Light3D:
				out.append(n)
	return out


func _city_lights(lighting: Node) -> Array:
	var out: Array = []
	if lighting == null:
		return out
	for n: Node in _all_nodes(lighting):
		if n is Light3D and not (n is DirectionalLight3D):
			out.append(n)
	return out


func _directional() -> Array:
	var out: Array = []
	for n: Node in _all_nodes(tree.root):
		if n is DirectionalLight3D:
			out.append(n)
	return out


func _all_canvas_layers() -> Array:
	var out: Array = []
	for n: Node in _all_nodes(tree.root):
		if n is CanvasLayer and not (n.get_parent() is CanvasLayer):
			out.append(n)
	return out


## ---- diagnostics ------------------------------------------------------------------------------------------------

func _print_env() -> void:
	var env: Environment = _world_env()
	if env == null:
		print("draw_breakdown: no WorldEnvironment")
		return
	print("draw_breakdown: env bg=%d glow=%s fog=%s volfog=%s ssao=%s ssil=%s ssr=%s sdfgi=%s adjust=%s" % [
		env.background_mode, env.glow_enabled, env.fog_enabled, env.volumetric_fog_enabled, env.ssao_enabled,
		env.ssil_enabled, env.ssr_enabled, env.sdfgi_enabled, env.adjustment_enabled])


func _group_stats(label: String, nodes: Array) -> void:
	var total: int = 0
	var meshes: int = 0
	var mmis: int = 0
	var instances: int = 0
	var lights: int = 0
	for r: Variant in nodes:
		if r == null:
			continue
		for n: Node in _all_nodes(r):
			total += 1
			if n is MeshInstance3D:
				meshes += 1
			elif n is MultiMeshInstance3D:
				mmis += 1
				var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
				if mm != null:
					instances += mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			elif n is Light3D:
				lights += 1
	print("draw_breakdown:   group %-34s nodes=%5d MeshInstance3D=%4d MultiMeshInstance3D=%4d (instances %6d) Light3D=%3d" % [label, total, meshes, mmis, instances, lights])


func _print_tree_summary() -> void:
	var track: Node = _scene.track
	var geo: Node = track.get_node_or_null("Geometry")
	print("draw_breakdown: tree summary (counts, not draws; draws are the deltas below)")
	if geo != null:
		for c: Node in geo.get_children():
			_group_stats("Geometry/" + String(c.name), [c])
	for c: Node in track.get_children():
		if String(c.name) != "Geometry":
			_group_stats("Track/" + String(c.name), [c])
	_group_stats("cars (%d)" % _scene.cars.size(), _scene.cars)
	for c: Node in _scene._world.get_children():
		if c != track and not (c is ArcadeCar):
			_group_stats("World/" + String(c.name), [c])
	for n: Node in _all_canvas_layers():
		_group_stats("CanvasLayer " + String(n.name), [n])


func _make_grid_cam() -> Camera3D:
	var c: Vector3 = Vector3.ZERO
	for car: ArcadeCar in _scene.cars:
		c += car.global_position
	c /= float(_scene.cars.size())
	var fwd: Vector3 = _scene.track.get_tangent_at(_scene.track.get_progress(c))
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side: Vector3 = fwd.cross(Vector3.UP).normalized()
	var cam := Camera3D.new()
	cam.fov = GRID_FOV_DEG
	tree.root.add_child(cam)
	cam.global_position = c - fwd * GRID_BACK_M + side * GRID_SIDE_M + Vector3.UP * GRID_UP_M
	cam.look_at(c + fwd * 8.0 + Vector3.UP * 1.0)
	cam.current = true
	return cam


func _rivals_in_view() -> int:
	var n: int = 0
	for c: ArcadeCar in _scene.cars:
		if c == _scene.player:
			continue
		if c.global_position.distance_to(_scene.player.global_position) <= PACK_RANGE_M and _scene.camera.is_position_in_frustum(c.global_position):
			n += 1
	return n
