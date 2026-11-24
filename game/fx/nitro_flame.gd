class_name NitroFlame
extends Node3D
## Two blue-white to magenta additive flames at the exhausts, a short pop at ignition and one small
## OmniLight flash. Drive with set_active() and set_strength(); pop() plays the ignition burst.

@export var flame_amount: int = 24
@export var base_lifetime: float = 0.35
@export var light_energy: float = 4.0
@export var light_range: float = 6.0

var _flames: Array[GPUParticles3D] = []
var _cores: Array[GPUParticles3D] = []
var _pop: GPUParticles3D
var _light: OmniLight3D
var _strength: float = 0.0
var _pop_timer: float = 0.0
var _active: bool = false


func _ready() -> void:
	var mat := FxUtil.billboard_material(true, Color(1, 1, 1, 1))
	var pm_core := _flame_process(0.9, 6.0)
	for i: int in 2:
		var pm_flame := _flame_process(1.0, 9.0)
		pm_flame.color_ramp = FxUtil.ramp(PackedColorArray([Color(0.6, 0.85, 1.0, 0.8), Color(0.25, 0.35, 1.0, 0.5), Color(1.0, 0.15, 0.9, 0.0)]))
		var f := FxUtil.emitter(flame_amount, base_lifetime, pm_flame, mat, Vector2(0.5, 0.5))
		add_child(f)
		_flames.append(f)
	# Hot core: a smaller, brighter white-blue emitter at the same points.
	for f: GPUParticles3D in _flames:
		var core := FxUtil.emitter(flame_amount / 2, base_lifetime * 0.6, pm_core, mat, Vector2(0.2, 0.2))
		f.add_child(core)
		_cores.append(core)
	_pop = FxUtil.emitter(40, 0.25, _pop_process(), mat, Vector2(0.7, 0.7))
	_pop.one_shot = true
	_pop.explosiveness = 1.0
	add_child(_pop)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.6, 0.7, 1.0)
	_light.light_energy = 0.0
	_light.omni_range = light_range
	_light.shadow_enabled = false
	add_child(_light)
	set_active(false)


func set_exhaust_points(points: PackedVector3Array) -> void:
	for i: int in mini(points.size(), _flames.size()):
		_flames[i].position = points[i]
	if points.size() > 0:
		_pop.position = points[0]
		_light.position = points[0] + Vector3(0.0, 0.1, 0.4)


func set_active(on: bool) -> void:
	_active = on
	for f: GPUParticles3D in _flames:
		f.emitting = on
	for c: GPUParticles3D in _cores:
		c.emitting = on
	_light.visible = on
	if not on:
		_light.light_energy = 0.0


## Flame length and brightness, 0..1. Grows with car speed while nitro is on.
func set_strength(v: float) -> void:
	_strength = clampf(v, 0.0, 1.0)
	var s: float = 0.4 + 0.6 * _strength
	for f: GPUParticles3D in _flames:
		f.scale = Vector3(s, s, s)
	if _active:
		_light.light_energy = light_energy * _strength


func pop() -> void:
	_pop.restart()
	_pop.emitting = true
	_pop_timer = 0.12
	_light.light_energy = light_energy * 2.0


func _process(delta: float) -> void:
	if _pop_timer > 0.0:
		_pop_timer -= delta
		if _pop_timer <= 0.0 and _active:
			_light.light_energy = light_energy * _strength


func _flame_process(spread: float, speed: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, 1.0)  # out of the exhaust, toward the back of the car
	pm.spread = spread * 6.0
	pm.initial_velocity_min = speed * 0.8
	pm.initial_velocity_max = speed
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = FxUtil.ramp(PackedColorArray([Color(0.8, 0.9, 1.0, 0.6), Color(0.3, 0.5, 1.0, 0.45), Color(1.0, 0.2, 0.9, 0.0)]))
	return pm


func _pop_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, 1.0)
	pm.spread = 180.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 12.0
	pm.damping_max = 12.0
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.color_ramp = FxUtil.ramp(PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(0.5, 0.6, 1.0, 0.0)]))
	return pm
