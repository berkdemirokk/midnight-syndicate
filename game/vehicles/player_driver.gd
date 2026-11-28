class_name PlayerDriver
extends Node
## Writes car.input every physics tick from the keyboard, the left stick, tilt or the touch setters.
## Keyboard steering ramps toward its target; the stick is used directly. Options come from the
## Settings autoload (auto_accelerate, steering_mode) when it exists, otherwise from the fallbacks.
## Assist mode adds a capped steer toward the racing line on top of the manual input (WP-A4).

signal reset_requested

const MODE_TILT: String = "tilt"
const MODE_ASSIST: String = "assist"
const ASSIST_LOOK_M: float = 30.0  ## m, the racing line point the assist steers at. Plan said 12 m: that gave 21 body contacts on bogaz (dev PC, 2026-11-28); 30 m gives 2. shortcut: fixed look-ahead, not speed-scaled; upgrade: scale with speed if the tuning shows a need
const ASSIST_SPEED_AHEAD_S: float = 0.6  ## s, the speed target is also read this far ahead (as AIDriver does)
const ASSIST_SPEED_AHEAD_M: float = 40.0  ## m, cap of that look-ahead
const ASSIST_THROTTLE_GAIN: float = 0.5  ## throttle per m/s below the target (AIDriver's gain)
const ASSIST_BRAKE_GAIN: float = 0.2  ## brake per m/s above the target (AIDriver's gain)
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
@export_group("Touch steering")
@export var touch_turn_rate: float = 14.0  ## steer units per second toward a touch zone, the same at every speed
@export_group("Stick")
@export var stick_deadzone: float = 0.15
@export var stick_exponent: float = 1.6
@export_group("Tilt")
@export var tilt_deadzone: float = 0.05  ## fraction of tilt_full_ms2
@export var tilt_full_ms2: float = 4.0  ## accelerometer reading (m/s^2) that gives full steer
@export var tilt_exponent: float = 1.4
@export var tilt_invert: bool = false
@export_group("Steer assist")
@export var assist_cap_deg: float = 6.0  ## largest wheel angle the assist adds (degrees); manual input adds on top

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
var _track: Track = null  ## for assist mode, found once by _find_track
var _track_searched: bool = false
var _track_s: float = -1.0  ## track progress hint for assist mode (-1 = search the whole line)


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
	if _setting_str("steering_mode", steering_mode_fallback) == MODE_ASSIST:
		var sp: Vector2 = _assist_speed()  # without it a zero-input lap ends in the walls at top speed
		throttle = minf(throttle, sp.x)
		brake_in = maxf(brake_in, sp.y)
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
	var mode: String = _setting_str("steering_mode", steering_mode_fallback)
	if mode == MODE_TILT:
		steer = _tilt_steer()
		return steer
	var manual: float = _manual_steer(delta)
	if mode == MODE_ASSIST:
		return clampf(manual + _assist_steer(), -1.0, 1.0)  # steer keeps the manual value only (ramp state)
	return manual


func _manual_steer(delta: float) -> float:
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
	if touch_steer != 0.0:
		rate = touch_turn_rate  # no speed cap: touch must reach lock fast at every speed
	if target == 0.0:
		rate *= centre_rate_mult
	steer = move_toward(steer, target, rate * delta)
	return steer


## Pure pursuit to the racing line ASSIST_LOOK_M ahead, the same geometry as AIDriver, capped at assist_cap_deg of wheel angle.
func _assist_steer() -> float:
	if not _ensure_track() or _car.spec == null:
		return 0.0
	var pos: Vector3 = _car.global_position
	var ahead: float = _track_progress() + ASSIST_LOOK_M
	var t: Vector3 = _track.get_tangent_at(ahead)
	var target: Vector3 = _track.get_point_at(ahead) + Vector3(-t.z, 0.0, t.x) * _track.get_line_offset(ahead)
	var b: Basis = _car.global_transform.basis
	var fwd: Vector3 = Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var rgt: Vector3 = Vector3(b.x.x, 0.0, b.x.z).normalized()
	var d: Vector3 = target - pos
	d.y = 0.0
	var lx: float = d.dot(rgt)
	var lz: float = d.dot(fwd)
	var ld2: float = maxf(lx * lx + lz * lz, MIN_DIV)
	var spec: CarSpec = _car.spec
	var top_ms: float = maxf(spec.top_speed_kmh / 3.6, MIN_DIV)
	var lock_deg: float = lerpf(spec.steer_angle_low_deg, spec.steer_angle_high_deg, clampf(_car.forward_speed / top_ms, 0.0, 1.0))
	var wheel: float = atan(2.0 * spec.wheelbase * lx / ld2)
	var cap: float = deg_to_rad(assist_cap_deg)
	return clampf(clampf(wheel, -cap, cap) / deg_to_rad(maxf(lock_deg, MIN_DIV)), -1.0, 1.0)


## Throttle and brake that hold the autopilot's target speed: x = throttle cap, y = brake (assist mode only).
func _assist_speed() -> Vector2:
	if not _ensure_track():
		return Vector2(1.0, 0.0)
	var s: float = _track_progress()
	var v: float = maxf(_car.forward_speed, 0.0)
	var want: float = minf(_track.get_line_speed(s), _track.get_line_speed(s + clampf(ASSIST_SPEED_AHEAD_S * v, 0.0, ASSIST_SPEED_AHEAD_M)))
	var err: float = want - v
	if err >= 0.0:
		return Vector2(clampf(err * ASSIST_THROTTLE_GAIN, 0.0, 1.0), 0.0)
	return Vector2(0.0, clampf(-err * ASSIST_BRAKE_GAIN, 0.0, 1.0))


func _track_progress() -> float:
	_track_s = _track.get_progress(_car.global_position, _track_s)
	return _track_s


func _ensure_track() -> bool:
	if not _track_searched:
		_track_searched = true
		_track = _find_track(get_tree().root)  # shortcut: one tree scan, race_scene does not pass the track; upgrade: pass it from race_scene
	return _track != null and _car != null


func _find_track(n: Node) -> Track:
	if n is Track:
		return n as Track
	for c: Node in n.get_children():
		var f: Track = _find_track(c)
		if f != null:
			return f
	return null


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
