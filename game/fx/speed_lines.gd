class_name SpeedLines
extends CanvasLayer
## Full-screen radial speed streaks on the HUD layer. set_intensity(v) clamps v to 0..1. set_speed(kmh, nitro)
## maps the car's speed to an intensity: nothing below from_kmh, full at full_kmh, and less without nitro.

@export var from_kmh: float = 160.0  ## lines start to show here
@export var full_kmh: float = 180.0  ## full strength here (clearly visible from 180 km/h)
@export var no_nitro_mul: float = 0.75  ## strength scale without nitro; nitro gives 1.0

var _rect: ColorRect = ColorRect.new()


func _ready() -> void:
	layer = 5
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := load("res://shaders/speed_lines.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_rect.material = mat
	_rect.color = Color(1, 1, 1, 1)
	add_child(_rect)
	set_intensity(0.0)


func set_intensity(v: float) -> void:
	var mat := _rect.material as ShaderMaterial
	mat.set_shader_parameter("intensity", clampf(v, 0.0, 1.0))


func get_intensity() -> float:
	return (_rect.material as ShaderMaterial).get_shader_parameter("intensity")


## Feed this every frame with the player's car. Caller: race_scene or race_hud (see FX_AND_SHADERS.md).
func set_speed(kmh: float, nitro: bool) -> void:
	set_intensity(intensity_for(kmh, nitro))


func intensity_for(kmh: float, nitro: bool) -> float:
	var k: float = smoothstep(from_kmh, full_kmh, kmh)
	return k if nitro else k * no_nitro_mul
