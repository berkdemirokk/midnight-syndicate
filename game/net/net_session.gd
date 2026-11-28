class_name NetSession
extends Node
## LAN session (experimental, see docs/design/ONLINE_LAN.md). Raw ENet transport (ENetConnection, so the server can
## bind 127.0.0.1), a server lobby with ready flags, a shared countdown, relay of validated car states, and server
## race results. One instance lives under the scene root as "NetSession" so it survives scene changes.
## Clients never decide progress, laps or finish order: the server does (NetRaceAuthority).

signal lobby_changed(players: Array)
signal welcomed(pid: int)
signal rejected(reason: String)
signal race_starting(info: Dictionary)  ## client: start message (countdown, laps, grid, names)
signal snapshot_received(pid: int, st: Dictionary)
signal peer_left(pid: int)
signal results_received(rows: Array)
signal connection_lost(reason: String)
signal server_results(rows: Array)  ## server: results it sent to the clients
signal order_received(rows: Array)  ## client: live order of the racers (NetProtocol.clean_order checks it)

const NODE_NAME: String = "NetSession"
const ROLE_NONE: int = 0
const ROLE_SERVER: int = 1
const ROLE_CLIENT: int = 2
const STATE_LOBBY: String = "lobby"
const STATE_COUNTDOWN: String = "countdown"
const STATE_RACING: String = "racing"
const LOST_MESSAGE: String = "lost the connection to the server"  ## English on the wire; menus show net.lost

var role: int = ROLE_NONE
var my_pid: int = -1
var my_name: String = ""
var last_message: String = ""  ## read by the main menu after a reject or a lost connection
var race_info: Dictionary = {}  ## client: the last start message
var stats: Dictionary = {"accepted": 0, "rejected": 0, "relayed": 0, "rate_limited": 0, "snapshots_seen": 0, "orders_seen": 0}  ## logs and smoke tests

var _host: ENetConnection = null
var _server_link: ENetPacketPeer = null  ## client: the connection to the server
var _lobby: NetLobby = NetLobby.new()
var _pid_of: Dictionary = {}  ## server: peer key (String) -> pid
var _peer_of: Dictionary = {}  ## server: pid -> ENetPacketPeer
var _next_pid: int = 1
var _rate: Dictionary = {}  ## server: pid -> [window start s of the sim clock, states in window]
var _sim_t: float = 0.0  ## server: summed frame time, so the rate cap follows game time, not the wall clock
var _accepted_by_pid: Dictionary = {}  ## server: pid -> accepted states, printed at the end of the race
var _state: String = STATE_LOBBY
var _countdown_t: float = 0.0
var _order_t: float = 0.0  ## server: time since the last order message
var _track_path: String = ""  ## server: the allow-listed track scene the race uses, "" for the development circuit
var _race: NetRaceAuthority = null
var _track: Track = null
var _laps: int = 1
var rtt_last_ms: float = -1.0  ## client: round trip to the server, measured with ping and pong
var rtt_min_ms: float = -1.0
var _rtt_sum_ms: float = 0.0
var _rtt_n: int = 0
var resume: Dictionary = {}  ## client: the car's last accepted server state when this join resumes a dropped seat, else {}
var last_reject_key: String = ""  ## client: NetProtocol.REJECT_* key of the last reject, "" for other reasons
var _rejected: bool = false  ## client: the server refused this connect; the disconnect that follows is not a lost link
var _join_code: String = ""  ## server: the join code every hello must carry (never sent to clients or logged)
var _hello_code: String = ""  ## client: the join code sent in the hello
var _hello_limit: NetHelloLimiter = NetHelloLimiter.new()  ## server: hello attempts per remote address
var _unjoined: Dictionary = {}  ## server: peer key -> [connect time on the sim clock, peer], until its hello is accepted
var _seats: NetReconnect = NetReconnect.new()  ## server: seats held for players who dropped out of a race
var _start_msg: Dictionary = {}  ## server: the start message of this race, sent again to a player who resumes


## The session node under the scene root, created on first use.
static func get_or_create(tree: SceneTree) -> NetSession:
	var s: NetSession = tree.root.get_node_or_null(NODE_NAME) as NetSession
	if s == null:
		s = NetSession.new()
		s.name = NODE_NAME
		tree.root.add_child(s)
	return s


func _process(delta: float) -> void:
	if _host == null:
		return
	var guard: int = 0
	while guard < 512 and _host != null:
		guard += 1
		var ev: Array = _host.service(0)
		var kind: int = int(ev[0])
		if kind == ENetConnection.EVENT_NONE:
			break
		var peer: ENetPacketPeer = ev[1] as ENetPacketPeer
		if kind == ENetConnection.EVENT_CONNECT and peer != null and role == ROLE_SERVER:
			_unjoined[_peer_key(peer)] = [_sim_t, peer]
		if kind == ENetConnection.EVENT_CONNECT and peer != null and role == ROLE_CLIENT:
			_send(peer, {"t": NetProtocol.MSG_HELLO, "v": NetConfig.PROTOCOL_VERSION, "name": my_name, "code": _hello_code})
		if kind == ENetConnection.EVENT_RECEIVE and peer != null:
			_on_packet(peer)
		elif kind == ENetConnection.EVENT_DISCONNECT and peer != null:
			_on_disconnect(peer)
		elif kind == ENetConnection.EVENT_ERROR:
			push_warning("net transport error")
	if role == ROLE_SERVER:
		_tick_server(delta)


## Server: binds bind_address:port (127.0.0.1 unless a LAN address is given) and builds the dev circuit.
func start_server(bind_address: String, port: int, laps: int, track_scene: String = NetConfig.TRACK_SCENE, join_code: String = "") -> String:
	if role != ROLE_NONE:
		return "already running"
	if not NetConfig.bind_allowed(bind_address):
		return "refused: %s is not loopback; start with --address=<LAN IP> to host on the LAN" % bind_address
	# An empty code means a random one; a given code must be well formed (the menu shows the code it ends up with).
	var code: String = NetProtocol.normalize_code(join_code)
	if code == "":
		code = NetProtocol.make_code()
	elif not NetProtocol.code_valid(code):
		return "refused: the join code is %d characters from %s" % [NetConfig.CODE_LEN, NetConfig.CODE_ALPHABET]
	_host = ENetConnection.new()
	# Extra slots past the 8 players: a connection that never sends hello must not hold a player's seat.
	var err: int = _host.create_host_bound(bind_address, port, NetConfig.MAX_PLAYERS + 4)
	if err != OK:
		_host = null
		return "could not open %s:%d (error %d)" % [bind_address, port, err]
	role = ROLE_SERVER
	_join_code = code
	my_pid = 0
	_laps = maxi(laps, 1)
	_track = NetTrack.instance(track_scene)
	_track_path = track_scene if _track != null else ""
	if _track == null:
		if track_scene != "":
			push_warning("net: track %s did not load, using the development circuit" % track_scene)
		_track = DevTrack.build()
	add_child(_track)
	print("[net] server listening on %s:%d, %d lap(s), protocol %d" % [bind_address, port, _laps, NetConfig.PROTOCOL_VERSION])
	print("[net] track: %s" % (_track_path if _track_path != "" else "dev circuit"))
	return ""


## Client: connects to address:port; the hello is sent at once and the server answers with welcome or reject.
func connect_to_server(address: String, port: int, player_name: String, join_code: String = "") -> String:
	if role != ROLE_NONE:
		return "already connected"
	_host = ENetConnection.new()
	if _host.create_host(1) != OK:
		_host = null
		return "could not create a client socket"
	_server_link = _host.connect_to_host(address, port, 1, 0)
	role = ROLE_CLIENT
	_rejected = false
	last_reject_key = ""
	my_name = player_name.strip_edges()
	_hello_code = NetProtocol.normalize_code(join_code)
	# The hello goes out on EVENT_CONNECT: ENet drops sends made before the link is up.
	return ""


func send_ping() -> void:
	_send(_server_link, {"t": NetProtocol.MSG_PING, "ts": Time.get_ticks_usec()}, false)


func rtt_avg_ms() -> float:
	return _rtt_sum_ms / float(_rtt_n) if _rtt_n > 0 else -1.0


func send_ready(on: bool) -> void:
	_send(_server_link, {"t": NetProtocol.MSG_READY, "on": on})


## Client: one car state (see NetProtocol.make_state). Unreliable: a late state is worthless.
func send_state(seq: int, xf: Transform3D, vel: Vector3, steer: float, reset: bool = false) -> void:
	_send(_server_link, {"t": NetProtocol.MSG_STATE, "seq": seq, "xf": xf, "vel": vel, "steer": steer, "reset": reset}, false)


## Leaves cleanly: the server drops this player from the lobby or the race.
func close() -> void:
	if _host != null:
		if role == ROLE_CLIENT and _server_link != null and _server_link.get_state() == ENetPacketPeer.STATE_CONNECTED:
			_send(_server_link, {"t": NetProtocol.MSG_BYE})
			_server_link.peer_disconnect_later()
		for pid: int in _peer_of:
			if (_peer_of[pid] as ENetPacketPeer).get_state() == ENetPacketPeer.STATE_CONNECTED:
				(_peer_of[pid] as ENetPacketPeer).peer_disconnect_later()
		_host.flush()
		_host.destroy()
	_host = null
	_server_link = null
	role = ROLE_NONE
	my_pid = -1
	race_info = {}
	_lobby = NetLobby.new()
	_pid_of.clear()
	_peer_of.clear()
	_next_pid = 1
	_state = STATE_LOBBY
	_race = null
	_track_path = ""
	_join_code = ""
	_hello_code = ""
	_hello_limit = NetHelloLimiter.new()
	_unjoined.clear()
	_seats.clear()
	_start_msg = {}
	resume = {}
	if _track != null:
		_track.queue_free()
		_track = null


## Server: the join code players must enter (shown to the host in the lobby overlay, sent to no one).
func join_code() -> String:
	return _join_code


func lobby_players() -> Array:
	return _lobby.snapshot()


## True when a connection that opened at connected_at_s has gone past NetConfig.HELLO_DEADLINE_S without a hello.
static func hello_overdue(connected_at_s: float, now_s: float) -> bool:
	return now_s - connected_at_s > NetConfig.HELLO_DEADLINE_S


func _tick_server(delta: float) -> void:
	_sim_t += delta
	for key: String in _unjoined.keys():
		var entry: Array = _unjoined[key]
		if hello_overdue(float(entry[0]), _sim_t):
			_unjoined.erase(key)
			(entry[1] as ENetPacketPeer).peer_disconnect_later()
	for seat: int in _seats.expire(_sim_t):
		if _race != null:
			_race.mark_dnf(seat, "disconnected")
		print("[net] pid %d did not come back within the grace period: DNF" % seat)
	if _state == STATE_COUNTDOWN:
		_countdown_t -= delta
		if _countdown_t <= 0.0:
			_state = STATE_RACING
			print("[net] GO, server race clock starts")
	elif _state == STATE_RACING and _race != null:
		_race.tick(delta)
		_order_t += delta
		if _order_t >= 1.0 / NetConfig.ORDER_HZ:
			_order_t -= 1.0 / NetConfig.ORDER_HZ
			_broadcast({"t": NetProtocol.MSG_ORDER, "rows": _race.order_rows()}, false)
		if _race.all_over():
			_end_race()


func _on_packet(peer: ENetPacketPeer) -> void:
	var raw: PackedByteArray = peer.get_packet()
	if raw.size() > NetConfig.MAX_PACKET_BYTES:
		return
	var msg: Variant = bytes_to_var(raw)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	var d: Dictionary = msg
	var t: String = str(d.get("t", ""))
	if role == ROLE_SERVER:
		_server_message(peer, t, d)
	else:
		_client_message(t, d)


func _server_message(peer: ENetPacketPeer, t: String, d: Dictionary) -> void:
	var key: String = _peer_key(peer)
	if t == NetProtocol.MSG_HELLO:
		_on_hello(peer, key, d)
		return
	if t == NetProtocol.MSG_PING:
		_send(peer, {"t": NetProtocol.MSG_PONG, "ts": d.get("ts", 0)}, false)
		return
	if not _pid_of.has(key):
		return
	var pid: int = _pid_of[key]
	match t:
		NetProtocol.MSG_READY:
			if _state != STATE_LOBBY:
				return
			_lobby.set_ready(pid, bool(d.get("on", false)))
			print("[net] ready pid %d: %s" % [pid, str(bool(d.get("on", false)))])
			_broadcast_lobby()
			if _lobby.can_start():
				_begin_countdown()
		NetProtocol.MSG_STATE:
			_on_state(pid, d)
		NetProtocol.MSG_BYE:
			peer.peer_disconnect_later()


func _on_hello(peer: ENetPacketPeer, key: String, d: Dictionary) -> void:
	_unjoined.erase(key)
	if _pid_of.has(key):
		return
	var player_name: String = str(d.get("name", "")).strip_edges()
	var reason: String = ""
	var reason_key: String = ""
	# Every attempt counts, right or wrong, before anything else is checked: this is what stops code guessing.
	if not _hello_limit.allow(peer.get_remote_address(), Time.get_ticks_msec() / 1000.0):
		reason = "too many attempts, wait a few seconds"
		reason_key = NetProtocol.REJECT_RATE
	else:
		reason = NetProtocol.check_hello(int(d.get("v", -1)), player_name)
	if reason == "" and not NetProtocol.code_matches(_join_code, d.get("code", "")):
		reason = "wrong join code"
		reason_key = NetProtocol.REJECT_CODE
	if reason == "" and _state != STATE_LOBBY:
		var seat: int = _resume_seat(player_name)
		if seat >= 0:
			_resume(peer, key, seat)
			return
	if reason == "" and _state != STATE_LOBBY:
		reason = "a race is running, try again after the results"
	var pid: int = _next_pid
	if reason == "":
		reason = _lobby.join(pid, player_name)
	if reason != "":
		print("[net] reject hello: %s" % reason)
		_send(peer, {"t": NetProtocol.MSG_REJECT, "reason": reason, "key": reason_key})
		peer.peer_disconnect_later()
		return
	_next_pid += 1
	_pid_of[key] = pid
	_peer_of[pid] = peer
	print("[net] join pid %d name %s" % [pid, player_name])
	_send(peer, {"t": NetProtocol.MSG_WELCOME, "pid": pid, "v": NetConfig.PROTOCOL_VERSION})
	_broadcast_lobby()


## Server: the seat a hello of this name resumes during a race: a held seat inside the grace period, or the active
## seat of the same name (the old connection has not timed out yet). -1 when there is none.
func _resume_seat(player_name: String) -> int:
	if _race == null:
		return -1
	var seat: int = _seats.claim(player_name, _sim_t)
	if seat >= 0:
		return seat
	for other: int in _peer_of:
		if _race.is_racing(other) and _race.driver(other).display_name == player_name:
			return other
	return -1


## Server: the player gets its seat back: same pid, the car's last accepted state (the client resumes from it and
## continues the sequence after it) and the race's start message again with no countdown.
func _resume(peer: ENetPacketPeer, key: String, pid: int) -> void:
	var old: ENetPacketPeer = _peer_of.get(pid) as ENetPacketPeer
	if old != null and old != peer:
		_forget_pid_keys(pid)
		old.peer_disconnect_later()
	_pid_of[key] = pid
	_peer_of[pid] = peer
	var driver: NetRaceAuthority.NetDriver = _race.driver(pid)
	if not _lobby.has(pid):
		_lobby.join(pid, driver.display_name)
		_lobby.set_ready(pid, true)
	var st: Dictionary = driver.last_state
	var seat_state: Dictionary = {}
	if not st.is_empty():
		seat_state = {"seq": st["seq"], "xf": st["xf"], "vel": st["vel"], "steer": st["steer"]}
	print("[net] resume pid %d name %s, last seq %d" % [pid, driver.display_name, int(seat_state.get("seq", 0))])
	_send(peer, {"t": NetProtocol.MSG_WELCOME, "pid": pid, "v": NetConfig.PROTOCOL_VERSION, "resume": seat_state})
	var again: Dictionary = _start_msg.duplicate()
	again["countdown"] = 0.0
	again["resume"] = true
	_send(peer, again)


func _on_state(pid: int, d: Dictionary) -> void:
	# Cars that finished or dropped out send no more useful states: dropped silently, not logged as rejects.
	if _state != STATE_RACING or _race == null or not _race.is_racing(pid):
		return
	if _over_rate(pid):
		stats["rate_limited"] = int(stats["rate_limited"]) + 1
		return
	# Raw client values: NetRaceAuthority.submit type-checks them before they are used.
	var st: Dictionary = {"seq": d.get("seq"), "xf": d.get("xf"), "vel": d.get("vel"), "steer": d.get("steer")}
	var reason: String = _race.submit(pid, st, bool(d.get("reset", false)))
	if reason != "":
		stats["rejected"] = int(stats["rejected"]) + 1
		print("[net] reject state pid %d: %s" % [pid, reason])
		return
	stats["accepted"] = int(stats["accepted"]) + 1
	_accepted_by_pid[pid] = int(_accepted_by_pid.get(pid, 0)) + 1
	for other: int in _peer_of:
		if other == pid:
			continue
		_send(_peer_of[other], {"t": NetProtocol.MSG_SNAP, "pid": pid, "seq": st["seq"], "xf": st["xf"], "vel": st["vel"], "steer": st["steer"]}, false)
		stats["relayed"] = int(stats["relayed"]) + 1


## Caps the states accepted per car per second (NetConfig.MAX_STATES_PER_S); the excess is dropped unread.
func _over_rate(pid: int) -> bool:
	var now: float = _sim_t
	var w: Array = _rate.get(pid, [now, 0])
	if now - float(w[0]) >= 1.0:
		w = [now, 0]
	w[1] = int(w[1]) + 1
	_rate[pid] = w
	return int(w[1]) > NetConfig.MAX_STATES_PER_S


func _begin_countdown() -> void:
	var racers: Array[int] = _lobby.racers()
	var grid: Dictionary = {}
	var names: Dictionary = {}
	for i: int in racers.size():
		grid[racers[i]] = i
		names[racers[i]] = _lobby.players[racers[i]]["name"]
	_race = NetRaceAuthority.new()
	_race.setup(_track, _laps, names, grid)
	_state = STATE_COUNTDOWN
	_countdown_t = NetConfig.COUNTDOWN_S
	_order_t = 0.0
	print("[net] start: %d racers, grid %s" % [racers.size(), str(grid)])
	_start_msg = {"t": NetProtocol.MSG_START, "countdown": NetConfig.COUNTDOWN_S, "laps": _laps, "grid": grid, "names": names, "track": _track_path}
	_broadcast(_start_msg)


func _end_race() -> void:
	var rows: Array[Dictionary] = _race.results()
	print("[net] results: %s" % str(rows))
	print("[net] accepted states per pid: %s, rate limited: %d" % [str(_accepted_by_pid), int(stats["rate_limited"])])
	_broadcast({"t": NetProtocol.MSG_RESULTS, "rows": rows})
	server_results.emit(rows)
	_race = null
	_seats.clear()
	_state = STATE_LOBBY
	_lobby.reset_ready()
	_broadcast_lobby()


func _on_disconnect(peer: ENetPacketPeer) -> void:
	if role != ROLE_SERVER:
		# A rejected client leaves the server's lobby by disconnect too: free the role so Join works again, and keep
		# the reject text instead of replacing it with the lost-connection message.
		var was_rejected: bool = _rejected
		close()
		if not was_rejected:
			last_message = LOST_MESSAGE
			connection_lost.emit(last_message)
		return
	_forget_unjoined(peer)
	var pid: int = _pid_for_peer(peer)
	if pid < 0:
		return
	_forget_pid_keys(pid)
	_peer_of.erase(pid)
	_rate.erase(pid)
	_lobby.leave(pid)
	if _race != null and _race.is_racing(pid):
		# Mid-race drop: the seat is held (see NetReconnect); the car is DNF only if no one takes it back in time.
		_seats.reserve(pid, _race.driver(pid).display_name, _sim_t)
		print("[net] pid %d dropped in the race, seat held for %.0f s" % [pid, NetConfig.RECONNECT_GRACE_S])
	print("[net] leave pid %d" % pid)
	_broadcast({"t": NetProtocol.MSG_PEER_LEFT, "pid": pid})
	peer_left.emit(pid)
	_broadcast_lobby()


## Server: the pid whose connection is this peer object, or -1. Compares objects, never asks a dead peer for its address.
func _pid_for_peer(peer: ENetPacketPeer) -> int:
	for pid: int in _peer_of:
		if _peer_of[pid] == peer:
			return pid
	return -1


## Server: removes every peer key that maps to pid (the key of a connection that has gone or been replaced).
func _forget_pid_keys(pid: int) -> void:
	for key: String in _pid_of.keys():
		if _pid_of[key] == pid:
			_pid_of.erase(key)


func _forget_unjoined(peer: ENetPacketPeer) -> void:
	for key: String in _unjoined.keys():
		if (_unjoined[key] as Array)[1] == peer:
			_unjoined.erase(key)


func _client_message(t: String, d: Dictionary) -> void:
	match t:
		NetProtocol.MSG_WELCOME:
			my_pid = int(d.get("pid", -1))
			resume = d.get("resume", {}) as Dictionary
			welcomed.emit(my_pid)
		NetProtocol.MSG_REJECT:
			last_message = str(d.get("reason", "rejected"))
			last_reject_key = str(d.get("key", ""))
			_rejected = true
			rejected.emit(last_message)
		NetProtocol.MSG_LOBBY:
			lobby_changed.emit(d.get("players", []))
		NetProtocol.MSG_START:
			race_info = d
			race_starting.emit(d)
		NetProtocol.MSG_SNAP:
			stats["snapshots_seen"] = int(stats["snapshots_seen"]) + 1
			snapshot_received.emit(int(d.get("pid", -1)), d)
		NetProtocol.MSG_PEER_LEFT:
			peer_left.emit(int(d.get("pid", -1)))
		NetProtocol.MSG_PONG:
			var rtt: float = (Time.get_ticks_usec() - int(d.get("ts", 0))) / 1000.0
			rtt_last_ms = rtt
			rtt_min_ms = rtt if rtt_min_ms < 0.0 else minf(rtt_min_ms, rtt)
			_rtt_sum_ms += rtt
			_rtt_n += 1
		NetProtocol.MSG_RESULTS:
			results_received.emit(d.get("rows", []))
		NetProtocol.MSG_ORDER:
			stats["orders_seen"] = int(stats["orders_seen"]) + 1
			order_received.emit(d.get("rows", []))


func _broadcast_lobby() -> void:
	var players: Array = _lobby.snapshot()
	lobby_changed.emit(players)  ## the host sees its own lobby too
	_broadcast({"t": NetProtocol.MSG_LOBBY, "players": players})


func _broadcast(msg: Dictionary, reliable: bool = true) -> void:
	for pid: int in _peer_of:
		_send(_peer_of[pid], msg, reliable)


func _send(peer: ENetPacketPeer, msg: Dictionary, reliable: bool = true) -> void:
	if peer == null or peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return
	var flags: int = ENetPacketPeer.FLAG_RELIABLE if reliable else ENetPacketPeer.FLAG_UNSEQUENCED
	peer.send(NetConfig.SERVER_CHANNEL, var_to_bytes(msg), flags)


func _peer_key(peer: ENetPacketPeer) -> String:
	return "%s:%d" % [peer.get_remote_address(), peer.get_remote_port()]
