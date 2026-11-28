class_name OnboardingHints
extends CanvasLayer
## Three one-time hints in the first career race (Ortakoy Night) for a player who just finished onboarding.
## Steer, nitro, drift: each shows for HINT_S seconds or until OK, then the next one. SKIP or the end of the set
## (or the results screen) marks GameState hints_done, so they never come back. attach() does nothing for any other
## race, before onboarding, or once the hints are done. Pauses with the race because it runs in the race tree.

const EVENT_ID: String = "ortakoy_night"
const FIRST_DELAY_S: float = 4.0  ## the grid intro and countdown run first
const HINT_S: float = 7.0
const GAP_S: float = 1.5
const LAYER: int = 15
const TITLE_PX: int = 26
const BTN_PX: int = 18
const PANEL_TOP_PX: float = 96.0
const PANEL_W: float = 640.0
const HINT_KEYS: PackedStringArray = ["hint.steer", "hint.nitro", "hint.drift"]
const HINT_TOUCH_KEYS: PackedStringArray = ["hint.steer_touch", "hint.nitro_touch", "hint.drift_touch"]

var _store: Node = null
var _index: int = 0
var _wait_s: float = FIRST_DELAY_S
var _hold_s: float = 0.0
var _showing: bool = false
var _done: bool = false
var _panel: PanelContainer
var _text: Label
var _ok: Button
var _skip: Button


## Adds the hints to parent when they apply. store defaults to the GameState autoload. Returns null when they do not.
static func attach(parent: Node, config: RaceConfig, results: Control = null, store: Node = null) -> OnboardingHints:
	var gs: Node = store if store != null else GameState
	if config == null or config.event_id != EVENT_ID or not gs.is_onboarded() or gs.hints_done():
		return null
	var h := OnboardingHints.new()
	h._store = gs
	parent.add_child(h)
	if results != null:
		results.visibility_changed.connect(h._on_results_visibility.bind(results))
	return h


func _ready() -> void:
	layer = LAYER
	_panel = PanelContainer.new()
	_panel.name = "HintPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_top = PANEL_TOP_PX
	_panel.custom_minimum_size = Vector2(PANEL_W * MSTheme.k(), 0.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.visible = false
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 2))
	_panel.add_child(col)
	_text = MSTheme.make_label("", "bold", MSTheme.px(TITLE_PX), MSTheme.TEXT, true)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 2))
	col.add_child(row)
	_skip = _button(row, "hint.skip", _finish, false)
	_ok = _button(row, "hint.ok", _advance, true)


func _button(parent: Container, key: String, handler: Callable, primary: bool) -> Button:
	var b := Button.new()
	b.text = I18n.t(key)
	b.add_theme_font_size_override("font_size", MSTheme.px(BTN_PX))
	b.custom_minimum_size = Vector2(MSTheme.BUTTON_MIN_W * 0.5, MSTheme.button_h() * 0.8)
	if primary:
		b.theme_type_variation = &"PrimaryButton"
	b.pressed.connect(func() -> void: UiSounds.click())
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _process(delta: float) -> void:
	if _done:
		return
	if _showing:
		_hold_s -= delta
		if _hold_s <= 0.0:
			_advance()
		return
	_wait_s -= delta
	if _wait_s <= 0.0:
		_show()


## Index of the hint that shows next (0 to 3; 3 when the set is over).
func current_step() -> int:
	return _index


func is_showing() -> bool:
	return _showing


func is_done() -> bool:
	return _done


func _show() -> void:
	if _index >= HINT_KEYS.size():
		_finish()
		return
	var touch: bool = MSTheme.phone or DisplayServer.is_touchscreen_available()
	_text.text = I18n.t(HINT_TOUCH_KEYS[_index] if touch else HINT_KEYS[_index])
	_showing = true
	_hold_s = HINT_S
	_panel.visible = true


## Hides the current hint and moves on. After the last one the set is finished.
func _advance() -> void:
	if not _showing:
		return
	_showing = false
	_panel.visible = false
	_index += 1
	_wait_s = GAP_S
	if _index >= HINT_KEYS.size():
		_finish()


## Ends the set for good: saved as done, nothing shows again.
func _finish() -> void:
	if _done:
		return
	_done = true
	_showing = false
	_panel.visible = false
	_store.mark_hints_done()
	queue_free()


func _on_results_visibility(results: Control) -> void:
	if results.visible:
		_finish()
