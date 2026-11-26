class_name RainOnLens
extends CanvasLayer
## Rain on the lens: a full-screen layer of sliding drops that refract the frame behind them (rain_on_lens.gdshader).
## Layer 3: under the speed lines (5) and the race HUD (10), so the speedometer and text stay sharp.
## Medium and High with rain_enabled only (Low never). set_strength(v) takes 0..1: pass RainFx.rain_factor() while it
## rains, 0 at sunset and day. The layer is hidden (no screen copy) once it fades out.

const SHADER_PATH: String = "res://shaders/rain_on_lens.gdshader"
const LAYER: int = 3
const FADE_S: float = 0.6
const LOW_PRESET_ID: String = "low"

@export_range(0.0, 1.0, 0.01) var max_strength: float = 0.8

var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _allowed: bool = true
var _target: float = 0.0
var _level: float = 0.0


func _ready() -> void:
	layer = LAYER
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH) as Shader
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)
	Settings.changed.connect(_on_settings_changed)
	_apply_settings()


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.disconnect(_on_settings_changed)


func _process(delta: float) -> void:
	var goal: float = _target if _allowed else 0.0
	_level = move_toward(_level, goal, delta / FADE_S)
	_mat.set_shader_parameter("strength", _level)
	_rect.visible = _level > 0.001


## 0 = no drops, 1 = max_strength. Ignored (stays 0) on the Low preset or with rain_enabled off.
func set_strength(v: float) -> void:
	_target = clampf(v, 0.0, 1.0) * max_strength


func level() -> float:
	return _level


func is_allowed() -> bool:
	return _allowed


func _on_settings_changed(_section: String) -> void:
	_apply_settings()


func _apply_settings() -> void:
	_allowed = Settings.get_preset().rain_enabled and Settings.get_preset_id() != LOW_PRESET_ID
