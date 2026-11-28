extends Node
## Graphics presets, audio buses, controls and language. Saved to user://settings.cfg.
## Graphics values come from GraphicsPreset (see graphics_preset.gd).

signal changed(section: String)

const SECTION_GRAPHICS: String = "graphics"
const SECTION_AUDIO: String = "audio"
const SECTION_CONTROLS: String = "controls"
const SECTION_GENERAL: String = "general"
const PRESET_IDS: PackedStringArray = ["low", "medium", "high"]
const STEERING_MODES: PackedStringArray = ["buttons", "tilt"]
const LANGUAGES: PackedStringArray = ["tr", "en"]
## Frame rate caps offered in the settings screen (Engine.max_fps).
const FPS_CAPS: PackedInt32Array = [30, 60]
## Settings key -> AudioServer bus name. Missing buses are created at startup.
const AUDIO_BUSES: Dictionary = {"master": "Master", "music": "Music", "sfx": "SFX", "engine": "Engine", "ui": "UI"}
const DEFAULT_VOLUMES: Dictionary = {"master": 1.0, "music": 0.8, "sfx": 1.0, "engine": 1.0, "ui": 1.0}
const MUTE_DB: float = -80.0
## Float slack so that a step lands once per interval even after summing many frame deltas.
const TIME_EPS: float = 0.0001

@export var config_path: String = "user://settings.cfg"
## Dynamic resolution: frames slower than dyn_slow_ms step the scale down, faster than
## dyn_fast_ms step it up. The gap between the two is the hysteresis band.
@export_range(1.0, 100.0, 0.5) var dyn_slow_ms: float = 18.0
@export_range(1.0, 100.0, 0.5) var dyn_fast_ms: float = 13.0
@export_range(0.01, 0.5, 0.01) var dyn_step: float = 0.05
@export_range(0.1, 10.0, 0.1) var dyn_step_interval_s: float = 1.0

## When false, setters change memory only and nothing is written to config_path.
## The capture harness turns this off so a screenshot run never rewrites the player's settings.
var autosave: bool = true
var steering_mode: String = "buttons"
var auto_accelerate: bool = true
var haptics: bool = true
var camera_shake: float = 0.6
var language: String = "en"
## Frame-time card (ui/hud/perf_card.gd). Default on only in TestFlight builds (export feature "testflight").
## No settings-screen row yet: set [general] perf_card in settings.cfg to turn it on elsewhere.
var perf_card: bool = OS.has_feature("testflight")

var _presets: Dictionary = {}
var _preset_id: String = "medium"
var _dynamic_resolution: bool = false
var _scale: float = 0.85
var fps_cap: int = 60
var _since_step: float = 0.0
var _volumes: Dictionary = {}
var _viewport: Viewport = null
var _loading: bool = false


func _init() -> void:
	for id: String in PRESET_IDS:
		_presets[id] = GraphicsPreset.build(id)
	_volumes = DEFAULT_VOLUMES.duplicate()
	_select_preset("medium")


func _ready() -> void:
	ensure_audio_buses()
	load_settings()
	Engine.max_fps = fps_cap
	for key: String in AUDIO_BUSES:
		_apply_bus(key)
	_apply_renderer()
	attach_viewport(get_tree().root)


func _process(delta: float) -> void:
	if _dynamic_resolution and is_instance_valid(_viewport):
		dynamic_resolution_tick(delta * 1000.0, delta)


# --- graphics ---------------------------------------------------------------

func get_preset() -> GraphicsPreset:
	return _presets[_preset_id] as GraphicsPreset


func get_preset_id() -> String:
	return _preset_id


func get_render_scale() -> float:
	return _scale


func get_dynamic_resolution() -> bool:
	return _dynamic_resolution


func get_fps_cap() -> int:
	return fps_cap


## Caps the frame rate through Engine.max_fps. Only values in FPS_CAPS are accepted.
func set_fps_cap(fps: int) -> bool:
	if not FPS_CAPS.has(fps):
		return false
	fps_cap = fps
	Engine.max_fps = fps
	_changed(SECTION_GRAPHICS)
	return true


func set_preset(id: String) -> bool:
	if not _presets.has(id):
		push_warning("Settings: unknown preset '%s'" % id)
		return false
	_select_preset(id)
	_apply_renderer()
	if is_instance_valid(_viewport):
		apply_to_viewport(_viewport)
	_changed(SECTION_GRAPHICS)
	return true


## Ignored (stays off) unless the preset's scaling is confirmed on device.
func set_dynamic_resolution(on: bool) -> void:
	var p: GraphicsPreset = get_preset()
	_dynamic_resolution = on and p.scaling_confirmed_on_device
	_since_step = 0.0
	if not _dynamic_resolution:
		_scale = p.effective_scale()
	if is_instance_valid(_viewport):
		_viewport.scaling_3d_scale = _scale
	_changed(SECTION_GRAPHICS)


## Makes vp the viewport that dynamic resolution steps and that set_preset() updates.
func attach_viewport(vp: Viewport) -> void:
	_viewport = vp
	apply_to_viewport(vp)


func apply_to_viewport(vp: Viewport) -> void:
	vp.msaa_3d = get_preset().msaa_3d
	vp.screen_space_aa = get_preset().screen_space_aa
	vp.scaling_3d_scale = _scale


func apply_to_environment(env: Environment) -> void:
	var p: GraphicsPreset = get_preset()
	env.glow_enabled = p.glow_enabled
	env.glow_intensity = p.glow_intensity


## Call once per frame with the frame time in ms and the delta in seconds. Returns the scale in use.
## Steps at most once per dyn_step_interval_s, and only when the frame time leaves the hysteresis band.
func dynamic_resolution_tick(frame_ms: float, delta_s: float) -> float:
	if not _dynamic_resolution:
		return _scale
	_since_step += delta_s
	if _since_step + TIME_EPS < dyn_step_interval_s:
		return _scale
	var next: float = _scale
	if frame_ms > dyn_slow_ms:
		next = _scale - dyn_step
	elif frame_ms < dyn_fast_ms:
		next = _scale + dyn_step
	var p: GraphicsPreset = get_preset()
	next = clampf(next, p.min_scaling_3d_scale, p.effective_scale())
	if is_equal_approx(next, _scale):
		return _scale
	_scale = next
	_since_step = 0.0
	if is_instance_valid(_viewport):
		_viewport.scaling_3d_scale = _scale
	return _scale


func _select_preset(id: String) -> void:
	_preset_id = id
	var p: GraphicsPreset = _presets[id] as GraphicsPreset
	_dynamic_resolution = p.dynamic_resolution and p.scaling_confirmed_on_device
	_scale = p.effective_scale()
	_since_step = 0.0


func _apply_renderer() -> void:
	RenderingServer.directional_shadow_atlas_set_size(get_preset().directional_shadow_size, false)
	RenderingServer.directional_soft_shadow_filter_set_quality(get_preset().shadow_filter)


# --- audio ------------------------------------------------------------------

func ensure_audio_buses() -> void:
	for key: String in AUDIO_BUSES:
		var bus_name: String = AUDIO_BUSES[key]
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func get_volume(key: String) -> float:
	return _volumes[key]


## linear 0..1, stored in settings and applied to the bus in dB.
func set_volume(key: String, linear: float) -> void:
	if not AUDIO_BUSES.has(key):
		push_warning("Settings: unknown audio bus '%s'" % key)
		return
	_volumes[key] = clampf(linear, 0.0, 1.0)
	_apply_bus(key)
	_changed(SECTION_AUDIO)


func _apply_bus(key: String) -> void:
	var bus_name: String = AUDIO_BUSES[key]
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v: float = _volumes[key]
	AudioServer.set_bus_volume_db(idx, MUTE_DB if v <= 0.0 else linear_to_db(v))


# --- controls and language --------------------------------------------------

func set_steering_mode(mode: String) -> bool:
	if not STEERING_MODES.has(mode):
		return false
	steering_mode = mode
	_changed(SECTION_CONTROLS)
	return true


func set_auto_accelerate(on: bool) -> void:
	auto_accelerate = on
	_changed(SECTION_CONTROLS)


func set_haptics(on: bool) -> void:
	haptics = on
	_changed(SECTION_CONTROLS)


func set_camera_shake(amount: float) -> void:
	camera_shake = clampf(amount, 0.0, 1.0)
	_changed(SECTION_CONTROLS)


func set_language(lang: String) -> bool:
	if not LANGUAGES.has(lang):
		return false
	language = lang
	_changed(SECTION_GENERAL)
	return true


func set_perf_card(on: bool) -> void:
	perf_card = on
	_changed(SECTION_GENERAL)


## Emits changed, and writes config_path first unless autosave is off or a load is in progress.
func _changed(section: String) -> void:
	if autosave and not _loading:
		save_settings()
	changed.emit(section)


# --- persistence ------------------------------------------------------------

func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_GRAPHICS, "preset", _preset_id)
	cfg.set_value(SECTION_GRAPHICS, "dynamic_resolution", _dynamic_resolution)
	cfg.set_value(SECTION_GRAPHICS, "fps_cap", fps_cap)
	for key: String in AUDIO_BUSES:
		cfg.set_value(SECTION_AUDIO, key, _volumes[key])
	cfg.set_value(SECTION_CONTROLS, "steering_mode", steering_mode)
	cfg.set_value(SECTION_CONTROLS, "auto_accelerate", auto_accelerate)
	cfg.set_value(SECTION_CONTROLS, "haptics", haptics)
	cfg.set_value(SECTION_CONTROLS, "camera_shake", camera_shake)
	cfg.set_value(SECTION_GENERAL, "language", language)
	cfg.set_value(SECTION_GENERAL, "perf_card", perf_card)
	var ok: bool = cfg.save(config_path) == OK
	if not ok:
		push_warning("Settings: cannot write %s" % config_path)
	return ok


## Invalid values in the file fall back to the current value. Returns false if the file is missing.
func load_settings() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return false
	_loading = true
	set_preset(_read_string(cfg, SECTION_GRAPHICS, "preset", _preset_id, PRESET_IDS))
	set_dynamic_resolution(_read_bool(cfg, SECTION_GRAPHICS, "dynamic_resolution", _dynamic_resolution))
	set_fps_cap(_read_fps(cfg))
	for key: String in AUDIO_BUSES:
		_volumes[key] = _read_float(cfg, SECTION_AUDIO, key, _volumes[key], 0.0, 1.0)
		_apply_bus(key)
	steering_mode = _read_string(cfg, SECTION_CONTROLS, "steering_mode", steering_mode, STEERING_MODES)
	auto_accelerate = _read_bool(cfg, SECTION_CONTROLS, "auto_accelerate", auto_accelerate)
	haptics = _read_bool(cfg, SECTION_CONTROLS, "haptics", haptics)
	camera_shake = _read_float(cfg, SECTION_CONTROLS, "camera_shake", camera_shake, 0.0, 1.0)
	language = _read_string(cfg, SECTION_GENERAL, "language", language, LANGUAGES)
	perf_card = _read_bool(cfg, SECTION_GENERAL, "perf_card", perf_card)
	_loading = false
	for section: String in [SECTION_GRAPHICS, SECTION_AUDIO, SECTION_CONTROLS, SECTION_GENERAL]:
		changed.emit(section)
	return true


func _read_fps(cfg: ConfigFile) -> int:
	var v: Variant = cfg.get_value(SECTION_GRAPHICS, "fps_cap", fps_cap)
	if (v is int or v is float) and FPS_CAPS.has(int(v)):
		return int(v)
	return fps_cap


func _read_bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var v: Variant = cfg.get_value(section, key, fallback)
	return v if v is bool else fallback


func _read_float(cfg: ConfigFile, section: String, key: String, fallback: float, lo: float, hi: float) -> float:
	var v: Variant = cfg.get_value(section, key, fallback)
	if v is float or v is int:
		return clampf(float(v), lo, hi)
	return fallback


func _read_string(cfg: ConfigFile, section: String, key: String, fallback: String, allowed: PackedStringArray) -> String:
	var v: Variant = cfg.get_value(section, key, fallback)
	if v is String and allowed.has(v):
		return v
	return fallback
