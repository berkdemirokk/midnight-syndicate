class_name PostFx
extends CanvasLayer
## Finishing pass under the HUD (post_grade.gdshader): speed blur, grade and vignette. Hidden on the Low preset.
## set_speed(kmh, nitro) each frame; set_time_of_day(id) once per race.

const LAYER: int = 2  ## under the speed lines (5) and the HUD
const BLUR_FROM_KMH: float = 110.0
const BLUR_FULL_KMH: float = 260.0
const NITRO_BLUR: float = 0.35  ## extra blur while the nitro burns
const BLUR_RATE: float = 4.0  ## 1/s smoothing so the blur does not pop

var _rect: ColorRect = ColorRect.new()
var _blur: float = 0.0
var _target: float = 0.0


func _ready() -> void:
	layer = LAYER
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/post_grade.gdshader") as Shader
	_rect.material = mat
	add_child(_rect)
	Settings.changed.connect(_on_settings_changed)
	_on_settings_changed("")


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.disconnect(_on_settings_changed)


func _on_settings_changed(_section: String) -> void:
	visible = Settings.get_preset_id() != "low"


func _process(delta: float) -> void:
	_blur = lerpf(_blur, _target, 1.0 - exp(-BLUR_RATE * delta))
	(_rect.material as ShaderMaterial).set_shader_parameter("blur", _blur)


func set_speed(kmh: float, nitro: bool) -> void:
	_target = clampf(blur_for(kmh, nitro), 0.0, 1.0)


static func blur_for(kmh: float, nitro: bool) -> float:
	return smoothstep(BLUR_FROM_KMH, BLUR_FULL_KMH, kmh) * (1.0 - NITRO_BLUR) + (NITRO_BLUR if nitro else 0.0)


func get_blur() -> float:
	return _blur


## Grade per hour: richer and cooler at night, cleaner by day, warm at sunset.
func set_time_of_day(tod_id: String) -> void:
	var m: ShaderMaterial = _rect.material as ShaderMaterial
	match tod_id:
		"day":
			_grade(m, 1.06, 1.05, Color(0.97, 0.99, 1.04), Color(1.02, 1.0, 0.97), 0.18)
		"sunset":
			_grade(m, 1.1, 1.07, Color(0.95, 0.93, 1.06), Color(1.07, 1.0, 0.92), 0.26)
		_:
			_grade(m, 1.16, 1.1, Color(0.9, 0.95, 1.12), Color(1.05, 1.0, 0.95), 0.36)


func _grade(m: ShaderMaterial, sat: float, con: float, shadows: Color, highlights: Color, vig: float) -> void:
	m.set_shader_parameter("saturation", sat)
	m.set_shader_parameter("contrast", con)
	m.set_shader_parameter("shadow_tint", shadows)
	m.set_shader_parameter("highlight_tint", highlights)
	m.set_shader_parameter("vignette", vig)
