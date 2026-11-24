class_name SpeedLines
extends CanvasLayer
## Full-screen radial speed streaks. set_intensity(v) clamps v to 0..1. Put it on the HUD layer.

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
