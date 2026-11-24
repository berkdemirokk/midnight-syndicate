class_name SettingsMenu
extends Control
## Settings screen. Reads and writes the Settings autoload directly; no copy of the values lives here.
## overlay = false: BACK goes to the main menu. overlay = true (pause menu): BACK emits closed and frees itself.

signal closed

const MAIN_MENU_SCENE: String = "res://ui/menus/main_menu.tscn"
const TITLE_PX: int = 40
const SECTION_PX: int = 18
const ROW_LABEL_PX: int = 24
const VALUE_PX: int = 22
const COL_W: float = 480.0
const SLIDER_W: float = 260.0
const SLIDER_VALUE_W: float = 64.0
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 48.0
const ROW_GAP_PX: int = 16
const SECTION_GAP_PX: int = 32
const VOLUME_PERCENT: float = 100.0

@export var overlay: bool = false

var _title: Label
var _back_btn: Button
var _section_labels: Dictionary = {}  ## section key -> Label
var _row_labels: Dictionary = {}  ## row key -> Label
var _preset_opt: OptionButton
var _dynres: CheckButton
var _steer_opt: OptionButton
var _auto_accel: CheckButton
var _haptics: CheckButton
var _shake: HSlider
var _shake_val: Label
var _lang_opt: OptionButton
var _volume_sliders: Dictionary = {}  ## bus key -> HSlider
var _volume_vals: Dictionary = {}  ## bus key -> Label
var _syncing: bool = false

const VOLUME_KEYS: Array[String] = ["master", "music", "sfx", "engine"]
const VOLUME_LABEL_KEYS: Dictionary = {
	"master": "settings.master", "music": "settings.music", "sfx": "settings.sfx", "engine": "settings.engine"}
const PRESET_KEYS: Array[String] = ["settings.preset_low", "settings.preset_medium", "settings.preset_high"]
const STEER_KEYS: Array[String] = ["settings.steer_buttons", "settings.steer_tilt"]
const LANG_KEYS: Array[String] = ["settings.lang_tr", "settings.lang_en"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = MSTheme.BG if not overlay else Color(MSTheme.BG.r, MSTheme.BG.g, MSTheme.BG.b, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	_build()
	_sync_from_settings()
	Settings.changed.connect(_on_settings_changed)
	_refresh_text()
	_back_btn.grab_focus()


func _build() -> void:
	var ins: Vector4 = MSTheme.safe_insets()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(ins.x + EDGE_PX))
	margin.add_theme_constant_override("margin_top", int(ins.y + EDGE_Y_PX))
	margin.add_theme_constant_override("margin_right", int(ins.z + EDGE_PX))
	margin.add_theme_constant_override("margin_bottom", int(ins.w + EDGE_Y_PX))
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", SECTION_GAP_PX)
	margin.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	_title = MSTheme.make_label("", "bold", TITLE_PX, MSTheme.TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_back_btn = Button.new()
	_back_btn.custom_minimum_size = Vector2(COL_W * 0.5, MSTheme.BUTTON_MIN_H)
	_back_btn.pressed.connect(_on_back)
	head.add_child(_back_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", SECTION_GAP_PX * 2)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(COL_W, 0.0)
	left.add_theme_constant_override("separation", ROW_GAP_PX)
	cols.add_child(left)
	_section(left, "graphics", "settings.graphics")
	_preset_opt = OptionButton.new()
	_preset_opt.custom_minimum_size = Vector2(SLIDER_W + SLIDER_VALUE_W, MSTheme.BUTTON_MIN_H * 0.75)
	_row(left, "preset", "settings.preset", _preset_opt)
	_dynres = CheckButton.new()
	_row(left, "dynres", "settings.dynres", _dynres)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, SECTION_GAP_PX)
	left.add_child(gap)
	_section(left, "audio", "settings.audio")
	for key: String in VOLUME_KEYS:
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.01
		s.custom_minimum_size = Vector2(SLIDER_W, MSTheme.BUTTON_MIN_H * 0.5)
		s.value_changed.connect(_on_volume.bind(key))
		_volume_sliders[key] = s
		var v: Label = MSTheme.make_label("", "digits", VALUE_PX, MSTheme.CYAN)
		v.custom_minimum_size = Vector2(SLIDER_VALUE_W, 0.0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_volume_vals[key] = v
		var box := HBoxContainer.new()
		box.add_child(s)
		box.add_child(v)
		_row(left, "vol_" + key, VOLUME_LABEL_KEYS[key], box)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(COL_W, 0.0)
	right.add_theme_constant_override("separation", ROW_GAP_PX)
	cols.add_child(right)
	_section(right, "controls", "settings.controls")
	_steer_opt = OptionButton.new()
	_steer_opt.custom_minimum_size = Vector2(SLIDER_W + SLIDER_VALUE_W, MSTheme.BUTTON_MIN_H * 0.75)
	_row(right, "steering", "settings.steering", _steer_opt)
	_auto_accel = CheckButton.new()
	_row(right, "auto_accel", "settings.auto_accel", _auto_accel)
	_haptics = CheckButton.new()
	_row(right, "haptics", "settings.haptics", _haptics)
	_shake = HSlider.new()
	_shake.min_value = 0.0
	_shake.max_value = 1.0
	_shake.step = 0.01
	_shake.custom_minimum_size = Vector2(SLIDER_W, MSTheme.BUTTON_MIN_H * 0.5)
	_shake_val = MSTheme.make_label("", "digits", VALUE_PX, MSTheme.CYAN)
	_shake_val.custom_minimum_size = Vector2(SLIDER_VALUE_W, 0.0)
	_shake_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var shake_box := HBoxContainer.new()
	shake_box.add_child(_shake)
	shake_box.add_child(_shake_val)
	_row(right, "shake", "settings.camera_shake", shake_box)
	_lang_opt = OptionButton.new()
	_lang_opt.custom_minimum_size = Vector2(SLIDER_W + SLIDER_VALUE_W, MSTheme.BUTTON_MIN_H * 0.75)
	_row(right, "lang", "settings.language", _lang_opt)

	_preset_opt.item_selected.connect(_on_preset)
	_dynres.toggled.connect(_on_dynres)
	_steer_opt.item_selected.connect(_on_steering)
	_auto_accel.toggled.connect(_on_auto_accel)
	_haptics.toggled.connect(_on_haptics)
	_shake.value_changed.connect(_on_shake)
	_lang_opt.item_selected.connect(_on_language)


func _section(parent: Container, key: String, text_key: String) -> void:
	var l: Label = MSTheme.make_label("", "tracked", SECTION_PX, MSTheme.CYAN)
	parent.add_child(l)
	_section_labels[key] = [l, text_key]


func _row(parent: Container, key: String, text_key: String, control: Control) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", MSTheme.GRID_PX * 2)
	var l: Label = MSTheme.make_label("", "bold", ROW_LABEL_PX, MSTheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(l)
	line.add_child(control)
	parent.add_child(line)
	_row_labels[key] = [l, text_key]


func _sync_from_settings() -> void:
	_syncing = true
	_preset_opt.clear()
	for _k: String in PRESET_KEYS:
		_preset_opt.add_item("")
	_preset_opt.select(maxi(Settings.PRESET_IDS.find(Settings.get_preset_id()), 0))
	_dynres.set_pressed_no_signal(Settings.get_dynamic_resolution())
	for key: String in VOLUME_KEYS:
		var v: float = Settings.get_volume(key)
		(_volume_sliders[key] as HSlider).set_value_no_signal(v)
		(_volume_vals[key] as Label).text = _percent(v)
	_steer_opt.clear()
	for _k: String in STEER_KEYS:
		_steer_opt.add_item("")
	_steer_opt.select(maxi(Settings.STEERING_MODES.find(Settings.steering_mode), 0))
	_auto_accel.set_pressed_no_signal(Settings.auto_accelerate)
	_haptics.set_pressed_no_signal(Settings.haptics)
	_shake.set_value_no_signal(Settings.camera_shake)
	_shake_val.text = _percent(Settings.camera_shake)
	_lang_opt.clear()
	for _k: String in LANG_KEYS:
		_lang_opt.add_item("")
	_lang_opt.select(maxi(Settings.LANGUAGES.find(Settings.language), 0))
	_syncing = false


func _refresh_text() -> void:
	_title.text = I18n.t("settings.title")
	_back_btn.text = I18n.t("common.back")
	for key: String in _section_labels:
		var pair: Array = _section_labels[key]
		(pair[0] as Label).text = I18n.t(pair[1])
	for key: String in _row_labels:
		var pair: Array = _row_labels[key]
		(pair[0] as Label).text = I18n.t(pair[1])
	for i: int in PRESET_KEYS.size():
		_preset_opt.set_item_text(i, I18n.t(PRESET_KEYS[i]))
	for i: int in STEER_KEYS.size():
		_steer_opt.set_item_text(i, I18n.t(STEER_KEYS[i]))
	for i: int in LANG_KEYS.size():
		_lang_opt.set_item_text(i, I18n.t(LANG_KEYS[i]))
	_dynres.text = ""
	_auto_accel.text = ""
	_haptics.text = ""


func _percent(v: float) -> String:
	return "%d%%" % roundi(v * VOLUME_PERCENT)


func _on_settings_changed(section: String) -> void:
	if section == Settings.SECTION_GENERAL:
		_refresh_text()


func _on_preset(index: int) -> void:
	if _syncing:
		return
	Settings.set_preset(Settings.PRESET_IDS[index])


func _on_dynres(on: bool) -> void:
	if not _syncing:
		Settings.set_dynamic_resolution(on)


func _on_volume(value: float, key: String) -> void:
	(_volume_vals[key] as Label).text = _percent(value)
	if not _syncing:
		Settings.set_volume(key, value)


func _on_steering(index: int) -> void:
	if not _syncing:
		Settings.set_steering_mode(Settings.STEERING_MODES[index])


func _on_auto_accel(on: bool) -> void:
	if not _syncing:
		Settings.set_auto_accelerate(on)


func _on_haptics(on: bool) -> void:
	if not _syncing:
		Settings.set_haptics(on)


func _on_shake(value: float) -> void:
	_shake_val.text = _percent(value)
	if not _syncing:
		Settings.set_camera_shake(value)


func _on_language(index: int) -> void:
	if not _syncing:
		Settings.set_language(Settings.LANGUAGES[index])


func _on_back() -> void:
	if overlay:
		closed.emit()
		queue_free()
	else:
		Router.goto(MAIN_MENU_SCENE)
