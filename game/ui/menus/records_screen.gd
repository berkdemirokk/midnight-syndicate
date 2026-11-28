class_name RecordsScreen
extends Control
## Personal records, one row per career event: best time (race) or best drift score, best position, stars and the car
## of that best result. Data: GameState.career_record. Local only, no online ranking. Back returns to the main menu.
## store: the GameState to read (null = the autoload). Tests and captures pass a temporary profile.

const MENU_SCENE: String = "res://ui/menus/main_menu.tscn"
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 56.0
const TITLE_PX: int = 40
const HEAD_PX: int = 16
const ROW_PX: int = 22
const ROW_W: float = 1040.0
const COL_EVENT_W: float = 380.0
const COL_BEST_W: float = 220.0
const COL_STARS_W: float = 120.0
const COL_CAR_W: float = 320.0
const ROW_GAP_PX: int = 6
const MAX_STARS: int = 3

var store: Node = null
var nav: Callable = Router.goto  ## scene change; tests swap in a recorder so the runner scene stays

var _col: VBoxContainer
var _list: VBoxContainer
var _back_btn: Button


func _ready() -> void:
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new(0.7))
	var ins: Vector4 = MSTheme.safe_insets()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(ins.x + EDGE_PX * 0.6))
	margin.add_theme_constant_override("margin_top", int(ins.y + EDGE_Y_PX))
	margin.add_theme_constant_override("margin_right", int(ins.z + EDGE_PX * 0.6))
	margin.add_theme_constant_override("margin_bottom", int(ins.w + EDGE_Y_PX))
	add_child(margin)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 2))
	margin.add_child(_col)
	_col.add_child(MSTheme.make_label(I18n.t("records.title"), "bold", MSTheme.px(TITLE_PX), MSTheme.TEXT))
	_col.add_child(_header())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", ROW_GAP_PX)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_back_btn = Button.new()
	_back_btn.custom_minimum_size = Vector2(MSTheme.BUTTON_MIN_W, MSTheme.button_h())
	_back_btn.pressed.connect(func() -> void: UiSounds.click())
	_back_btn.pressed.connect(_on_back)
	_col.add_child(_back_btn)
	populate()
	_back_btn.grab_focus()


## Fills the list from the store. Safe to call again.
func populate() -> void:
	_back_btn.text = I18n.t("common.back")
	for c: Node in _list.get_children():
		c.queue_free()
	var gs: Node = store if store != null else GameState
	var any: bool = false
	for i: int in EventCatalog.count():
		var id: String = EventCatalog.id_at(i)
		var rec: Dictionary = gs.career_record(id)
		if not rec.is_empty():
			any = true
		_list.add_child(_row(id, rec))
	if not any:
		var empty: Label = MSTheme.make_label(I18n.t("records.empty"), "body", MSTheme.px(ROW_PX), MSTheme.MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)


func row_count() -> int:
	return _list.get_child_count()


## Text of the best value column for a record (time, score or position), "Not yet" when nothing is recorded.
static func best_text(id: String, rec: Dictionary) -> String:
	if EventCatalog.is_score_event(id) and float(rec.get("best_score", 0.0)) > 0.0:
		return I18n.t("records.score") % int(rec["best_score"])
	if float(rec.get("best_time", 0.0)) > 0.0:
		return RaceHUD.fmt_time(float(rec["best_time"]))
	if int(rec.get("best_position", 0)) > 0:
		return I18n.t("records.pos") % int(rec["best_position"])
	return I18n.t("records.none")


static func car_name(car_id: String) -> String:
	if car_id.is_empty():
		return I18n.t("records.none")
	var path: String = CarCatalog.spec_path(car_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return car_id
	var spec: Resource = load(path)
	return str(spec.get("display_name")) if spec != null and spec.get("display_name") is String else car_id


func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 2))
	row.add_child(_cell(I18n.t("records.col_event"), COL_EVENT_W, HEAD_PX, MSTheme.MUTED, "tracked"))
	row.add_child(_cell(I18n.t("records.col_best"), COL_BEST_W, HEAD_PX, MSTheme.MUTED, "tracked"))
	row.add_child(_cell(I18n.t("records.col_stars"), COL_STARS_W, HEAD_PX, MSTheme.MUTED, "tracked"))
	row.add_child(_cell(I18n.t("records.col_car"), COL_CAR_W, HEAD_PX, MSTheme.MUTED, "tracked"))
	return row


func _row(id: String, rec: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MSTheme.card(MSTheme.PANEL_BG, MSTheme.BORDER))
	card.custom_minimum_size = Vector2(ROW_W * MSTheme.k(), 0.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 2))
	card.add_child(row)
	var has: bool = not rec.is_empty()
	row.add_child(_cell(I18n.t(EventCatalog.name_key(id)), COL_EVENT_W, ROW_PX, MSTheme.TEXT, "bold"))
	row.add_child(_cell(best_text(id, rec) if has else I18n.t("records.none"), COL_BEST_W, ROW_PX, MSTheme.CYAN if has else MSTheme.MUTED, "digits"))
	var stars: int = clampi(int(rec.get("stars", 0)), 0, MAX_STARS)
	row.add_child(_cell("%d / %d" % [stars, MAX_STARS], COL_STARS_W, ROW_PX, MSTheme.AMBER if stars > 0 else MSTheme.MUTED, "digits"))
	var car: String = str(rec.get("car", ""))
	row.add_child(_cell(car_name(car) if has else I18n.t("records.none"), COL_CAR_W, ROW_PX, MSTheme.TEXT if has else MSTheme.MUTED, "body"))
	return card


func _cell(text: String, w: float, px: int, col: Color, kind: String) -> Label:
	var l: Label = MSTheme.make_label(text, kind, MSTheme.px(px), col)
	l.custom_minimum_size = Vector2(w * MSTheme.k(), 0.0)
	l.clip_text = true
	return l


func _on_back() -> void:
	nav.call(MENU_SCENE, {})
