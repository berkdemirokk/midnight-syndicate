class_name EventSelect
extends Control
## Career event list: lock state, stars, best time and rewards per event, a detail panel for the selected one,
## START and BACK. START hands the event's RaceConfig to race_scene through Router params["config"].
## Draw cost: like ResultsScreen, containers only place empty slots and invisible-label buttons; one canvas item
## (the Board) paints every panel, star and text in passes, so the screen is the backdrop plus a handful of draws.
## Keyboard and controller: up/down moves through the rows (the focused row is the selected one), accept on a row
## jumps to START. Touch: tap a row to select, tap START.

const RACE_SCENE: String = "res://race/race_scene.tscn"
const MENU_SCENE: String = "res://ui/menus/main_menu.tscn"
const NEON_SHADER: String = "res://ui/menus/neon_bg.gdshader"
const TITLE_PX: int = 40
const SUB_PX: int = 18
const ROW_PX: int = 26
const ROW_INFO_PX: int = 18
const DETAIL_TITLE_PX: int = 32
const VAL_PX: int = 26
const ROW_W: float = 760.0
const ROW_H: float = 72.0
const ROW_GAP_PX: float = 8.0
const DETAIL_MIN_W: float = 520.0
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 56.0
const NUM_W: float = 64.0
const STAR_R: float = 11.0
const STAR_STEP: float = 30.0
const DETAIL_STAR_R: float = 18.0
const FOCUS_PX: float = 2.0
const RULE_LINES: int = 3
const STAR_OFF: Color = Color(0.541, 0.580, 0.651, 0.3)

## The single canvas item the screen paints into.
class Board:
	extends Control
	var painter: Callable

	func _draw() -> void:
		painter.call(self)


var _board: Board
var _title_slot: Control
var _sub_slot: Control
var _detail_slot: Control
var _title: HudText
var _subtitle: HudText
var _row_btns: Array[Button] = []
var _row_num: Array[HudText] = []
var _row_name: Array[HudText] = []
var _row_info: Array[HudText] = []
var _row_lock: Array[HudText] = []
var _d_title: HudText
var _d_state: HudText
var _d_caps: Array[HudText] = []  ## rival level, laps, rivals, winner pays, best time
var _d_vals: Array[HudText] = []  ## the matching values; the winner-pays value is cash, _d_rep follows it
var _d_rep: HudText
var _d_rules: Array[HudText] = []
var _all_texts: Array[HudText] = []
var _start_btn: Button
var _back_btn: Button
var _buttons: Array[Button] = []
var _text_nodes: Array = []  ## [button, i18n key]
var _sel: int = 0


func _ready() -> void:
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = MSTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var neon := ColorRect.new()
	neon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	neon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(NEON_SHADER) as Shader
	neon.material = mat
	add_child(neon)
	_board = Board.new()
	_board.painter = _paint_board
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)

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

	_title = _text("bold", TITLE_PX, MSTheme.TEXT)
	_subtitle = _text("tracked", SUB_PX, MSTheme.CYAN)
	_title_slot = _slot(col, Vector2(0.0, _title.height()))
	_sub_slot = _slot(col, Vector2(0.0, _subtitle.height()))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 4))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", int(ROW_GAP_PX))
	body.add_child(list)
	for i: int in EventCatalog.count():
		_row_btns.append(_row_button(list, i))
		_row_num.append(_text("digits", ROW_PX, MSTheme.CYAN))
		_row_name.append(_text("bold", ROW_PX, MSTheme.TEXT))
		_row_info.append(_text("tracked", ROW_INFO_PX, MSTheme.MUTED))
		_row_lock.append(_text("tracked", ROW_INFO_PX, MSTheme.DANGER))
	_detail_slot = _slot(body, Vector2(DETAIL_MIN_W, 0.0))
	_detail_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_d_title = _text("bold", DETAIL_TITLE_PX, MSTheme.TEXT)
	_d_state = _text("tracked", SUB_PX, MSTheme.DANGER)
	for i: int in 5:
		_d_caps.append(_text("tracked", SUB_PX, MSTheme.MUTED))
		_d_vals.append(_text("digits", VAL_PX, MSTheme.TEXT))
	_d_vals[3].color = MSTheme.AMBER
	_d_rep = _text("digits", VAL_PX, MSTheme.CYAN)
	for i: int in RULE_LINES:
		_d_rules.append(_text("bold", SUB_PX, MSTheme.MUTED))

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 2))
	col.add_child(footer)
	_back_btn = _button(footer, "common.back", _on_back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(spacer)
	_start_btn = _button(footer, "event.start", start_race)

	_wire_neighbours()
	_sel = _default_selection()
	Settings.changed.connect(_on_settings_changed)
	_refresh_text()
	_sort_texts()
	_row_btns[_sel].grab_focus()


# --- public --------------------------------------------------------------------------------------------

func get_selected_id() -> String:
	return EventCatalog.id_at(_sel)


func get_row_count() -> int:
	return _row_btns.size()


func is_start_enabled() -> bool:
	return not _start_btn.disabled


func select(index: int) -> void:
	if index < 0 or index >= _row_btns.size() or index == _sel:
		return
	_sel = index
	_refresh_text()


## Router params for the selected event: {"config": RaceConfig}. Empty when the event is locked.
func build_start_params() -> Dictionary:
	var id: String = get_selected_id()
	if not GameState.is_event_unlocked(id):
		return {}
	return {RaceScene.CONFIG_PARAM: EventCatalog.config_for(id)}


func start_race() -> void:
	var params: Dictionary = build_start_params()
	if params.is_empty():
		return
	UiSounds.click()
	Router.goto(RACE_SCENE, params)


# --- build ---------------------------------------------------------------------------------------------

func _text(kind: String, px: int, col: Color) -> HudText:
	var t := HudText.new(kind, px, col, false)
	_all_texts.append(t)
	return t


func _sort_texts() -> void:
	_all_texts.sort_custom(func(a: HudText, b: HudText) -> bool: return a.size_px < b.size_px)


func _slot(parent: Container, min_size: Vector2) -> Control:
	var s := Control.new()
	s.custom_minimum_size = min_size
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.resized.connect(_board.queue_redraw)
	parent.add_child(s)
	return s


## A button that only takes the layout space and the input; the board paints its look.
func _plain_button(parent: Container, min_size: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	var none := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, none)
	for sig: Signal in [b.mouse_entered, b.mouse_exited, b.focus_entered, b.focus_exited, b.button_down, b.button_up, b.visibility_changed]:
		sig.connect(_board.queue_redraw)
	parent.add_child(b)
	_buttons.append(b)
	return b


func _button(parent: Container, key: String, handler: Callable) -> Button:
	var b: Button = _plain_button(parent, Vector2(MSTheme.BUTTON_MIN_W * 0.5, MSTheme.BUTTON_MIN_H))
	b.pressed.connect(func() -> void: UiSounds.click())
	b.pressed.connect(handler)
	_text_nodes.append([b, key])
	return b


func _row_button(parent: Container, index: int) -> Button:
	var b: Button = _plain_button(parent, Vector2(ROW_W, ROW_H))
	b.focus_entered.connect(select.bind(index))
	b.pressed.connect(_on_row_pressed.bind(index))
	return b


## Rows stay in one column; the footer buttons are reached from the first/last row.
func _wire_neighbours() -> void:
	var last: Button = _row_btns[_row_btns.size() - 1]
	last.focus_neighbor_bottom = last.get_path_to(_start_btn)
	_start_btn.focus_neighbor_top = _start_btn.get_path_to(last)
	_back_btn.focus_neighbor_top = _back_btn.get_path_to(last)
	_row_btns[0].focus_neighbor_top = _row_btns[0].get_path_to(_row_btns[0])
	_start_btn.focus_neighbor_left = _start_btn.get_path_to(_back_btn)
	_back_btn.focus_neighbor_right = _back_btn.get_path_to(_start_btn)


## First unlocked event without a star, else the last one (the whole ladder is done).
func _default_selection() -> int:
	for i: int in EventCatalog.count():
		var id: String = EventCatalog.id_at(i)
		if GameState.is_event_unlocked(id) and GameState.event_stars(id) == 0:
			return i
	return EventCatalog.count() - 1


# --- text ----------------------------------------------------------------------------------------------

func _refresh_text() -> void:
	for pair: Array in _text_nodes:
		(pair[0] as Button).text = I18n.t(pair[1])
	_title.set_text(I18n.t("event.title"))
	_subtitle.set_text(I18n.t("event.subtitle") % [GameState.total_stars(), EventCatalog.count() * GameState.MAX_STARS])
	for i: int in EventCatalog.count():
		var id: String = EventCatalog.id_at(i)
		var ev: Dictionary = EventCatalog.find(id)
		var open: bool = GameState.is_event_unlocked(id)
		_row_num[i].set_text("%02d" % (i + 1))
		_row_num[i].color = MSTheme.CYAN if open else MSTheme.MUTED
		_row_name[i].set_text(I18n.t(EventCatalog.name_key(id)))
		_row_name[i].color = MSTheme.TEXT if open else MSTheme.MUTED
		_row_info[i].set_text(_info_line(ev))
		_row_lock[i].set_text(I18n.t("event.locked"))
		_row_lock[i].visible = not open
	_refresh_detail()
	_start_btn.disabled = not GameState.is_event_unlocked(get_selected_id())
	_board.queue_redraw()


func _info_line(ev: Dictionary) -> String:
	var laps: int = int(ev["laps"])
	return "%d %s  ·  %d %s" % [laps, I18n.t("event.lap" if laps == 1 else "event.laps"), (ev["skills"] as Array).size(), I18n.t("event.rival" if (ev["skills"] as Array).size() == 1 else "event.rivals")]


func _refresh_detail() -> void:
	var id: String = get_selected_id()
	var ev: Dictionary = EventCatalog.find(id)
	var open: bool = GameState.is_event_unlocked(id)
	_d_title.set_text(I18n.t(EventCatalog.name_key(id)))
	_d_state.set_text("" if open else I18n.t("event.locked_hint"))
	var caps: Array[String] = ["event.ai", "event.laps", "event.rivals", "event.win_reward", "event.best"]
	for i: int in caps.size():
		_d_caps[i].set_text(I18n.t(caps[i]))
	var reward: Dictionary = EventCatalog.win_rewards(id)
	var best: float = GameState.best_time(id)
	_d_vals[0].set_text(I18n.t("event.level_%d" % int(ev["level"])))
	_d_vals[1].set_text(str(ev["laps"]))
	_d_vals[2].set_text(str((ev["skills"] as Array).size()))
	_d_vals[3].set_text(I18n.t("garage.money") % int(reward["cash"]))
	_d_rep.set_text("%s %s" % [RaceHUD.group_int(int(reward["rep"])), I18n.t("results.reward_rep")])
	_d_vals[4].set_text(RaceHUD.fmt_time(best) if best > 0.0 else I18n.t("hud.no_time"))
	var rules: Array[String] = []
	if EventCatalog.is_time_event(id):
		var limits: Array = ev["star_times"]
		for i: int in limits.size():
			var n: int = 3 - i
			rules.append(I18n.t("event.rule_time") % [RaceHUD.fmt_time(float(limits[i])), n, I18n.t("event.star" if n == 1 else "event.stars")])
	else:
		rules = [I18n.t("event.rule_win"), I18n.t("event.rule_podium"), I18n.t("event.rule_finish")]
	for i: int in RULE_LINES:
		_d_rules[i].set_text(rules[i])


func _on_settings_changed(section: String) -> void:
	if section == Settings.SECTION_GENERAL:
		_refresh_text()


func _on_row_pressed(index: int) -> void:
	select(index)
	UiSounds.click()
	if not _start_btn.disabled:
		_start_btn.grab_focus()


func _on_back() -> void:
	Router.goto(MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()


# --- painting ------------------------------------------------------------------------------------------

func _local_rect(n: Control) -> Rect2:
	var g: Rect2 = n.get_global_rect()
	return Rect2(g.position - _board.get_global_rect().position, g.size)


## Five-point star polygon centred at c.
static func star_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in 10:
		var a: float = -PI * 0.5 + float(i) * PI / 5.0
		var rr: float = r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts


## Three stars (earned ones lit) with the right edge of the last star at right_x. Call in the rect pass.
static func draw_stars(c: CanvasItem, right_x: float, cy: float, r: float, earned: int, step: float) -> void:
	for i: int in GameState.MAX_STARS:
		var cx: float = right_x - r - float(GameState.MAX_STARS - 1 - i) * step
		c.draw_colored_polygon(star_points(Vector2(cx, cy), r), MSTheme.AMBER if i < earned else STAR_OFF)


func _paint_board(c: Control) -> void:
	var sep: float = float(MSTheme.GRID_PX)
	_title.pos = _local_rect(_title_slot).position
	_subtitle.pos = _local_rect(_sub_slot).position
	var detail: Rect2 = _local_rect(_detail_slot)

	# Rows.
	var star_rights: Array[float] = []
	for i: int in _row_btns.size():
		var r: Rect2 = _local_rect(_row_btns[i])
		var right: float = r.end.x - MSTheme.BUTTON_PAD_X
		star_rights.append(right)
		var x: float = r.position.x + MSTheme.BUTTON_PAD_X
		_row_num[i].pos = Vector2(x, r.position.y + (r.size.y - _row_num[i].height()) * 0.5)
		var nx: float = x + NUM_W
		var block: float = _row_name[i].height() + _row_info[i].height()
		var top: float = r.position.y + (r.size.y - block) * 0.5
		_row_name[i].pos = Vector2(nx, top)
		_row_info[i].pos = Vector2(nx, top + _row_name[i].height())
		_row_lock[i].pos = Vector2(right - _row_lock[i].width(), r.position.y + (r.size.y - _row_lock[i].height()) * 0.5)

	# Detail panel text.
	var rx: float = detail.position.x + MSTheme.BUTTON_PAD_X * 1.5
	var y: float = detail.position.y + MSTheme.BUTTON_PAD_Y * 1.5
	_d_title.pos = Vector2(rx, y)
	y += _d_title.height() + sep
	var star_y: float = y + DETAIL_STAR_R
	y += DETAIL_STAR_R * 2.0 + sep * 1.5
	_d_state.pos = Vector2(rx, y)
	if _d_state.text != "":
		y += _d_state.height() + sep
	for i: int in _d_caps.size():
		_d_caps[i].pos = Vector2(rx, y)
		y += _d_caps[i].height()
		_d_vals[i].pos = Vector2(rx, y)
		if i == 3:
			_d_rep.pos = Vector2(rx + _d_vals[i].width() + MSTheme.BUTTON_PAD_X, y)
		y += _d_vals[i].height() + sep
	y += sep
	for t: HudText in _d_rules:
		t.pos = Vector2(rx, y)
		y += t.height() + sep * 0.5

	# Pass 1: rects and stars.
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(MSTheme.BG.r, MSTheme.BG.g, MSTheme.BG.b, 0.55))
	ResultsScreen._fill_skewed(c, detail, MSTheme.PANEL_BG)
	for i: int in _row_btns.size():
		var r2: Rect2 = _local_rect(_row_btns[i])
		var open: bool = GameState.is_event_unlocked(EventCatalog.id_at(i))
		var fill: Color = MSTheme.PANEL_BG if open else MSTheme.DISABLED_BG
		if i == _sel:
			fill = MSTheme.tint(MSTheme.CYAN, 0.18 if open else 0.08)
		ResultsScreen._fill_skewed(c, r2, fill)
		if open:
			draw_stars(c, star_rights[i], r2.position.y + r2.size.y * 0.5, STAR_R, GameState.event_stars(EventCatalog.id_at(i)), STAR_STEP)
	if GameState.is_event_unlocked(get_selected_id()):
		draw_stars(c, rx + DETAIL_STAR_R * 2.0 + DETAIL_STAR_R * 2.4 * 2.0, star_y, DETAIL_STAR_R, GameState.event_stars(get_selected_id()), DETAIL_STAR_R * 2.4)
	for b: Button in _buttons:
		if _is_footer(b):
			ResultsScreen._fill_skewed(c, _local_rect(b), _button_fill(b))
	# Pass 2: lines.
	ResultsScreen._outline_skewed(c, detail, MSTheme.BORDER, 1.0)
	for i: int in _row_btns.size():
		var r3: Rect2 = _local_rect(_row_btns[i])
		ResultsScreen._outline_skewed(c, r3, MSTheme.CYAN if i == _sel else MSTheme.BORDER, 1.0)
		if _row_btns[i].has_focus():
			ResultsScreen._outline_skewed(c, r3, MSTheme.MAGENTA, FOCUS_PX)
	for b: Button in _buttons:
		if _is_footer(b):
			ResultsScreen._outline_skewed(c, _local_rect(b), _button_edge(b), 1.0)
			if b.has_focus():
				ResultsScreen._outline_skewed(c, _local_rect(b), MSTheme.MAGENTA, FOCUS_PX)
	# Pass 3: text, one draw per pixel size.
	HudText.paint(c, _all_texts)


func _is_footer(b: Button) -> bool:
	return b == _start_btn or b == _back_btn



func _button_fill(b: Button) -> Color:
	match b.get_draw_mode():
		BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED:
			return MSTheme.tint(MSTheme.CYAN, 0.32)
		BaseButton.DRAW_HOVER:
			return MSTheme.tint(MSTheme.CYAN, 0.16)
		BaseButton.DRAW_DISABLED:
			return MSTheme.DISABLED_BG
	return MSTheme.PANEL_BG


func _button_edge(b: Button) -> Color:
	match b.get_draw_mode():
		BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED, BaseButton.DRAW_HOVER:
			return MSTheme.CYAN
		BaseButton.DRAW_DISABLED:
			return MSTheme.tint(MSTheme.MUTED, 0.3)
	return MSTheme.BORDER
