class_name Petals
extends Node3D
## Erguvan (Judas tree) petals drifting through the air on the Ortakoy route by day and at sunset: the blossom rows
## (StreetProps) shed them, as the owner's reference frame shows. One GPUParticles3D box that follows the camera,
## world-space particles, small pink sprites with a slow fall, sideways drift and spin. Count follows Settings
## particle_amount_scale; Low turns it off.

const AMOUNT: int = 140
const LIFETIME_S: float = 7.0
const BOX: Vector3 = Vector3(36.0, 9.0, 36.0)
const PETAL_M: float = 0.07
const PINK: Color = Color(0.95, 0.45, 0.72, 0.9)

var _emitter: GPUParticles3D = null


func _ready() -> void:
	var scale_f: float = Settings.get_preset().particle_amount_scale
	if scale_f <= 0.0 or Settings.get_preset_id() == "low":
		return
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = BOX * 0.5
	pm.direction = Vector3(1.0, -0.3, 0.2)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0.25, -0.45, 0.1)
	pm.damping_min = 0.2
	pm.damping_max = 0.6
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color_ramp = FxUtil.ramp(PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]))
	var mat: StandardMaterial3D = FxUtil.billboard_material(false, PINK)
	_emitter = FxUtil.emitter(maxi(8, int(round(AMOUNT * scale_f))), LIFETIME_S, pm, mat, Vector2(PETAL_M, PETAL_M * 0.8))
	_emitter.local_coords = false
	_emitter.visibility_aabb = AABB(-BOX, BOX * 2.0)
	_emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_emitter)
	_emitter.emitting = true


func _process(_delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		global_position = cam.global_position + Vector3(0.0, 1.5, 0.0)
