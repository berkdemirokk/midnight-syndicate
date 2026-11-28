class_name Headlights
extends Node3D
## Two forward SpotLight3D with a soft cone and short range. No shadows by default.
## lamp_pools (rivals): no lights at all, one additive glow_pool quad on the road ahead of the car instead.

const POOL_SHADER_PATH: String = "res://shaders/glow_pool.gdshader"
const POOL_AHEAD_M: float = 3.0  ## pool centre in front of the car origin (-Z)
const POOL_RADIUS_M: float = 2.6
const POOL_ROAD_Y_M: float = -0.44  ## same road level as Underglow (the car origin is 0.47 m above the road)
const POOL_STRENGTH: float = 0.6
const POOL_COLOR: Color = Color(1.0, 0.95, 0.82)

@export var lamp_pools: bool = false
@export var energy: float = 40.0
@export var range_m: float = 22.0
@export var cone_deg: float = 32.0
@export var cast_shadows: bool = false
@export var lamp_points: PackedVector3Array = PackedVector3Array([Vector3(-0.55, 0.45, -2.1), Vector3(0.55, 0.45, -2.1)])

var _lights: Array[SpotLight3D] = []
var _pool: MeshInstance3D = null
var mesh_layers: int = 1  ## render layers of the pool quad; CarFx passes the car body's layers (car fill light rule)


func _ready() -> void:
	if lamp_pools:
		_build_pool()
		set_on(false)
		return
	for p: Vector3 in lamp_points:
		var s := SpotLight3D.new()
		s.light_color = Color(1.0, 0.95, 0.82)
		s.light_energy = energy
		s.spot_range = range_m
		s.spot_angle = cone_deg
		s.spot_attenuation = 1.6
		s.shadow_enabled = cast_shadows
		s.position = p
		s.rotation_degrees = Vector3(-8.0, 0.0, 0.0)  # faces -Z, the car forward, tilted down onto the road
		add_child(s)
		_lights.append(s)
	set_on(false)


func set_on(on: bool) -> void:
	for s: SpotLight3D in _lights:
		s.visible = on
	if _pool != null:
		_pool.visible = on


func _build_pool() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(POOL_SHADER_PATH) as Shader
	mat.set_shader_parameter("tint", POOL_COLOR)
	mat.set_shader_parameter("strength", POOL_STRENGTH)
	mat.set_shader_parameter("radius_m", POOL_RADIUS_M)
	var plane := PlaneMesh.new()
	plane.size = Vector2(POOL_RADIUS_M * 2.0, POOL_RADIUS_M * 2.0)
	_pool = MeshInstance3D.new()
	_pool.name = "LampPool"
	_pool.mesh = plane
	_pool.material_override = mat
	_pool.position = Vector3(0.0, POOL_ROAD_Y_M, -POOL_AHEAD_M)
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pool.layers = mesh_layers
	add_child(_pool)
