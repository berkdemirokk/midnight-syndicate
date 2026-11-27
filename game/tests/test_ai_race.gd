extends "res://tests/test_case.gd"
## Racing AI, race manager and track acceptance tests (ai/ai_driver.gd, race/race_manager.gd, world/track.gd).
## Lap times and lateral offsets are recorded with metric(). Run at --fixed-fps 60 (physics ticks = frames).

const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const TestTrack = preload("res://tests/helpers/test_track.gd")
const HZ: float = 60.0
const START_H: float = 0.47  ## car origin height at rest, as in test_vehicle.gd
const MAX_RACE_S: float = 150.0  ## a race must end within this much simulated time
const LAP_LIMIT_S: float = 60.0
const WALK_STEP_M: float = 4.0  ## teleport step for the reversing test, below one gate spacing
const RUBBER_TOL: float = 0.0001
const OVERTAKE_RUN_S: float = 6.0
const OVERTAKE_MIN_SHIFT_M: float = 1.5  ## lane shift the chaser must reach to count as passing
const OVERTAKE_BLOCKER_O: float = 100.0  ## m along the line, parked car (start straight: the pass zone must not be a bend)
const OVERTAKE_CHASER_O: float = 70.0  ## m along the line, 30 m behind the parked car
const STUCK_HOLD_S: float = 3.0  ## car held still while racing; the detector needs 2.5 s
const STUCK_RUN_S: float = 8.0  ## time after release to drive on
const STUCK_MIN_FORWARD_M: float = 20.0
const WRONG_WAY_SPEED: float = 10.0  ## m/s set on the player car
const WRONG_WAY_FRAMES: int = 60  ## 1 s per phase

var _lap_log: Array[Dictionary] = []
var _finished_events: int = 0
var _results: Array[Dictionary] = []
var _ticks: Array[int] = []
var _race_started_events: int = 0
var _cars: Array[ArcadeCar] = []
var _starts: Array[Vector3] = []
var _moved_before_go: float = 0.0
var _wrong_events: int = 0
var _wrong_last: bool = false


func _make_car(skill: float, lane: float, seed_value: int = 1) -> ArcadeCar:
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	var d := AIDriver.new()
	d.name = "AIDriver"
	d.skill = skill
	d.lane_offset = lane
	d.noise_seed = seed_value
	car.add_child(d)
	return car


func _new_manager(laps: int) -> RaceManager:
	var m := RaceManager.new()
	m.total_laps = laps
	add(m)
	return m


func _wrap(d: float, length: float) -> float:
	return fposmod(d + length * 0.5, length) - length * 0.5


func _on_lap(car: ArcadeCar, lap: int, lap_time: float) -> void:
	_lap_log.append({"car": car, "lap": lap, "time": lap_time})


func _on_finished(results: Array[Dictionary]) -> void:
	_finished_events += 1
	_results = results


func _on_countdown_tick(n: int) -> void:
	_ticks.append(n)
	if n == 0:
		for i: int in _cars.size():
			_moved_before_go = maxf(_moved_before_go, _cars[i].global_position.distance_to(_starts[i]))


func _on_race_started() -> void:
	_race_started_events += 1


func _on_wrong_way(is_wrong: bool) -> void:
	_wrong_events += 1
	_wrong_last = is_wrong


## Puts the car at offset o on the line, facing the race direction, at rest.
func _place(track: Track, car: ArcadeCar, o: float) -> void:
	var c: Vector3 = track.get_point_at(o)
	var t: Vector3 = track.get_tangent_at(o)
	car.reset_to(Transform3D(Basis(Vector3(-t.z, 0.0, t.x), Vector3.UP, -t), c + Vector3.UP * START_H))


## Teleports the car along the line in small steps, one physics tick each, from offset `from_o` to `to_o`.
func _walk(track: Track, car: ArcadeCar, from_o: float, to_o: float) -> void:
	var dir: float = signf(to_o - from_o)
	var steps: int = roundi(absf(to_o - from_o) / WALK_STEP_M)
	for i: int in steps:
		_place(track, car, from_o + dir * WALK_STEP_M * float(i + 1))
		await frames(1)


func _wait_racing(manager: RaceManager) -> void:
	var ticks: int = 0
	while manager.state != RaceManager.State.RACING and ticks < roundi(6.0 * HZ):
		await frames(1)
		ticks += 1


func test_track_maths() -> void:
	var track: Track = TestTrack.build()
	add(track)
	var pts: PackedVector2Array = track.get_minimap_points()
	var chord: float = 0.0
	for i: int in pts.size():
		chord += pts[i].distance_to(pts[(i + 1) % pts.size()])
	metric("track_length_m", track.length)
	metric("track_samples", pts.size())
	check_range(track.length, 1100.0, 1400.0, "track length (m)")
	check_range(absf(track.length - chord) / track.length, 0.0, 0.01, "length vs summed sample distances, relative")

	var step: float = 10.0
	var prev: float = track.get_progress(track.get_point_at(0.0))
	var mono: bool = true
	var max_err: float = 0.0
	var o: float = step
	while o < track.length:
		var p: float = track.get_progress(track.get_point_at(o))
		var dp: float = fposmod(p - prev, track.length)
		if dp <= 0.0 or dp > 1.5 * step:
			mono = false
		max_err = maxf(max_err, absf(_wrap(p - o, track.length)))
		prev = p
		o += step
	check(mono, "get_progress does not increase steadily along the line")
	metric("progress_max_error_m", max_err)
	check_range(max_err, 0.0, 0.5, "progress vs walked offset (m)")

	var p_straight: float = track.get_progress(Vector3(0.0, 0.0, -100.0))
	var p_hairpin: float = track.get_progress(Vector3(276.0, 0.0, -248.0))
	var v_straight: float = track.get_target_speed(p_straight)
	var v_hairpin: float = track.get_target_speed(p_hairpin)
	metric("target_speed_straight_ms", v_straight)
	metric("target_speed_hairpin_ms", v_hairpin)
	metric("curvature_hairpin_radius_m", 1.0 / absf(track.get_curvature(p_hairpin)))
	check(v_hairpin < v_straight - 1.0, "hairpin target speed %.1f not below straight %.1f" % [v_hairpin, v_straight])

	var t: Vector3 = track.get_tangent_at(p_straight)
	check(t.z < -0.9, "race direction on the start straight is not -Z")
	var right: Vector3 = Vector3(-t.z, 0.0, t.x)
	check(right.x > 0.9, "right of the race direction is not +X")
	var c: Vector3 = track.get_point_at(p_straight)
	var lat_right: float = track.get_lateral_offset(c + right * 3.0)
	var lat_left: float = track.get_lateral_offset(c - right * 3.0)
	metric("lateral_3m_right_m", lat_right)
	metric("lateral_3m_left_m", lat_left)
	check_range(lat_right, 2.9, 3.1, "lateral offset 3 m right of the line")
	check_range(lat_left, -3.1, -2.9, "lateral offset 3 m left of the line")
	check(track.get_grid_transform(0).origin.z > 0.0, "grid slot 0 is not behind the start line")
	await cleanup([track])


func test_single_ai_two_laps() -> void:
	var track: Track = TestTrack.build()
	add(track)
	var car: ArcadeCar = _make_car(1.0, 0.0)
	var manager: RaceManager = _new_manager(2)
	manager.lap_completed.connect(_on_lap)
	var cars: Array[ArcadeCar] = [car]
	manager.setup(track, cars, null, PackedStringArray(["Solo"]))
	var driver: AIDriver = car.get_node("AIDriver") as AIDriver
	manager.start_countdown()
	var max_lat: float = 0.0
	var ticks: int = 0
	while manager.state != RaceManager.State.FINISHED and ticks < roundi(MAX_RACE_S * HZ):
		await frames(1)
		ticks += 1
		max_lat = maxf(max_lat, absf(track.get_lateral_offset(car.global_position)))
	check(manager.state == RaceManager.State.FINISHED, "single AI car did not finish 2 laps in %.0f s" % MAX_RACE_S)
	check(_lap_log.size() == 2, "single AI car: %d laps counted, expected 2" % _lap_log.size())
	var lap1: float = float(_lap_log[0]["time"]) if _lap_log.size() > 0 else 0.0
	var lap2: float = float(_lap_log[1]["time"]) if _lap_log.size() > 1 else 0.0
	metric("solo_lap1_s", lap1)
	metric("solo_lap2_s", lap2)
	metric("solo_max_abs_lateral_m", max_lat)
	metric("solo_stuck_events", driver.stuck_count)
	check_range(lap2, 1.0, LAP_LIMIT_S, "single AI car lap 2 time (s)")
	check(max_lat < track.width * 0.5, "single AI car left the track: max lateral %.2f m" % max_lat)
	check(driver.stuck_count == 0, "single AI car was stuck %d times" % driver.stuck_count)
	var nodes: Array[Node] = [manager, car, track]
	await cleanup(nodes)


func test_four_ai_race() -> void:
	var track: Track = TestTrack.build()
	add(track)
	var skills: Array[float] = [1.0, 0.95, 0.9, 0.85]
	var lanes: Array[float] = [-2.5, 2.5, 0.0, -4.5]
	var cars: Array[ArcadeCar] = []
	for i: int in 4:
		cars.append(_make_car(skills[i], lanes[i], i + 1))
	var manager: RaceManager = _new_manager(2)
	manager.lap_completed.connect(_on_lap)
	manager.race_finished.connect(_on_finished)
	manager.setup(track, cars, null, PackedStringArray(["Alpha", "Bravo", "Charlie", "Delta"]))
	manager.start_countdown()
	var min_up: Array[float] = [1.0, 1.0, 1.0, 1.0]
	var ticks: int = 0
	while manager.state != RaceManager.State.FINISHED and ticks < roundi(MAX_RACE_S * HZ):
		await frames(1)
		ticks += 1
		for i: int in 4:
			min_up[i] = minf(min_up[i], cars[i].global_transform.basis.y.y)
	check(manager.state == RaceManager.State.FINISHED, "4-car race did not finish within %.0f s" % MAX_RACE_S)
	check(_lap_log.size() == 8, "lap_completed fired %d times, expected 8" % _lap_log.size())
	check(_finished_events == 1, "race_finished fired %d times, expected 1" % _finished_events)
	check(_results.size() == 4, "race_finished gave %d results, expected 4" % _results.size())
	var last_time: float = -1.0
	for i: int in _results.size():
		var r: Dictionary = _results[i]
		var total: float = float(r["total_time"])
		check(int(r["position"]) == i + 1, "result %d has position %d" % [i + 1, int(r["position"])])
		check(total >= last_time, "results not sorted by total_time at position %d" % (i + 1))
		last_time = total
		metric("race_pos%d_total_s" % (i + 1), total)
		metric("race_pos%d_best_lap_s" % (i + 1), float(r["best_lap"]))
		if r["car"] == cars[0]:
			check(int(r["position"]) != 4, "skill 1.0 car finished last")
	for i: int in 4:
		metric("car%d_min_up_y" % i, min_up[i])
		check(min_up[i] > 0.5, "car %d went upside down (min up.y %.2f)" % [i, min_up[i]])
	var nodes: Array[Node] = [manager, track]
	for c: ArcadeCar in cars:
		nodes.append(c)
	await cleanup(nodes)


func test_countdown() -> void:
	var track: Track = TestTrack.build()
	add(track)
	_cars.clear()
	_starts.clear()
	for i: int in 4:
		_cars.append(_make_car(0.9, float(i) - 1.5, i + 1))
	var manager: RaceManager = _new_manager(2)
	manager.countdown_tick.connect(_on_countdown_tick)
	manager.race_started.connect(_on_race_started)
	var cars: Array[ArcadeCar] = []
	for c: ArcadeCar in _cars:
		cars.append(c)
	manager.setup(track, cars, null, PackedStringArray(["A", "B", "C", "D"]))
	for c: ArcadeCar in _cars:
		_starts.append(c.global_position)
	manager.start_countdown()
	var ticks: int = 0
	while _race_started_events == 0 and ticks < roundi(5.0 * HZ):
		await frames(1)
		ticks += 1
	check(_ticks == [3, 2, 1, 0], "countdown ticks %s, expected 3,2,1,0" % str(_ticks))
	check(_race_started_events == 1, "race_started fired %d times, expected 1" % _race_started_events)
	metric("countdown_moved_before_go_m", _moved_before_go)
	check_range(_moved_before_go, 0.0, 0.2, "car movement before GO (m)")
	var nodes: Array[Node] = [manager, track]
	for c: ArcadeCar in _cars:
		nodes.append(c)
	await cleanup(nodes)


## Reverses across the start line (offset 0) with no gate passed, then drives forward: only the full forward lap counts.
func test_reverse_across_start_adds_no_lap() -> void:
	var track: Track = TestTrack.build()
	add(track)
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	var manager: RaceManager = _new_manager(3)
	manager.lap_completed.connect(_on_lap)
	var cars: Array[ArcadeCar] = [car]
	manager.setup(track, cars, car, PackedStringArray(["Player"]))
	manager.start_countdown()
	await _wait_racing(manager)
	check(manager.state == RaceManager.State.RACING, "race did not reach RACING")
	var length: float = track.length
	# Forward across the line from just behind it: no gate has been passed, so no lap.
	await _walk(track, car, length - 40.0, 40.0 + length)
	check(_lap_log.is_empty(), "crossing the line forward with no gate passed added a lap")
	# Reverse back across the line: the car goes from 40 m past it to 40 m before it.
	await _walk(track, car, 40.0, -40.0)
	check(_lap_log.is_empty(), "reversing across the start line added %d lap(s)" % _lap_log.size())
	# Forward across it again, still no gate passed.
	await _walk(track, car, -40.0, 40.0)
	check(_lap_log.is_empty(), "crossing the line forward again added %d lap(s)" % _lap_log.size())
	# One full forward lap.
	await _walk(track, car, 40.0, 40.0 + length)
	check(_lap_log.size() == 1, "one forward lap after the reversal counted %d laps, expected 1" % _lap_log.size())
	var nodes: Array[Node] = [manager, car, track]
	await cleanup(nodes)


## Rubber band uses the race distance: a 700 m gap is past half a lap, where the old wrapped gap read as behind.
func test_rubber_band_uses_race_gap() -> void:
	var track: Track = TestTrack.build()
	add(track)
	var car: ArcadeCar = _make_car(1.0, 0.0, 1)
	var driver: AIDriver = car.get_node("AIDriver") as AIDriver
	driver.setup(track)
	check(absf(driver.get_rubber_band() - 1.0) < RUBBER_TOL, "rubber band not neutral before any gap is set")
	# gap (m), expected factor with rubber_band_max 0.08 and rubber_band_gap 150 m
	var gaps: Array[float] = [75.0, 225.0, 700.0, -225.0, -700.0]
	var expected: Array[float] = [1.0, 1.04, 1.08, 0.96, 0.92]
	for i: int in gaps.size():
		driver.set_reference_gap(gaps[i])
		var got: float = driver.get_rubber_band()
		metric("rubber_band_at_%dm" % int(gaps[i]), got)
		check(absf(got - expected[i]) < RUBBER_TOL, "rubber band at gap %.0f m is %.4f, expected %.4f" % [gaps[i], got, expected[i]])
	var nodes: Array[Node] = [car, track]
	await cleanup(nodes)


## A slower car 30 m ahead in our lane: the chaser must shift sideways to pass it.
func test_overtake_shifts_lane() -> void:
	var track: Track = TestTrack.build()
	add(track)
	var blocker: ArcadeCar = _make_car(0.8, 0.0, 2)
	var chaser: ArcadeCar = _make_car(1.0, 0.0, 3)
	var blocker_driver: AIDriver = blocker.get_node("AIDriver") as AIDriver
	blocker_driver.enabled = false  # parked on the line
	var chaser_driver: AIDriver = chaser.get_node("AIDriver") as AIDriver
	var traffic: Array[ArcadeCar] = [blocker, chaser]
	chaser_driver.setup(track)
	chaser_driver.set_traffic(traffic)
	_place(track, blocker, OVERTAKE_BLOCKER_O)
	_place(track, chaser, OVERTAKE_CHASER_O)
	chaser_driver.set_racing(true)
	var max_shift: float = 0.0
	for i: int in roundi(OVERTAKE_RUN_S * HZ):
		await frames(1)
		max_shift = maxf(max_shift, absf(track.get_lateral_offset(chaser.global_position)))
	metric("overtake_max_shift_m", max_shift)
	check(max_shift > OVERTAKE_MIN_SHIFT_M, "chaser did not shift lane to pass (max %.2f m)" % max_shift)
	check(max_shift < track.width * 0.5, "chaser left the track while passing: %.2f m" % max_shift)
	var nodes: Array[Node] = [blocker, chaser, track]
	await cleanup(nodes)


## A car held still while racing starts stuck recovery, then drives on once released.
func test_stuck_recovery() -> void:
	var track: Track = TestTrack.build()
	add(track)
	var car: ArcadeCar = _make_car(1.0, 0.0, 4)
	var manager: RaceManager = _new_manager(2)
	var cars: Array[ArcadeCar] = [car]
	manager.setup(track, cars, null, PackedStringArray(["Stuck"]))
	var driver: AIDriver = car.get_node("AIDriver") as AIDriver
	manager.start_countdown()
	await _wait_racing(manager)
	car.set_frozen_for_grid(true)
	await frames(roundi(STUCK_HOLD_S * HZ))
	var stuck_while_held: int = driver.stuck_count
	car.set_frozen_for_grid(false)
	var s0: float = track.get_progress(car.global_position)
	var forward: float = 0.0
	var s_prev: float = s0
	for i: int in roundi(STUCK_RUN_S * HZ):
		await frames(1)
		var s: float = track.get_progress(car.global_position, s_prev)
		forward += _wrap(s - s_prev, track.length)
		s_prev = s
	metric("stuck_events_held", stuck_while_held)
	metric("stuck_forward_after_release_m", forward)
	check(stuck_while_held >= 1, "held car never started stuck recovery")
	check(forward > STUCK_MIN_FORWARD_M, "car did not drive on after stuck recovery (forward %.1f m)" % forward)
	var nodes: Array[Node] = [manager, car, track]
	await cleanup(nodes)


## The player driving backwards along the line raises wrong_way_changed(true); driving forward clears it.
func test_wrong_way_signal() -> void:
	var track: Track = TestTrack.build()
	add(track)
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	var manager: RaceManager = _new_manager(3)
	manager.wrong_way_changed.connect(_on_wrong_way)
	manager.setup(track, [car], car, PackedStringArray(["Player"]))
	manager.start_countdown()
	await _wait_racing(manager)
	var t: Vector3 = track.get_tangent_at(track.get_progress(car.global_position))
	for i: int in WRONG_WAY_FRAMES:
		car.linear_velocity = t * WRONG_WAY_SPEED
		await frames(1)
	check(_wrong_events == 0, "wrong-way fired while driving forward")
	for i: int in WRONG_WAY_FRAMES:
		car.linear_velocity = -t * WRONG_WAY_SPEED
		await frames(1)
	check(_wrong_events == 1 and _wrong_last, "wrong-way did not fire when reversing (events %d)" % _wrong_events)
	for i: int in WRONG_WAY_FRAMES:
		car.linear_velocity = t * WRONG_WAY_SPEED
		await frames(1)
	check(_wrong_events == 2 and not _wrong_last, "wrong-way did not clear when driving forward (events %d)" % _wrong_events)
	var nodes: Array[Node] = [manager, car, track]
	await cleanup(nodes)


## Both reset candidates are occupied: no unchecked teleport, and retry succeeds once clear.
func test_reset_never_teleports_into_occupied_candidate() -> void:
	var track: Track = TestTrack.build()
	add(track)
	var car: ArcadeCar = _make_car(1.0, 0.0)
	var blocker_a: ArcadeCar = _make_car(0.8, 0.0)
	var blocker_b: ArcadeCar = _make_car(0.8, 0.0)
	var driver: AIDriver = car.get_node("AIDriver") as AIDriver
	driver.setup(track)
	driver.reset_probe_tries = 1
	driver.reset_advance_m = 4.0
	driver.reset_probe_step_m = 16.0
	var traffic: Array[ArcadeCar] = [car, blocker_a, blocker_b]
	driver.set_traffic(traffic)
	_place(track, car, 70.0)
	_place(track, blocker_a, 74.0)
	_place(track, blocker_b, 90.0)
	var before: Vector3 = car.global_position
	check(not driver._reset_to_line(), "all candidates occupied: refuse reset")
	check(car.global_position.distance_to(before) < 0.01, "no teleport to occupied spot")
	_place(track, blocker_b, 160.0)
	check(driver._reset_to_line(), "last candidate is now clear")
	check(absf(_wrap(track.get_progress(car.global_position) - 90.0, track.length)) < 1.0, "reset to checked second candidate")
	await cleanup([car, blocker_a, blocker_b, track])
