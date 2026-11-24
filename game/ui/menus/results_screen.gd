class_name ResultsScreen
extends Control
## Race results: finishing order with times and gaps, best laps, the player row highlighted, and rewards
## that count up. Emits retry_pressed, garage_pressed or menu_pressed.

signal retry_pressed
signal garage_pressed
signal menu_pressed

const COUNT_UP_S: float = 1.2
const TITLE_PX: int = 40
const SUB_PX: int = 18
const ROW_PX: int = 26
const REWARD_PX: int = 56
const REWARD_LABEL_PX: int = 18
const COL_POS_W: float = 96.0
const COL_TIME_W: float = 200.0
const COL_GAP_W: float = 160.0
const COL_BEST_W: float = 200.0
const ROW_MIN_H: float = 56.0
const TABLE_W: float = 960.0
const REWARD_W: float = 320.0
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 56.0
const BUTTON_GAP_PX: float = 16.0

var _title: Label
var _subtitle: Label
var _rows: VBoxContainer
var _cash_val: Label
var _rep_val: Label
var _cash_caption: Label
var _rep_caption: Label
var _retry_btn: Button
var _garage_btn: Button
var _menu_btn: Button
var _count_tw: Tween = null
var _text_nodes: Array = []  ## [node, i18n key]


func _ready() -> void:
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(MSTheme.BG.r, MSTheme.BG.g, MSTheme.BG.b, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

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

	_title = MSTheme.make_label("", "bold", TITLE_PX, MSTheme.TEXT)
	col.add_child(_title)
	_subtitle = MSTheme.make_label("", "tracked", SUB_PX, MSTheme.CYAN)
	col.add_child(_subtitle)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 4))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	var table := PanelContainer.new()
	table.custom_minimum_size = Vector2(TABLE_W, 0.0)
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(table)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	table.add_child(_rows)

	var rewards := PanelContainer.new()
	rewards.custom_minimum_size = Vector2(REWARD_W, 0.0)
	body.add_child(rewards)
	var rcol := VBoxContainer.new()
	rewards.add_child(rcol)
	_cash_caption = MSTheme.make_label("", "tracked", REWARD_LABEL_PX, MSTheme.MUTED)
	rcol.add_child(_cash_caption)
	_cash_val = MSTheme.make_label("0", "digits", REWARD_PX, MSTheme.AMBER)
	rcol.add_child(_cash_val)
	_rep_caption = MSTheme.make_label("", "tracked", REWARD_LABEL_PX, MSTheme.MUTED)
	rcol.add_child(_rep_caption)
	_rep_val = MSTheme.make_label("0", "digits", REWARD_PX, MSTheme.CYAN)
	rcol.add_child(_rep_val)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", int(BUTTON_GAP_PX))
	col.add_child(footer)
	_retry_btn = _button(footer, "results.retry", func() -> void: retry_pressed.emit())
	_garage_btn = _button(footer, "results.garage", func() -> void: garage_pressed.emit())
	_menu_btn = _button(footer, "results.menu", func() -> void: menu_pressed.emit())

	Settings.changed.connect(_on_settings_changed)
	_refresh_text()
	_retry_btn.grab_focus()


func _button(parent: Container, key: String, handler: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(MSTheme.BUTTON_MIN_W * 0.5, MSTheme.BUTTON_MIN_H)
	b.pressed.connect(handler)
	parent.add_child(b)
	_text_nodes.append([b, key])
	return b


func _refresh_text() -> void:
	for pair: Array in _text_nodes:
		(pair[0] as Button).text = I18n.t(pair[1])
	_cash_caption.text = I18n.t("results.reward_cash")
	_rep_caption.text = I18n.t("results.reward_rep")


func _on_settings_changed(section: String) -> void:
	if section == Settings.SECTION_GENERAL:
		_refresh_text()


## results: one Dictionary per car, sorted by position. Keys: name, position, total_time, best_lap, is_player.
## rewards: {"cash": int, "rep": int}. Missing keys count as zero.
func show_results(results: Array[Dictionary], rewards: Dictionary) -> void:
	for c: Node in _rows.get_children():
		c.queue_free()
	var leader_time: float = 0.0
	var player_won: bool = false
	for r: Dictionary in results:
		if int(r.get("position", 0)) == 1:
			leader_time = float(r.get("total_time", 0.0))
			player_won = bool(r.get("is_player", false))
	_title.text = I18n.t("results.title")
	_subtitle.text = I18n.t("results.won") if player_won else I18n.t("results.done")
	_rows.add_child(_header_row())
	for r: Dictionary in results:
		_rows.add_child(_result_row(r, leader_time))
	_count_rewards(int(rewards.get("cash", 0)), int(rewards.get("rep", 0)))
	_retry_btn.grab_focus()


func _header_row() -> Control:
	var panel := _row_panel(false)
	panel.custom_minimum_size = Vector2(0.0, 0.0)
	var h := HBoxContainer.new()
	panel.add_child(h)
	h.add_child(_cell(I18n.t("results.col_pos"), COL_POS_W, HORIZONTAL_ALIGNMENT_LEFT, SUB_PX, MSTheme.MUTED))
	var name_lbl := _cell(I18n.t("results.col_driver"), 0.0, HORIZONTAL_ALIGNMENT_LEFT, SUB_PX, MSTheme.MUTED)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_lbl)
	h.add_child(_cell(I18n.t("results.col_time"), COL_TIME_W, HORIZONTAL_ALIGNMENT_RIGHT, SUB_PX, MSTheme.MUTED))
	h.add_child(_cell(I18n.t("results.col_gap"), COL_GAP_W, HORIZONTAL_ALIGNMENT_RIGHT, SUB_PX, MSTheme.MUTED))
	h.add_child(_cell(I18n.t("results.col_best"), COL_BEST_W, HORIZONTAL_ALIGNMENT_RIGHT, SUB_PX, MSTheme.MUTED))
	return panel


func _row_panel(highlight: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = MSTheme.tint(MSTheme.CYAN, 0.14) if highlight else Color(0, 0, 0, 0)
	st.border_color = MSTheme.CYAN if highlight else Color(0, 0, 0, 0)
	st.set_border_width_all(1 if highlight else 0)
	st.skew = Vector2(-MSTheme.SKEW_RATIO * 0.5, 0.0)
	st.content_margin_left = MSTheme.BUTTON_PAD_X
	st.content_margin_right = MSTheme.BUTTON_PAD_X
	st.content_margin_top = MSTheme.BUTTON_PAD_Y * 0.5
	st.content_margin_bottom = MSTheme.BUTTON_PAD_Y * 0.5
	panel.add_theme_stylebox_override("panel", st)
	return panel


func _result_row(r: Dictionary, leader_time: float) -> Control:
	var is_player: bool = bool(r.get("is_player", false))
	var pos: int = int(r.get("position", 0))
	var total: float = float(r.get("total_time", 0.0))
	var best: float = float(r.get("best_lap", 0.0))
	var panel := _row_panel(is_player)
	panel.custom_minimum_size = Vector2(0.0, ROW_MIN_H)
	var h := HBoxContainer.new()
	panel.add_child(h)
	var ink: Color = MSTheme.CYAN if is_player else MSTheme.TEXT
	h.add_child(_cell(str(pos), COL_POS_W, HORIZONTAL_ALIGNMENT_LEFT, ROW_PX, ink, "digits"))
	var name_lbl := _cell(str(r.get("name", "")), 0.0, HORIZONTAL_ALIGNMENT_LEFT, ROW_PX, ink)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_lbl)
	h.add_child(_cell(RaceHUD.fmt_time(total) if total > 0.0 else I18n.t("hud.no_time"), COL_TIME_W,
		HORIZONTAL_ALIGNMENT_RIGHT, ROW_PX, ink, "digits"))
	var gap_text: String = I18n.t("results.leader") if pos == 1 else "+%.3f" % (total - leader_time)
	h.add_child(_cell(gap_text, COL_GAP_W, HORIZONTAL_ALIGNMENT_RIGHT, ROW_PX, MSTheme.MUTED, "digits"))
	h.add_child(_cell(RaceHUD.fmt_time(best) if best > 0.0 else I18n.t("hud.no_time"), COL_BEST_W,
		HORIZONTAL_ALIGNMENT_RIGHT, ROW_PX, ink, "digits"))
	return panel


func _cell(text: String, min_w: float, align: HorizontalAlignment, px: int, color: Color, kind: String = "bold") -> Label:
	var l := MSTheme.make_label(text, kind, px, color)
	l.custom_minimum_size = Vector2(min_w, 0.0)
	l.horizontal_alignment = align
	return l


## Counts the rewards up from zero over COUNT_UP_S seconds.
func _count_rewards(cash: int, rep: int) -> void:
	if _count_tw != null and _count_tw.is_valid():
		_count_tw.kill()
	_cash_val.text = "0"
	_rep_val.text = "0"
	_count_tw = create_tween().set_parallel(true)
	_count_tw.tween_method(func(v: float) -> void: _cash_val.text = RaceHUD.group_int(int(v)), 0.0, float(cash), COUNT_UP_S)
	_count_tw.tween_method(func(v: float) -> void: _rep_val.text = RaceHUD.group_int(int(v)), 0.0, float(rep), COUNT_UP_S)
