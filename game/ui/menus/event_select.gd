class_name EventSelect
extends Control
## Career screen as a city map: five district tabs (progress, lock state), the events of the selected district as cards
## (mode, laps, time of day, 3 stars, lock reason) and a detail panel with the real rewards, targets and best time.
## Every EventCatalog event sits in exactly one district (district_of). START hands the event's RaceConfig to race_scene
## through Router params["config"]. No rival crews or territory exist yet: the screen shows only what EventCatalog and
## GameState hold.
## Keyboard and controller: left/right switch district (from a card or a tab), up/down move through the cards of the
## district, accept on a card jumps to START, cancel goes back. Touch: tap a tab or a card, tap START; the chevrons move
## the selection on a phone.

const RACE_SCENE: String = "res://race/race_scene.tscn"
const MENU_SCENE: String = "res://ui/menus/main_menu.tscn"
const DESKTOP_WINDOW_ROWS: int = 8  ## cards shown at once in a district on desktop (the rest scroll by selection)
const PHONE_WINDOW_ROWS: int = 4  ## cards shown at once on a phone: 44 pt cards do not fit more
const D_ARDEN: int = 0  ## events without "place": the Neon Wharf loop, its drift and elimination events
const D_ORTAKOY: int = 1
const D_MASLAK: int = 2
const D_BOGAZ: int = 3
const D_POLICE: int = 4  ## every event with "pursuit": true, career and open runs alike (the open ones show OPEN RUN)
const DISTRICT_COUNT: int = 5
const DISTRICT_KEYS: Array[String] = ["place.arden", "place.ortakoy", "place.maslak", "place.bogaz", "career.district.police"]
const TITLE_PX: int = 56
const SUB_PX: int = 16
const NAME_PX: int = 22
const INFO_PX: int = 15
const TAB_NAME_PX: int = 22
const DETAIL_TITLE_PX: int = 40
const CAPTION_PX: int = 16
const VAL_PX: int = 22
const RULE_PX: int = 16
const ROW_H: float = 64.0  ## desktop card height
const ROW_GAP_PX: float = 6.0
const TAB_H: float = 92.0
const LIST_W: float = 760.0
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 56.0
const ACCENT_PX: int = 4  ## red left edge of the selected card, underline of the active tab
const STAR_R: float = 11.0
const STAR_STEP: float = 30.0
const DETAIL_STAR_R: float = 14.0
const STAR_OFF: Color = Color(0.541, 0.580, 0.651, 0.3)
const ARROW_R: float = 0.22  ## chevron half size as a fraction of the button side


## Five-point star pips: earned stars lit, the rest in STAR_OFF. Drawn in one pass, no children.
class Pips:
	extends Control
	var count: int = 3
	var earned: int = 0
	var radius: float = 11.0
	var gap: float = 30.0
	var lit: Color = MSTheme.GOLD

	static func make(n: int, r: float, step: float, on: Color) -> Pips:
		var p := Pips.new()
		p.count = n
		p.radius = r
		p.gap = step
		p.lit = on
		p.custom_minimum_size = Vector2(r * 2.0 + float(n - 1) * step, r * 2.0)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return p

	func _draw() -> void:
		for i: int in count:
			draw_colored_polygon(EventSelect.star_points(Vector2(radius + float(i) * gap, radius), radius), lit if i < earned else EventSelect.STAR_OFF)


## Up or down chevron inside a chevron button.
class Chevron:
	extends Control
	var up: bool = true
	var color: Color = MSTheme.TITANIUM

	func _draw() -> void:
		var m: Vector2 = size * 0.5
		var d: float = minf(size.x, size.y) * ARROW_R
		var pts := PackedVector2Array()
		if up:
			pts = PackedVector2Array([Vector2(m.x - d, m.y + d * 0.5), Vector2(m.x + d, m.y + d * 0.5), Vector2(m.x, m.y - d * 0.5)])
		else:
			pts = PackedVector2Array([Vector2(m.x - d, m.y - d * 0.5), Vector2(m.x + d, m.y - d * 0.5), Vector2(m.x, m.y + d * 0.5)])
		draw_colored_polygon(pts, color)


var _row_btns: Array[Button] = []
var _row_name: Array[Label] = []
var _row_info: Array[Label] = []
var _row_lock: Array[Label] = []
var _row_pips: Array[Pips] = []
var _tabs: Array[Button] = []
var _tab_name: Array[Label] = []
var _tab_count: Array[Label] = []
var _tab_lock: Array[Label] = []
var _tab_bar: Array[ProgressBar] = []
var _tab_line: Array[ColorRect] = []
var _district_ids: Array = []  ## per district: Array of event indices in catalog order
var _title: Label
var _stars_label: Label
var _list_info: Label
var _up_btn: Button
var _down_btn: Button
var _up_chev: Chevron
var _down_chev: Chevron
var _d_name: Label
var _d_meta: Label
var _d_body: VBoxContainer
var _start_btn: Button
var _back_btn: Button
var _district: int = 0
var _sel: int = 0  ## selected event index (catalog order)
var _win: int = 0  ## first visible card position inside the district (phone and desktop)


func _ready() -> void:
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new(0.0, 0.7))
	for d: int in DISTRICT_COUNT:
		_district_ids.append([])
	for i: int in EventCatalog.count():
		(_district_ids[district_of(EventCatalog.id_at(i))] as Array).append(i)

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

	col.add_child(_header())
	col.add_child(_tab_strip())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 4))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_list_column())
	body.add_child(_detail_panel())

	_sel = _default_selection()
	_district = district_of(EventCatalog.id_at(_sel))
	_update_window()
	Settings.changed.connect(_on_settings_changed)
	_refresh_text()
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
	var d: int = district_of(EventCatalog.id_at(index))
	if d != _district:
		_district = d
		_win = 0
	_sel = index
	_update_window()
	_refresh_text()


func get_district() -> int:
	return _district


## Switches to district d and selects its first unfinished unlocked event (else its first event).
func select_district(d: int) -> void:
	if d == _district or d < 0 or d >= DISTRICT_COUNT:
		return
	_set_district(d)


func get_district_event_count() -> int:
	return (_district_ids[_district] as Array).size()


func get_district_stars(d: int) -> int:
	var n: int = 0
	for i: Variant in _district_ids[d]:
		n += GameState.event_stars(EventCatalog.id_at(int(i)))
	return n


func get_district_max_stars(d: int) -> int:
	return (_district_ids[d] as Array).size() * GameState.MAX_STARS


## False when no event of district d is unlocked (the tab shows LOCKED).
func is_district_open(d: int) -> bool:
	for i: Variant in _district_ids[d]:
		if GameState.is_event_unlocked(EventCatalog.id_at(int(i))):
			return true
	return false


func get_visible_row_count() -> int:
	var count: int = 0
	for b: Button in _row_btns:
		if b.visible:
			count += 1
	return count


func is_selected_row_visible() -> bool:
	return _row_btns[_sel].visible


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


## District of an event: the Pursuit district for every pursuit event, else by "place" (no place = Arden Bay).
static func district_of(id: String) -> int:
	var ev: Dictionary = EventCatalog.find(id)
	if bool(ev.get("pursuit", false)):
		return D_POLICE
	match str(ev.get("place", "arden")):
		"ortakoy":
			return D_ORTAKOY
		"maslak":
			return D_MASLAK
		"bogaz":
			return D_BOGAZ
	return D_ARDEN


## Mode label key of an event: pursuit, drift, elimination, time trial (no rivals), duel (one rival), else race.
static func mode_key(id: String) -> String:
	var ev: Dictionary = EventCatalog.find(id)
	if bool(ev.get("pursuit", false)):
		return "career.mode.pursuit"
	var mode: String = EventCatalog.mode_of(id)
	if mode == RaceConfig.MODE_DRIFT:
		return "mode.drift"
	if mode == RaceConfig.MODE_ELIMINATION:
		return "mode.elimination"
	var rivals: int = (ev["skills"] as Array).size()
	if rivals == 0:
		return "career.mode.time_trial"
	return "career.mode.duel" if rivals == 1 else "mode.race"


## Five-point star polygon centred at c.
static func star_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in 10:
		var a: float = -PI * 0.5 + float(i) * PI / 5.0
		var rr: float = r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts


# --- build ---------------------------------------------------------------------------------------------

func _label(text: String, kind: String, px: float, col: Color) -> Label:
	return MSTheme.make_label(text, kind, MSTheme.px(px), col)


func _header() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(MSTheme.GRID_PX))
	_title = _label("", "display", TITLE_PX, MSTheme.TEXT)
	box.add_child(_title)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", int(MSTheme.GRID_PX))
	var glyph: Pips = Pips.make(1, MSTheme.px(9.0), 0.0, MSTheme.GOLD)
	glyph.earned = 1
	sub.add_child(glyph)
	_stars_label = _label("", "tracked", SUB_PX, MSTheme.MUTED)
	sub.add_child(_stars_label)
	box.add_child(sub)
	return box


func _tab_strip() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(MSTheme.GRID_PX))
	for d: int in DISTRICT_COUNT:
		var b := Button.new()
		b.text = ""
		b.clip_contents = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0.0, TAB_H * MSTheme.k())
		var none := StyleBoxEmpty.new()
		b.add_theme_stylebox_override("normal", none)
		b.add_theme_stylebox_override("pressed", none)
		b.add_theme_stylebox_override("hover", MSTheme.box(MSTheme.tint(MSTheme.PEARL, 0.05), Color(0, 0, 0, 0), 0))
		var m := MarginContainer.new()
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_theme_constant_override("margin_left", int(MSTheme.px(4.0)))
		m.add_theme_constant_override("margin_right", int(MSTheme.px(4.0)))
		m.add_theme_constant_override("margin_top", int(MSTheme.px(8.0)))
		m.add_theme_constant_override("margin_bottom", int(MSTheme.px(10.0)))
		b.add_child(m)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", int(MSTheme.px(4.0)))
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(v)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(top)
		var name_l: Label = _label("", "bold", TAB_NAME_PX, MSTheme.TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_l)
		var lock_l: Label = _label("", "tracked", INFO_PX, MSTheme.DANGER)
		top.add_child(lock_l)
		var count_l: Label = _label("", "tracked", INFO_PX, MSTheme.MUTED)
		v.add_child(count_l)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(bar)
		var line := ColorRect.new()
		line.color = MSTheme.RED
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		line.offset_top = -float(ACCENT_PX)
		line.offset_bottom = 0.0
		line.visible = false
		b.add_child(line)
		b.pressed.connect(_set_district.bind(d))
		b.focus_entered.connect(_set_district.bind(d))
		h.add_child(b)
		_tabs.append(b)
		_tab_name.append(name_l)
		_tab_count.append(count_l)
		_tab_lock.append(lock_l)
		_tab_bar.append(bar)
		_tab_line.append(line)
	return h


func _list_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = LIST_W * MSTheme.k()
	col.add_theme_constant_override("separation", int(ROW_GAP_PX * MSTheme.k()))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", int(ROW_GAP_PX * MSTheme.k()))
	col.add_child(rows)
	for i: int in EventCatalog.count():
		_row_btns.append(_row(rows, i))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 2))
	col.add_child(nav)
	_up_btn = _chevron(nav, true)
	_list_info = _label("", "tracked", SUB_PX, MSTheme.MUTED)
	_list_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(_list_info)
	_down_btn = _chevron(nav, false)
	return col


## One event card: number-less name, info line, lock or stars. Built once; refreshed in _refresh_row.
func _row(parent: Container, index: int) -> Button:
	var b := Button.new()
	b.text = ""
	b.clip_contents = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0.0, _row_h())
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", int(MSTheme.px(24.0)))
	m.add_theme_constant_override("margin_right", int(MSTheme.px(20.0)))
	m.add_theme_constant_override("margin_top", int(MSTheme.px(4.0)))
	m.add_theme_constant_override("margin_bottom", int(MSTheme.px(4.0)))
	b.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 2))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 0)
	h.add_child(text)
	var name_l: Label = _label("", "bold", NAME_PX, MSTheme.TEXT)
	name_l.clip_text = true
	name_l.custom_minimum_size.x = 0.0
	text.add_child(name_l)
	var info_l: Label = _label("", "tracked", INFO_PX, MSTheme.MUTED)
	info_l.clip_text = true
	info_l.custom_minimum_size.x = 0.0
	text.add_child(info_l)
	var lock_l: Label = _label("", "tracked", INFO_PX, MSTheme.DANGER)
	lock_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(lock_l)
	var pips := Pips.make(GameState.MAX_STARS, MSTheme.px(STAR_R), MSTheme.px(STAR_STEP), MSTheme.GOLD)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pips)
	b.focus_entered.connect(select.bind(index))
	b.pressed.connect(_on_row_pressed.bind(index))
	parent.add_child(b)
	_row_name.append(name_l)
	_row_info.append(info_l)
	_row_lock.append(lock_l)
	_row_pips.append(pips)
	return b


func _chevron(parent: Container, up: bool) -> Button:
	var b := Button.new()
	b.text = ""
	b.custom_minimum_size = Vector2(_row_h(), _row_h())
	var plate: StyleBoxFlat = MSTheme.card(MSTheme.PANEL_BG, MSTheme.BORDER)
	var dead: StyleBoxFlat = MSTheme.card(MSTheme.DISABLED_BG, MSTheme.tint(MSTheme.STEEL, 0.18))
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, plate)
	b.add_theme_stylebox_override("disabled", dead)
	var chev := Chevron.new()
	chev.up = up
	chev.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(chev)
	b.pressed.connect(_step.bind(-1 if up else 1))
	parent.add_child(b)
	if up:
		_up_chev = chev
	else:
		_down_chev = chev
	return b


func _detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MSTheme.box(MSTheme.PLATE_BG, MSTheme.BORDER))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 2))
	panel.add_child(v)
	_d_name = _label("", "display", DETAIL_TITLE_PX, MSTheme.TEXT)
	v.add_child(_d_name)
	_d_meta = _label("", "tracked", CAPTION_PX, MSTheme.MUTED)
	v.add_child(_d_meta)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var inner := MarginContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("margin_right", int(MSTheme.GRID_PX * 4))  # keeps values clear of the scroll bar
	scroll.add_child(inner)
	_d_body = VBoxContainer.new()
	_d_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_body.add_theme_constant_override("separation", int(MSTheme.GRID_PX))
	inner.add_child(_d_body)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 2))
	v.add_child(foot)
	_back_btn = _button(foot, _on_back, false)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(spacer)
	_start_btn = _button(foot, start_race, true)
	return panel


func _button(parent: Container, handler: Callable, primary: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(MSTheme.BUTTON_MIN_W * (0.75 if primary else 0.5), MSTheme.button_h())
	b.pressed.connect(func() -> void: UiSounds.click())
	b.pressed.connect(handler)
	b.theme_type_variation = &"PrimaryButton" if primary else &"GhostButton"
	parent.add_child(b)
	return b


func _row_h() -> float:
	return MSTheme.button_h() if MSTheme.phone else ROW_H


func _capacity() -> int:
	return PHONE_WINDOW_ROWS if MSTheme.phone else DESKTOP_WINDOW_ROWS


# --- window and selection --------------------------------------------------------------------------------

## Shows the cards of the selected district in a window of _capacity() cards that follows the selection.
func _update_window() -> void:
	var ids: Array = _district_ids[_district]
	var cap: int = _capacity()
	var pos: int = ids.find(_sel)
	_win = clampi(_win, 0, maxi(ids.size() - cap, 0))
	if pos < _win:
		_win = pos
	elif pos >= _win + cap:
		_win = pos - cap + 1
	for b: Button in _row_btns:
		b.visible = false
	for p: int in range(_win, mini(_win + cap, ids.size())):
		_row_btns[int(ids[p])].visible = true


## First unlocked event of district d without a star, else its first event.
func _default_in(d: int) -> int:
	var ids: Array = _district_ids[d]
	for i: Variant in ids:
		var id: String = EventCatalog.id_at(int(i))
		if GameState.is_event_unlocked(id) and GameState.event_stars(id) == 0:
			return int(i)
	return int(ids[0]) if not ids.is_empty() else _sel


func _set_district(d: int) -> void:
	if d == _district or d < 0 or d >= DISTRICT_COUNT:
		return
	_district = d
	_win = 0
	_sel = _default_in(d)
	_update_window()
	_refresh_text()


## Chevron: moves the selection one card up or down inside the district.
func _step(delta: int) -> void:
	var ids: Array = _district_ids[_district]
	var p: int = clampi(ids.find(_sel) + delta, 0, ids.size() - 1)
	UiSounds.click()
	select(int(ids[p]))


## First unlocked event without a star, else the last one (the whole ladder is done).
func _default_selection() -> int:
	for i: int in EventCatalog.count():
		var id: String = EventCatalog.id_at(i)
		if GameState.is_event_unlocked(id) and GameState.event_stars(id) == 0:
			return i
	return EventCatalog.count() - 1


# --- text and state -------------------------------------------------------------------------------------

func _refresh_text() -> void:
	_title.text = I18n.t("event.title")
	_stars_label.text = I18n.t("career.stars") % [GameState.total_stars(), EventCatalog.count() * GameState.MAX_STARS]
	_back_btn.text = I18n.t("common.back")
	_start_btn.text = I18n.t("event.start")
	_start_btn.disabled = not GameState.is_event_unlocked(get_selected_id())
	for d: int in DISTRICT_COUNT:
		_refresh_tab(d)
	for i: int in _row_btns.size():
		_refresh_row(i)
	_refresh_list_nav()
	_refresh_detail()


func _refresh_tab(d: int) -> void:
	var ids: Array = _district_ids[d]
	var any_open: bool = false
	for i: Variant in ids:
		if GameState.is_event_unlocked(EventCatalog.id_at(int(i))):
			any_open = true
	var active: bool = d == _district
	_tab_name[d].text = I18n.t(DISTRICT_KEYS[d])
	_tab_name[d].add_theme_color_override("font_color", MSTheme.TEXT if active else MSTheme.TITANIUM)
	# The lock tag takes the count line of its own tab, so it never sits next to the neighbouring tab's name.
	_tab_count[d].text = I18n.t("event.locked") if not any_open else I18n.t("career.stars") % [get_district_stars(d), get_district_max_stars(d)]
	_tab_count[d].add_theme_color_override("font_color", MSTheme.DANGER if not any_open else MSTheme.MUTED)
	_tab_bar[d].max_value = maxf(float(get_district_max_stars(d)), 1.0)
	_tab_bar[d].value = float(get_district_stars(d))
	_tab_lock[d].visible = false
	_tab_line[d].visible = active


func _refresh_row(i: int) -> void:
	var id: String = EventCatalog.id_at(i)
	var open: bool = GameState.is_event_unlocked(id)
	_row_name[i].text = I18n.t(EventCatalog.name_key(id))
	_row_name[i].add_theme_color_override("font_color", MSTheme.TEXT if open else MSTheme.MUTED)
	_row_info[i].text = _info_line(id, open)
	# A locked card's reason is a sentence (event name in Title Case), so it sets in the body face, not tracked capitals.
	_row_info[i].add_theme_font_override("font", MSTheme.font("body" if not open else "tracked"))
	_row_lock[i].text = I18n.t("event.locked")
	_row_lock[i].visible = not open
	_row_pips[i].earned = GameState.event_stars(id)
	_row_pips[i].visible = open
	_row_pips[i].queue_redraw()
	var sb: StyleBox
	if i == _sel:
		sb = MSTheme.edged(MSTheme.GRAPHITE_3 if open else MSTheme.DISABLED_BG, MSTheme.RED, int(MSTheme.px(ACCENT_PX)))
	elif open:
		sb = MSTheme.card(MSTheme.PANEL_BG, MSTheme.BORDER)
	else:
		sb = MSTheme.card(MSTheme.DISABLED_BG, MSTheme.tint(MSTheme.STEEL, 0.18))
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		_row_btns[i].add_theme_stylebox_override(state, sb)


func _info_line(id: String, open: bool) -> String:
	if not open:
		return I18n.t("career.locked_by") % I18n.t(EventCatalog.name_key(EventCatalog.previous_id(id)))
	var ev: Dictionary = EventCatalog.find(id)
	var parts: PackedStringArray = [I18n.t(mode_key(id)), I18n.t("tod.%s" % str(ev.get("tod", "night")))]
	if EventCatalog.mode_of(id) == RaceConfig.MODE_DRIFT:
		parts.append(I18n.t("event.time_limit_value") % int(ev["time_limit"]))
	else:
		var laps: int = int(ev["laps"])
		parts.append("%d %s" % [laps, I18n.t("event.lap" if laps == 1 else "event.laps")])
	var rivals: int = (ev["skills"] as Array).size()
	if rivals > 0:
		parts.append("%d %s" % [rivals, I18n.t("event.rival" if rivals == 1 else "event.rivals")])
	if EventCatalog.is_open(id):
		parts.append(I18n.t("career.free"))
	return " · ".join(parts)


func _refresh_list_nav() -> void:
	var ids: Array = _district_ids[_district]
	var pos: int = ids.find(_sel)
	var last: int = mini(_win + _capacity(), ids.size())
	_list_info.text = "%d-%d / %d" % [_win + 1, last, ids.size()]
	_up_btn.disabled = pos <= 0
	_down_btn.disabled = pos >= ids.size() - 1
	_up_chev.color = MSTheme.MUTED if _up_btn.disabled else MSTheme.TITANIUM
	_down_chev.color = MSTheme.MUTED if _down_btn.disabled else MSTheme.TITANIUM
	_up_chev.queue_redraw()
	_down_chev.queue_redraw()


func _refresh_detail() -> void:
	var id: String = get_selected_id()
	var ev: Dictionary = EventCatalog.find(id)
	var open: bool = GameState.is_event_unlocked(id)
	var free: bool = EventCatalog.is_open(id)
	_d_name.text = I18n.t(EventCatalog.name_key(id))
	_d_meta.text = "%s  ·  %s" % [I18n.t(DISTRICT_KEYS[district_of(id)]), I18n.t("career.free" if free else "career.tag")]
	for c: Node in _d_body.get_children():
		_d_body.remove_child(c)
		c.queue_free()
	if not open:
		_d_body.add_child(_note(I18n.t("career.locked_by") % I18n.t(EventCatalog.name_key(EventCatalog.previous_id(id))), MSTheme.DANGER))
	_stat_row(_d_body, I18n.t("career.mode_label"), _value(I18n.t(mode_key(id))))
	if EventCatalog.mode_of(id) == RaceConfig.MODE_DRIFT:
		_stat_row(_d_body, I18n.t("event.time_limit"), _value(I18n.t("event.time_limit_value") % int(ev["time_limit"])))
	else:
		_stat_row(_d_body, I18n.t("event.laps"), _value(str(ev["laps"])))
	var rivals: int = (ev["skills"] as Array).size()
	if rivals > 0:
		_stat_row(_d_body, I18n.t("event.rivals"), _value(str(rivals)))
		_stat_row(_d_body, I18n.t("event.ai"), _value(I18n.t("event.level_%d" % int(ev["level"]))))
	_stat_row(_d_body, I18n.t("career.tod_label"), _value(I18n.t("tod.%s" % str(ev.get("tod", "night")))))
	if bool(ev.get("pursuit", false)):
		var goal: String = I18n.t("pursuit.goal.escape")
		if ev.has("survive_s"):
			var secs: int = int(ev["survive_s"])
			goal = I18n.t("pursuit.goal.survive") % [secs / 60, secs % 60]
		_stat_row(_d_body, I18n.t("career.goal_label"), _value(goal))
	var best: float = GameState.best_time(id)
	_stat_row(_d_body, I18n.t("event.best"), _value(RaceHUD.fmt_time(best) if best > 0.0 else I18n.t("hud.no_time")))
	var pips := Pips.make(GameState.MAX_STARS, MSTheme.px(DETAIL_STAR_R), MSTheme.px(DETAIL_STAR_R * 2.4), MSTheme.GOLD)
	pips.earned = GameState.event_stars(id)
	_stat_row(_d_body, I18n.t("event.stars"), pips)
	_d_body.add_child(_rule())
	var reward: Dictionary = EventCatalog.win_rewards(id)
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 3))
	pair.add_child(_value(I18n.t("garage.money") % int(reward["cash"]), MSTheme.GOLD))
	pair.add_child(_value("%s %s" % [RaceHUD.group_int(int(reward["rep"])), I18n.t("results.reward_rep")], MSTheme.TITANIUM))
	_stat_row(_d_body, I18n.t("event.win_reward"), pair)
	_d_body.add_child(_rule())
	_d_body.add_child(_label(I18n.t("career.rules_label"), "tracked", CAPTION_PX, MSTheme.MUTED))
	for line: String in _rule_lines(id):
		_d_body.add_child(_note(line, MSTheme.TITANIUM))
	if free:
		_d_body.add_child(_rule())
		_d_body.add_child(_note(I18n.t("career.free_note"), MSTheme.MUTED))


func _rule_lines(id: String) -> Array[String]:
	var ev: Dictionary = EventCatalog.find(id)
	var rules: Array[String] = []
	if EventCatalog.is_time_event(id):
		var limits: Array = ev["star_times"]
		for i: int in limits.size():
			var n: int = 3 - i
			rules.append(I18n.t("event.rule_time") % [RaceHUD.fmt_time(float(limits[i])), n, I18n.t("event.star" if n == 1 else "event.stars")])
	elif EventCatalog.is_score_event(id):
		var scores: Array = ev["star_scores"]
		for i: int in scores.size():
			var n: int = 3 - i
			rules.append(I18n.t("event.rule_score") % [RaceHUD.group_int(int(scores[i])), n, I18n.t("event.star" if n == 1 else "event.stars")])
	elif EventCatalog.mode_of(id) == RaceConfig.MODE_ELIMINATION:
		rules = [I18n.t("event.rule_win"), I18n.t("event.rule_podium"), I18n.t("event.rule_elim")]
	else:
		rules = [I18n.t("event.rule_win"), I18n.t("event.rule_podium"), I18n.t("event.rule_finish")]
	return rules


func _value(text: String, col: Color = MSTheme.TEXT) -> Label:
	var l: Label = MSTheme.make_label(text, "digits", MSTheme.px(VAL_PX), col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _stat_row(parent: Container, caption: String, value: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 2))
	var cap: Label = _label(caption, "tracked", CAPTION_PX, MSTheme.MUTED)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(cap)
	h.add_child(value)
	parent.add_child(h)


func _note(text: String, col: Color) -> Label:
	var l: Label = MSTheme.make_label(text, "bold", MSTheme.px(RULE_PX), col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = MSTheme.BORDER
	r.custom_minimum_size = Vector2(0.0, 1.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


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


## Up/down move through the cards of the district, left/right switch district while a card has focus.
func _input(event: InputEvent) -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus == null:
		return
	var i: int = _row_btns.find(focus)
	if i < 0:
		return
	var ids: Array = _district_ids[_district]
	if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
		var p: int = ids.find(i) + (1 if event.is_action_pressed("ui_down") else -1)
		if p < 0 or p >= ids.size():
			return
		select(int(ids[p]))
		_row_btns[_sel].grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		var step: int = 1 if event.is_action_pressed("ui_right") else -1
		_set_district(posmod(_district + step, DISTRICT_COUNT))
		_row_btns[_sel].grab_focus()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()

