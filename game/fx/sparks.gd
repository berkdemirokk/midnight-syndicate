class_name Sparks
extends Node3D
## Pool of one-shot bursts of stretched hot sparks with gravity. Call burst(world_pos) on impact.
## The pool is built once in _ready; a burst reuses the next emitter, so nothing is allocated per hit.

const POOL_SIZE: int = 4

@export var spark_amount: int = 60
@export var lifetime: float = 0.7

var _pool: Array[GPUParticles3D] = []
var _next: int = 0
var burst_count: int = 0  ## bursts since _ready, for tests and the perf log


func _ready() -> void:
	var mat := FxUtil.billboard_material(true, Color(1.0, 0.75, 0.35, 1.0))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 80.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0.0, -18.0, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	pm.particle_flag_align_y = true
	pm.color_ramp = FxUtil.ramp(PackedColorArray([Color(1.0, 1.0, 0.8, 1.0), Color(1.0, 0.5, 0.15, 1.0), Color(0.6, 0.1, 0.0, 0.0)]))
	for i: int in POOL_SIZE:
		var e := FxUtil.emitter(spark_amount, lifetime, pm, mat, Vector2(0.08, 0.6))
		e.one_shot = true
		e.explosiveness = 1.0  # one burst: every spark leaves at once, not spread over the lifetime
		e.local_coords = false
		add_child(e)
		_pool.append(e)


func burst(world_pos: Vector3) -> void:
	var e := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	burst_count += 1
	e.global_position = world_pos
	e.restart()
	e.emitting = true


func stop() -> void:
	for e: GPUParticles3D in _pool:
		e.emitting = false
