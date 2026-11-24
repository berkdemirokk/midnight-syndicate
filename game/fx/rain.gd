class_name RainFx
extends Node3D
## Rain streaks and ground splashes in a box that follows the active camera. Off when the graphics
## preset says rain_enabled is false; particle count follows particle_amount_scale.

@export var box_half_extent: Vector3 = Vector3(18.0, 0.0, 18.0)  ## metres around the camera
@export var box_height: float = 14.0
@export var streak_amount: int = 900  ## at particle_amount_scale 1.0
@export var splash_amount: int = 160
@export var ground_y: float = 0.0
@export var fall_speed: float = 22.0
@export var rain_layer: int = 10  ## render layer bit (1 << 9) excluded from planar reflections

var _streaks: GPUParticles3D
var _splash: GPUParticles3D
var _enabled: bool = true
var _cam: Camera3D = null


func _ready() -> void:
	_streaks = FxUtil.emitter(streak_amount, 0.9, _streak_process(), FxUtil.billboard_material(true, Color(0.42, 0.52, 0.7, 0.5), false), Vector2(0.02, 0.8))
	_streaks.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	_splash = FxUtil.emitter(splash_amount, 0.25, _splash_process(), FxUtil.billboard_material(true, Color(0.5, 0.7, 0.9, 0.35)), Vector2(0.05, 0.05))
	_splash.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 8, 80))
	add_child(_streaks)
	add_child(_splash)
	_streaks.layers = 1 << (rain_layer - 1)
	_splash.layers = 1 << (rain_layer - 1)
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
	_streaks.emitting = _enabled
	_splash.emitting = _enabled
	var scale_f: float = p.particle_amount_scale
	_streaks.amount = maxi(1, int(round(streak_amount * scale_f)))
	_splash.amount = maxi(1, int(round(splash_amount * scale_f)))


func _process(_delta: float) -> void:
	if not _enabled:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_cam = cam
	var c: Vector3 = cam.global_position
	# The box follows the camera and sits on the ground plane for splashes.
	global_position = Vector3(c.x, ground_y + box_height * 0.5, c.z)
	_streaks.global_position = global_position
	_splash.global_position = Vector3(c.x, ground_y + 0.02, c.z)


func set_enabled(on: bool) -> void:
	_enabled = on and Settings.get_preset().rain_enabled
	visible = _enabled
	_streaks.emitting = _enabled
	_splash.emitting = _enabled


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
	pm.particle_flag_align_y = true  # stretched streak along the fall direction
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
