class_name SettingsMenu
extends Control
## Settings screen. Reads and writes the Settings autoload directly; no copy of the values lives here.
## Two cards (graphics + audio, controls + language), every row at least 44 pt tall on a phone, whole rows focusable.
## overlay = false: BACK goes to the main menu. overlay = true (pause menu): BACK emits closed and frees itself.

signal closed

const MAIN_MENU_SCENE: String = "res://ui/menus/main_menu.tscn"
const TITLE_PX: int = 44
const SECTION_PX: int = 18
const ROW_LABEL_PX: int = 24
const VALUE_PX: int = 24
const CONTROL_W: float = 300.0
const VALUE_W: float = 84.0
const ROW_H: float = 56.0
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 48.0
const ROW_GAP_PX: int = 6
const SECTION_GAP_PX: int = 24
const CARD_PAD_PX: int = 28
const VOLUME_PERCENT: float = 100.0

@export var overlay: bool = false

var _title: Label
var _back_btn: Button
var _section_labels: Dictionary = {}  ## section key -> [Label, text key]
var _row_labels: Dictionary = {}  ## row key -> [Label or Button, text key]
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

const VOLUME_KEYS: Array[String] = ["master", "music", "sfx", "engine", "ui"]
const VOLUME_LABEL_KEYS: Dictionary = {
	"master": "settings.master", "music": "settings.music", "sfx": "settings.sfx", "engine": "settings.engine",
	"ui": "settings.ui"}
const PRESET_KEYS: Array[String] = ["settings.preset_low", "settings.preset_medium", "settings.preset_high"]
const STEER_KEYS: Array[String] = ["settings.steer_buttons", "settings.steer_tilt"]
const LANG_KEYS: Array[String] = ["settings.lang_tr", "settings.lang_en"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if overlay:
		var bg := ColorRect.new()
		bg.color = Color(MSTheme.BG.r, MSTheme.BG.g, MSTheme.BG.b, 0.97)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(bg)
	else:
		add_child(MenuBackdrop.new(0.0, 0.5))
		var dim := ColorRect.new()
		dim.color = Color(MSTheme.BG.r, MSTheme.BG.g, MSTheme.BG.b, 0.78)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
	_build()
	_sync_from_settings()
	Settings.changed.connect(_on_settings_changed)
	_refresh_text()
	_back_btn.grab_focus()


func _row_h() -> float:
	return MSTheme.button_h() if MSTheme.phone else ROW_H


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
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_title)
	_back_btn = Button.new()
	_back_btn.custom_minimum_size = Vector2(MSTheme.BUTTON_MIN_W * 0.6, MSTheme.button_h())
	_back_btn.pressed.connect(func() -> void: UiSounds.click())
	_back_btn.pressed.connect(_on_back)
	head.add_child(_back_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	col.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", SECTION_GAP_PX)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)

	var left: VBoxContainer = _card(cols)
	_section(left, "graphics", "settings.graphics")
	_preset_opt = _option()
	_row(left, "preset", "settings.preset", _preset_opt)
	_dynres = _toggle(left, "dynres", "settings.dynres")
	_section(left, "audio", "settings.audio")
	for key: String in VOLUME_KEYS:
		var v: Label = _value_label()
		var s: HSlider = _slider(v)
		s.value_changed.connect(_on_volume.bind(key))
		_volume_sliders[key] = s
		_volume_vals[key] = v
		_row(left, "vol_" + key, VOLUME_LABEL_KEYS[key], _slider_box(s, v))

	var right: VBoxContainer = _card(cols)
	_section(right, "controls", "settings.controls")
	_steer_opt = _option()
	_row(right, "steering", "settings.steering", _steer_opt)
	_auto_accel = _toggle(right, "auto_accel", "settings.auto_accel")
	_haptics = _toggle(right, "haptics", "settings.haptics")
	_shake_val = _value_label()
	_shake = _slider(_shake_val)
	_row(right, "shake", "settings.camera_shake", _slider_box(_shake, _shake_val))
	_lang_opt = _option()
	_row(right, "lang", "settings.language", _lang_opt)

	_preset_opt.item_selected.connect(_on_preset)
	_dynres.toggled.connect(_on_dynres)
	_steer_opt.item_selected.connect(_on_steering)
	_auto_accel.toggled.connect(_on_auto_accel)
	_haptics.toggled.connect(_on_haptics)
	_shake.value_changed.connect(_on_shake)
	_lang_opt.item_selected.connect(_on_language)


## A backing card; returns the column rows go into.
func _card(parent: Container) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", MSTheme.card(MSTheme.PLATE_BG, MSTheme.BORDER))
	parent.add_child(panel)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, CARD_PAD_PX)
	panel.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", ROW_GAP_PX)
	pad.add_child(v)
	return v


func _option() -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(CONTROL_W + VALUE_W, _row_h())
	o.fit_to_longest_item = false
	o.get_popup().add_theme_constant_override("v_separation", MSTheme.px(14.0))
	return o


func _value_label() -> Label:
	var v: Label = MSTheme.make_label("", "digits", MSTheme.px(VALUE_PX), MSTheme.CYAN)
	v.custom_minimum_size = Vector2(VALUE_W, 0.0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return v


func _slider(_value_lbl: Label) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.custom_minimum_size = Vector2(CONTROL_W, _row_h())
	return s


func _slider_box(s: HSlider, v: Label) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", MSTheme.GRID_PX)
	box.add_child(s)
	box.add_child(v)
	return box


## Section header with a hairline under it.
func _section(parent: Container, key: String, text_key: String) -> void:
	if parent.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0.0, SECTION_GAP_PX)
		parent.add_child(gap)
	var l: Label = MSTheme.make_label("", "tracked", MSTheme.px(SECTION_PX), MSTheme.CYAN)
	parent.add_child(l)
	var rule := ColorRect.new()
	rule.color = MSTheme.tint(MSTheme.CYAN, 0.35)
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	parent.add_child(rule)
	_section_labels[key] = [l, text_key]


func _row(parent: Container, key: String, text_key: String, control: Control) -> void:
	var line := HBoxContainer.new()
	line.custom_minimum_size = Vector2(0.0, _row_h())
	line.add_theme_constant_override("separation", MSTheme.GRID_PX * 2)
	var l: Label = MSTheme.make_label("", "bold", MSTheme.px(ROW_LABEL_PX), MSTheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(l)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(control)
	parent.add_child(line)
	_row_labels[key] = [l, text_key]


## A toggle whose whole row is the touch target and the focus target: label left, switch right.
func _toggle(parent: Container, key: String, text_key: String) -> CheckButton:
	var c := CheckButton.new()
	c.custom_minimum_size = Vector2(0.0, _row_h())
	c.alignment = HORIZONTAL_ALIGNMENT_LEFT
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	_row_labels[key] = [c, text_key]
	return c


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
		(pair[0] as Control).set("text", I18n.t(pair[1]))
	for i: int in PRESET_KEYS.size():
		_preset_opt.set_item_text(i, I18n.t(PRESET_KEYS[i]))
	for i: int in STEER_KEYS.size():
		_steer_opt.set_item_text(i, I18n.t(STEER_KEYS[i]))
	for i: int in LANG_KEYS.size():
		_lang_opt.set_item_text(i, I18n.t(LANG_KEYS[i]))


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()


func _on_back() -> void:
	if overlay:
		closed.emit()
		queue_free()
	else:
		Router.goto(MAIN_MENU_SCENE)
