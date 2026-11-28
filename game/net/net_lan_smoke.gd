extends "res://devtools/net_smoke.gd"
## LAN and impairment variant of the headless smoke test (devtools/net_smoke.gd), used by tools/net_impair_run.py.
## Differences from the base: the server binds, and the clients connect to, the address given with --address (a LAN IP
## is accepted only for the server, by NetConfig.bind_allowed); --leave-after=S makes a client leave cleanly S seconds
## after GO (BYE, no rejoin). A client that joins a race already running gets its seat back from the server (welcome
## with the seat's last accepted state, then the start message again with countdown 0 and resume true) and continues
## from that state with the sequence after it. Everything else is inherited from the base script.

var _address: String = NetConfig.DEFAULT_BIND
var _leave_after: float = -1.0
var _leave_t: float = 0.0
var _wait_players: int = 1  ## the client readies only when the lobby holds this many players (3 = all clients start together)
var _readied: bool = false


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
		elif a.begins_with("--code="):
			_code = a.trim_prefix("--code=")
		elif a.begins_with("--address="):
			_address = a.trim_prefix("--address=")
		elif a.begins_with("--wait-players="):
			_wait_players = int(a.trim_prefix("--wait-players="))
		elif a.begins_with("--leave-after="):
			_leave_after = float(a.trim_prefix("--leave-after="))
	_session = NetSession.get_or_create(self)
	if _role == "server":
		var err: String = _session.start_server(_address, _port, _laps, NetConfig.TRACK_SCENE, _code)
		if err != "":
			print("[smoke] server failed: %s" % err)
			quit(2)
			return
		_session.server_results.connect(_on_server_results)
		print("[smoke] server up on %s:%d" % [_address, _port])
	else:
		var err2: String = _session.connect_to_server(_address, _port, _name, _code)
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
		print("[smoke] %s connecting to %s:%d" % [_name, _address, _port])


func _on_welcomed(pid: int) -> void:
	print("[smoke] %s joined as pid %d" % [_name, pid])


func _on_lobby(players: Array) -> void:
	print("[smoke] %s lobby: %s" % [_name, str(players)])
	if not _readied and players.size() >= _wait_players:
		_readied = true
		_session.send_ready(true)


func _physics_process(delta: float) -> bool:
	super._physics_process(delta)
	if _leave_after > 0.0 and _racing and not _done:
		_leave_t += delta
		if _leave_t >= _leave_after:
			_done = true
			print("[smoke] %s leaves the race (bye, no rejoin)" % _name)
			_session.close()
			create_timer(0.2).timeout.connect(quit.bind(0))
	return false


func _on_start(info: Dictionary) -> void:
	super._on_start(info)
	if not bool(info.get("resume", false)):
		return
	var rs: Dictionary = _session.resume
	if rs.is_empty():
		print("[smoke] %s resumes with no state, from the grid" % _name)
	else:
		_car.reset_to(rs["xf"])
		_seq = int(rs["seq"])
		print("[smoke] %s resumes from server seq %d" % [_name, _seq])
	_car.set_frozen_for_grid(false)
	_countdown_left = -1.0
	_ai.set_racing(true)
	_racing = true
	_started_at = _elapsed
	print("[smoke] %s GO (resumed)" % _name)
