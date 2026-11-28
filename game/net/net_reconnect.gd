class_name NetReconnect
extends RefCounted
## Grace seats for players who drop out of a running race (pure logic, unit tested in game/tests/test_net_reconnect.gd).
## A dropped car keeps its pid and the server's last accepted state for NetConfig.RECONNECT_GRACE_S. A hello with the
## same name (the join code is checked first, by the session) within that time takes the seat back. When the grace
## runs out the car is DNF. Seats are keyed by pid; names are matched exactly, as typed in the lobby.

var _seats: Dictionary = {}  ## pid -> {name: String, until: float} (sim clock seconds)


## Keeps pid's seat for player_name until now_s + the grace period.
func reserve(pid: int, player_name: String, now_s: float) -> void:
	_seats[pid] = {"name": player_name, "until": now_s + NetConfig.RECONNECT_GRACE_S}


## The pid of the seat held for player_name at now_s, or -1. The seat is taken (removed) when it is claimed.
func claim(player_name: String, now_s: float) -> int:
	for pid: int in _seats:
		var seat: Dictionary = _seats[pid]
		if str(seat["name"]) == player_name and now_s <= float(seat["until"]):
			_seats.erase(pid)
			return pid
	return -1


## The pids whose grace ran out by now_s. They are removed from the table, so each is reported once.
func expire(now_s: float) -> Array[int]:
	var out: Array[int] = []
	for pid: int in _seats.keys():
		if now_s > float(_seats[pid]["until"]):
			out.append(pid)
			_seats.erase(pid)
	return out


func holds(pid: int) -> bool:
	return _seats.has(pid)


func count() -> int:
	return _seats.size()


func clear() -> void:
	_seats.clear()
