class_name GarageOrbit
extends RefCounted
## Orbit camera state for the garage: yaw, pitch and distance around a target. Drags and zoom set targets,
## which are smoothed and carry a little inertia. Preset views ease from the current pose to a fixed one.
## No nodes here: garage.gd reads camera_position() and looks at target. Limits come from garage_layout.json.

const PRESETS: Dictionary = {
	"front": {"yaw": 3.14159265, "pitch": 7.0, "dist": 7.0},
	"side": {"yaw": 1.5707963, "pitch": 8.0, "dist": 8.2},
	"rear34": {"yaw": 0.45, "pitch": 8.0, "dist": 7.4},
	"overview": {"yaw": -2.45, "pitch": 8.0, "dist": 7.4},  ## STREET EMPIRE studio, 38 deg lens: the car between the panels
}
const PRESET_SECONDS: float = 0.9
const DRAG_RAD_PER_PX: float = 0.008
const DRAG_DEG_PER_PX: float = 0.12
const INERTIA_DECAY: float = 4.0  ## 1/s, how fast a flick slows down
const SMOOTH_RATE: float = 10.0  ## 1/s, how fast the current pose follows the target
const IDLE_START_S: float = 4.0  ## seconds without input before the turntable starts to turn

var target: Vector3 = Vector3(0.0, 0.7, 0.0)
var min_dist: float = 3.2
var max_dist: float = 5.4
var min_pitch: float = -2.0
var max_pitch: float = 40.0
var yaw: float = -2.5
var pitch: float = 12.0
var dist: float = 4.6

var _yaw_t: float = -2.5
var _pitch_t: float = 12.0
var _dist_t: float = 4.6
var _yaw_vel: float = 0.0
var _pitch_vel: float = 0.0
var _idle: float = 0.0
var _preset_active: bool = false
var _preset_t: float = 0.0
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO


## Reads camera_orbit from garage_layout.json (already parsed). Missing keys keep the defaults above.
func configure(layout: Dictionary) -> void:
	var o: Dictionary = layout.get("camera_orbit", {})
	if o.has("target"):
		var t: Array = o["target"]
		target = Vector3(float(t[0]), float(t[1]), float(t[2]))
	min_dist = float(o.get("min_distance_m", min_dist))
	max_dist = float(o.get("max_distance_m", max_dist))
	min_pitch = float(o.get("min_pitch_deg", min_pitch))
	max_pitch = float(o.get("max_pitch_deg", max_pitch))
	set_pose(yaw, pitch, dist)


static func clamp_pitch(p: float, lo: float, hi: float) -> float:
	return clampf(p, lo, hi)


static func clamp_dist(d: float, lo: float, hi: float) -> float:
	return clampf(d, lo, hi)


## Jumps to a pose at once (clamped). Cancels any preset transition.
func set_pose(y: float, p: float, d: float) -> void:
	yaw = y
	pitch = clamp_pitch(p, min_pitch, max_pitch)
	dist = clamp_dist(d, min_dist, max_dist)
	_yaw_t = yaw
	_pitch_t = pitch
	_dist_t = dist
	_yaw_vel = 0.0
	_pitch_vel = 0.0
	_preset_active = false


## Starts an eased transition to a named preset. Returns false for an unknown name.
func go_preset(name: String) -> bool:
	if not PRESETS.has(name):
		return false
	var p: Dictionary = PRESETS[name]
	_from = Vector3(yaw, pitch, dist)
	_to = Vector3(float(p["yaw"]), clamp_pitch(float(p["pitch"]), min_pitch, max_pitch), clamp_dist(float(p["dist"]), min_dist, max_dist))
	_preset_t = 0.0
	_preset_active = true
	_yaw_vel = 0.0
	_pitch_vel = 0.0
	touch()
	return true


func is_preset_moving() -> bool:
	return _preset_active


## Pose a named preset ends at, after clamping. Empty dictionary for an unknown name.
func preset_pose(name: String) -> Dictionary:
	if not PRESETS.has(name):
		return {}
	var p: Dictionary = PRESETS[name]
	return {
		"yaw": float(p["yaw"]),
		"pitch": clamp_pitch(float(p["pitch"]), min_pitch, max_pitch),
		"dist": clamp_dist(float(p["dist"]), min_dist, max_dist),
	}


## One drag step in screen pixels (positive x moves the content right). Cancels a preset transition.
func drag(px: Vector2) -> void:
	_preset_active = false
	var dy: float = -px.x * DRAG_RAD_PER_PX
	var dp: float = px.y * DRAG_DEG_PER_PX
	_yaw_t += dy
	_pitch_t = clamp_pitch(_pitch_t + dp, min_pitch, max_pitch)
	_yaw_vel = dy * 60.0
	_pitch_vel = dp * 60.0
	touch()


## Keyboard and pad orbit: moves the yaw and pitch targets directly (radians and degrees). Cancels a preset.
func nudge(dyaw: float, dpitch_deg: float) -> void:
	_preset_active = false
	_yaw_t += dyaw
	_pitch_t = clamp_pitch(_pitch_t + dpitch_deg, min_pitch, max_pitch)
	touch()


## Multiplies the distance target. factor below 1 zooms in. Cancels a preset transition.
func zoom(factor: float) -> void:
	_preset_active = false
	_dist_t = clamp_dist(_dist_t * factor, min_dist, max_dist)
	touch()


func touch() -> void:
	_idle = 0.0


func idle_seconds() -> float:
	return _idle


func is_idle_spinning() -> bool:
	return _idle >= IDLE_START_S


func step(delta: float) -> void:
	_idle += delta
	if _preset_active:
		_preset_t = minf(_preset_t + delta / PRESET_SECONDS, 1.0)
		var e: float = smoothstep(0.0, 1.0, _preset_t)
		yaw = lerpf(_from.x, _to.x, e)
		pitch = lerpf(_from.y, _to.y, e)
		dist = lerpf(_from.z, _to.z, e)
		if _preset_t >= 1.0:
			_preset_active = false
			set_pose(_to.x, _to.y, _to.z)
		return
	var decay: float = exp(-INERTIA_DECAY * delta)
	_yaw_t += _yaw_vel * delta
	_pitch_t = clamp_pitch(_pitch_t + _pitch_vel * delta, min_pitch, max_pitch)
	_yaw_vel *= decay
	_pitch_vel *= decay
	var k: float = 1.0 - exp(-SMOOTH_RATE * delta)
	yaw = lerp_angle(yaw, _yaw_t, k)
	pitch = lerpf(pitch, _pitch_t, k)
	dist = lerpf(dist, _dist_t, k)


## Camera position in world space for the current pose.
func camera_position() -> Vector3:
	var p: float = deg_to_rad(pitch)
	var cp: float = cos(p)
	return target + Vector3(sin(yaw) * cp, sin(p), cos(yaw) * cp) * dist
