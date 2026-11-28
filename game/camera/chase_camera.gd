class_name ChaseCamera
extends Camera3D
## Follows an ArcadeCar. The chase offsets (travel direction, distance, drift swing) are critically
## damped springs, so the camera trails the car's direction, not its position. Runs in _process and
## reads the car with get_global_transform_interpolated(); the camera has physics interpolation off.
## Wall raycasts in _physics_process pull the distance in and cap the height (ceiling) and the
## lateral swing (side walls, parapets); the spring smooths the distance pull.
## Corner look-into and roll follow the car's yaw rate. ORBIT is the grid and the finish camera.

enum Mode { CHASE, HOOD, ORBIT }

const MIN_DIV: float = 0.0001  ## divisor floor, not a tunable
const MIN_BLEND_SPEED_MS: float = 0.5  ## below this speed the car's facing alone sets the direction
const MIN_DIR_LEN_SQ: float = 0.000001  ## numeric guard for a near-zero blended direction
const MIN_CAMERA_HEIGHT_M: float = 0.2  ## lowest camera height above the car origin under a ceiling
const KICK_CLOCK_IDLE_S: float = 1000.0  ## starts the nitro kick clock far past its end
const NITRO_PUNCH_S: float = 0.18  ## time constant of the nitro ignition FOV punch
const MAX_HFOV_DEG: float = 125.0  ## horizontal FOV ceiling, whatever the aspect

@export var target: ArcadeCar: set = set_target
@export var mode: Mode = Mode.CHASE
@export_group("Chase")
@export var distance_rest_m: float = 4.5
@export var distance_top_m: float = 5.9
@export var height_m: float = 1.18
@export var look_ahead_m: float = 9.0
@export var look_height_m: float = 0.85
@export var velocity_blend: float = 0.5  ## max weight of the travel direction against the facing
@export var velocity_full_ms: float = 25.0  ## speed at which velocity_blend is fully applied
@export var offset_smooth_s: float = 0.2  ## critically damped smoothing time of the offsets
@export var drift_swing_m: float = 1.2
@export var drift_swing_norm_deg: float = 30.0
@export var fallback_top_speed_kmh: float = 286.0  ## used when the car has no spec
@export var min_distance_m: float = 3.0
@export_group("Look, roll and speed feel")
@export var look_inside_m: float = 2.2  ## look point shift toward the inside of a corner, at full yaw
@export var look_smooth_s: float = 0.35  ## time constant of the look shift
@export var yaw_full_rad_s: float = 0.6  ## yaw rate at which look shift and roll reach full strength
@export var max_roll_deg: float = 2.5  ## camera roll into a turn, chase mode only
@export var roll_smooth_s: float = 0.4
@export var speed_drop_m: float = 0.06  ## camera lowered by this much at top speed
@export var speed_shake_m: float = 0.012  ## high-frequency shake amplitude at full shake speed
@export var speed_shake_from_kmh: float = 150.0
@export var speed_shake_full_kmh: float = 240.0
@export var speed_shake_hz: float = 35.0
@export var nitro_kick_back_m: float = 0.85  ## camera pushed back on nitro ignition, eased to 0
@export var nitro_kick_back_s: float = 1.1
@export_group("Lens")
@export var fov_rest: float = 62.0
@export var fov_top: float = 72.0
@export var nitro_fov_kick: float = 6.0
@export var nitro_kick_rate: float = 9.0  ## 1/s
@export var fov_rate: float = 3.0  ## 1/s
@export var max_hfov_gain_deg: float = 14.0  ## horizontal FOV allowed above the rest lens, so wide phones keep their edges
@export var nitro_punch_deg: float = 4.0  ## FOV spike on nitro ignition, gone in about half a second
@export_group("Shake")
@export var max_shake_m: float = 0.35
@export var shake_hz: float = 16.0
@export var trauma_decay: float = 1.2  ## per second
@export var nitro_trauma: float = 0.12
@export var hit_impulse_full: float = 20000.0  ## impulse that adds full hit trauma
@export var hit_trauma_max: float = 0.8
@export_group("Wall")
@export var wall_mask: int = 1  ## world layer
@export var wall_margin_m: float = 0.3
@export var wall_ray_height_m: float = 0.5
@export var side_probe_m: float = 2.0  ## lateral reach of the side-wall probes
@export var ceiling_probe_m: float = 2.0  ## how far above the camera the ceiling probe looks
@export_group("Hood and orbit")
@export var hood_offset: Vector3 = Vector3(0.0, 0.5, -0.6)
@export var hood_look_local: Vector3 = Vector3(0.0, 0.4, -30.0)
@export var orbit_radius_m: float = 6.5
@export var orbit_height_m: float = 0.95
@export var orbit_rate_rad_s: float = 0.09
@export var orbit_look_height_m: float = 0.55
@export var orbit_fov_deg: float = 38.0  ## long lens for the grid and finish orbit
@export_group("Grid intro")
@export var intro_fov_deg: float = 52.0  ## wide lens at the start of the intro, eased to the live lens

var trauma: float = 0.0  ## 0..1, shake strength is trauma squared
var nitro_kick: float = 0.0  ## 0..1, eased nitro state that drives the FOV kick
var kick_back_m: float = 0.0  ## current nitro push-back distance, eased to 0
var look_side: float = 0.0  ## smoothed corner look: +1 shifts right, -1 shifts left
var roll_rad: float = 0.0  ## smoothed roll; negative leans the camera left

var _settings: Node = null
var _initialised: bool = false
var _dir: Vector3 = Vector3(0.0, 0.0, -1.0)  ## smoothed travel direction, flat
var _dir_vel: Vector3 = Vector3.ZERO
var _off: Vector3 = Vector3.ZERO  ## smoothed offsets: x = distance behind, y = lateral swing
var _off_vel: Vector3 = Vector3.ZERO
var _wall_limit: float = INF  ## distance behind the car where a wall stops the camera
var _orbit_limit: float = INF  ## ORBIT radius where a wall stops the camera
var _ceiling_height_m: float = INF  ## camera height above the car origin where a ceiling stops it
var _side_limit_right_m: float = INF  ## lateral swing to the right before a wall
var _side_limit_left_m: float = INF  ## lateral swing to the left before a wall
var _fov_now: float = 62.0
var _shake_clock: float = 0.0
var _kick_clock: float = KICK_CLOCK_IDLE_S
var _orbit_angle: float = 0.0
var _ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()  ## reused every physics tick
var _exclude: Array[RID] = []  ## the car's RID, kept out of the wall ray
var _intro_t: float = -1.0  ## seconds into the grid intro, -1 when none runs
var _intro_s: float = 0.0
var _intro_from_pos: Vector3 = Vector3.ZERO
var _intro_from_look: Vector3 = Vector3.ZERO


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_settings = get_node_or_null("/root/Settings")
	_fov_now = fov_rest
	fov = fov_rest
	if is_instance_valid(target):
		snap()


## Moves the hit and nitro connections to the new car, so a target set at any time gets trauma.
func set_target(car: ArcadeCar) -> void:
	if is_instance_valid(target):
		if target.hit.is_connected(_on_car_hit):
			target.hit.disconnect(_on_car_hit)
		if target.nitro_started.is_connected(_on_nitro_started):
			target.nitro_started.disconnect(_on_nitro_started)
	target = car
	_exclude.clear()
	if is_instance_valid(target):
		target.hit.connect(_on_car_hit)
		target.nitro_started.connect(_on_nitro_started)
		_exclude.append(target.get_rid())
	_ray.exclude = _exclude


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_toggle"):
		toggle_mode()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(target):
		return
	var xf: Transform3D = target.global_transform
	var dir: Vector3 = _goal_dir(xf)
	var right: Vector3 = dir.cross(Vector3.UP)
	var base: float = lerpf(distance_rest_m, distance_top_m, _speed_t()) + kick_back_m
	var rear: Vector3 = xf.origin - dir * base
	var hit: Dictionary = _cast(xf.origin + Vector3.UP * wall_ray_height_m, rear + Vector3.UP * height_m)
	_wall_limit = INF
	if not hit.is_empty():
		var hp: Vector3 = hit["position"]
		_wall_limit = maxf((hp - xf.origin).dot(-dir) - wall_margin_m, 0.0)
	_ceiling_height_m = INF
	var roof: Dictionary = _cast(rear + Vector3.UP * wall_ray_height_m, rear + Vector3.UP * (height_m + ceiling_probe_m))
	if not roof.is_empty():
		var roof_y: float = (roof["position"] as Vector3).y
		_ceiling_height_m = maxf(roof_y - xf.origin.y - wall_margin_m, MIN_CAMERA_HEIGHT_M)
	_side_limit_right_m = _side_limit(xf.origin, right)
	_side_limit_left_m = _side_limit(xf.origin, -right)
	_orbit_limit = INF
	if mode == Mode.ORBIT:
		var ohit: Dictionary = _cast(xf.origin + Vector3.UP * wall_ray_height_m, _orbit_point(xf, orbit_radius_m))
		if not ohit.is_empty():
			var op: Vector3 = ohit["position"]
			_orbit_limit = maxf(Vector2(op.x - xf.origin.x, op.z - xf.origin.z).length() - wall_margin_m, 0.0)


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var xf: Transform3D = target.get_global_transform_interpolated()
	trauma = maxf(0.0, trauma - trauma_decay * delta)
	_shake_clock += delta
	_kick_clock += delta
	_orbit_angle += orbit_rate_rad_s * delta
	_update_lens(delta)
	_update_feel(delta)
	if _intro_t >= 0.0:
		_process_intro(xf, delta)
		return
	var pos: Vector3
	match mode:
		Mode.HOOD:
			pos = xf * hood_offset
		Mode.ORBIT:
			pos = _orbit_pos(xf)
		_:
			_step_chase(xf, delta)
			pos = _chase_pos(xf, _dir, _off)
	global_position = pos
	look_at(_look_point(xf), Vector3.UP)
	_apply_roll()
	var b: Basis = global_transform.basis
	global_position = pos + _shake_offset(b) + _speed_shake_offset(b)


## Where the camera should be right now, without smoothing or shake.
func compute_ideal_position() -> Vector3:
	if not is_instance_valid(target):
		return global_position
	var xf: Transform3D = target.get_global_transform_interpolated()
	match mode:
		Mode.HOOD:
			return xf * hood_offset
		Mode.ORBIT:
			return _orbit_pos(xf)
	return _chase_pos(xf, _goal_dir(xf), _goal_offset())


## Teleports to the ideal pose and drops all smoothing state.
func snap() -> void:
	if not is_instance_valid(target):
		return
	var xf: Transform3D = target.get_global_transform_interpolated()
	_dir = _goal_dir(xf)
	_off = _goal_offset()
	_dir_vel = Vector3.ZERO
	_off_vel = Vector3.ZERO
	_initialised = true
	nitro_kick = 1.0 if target.nitro_active else 0.0
	_fov_now = orbit_fov_deg if mode == Mode.ORBIT else compute_base_fov() + nitro_fov_kick * nitro_kick * _motion_gain()
	fov = minf(_fov_now, fov_cap_deg())
	global_position = compute_ideal_position()
	look_at(_look_point(xf), Vector3.UP)


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	snap()


## In-race toggle between CHASE and HOOD. ORBIT is entered only through set_mode().
func toggle_mode() -> void:
	set_mode(Mode.HOOD if mode == Mode.CHASE else Mode.CHASE)


## Results-screen camera: a slow orbit around the car (ORBIT). Call when the race finishes.
func start_finish_orbit() -> void:
	set_mode(Mode.ORBIT)


## Grid intro: moves from from_pos (looking at from_look) to the live chase pose over duration_s, then hands
## over to CHASE. Both ends use the same smoothed chase state as CHASE mode, so the hand-over does not pop.
func start_grid_intro(from_pos: Vector3, from_look: Vector3, duration_s: float) -> void:
	_intro_from_pos = from_pos
	_intro_from_look = from_look
	_intro_s = maxf(duration_s, MIN_DIV)
	mode = Mode.CHASE
	snap()  ## resets the smoothed direction and offset, so the chase state the intro hands over to is current
	_intro_t = 0.0


func intro_active() -> bool:
	return _intro_t >= 0.0


## 0..1 through the grid intro, 1 when none runs.
func intro_progress() -> float:
	return clampf(_intro_t / _intro_s, 0.0, 1.0) if _intro_t >= 0.0 else 1.0


func _process_intro(xf: Transform3D, delta: float) -> void:
	_intro_t = minf(_intro_t + delta, _intro_s)
	_step_chase(xf, delta)
	var w: float = smoothstep(0.0, 1.0, _intro_t / _intro_s)
	global_position = _intro_from_pos.lerp(_chase_pos(xf, _dir, _off), w)
	look_at(_intro_from_look.lerp(_look_point(xf), w), Vector3.UP)
	_apply_roll()
	fov = minf(lerpf(intro_fov_deg, _fov_now, w), fov_cap_deg())
	if _intro_t >= _intro_s:
		_intro_t = -1.0


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## FOV for the current speed, before the nitro kick.
func compute_base_fov() -> float:
	return lerpf(fov_rest, fov_top, _speed_t())


## Vertical FOV cap: horizontal FOV may grow at most max_hfov_gain_deg past the rest lens.
func fov_cap_deg() -> float:
	var sz: Vector2 = get_viewport().get_visible_rect().size
	var asp: float = sz.x / maxf(sz.y, 1.0)
	var rest_h: float = 2.0 * atan(tan(deg_to_rad(fov_rest) * 0.5) * asp)
	var cap_h: float = minf(rest_h + deg_to_rad(max_hfov_gain_deg), deg_to_rad(MAX_HFOV_DEG))
	return rad_to_deg(2.0 * atan(tan(cap_h * 0.5) / asp))


func _on_car_hit(impulse: float, _world_pos: Vector3) -> void:
	add_trauma(minf(impulse / maxf(hit_impulse_full, MIN_DIV), hit_trauma_max))


func _on_nitro_started() -> void:
	add_trauma(nitro_trauma)
	_kick_clock = 0.0


## One physics-state ray from from to to; the result dictionary is empty on no hit.
func _cast(from: Vector3, to: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = to
	_ray.collision_mask = wall_mask
	return get_world_3d().direct_space_state.intersect_ray(_ray)


## How far the camera may swing along side (a unit vector) before a wall, in metres from the car.
func _side_limit(origin: Vector3, side: Vector3) -> float:
	var hit: Dictionary = _cast(origin + Vector3.UP * wall_ray_height_m, origin + Vector3.UP * height_m + side * side_probe_m)
	if hit.is_empty():
		return INF
	var hp: Vector3 = hit["position"]
	return maxf((hp - origin).dot(side) - wall_margin_m, 0.0)


## Smoothed look shift, roll and nitro push-back, all frame-rate independent.
func _update_feel(delta: float) -> void:
	var kick_t: float = clampf(_kick_clock / maxf(nitro_kick_back_s, MIN_DIV), 0.0, 1.0)
	kick_back_m = nitro_kick_back_m * (1.0 - smoothstep(0.0, 1.0, kick_t))
	var yaw_norm: float = clampf(target.angular_velocity.y / maxf(yaw_full_rad_s, MIN_DIV), -1.0, 1.0)
	# Positive yaw turns left, so the inside of the corner is -right.
	look_side = lerpf(look_side, -yaw_norm, 1.0 - exp(-delta / maxf(look_smooth_s, MIN_DIV)))
	var roll_goal: float = 0.0
	if mode == Mode.CHASE:
		roll_goal = -yaw_norm * deg_to_rad(max_roll_deg)
	roll_rad = lerpf(roll_rad, roll_goal, 1.0 - exp(-delta / maxf(roll_smooth_s, MIN_DIV)))


func _apply_roll() -> void:
	if absf(roll_rad) < MIN_DIV * MIN_DIV:
		return
	var t: Transform3D = global_transform
	t.basis = Basis(-t.basis.z, roll_rad) * t.basis
	global_transform = t


## Critically damped spring on the offsets (Unity SmoothDamp form with the exact exponential).
func _step_chase(xf: Transform3D, delta: float) -> void:
	var goal_dir: Vector3 = _goal_dir(xf)
	var goal_off: Vector3 = _goal_offset()
	if not _initialised:
		snap()
		return
	var w: float = 2.0 / maxf(offset_smooth_s, MIN_DIV)
	var e: float = exp(-w * delta)
	var d0: Vector3 = _dir - goal_dir
	var t0: Vector3 = (_dir_vel + d0 * w) * delta
	_dir_vel = (_dir_vel - t0 * w) * e
	var nd: Vector3 = goal_dir + (d0 + t0) * e
	nd.y = 0.0
	_dir = nd.normalized() if nd.length_squared() > MIN_DIR_LEN_SQ else goal_dir
	var d1: Vector3 = _off - goal_off
	var t1: Vector3 = (_off_vel + d1 * w) * delta
	_off_vel = (_off_vel - t1 * w) * e
	_off = goal_off + (d1 + t1) * e


## Travel direction: the car's facing, blended toward its velocity with speed. Flat (no pitch).
func _goal_dir(xf: Transform3D) -> Vector3:
	var facing: Vector3 = -xf.basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var v: Vector3 = target.linear_velocity
	v.y = 0.0
	var speed: float = v.length()
	if speed < MIN_BLEND_SPEED_MS:
		return facing
	var w: float = velocity_blend * clampf(speed / maxf(velocity_full_ms, MIN_DIV), 0.0, 1.0)
	var mixed: Vector3 = facing.lerp(v / speed, w)
	if mixed.length_squared() < MIN_DIR_LEN_SQ:
		return facing
	return mixed.normalized()


func _goal_offset() -> Vector3:
	var dist: float = lerpf(distance_rest_m, distance_top_m, _speed_t()) + kick_back_m
	dist = maxf(minf(dist, _wall_limit), min_distance_m)
	var slip: float = target.drift_angle_deg
	var swing: float = -clampf(slip / maxf(drift_swing_norm_deg, MIN_DIV), -1.0, 1.0) * drift_swing_m
	swing = minf(swing, _side_limit_right_m)
	swing = maxf(swing, -_side_limit_left_m)
	return Vector3(dist, swing, 0.0)


## Camera height at this speed: a few centimetres lower at top speed, never above the ceiling limit.
func _chase_height() -> float:
	return minf(height_m - speed_drop_m * _speed_t(), _ceiling_height_m)


func _chase_pos(xf: Transform3D, dir: Vector3, off: Vector3) -> Vector3:
	var right: Vector3 = dir.cross(Vector3.UP)
	return xf.origin - dir * off.x + Vector3.UP * _chase_height() + right * off.y


func _look_point(xf: Transform3D) -> Vector3:
	match mode:
		Mode.HOOD:
			return xf * hood_look_local
		Mode.ORBIT:
			return xf.origin + Vector3.UP * orbit_look_height_m
	var right: Vector3 = _dir.cross(Vector3.UP)
	return xf.origin + _dir * look_ahead_m + Vector3.UP * look_height_m + right * (look_side * look_inside_m)


func _orbit_pos(xf: Transform3D) -> Vector3:
	return _orbit_point(xf, maxf(minf(orbit_radius_m, _orbit_limit), min_distance_m))


func _orbit_point(xf: Transform3D, radius: float) -> Vector3:
	var ring: Vector3 = Vector3(cos(_orbit_angle), 0.0, sin(_orbit_angle)) * radius
	return xf.origin + ring + Vector3.UP * orbit_height_m


func _update_lens(delta: float) -> void:
	var nitro_goal: float = 1.0 if target.nitro_active else 0.0
	nitro_kick = lerpf(nitro_kick, nitro_goal, 1.0 - exp(-nitro_kick_rate * delta))
	var goal: float = orbit_fov_deg if mode == Mode.ORBIT else compute_base_fov() + nitro_fov_kick * nitro_kick * _motion_gain()
	_fov_now = lerpf(_fov_now, goal, 1.0 - exp(-fov_rate * delta))
	# The ignition punch is added after smoothing, so it peaks at once instead of being filtered away.
	fov = minf(_fov_now + nitro_punch_deg * _motion_gain() * exp(-_kick_clock / NITRO_PUNCH_S), fov_cap_deg())


## Two sines per axis, about 16 Hz, scaled by trauma squared and the camera_shake option.
func _shake_offset(b: Basis) -> Vector3:
	var amp: float = max_shake_m * trauma * trauma * _shake_scale()
	if amp <= 0.0:
		return Vector3.ZERO
	var ph: float = _shake_clock * TAU * shake_hz
	var sx: float = sin(ph) + 0.5 * sin(ph * 1.31 + 1.7)
	var sy: float = sin(ph * 0.87 + 0.6) + 0.5 * sin(ph * 1.73 + 2.9)
	return (b.x * sx + b.y * sy) * amp


## Very small high-frequency shake that ramps in above speed_shake_from_kmh, scaled by camera_shake.
func _speed_shake_offset(b: Basis) -> Vector3:
	var k: float = clampf((target.speed_kmh - speed_shake_from_kmh) / maxf(speed_shake_full_kmh - speed_shake_from_kmh, MIN_DIV), 0.0, 1.0)
	var amp: float = speed_shake_m * k * _shake_scale() * _motion_gain()
	if amp <= 0.0:
		return Vector3.ZERO
	var ph: float = _shake_clock * TAU * speed_shake_hz
	return (b.x * sin(ph) + b.y * 0.5 * sin(ph * 1.37 + 0.8)) * amp


func _shake_scale() -> float:
	if _settings == null:
		return 1.0
	var v: Variant = _settings.get("camera_shake")
	if v == null:
		return 1.0
	return clampf(float(v), 0.0, 1.0)


## Gain of the speed shake and nitro FOV kick for a reduced_motion level: off 0, low half, high full.
static func motion_gain(level: String) -> float:
	if level == "off":
		return 0.0
	return 0.5 if level == "low" else 1.0


func _motion_gain() -> float:
	if _settings == null:
		return 1.0
	var v: Variant = _settings.get("reduced_motion")
	return motion_gain(str(v)) if v != null else 1.0


func _speed_t() -> float:
	if not is_instance_valid(target):
		return 0.0
	var top: float = fallback_top_speed_kmh
	if target.spec != null:
		top = target.spec.top_speed_kmh
	return clampf(target.speed_kmh / maxf(top, MIN_DIV), 0.0, 1.0)
