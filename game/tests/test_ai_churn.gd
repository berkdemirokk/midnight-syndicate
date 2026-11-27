extends "res://tests/test_case.gd"
## AI churn (ai/ai_driver.gd): a car queued behind a stopped car is not a stuck event, and a car closing fast on a
## stopped car brakes in time (no car-to-car contact). The matrix numbers are in docs/perf/DRIVE_TELEMETRY.md.

const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const TestTrack = preload("res://tests/helpers/test_track.gd")
const HZ: float = 60.0
const START_H: float = 0.47  ## car origin height at rest, as in test_vehicle.gd
const QUEUE_LEAD_O: float = 100.0  ## m along the line, the stopped car
const QUEUE_FOLLOW_O: float = 86.0  ## m along the line, 14 m behind it, racing
const QUEUE_RUN_S: float = 8.0  ## time the queue stands: the stuck detector needs 2 s without progress
const QUEUE_MIN_GAP_M: float = 3.0  ## the follower may not reach the stopped car
const CLOSE_LEAD_O: float = 100.0
const CLOSE_FOLLOW_O: float = 60.0  ## 40 m behind the stopped car
const CLOSE_SPEED_MS: float = 25.0  ## m/s, about 90 km/h, toward the stopped car
const CLOSE_RUN_S: float = 6.0
const SIDE_M: float = 2.7  ## m, lateral offset of the blockers: car_width + side_clearance

var _contacts: int = 0


## An AI car; a disabled one sits still (its input is cleared) and is a stopped obstacle for the test.
func _make_car(skill: float, seed_value: int, ai_on: bool) -> ArcadeCar:
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	var d := AIDriver.new()
	d.name = "AIDriver"
	d.skill = skill
	d.lane_offset = 0.0
	d.noise_seed = seed_value
	d.enabled = ai_on
	car.add_child(d)
	return car


func _new_manager() -> RaceManager:
	var m := RaceManager.new()
	m.total_laps = 2
	add(m)
	return m


## Puts the car at offset o on the line, lat metres right of it, facing the race direction, at rest.
func _place(track: Track, car: ArcadeCar, o: float, lat: float = 0.0) -> void:
	var c: Vector3 = track.get_point_at(o)
	var t: Vector3 = track.get_tangent_at(o)
	var right: Vector3 = Vector3(-t.z, 0.0, t.x)
	car.reset_to(Transform3D(Basis(right, Vector3.UP, -t), c + right * lat + Vector3.UP * START_H))


func _wait_racing(manager: RaceManager) -> void:
	var ticks: int = 0
	while manager.state != RaceManager.State.RACING and ticks < roundi(6.0 * HZ):
		await frames(1)
		ticks += 1


func _on_hit(_impulse: float, _pos: Vector3) -> void:
	_contacts += 1


## A car queued behind a stopped car in its lane is held by the car ahead. That is a queue, not a wedge:
## it must not count as a stuck recovery, and it must stop short of the car ahead. Two stopped cars alongside
## the lead (2.7 m either side) close both sides, so the follower cannot pass and must queue.
func test_queued_car_is_not_stuck() -> void:
	var track: Track = TestTrack.build()
	add(track)
	var lead: ArcadeCar = _make_car(1.0, 1, false)
	var left: ArcadeCar = _make_car(1.0, 2, false)
	var right: ArcadeCar = _make_car(1.0, 3, false)
	var follow: ArcadeCar = _make_car(1.0, 4, true)
	var manager: RaceManager = _new_manager()
	var cars: Array[ArcadeCar] = [lead, left, right, follow]
	manager.setup(track, cars, null, PackedStringArray(["Lead", "Left", "Right", "Follow"]))
	_place(track, lead, QUEUE_LEAD_O)
	_place(track, left, QUEUE_LEAD_O, -SIDE_M)
	_place(track, right, QUEUE_LEAD_O, SIDE_M)
	_place(track, follow, QUEUE_FOLLOW_O)
	_contacts = 0
	follow.hit.connect(_on_hit)
	manager.start_countdown()
	await _wait_racing(manager)
	await frames(roundi(QUEUE_RUN_S * HZ))
	var driver: AIDriver = follow.get_node("AIDriver") as AIDriver
	var gap: float = track.get_progress(lead.global_position) - track.get_progress(follow.global_position)
	metric("queue_stuck_events", driver.stuck_count)
	metric("queue_gap_m", snappedf(gap, 0.01))
	check(driver.stuck_count == 0, "queued car counted as stuck %d times" % driver.stuck_count)
	check(gap > QUEUE_MIN_GAP_M, "queued car reached the stopped car (gap %.2f m)" % gap)
	var nodes: Array[Node] = [manager, lead, left, right, follow, track]
	await cleanup(nodes)


## A car closing fast on a stopped car in its lane brakes for the closing speed, so it does not hit it.
func test_closing_car_brakes_before_contact() -> void:
	var track: Track = TestTrack.build()
	add(track)
	var lead: ArcadeCar = _make_car(1.0, 1, false)
	var follow: ArcadeCar = _make_car(1.0, 2, true)
	var manager: RaceManager = _new_manager()
	var cars: Array[ArcadeCar] = [lead, follow]
	manager.setup(track, cars, null, PackedStringArray(["Lead", "Follow"]))
	_place(track, lead, CLOSE_LEAD_O)
	_place(track, follow, CLOSE_FOLLOW_O)
	_contacts = 0
	follow.hit.connect(_on_hit)
	manager.start_countdown()
	await _wait_racing(manager)
	follow.linear_velocity = track.get_tangent_at(CLOSE_FOLLOW_O) * -CLOSE_SPEED_MS
	await frames(roundi(CLOSE_RUN_S * HZ))
	metric("closing_contacts", _contacts)
	check(_contacts == 0, "closing car hit the stopped car %d times" % _contacts)
	var nodes: Array[Node] = [manager, lead, follow, track]
	await cleanup(nodes)
