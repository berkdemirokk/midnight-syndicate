class_name MenuBackdrop
extends ColorRect
## Full-screen live night-city backdrop (menu_backdrop.gdshader). One quad, no textures, no 3D.
## dim_left darkens the left side where the menu column sits; menus with a wide table use a larger value.

const SHADER: String = "res://ui/menus/menu_backdrop.gdshader"

var _mat: ShaderMaterial


func _init(dim_left: float = 0.55, intensity: float = 1.0) -> void:
	name = "Backdrop"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER) as Shader
	_mat.set_shader_parameter("dim_left", dim_left)
	_mat.set_shader_parameter("intensity", intensity)
	material = _mat
	resized.connect(_on_resized)


func _on_resized() -> void:
	if size.y > 0.0:
		_mat.set_shader_parameter("aspect", size.x / size.y)


func set_dim(dim_left: float, intensity: float = 1.0) -> void:
	_mat.set_shader_parameter("dim_left", dim_left)
	_mat.set_shader_parameter("intensity", intensity)
