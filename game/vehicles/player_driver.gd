class_name PlayerDriver
extends Node
## Writes car.input every physics tick from the keyboard, the left stick, tilt or the touch setters.
## Keyboard steering ramps toward its target; the stick is used directly. Options come from the
## Settings autoload (auto_accelerate, steering_mode) when it exists, otherwise from the fallbacks.

signal reset_requested

const MODE_TILT: String = "tilt"
const PAD_DEVICE: int = 0
const STICK_AXIS: int = JOY_AXIS_LEFT_X
const MIN_DIV: float = 0.0001  ## divisor floor, not a tunable

@export var enabled: bool = true
@export var car_path: NodePath  ## empty = the parent node, which must be an ArcadeCar
@export var auto_accelerate_fallback: bool = true  ## used when Settings has no auto_accelerate
@export var steering_mode_fallback: String = "buttons"  ## buttons | tilt
@export_group("Keyboard steering")
@export var turn_rate_low: float = 6.0  ## steer units per second at standstill
@export var turn_rate_high: float = 2.2  ## steer units per second at speed_norm_kmh and above
@export var centre_rate_mult: float = 2.5  ## returning to centre is this many times faster than turning in
@export var speed_norm_kmh: float = 286.0  ## speed at which turn_rate_high applies
@export_group("Stick")
@export var stick_deadzone: float = 0.15
@export var stick_exponent: float = 1.6
@export_group("Tilt")
@export var tilt_deadzone: float = 0.05  ## fraction of tilt_full_ms2
@export var tilt_full_ms2: float = 4.0  ## accelerometer reading (m/s^2) that gives full steer
@export var tilt_exponent: float = 1.4
@export var tilt_invert: bool = false

## Steer written to car.input (-1 left .. +1 right). Read by tests and the HUD.
var steer: float = 0.0
var touch_steer: float = 0.0
var touch_brake: bool = false
var touch_nitro: bool = false
var touch_handbrake: bool = false

var _car: ArcadeCar = null
var _settings: Node = null
var _tilt_neutral: Vector3 = Vector3.ZERO
var _tilt_calibrated: bool = false


func _ready() -> void:
	if not car_path.is_empty():
		_car = get_node_or_null(car_path) as ArcadeCar
	else:
		_car = get_parent() as ArcadeCar
	if _car == null:
		push_error("PlayerDriver needs an ArcadeCar as its parent or car_path")
	_settings = get_node_or_null("/root/Settings")


func _physics_process(delta: float) -> void:
	if _car == null:
		return
	var vi: VehicleInput = _car.input
	if not enabled:
		vi.clear()
		steer = 0.0
		return
	var brake_in: float = maxf(Input.get_action_strength("brake"), 1.0 if touch_brake else 0.0)
	var throttle: float = 0.0
	if brake_in <= 0.0:
		throttle = 1.0 if _auto_accelerate() else Input.get_action_strength("accelerate")
	vi.throttle = throttle
	vi.brake = brake_in
	vi.steer = _update_steer(delta)
	vi.handbrake = touch_handbrake or Input.is_action_pressed("handbrake")
	vi.nitro = touch_nitro or Input.is_action_pressed("nitro")
	if Input.is_action_just_pressed("reset_car"):
		reset_requested.emit()


## Touch zones (TouchControls) call these every time a finger goes down or up.
func set_touch_steer(value: float) -> void:
	touch_steer = clampf(value, -1.0, 1.0)


func set_touch_brake(on: bool) -> void:
	touch_brake = on


func set_touch_nitro(on: bool) -> void:
	touch_nitro = on


func set_touch_handbrake(on: bool) -> void:
	touch_handbrake = on


## Sets the neutral tilt to the device's current pose. Also runs once automatically.
func calibrate_tilt() -> void:
	_tilt_neutral = Input.get_accelerometer()
	_tilt_calibrated = true


func _update_steer(delta: float) -> float:
	if _setting_str("steering_mode", steering_mode_fallback) == MODE_TILT:
		steer = _tilt_steer()
		return steer
	var stick: float = _shape(Input.get_joy_axis(PAD_DEVICE, STICK_AXIS), stick_deadzone, stick_exponent)
	if stick != 0.0:
		steer = stick
		return steer
	var target: float = touch_steer
	if target == 0.0:
		target = (1.0 if Input.is_action_pressed("steer_right") else 0.0) \
			- (1.0 if Input.is_action_pressed("steer_left") else 0.0)
	var high: float = clampf(_car.speed_kmh / maxf(speed_norm_kmh, MIN_DIV), 0.0, 1.0)
	var rate: float = lerpf(turn_rate_low, turn_rate_high, high)
	if target == 0.0:
		rate *= centre_rate_mult
	steer = move_toward(steer, target, rate * delta)
	return steer


func _tilt_steer() -> float:
	var acc: Vector3 = Input.get_accelerometer()
	if acc.length_squared() < MIN_DIV:  # no sensor reports zero
		return 0.0
	if not _tilt_calibrated:
		calibrate_tilt()
	var v: float = clampf((acc.x - _tilt_neutral.x) / maxf(tilt_full_ms2, MIN_DIV), -1.0, 1.0)
	if tilt_invert:
		v = -v
	return _shape(v, tilt_deadzone, tilt_exponent)


## Deadzone with rescale to 0..1, then a power curve for finer control near centre.
static func _shape(v: float, deadzone: float, exponent: float) -> float:
	var a: float = absf(v)
	if a <= deadzone:
		return 0.0
	var n: float = clampf((a - deadzone) / maxf(1.0 - deadzone, MIN_DIV), 0.0, 1.0)
	return signf(v) * pow(n, exponent)


func _auto_accelerate() -> bool:
	return bool(_setting("auto_accelerate", auto_accelerate_fallback))


func _setting_str(key: String, fallback: String) -> String:
	return str(_setting(key, fallback))


func _setting(key: String, fallback: Variant) -> Variant:
	if _settings == null:
		return fallback
	var v: Variant = _settings.get(key)
	return fallback if v == null else v
