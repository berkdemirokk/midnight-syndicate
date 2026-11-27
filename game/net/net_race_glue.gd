class_name NetRaceGlue
extends Node
## Client side of an online race. Attached to the race scene only when RaceConfig.net_hold_grid is set.
## Places the local car on its server grid slot, starts the shared countdown on the server start message,
## sends the local car state at SNAP_HZ once the race is green, draws the remote cars from snapshots that are
## INTERP_DELAY_S behind, and shows the results the server computed. Remote cars are frozen visuals (no AI).

const SAMPLES_MAX: int = 32
const MENU_SCENE: String = "res://ui/menus/main_menu.tscn"

var _scene: RaceScene = null
var _session: NetSession = null
var _started: bool = false
var _done: bool = false
var _send_t: float = 0.0
var _seq: int = 0
var _cars: Dictionary = {}  ## pid -> ArcadeCar (visual only)
var _samples: Dictionary = {}  ## pid -> Array of [time_s: float, xf: Transform3D]
var _last_origin: Vector3 = Vector3.ZERO
var _has_last: bool = false


## Creates the glue under world and binds it to the scene. Safe to call when no online session is running.
static func attach(scene: RaceScene, world: Node3D) -> NetRaceGlue:
	var g := NetRaceGlue.new()
	g.name = "NetRaceGlue"
	world.add_child(g)
	g._bind(scene)
	return g


func _bind(scene: RaceScene) -> void:
	_scene = scene
	_session = NetSession.get_or_create(get_tree())
	if _session.role != NetSession.ROLE_CLIENT:
		return
	_session.snapshot_received.connect(_on_snapshot)
	_session.peer_left.connect(_on_peer_left)
	_session.results_received.connect(_on_results)
	_session.connection_lost.connect(_on_lost)
	_session.race_starting.connect(_on_start)
	if not _session.race_info.is_empty():
		_on_start(_session.race_info)


func _on_start(info: Dictionary) -> void:
	if _started or _scene == null or _scene.track == null or _scene.player == null:
		return
	_started = true
	var grid: Dictionary = info.get("grid", {})
	if not grid.has(_session.my_pid):
		_on_lost("this race started without you")
		return
	var track: Track = _scene.track
	var spec: CarSpec = load(_scene.config_used.car_spec_path) as CarSpec
	_scene.player.reset_to(track.get_grid_transform(int(grid[_session.my_pid])))
	_scene.player.set_frozen_for_grid(true)
	for pid: int in grid:
		if pid == _session.my_pid:
			continue
		var car: ArcadeCar = CarFactory.create(_scene.config_used.car_scene, spec, _scene.config_used.opponent_paint(pid))
		get_parent().add_child(car)
		car.set_physics_process(false)
		car.reset_to(track.get_grid_transform(int(grid[pid])))
		car.set_frozen_for_grid(true)
		_cars[pid] = car
		_samples[pid] = []
	_scene.start_net_countdown()


func _physics_process(delta: float) -> void:
	if not _started or _done or _scene == null or _scene.race == null or _scene.player == null:
		return
	if _scene.race.state != RaceManager.State.RACING:
		return
	_send_t += delta
	var step: float = 1.0 / NetConfig.SNAP_HZ
	if _send_t < step:
		return
	_send_t -= step
	_seq += 1
	var p: ArcadeCar = _scene.player
	var steer: float = p.input.steer if p.input != null else 0.0
	# A move this long between two sent states is a reset (R key, stuck recovery): the server accepts one short jump.
	var reset: bool = _has_last and p.global_position.distance_to(_last_origin) > NetConfig.RESET_TRIGGER_M
	_last_origin = p.global_position
	_has_last = true
	_session.send_state(_seq, p.global_transform, p.linear_velocity, steer, reset)


func _process(_delta: float) -> void:
	if _cars.is_empty():
		return
	var render_t: float = Time.get_ticks_msec() / 1000.0 - NetConfig.INTERP_DELAY_S
	for pid: int in _cars:
		var samples: Array = _samples.get(pid, [])
		if samples.is_empty():
			continue
		var car: ArcadeCar = _cars[pid]
		car.global_transform = _sample_at(samples, render_t)
		car.reset_physics_interpolation()


## Interpolated transform at time t from [time_s, xf] samples sorted by time. Clamped at both ends.
static func _sample_at(samples: Array, t: float) -> Transform3D:
	var first: Array = samples[0]
	if t <= float(first[0]):
		return first[1]
	var last: Array = samples[samples.size() - 1]
	if t >= float(last[0]):
		return last[1]
	for i: int in range(samples.size() - 1):
		var a: Array = samples[i]
		var b: Array = samples[i + 1]
		var ta: float = float(a[0])
		var tb: float = float(b[0])
		if t >= ta and t <= tb:
			var k: float = (t - ta) / maxf(tb - ta, 0.0001)
			return (a[1] as Transform3D).interpolate_with(b[1] as Transform3D, k)
	return last[1]


func _on_snapshot(pid: int, d: Dictionary) -> void:
	if not _samples.has(pid):
		return
	var xf: Variant = d.get("xf")
	if not (xf is Transform3D) or not NetProtocol.xf_finite(xf):
		return
	var arr: Array = _samples[pid]
	arr.append([Time.get_ticks_msec() / 1000.0, xf])
	while arr.size() > SAMPLES_MAX:
		arr.pop_front()


func _on_peer_left(pid: int) -> void:
	if _cars.has(pid):
		(_cars[pid] as ArcadeCar).queue_free()
		_cars.erase(pid)
		_samples.erase(pid)


func _on_results(rows: Array) -> void:
	if _done:
		return
	_done = true
	var out: Array[Dictionary] = []
	for r: Variant in rows:
		var row: Dictionary = r
		var finished: bool = bool(row.get("finished", false))
		out.append({
			"name": str(row.get("name", "")),
			"position": int(row.get("position", 0)),
			"total_time": float(row.get("time", 0.0)) if finished else 0.0,
			"best_lap": 0.0,
			"is_player": int(row.get("pid", -1)) == _session.my_pid,
		})
	_scene.hud.visible = false
	_scene.results_screen.set_replay_enabled(false)
	_scene.results_screen.show_results(out, {})
	_scene.results_screen.visible = true
	call_deferred("_leave_session")


func _on_lost(reason: String) -> void:
	if _done:
		return
	_done = true
	_session.last_message = reason
	call_deferred("_leave_session")
	call_deferred("_go_menu")


func _leave_session() -> void:
	if _session != null and _session.role != NetSession.ROLE_NONE:
		_session.close()


func _go_menu() -> void:
	Router.goto(MENU_SCENE)
