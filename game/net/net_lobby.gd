class_name NetLobby
extends RefCounted
## Players in the server lobby with names and ready flags. Pure logic, unit tested.
## Dictionary order is join order, which is also the order of the grid.

var players: Dictionary = {}  ## pid (int) -> {"name": String, "ready": bool}


## "" on success, else the reason (already joined, lobby full).
func join(pid: int, player_name: String) -> String:
	if players.has(pid):
		return "already in the lobby"
	if players.size() >= NetConfig.MAX_PLAYERS:
		return "lobby is full (%d players)" % NetConfig.MAX_PLAYERS
	players[pid] = {"name": player_name, "ready": false}
	return ""


func leave(pid: int) -> void:
	players.erase(pid)


func has(pid: int) -> bool:
	return players.has(pid)


func set_ready(pid: int, on: bool) -> bool:
	if not players.has(pid):
		return false
	players[pid]["ready"] = on
	return true


func ready_count() -> int:
	var n: int = 0
	for pid: int in players:
		if bool(players[pid]["ready"]):
			n += 1
	return n


func can_start() -> bool:
	return ready_count() >= NetConfig.MIN_START_READY


## Ready players in join order: the racers, and their grid order (index 0 = first grid slot).
func racers() -> Array[int]:
	var out: Array[int] = []
	for pid: int in players:
		if bool(players[pid]["ready"]):
			out.append(pid)
	return out


func reset_ready() -> void:
	for pid: int in players:
		players[pid]["ready"] = false


## Array of {"pid", "name", "ready"} for the lobby message.
func snapshot() -> Array:
	var out: Array = []
	for pid: int in players:
		out.append({"pid": pid, "name": players[pid]["name"], "ready": players[pid]["ready"]})
	return out
