class_name TireSmoke
extends Node3D
## Soft alpha puffs from the rear wheel contacts. Amount follows slip, puffs drift with the car's
## lateral velocity and fade over 1.2 s. Not additive. Positions and drift are set each frame.

const FADE_S: float = 1.2
@export var puff_amount: int = 40

var _emitters: Array[GPUParticles3D] = []
var _pms: Array[ParticleProcessMaterial] = []


func _ready() -> void:
	var mat := FxUtil.billboard_material(false, Color(0.82, 0.84, 0.88, 0.55))
	for i: int in 2:
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.0, 1.0, 0.0)
		pm.spread = 25.0
		pm.initial_velocity_min = 0.5
		pm.initial_velocity_max = 1.2
		pm.gravity = Vector3(0.0, 0.2, 0.0)
		pm.scale_min = 0.8
		pm.scale_max = 1.6
		pm.color_ramp = FxUtil.ramp(PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)]))
		var e := FxUtil.emitter(puff_amount, FADE_S, pm, mat, Vector2(1.2, 1.2))
		add_child(e)
		_emitters.append(e)
		_pms.append(pm)


## Positions the puffs at the wheel contacts (world space) and sets the drift. Called by CarFx.
func update_puffs(world_points: PackedVector3Array, slip: PackedFloat32Array, lateral_dir: Vector3, lateral_speed: float) -> void:
	for i: int in mini(_emitters.size(), world_points.size()):
		var e := _emitters[i]
		var on: bool = slip[i] > 0.0
		e.global_position = world_points[i]
		e.emitting = on
		e.amount_ratio = clampf(slip[i], 0.0, 1.0)
		var pm := _pms[i]
		pm.direction = Vector3(-lateral_dir.x, 0.6, -lateral_dir.z).normalized()
		pm.initial_velocity_min = lateral_speed * 0.3
		pm.initial_velocity_max = lateral_speed * 0.6 + 0.5


func stop() -> void:
	for e: GPUParticles3D in _emitters:
		e.emitting = false
