class_name RainFx
extends Node3D
## Rain streaks, ground splashes (droplets and ripple rings) in a box that follows the active camera.
## Off when the graphics preset says rain_enabled is false; particle count follows particle_amount_scale.
## Shelter: a ray up from the camera finds a roof and the rain fades out in SHELTER_FADE_S.
## Ground: a ray down from the camera sets the splash height to the road under the camera.

const WORLD_LAYER_MASK: int = 1  ## physics layer 1: world and static, as race_scene.gd
const SHELTER_RANGE_M: float = 40.0
const GROUND_RANGE_M: float = 60.0
const PROBE_INTERVAL_S: float = 0.05  ## about every 3 frames at 60 fps
const SHELTER_FADE_S: float = 0.3
const MAX_SLANT_RATIO: float = 0.6  ## streak slant toward the camera's motion, as a share of fall speed
const CAM_VEL_RATE: float = 8.0  ## 1/s: camera velocity smoothing for the streak slant
const SPLASH_RGBA: Color = Color(0.5, 0.7, 0.9, 0.35)
const STREAK_RGBA: Color = Color(0.42, 0.52, 0.7, 0.5)
const RIPPLE_RGBA: Color = Color(0.55, 0.68, 0.9, 0.32)
const CAM_CUT_M: float = 5.0  ## a camera jump larger than this per frame is a cut: the slant restarts from rest

@export var box_half_extent: Vector3 = Vector3(18.0, 0.0, 18.0)  ## metres around the camera
@export var box_height: float = 14.0
@export var streak_amount: int = 900  ## at particle_amount_scale 1.0
@export var splash_amount: int = 160
@export var ripple_amount: int = 160
@export var ground_y: float = 0.0  ## fallback splash height until a ground ray hits
@export var fall_speed: float = 22.0
@export var rain_layer: int = 10  ## render layer bit (1 << 9) excluded from planar reflections

var _streaks: GPUParticles3D
var _streak_pm: ParticleProcessMaterial
var _streak_mat: ShaderMaterial
var _splash: GPUParticles3D
var _splash_mat: StandardMaterial3D
var _ripples: GPUParticles3D
var _ripple_mat: ShaderMaterial
var _enabled: bool = true
var _ground_h: float = 0.0
var _covered: bool = false
var _rain_factor: float = 1.0  ## 1 = raining, 0 = under cover (fades over SHELTER_FADE_S)
var _probe_t: float = 0.0
var _cam_prev: Vector3 = Vector3.ZERO
var _cam_vel: Vector3 = Vector3.ZERO
var _has_cam: bool = false
var _ground_known: bool = false  ## no ripples before the first ground probe (they spawned wherever the emitter started)
var _flags_on: int = -1  ## last state pushed to the emitters (-1 = never)


func _ready() -> void:
	_ground_h = ground_y
	_streak_mat = ShaderMaterial.new()
	_streak_mat.shader = load("res://shaders/rain_streak.gdshader") as Shader
	_streak_mat.set_shader_parameter("streak_color", STREAK_RGBA)
	_streak_pm = _streak_process()
	_streaks = FxUtil.emitter(streak_amount, 0.9, _streak_pm, _streak_mat, Vector2(0.012, 0.8))
	_streaks.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	_splash_mat = FxUtil.billboard_material(true, SPLASH_RGBA) as StandardMaterial3D
	_splash = FxUtil.emitter(splash_amount, 0.25, _splash_process(), _splash_mat, Vector2(0.05, 0.05))
	_splash.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 8, 80))
	_ripple_mat = ShaderMaterial.new()
	_ripple_mat.shader = load("res://shaders/rain_ripple.gdshader") as Shader
	_ripple_mat.set_shader_parameter("ring_color", RIPPLE_RGBA)
	_ripples = FxUtil.emitter(ripple_amount, 0.45, _ripple_process(), _ripple_mat, Vector2(0.55, 0.55))
	_ripples.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 8, 80))
	add_child(_streaks)
	add_child(_splash)
	add_child(_ripples)
	for e: GPUParticles3D in [_streaks, _splash, _ripples]:
		e.layers = 1 << (rain_layer - 1)
	Settings.changed.connect(_on_settings_changed)
	_apply_settings()


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.disconnect(_on_settings_changed)


func _on_settings_changed(_section: String) -> void:
	_apply_settings()


func _apply_settings() -> void:
	var p: GraphicsPreset = Settings.get_preset()
	_enabled = p.rain_enabled
	visible = _enabled
	var scale_f: float = p.particle_amount_scale
	_streaks.amount = maxi(1, int(round(streak_amount * scale_f)))
	_splash.amount = maxi(1, int(round(splash_amount * scale_f)))
	_ripples.amount = maxi(1, int(round(ripple_amount * scale_f)))
	_apply_flags()


func _process(delta: float) -> void:
	if not _enabled:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c: Vector3 = cam.global_position
	if _has_cam and delta > 0.0:
		if c.distance_to(_cam_prev) > CAM_CUT_M:
			_cam_vel = Vector3.ZERO
		else:
			_cam_vel = _cam_vel.lerp((c - _cam_prev) / delta, 1.0 - exp(-CAM_VEL_RATE * delta))
	_cam_prev = c
	_has_cam = true
	_probe_t -= delta
	if _probe_t <= 0.0:
		_probe_t = PROBE_INTERVAL_S
		_probe(c)
	_update_shelter(delta)
	_update_slant()
	# The box follows the camera; splashes sit on the road height found under it.
	global_position = Vector3(c.x, _ground_h + box_height * 0.5, c.z)
	_streaks.global_position = global_position
	var splash_pos := Vector3(c.x, _ground_h + 0.02, c.z)
	_splash.global_position = splash_pos
	_ripples.global_position = splash_pos


## True while a roof is within SHELTER_RANGE_M above the camera.
func is_covered() -> bool:
	return _covered


## 1.0 in the open, 0.0 under cover, in between while fading.
func rain_factor() -> float:
	return _rain_factor


## Streak emitter is on and visible (the rain is actually drawn).
func is_raining() -> bool:
	return _streaks.visible and _streaks.emitting


## Road height used for the splash layer (from the camera ground ray).
func ground_height() -> float:
	return _ground_h


func set_enabled(on: bool) -> void:
	_enabled = on and Settings.get_preset().rain_enabled
	visible = _enabled
	_apply_flags()


func _probe(c: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var up := PhysicsRayQueryParameters3D.create(c, c + Vector3.UP * SHELTER_RANGE_M, WORLD_LAYER_MASK)
	_covered = not space.intersect_ray(up).is_empty()
	var down := PhysicsRayQueryParameters3D.create(c, c + Vector3.DOWN * GROUND_RANGE_M, WORLD_LAYER_MASK)
	var hit: Dictionary = space.intersect_ray(down)
	if not hit.is_empty():
		_ground_h = (hit["position"] as Vector3).y
	_ground_known = true  # after the first probe the height is either the hit or the scene's ground_y fallback


func _update_shelter(delta: float) -> void:
	var target: float = 0.0 if _covered else 1.0
	_rain_factor = move_toward(_rain_factor, target, delta / SHELTER_FADE_S)
	_streak_mat.set_shader_parameter("rain_alpha", _rain_factor)
	_ripple_mat.set_shader_parameter("rain_alpha", _rain_factor)
	var c := SPLASH_RGBA
	c.a *= _rain_factor
	_splash_mat.albedo_color = c
	_apply_flags()


## Emitters run only while enabled and not fully under cover; ripples also wait for the first ground hit.
func _apply_flags() -> void:
	var on: bool = _enabled and _rain_factor > 0.001
	var state: int = int(on) + 2 * int(on and _ground_known)
	if state == _flags_on:
		return
	_flags_on = state
	_streaks.emitting = on
	_streaks.visible = on
	_splash.emitting = on
	_splash.visible = on
	_ripples.emitting = on and _ground_known
	_ripples.visible = on and _ground_known


## Relative rain velocity = rain minus camera motion, so streaks lean back toward the camera when driving.
## Only the drawn streak axis leans: the drops themselves fall straight down in the world, so their motion past the
## camera already carries the camera velocity once (slanting the spawn direction too doubled it).
func _update_slant() -> void:
	var rel := Vector3(-_cam_vel.x, 0.0, -_cam_vel.z)
	var max_h: float = fall_speed * MAX_SLANT_RATIO
	if rel.length() > max_h:
		rel = rel.normalized() * max_h
	var dir := Vector3(rel.x, -fall_speed, rel.z).normalized()
	_streak_mat.set_shader_parameter("fall_dir", dir)


func _streak_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(box_half_extent.x, box_height * 0.5, box_half_extent.z)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 3.0
	pm.initial_velocity_min = fall_speed
	pm.initial_velocity_max = fall_speed * 1.15
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	# Per-particle alpha (COLOR.a in rain_streak.gdshader) varies the streaks so they do not read as identical pinstripes.
	pm.color_initial_ramp = FxUtil.ramp(PackedColorArray([Color(1, 1, 1, 0.15), Color(1, 1, 1, 0.9)]))
	return pm


func _splash_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(box_half_extent.x, 0.0, box_half_extent.z)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.scale_min = 0.4
	pm.scale_max = 0.9
	return pm


## Ripple rings stay in place: no velocity, the quad grows along scale_curve and fades along the colour ramp.
func _ripple_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(box_half_extent.x, 0.0, box_half_extent.z)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 1.0
	pm.scale_max = 1.0
	var curve := Curve.new()
	curve.clear_points()
	curve.add_point(Vector2(0.0, 0.15))
	curve.add_point(Vector2(1.0, 1.0))
	var grow := CurveTexture.new()
	grow.curve = curve
	pm.scale_curve = grow
	pm.color_ramp = FxUtil.ramp(PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)]))
	return pm
