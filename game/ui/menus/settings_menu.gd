class_name SettingsMenu
extends Control
## Settings screen in five tabs: GRAPHICS, CONTROLS, AUDIO, LANGUAGE, ABOUT. Reads and writes the Settings autoload directly.
## Every control is a touch target of TOUCH_PX (MSTheme scales it on the phone layout).
## overlay = false: BACK goes to the main menu. overlay = true (pause menu): BACK emits closed and frees itself.

signal closed

const MAIN_MENU_SCENE: String = "res://ui/menus/main_menu.tscn"
const TOUCH_PX: float = 88.0  ## base px; MSTheme.px() gives 132 px (44 pt) on the phone layout
const TITLE_PX: int = 44
const SECTION_PX: int = 18
const ROW_LABEL_PX: int = 24
const VALUE_PX: int = 24
const DESC_PX: int = 20
const CONTROL_W: float = 360.0
const VALUE_W: float = 84.0
const BACK_W: float = 220.0
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 48.0
const ROW_GAP_PX: int = 8
const SECTION_GAP_PX: int = 24
const VOLUME_PERCENT: float = 100.0

const TAB_TEXT_KEYS: Array[String] = ["settings.graphics", "settings.controls", "settings.audio", "settings.language", "settings.about"]
const VOLUME_KEYS: Array[String] = ["master", "music", "sfx", "engine", "ui"]
const VOLUME_LABEL_KEYS: Dictionary = {
	"master": "settings.master", "music": "settings.music", "sfx": "settings.sfx", "engine": "settings.engine",
	"ui": "settings.ui"}
const PRESET_KEYS: Array[String] = ["settings.preset_low", "settings.preset_medium", "settings.preset_high"]
const PRESET_DESC_KEYS: Array[String] = ["settings.preset_desc_low", "settings.preset_desc_medium", "settings.preset_desc_high"]
const STEER_KEYS: Array[String] = ["settings.steer_buttons", "settings.steer_tilt"]
const LANG_KEYS: Array[String] = ["settings.lang_tr", "settings.lang_en"]

@export var overlay: bool = false

var _title: Label
var _back_btn: Button
var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _scroll: ScrollContainer
var _texts: Dictionary = {}  ## Label or Button -> text key
var _options: Dictionary = {}  ## OptionButton -> Array of text keys, one per item
var _preset_opt: OptionButton
var _preset_desc: Label
var _fps_opt: OptionButton
var _steer_opt: OptionButton
var _auto_accel: CheckButton
var _haptics: CheckButton
var _shake: HSlider
var _shake_val: Label
var _lang_opt: OptionButton
var _volume_sliders: Dictionary = {}  ## bus key -> HSlider
var _volume_vals: Dictionary = {}  ## bus key -> Label
var _credits: CreditsPanel
var _syncing: bool = false


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
	show_tab(0)


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
	_title = MSTheme.make_label("", "bold", MSTheme.px(TITLE_PX), MSTheme.TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_title)
	_texts[_title] = "settings.title"
	_back_btn = Button.new()
	_back_btn.custom_minimum_size = Vector2(MSTheme.px(BACK_W), MSTheme.px(TOUCH_PX))
	_back_btn.pressed.connect(func() -> void: UiSounds.click())
	_back_btn.pressed.connect(_on_back)
	head.add_child(_back_btn)
	_texts[_back_btn] = "common.back"

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", MSTheme.GRID_PX)
	col.add_child(tab_bar)
	var group := ButtonGroup.new()
	for i: int in TAB_TEXT_KEYS.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0.0, MSTheme.px(TOUCH_PX))
		b.toggled.connect(_on_tab.bind(i))
		tab_bar.add_child(b)
		_tabs.append(b)
		_texts[b] = TAB_TEXT_KEYS[i]

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	col.add_child(_scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", SECTION_GAP_PX)
	_scroll.add_child(stack)

	_build_graphics(_page(stack))
	_build_controls(_page(stack))
	_build_audio(_page(stack))
	_build_language(_page(stack))
	_build_about(_page(stack))

	_preset_opt.item_selected.connect(_on_preset)
	_fps_opt.item_selected.connect(_on_fps)
	_steer_opt.item_selected.connect(_on_steering)
	_auto_accel.toggled.connect(_on_auto_accel)
	_haptics.toggled.connect(_on_haptics)
	_shake.value_changed.connect(_on_shake)
	_lang_opt.item_selected.connect(_on_language)


func _build_graphics(p: VBoxContainer) -> void:
	_section(p, "settings.graphics")
	_preset_opt = _option(PRESET_KEYS)
	_row(p, "settings.preset", _preset_opt)
	_preset_desc = MSTheme.make_label("", "bold", MSTheme.px(DESC_PX), MSTheme.MUTED)
	_preset_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(_preset_desc)
	_section(p, "settings.perf_group")
	_fps_opt = _option([])
	for fps: int in Settings.FPS_CAPS:
		_fps_opt.add_item("%d FPS" % fps)
	_row(p, "settings.fps_cap", _fps_opt)


func _build_controls(p: VBoxContainer) -> void:
	_section(p, "settings.controls")
	_steer_opt = _option(STEER_KEYS)
	_row(p, "settings.steering", _steer_opt)
	_auto_accel = _toggle(p, "settings.auto_accel")
	_haptics = _toggle(p, "settings.haptics")
	_shake_val = _value_label()
	_shake = _slider()
	_row(p, "settings.camera_shake", _slider_box(_shake, _shake_val))


func _build_audio(p: VBoxContainer) -> void:
	_section(p, "settings.audio")
	for key: String in VOLUME_KEYS:
		var v: Label = _value_label()
		var s: HSlider = _slider()
		s.value_changed.connect(_on_volume.bind(key))
		_volume_sliders[key] = s
		_volume_vals[key] = v
		_row(p, VOLUME_LABEL_KEYS[key], _slider_box(s, v))


func _build_language(p: VBoxContainer) -> void:
	_section(p, "settings.language")
	_lang_opt = _option(LANG_KEYS)
	_row(p, "settings.language", _lang_opt)


func _build_about(p: VBoxContainer) -> void:
	_section(p, "settings.credits")
	var hint: Label = MSTheme.make_label("", "bold", MSTheme.px(DESC_PX), MSTheme.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(hint)
	_texts[hint] = "settings.credits_hint"
	_credits = CreditsPanel.new()
	p.add_child(_credits)


## One tab page. Pages are stacked inside the scroll; show_tab() shows exactly one.
func _page(parent: Container) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", ROW_GAP_PX)
	parent.add_child(v)
	_pages.append(v)
	return v


## Shows one tab page, marks its tab as pressed and scrolls to the top.
func show_tab(index: int) -> void:
	for i: int in _pages.size():
		_pages[i].visible = i == index
	_tabs[index].button_pressed = true
	_tabs[index].grab_focus()  # keep the focus ring on the shown tab, not on a stale one
	_scroll.scroll_vertical = 0


func _on_tab(on: bool, index: int) -> void:
	if on:
		show_tab(index)


func _option(keys: Array) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(MSTheme.px(CONTROL_W + VALUE_W), MSTheme.px(TOUCH_PX))
	o.fit_to_longest_item = false
	o.get_popup().add_theme_constant_override("v_separation", MSTheme.px(14.0))
	for _k: String in keys:
		o.add_item("")
	if not keys.is_empty():
		_options[o] = keys
	return o


func _value_label() -> Label:
	var v: Label = MSTheme.make_label("", "digits", MSTheme.px(VALUE_PX), MSTheme.CYAN)
	v.custom_minimum_size = Vector2(MSTheme.px(VALUE_W), 0.0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return v


func _slider() -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.custom_minimum_size = Vector2(MSTheme.px(CONTROL_W), MSTheme.px(TOUCH_PX))
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


func _slider_box(s: HSlider, v: Label) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", MSTheme.GRID_PX)
	box.add_child(s)
	box.add_child(v)
	return box


## Section header with a hairline under it.
func _section(parent: Container, text_key: String) -> void:
	if parent.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0.0, SECTION_GAP_PX)
		parent.add_child(gap)
	var l: Label = MSTheme.make_label("", "tracked", MSTheme.px(SECTION_PX), MSTheme.CYAN)
	parent.add_child(l)
	_texts[l] = text_key
	var rule := ColorRect.new()
	rule.color = MSTheme.tint(MSTheme.CYAN, 0.35)
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	parent.add_child(rule)


## One setting: label left, control right, the whole row at least TOUCH_PX tall.
func _row(parent: Container, text_key: String, control: Control) -> void:
	var line := HBoxContainer.new()
	line.custom_minimum_size = Vector2(0.0, MSTheme.px(TOUCH_PX))
	line.add_theme_constant_override("separation", MSTheme.GRID_PX * 2)
	var l: Label = MSTheme.make_label("", "bold", MSTheme.px(ROW_LABEL_PX), MSTheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(l)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(control)
	parent.add_child(line)
	_texts[l] = text_key


## A switch whose whole row is the touch and focus target: label left, switch right.
func _toggle(parent: Container, text_key: String) -> CheckButton:
	var c := CheckButton.new()
	c.custom_minimum_size = Vector2(0.0, MSTheme.px(TOUCH_PX))
	c.alignment = HORIZONTAL_ALIGNMENT_LEFT
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	_texts[c] = text_key
	return c


func _sync_from_settings() -> void:
	_syncing = true
	_preset_opt.select(maxi(Settings.PRESET_IDS.find(Settings.get_preset_id()), 0))
	_fps_opt.select(maxi(Settings.FPS_CAPS.find(Settings.get_fps_cap()), 0))
	for key: String in VOLUME_KEYS:
		var v: float = Settings.get_volume(key)
		(_volume_sliders[key] as HSlider).set_value_no_signal(v)
		(_volume_vals[key] as Label).text = _percent(v)
	_steer_opt.select(maxi(Settings.STEERING_MODES.find(Settings.steering_mode), 0))
	_auto_accel.set_pressed_no_signal(Settings.auto_accelerate)
	_haptics.set_pressed_no_signal(Settings.haptics)
	_shake.set_value_no_signal(Settings.camera_shake)
	_shake_val.text = _percent(Settings.camera_shake)
	_lang_opt.select(maxi(Settings.LANGUAGES.find(Settings.language), 0))
	_syncing = false


func _refresh_text() -> void:
	for node: Object in _texts:
		node.set("text", I18n.t(_texts[node]))
	for opt: OptionButton in _options:
		var keys: Array = _options[opt]
		for i: int in keys.size():
			opt.set_item_text(i, I18n.t(keys[i]))
	var idx: int = maxi(Settings.PRESET_IDS.find(Settings.get_preset_id()), 0)
	_preset_desc.text = I18n.t(PRESET_DESC_KEYS[idx])


func _percent(v: float) -> String:
	return "%d%%" % roundi(v * VOLUME_PERCENT)


func _on_settings_changed(_section: String) -> void:
	_refresh_text()


func _on_preset(index: int) -> void:
	if not _syncing:
		Settings.set_preset(Settings.PRESET_IDS[index])


func _on_fps(index: int) -> void:
	if not _syncing:
		Settings.set_fps_cap(Settings.FPS_CAPS[index])


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
