class_name Underglow
extends Node3D
## Coloured light pool under a car: an additive quad on the road (glow_pool.gdshader) and, when player_light is on
## (the player's car only), one short-range OmniLight that tints the body and the tarmac beside it.
## Shown at night and sunset only: pass the race's TimeOfDay id to apply_time_of_day().

const SHADER_PATH: String = "res://shaders/glow_pool.gdshader"
const DEFAULT_COLOR: Color = Color(0.62, 0.18, 0.95)  ## violet-magenta
const RADIUS_M: float = 2.7
const ROAD_Y_LOCAL: float = -0.44  ## the car origin is 0.47 m above the road (CAR_RESET_HEIGHT_M); the pool sits 3 cm above it
const LIGHT_RANGE_M: float = 4.5
const LIGHT_ENERGY: float = 1.2
const SHOW_TODS: PackedStringArray = ["night", "sunset"]

@export var color: Color = DEFAULT_COLOR:
	set(v):
		color = v
		_apply_color()
@export_range(0.0, 2.0, 0.01) var strength: float = 1.3:
	set(v):
		strength = v
		if _mat != null:
			_mat.set_shader_parameter("strength", strength)
@export var player_light: bool = false:
	set(v):
		player_light = v
		_apply_visibility()

var _pool: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _light: OmniLight3D = null
var _tod_on: bool = true


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH) as Shader
	var plane := PlaneMesh.new()
	plane.size = Vector2(RADIUS_M * 2.0, RADIUS_M * 2.0)
	_pool = MeshInstance3D.new()
	_pool.name = "Pool"
	_pool.mesh = plane
	_pool.material_override = _mat
	_pool.position = Vector3(0.0, ROAD_Y_LOCAL, 0.0)
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pool)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.position = Vector3(0.0, -0.2, 0.0)
	_light.omni_range = LIGHT_RANGE_M
	_light.light_energy = LIGHT_ENERGY
	_light.shadow_enabled = false
	_light.light_cull_mask = ((1 << 20) - 1) & ~WheelSpray.SPRAY_LAYER  ## the spray is not lit by this light
	add_child(_light)
	_mat.set_shader_parameter("strength", strength)
	_mat.set_shader_parameter("radius_m", RADIUS_M)
	_apply_color()
	_apply_visibility()


## Night and sunset only. Other ids (day) hide the pool and the light.
func apply_time_of_day(tod_id: String) -> void:
	_tod_on = SHOW_TODS.has(tod_id)
	_apply_visibility()


func is_showing() -> bool:
	return _pool != null and _pool.visible


func _apply_color() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("tint", color)
	_light.light_color = color


func _apply_visibility() -> void:
	if _pool == null:
		return
	_pool.visible = _tod_on
	_light.visible = _tod_on and player_light
