extends Node
## Scene changes with a short fade through black. The fade is skipped headless and during capture,
## so goto() never waits on a tween there.

signal scene_changed(path: String)

@export_range(0.0, 2.0, 0.01) var fade_seconds: float = 0.25

var current_path: String = ""
var _params: Dictionary = {}
var _busy: bool = false
var _fade_enabled: bool = true
var _rect: ColorRect = null
var _card: Control = null
const LOADING_CARD: String = "res://ui/menus/loading_card.gd"


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_rect = ColorRect.new()
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_rect)
	# STREET EMPIRE loading card inside the fade: shown while the next scene loads, faded with the rect.
	if ResourceLoader.exists(LOADING_CARD):
		_card = (load(LOADING_CARD) as Script).new() as Control
		_card.modulate.a = 0.0
		_card.visible = false
		_rect.add_child(_card)
	_fade_enabled = DisplayServer.get_name() != "headless" and fade_seconds > 0.0 and not _is_capture_run()
	get_tree().scene_changed.connect(_on_tree_scene_changed)


## Changes to scene_path. params are handed to the new scene through take_params().
## Returns once the new scene is the current scene (change_scene_to_file itself is deferred).
func goto(scene_path: String, params: Dictionary = {}) -> void:
	if _busy:
		push_warning("Router: busy, ignoring goto " + scene_path)
		return
	_busy = true
	_params = params.duplicate()
	if _fade_enabled:
		await _fade(1.0)
	if _change(scene_path):
		await get_tree().scene_changed
		if _fade_enabled:
			await _fade(0.0)
	_busy = false


## Returns the params given to the last goto() and clears them.
func take_params() -> Dictionary:
	var p: Dictionary = _params
	_params = {}
	return p


func reload() -> void:
	var path: String = current_path
	if path.is_empty() and get_tree().current_scene != null:
		path = get_tree().current_scene.scene_file_path
	if path.is_empty():
		push_warning("Router: nothing to reload")
		return
	goto(path, {})


## Returns false if the scene cannot be loaded. The switch itself happens at the end of the frame.
func _change(path: String) -> bool:
	var err: Error = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Router: cannot change scene to %s (error %d)" % [path, err])
		return false
	return true


func _on_tree_scene_changed() -> void:
	var cur: Node = get_tree().current_scene
	current_path = cur.scene_file_path if cur != null else ""
	scene_changed.emit(current_path)


func _fade(alpha: float) -> void:
	if fade_seconds <= 0.0:
		return
	var tw: Tween = create_tween()
	tw.tween_property(_rect, "color:a", alpha, fade_seconds)
	if _card != null:
		_card.visible = true
		tw.parallel().tween_property(_card, "modulate:a", alpha, fade_seconds)
	await tw.finished
	if _card != null and alpha <= 0.0:
		_card.visible = false


func _is_capture_run() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			return true
	return false
