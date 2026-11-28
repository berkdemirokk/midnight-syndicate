class_name PostFx
extends CanvasLayer
## Finishing pass under the HUD (post_grade.gdshader): speed blur, grade and vignette. Hidden on the Low preset.
## set_speed(kmh, nitro) each frame; set_time_of_day(id) once per race.

const LAYER: int = 2  ## under the speed lines (5) and the HUD
const BLUR_FROM_KMH: float = 110.0
const BLUR_FULL_KMH: float = 260.0
const NITRO_BLUR: float = 0.35  ## extra blur while the nitro burns
const BLUR_RATE: float = 4.0  ## 1/s smoothing so the blur does not pop
const BURST_PEAK: float = 0.5  ## blur added on the frame nitro ignites
const BURST_DECAY: float = 6.0  ## 1/s, the ignition burst is gone in about half a second
const BLUR_TAPS: Dictionary = {"low": 0, "medium": 3, "high": 5}  ## extra blur samples by graphics preset

var _rect: ColorRect = ColorRect.new()
var _blur: float = 0.0
var _target: float = 0.0
var _burst: float = 0.0  ## decaying ignition blur
var _was_nitro: bool = false
var _taps: int = 5


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
	_taps = blur_taps_for(Settings.get_preset_id(), Settings.reduced_motion)
	(_rect.material as ShaderMaterial).set_shader_parameter("blur_taps", _taps)
	if _taps == 0:
		_blur = 0.0
		_burst = 0.0


func _process(delta: float) -> void:
	_blur = lerpf(_blur, _target, 1.0 - exp(-BLUR_RATE * delta))
	_burst *= exp(-BURST_DECAY * delta)
	(_rect.material as ShaderMaterial).set_shader_parameter("blur", clampf(_blur + _burst, 0.0, 1.0))


func set_speed(kmh: float, nitro: bool) -> void:
	if nitro and not _was_nitro and _taps > 0:
		_burst = BURST_PEAK
	_was_nitro = nitro
	_target = clampf(blur_for(kmh, nitro), 0.0, 1.0) if _taps > 0 else 0.0


## Blur samples for a graphics preset and a reduced_motion level: off 0, low at most 3, high as the preset.
static func blur_taps_for(preset_id: String, motion: String) -> int:
	if motion == "off":
		return 0
	var taps: int = int(BLUR_TAPS.get(preset_id, 5))
	return mini(taps, 3) if motion == "low" else taps


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
