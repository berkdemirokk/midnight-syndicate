extends "res://tests/test_case.gd"
## Online LAN protocol and lobby rules (game/net/net_protocol.gd, net_lobby.gd, net_config.gd). Pure logic, no sockets.


func _st(seq: int, origin: Vector3, vel: Vector3 = Vector3(0.0, 0.0, -20.0), steer: float = 0.0) -> Dictionary:
	return NetProtocol.make_state(seq, Transform3D(Basis.IDENTITY, origin), vel, steer)


func test_version_mismatch_rejected() -> void:
	var reason: String = NetProtocol.check_hello(NetConfig.PROTOCOL_VERSION + 1, "Tester")
	check(reason.begins_with("version mismatch"), "a different protocol version is rejected, got '%s'" % reason)
	check(NetProtocol.check_hello(NetConfig.PROTOCOL_VERSION, "Tester") == "", "the matching version is accepted")
	check(NetProtocol.check_hello(NetConfig.PROTOCOL_VERSION, "   ") != "", "an empty name is rejected")
	check(NetProtocol.check_hello(NetConfig.PROTOCOL_VERSION, "x".repeat(NetConfig.MAX_NAME_LEN + 1)) != "", "a long name is rejected")


func test_invalid_states_rejected() -> void:
	var ok: Dictionary = _st(1, Vector3.ZERO)
	check(NetProtocol.validate_state({}, ok, 0.05) == "", "a plain first state is accepted")
	var nan_state: Dictionary = _st(1, Vector3(NAN, 0.0, 0.0))
	check(NetProtocol.validate_state({}, nan_state, 0.05) == "non-finite state", "NaN position is rejected")
	var inf_vel: Dictionary = _st(1, Vector3.ZERO, Vector3(INF, 0.0, 0.0))
	check(NetProtocol.validate_state({}, inf_vel, 0.05) == "non-finite state", "infinite velocity is rejected")
	var fast: Dictionary = _st(1, Vector3.ZERO, Vector3(0.0, 0.0, -130.0))
	check(NetProtocol.validate_state({}, fast, 0.05).begins_with("speed"), "speed above 120 m/s is rejected")
	var wrong_type: Dictionary = {"seq": "1", "xf": Transform3D.IDENTITY, "vel": Vector3.ZERO, "steer": 0.0}
	check(NetProtocol.validate_state({}, wrong_type, 0.05) == "malformed state", "a string sequence number is rejected")
	var bad_steer: Dictionary = _st(1, Vector3.ZERO, Vector3.ZERO, 3.0)
	check(NetProtocol.validate_state({}, bad_steer, 0.05) == "steer out of range", "steer beyond 1 is rejected")


func test_sequence_and_teleport_rules() -> void:
	var prev: Dictionary = _st(5, Vector3.ZERO)
	check(NetProtocol.validate_state(prev, _st(5, Vector3(0.5, 0.0, 0.0)), 0.05) == "sequence not increasing", "a repeated sequence number is rejected")
	check(NetProtocol.validate_state(prev, _st(4, Vector3(0.5, 0.0, 0.0)), 0.05) == "sequence not increasing", "an older sequence number is rejected")
	# 20 m/s over 0.05 s: 1 m step is fine, a 500 m jump is a teleport.
	check(NetProtocol.validate_state(prev, _st(6, Vector3(0.0, 0.0, -1.0)), 0.05) == "", "a normal step is accepted")
	var jump: String = NetProtocol.validate_state(prev, _st(6, Vector3(0.0, 0.0, -500.0)), 0.05)
	check(jump.begins_with("teleport"), "a 500 m jump in one state is rejected, got '%s'" % jump)


func test_reset_waives_only_the_teleport_limit() -> void:
	var prev: Dictionary = _st(5, Vector3.ZERO)
	check(NetProtocol.validate_state(prev, _st(6, Vector3(0.0, 0.0, -500.0)), 0.05, true) == "", "a flagged reset may move the car")
	check(NetProtocol.validate_state(prev, _st(5, Vector3(0.0, 0.0, -500.0)), 0.05, true) == "sequence not increasing", "a flagged reset keeps the sequence check")
	check(NetProtocol.validate_state(prev, _st(6, Vector3(NAN, 0.0, 0.0)), 0.05, true) == "non-finite state", "a flagged reset keeps the finite check")


func test_bind_is_loopback_unless_lan_is_given() -> void:
	check(NetConfig.bind_allowed("127.0.0.1"), "loopback is allowed")
	check(not NetConfig.bind_allowed("0.0.0.0"), "a wildcard bind is refused")
	check(not NetConfig.bind_allowed("192.168.1.20"), "a LAN address needs --address on the command line")
	check(not NetConfig.bind_allowed(""), "an empty address is refused")


func test_lobby_ready_and_capacity() -> void:
	var lobby := NetLobby.new()
	check(lobby.join(1, "A") == "", "first player joins")
	check(lobby.join(1, "A again") != "", "the same pid cannot join twice")
	lobby.join(2, "B")
	check(not lobby.can_start(), "no start with nobody ready")
	lobby.set_ready(1, true)
	check(not lobby.can_start(), "one ready player is not enough")
	lobby.set_ready(2, true)
	check(lobby.can_start(), "two ready players start the race")
	check(lobby.racers().size() == 2 and lobby.racers()[0] == 1, "racers keep join order")
	for i: int in range(3, NetConfig.MAX_PLAYERS + 1):
		lobby.join(i, "P%d" % i)
	check(lobby.join(99, "overflow") != "", "a full lobby refuses another player")
	lobby.reset_ready()
	check(lobby.ready_count() == 0, "reset clears the ready flags")
	lobby.leave(2)
	check(not lobby.has(2), "a player who leaves is removed")
	check(NetConfig.is_enabled() == false, "online is off by default (NetConfig.ENABLED false, no --experimental-online flag)")


func test_grid_cap_matches_track() -> void:
	check(NetConfig.MAX_PLAYERS <= 8, "the online lobby never exceeds the 8 grid slots")
	check(NetConfig.MIN_START_READY >= 2, "a race needs at least two players")
	check(NetConfig.DEFAULT_BIND == "127.0.0.1", "the server binds loopback by default")
