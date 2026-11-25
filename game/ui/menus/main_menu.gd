class_name MainMenu
extends Control
## Title screen: logotype, RACE / GARAGE / SETTINGS / QUIT, animated neon backdrop and an optional 3D backdrop.
## Keyboard, gamepad and touch all reach the buttons through Godot's focus navigation.

const EVENT_SELECT_SCENE: String = "res://ui/menus/event_select.tscn"
const GARAGE_SCENE: String = "res://ui/garage/garage.tscn"
const SETTINGS_SCENE: String = "res://ui/menus/settings_menu.tscn"
const NEON_SHADER: String = "res://ui/menus/neon_bg.gdshader"
const LOGO_PX: int = 96
const LOGO_SUB_PX: int = 40
const TAGLINE_PX: int = 18
const VERSION_PX: int = 16
const TOAST_PX: int = 22
const LOGO_BAR_W: float = 360.0
const LOGO_BAR_H: float = 6.0
const LOGO_GAP_PX: float = 56.0
const MENU_GAP_PX: float = 16.0
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 64.0
const TOAST_HOLD_S: float = 1.4
const TOAST_FADE_S: float = 0.4

var _holder: Control
var _race_btn: Button
var _garage_btn: Button
var _settings_btn: Button
var _quit_btn: Button
var _tagline: Label
var _version: Label
var _toast: Label
var _toast_tw: Tween = null
var _text_nodes: Array = []  ## [node, i18n key] pairs refreshed on language change


class SlashBar extends Control:
	func _draw() -> void:
		var h: float = size.y
		var sk: float = h * MSTheme.SKEW_RATIO
		draw_colored_polygon(PackedVector2Array([
			Vector2(sk, 0.0), Vector2(size.x, 0.0), Vector2(size.x - sk, h), Vector2(0.0, h)]), MSTheme.MAGENTA)


func _ready() -> void:
	MusicPlayer.get_instance().play_menu()
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = MSTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_holder = Control.new()
	_holder.name = "Backdrop"
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	add_child(_make_neon())
	_build_foreground()
	Settings.changed.connect(_on_settings_changed)
	_refresh_text()
	_race_btn.grab_focus()


func _make_neon() -> ColorRect:
	var neon := ColorRect.new()
	neon.name = "NeonLines"
	neon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	neon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(NEON_SHADER) as Shader
	neon.material = mat
	return neon


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

	var logo := MSTheme.make_label("MIDNIGHT", "slant", LOGO_PX, MSTheme.TEXT, false)
	logo.name = "LogoTop"
	col.add_child(logo)
	var sub := MSTheme.make_label("SYNDICATE", "tracked", LOGO_SUB_PX, MSTheme.CYAN, false)
	sub.name = "LogoBottom"
	col.add_child(sub)
	var bar := SlashBar.new()
	bar.custom_minimum_size = Vector2(LOGO_BAR_W, LOGO_BAR_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bar)
	_tagline = MSTheme.make_label("", "tracked", TAGLINE_PX, MSTheme.MUTED, false)
	col.add_child(_tagline)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, LOGO_GAP_PX)
	col.add_child(gap)

	var menu := VBoxContainer.new()
	menu.name = "Menu"
	menu.add_theme_constant_override("separation", int(MENU_GAP_PX))
	col.add_child(menu)
	_race_btn = _menu_button(menu, "menu.race", _on_race)
	_garage_btn = _menu_button(menu, "menu.garage", _on_garage)
	_settings_btn = _menu_button(menu, "menu.settings", _on_settings)
	_quit_btn = _menu_button(menu, "menu.quit", _on_quit)
	_quit_btn.visible = not (OS.has_feature("ios") or OS.has_feature("android"))

	_version = MSTheme.make_label("", "tracked", VERSION_PX, MSTheme.MUTED, false)
	_version.name = "Version"
	_version.anchor_left = 1.0
	_version.anchor_right = 1.0
	_version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_version.offset_top = ins.y + EDGE_Y_PX * 0.5
	_version.offset_right = -(ins.z + EDGE_PX * 0.5)
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


func _menu_button(parent: Container, key: String, handler: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(MSTheme.BUTTON_MIN_W, MSTheme.BUTTON_MIN_H)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func() -> void: UiSounds.click())
	b.pressed.connect(handler)
	parent.add_child(b)
	_text_nodes.append([b, key])
	return b


## Replaces the backdrop with a 3D scene rendered through a SubViewport behind the UI.
func set_backdrop(node: Node) -> void:
	for c: Node in _holder.get_children():
		c.queue_free()
	if node == null:
		return
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
