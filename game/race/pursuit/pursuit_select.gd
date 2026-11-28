class_name PursuitSelect
extends Control
## Pursuit run select, opened from the main menu. Lists the open pursuit runs (EventCatalog rows with "pursuit" and
## "open"), one button each, and starts the picked run through Router with its RaceConfig. Tests swap nav for a recorder.

const MENU_SCENE: String = "res://ui/menus/main_menu.tscn"
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 56.0
const ROW_W: float = 640.0
const ROW_GAP_PX: float = 14.0
const TITLE_PX: int = 40
const SUB_PX: int = 18
const TOUCH_H: float = 88.0  ## touch target of each run row, the same size as the main menu buttons on a phone

var nav: Callable = Router.goto  ## scene change; tests swap in a recorder
var _list: VBoxContainer
var _back: Button


## Ids of the open pursuit runs, in catalog order. Pure data, so tests and the menu agree.
static func run_ids() -> Array[String]:
	var out: Array[String] = []
	for ev: Dictionary in EventCatalog.EVENTS:
		if bool(ev.get("pursuit", false)) and bool(ev.get("open", false)):
			out.append(str(ev["id"]))
	return out


func _ready() -> void:
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new(0.0, 0.7))
	var ins: Vector4 = MSTheme.safe_insets()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(ins.x + EDGE_PX))
	margin.add_theme_constant_override("margin_top", int(ins.y + EDGE_Y_PX))
	margin.add_theme_constant_override("margin_right", int(ins.z + EDGE_PX))
	margin.add_theme_constant_override("margin_bottom", int(ins.w + EDGE_Y_PX))
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 2))
	margin.add_child(col)
	col.add_child(MSTheme.make_label(I18n.t("pursuit.select.title"), "bold", MSTheme.px(TITLE_PX), MSTheme.TEXT))
	col.add_child(MSTheme.make_label(I18n.t("pursuit.select.sub"), "tracked", MSTheme.px(SUB_PX), MSTheme.CYAN))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", int(ROW_GAP_PX))
	_list.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(_list)
	for id: String in run_ids():
		var b := Button.new()
		b.name = "Run_" + id
		b.custom_minimum_size = Vector2(ROW_W, maxf(TOUCH_H, MSTheme.button_h()))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   x%.2f" % [I18n.t(EventCatalog.name_key(id)), EventCatalog.reward_multiplier(id)]
		b.disabled = not GameState.is_event_unlocked(id)
		b.set_meta("event_id", id)
		b.pressed.connect(func() -> void: UiSounds.click())
		b.pressed.connect(start_run.bind(id))
		_list.add_child(b)
	_back = Button.new()
	_back.name = "Back"
	_back.custom_minimum_size = Vector2(ROW_W, maxf(TOUCH_H, MSTheme.button_h()))
	_back.text = I18n.t("common.back")
	_back.pressed.connect(func() -> void: UiSounds.click())
	_back.pressed.connect(back)
	col.add_child(_back)
	if _list.get_child_count() > 0:
		(_list.get_child(0) as Button).grab_focus()
	else:
		_back.grab_focus()


## Starts one pursuit run through Router with its config (no config for a locked run).
func start_run(id: String) -> void:
	if not GameState.is_event_unlocked(id):
		return
	nav.call(EventSelect.RACE_SCENE, {RaceScene.CONFIG_PARAM: EventCatalog.config_for(id)})


func back() -> void:
	nav.call(MENU_SCENE, {})
