class_name TireSmoke
extends Node3D
## Soft grey puffs from the rear wheel contacts while the car slides. CarFx decides when and how much;
## this node only places puffs, sets drift from lateral velocity and fades them over FADE_S.
## Lit by the scene (not unshaded), low alpha, and fades out pixel by pixel when a puff is near the lens.

const FADE_S: float = 1.0
const PUFF_COLOR: Color = Color(0.42, 0.45, 0.5, 1.0)
const PUFF_PEAK_ALPHA: float = 0.25
const MAX_DRIFT_MS: float = 4.0
## shortcut: one emitter per rear wheel, drift capped at MAX_DRIFT_MS, upgrade if trails need per-wheel tuning
@export var puff_amount: int = 14

var _emitters: Array[GPUParticles3D] = []
var _pms: Array[ParticleProcessMaterial] = []


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = FxUtil.soft_sprite()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 1.5  ## fully transparent inside this distance
	mat.distance_fade_max_distance = 5.0  ## fully opaque beyond this distance
	var ramp_colors := PackedColorArray([
		Color(PUFF_COLOR.r, PUFF_COLOR.g, PUFF_COLOR.b, 0.0),
		Color(PUFF_COLOR.r, PUFF_COLOR.g, PUFF_COLOR.b, PUFF_PEAK_ALPHA),
		Color(PUFF_COLOR.r, PUFF_COLOR.g, PUFF_COLOR.b, 0.0),
	])
	for i: int in 2:
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.0, 1.0, 0.0)
		pm.spread = 25.0
		pm.initial_velocity_min = 0.3
		pm.initial_velocity_max = 0.8
		pm.gravity = Vector3(0.0, 0.2, 0.0)
		pm.scale_min = 0.5
		pm.scale_max = 0.9
		pm.color_ramp = FxUtil.ramp(ramp_colors)
		var e := FxUtil.emitter(puff_amount, FADE_S, pm, mat, Vector2(0.7, 0.7))
		add_child(e)
		_emitters.append(e)
		_pms.append(pm)


## Positions the puffs at the wheel contacts (world space) and sets the drift. Called by CarFx.
## slip[i] is the puff amount for wheel i, 0..1; a wheel with 0 emits nothing.
func update_puffs(world_points: PackedVector3Array, slip: PackedFloat32Array, lateral_dir: Vector3, lateral_speed: float) -> void:
	var drift: float = clampf(lateral_speed, 0.0, MAX_DRIFT_MS)
	for i: int in mini(_emitters.size(), world_points.size()):
		var e := _emitters[i]
		var on: bool = slip[i] > 0.0
		e.global_position = world_points[i]
		e.emitting = on
		e.amount_ratio = clampf(slip[i], 0.0, 1.0)
		var pm := _pms[i]
		pm.direction = Vector3(-lateral_dir.x, 0.6, -lateral_dir.z).normalized()
		pm.initial_velocity_min = drift * 0.3
		pm.initial_velocity_max = drift * 0.6 + 0.3


func stop() -> void:
	for e: GPUParticles3D in _emitters:
		e.emitting = false
