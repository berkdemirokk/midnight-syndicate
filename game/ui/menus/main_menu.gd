class_name MainMenu
extends Control
## Title screen: wordmark, RACE / GARAGE / SETTINGS / QUIT over a live night-city backdrop (menu_backdrop shader),
## and a career strip (stars, cash, rep). set_backdrop() can still swap in a real 3D scene behind the UI.
## Keyboard, gamepad and touch all reach the buttons through Godot's focus navigation.

const EVENT_SELECT_SCENE: String = "res://ui/menus/event_select.tscn"
const GARAGE_SCENE: String = "res://ui/garage/garage.tscn"
const SETTINGS_SCENE: String = "res://ui/menus/settings_menu.tscn"
const TAGLINE_PX: int = 20
const VERSION_PX: int = 16
const TOAST_PX: int = 22
const STAT_PX: int = 24
const STAT_CAP_PX: int = 16
const LOGO_GAP_PX: float = 36.0
const MENU_GAP_PX: float = 14.0
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 56.0
const MENU_W: float = 460.0
const TOAST_HOLD_S: float = 1.4
const TOAST_FADE_S: float = 0.4
const INTRO_S: float = 0.5
const INTRO_STAGGER_S: float = 0.07

var _holder: Control
var _backdrop: MenuBackdrop
var _race_btn: Button
var _garage_btn: Button
var _settings_btn: Button
var _quit_btn: Button
var _tagline: Label
var _version: Label
var _toast: Label
var _toast_tw: Tween = null
var _stat_stars: Label
var _stat_cash: Label
var _stat_rep: Label
var _stat_caps: Array[Label] = []
var _text_nodes: Array = []  ## [node, i18n key] pairs refreshed on language change


func _ready() -> void:
	MusicPlayer.get_instance().play_menu()
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop = MenuBackdrop.new(0.72)
	add_child(_backdrop)
	_holder = Control.new()
	_holder.name = "Backdrop3D"
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	_build_foreground()
	Settings.changed.connect(_on_settings_changed)
	GameState.profile_changed.connect(_refresh_stats)
	_refresh_text()
	_race_btn.grab_focus()
	_play_intro()


func _build_foreground() -> void:
	var ins: Vector4 = MSTheme.safe_insets()
	var margin := MarginContainer.new()
	margin.name = "Foreground"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(ins.x + EDGE_PX))
	margin.add_theme_constant_override("margin_top", int(ins.y + EDGE_Y_PX))
	margin.add_theme_constant_override("margin_right", int(ins.z + EDGE_PX))
	margin.add_theme_constant_override("margin_bottom", int(ins.w + EDGE_Y_PX))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 0)
	margin.add_child(col)

	var logo := Logotype.new(1.0 if not MSTheme.phone else 0.95)
	logo.name = "Logo"
	col.add_child(logo)
	_tagline = MSTheme.make_label("", "tracked", TAGLINE_PX, MSTheme.MUTED, false)
	_tagline.name = "Tagline"
	col.add_child(_tagline)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, LOGO_GAP_PX)
	col.add_child(gap)

	var menu := VBoxContainer.new()
	menu.name = "Menu"
	menu.add_theme_constant_override("separation", int(MENU_GAP_PX * (1.4 if MSTheme.phone else 1.0)))
	col.add_child(menu)
	_race_btn = _menu_button(menu, "menu.race", _on_race)
	_race_btn.theme_type_variation = &"PrimaryButton"
	_garage_btn = _menu_button(menu, "menu.garage", _on_garage)
	_settings_btn = _menu_button(menu, "menu.settings", _on_settings)
	_quit_btn = _menu_button(menu, "menu.quit", _on_quit)
	_quit_btn.visible = not (OS.has_feature("ios") or OS.has_feature("android"))

	# Career strip, bottom right: stars, cash, rep on one backing plate.
	var strip_margin := MarginContainer.new()
	strip_margin.name = "CareerStrip"
	strip_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	strip_margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	strip_margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip_margin.offset_right = -(ins.z + EDGE_PX * 0.6)
	strip_margin.offset_bottom = -(ins.w + EDGE_Y_PX * 0.8)
	strip_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip_margin)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", MSTheme.box(MSTheme.PLATE_BG, MSTheme.BORDER))
	strip_margin.add_child(plate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MSTheme.GRID_PX * 4)
	plate.add_child(row)
	_stat_stars = _stat(row, MSTheme.AMBER, "results.reward_stars")
	_stat_cash = _stat(row, MSTheme.AMBER, "results.reward_cash")
	_stat_rep = _stat(row, MSTheme.CYAN, "results.reward_rep")

	_version = MSTheme.make_label("", "tracked", VERSION_PX, MSTheme.MUTED, false)
	_version.name = "Version"
	_version.anchor_left = 1.0
	_version.anchor_right = 1.0
	_version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_version.offset_top = ins.y + EDGE_Y_PX * 0.5
	_version.offset_right = -(ins.z + EDGE_PX * 0.6)
	_version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_version)

	_toast = MSTheme.make_label("", "bold", TOAST_PX, MSTheme.AMBER, true)
	_toast.name = "Toast"
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = -(ins.w + EDGE_Y_PX * 2.0)
	_toast.offset_bottom = _toast.offset_top + TOAST_PX * 2.0
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)


## One caption over one value, tinted.
func _stat(parent: Container, ink: Color, cap_key: String) -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var cap: Label = MSTheme.make_label("", "tracked", MSTheme.px(STAT_CAP_PX), MSTheme.MUTED)
	cap.set_meta("key", cap_key)
	_stat_caps.append(cap)
	var val: Label = MSTheme.make_label("", "digits", MSTheme.px(STAT_PX), ink)
	box.add_child(cap)
	box.add_child(val)
	parent.add_child(box)
	return val


func _menu_button(parent: Container, key: String, handler: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(MENU_W, MSTheme.button_h())
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func() -> void: UiSounds.click())
	b.pressed.connect(handler)
	parent.add_child(b)
	_text_nodes.append([b, key])
	return b


## The column slides in from the left, button by button (skipped when the tree is not running a real frame loop).
func _play_intro() -> void:
	var items: Array[Control] = [_race_btn, _garage_btn, _settings_btn, _quit_btn]
	for i: int in items.size():
		var b: Control = items[i]
		b.modulate.a = 0.0
		var tw: Tween = create_tween()
		tw.tween_interval(INTRO_STAGGER_S * float(i))
		tw.tween_property(b, "modulate:a", 1.0, INTRO_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Replaces the live backdrop with a 3D scene rendered through a SubViewport behind the UI.
func set_backdrop(node: Node) -> void:
	for c: Node in _holder.get_children():
		c.queue_free()
	if node == null:
		_backdrop.visible = true
		return
	_backdrop.visible = false
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.handle_input_locally = false
	container.add_child(vp)
	_holder.add_child(container)
	vp.add_child(node)


func _refresh_text() -> void:
	for pair: Array in _text_nodes:
		var n: Object = pair[0]
		(n as Button).text = I18n.t(pair[1])
	_tagline.text = I18n.t("menu.tagline")
	_version.text = I18n.t("menu.version") % str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	for cap: Label in _stat_caps:
		cap.text = I18n.t(str(cap.get_meta("key")))
	_refresh_stats()


func _refresh_stats() -> void:
	_stat_stars.text = "%d / %d" % [GameState.total_stars(), EventCatalog.count() * GameState.MAX_STARS]
	_stat_cash.text = I18n.t("garage.money") % GameState.get_cash()
	_stat_rep.text = RaceHUD.group_int(GameState.get_rep())


func _on_settings_changed(section: String) -> void:
	if section == Settings.SECTION_GENERAL:
		_refresh_text()


func _on_race() -> void:
	_open(EVENT_SELECT_SCENE)


func _on_garage() -> void:
	_open(GARAGE_SCENE)


func _on_settings() -> void:
	_open(SETTINGS_SCENE)


func _on_quit() -> void:
	get_tree().quit()


## Opens a scene through Router when it exists. Missing scenes show a short toast instead.
func _open(path: String) -> void:
	if ResourceLoader.exists(path):
		Router.goto(path)
	else:
		_show_toast(I18n.t("menu.coming_soon"))


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_interval(TOAST_HOLD_S)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, TOAST_FADE_S)
	_toast_tw.tween_callback(func() -> void: _toast.visible = false)
