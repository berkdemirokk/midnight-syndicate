extends "res://tests/test_case.gd"
## Defence (ai/ai_driver.gd _defence_shift): a faster car 7.5 m behind us in our lane gets one lateral move toward its
## side, and the move never goes into a car alongside. Scripted on the flat test circuit, start straight heading -Z.

const TestTrack = preload("res://tests/helpers/test_track.gd")
const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const HZ: float = 60.0
const START_H: float = 0.47
const DEFENDER_O: float = 60.0  ## m along the line, on the start straight
const ATTACKER_GAP_M: float = 7.5  ## m behind the defender in our lane, inside the 8 m defence window
const ATTACKER_LANE_M: float = 1.0  ## m right of the line: the attacker is on the right
const DEFENDER_SPEED_MS: float = 10.0
const ATTACKER_SPEED_MS: float = 16.0
const WINDOW_S: float = 2.0
const MIN_DEFENCE_M: float = 0.3  ## commanded lateral move toward the attacker within the window (the car follows it with lag)


func _make_car(skill: float, lane: float, seed_value: int) -> ArcadeCar:
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


func _place(track: Track, car: ArcadeCar, o: float, lateral: float, speed: float) -> void:
	var c: Vector3 = track.get_point_at(o)
	var t: Vector3 = track.get_tangent_at(o)
	var right: Vector3 = Vector3(-t.z, 0.0, t.x)
	car.reset_to(Transform3D(Basis(right, Vector3.UP, -t), c + right * lateral + Vector3.UP * START_H))
	car.linear_velocity = t * speed


func test_defender_moves_once_toward_attacker() -> void:
	var track: Track = TestTrack.build()
	add(track)
	var defender: ArcadeCar = _make_car(0.8, 0.0, 4)
	var attacker: ArcadeCar = _make_car(1.0, ATTACKER_LANE_M, 5)
	var defender_driver: AIDriver = defender.get_node("AIDriver") as AIDriver
	var attacker_driver: AIDriver = attacker.get_node("AIDriver") as AIDriver
	var traffic: Array[ArcadeCar] = [defender, attacker]
	defender_driver.defence_shift = 1.5  ## the default is off
	defender_driver.setup(track)
	defender_driver.set_traffic(traffic)
	attacker_driver.setup(track)
	attacker_driver.set_traffic(traffic)
	_place(track, defender, DEFENDER_O, 0.0, DEFENDER_SPEED_MS)
	_place(track, attacker, DEFENDER_O - ATTACKER_GAP_M, ATTACKER_LANE_M, ATTACKER_SPEED_MS)
	defender_driver.set_racing(true)
	attacker_driver.set_racing(true)
	attacker_driver.enabled = false  # coasts straight on its lane, so the test sees only the defence
	var max_toward: float = 0.0
	var max_lateral: float = 0.0
	var contact: bool = false
	for i: int in roundi(WINDOW_S * HZ):
		await frames(1)
		max_toward = maxf(max_toward, defender_driver.get_defence_shift())
		max_lateral = maxf(max_lateral, track.get_lateral_offset(defender.global_position))
		if defender.get_colliding_bodies().has(attacker):
			contact = true
	metric("defence_commanded_shift_m", snappedf(max_toward, 0.01))
	metric("defence_car_lateral_m", snappedf(max_lateral, 0.01))
	check(max_toward >= MIN_DEFENCE_M, "defender did not command a move toward the attacker: %.2f m" % max_toward)
	check(not contact, "defender touched the attacker during the defence move")
	var nodes: Array[Node] = [defender, attacker, track]
	await cleanup(nodes)
