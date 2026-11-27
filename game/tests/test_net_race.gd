extends "res://tests/test_case.gd"
## Server-side race truth (game/net/net_race_authority.gd) on the real development circuit: laps and finish
## order come from validated positions and the server clock, a dropped driver is DNF, teleports are refused.

const STEP_S: float = 0.05  ## one state every 50 ms, as at SNAP_HZ 20


func _make_track() -> Track:
	var track: Track = DevTrack.build()
	add(track)
	return track


## State of a car at line offset o, moving at speed_ms along the line.
static func _state_at(track: Track, seq: int, o: float, speed_ms: float) -> Dictionary:
	var p: Vector3 = track.get_point_at(o)
	var t: Vector3 = track.get_tangent_at(o)
	return NetProtocol.make_state(seq, Transform3D(Basis.looking_at(-t, Vector3.UP), p + Vector3.UP * 0.47), t * speed_ms, 0.0)


func test_authority_orders_finish_by_server_clock() -> void:
	var track: Track = _make_track()
	var race := NetRaceAuthority.new()
	race.setup(track, 1, {1: "Fast", 2: "Slow"}, {1: 0, 2: 1})
	var speed: Dictionary = {1: 30.0, 2: 25.0}  ## m/s; the slow car must finish inside FINISH_WAIT_S of the fast one
	var offset: Dictionary = {1: race.driver(1).progress, 2: race.driver(2).progress}
	var seq: int = 0
	var ticks: int = 0
	while not race.all_over() and ticks < 60000:
		race.tick(STEP_S)
		seq += 1
		for pid: int in [1, 2]:
			if not race.driver(pid).racing():
				continue
			offset[pid] = float(offset[pid]) + float(speed[pid]) * STEP_S
			var reason: String = race.submit(pid, _state_at(track, seq, float(offset[pid]), float(speed[pid])))
			if reason != "":
				check(false, "a valid step was refused for pid %d: %s (tick %d)" % [pid, reason, ticks])
		ticks += 1
	check(race.all_over(), "the race ends when every car has finished")
	var rows: Array[Dictionary] = race.results()
	check(rows.size() == 2, "two results")
	if rows.size() == 2:
		check(int(rows[0]["pid"]) == 1 and int(rows[0]["position"]) == 1, "the faster car is first by server time")
		check(bool(rows[0]["finished"]) and bool(rows[1]["finished"]), "both cars finished")
		check(float(rows[0]["time"]) < float(rows[1]["time"]), "finish times are ordered")
		metric("net_race_fast_time_s", float(rows[0]["time"]))
		metric("net_race_slow_time_s", float(rows[1]["time"]))
	metric("net_race_ticks", ticks)
	await cleanup([track])


func test_teleport_and_stale_states_refused() -> void:
	var track: Track = _make_track()
	var race := NetRaceAuthority.new()
	race.setup(track, 1, {1: "A"}, {1: 0})
	race.tick(STEP_S)
	check(race.submit(1, _state_at(track, 1, 10.0, 0.0)) == "", "the first state is accepted")
	race.tick(STEP_S)
	check(race.submit(1, _state_at(track, 2, 400.0, 0.0)).begins_with("teleport"), "a 390 m jump is refused by the server")
	race.tick(STEP_S)
	check(race.submit(1, _state_at(track, 2, 10.2, 0.0)) == "", "an honest state is still accepted after a refusal")
	check(race.submit(9, _state_at(track, 3, 10.2, 0.0)) == "not racing", "a pid that is not in the race is refused")
	await cleanup([track])


func test_disconnect_is_dnf_and_race_goes_on() -> void:
	var track: Track = _make_track()
	var race := NetRaceAuthority.new()
	race.setup(track, 1, {1: "Stays", 2: "Drops"}, {1: 0, 2: 1})
	race.mark_dnf(2, "disconnected")
	check(not race.all_over(), "the race continues for the driver who stays")
	var results: Array[Dictionary] = race.results()
	check(int(results[1]["pid"]) == 2 and bool(results[1]["dnf"]), "the dropped driver is ranked last as DNF")
	race.mark_dnf(1, "disconnected")
	check(race.all_over(), "with everyone DNF the race is over")
	await cleanup([track])


func test_time_limit_after_first_finish() -> void:
	var track: Track = _make_track()
	var race := NetRaceAuthority.new()
	race.setup(track, 1, {1: "Done", 2: "Stuck"}, {1: 0, 2: 1})
	race.driver(1).finished = true
	race._first_finish_t = 0.0
	race.tick(NetConfig.FINISH_WAIT_S + 0.1)
	check(race.all_over(), "cars still running after FINISH_WAIT_S are marked DNF by the server clock")
	await cleanup([track])
