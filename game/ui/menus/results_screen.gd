class_name ResultsScreen
extends Control
## Race results: finishing order with times and gaps, best laps, the player row highlighted, and rewards
## that count up. Emits retry_pressed, garage_pressed or menu_pressed.
## Draw cost: containers only place empty slots and the four buttons. Every panel, row and text is painted by one
## canvas item (_paint_board) in passes (rects, lines, text by size), so the overlay batches to a handful of draws.
## The buttons draw only their label; their skewed backgrounds are painted under them by the same board.

signal retry_pressed
signal garage_pressed
signal menu_pressed
signal replay_pressed
signal next_pressed

const RACE_SCENE: String = "res://race/race_scene.tscn"
const STAR_R: float = 26.0
const STAR_STEP: float = 66.0
const COUNT_UP_S: float = 1.2
const HERO_PX: int = 88
const HERO_SUFFIX_PX: int = 32
const STAR_POP_S: float = 0.55
const STAR_DELAY_S: float = 0.45  ## first star pops this long after the count-up starts, then one per step
const STAR_STEP_S: float = 0.38
const BURST_GROW: float = 1.9
const ROW_MAX_H: float = 92.0
const PANEL_TEXT_MAX_K: float = 1.25  ## the reward panel is narrow, so its type grows less than the rest on a phone
const TITLE_PX: int = 40
const SUB_PX: int = 18
const ROW_PX: int = 26
const REWARD_PX: int = 48
const REWARD_LABEL_PX: int = 18
const COL_POS_W: float = 96.0
const COL_TIME_W: float = 200.0
const COL_GAP_W: float = 160.0
const COL_BEST_W: float = 200.0
const ROW_MIN_H: float = 56.0
const TABLE_W: float = 960.0
const REWARD_W: float = 340.0
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 56.0
const BUTTON_GAP_PX: float = 16.0
const PANEL_SKEW: float = MSTheme.SKEW_RATIO * 0.5  ## same shear as MSTheme.box()
const ROW_PAD_Y: float = MSTheme.BUTTON_PAD_Y * 0.5
const FOCUS_COL_PX: float = 2.0


## The single canvas item the screen paints into.
class Board:
	extends Control
	var painter: Callable

	func _draw() -> void:
		painter.call(self)


var _board: Board
var _title_slot: Control
var _sub_slot: Control
var _table_slot: Control
var _reward_slot: Control
var _title: HudText
var _subtitle: HudText
var _head_texts: Array[HudText] = []  ## POS, DRIVER, TIME, GAP, BEST LAP
var _row_texts: Array = []  ## per result row: Array[HudText] (pos, name, time, gap, best)
var _row_player: Array[bool] = []
var _cash_caption: HudText
var _rep_caption: HudText
var _hero_pos: HudText
var _hero_suffix: HudText
var _primary: Button = null
var _star_pop: Array[float] = [0.0, 0.0, 0.0]  ## 0..1 pop progress per star
var _star_tw: Tween = null
var _cash_val: HudText
var _rep_val: HudText
var _all_texts: Array[HudText] = []  ## sorted by pixel size, the order HudText.paint needs
var _next_btn: Button
var _retry_btn: Button
var _show_stars: bool = false  ## the finished event is on the career ladder: paint its stars under the rewards
var _stars: int = 0
var _next_id: String = ""  ## the unlocked event the NEXT EVENT button starts, "" = button hidden
var _event_id_override: String = ""
var _garage_btn: Button
var _menu_btn: Button
var _replay_btn: Button
var _buttons: Array[Button] = []
var _count_tw: Tween = null
var _text_nodes: Array = []  ## [node, i18n key]


func _ready() -> void:
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new(0.0, 0.5))
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
	_table_slot = _slot(body, Vector2(TABLE_W, 0.0))
	_table_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reward_slot = _slot(body, Vector2(REWARD_W * (1.0 + (MSTheme.k() - 1.0) * 0.6), 0.0))

	_hero_pos = _ptext("digits", HERO_PX, MSTheme.TEXT)
	_hero_suffix = _ptext("digits", HERO_SUFFIX_PX, MSTheme.CYAN)
	_cash_caption = _ptext("tracked", REWARD_LABEL_PX, MSTheme.MUTED)
	_cash_val = _ptext("digits", REWARD_PX, MSTheme.AMBER)
	_rep_caption = _ptext("tracked", REWARD_LABEL_PX, MSTheme.MUTED)
	_rep_val = _ptext("digits", REWARD_PX, MSTheme.CYAN)
	_cash_val.set_text("0")
	_rep_val.set_text("0")
	for i: int in 5:
		_head_texts.append(_text("bold", SUB_PX, MSTheme.MUTED))

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", int(BUTTON_GAP_PX))
	col.add_child(footer)
	_next_btn = _button(footer, "results.next", _on_next)
	_next_btn.custom_minimum_size.x = MSTheme.BUTTON_MIN_W * 0.75  # the label is wider than the other footer buttons
	_next_btn.visible = false
	_retry_btn = _button(footer, "results.retry", func() -> void: retry_pressed.emit())
	_replay_btn = _button(footer, "results.replay", func() -> void: replay_pressed.emit())
	_garage_btn = _button(footer, "results.garage", func() -> void: garage_pressed.emit())
	_menu_btn = _button(footer, "results.menu", func() -> void: menu_pressed.emit())

	Settings.changed.connect(_on_settings_changed)
	_refresh_text()
	_sort_texts()
	_retry_btn.grab_focus()


## HudText.paint needs the texts sorted by pixel size so each size is one batch.
func _sort_texts() -> void:
	_all_texts.sort_custom(func(a: HudText, b: HudText) -> bool: return a.size_px < b.size_px)


## An empty Control the containers size; the board reads its rect.
func _slot(parent: Container, min_size: Vector2) -> Control:
	var s := Control.new()
	s.custom_minimum_size = min_size
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.resized.connect(_board.queue_redraw)
	parent.add_child(s)
	return s


func _text(kind: String, px: int, col: Color) -> HudText:
	var t := HudText.new(kind, MSTheme.px(px), col, false)
	_all_texts.append(t)
	return t


## Text for the narrow reward panel (grows less than the table text on a phone).
func _ptext(kind: String, px: int, col: Color) -> HudText:
	var t := HudText.new(kind, roundi(px * minf(MSTheme.k(), PANEL_TEXT_MAX_K)), col, false)
	_all_texts.append(t)
	return t


func _button(parent: Container, key: String, handler: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(MSTheme.BUTTON_MIN_W * 0.5 * (1.0 + (MSTheme.k() - 1.0) * 0.8), MSTheme.button_h())
	b.pressed.connect(handler)
	# The board paints the background; the button keeps only its label (same font, colours and size from the theme).
	var none := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, none)
	for sig: Signal in [b.mouse_entered, b.mouse_exited, b.focus_entered, b.focus_exited, b.button_down, b.button_up, b.visibility_changed]:
		sig.connect(_board.queue_redraw)
	parent.add_child(b)
	_text_nodes.append([b, key])
	_buttons.append(b)
	return b


func _refresh_text() -> void:
	for pair: Array in _text_nodes:
		(pair[0] as Button).text = I18n.t(pair[1])
	_cash_caption.set_text(I18n.t("results.reward_cash"))
	_rep_caption.set_text(I18n.t("results.reward_rep"))
	var keys: Array[String] = ["results.col_pos", "results.col_driver", "results.col_time", "results.col_gap", "results.col_best"]
	for i: int in keys.size():
		_head_texts[i].set_text(I18n.t(keys[i]))
	_board.queue_redraw()


func _on_settings_changed(section: String) -> void:
	if section == Settings.SECTION_GENERAL:
		_refresh_text()


## Event the results belong to, for the NEXT EVENT button. Normally read from the RaceScene above this screen;
## set it by hand where there is none (capture, tests). Call before show_results.
func set_event_id(id: String) -> void:
	_event_id_override = id


func get_next_event_id() -> String:
	return _next_id


func _current_event_id() -> String:
	if not _event_id_override.is_empty():
		return _event_id_override
	var n: Node = get_parent()
	while n != null:
		if n is RaceScene:
			return (n as RaceScene).config_used.event_id
		n = n.get_parent()
	return ""


## Starts the next event of the ladder (already unlocked by the result that was just recorded).
func _on_next() -> void:
	next_pressed.emit()
	if not _next_id.is_empty():
		Router.goto(RACE_SCENE, {RaceScene.CONFIG_PARAM: EventCatalog.config_for(_next_id)})


## Shows the REPLAY button only when the race has a recording to play.
func set_replay_enabled(on: bool) -> void:
	_replay_btn.visible = on


## Rows currently shown, not counting the header.
func get_row_count() -> int:
	return _row_texts.size()


## The reward texts as displayed: {"cash": String, "rep": String}.
func get_reward_text() -> Dictionary:
	return {"cash": _cash_val.text, "rep": _rep_val.text}


## results: one Dictionary per car, sorted by position. Keys: name, position, total_time, best_lap, is_player.
## rewards: {"cash": int, "rep": int}. Missing keys count as zero.
func show_results(results: Array[Dictionary], rewards: Dictionary) -> void:
	var leader_time: float = 0.0
	var player_won: bool = false
	for r: Dictionary in results:
		if int(r.get("position", 0)) == 1:
			leader_time = float(r.get("total_time", 0.0))
			player_won = bool(r.get("is_player", false))
	_title.set_text(I18n.t("results.title"))
	_subtitle.set_text(I18n.t("results.won") if player_won else I18n.t("results.done"))
	for row: Array in _row_texts:
		for t: HudText in row:
			_all_texts.erase(t)
	_row_texts.clear()
	_row_player.clear()
	for r: Dictionary in results:
		_row_texts.append(_result_row(r, leader_time))
		_row_player.append(bool(r.get("is_player", false)))
	_sort_texts()
	_count_rewards(int(rewards.get("cash", 0)), int(rewards.get("rep", 0)))
	var event_id: String = _current_event_id()
	_show_stars = EventCatalog.index_of(event_id) >= 0
	_stars = int(rewards.get("stars", 0))
	var next: String = EventCatalog.next_id(event_id)
	_next_id = next if not next.is_empty() and GameState.is_event_unlocked(next) else ""
	_next_btn.visible = not _next_id.is_empty()
	_primary = _next_btn if _next_btn.visible else _retry_btn
	for b: Button in _buttons:
		b.theme_type_variation = &"PrimaryButton" if b == _primary else &""
	_primary.grab_focus()
	var player_pos: int = 0
	for r: Dictionary in results:
		if bool(r.get("is_player", false)):
			player_pos = int(r.get("position", 0))
	_hero_pos.set_text(str(player_pos) if player_pos > 0 else "-")
	_hero_pos.color = MSTheme.AMBER if player_pos == 1 else MSTheme.TEXT
	_hero_suffix.set_text(I18n.ordinal(player_pos) if player_pos > 0 else "")
	_hero_suffix.color = MSTheme.AMBER if player_pos == 1 else MSTheme.CYAN
	_pop_stars()
	_board.queue_redraw()


func _result_row(r: Dictionary, leader_time: float) -> Array[HudText]:
	var is_player: bool = bool(r.get("is_player", false))
	var pos: int = int(r.get("position", 0))
	var total: float = float(r.get("total_time", 0.0))
	var best: float = float(r.get("best_lap", 0.0))
	var ink: Color = MSTheme.CYAN if is_player else MSTheme.TEXT
	var gap_text: String = I18n.t("results.leader") if pos == 1 else "+%.3f" % (total - leader_time)
	var cells: Array[HudText] = []
	var specs: Array = [
		["digits", str(pos), ink],
		["bold", str(r.get("name", "")), ink],
		["digits", RaceHUD.fmt_time(total) if total > 0.0 else I18n.t("hud.no_time"), ink],
		["digits", gap_text, MSTheme.MUTED],
		["digits", RaceHUD.fmt_time(best) if best > 0.0 else I18n.t("hud.no_time"), ink]]
	for s: Array in specs:
		var t: HudText = _text(s[0], ROW_PX, s[2])
		t.set_text(s[1])
		cells.append(t)
	return cells


## Counts the rewards up from zero over COUNT_UP_S seconds.
func _count_rewards(cash: int, rep: int) -> void:
	if _count_tw != null and _count_tw.is_valid():
		_count_tw.kill()
	_cash_val.set_text("0")
	_rep_val.set_text("0")
	_count_tw = create_tween().set_parallel(true)
	_count_tw.tween_method(_set_cash, 0.0, float(cash), COUNT_UP_S)
	_count_tw.tween_method(_set_rep, 0.0, float(rep), COUNT_UP_S)


## Earned stars pop in one after another (overshoot scale plus an expanding ring); unearned ones stay dim.
func _pop_stars() -> void:
	if _star_tw != null and _star_tw.is_valid():
		_star_tw.kill()
	_star_pop = [0.0, 0.0, 0.0]
	if not _show_stars or _stars <= 0:
		return
	_star_tw = create_tween().set_parallel(true)
	for i: int in mini(_stars, GameState.MAX_STARS):
		_star_tw.tween_method(_set_star_pop.bind(i), 0.0, 1.0, STAR_POP_S).set_delay(STAR_DELAY_S + STAR_STEP_S * float(i))


func _set_star_pop(v: float, index: int) -> void:
	_star_pop[index] = v
	_board.queue_redraw()


## Star pop scale: 0 -> about 1.1 -> 1 (back ease out), used by the painter and the tests.
static func pop_scale(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	var u: float = t - 1.0
	return 1.0 + 2.70158 * u * u * u + 1.70158 * u * u


func get_star_pop() -> Array[float]:
	return _star_pop.duplicate()


func _set_cash(v: float) -> void:
	_cash_val.set_text(RaceHUD.group_int(int(v)))
	_board.queue_redraw()


func _set_rep(v: float) -> void:
	_rep_val.set_text(RaceHUD.group_int(int(v)))
	_board.queue_redraw()


# --- painting ---------------------------------------------------------------------------------------------

## Rect of a node in the board's own space.
func _local_rect(n: Control) -> Rect2:
	var g: Rect2 = n.get_global_rect()
	return Rect2(g.position - _board.get_global_rect().position, g.size)


## The four corners of r sheared like a StyleBoxFlat with MSTheme.SKEW_RATIO (about the vertical centre).
static func _skewed(r: Rect2) -> PackedVector2Array:
	var mid: float = r.position.y + r.size.y * 0.5
	var pts := PackedVector2Array()
	for p: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		pts.append(Vector2(p.x + PANEL_SKEW * (p.y - mid), p.y))
	return pts


static func _fill_skewed(c: CanvasItem, r: Rect2, col: Color) -> void:
	c.draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(PANEL_SKEW, 1.0), Vector2(-PANEL_SKEW * (r.position.y + r.size.y * 0.5), 0.0)))
	c.draw_rect(r, col)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _outline_skewed(c: CanvasItem, r: Rect2, col: Color, width: float) -> void:
	var p: PackedVector2Array = _skewed(r.grow(-width * 0.5))
	c.draw_multiline(PackedVector2Array([p[0], p[1], p[1], p[2], p[2], p[3], p[3], p[0]]), col, width, true)


func _paint_board(c: Control) -> void:
	var sep: float = float(MSTheme.GRID_PX * 2)
	var table: Rect2 = _local_rect(_table_slot)
	var rewards: Rect2 = _local_rect(_reward_slot)
	var title_at: Vector2 = _local_rect(_title_slot).position
	var sub_at: Vector2 = _local_rect(_sub_slot).position

	_title.pos = title_at
	_subtitle.pos = sub_at

	# Table: header row, then one row per result. Rows are inset by the panel margins, cells by the row margins.
	var inner_x: float = table.position.x + MSTheme.BUTTON_PAD_X
	var inner_w: float = table.size.x - MSTheme.BUTTON_PAD_X * 2.0
	var cells_x: float = inner_x + MSTheme.BUTTON_PAD_X
	var cells_w: float = inner_w - MSTheme.BUTTON_PAD_X * 2.0
	var name_w: float = cells_w - (COL_POS_W + COL_TIME_W + COL_GAP_W + COL_BEST_W) - sep * 4.0
	var col_x: Array[float] = [cells_x, cells_x + COL_POS_W + sep]
	col_x.append(col_x[1] + name_w + sep)
	col_x.append(col_x[2] + COL_TIME_W + sep)
	col_x.append(col_x[3] + COL_GAP_W + sep)
	var col_w: Array[float] = [COL_POS_W, name_w, COL_TIME_W, COL_GAP_W, COL_BEST_W]
	var y: float = table.position.y + MSTheme.BUTTON_PAD_Y
	var head_h: float = _head_texts[0].height() + ROW_PAD_Y * 2.0
	for i: int in _head_texts.size():
		var t: HudText = _head_texts[i]
		t.pos = Vector2(_aligned_x(col_x[i], col_w[i], t.width(), i >= 2), y + (head_h - t.height()) * 0.5)
	y += head_h
	var highlight: Rect2 = Rect2()
	var has_highlight: bool = false
	var row_slot: float = (table.end.y - MSTheme.BUTTON_PAD_Y - y) / maxf(float(_row_texts.size()), 1.0)
	for ri: int in _row_texts.size():
		var cells: Array = _row_texts[ri]
		var row_h: float = clampf(row_slot, maxf(ROW_MIN_H, (cells[0] as HudText).height() + ROW_PAD_Y * 2.0), ROW_MAX_H)
		for i: int in cells.size():
			var t: HudText = cells[i]
			t.pos = Vector2(_aligned_x(col_x[i], col_w[i], t.width(), i >= 2), y + (row_h - t.height()) * 0.5)
		if _row_player[ri]:
			highlight = Rect2(inner_x, y, inner_w, row_h)
			has_highlight = true
		y += row_h

	# Rewards panel.
	var rx: float = rewards.position.x + MSTheme.BUTTON_PAD_X * 1.5
	var ry: float = rewards.position.y + MSTheme.BUTTON_PAD_Y
	_hero_pos.pos = Vector2(rx, ry)
	_hero_suffix.pos = Vector2(rx + _hero_pos.width() + float(MSTheme.GRID_PX), ry + (_hero_pos.height() - _hero_suffix.height()) * 0.28)
	ry += _hero_pos.height() + sep
	_cash_caption.pos = Vector2(rx, ry)
	ry += _cash_caption.height() + sep
	_cash_val.pos = Vector2(rx, ry)
	ry += _cash_val.height() + sep
	_rep_caption.pos = Vector2(rx, ry)
	ry += _rep_caption.height() + sep
	_rep_val.pos = Vector2(rx, ry)
	var star_r: float = STAR_R * minf(MSTheme.k(), PANEL_TEXT_MAX_K)
	var star_step: float = STAR_STEP * minf(MSTheme.k(), PANEL_TEXT_MAX_K)
	var star_y: float = rewards.end.y - MSTheme.BUTTON_PAD_Y * 2.0 - star_r * 1.5
	var star_right: float = rx + star_step * 2.0 + star_r * 2.0

	# Pass 1: rects.
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(MSTheme.BG.r, MSTheme.BG.g, MSTheme.BG.b, 0.84))
	_fill_skewed(c, table, MSTheme.PLATE_BG)
	_fill_skewed(c, rewards, MSTheme.PLATE_BG)
	if has_highlight:
		_fill_skewed(c, highlight, MSTheme.tint(MSTheme.CYAN, 0.14))
	if _show_stars:
		for i: int in GameState.MAX_STARS:
			var cx: float = star_right - star_r - float(GameState.MAX_STARS - 1 - i) * star_step
			if i < _stars:
				var sc: float = pop_scale(_star_pop[i])
				if sc > 0.0:
					c.draw_colored_polygon(EventSelect.star_points(Vector2(cx, star_y), star_r * sc), MSTheme.AMBER)
			else:
				c.draw_colored_polygon(EventSelect.star_points(Vector2(cx, star_y), star_r), EventSelect.STAR_OFF)
	for b: Button in _buttons:
		if b.visible:
			_fill_skewed(c, _local_rect(b), _button_fill(b))
	# Pass 2: lines.
	_outline_skewed(c, table, MSTheme.BORDER, 1.0)
	_outline_skewed(c, rewards, MSTheme.BORDER, 1.0)
	if has_highlight:
		_outline_skewed(c, highlight, MSTheme.CYAN, 1.0)
	if _show_stars:
		for i: int in mini(_stars, GameState.MAX_STARS):
			var t: float = _star_pop[i]
			if t > 0.0 and t < 1.0:
				var cx2: float = star_right - star_r - float(GameState.MAX_STARS - 1 - i) * star_step
				c.draw_arc(Vector2(cx2, star_y), star_r * (1.0 + t * BURST_GROW), 0.0, TAU, 40, MSTheme.tint(MSTheme.AMBER, 1.0 - t), 3.0, true)
	for b: Button in _buttons:
		if b.visible:
			_outline_skewed(c, _local_rect(b), _button_edge(b), 1.0)
			if b.has_focus():
				_outline_skewed(c, _local_rect(b), MSTheme.MAGENTA, FOCUS_COL_PX)
	# Pass 3: text, one draw per pixel size.
	HudText.paint(c, _all_texts)


static func _aligned_x(x: float, w: float, text_w: float, right: bool) -> float:
	return x + (w - text_w if right else 0.0)


func _button_fill(b: Button) -> Color:
	if b == _primary and not b.disabled:
		var hot: bool = b.get_draw_mode() in [BaseButton.DRAW_HOVER, BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED]
		return Color(0.45, 0.95, 1.0, 1.0) if hot else MSTheme.PRIMARY_FILL
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
