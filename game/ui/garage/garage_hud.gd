class_name GarageHud
extends Control
## 2D layer of the garage over the 3D view: car name and class, cash, four stat bars, the PAINT / RIMS / UPGRADES
## tabs, preset views, BACK and RACE. It only emits signals and shows what garage.gd hands it; GameState and
## CarMaterials are touched by garage.gd. Strings go through I18n.t. Layout rules: docs/design/UI_STYLE.md.

signal back_pressed
signal race_pressed
signal view_pressed(view: String)
signal paint_previewed(colour: Color)
signal paint_committed(colour: Color)
signal rim_pressed(colour: Color)
signal upgrade_pressed(part: String)
signal car_step_pressed(dir: int)  ## carousel: -1 previous car, +1 next car
signal car_action_pressed  ## BUY, SELECT

const PAINTS: Array[Color] = [
	Color("8E0F1E"), Color("0A1A5C"), Color("33363B"), Color("E8E9EE"), Color("0B0D12"), Color("19E6FF"),
	Color("FF2BD6"), Color("FFC23D"), Color("0F4D2E"), Color("A9AFBA"), Color("4B1E8C"), Color("C4501B"),
]
const RIM_KEYS: PackedStringArray = [
	"garage.rim_gunmetal", "garage.rim_silver", "garage.rim_graphite", "garage.rim_chrome", "garage.rim_white", "garage.rim_bronze",
]
const RIM_COLOURS: Array[Color] = [
	Color(0.314, 0.333, 0.369), Color(0.75, 0.77, 0.8), Color(0.2, 0.21, 0.23), Color(0.92, 0.93, 0.95), Color(0.95, 0.95, 0.92), Color(0.55, 0.36, 0.18),
]
const PARTS: PackedStringArray = ["engine", "tires", "nitro", "weight"]
const PART_KEYS: Dictionary = {"engine": "garage.part_engine", "tires": "garage.part_tires", "nitro": "garage.part_nitro", "weight": "garage.part_weight"}
const STATS: PackedStringArray = ["speed", "accel", "handling", "nitro"]
const STAT_KEYS: Dictionary = {"speed": "garage.stat_speed", "accel": "garage.stat_accel", "handling": "garage.stat_handling", "nitro": "garage.stat_nitro"}
const VIEWS: PackedStringArray = ["front", "side", "rear34", "overview"]
const VIEW_KEYS: Dictionary = {"front": "garage.view_front", "side": "garage.view_side", "rear34": "garage.view_rear", "overview": "garage.view_overview"}
const PAGES: PackedStringArray = ["paint", "rims", "upgrades"]
const PAGE_KEYS: Dictionary = {"paint": "garage.tab_paint", "rims": "garage.tab_rims", "upgrades": "garage.tab_upgrades"}
const MARGIN_PX: float = 40.0
const PANEL_W: float = 520.0
const PANEL_TOP_PX: float = 136.0
const SWATCH_W: float = 70.0
const SWATCH_H: float = 56.0
const PIP_PX: float = 18.0
const TOUCH_H: float = 88.0  ## BUY and carousel buttons: touch targets at 1080 px (64 px was too small to hit reliably)
const STRIP_H: float = 28.0
const STEP_SATURATION: float = 0.85
const VALUE_FLOOR: float = 0.1
const SHAKE_S: float = 0.36
const SHAKE_RAD: float = 0.035
const MSG_HOLD_S: float = 1.6
const MSG_FADE_S: float = 0.4
const BAR_W: float = 320.0
const STAT_LABEL_W: float = 220.0

var _keyed: Array = []  ## [node, i18n key] pairs for static text
var _state: Dictionary = {}
var _msg_key: String = ""
var _msg_error: bool = false
var _car_name: Label
var _car_class: Label
var _hint: Label
var _cash_caption: Label
var _cash_value: Label
var _stat_labels: Dictionary = {}
var _bars: Dictionary = {}
var _tabs: Dictionary = {}
var _pages: Dictionary = {}
var _rim_buttons: Array[Button] = []
var _rows: Dictionary = {}
var _views: Dictionary = {}
var _msg: Label
var _msg_tw: Tween = null
var _shake_tw: Tween = null
var _hue_strip: GradientStrip
var _value_strip: GradientStrip
var _back_btn: Button
var _race_btn: Button
var _car_prev: Button
var _car_next: Button
var _car_action: Button
var _hue: float = 0.0
var _value: float = 1.0
var _built: bool = false


## Inner control: a gradient strip (hue or value) that reports a 0..1 position while dragged and when released.
class GradientStrip extends Control:
	signal changed(t: float)
	signal released(t: float)
	var mode: String = "hue"
	var t: float = 0.0
	var base_hue: float = 0.0
	var _drag: bool = false
	var _tex: ImageTexture = null

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0.0, GarageHud.STRIP_H)

	func set_position_t(v: float) -> void:
		t = clampf(v, 0.0, 1.0)
		queue_redraw()

	func _colour_at(v: float) -> Color:
		if mode == "hue":
			return Color.from_hsv(v, GarageHud.STEP_SATURATION, 1.0)
		return Color.from_hsv(base_hue, GarageHud.STEP_SATURATION, GarageHud.VALUE_FLOOR + (1.0 - GarageHud.VALUE_FLOOR) * v)

	func _draw() -> void:
		var img := Image.create(128, 1, false, Image.FORMAT_RGBA8)
		for x: int in 128:
			img.set_pixel(x, 0, _colour_at(float(x) / 127.0))
		_tex = ImageTexture.create_from_image(img)
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
		var mx: float = t * size.x
		draw_rect(Rect2(mx - 3.0, -2.0, 6.0, size.y + 4.0), MSTheme.TEXT, false, 2.0)

	func _gui_input(e: InputEvent) -> void:
		var mb: InputEventMouseButton = e as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_set_from_x(mb.position.x)
			elif _drag:
				_drag = false
				released.emit(t)
			accept_event()
			return
		var mm: InputEventMouseMotion = e as InputEventMouseMotion
		if mm != null and _drag:
			_set_from_x(mm.position.x)
			accept_event()
			return
		if e.is_action_pressed("ui_left") or e.is_action_pressed("ui_right"):
			var step: float = 0.02 if e.is_action_pressed("ui_right") else -0.02
			set_position_t(t + step)
			changed.emit(t)
			released.emit(t)
			accept_event()

	func _set_from_x(x: float) -> void:
		set_position_t(x / maxf(size.x, 1.0))
		changed.emit(t)


func _ready() -> void:
	build()


## Builds the whole layer once. Safe to call again; it does nothing after the first build.
func build() -> void:
	if _built:
		return
	_built = true
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ins: Vector4 = MSTheme.safe_insets()
	var m: float = MARGIN_PX

	_back_btn = _button("common.back", Vector2(200.0, 56.0))
	_back_btn.name = "Back"
	_back_btn.pressed.connect(func() -> void: back_pressed.emit())
	_place(_back_btn, 0.0, 0.0, 0.0, 0.0, ins.x + m, ins.y + m, 0, 0)

	var head_panel := PanelContainer.new()
	head_panel.name = "CarHead"
	head_panel.add_theme_stylebox_override("panel", _opaque_box())
	head_panel.custom_minimum_size = Vector2(470.0, 0.0)  ## wide enough to cover the room's neon sign behind it
	_place(head_panel, 0.0, 0.0, 0.0, 0.0, ins.x + m, ins.y + m + 80.0, 0, 0)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head_panel.add_child(head)
	_car_name = MSTheme.make_label("", "slant", 40, MSTheme.TEXT, true)
	head.add_child(_car_name)
	_car_class = _keyed_label("garage.class_street", "tracked", 18, MSTheme.CYAN)
	head.add_child(_car_class)
	_hint = _keyed_label("garage.hint", "tracked", 18, MSTheme.MUTED)
	head.add_child(_hint)

	var cash := VBoxContainer.new()
	cash.name = "Cash"
	cash.alignment = BoxContainer.ALIGNMENT_END
	_place(cash, 1.0, 0.0, 1.0, 0.0, -(ins.z + m + 320.0), ins.y + m, -(ins.z + m), ins.y + m + 80.0)
	_cash_caption = _keyed_label("garage.cash", "tracked", 18, MSTheme.MUTED)
	_cash_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash.add_child(_cash_caption)
	_cash_value = MSTheme.make_label("0", "digits", 40, MSTheme.AMBER, true)
	_cash_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash.add_child(_cash_value)

	_build_stats(ins, m)
	_build_carousel(ins, m)
	_build_panel(ins, m)
	_build_views(ins, m)
	apply_language()


func _build_stats(ins: Vector4, m: float) -> void:
	var box := VBoxContainer.new()
	box.name = "Stats"
	box.add_theme_constant_override("separation", 14)
	# on a backing panel: bare labels were unreadable over a light car body (the wing hid "ACCELERATION")
	var back := PanelContainer.new()
	back.name = "StatsPanel"
	back.add_theme_stylebox_override("panel", _opaque_box())
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(back, 0.0, 0.0, 0.0, 0.0, ins.x + m, ins.y + m + 244.0, ins.x + m + 470.0, ins.y + m + 244.0)
	back.add_child(box)
	for s: String in STATS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var lab: Label = _keyed_label(STAT_KEYS[s], "tracked", 18, MSTheme.TEXT)
		lab.custom_minimum_size = Vector2(STAT_LABEL_W, 0.0)
		row.add_child(lab)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.custom_minimum_size = Vector2(BAR_W, 14.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		box.add_child(row)
		_stat_labels[s] = lab
		_bars[s] = bar


## Car carousel under the stat bars: [<] [BUY / SELECT / SELECTED / LOCKED] [>].
func _build_carousel(ins: Vector4, m: float) -> void:
	var row := HBoxContainer.new()
	row.name = "Carousel"
	row.add_theme_constant_override("separation", 12)
	_place(row, 0.0, 0.0, 0.0, 0.0, ins.x + m, ins.y + m + 450.0, ins.x + m + 560.0, ins.y + m + 450.0 + TOUCH_H)
	_car_prev = Button.new()
	_car_prev.name = "CarPrev"
	_car_prev.text = "<"
	_car_prev.custom_minimum_size = Vector2(84.0, TOUCH_H)
	_car_prev.pressed.connect(func() -> void: car_step_pressed.emit(-1))
	row.add_child(_car_prev)
	_car_action = Button.new()
	_car_action.name = "CarAction"
	_car_action.custom_minimum_size = Vector2(300.0, TOUCH_H)
	_car_action.pressed.connect(func() -> void: car_action_pressed.emit())
	row.add_child(_car_action)
	_car_next = Button.new()
	_car_next.name = "CarNext"
	_car_next.text = ">"
	_car_next.custom_minimum_size = Vector2(84.0, TOUCH_H)
	_car_next.pressed.connect(func() -> void: car_step_pressed.emit(1))
	row.add_child(_car_next)


func _build_panel(ins: Vector4, m: float) -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", _opaque_box())
	_place(panel, 1.0, 0.0, 1.0, 0.0, -(ins.z + m + PANEL_W), ins.y + PANEL_TOP_PX, -(ins.z + m), ins.y + PANEL_TOP_PX)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	col.add_child(tabs)
	for p: String in PAGES:
		var b: Button = _button(PAGE_KEYS[p], Vector2(150.0, 52.0))
		b.toggle_mode = true
		b.pressed.connect(_show_page.bind(p))
		# Hover must not look like "selected": only the pressed tab gets the cyan fill and text.
		b.add_theme_stylebox_override("hover", MSTheme.box(MSTheme.PANEL_BG, MSTheme.BORDER))
		b.add_theme_stylebox_override("hover_pressed", MSTheme.box(MSTheme.tint(MSTheme.CYAN, 0.32), MSTheme.CYAN))
		tabs.add_child(b)
		_tabs[p] = b
	(_tabs["paint"] as Button).button_pressed = true

	var pages := VBoxContainer.new()
	col.add_child(pages)
	_pages["paint"] = _build_paint_page()
	_pages["rims"] = _build_rims_page()
	_pages["upgrades"] = _build_upgrades_page()
	for p: String in PAGES:
		var page: Control = _pages[p]
		pages.add_child(page)
	_show_page("paint")

	_msg = MSTheme.make_label("", "tracked", 22, MSTheme.MUTED, false)
	_msg.custom_minimum_size = Vector2(0.0, 30.0)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_msg)

	_race_btn = _button("menu.race", Vector2(PANEL_W, 72.0))
	_race_btn.name = "Race"
	# the one primary action of the screen: filled, the rest stay outlined
	_race_btn.add_theme_stylebox_override("normal", MSTheme.box(MSTheme.CYAN, MSTheme.CYAN))
	_race_btn.add_theme_stylebox_override("hover", MSTheme.box(MSTheme.CYAN.lightened(0.25), MSTheme.CYAN))
	_race_btn.add_theme_stylebox_override("pressed", MSTheme.box(MSTheme.CYAN.darkened(0.2), MSTheme.CYAN))
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_race_btn.add_theme_color_override(c, MSTheme.BG)
	_race_btn.pressed.connect(func() -> void: race_pressed.emit())
	col.add_child(_race_btn)


func _build_paint_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for c: Color in PAINTS:
		grid.add_child(_swatch(c))
	page.add_child(grid)
	_hue_strip = GradientStrip.new()
	_hue_strip.mode = "hue"
	_hue_strip.changed.connect(_on_hue_changed)
	_hue_strip.released.connect(_on_strip_released)
	page.add_child(_hue_strip)
	_value_strip = GradientStrip.new()
	_value_strip.mode = "value"
	_value_strip.changed.connect(_on_value_changed)
	_value_strip.released.connect(_on_strip_released)
	page.add_child(_value_strip)
	page.add_child(_keyed_label("garage.hue", "tracked", 18, MSTheme.MUTED))
	return page


func _build_rims_page() -> Control:
	var page := GridContainer.new()
	page.columns = 2
	page.add_theme_constant_override("h_separation", 16)
	page.add_theme_constant_override("v_separation", 16)
	for i: int in RIM_KEYS.size():
		var b: Button = _button(RIM_KEYS[i], Vector2(228.0, 64.0))
		b.icon = _disc(int(MSTheme.ICON_PX * 1.6), RIM_COLOURS[i])
		b.expand_icon = false
		var col: Color = RIM_COLOURS[i]
		b.pressed.connect(func() -> void: rim_pressed.emit(col))
		page.add_child(b)
		_rim_buttons.append(b)
	return page


func _build_upgrades_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	for part: String in PARTS:
		# One line per part: name, level pips, price, BUY. Pips: filled cyan = owned, outlined = not yet.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.custom_minimum_size = Vector2(0.0, TOUCH_H)
		var name_l: Label = _keyed_label(PART_KEYS[part], "bold", 20, MSTheme.TEXT)
		name_l.custom_minimum_size = Vector2(118.0, 0.0)  # the widest name fits; BUY must stay inside the panel
		row.add_child(name_l)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 4)
		var pip_list: Array[Panel] = []
		for i: int in GameState.MAX_UPGRADE_LEVEL:
			var pip := Panel.new()
			pip.custom_minimum_size = Vector2(PIP_PX, PIP_PX)
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pips.add_child(pip)
			pip_list.append(pip)
		row.add_child(pips)
		var price := MSTheme.make_label("", "digits", 22, MSTheme.TEXT, false)
		price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(price)
		var buy: Button = _button("garage.buy", Vector2(120.0, TOUCH_H))
		buy.pressed.connect(func() -> void: upgrade_pressed.emit(part))
		row.add_child(buy)
		page.add_child(row)
		_rows[part] = {"pips": pip_list, "price": price, "buy": buy}
	return page


func _build_views(ins: Vector4, m: float) -> void:
	var row := HBoxContainer.new()
	row.name = "Views"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_place(row, 0.5, 1.0, 0.5, 1.0, -460.0, -(ins.w + m + 56.0), 460.0, -(ins.w + m))
	for v: String in VIEWS:
		var b: Button = _button(VIEW_KEYS[v], Vector2(200.0, 56.0))
		var view: String = v
		b.pressed.connect(func() -> void: view_pressed.emit(view))
		row.add_child(b)
		_views[v] = b


# --- public API used by garage.gd -------------------------------------------

## Shows the car's data. state keys: name, cash, stats (dict), levels (dict part -> int),
## costs (dict part -> next cost, -1 at max), paint (Color), rim (Color), can_afford (dict part -> bool).
func refresh(state: Dictionary) -> void:
	_state = state.duplicate()
	_car_name.text = str(state.get("name", ""))
	_refresh_car(state)
	_cash_value.text = I18n.t("garage.money") % int(state.get("cash", 0))
	var stats: Dictionary = state.get("stats", {})
	for s: String in STATS:
		(_bars[s] as ProgressBar).value = float(stats.get(s, 0.0))
	var levels: Dictionary = state.get("levels", {})
	var costs: Dictionary = state.get("costs", {})
	var afford: Dictionary = state.get("can_afford", {})
	for part: String in PARTS:
		var row: Dictionary = _rows[part]
		var lvl: int = int(levels.get(part, 0))
		var pips: Array = row["pips"]
		for i: int in pips.size():
			(pips[i] as Panel).add_theme_stylebox_override("panel", _pip_on() if i < lvl else _pip_off())
		var price: Label = row["price"]
		var buy: Button = row["buy"]
		var cost: int = int(costs.get(part, -1))
		if cost < 0:
			price.text = I18n.t("garage.max")
			buy.disabled = true
			buy.text = I18n.t("garage.max")
		else:
			price.text = I18n.t("garage.money") % cost
			buy.disabled = false
			buy.text = I18n.t("garage.buy")
			price.modulate = Color.WHITE if bool(afford.get(part, true)) else MSTheme.tint(MSTheme.AMBER, 1.0)
	var paint: Color = state.get("paint", Color.WHITE)
	_sync_strips(paint)
	var rim: Color = state.get("rim", Color.WHITE)
	for i: int in _rim_buttons.size():
		_rim_buttons[i].disabled = false
		_rim_buttons[i].modulate = Color.WHITE if RIM_COLOURS[i].is_equal_approx(rim) else Color(1, 1, 1, 0.75)


func _refresh_car(state: Dictionary) -> void:
	var cls_key: String = "garage.class_" + str(state.get("class", "street"))
	_car_class.text = GarageText.t(cls_key)
	var many: bool = int(state.get("car_count", 1)) > 1
	_car_prev.disabled = not many
	_car_next.disabled = not many
	if bool(state.get("selected", true)):
		_car_action.text = GarageText.t("garage.car_selected")
		_car_action.disabled = true
	elif bool(state.get("owned", true)):
		_car_action.text = GarageText.t("garage.car_select")
		_car_action.disabled = false
	elif str(state.get("block", "")) == "rep":
		_car_action.text = GarageText.t("garage.car_rep") % int(state.get("rep_needed", 0))
		_car_action.disabled = true
	else:
		_car_action.text = GarageText.t("garage.car_buy") % int(state.get("price", 0))
		_car_action.disabled = false  ## short cash: pressing it shows the message


## Message line under the tabs. error true draws it in danger red.
func show_message(key: String, error: bool = false) -> void:
	_msg_key = key
	_msg_error = error
	_msg.text = GarageText.t(key) if not key.is_empty() else ""
	_msg.add_theme_color_override("font_color", MSTheme.DANGER if error else MSTheme.CYAN)
	_msg.modulate = Color.WHITE
	if _msg_tw != null:
		_msg_tw.kill()
	_msg_tw = create_tween()
	_msg_tw.tween_interval(MSG_HOLD_S)
	_msg_tw.tween_property(_msg, "modulate:a", 0.0, MSG_FADE_S)


## Gentle wiggle of a part's BUY button (not enough cash).
func shake_buy(part: String) -> void:
	if not _rows.has(part):
		return
	var buy: Button = (_rows[part] as Dictionary)["buy"]
	buy.pivot_offset = buy.size * 0.5
	if _shake_tw != null:
		_shake_tw.kill()
	_shake_tw = create_tween()
	_shake_tw.tween_property(buy, "rotation", SHAKE_RAD, SHAKE_S * 0.2)
	_shake_tw.tween_property(buy, "rotation", -SHAKE_RAD, SHAKE_S * 0.3)
	_shake_tw.tween_property(buy, "rotation", SHAKE_RAD * 0.5, SHAKE_S * 0.25)
	_shake_tw.tween_property(buy, "rotation", 0.0, SHAKE_S * 0.25)


func set_active_page(page: String) -> void:
	for k: String in PAGES:
		(_tabs[k] as Button).button_pressed = k == page
	_show_page(page)


func get_page_visible(page: String) -> bool:
	return _pages.has(page) and (_pages[page] as Control).visible


## Rebuilds every visible string in the current language.
func apply_language() -> void:
	for pair: Variant in _keyed:
		var node: Node = pair[0]
		var key: String = pair[1]
		if node is Label:
			(node as Label).text = I18n.t(key)
		elif node is Button:
			(node as Button).text = I18n.t(key)
	for s: String in STATS:
		(_stat_labels[s] as Label).text = I18n.t(STAT_KEYS[s])
	for v: String in VIEWS:
		(_views[v] as Button).text = I18n.t(VIEW_KEYS[v])
	if not _state.is_empty():
		refresh(_state)
	if not _msg_key.is_empty():
		_msg.text = GarageText.t(_msg_key)


func get_race_button() -> Button:
	return _race_btn


func get_back_button() -> Button:
	return _back_btn


func get_view_button(view: String) -> Button:
	return _views.get(view) as Button


func get_buy_button(part: String) -> Button:
	return (_rows[part] as Dictionary)["buy"] as Button


func get_swatch_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c: Node in (_pages["paint"] as Control).find_children("*", "GridContainer", false, false):
		for b: Node in c.get_children():
			out.append(b as Button)
	return out


func get_rim_buttons() -> Array[Button]:
	return _rim_buttons


func get_message() -> String:
	return _msg.text


# --- internals --------------------------------------------------------------

func _show_page(p: String) -> void:
	for k: String in PAGES:
		(_pages[k] as Control).visible = k == p
		var tab: Button = _tabs[k]
		tab.button_pressed = k == p
		var ink: Color = MSTheme.CYAN if k == p else MSTheme.TEXT
		tab.add_theme_color_override("font_color", ink)
		tab.add_theme_color_override("font_hover_color", ink)


func _opaque_box() -> StyleBoxFlat:
	return MSTheme.box(MSTheme.tint(MSTheme.PANEL_BG, 0.95), MSTheme.BORDER)


func _pip_on() -> StyleBoxFlat:
	return MSTheme.box(MSTheme.CYAN, MSTheme.CYAN, 0)


func _pip_off() -> StyleBoxFlat:
	return MSTheme.box(Color(1, 1, 1, 0.06), MSTheme.tint(MSTheme.MUTED, 0.6), 2)


## Rim swatch disc. Own texture per button (not MSTheme's static cache), so it is freed with the layer.
static func _disc(px: int, col: Color) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c: float = px * 0.5
	for y: int in px:
		for x: int in px:
			if Vector2(x + 0.5 - c, y + 0.5 - c).length() <= c:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _on_hue_changed(t: float) -> void:
	_hue = t
	_value_strip.base_hue = t
	_value_strip.queue_redraw()
	paint_previewed.emit(Color.from_hsv(_hue, STEP_SATURATION, _value))


func _on_value_changed(t: float) -> void:
	_value = VALUE_FLOOR + (1.0 - VALUE_FLOOR) * t
	paint_previewed.emit(Color.from_hsv(_hue, STEP_SATURATION, _value))


func _on_strip_released(_t: float) -> void:
	paint_committed.emit(Color.from_hsv(_hue, STEP_SATURATION, _value))


func _sync_strips(paint: Color) -> void:
	if _hue_strip == null:
		return
	var h: float = paint.h
	var v: float = paint.v
	_hue = h
	_value = clampf(v, VALUE_FLOOR, 1.0)
	_hue_strip.set_position_t(h)
	_value_strip.base_hue = h
	_value_strip.set_position_t((_value - VALUE_FLOOR) / (1.0 - VALUE_FLOOR))


func _swatch(c: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(SWATCH_W, SWATCH_H)
	b.focus_mode = Control.FOCUS_ALL
	var fill := StyleBoxFlat.new()
	fill.bg_color = c
	fill.set_border_width_all(2)
	fill.border_color = Color(1, 1, 1, 0.22)
	var hover := fill.duplicate() as StyleBoxFlat
	hover.border_color = MSTheme.CYAN
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(MSTheme.FOCUS_PX)
	focus.border_color = MSTheme.MAGENTA
	b.add_theme_stylebox_override("normal", fill)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", focus)
	b.pressed.connect(func() -> void: paint_committed.emit(c))
	return b


func _button(key: String, min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size if min_size != Vector2.ZERO else Vector2(MSTheme.BUTTON_MIN_W, MSTheme.BUTTON_MIN_H)
	b.text = I18n.t(key)
	b.focus_mode = Control.FOCUS_ALL
	_keyed.append([b, key])
	return b


func _keyed_label(key: String, kind: String, px: int, color: Color) -> Label:
	var l: Label = MSTheme.make_label(I18n.t(key), kind, px, color, false)
	_keyed.append([l, key])
	return l


func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob
	if c.get_parent() == null:
		add_child(c)
