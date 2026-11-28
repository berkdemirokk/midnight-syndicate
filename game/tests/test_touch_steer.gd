extends "res://tests/test_case.gd"
## WP-A1: touch steer reaches 90 % lock within a fixed tick budget at 60 and 200 km/h.
## The keyboard ramp must keep its numbers. _update_steer is called directly with a fixed delta.

const FlatWorld = preload("res://tests/helpers/flat_world.gd")
const DT: float = 1.0 / 60.0
const LOCK: float = 0.9
const MAX_TICKS: int = 60
const TOUCH_LIMIT_60_KMH: int = 9
const TOUCH_LIMIT_200_KMH: int = 15

var _car: ArcadeCar = null
var _driver: PlayerDriver = null
var _nodes: Array[Node] = []


func _rig() -> void:
	_nodes.append(add(FlatWorld.make_ground()))
	_car = ArcadeCar.new()
	_car.position = Vector3(0.0, 0.8, 0.0)
	_driver = PlayerDriver.new()
	_car.add_child(_driver)
	_nodes.append(add(_car))
	_driver.enabled = false


## Ticks of _update_steer until steer reaches LOCK, with touch or the keyboard holding full right.
func _ticks_to_lock(kmh: float, touch: bool) -> int:
	_car.speed_kmh = kmh
	_driver.steer = 0.0
	_driver.set_touch_steer(1.0 if touch else 0.0)
	if not touch:
		Input.action_press("steer_right")
	var n: int = 0
	while n < MAX_TICKS and _driver.steer < LOCK:
		_driver._update_steer(DT)
		n += 1
	Input.action_release("steer_right")
	_driver.set_touch_steer(0.0)
	return n


## The keyboard ramp as it was before WP-A1, computed from the driver's exports.
func _keyboard_reference_ticks(kmh: float) -> int:
	var high: float = clampf(kmh / _driver.speed_norm_kmh, 0.0, 1.0)
	var rate: float = lerpf(_driver.turn_rate_low, _driver.turn_rate_high, high)
	var s: float = 0.0
	var n: int = 0
	while n < MAX_TICKS and s < LOCK:
		s = move_toward(s, 1.0, rate * DT)
		n += 1
	return n


func test_touch_reaches_lock_fast_at_every_speed() -> void:
	_rig()
	var t60: int = _ticks_to_lock(60.0, true)
	var t200: int = _ticks_to_lock(200.0, true)
	metric("touch_ticks_60kmh", t60)
	metric("touch_ticks_200kmh", t200)
	check(t60 <= TOUCH_LIMIT_60_KMH, "touch ticks to 90 %% lock at 60 km/h = %d, expected <= %d" % [t60, TOUCH_LIMIT_60_KMH])
	check(t200 <= TOUCH_LIMIT_200_KMH, "touch ticks to 90 %% lock at 200 km/h = %d, expected <= %d" % [t200, TOUCH_LIMIT_200_KMH])
	await cleanup(_nodes)
	_nodes.clear()


func test_keyboard_ramp_unchanged() -> void:
	_rig()
	var pinned: Dictionary = {60.0: 11, 200.0: 17}  # pre-WP-A1 numbers from PRODUCTION_PLAN.md WP-A1
	for kmh: float in [60.0, 200.0]:
		var got: int = _ticks_to_lock(kmh, false)
		var want: int = _keyboard_reference_ticks(kmh)
		metric("keyboard_ticks_%dkmh" % int(kmh), got)
		check(got == want, "keyboard ticks to 90 %% lock at %d km/h = %d, expected %d" % [int(kmh), got, want])
		check(got == int(pinned[kmh]), "keyboard ticks at %d km/h = %d, pinned %d" % [int(kmh), got, int(pinned[kmh])])
	await cleanup(_nodes)
	_nodes.clear()
