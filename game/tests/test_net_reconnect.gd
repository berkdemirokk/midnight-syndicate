extends "res://tests/test_case.gd"
## Reconnect grace seats, duplicate and out-of-order states, and the state timeout (game/net/net_reconnect.gd,
## net_protocol.gd). Pure logic, no sockets. The real drop and rejoin over ENet is run by tools/net_impair_run.py.


func test_reconnect_within_grace_takes_the_seat() -> void:
	var seats := NetReconnect.new()
	seats.reserve(3, "Bo", 100.0)
	check(seats.holds(3), "a dropped car keeps its seat")
	check(seats.claim("Bo", 100.0 + NetConfig.RECONNECT_GRACE_S - 0.5) == 3, "the same name inside the grace gets pid 3 back")
	check(not seats.holds(3), "a claimed seat is taken, not kept for a second claim")
	check(seats.claim("Bo", 101.0) == -1, "a second claim of the same seat finds nothing")


func test_reconnect_wrong_name_or_late_is_refused() -> void:
	var seats := NetReconnect.new()
	seats.reserve(4, "Ada", 50.0)
	check(seats.claim("Eve", 51.0) == -1, "another name cannot take Ada's seat")
	check(seats.claim("ada", 51.0) == -1, "names are matched exactly")
	check(seats.claim("Ada", 50.0 + NetConfig.RECONNECT_GRACE_S + 1.0) == -1, "a claim after the grace is refused")
	check(seats.holds(4), "a refused claim leaves the seat for the expiry to handle")


func test_grace_expiry_reports_each_seat_once() -> void:
	var seats := NetReconnect.new()
	seats.reserve(1, "A", 0.0)
	seats.reserve(2, "B", 5.0)
	check(seats.expire(NetConfig.RECONNECT_GRACE_S).is_empty(), "nothing expires exactly at the grace end")
	var gone: Array[int] = seats.expire(NetConfig.RECONNECT_GRACE_S + 1.0)
	check(gone == [1], "only the seat whose grace ran out is reported (got %s)" % str(gone))
	var late: Array[int] = seats.expire(NetConfig.RECONNECT_GRACE_S + 100.0)
	check(late == [2], "the next seat expires on its own clock")
	check(seats.expire(1000.0).is_empty(), "an expired seat is not reported again")
	check(seats.count() == 0, "no seats left")


func test_duplicate_and_reordered_states_refused() -> void:
	var xf := Transform3D(Basis.IDENTITY, Vector3(0, 0, 0))
	var first: Dictionary = NetProtocol.make_state(5, xf, Vector3.ZERO, 0.0)
	var again: Dictionary = NetProtocol.make_state(5, xf, Vector3.ZERO, 0.0)
	var older: Dictionary = NetProtocol.make_state(4, xf, Vector3.ZERO, 0.0)
	var newer: Dictionary = NetProtocol.make_state(6, xf, Vector3.ZERO, 0.0)
	check(NetProtocol.validate_state({}, first, 0.0) == "", "the first state is accepted")
	check(NetProtocol.validate_state(first, again, 0.05).begins_with("sequence"), "a duplicate sequence is refused")
	check(NetProtocol.validate_state(first, older, 0.05).begins_with("sequence"), "an older (reordered) state is refused")
	check(NetProtocol.validate_state(first, newer, 0.05) == "", "a later state is accepted")


func test_long_gap_allowance_is_not_a_teleport() -> void:
	## A state that arrives after a long gap (lost packets) is not a teleport by itself: the allowance grows with dt.
	var xf0 := Transform3D(Basis.IDENTITY, Vector3(0, 0, 0))
	var xf1 := Transform3D(Basis.IDENTITY, Vector3(40.0, 0, 0))
	var prev: Dictionary = NetProtocol.make_state(1, xf0, Vector3(40.0, 0, 0), 0.0)
	var st: Dictionary = NetProtocol.make_state(2, xf1, Vector3(40.0, 0, 0), 0.0)
	check(NetProtocol.validate_state(prev, st, 1.0) == "", "40 m in 1 s at 40 m/s is allowed after a 1 s gap")
	check(NetProtocol.validate_state(prev, st, 0.05).begins_with("teleport"), "40 m in 50 ms is refused")


func test_held_seats_are_listed_for_the_end_of_race() -> void:
	var seats := NetReconnect.new()
	seats.reserve(2, "Bo", 0.0)
	seats.reserve(3, "Cy", 0.0)
	var held: Array[int] = seats.pids()
	held.sort()
	check(held == [2, 3], "both held seats are listed (got %s)" % str(held))
	seats.claim("Bo", 1.0)
	var left: Array[int] = seats.pids()
	check(left == [3], "a claimed seat is no longer listed (got %s)" % str(left))


func test_live_takeover_needs_the_same_address() -> void:
	check(NetSession.address_of_key("192.168.1.5:9999") == "192.168.1.5", "IPv4 key splits into address and port")
	check(NetSession.address_of_key("::1:4242") == "::1", "IPv6 key is cut at the last colon")
	check(NetSession.address_of_key("10.0.0.2:5") != NetSession.address_of_key("10.0.0.9:5"), "another address does not match the seat")
