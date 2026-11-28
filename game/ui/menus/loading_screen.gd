class_name LoadingScreen
extends Control
## Full-screen loading card shown between a menu and a race. The race scene loads on a worker thread
## (ResourceLoader.load_threaded_request) while the card shows track, event, a tip and the real load progress,
## then hands over to Router. Params: TARGET_KEY (scene path) and NEXT_KEY (params for that scene).

const SCENE: String = "res://ui/menus/loading_screen.tscn"
const TARGET_KEY: String = "target"
const NEXT_KEY: String = "next"
const TIP_KEY: String = "tip"  ## optional fixed tip index (captures); absent = random
const TIP_COUNT: int = 6
const MIN_SHOW_S: float = 0.8  ## a card that flashes by for 50 ms reads as a glitch
const TITLE_PX: int = 84
const EVENT_PX: int = 36
const TIP_PX: int = 26
const LABEL_PX: int = 20
const BAR_H_PX: float = 14.0
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 72.0
const TIP_BAR_GAP_PX: float = 22.0  ## air between the tip line and the progress bar

var _target: String = ""
var _next: Dictionary = {}
var _tip: int = 0
var _progress: float = 0.0
var _elapsed: float = 0.0
var _done: bool = false
var _packed: PackedScene = null  ## the loaded target, held until Router's change_scene_to_file finds it in the cache
var _bar: LoadingBar
var _pct: Label
var _track: Label
var _event: Label
var _tip_label: Label
var nav: Callable = Router.goto  ## the hand-over; tests swap in a recorder


## Set before the node enters the tree (tests, captures). Without this, _ready reads the params from Router.
func configure(target: String, next: Dictionary, tip: int = -1) -> void:
	_target = target
	_next = next
	_tip = tip


## Params for Router.goto(LoadingScreen.SCENE, ...): the race (or any scene) to load behind the card.
static func params_for(target: String, next: Dictionary, tip: int = -1) -> Dictionary:
	return {TARGET_KEY: target, NEXT_KEY: next, TIP_KEY: tip}


## Tip keys for TR/EN, in order. tests check that every one exists in both languages.
static func tip_keys() -> Array[String]:
	var keys: Array[String] = []
	for i: int in range(1, TIP_COUNT + 1):
		keys.append("menu.tip_%d" % i)
	return keys


func _ready() -> void:
	if _target.is_empty() and _next.is_empty():
		var p: Dictionary = Router.take_params()
		_target = str(p.get(TARGET_KEY, ""))
		_next = p.get(NEXT_KEY, {}) as Dictionary
		_tip = int(p.get(TIP_KEY, -1))
	if _tip < 0:
		_tip = randi() % TIP_COUNT
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(MenuBackdrop.new(0.25))
	_build()
	if _target.is_empty():
		return
	var err: Error = ResourceLoader.load_threaded_request(_target)
	if err != OK:
		push_warning("LoadingScreen: no background load for %s, Router loads it directly" % _target)  # status reads INVALID: _process hands over


func _build() -> void:
	var ins: Vector4 = MSTheme.safe_insets()
	var col := VBoxContainer.new()
	col.name = "Card"
	col.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_left = ins.x + EDGE_PX
	col.offset_right = -(ins.z + EDGE_PX)
	col.offset_top = -(ins.w + EDGE_Y_PX + 320.0)
	col.offset_bottom = -(ins.w + EDGE_Y_PX)
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	col.add_child(MSTheme.make_label(I18n.t("menu.loading"), "tracked", MSTheme.px(LABEL_PX), MSTheme.CYAN, false))
	var cfg: RaceConfig = _next.get(RaceScene.CONFIG_PARAM, null) as RaceConfig
	var ev: Dictionary = EventCatalog.find(cfg.event_id) if cfg != null else {}
	_track = MSTheme.make_label(_place_name(ev), "slant", MSTheme.px(TITLE_PX), MSTheme.TEXT, false)
	_track.name = "Track"
	col.add_child(_track)
	_event = MSTheme.make_label(_event_name(cfg, ev), "tracked", MSTheme.px(EVENT_PX), MSTheme.TITANIUM, false)
	_event.name = "Event"
	col.add_child(_event)
	_tip_label = MSTheme.make_label(I18n.t(tip_keys()[_tip]), "tracked", MSTheme.px(TIP_PX), MSTheme.MUTED, false)
	_tip_label.name = "Tip"
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_tip_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, TIP_BAR_GAP_PX)
	col.add_child(gap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	col.add_child(row)
	_bar = LoadingBar.new()
	_bar.name = "Bar"
	_bar.custom_minimum_size = Vector2(0.0, BAR_H_PX)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_bar)
	_pct = MSTheme.make_label("0%", "digits", MSTheme.px(LABEL_PX), MSTheme.CYAN, false)
	_pct.name = "Percent"
	row.add_child(_pct)


## Track name of the event's place ("MASLAK" / "BOĞAZ"); empty for a race without an event.
func _place_name(ev: Dictionary) -> String:
	var place: String = str(ev.get("place", ""))
	return I18n.t("place." + place) if I18n.has_key("place." + place) else ""


func _event_name(cfg: RaceConfig, ev: Dictionary) -> String:
	if cfg == null or ev.is_empty():
		return ""
	var key: String = EventCatalog.name_key(cfg.event_id)
	return I18n.t(key) if I18n.has_key(key) else cfg.event_id


## Progress shown on the bar, 0 to 1. Also driven directly by captures.
func set_progress(v: float) -> void:
	_progress = clampf(v, 0.0, 1.0)
	if _bar != null:
		_bar.value = _progress
		_bar.queue_redraw()
		_pct.text = "%d%%" % roundi(_progress * 100.0)


func _process(delta: float) -> void:
	if _done or _target.is_empty():
		return
	_elapsed += delta
	var prog: Array = []
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(_target, prog)
	set_progress(float(prog[0]) if not prog.is_empty() else _progress)
	var loaded: bool = status == ResourceLoader.THREAD_LOAD_LOADED and _elapsed >= MIN_SHOW_S
	var failed: bool = status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	# Router ignores goto() while it is still fading this card in (a long first frame can outrun the fade).
	if (loaded or failed) and not Router._busy:
		_finish()


## Hands over to the target scene. A failed background load falls through to Router, which reports it.
func _finish() -> void:
	if _done:
		return
	_done = true
	set_progress(1.0)
	if ResourceLoader.load_threaded_get_status(_target) == ResourceLoader.THREAD_LOAD_LOADED:
		_packed = ResourceLoader.load_threaded_get(_target) as PackedScene  # releases the loader task; without it the scene stays pinned
	nav.call(_target, _next)


## Thin progress bar: a dim track and a magenta fill, drawn in one pass.
class LoadingBar extends Control:
	var value: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), MSTheme.tint(MSTheme.CYAN, 0.18))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * value, size.y)), MSTheme.MAGENTA)
