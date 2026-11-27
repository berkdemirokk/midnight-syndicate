extends SceneTree
## Multi-process LAN smoke test for the online race (game/net). Start one server and two clients on 127.0.0.1:
##   godot --headless --path game -s res://devtools/net_smoke.gd -- --role=server --port=24590 --laps=1
##   godot --headless --path game -s res://devtools/net_smoke.gd -- --role=client --port=24590 --name=Ada
## (tools/net_smoke.py starts all three and checks the logs. No --fixed-fps: the server clock must be wall time.)
## Clients are real game processes: each drives a real ArcadeCar with the racing AI (AIDriver, RaceConfig.autopilot
## style) on the development circuit and sends its car state at SNAP_HZ. The server validates, relays, and decides
## laps, finish order and times. Prints "[smoke]" lines; exit code 0 when the results arrived.

const CAR_SCENE: String = "res://vehicles/noctra_tayfun/noctra_tayfun.tscn"
const SPEC_PATH: String = "res://vehicles/specs/noctra_tayfun.tres"
const PAINT: Color = Color("#8E0F1E")
const AUTOPILOT_SKILL: float = 0.97
const CLIENT_TIMEOUT_S: float = 240.0
const SERVER_TIMEOUT_S: float = 300.0
const PING_EVERY_S: float = 0.5

var _session: NetSession
var _role: String = "server"
var _name: String = "Client"
var _port: int = NetConfig.DEFAULT_PORT
var _laps: int = 1
var _track: Track = null
var _car: ArcadeCar = null
var _ai: AIDriver = null
var _countdown_left: float = -1.0
var _racing: bool = false
var _send_t: float = 0.0
var _ping_t: float = 0.0
var _seq: int = 0
var _sent: int = 0
var _elapsed: float = 0.0
var _done: bool = false
var _started_at: float = 0.0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			_role = a.trim_prefix("--role=")
		elif a.begins_with("--name="):
			_name = a.trim_prefix("--name=")
		elif a.begins_with("--port="):
			_port = int(a.trim_prefix("--port="))
		elif a.begins_with("--laps="):
			_laps = int(a.trim_prefix("--laps="))
	_session = NetSession.get_or_create(self)
	if _role == "server":
		var err: String = _session.start_server(NetConfig.DEFAULT_BIND, _port, _laps)
		if err != "":
			print("[smoke] server failed: %s" % err)
			quit(2)
			return
		_session.server_results.connect(_on_server_results)
		print("[smoke] server up on %s:%d" % [NetConfig.DEFAULT_BIND, _port])
	else:
		var err2: String = _session.connect_to_server(NetConfig.DEFAULT_BIND, _port, _name)
		if err2 != "":
			print("[smoke] client failed: %s" % err2)
			quit(2)
			return
		_session.welcomed.connect(_on_welcomed)
		_session.lobby_changed.connect(_on_lobby)
		_session.race_starting.connect(_on_start)
		_session.results_received.connect(_on_results)
		_session.rejected.connect(_on_rejected)
		_session.connection_lost.connect(_on_lost)
		print("[smoke] %s connecting to %s:%d" % [_name, NetConfig.DEFAULT_BIND, _port])


func _process(delta: float) -> bool:
	_elapsed += delta
	# Wall clock: headless runs at uncapped frame rate, so sim time can race ahead of ENet handshakes.
	var wall_s: float = Time.get_ticks_msec() / 1000.0
	if _role == "server" and wall_s > SERVER_TIMEOUT_S:
		print("[smoke] server timeout")
		quit(1)
	elif _role != "server" and wall_s > CLIENT_TIMEOUT_S:
		print("[smoke] %s timeout" % _name)
		quit(1)
	return false


func _physics_process(delta: float) -> bool:
	if _role == "server" or _car == null or _done:
		return false
	_ping_t += delta
	if _ping_t >= PING_EVERY_S:
		_ping_t = 0.0
		_session.send_ping()
	if _countdown_left > 0.0:
		_countdown_left -= delta
		if _countdown_left <= 0.0:
			_car.set_frozen_for_grid(false)
			_ai.set_racing(true)
			_racing = true
			_started_at = _elapsed
			print("[smoke] %s GO" % _name)
	if _racing:
		_send_t += delta
		if _send_t >= 1.0 / NetConfig.SNAP_HZ:
			_send_t -= 1.0 / NetConfig.SNAP_HZ
			_seq += 1
			_sent += 1
			var steer: float = _car.input.steer if _car.input != null else 0.0
			_session.send_state(_seq, _car.global_transform, _car.linear_velocity, steer)
	return false


func _on_welcomed(pid: int) -> void:
	print("[smoke] %s joined as pid %d, ready" % [_name, pid])
	_session.send_ready(true)


func _on_lobby(players: Array) -> void:
	print("[smoke] %s lobby: %s" % [_name, str(players)])


func _on_rejected(reason: String) -> void:
	print("[smoke] %s rejected: %s" % [_name, reason])
	quit(1)


func _on_lost(reason: String) -> void:
	print("[smoke] %s connection lost: %s" % [_name, reason])
	quit(1)


func _on_start(info: Dictionary) -> void:
	var grid: Dictionary = info["grid"]
	var slot: int = int(grid[_session.my_pid])
	# the server's track (its racing line and collision), else the development circuit when it does not load
	_track = NetTrack.instance(str(info.get("track", "")))
	if _track == null:
		_track = DevTrack.build()
	root.add_child(_track)
	var spec: CarSpec = load(SPEC_PATH) as CarSpec
	_car = CarFactory.create(CAR_SCENE, spec, PAINT)
	root.add_child(_car)
	_car.reset_to(_track.get_grid_transform(slot))
	_car.set_frozen_for_grid(true)
	_ai = AIDriver.new()
	_ai.name = "AIDriver"
	_ai.skill = AUTOPILOT_SKILL
	_car.add_child(_ai)
	_ai.setup(_track)
	_ai.set_racing(false)
	_countdown_left = float(info["countdown"])
	print("[smoke] %s on grid slot %d, countdown %.1f s, %d racers" % [_name, slot, _countdown_left, grid.size()])


func _on_results(rows: Array) -> void:
	_done = true
	var snaps: int = int(_session.stats["snapshots_seen"])
	var secs: float = maxf(_elapsed - _started_at, 0.001)
	print("[smoke] %s results: %s" % [_name, str(rows)])
	print("[smoke] %s orders seen %d" % [_name, int(_session.stats["orders_seen"])])
	print("[smoke] %s sent %d states (%.1f Hz), received %d snapshots (%.1f Hz), rejected %d, rtt_ms last %.2f min %.2f avg %.2f" % [
		_name, _sent, float(_sent) / secs, snaps, float(snaps) / secs, int(_session.stats["rejected"]),
		_session.rtt_last_ms, _session.rtt_min_ms, _session.rtt_avg_ms()])
	_session.close()
	create_timer(0.2).timeout.connect(quit.bind(0))


func _on_server_results(rows: Array) -> void:
	print("[smoke] server results sent: %s" % str(rows))
	print("[smoke] server accepted %d states, rejected %d, relayed %d" % [int(_session.stats["accepted"]), int(_session.stats["rejected"]), int(_session.stats["relayed"])])
	create_timer(1.0).timeout.connect(quit.bind(0))
