class_name PauseMenu
extends Control
## Pause overlay. Runs with PROCESS_MODE_ALWAYS so it still answers while the tree is paused.
## The pause action toggles it. RESTART and QUIT TO MENU act by default (Router) unless a listener is connected.

signal resumed
signal restart_requested
signal quit_requested

const SETTINGS_SCENE: String = "res://ui/menus/settings_menu.tscn"
const MENU_SCENE: String = "res://ui/menus/main_menu.tscn"
const DIM_ALPHA: float = 0.62
const TITLE_PX: int = 40
const PANEL_W: float = 440.0
const BUTTON_W: float = 360.0
const BUTTON_H: float = 64.0
const GAP_PX: int = 16

var _open: bool = false
var _column: VBoxContainer
var _title: Label
var _resume_btn: Button
var _restart_btn: Button
var _settings_btn: Button
var _quit_btn: Button
var _settings: Node = null
var _text_nodes: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(MSTheme.BG.r, MSTheme.BG.g, MSTheme.BG.b, DIM_ALPHA)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
	centre.add_child(panel)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, int(MSTheme.GRID_PX * 3))
	panel.add_child(pad)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", GAP_PX)
	pad.add_child(_column)

	_title = MSTheme.make_label("", "bold", TITLE_PX, MSTheme.TEXT)
	_column.add_child(_title)
	_resume_btn = _button("pause.resume", _on_resume)
	_restart_btn = _button("pause.restart", _on_restart)
	_settings_btn = _button("pause.settings", _on_settings)
	_quit_btn = _button("pause.quit", _on_quit)

	visible = false
	Settings.changed.connect(_on_settings_changed)
	_refresh_text()


func _button(key: String, handler: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(BUTTON_W, BUTTON_H)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(handler)
	_column.add_child(b)
	_text_nodes.append([b, key])
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _settings == null:
		if _open:
			resume()
		else:
			pause()
		get_viewport().set_input_as_handled()


func is_paused_menu_open() -> bool:
	return _open


func pause() -> void:
	if _open:
		return
	_open = true
	visible = true
	get_tree().paused = true
	MusicPlayer.get_instance().duck(-8.0)
	_resume_btn.grab_focus()


func resume() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false
	MusicPlayer.get_instance().unduck()
	resumed.emit()


func _refresh_text() -> void:
	_title.text = I18n.t("pause.title")
	for pair: Array in _text_nodes:
		(pair[0] as Button).text = I18n.t(pair[1])


func _on_settings_changed(section: String) -> void:
	if section == Settings.SECTION_GENERAL:
		_refresh_text()


func _on_resume() -> void:
	resume()


func _on_restart() -> void:
	get_tree().paused = false
	_open = false
	visible = false
	if restart_requested.get_connections().is_empty():
		Router.reload()
	restart_requested.emit()


func _on_quit() -> void:
	get_tree().paused = false
	_open = false
	visible = false
	if quit_requested.get_connections().is_empty():
		Router.goto(MENU_SCENE)
	quit_requested.emit()


func _on_settings() -> void:
	if not ResourceLoader.exists(SETTINGS_SCENE):
		return
	var packed: PackedScene = load(SETTINGS_SCENE) as PackedScene
	var s: SettingsMenu = packed.instantiate() as SettingsMenu
	s.overlay = true
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	s.closed.connect(_on_settings_closed)
	_settings = s
	_column.visible = false
	add_child(s)


func _on_settings_closed() -> void:
	_settings = null
	_column.visible = true
	_resume_btn.grab_focus()
