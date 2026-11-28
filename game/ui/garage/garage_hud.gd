class_name GarageHud
extends Control
## 2D layer of the garage over the 3D view, in the style of a car-maker configurator. Top bar: BACK, camera presets, REP
## and CASH. Left: car name, class, ownership chip, four stat bars in real units (the upgrade gain in GO) and the BUY /
## SELECT button. Right: PAINT / RIMS / UPGRADES text tabs and RACE. Bottom: the collection strip. A car or upgrade
## purchase opens a confirmation first; CONFIRM then emits the signal the old button emitted. It only emits signals and
## shows what garage.gd hands it; GameState and CarMaterials are touched by garage.gd. Strings go through I18n.t.
## Layout rules: docs/design/GARAGE.md.

signal back_pressed
signal race_pressed
signal view_pressed(view: String)
signal paint_previewed(colour: Color)
signal paint_committed(colour: Color)
signal rim_pressed(colour: Color)
signal upgrade_pressed(part: String)
signal preview_requested(part: String)  ## a BUY row was touched or hovered: its gain shows on the stat bars
signal car_step_pressed(dir: int)  ## collection: -1 previous car, +1 next car (a card jumps by repeating this)
signal car_action_pressed  ## BUY, SELECT (after the confirmation for a purchase)

const PAINTS: Array[Color] = [
	Color("8E0F1E"), Color("0A1A5C"), Color("33363B"), Color("E8E9EE"), Color("0B0D12"), Color("1F5F7A"),
	Color("6B2D4A"), Color("FFC23D"), Color("0F4D2E"), Color("A9AFBA"), Color("4B1E8C"), Color("C4501B"),
]
const RIM_KEYS: PackedStringArray = [
	"garage.rim_gunmetal", "garage.rim_silver", "garage.rim_graphite", "garage.rim_chrome", "garage.rim_white", "garage.rim_bronze",
]
const RIM_COLOURS: Array[Color] = [
	Color(0.314, 0.333, 0.369), Color(0.75, 0.77, 0.8), Color(0.2, 0.21, 0.23), Color(0.92, 0.93, 0.95), Color(0.95, 0.95, 0.92), Color(0.55, 0.36, 0.18),
]
const PARTS: PackedStringArray = ["engine", "tires", "nitro", "weight"]
const PART_KEYS: Dictionary = {"engine": "garage.part_engine", "tires": "garage.part_tires", "nitro": "garage.part_nitro", "weight": "garage.part_weight"}
const PART_STAT: Dictionary = {"engine": "speed", "tires": "handling", "nitro": "nitro", "weight": "accel"}  ## the stat each part moves
const STATS: PackedStringArray = ["speed", "accel", "handling", "nitro"]
const STAT_KEYS: Dictionary = {"speed": "garage.stat_speed", "accel": "garage.stat_accel", "handling": "garage.stat_handling", "nitro": "garage.stat_nitro"}
const STAT_UNIT_KEYS: Dictionary = {"speed": "garage.unit_kmh", "accel": "garage.unit_ms2", "handling": "garage.unit_grip", "nitro": "garage.unit_s"}
const VIEWS: PackedStringArray = ["front", "side", "rear34", "overview"]
const VIEW_KEYS: Dictionary = {"front": "garage.view_front", "side": "garage.view_side", "rear34": "garage.view_rear", "overview": "garage.view_overview"}
const PAGES: PackedStringArray = ["paint", "rims", "upgrades"]
const PAGE_KEYS: Dictionary = {"paint": "garage.tab_paint", "rims": "garage.tab_rims", "upgrades": "garage.tab_upgrades"}
const MARGIN_PX: float = 40.0
const TOP_BAR_H: float = 64.0
const LEFT_W: float = 440.0  ## identity and stats column, before MSTheme.px
const PANEL_W: float = 560.0  ## right panel, before MSTheme.px
const PANEL_GAP_PX: float = 24.0  ## gap between the collection strip and the right panel
const SWATCH_PX: float = 64.0
const PIP_PX: float = 16.0
const PIP_GAP_PX: float = 6.0
const TOUCH_H: float = 88.0  ## BUY and car action buttons: touch targets at 1080 px (the test checks this value)
const CARD_W: float = 232.0  ## collection card, before MSTheme.px
const CARD_H: float = 124.0
const CAPTION_H: float = 22.0
const BAR_PX: float = 6.0  ## stat bar height
const GRADIENT_H: float = 28.0  ## hue and value strips
const STEP_SATURATION: float = 0.85
const VALUE_FLOOR: float = 0.1
const SHAKE_S: float = 0.36
const SHAKE_RAD: float = 0.035
const MSG_HOLD_S: float = 1.6
const MSG_FADE_S: float = 0.4

var _keyed: Array = []  ## [node, i18n key, prefix] for static text
var _state: Dictionary = {}
var _msg_key: String = ""
var _msg_error: bool = false
var _car_name: Label
var _car_class: Label
var _chip_box: PanelContainer
var _chip: Label
var _hint: Label
var _cash_caption: Label
var _cash_value: Label
var _rep_value: Label
var _stat_labels: Dictionary = {}
var _stat_values: Dictionary = {}
var _stat_deltas: Dictionary = {}
var _stat_units: Dictionary = {}
var _bars: Dictionary = {}
var _ghosts: Dictionary = {}  ## stat -> ProgressBar under the live bar; its fill is the gain of the previewed upgrade
var _tabs: Dictionary = {}
var _pages: Dictionary = {}
var _swatch_buttons: Array[Button] = []
var _rim_buttons: Array[Button] = []
var _rows: Dictionary = {}
var _views: Dictionary = {}
var _cards: Dictionary = {}  ## car id -> {button, state}
var _strip_ids: Array[String] = []
var _strip_row: HBoxContainer
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
var _confirm: Control
var _confirm_item: Label
var _confirm_price: Label
var _confirm_balance: Label
var _confirm_ok: Button
var _confirm_cancel: Button
var _pending: Dictionary = {}  ## the purchase waiting for CONFIRM: kind car or upgrade, part, item, cost, balance
var _return_focus: Control = null
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
		custom_minimum_size = Vector2(0.0, GarageHud.GRADIENT_H)

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
		draw_rect(Rect2(mx - 3.0, -2.0, 6.0, size.y + 4.0), MSTheme.PEARL, false, 2.0)

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
	_build_top_bar(ins)
	_build_identity(ins)
	_build_panel(ins)
	_build_strip(ins)
	_build_confirm()
	apply_language()


# --- layout ------------------------------------------------------------------

func _bar_h() -> float:
	return maxf(TOP_BAR_H, MSTheme.button_h())


func _touch_h() -> float:
	return maxf(TOUCH_H, MSTheme.button_h())


func _top_y(ins: Vector4) -> float:
	return ins.y + MARGIN_PX


func _content_y(ins: Vector4) -> float:
	return ins.y + MARGIN_PX + _bar_h() + MARGIN_PX


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _build_top_bar(ins: Vector4) -> void:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	bar.add_theme_constant_override("separation", MSTheme.GRID_PX * 3)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top: float = _top_y(ins)
	_place(bar, 0.0, 0.0, 1.0, 0.0, ins.x + MARGIN_PX, top, -(ins.z + MARGIN_PX), top + _bar_h())

	_back_btn = _button("common.back", Vector2(MSTheme.px(200.0), _bar_h()), "< ")
	_back_btn.name = "Back"
	_back_btn.theme_type_variation = &"GhostButton"
	_back_btn.pressed.connect(func() -> void: back_pressed.emit())
	_back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_back_btn)
	bar.add_child(_spacer())

	var views := HBoxContainer.new()
	views.name = "Views"
	views.add_theme_constant_override("separation", MSTheme.GRID_PX)
	views.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for v: String in VIEWS:
		var b: Button = _button(VIEW_KEYS[v], Vector2(0.0, _bar_h()))
		b.theme_type_variation = &"GhostButton"
		var view: String = v
		b.pressed.connect(func() -> void: view_pressed.emit(view))
		views.add_child(b)
		_views[v] = b
	bar.add_child(_plate(views, "ViewsPlate"))
	bar.add_child(_spacer())

	var money := HBoxContainer.new()
	money.name = "Money"
	money.add_theme_constant_override("separation", MSTheme.GRID_PX * 3)
	money.alignment = BoxContainer.ALIGNMENT_END
	var rep_box := VBoxContainer.new()
	rep_box.name = "Rep"
	rep_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rep_cap: Label = _keyed_label("garage.rep", "tracked", MSTheme.px(16), MSTheme.STEEL)
	rep_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rep_box.add_child(rep_cap)
	_rep_value = MSTheme.make_label("0", "digits", MSTheme.px(36), MSTheme.PEARL)
	_rep_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rep_box.add_child(_rep_value)
	money.add_child(rep_box)

	var cash := VBoxContainer.new()
	cash.name = "Cash"
	cash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cash_caption = _keyed_label("garage.cash", "tracked", MSTheme.px(16), MSTheme.STEEL)
	_cash_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash.add_child(_cash_caption)
	_cash_value = MSTheme.make_label("0", "digits", MSTheme.px(36), MSTheme.GOLD)
	_cash_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash.add_child(_cash_value)
	money.add_child(cash)
	bar.add_child(_plate(money, "MoneyPlate"))


## Dark plate behind top-bar text: the room's ceiling lights wash out bare labels.
func _plate(inner: Control, plate_name: String) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.name = plate_name
	plate.add_theme_stylebox_override("panel", MSTheme.box(MSTheme.PLATE_BG, MSTheme.BORDER))
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.add_child(inner)
	return plate


func _build_identity(ins: Vector4) -> void:
	var col := VBoxContainer.new()
	col.name = "CarHead"
	col.add_theme_constant_override("separation", MSTheme.GRID_PX)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top: float = _content_y(ins)
	_place(col, 0.0, 0.0, 0.0, 0.0, ins.x + MARGIN_PX, top, ins.x + MARGIN_PX + MSTheme.px(LEFT_W), top)

	_car_name = MSTheme.make_label("", "display", MSTheme.px(64), MSTheme.PEARL)
	_car_name.clip_text = true
	col.add_child(_car_name)
	_car_class = MSTheme.make_label("", "tracked", MSTheme.px(20), MSTheme.TITANIUM)
	col.add_child(_car_class)
	_chip_box = PanelContainer.new()
	_chip_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_chip = MSTheme.make_label("", "tracked", MSTheme.px(18), MSTheme.PEARL)
	_chip_box.add_child(_chip)
	col.add_child(_chip_box)
	_hint = _keyed_label("garage.hint", "tracked", MSTheme.px(16), MSTheme.STEEL)
	col.add_child(_hint)

	var stats := VBoxContainer.new()
	stats.name = "Stats"
	stats.add_theme_constant_override("separation", MSTheme.GRID_PX * 2)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stats)
	_build_stats(stats)

	_car_action = Button.new()
	_car_action.name = "CarAction"
	_car_action.custom_minimum_size = Vector2(MSTheme.px(LEFT_W), _touch_h())
	_car_action.focus_mode = Control.FOCUS_ALL
	_car_action.pressed.connect(_on_car_action)
	col.add_child(_car_action)


func _build_stats(box: VBoxContainer) -> void:
	for s: String in STATS:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", MSTheme.GRID_PX / 2)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", MSTheme.GRID_PX)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lab: Label = _keyed_label(STAT_KEYS[s], "tracked", MSTheme.px(18), MSTheme.TITANIUM)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(lab)
		var delta := MSTheme.make_label("", "digits", MSTheme.px(20), MSTheme.GO)
		delta.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(delta)
		var value := MSTheme.make_label("", "digits", MSTheme.px(30), MSTheme.PEARL)
		value.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(value)
		var unit: Label = _keyed_label(STAT_UNIT_KEYS[s], "tracked", MSTheme.px(16), MSTheme.TITANIUM)
		unit.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(unit)
		row.add_child(head)
		# the live bar sits on top of a ghost bar that carries the track and, in preview, the gain
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(0.0, BAR_PX)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ghost := ProgressBar.new()
		ghost.show_percentage = false
		ghost.max_value = 1.0
		ghost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.add_theme_stylebox_override("background", _track_box())
		holder.add_child(ghost)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
		bar.add_theme_stylebox_override("fill", _fill_box(MSTheme.PEARL))
		holder.add_child(bar)
		row.add_child(holder)
		box.add_child(row)
		_stat_labels[s] = lab
		_stat_values[s] = value
		_stat_deltas[s] = delta
		_stat_units[s] = unit
		_ghosts[s] = ghost
		_bars[s] = bar


## Collection strip along the bottom, left of the right panel: [<] cards [>]. A card jumps to its car.
func _build_strip(ins: Vector4) -> void:
	var wrap := VBoxContainer.new()
	wrap.name = "Collection"
	wrap.add_theme_constant_override("separation", MSTheme.GRID_PX)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bottom: float = -(ins.w + MARGIN_PX)
	var strip_h: float = MSTheme.px(CARD_H) + CAPTION_H + MSTheme.GRID_PX
	_place(wrap, 0.0, 1.0, 1.0, 1.0, ins.x + MARGIN_PX, bottom - strip_h, -(ins.z + MARGIN_PX + MSTheme.px(PANEL_W) + MSTheme.px(PANEL_GAP_PX)), bottom)
	wrap.add_child(_keyed_label("garage.collection", "tracked", MSTheme.px(16), MSTheme.TITANIUM))

	var row := HBoxContainer.new()
	row.name = "Carousel"
	row.add_theme_constant_override("separation", MSTheme.GRID_PX)
	wrap.add_child(row)
	_car_prev = _arrow("<", "CarPrev", -1)
	row.add_child(_car_prev)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_strip_row = HBoxContainer.new()
	_strip_row.name = "Cards"
	_strip_row.add_theme_constant_override("separation", MSTheme.GRID_PX)
	scroll.add_child(_strip_row)
	for id: String in CarCatalog.available_ids():
		_strip_card(id)
	_car_next = _arrow(">", "CarNext", 1)
	row.add_child(_car_next)


func _arrow(txt: String, node_name: String, dir: int) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = txt
	b.custom_minimum_size = Vector2(MSTheme.px(72.0), MSTheme.px(CARD_H))
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void: car_step_pressed.emit(dir))
	return b


func _strip_card(id: String) -> void:
	var spec: CarSpec = _spec_of(id)
	var b := Button.new()
	b.name = "Card_" + id
	b.custom_minimum_size = Vector2(MSTheme.px(CARD_W), MSTheme.px(CARD_H))
	b.focus_mode = Control.FOCUS_ALL
	var inner := VBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 2)
	inner.offset_left = MSTheme.GRID_PX
	inner.offset_right = -MSTheme.GRID_PX
	var nm: String = spec.display_name if spec != null else id
	var name_l := MSTheme.make_label(nm.to_upper(), "display", MSTheme.px(26), MSTheme.PEARL)
	name_l.clip_text = true
	inner.add_child(name_l)
	inner.add_child(MSTheme.make_label(GarageText.t("garage.class_" + CarCatalog.class_id(id)), "tracked", MSTheme.px(14), MSTheme.STEEL))
	var st := MSTheme.make_label("", "digits", MSTheme.px(18), MSTheme.PEARL)
	inner.add_child(st)
	b.add_child(inner)
	b.pressed.connect(_jump_to.bind(id))
	_strip_row.add_child(b)
	_strip_ids.append(id)
	_cards[id] = {"button": b, "state": st}


func _build_panel(ins: Vector4) -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", MSTheme.box(MSTheme.tint(MSTheme.GRAPHITE_2, 0.94), MSTheme.BORDER))
	var top: float = _content_y(ins)
	_place(panel, 1.0, 0.0, 1.0, 0.0, -(ins.z + MARGIN_PX + MSTheme.px(PANEL_W)), top, -(ins.z + MARGIN_PX), top)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MSTheme.GRID_PX * 2)
	panel.add_child(col)

	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", MSTheme.GRID_PX * 3)
	col.add_child(tabs)
	for p: String in PAGES:
		var b: Button = _tab_button(PAGE_KEYS[p])
		b.pressed.connect(_show_page.bind(p))
		tabs.add_child(b)
		_tabs[p] = b

	var pages := VBoxContainer.new()
	col.add_child(pages)
	_pages["paint"] = _build_paint_page()
	_pages["rims"] = _build_rims_page()
	_pages["upgrades"] = _build_upgrades_page()
	for p: String in PAGES:
		pages.add_child(_pages[p])
	_show_page("paint")

	_msg = MSTheme.make_label("", "tracked", MSTheme.px(20), MSTheme.TITANIUM)
	_msg.custom_minimum_size = Vector2(0.0, MSTheme.px(30.0))
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_msg)

	_race_btn = _button("garage.race", Vector2(MSTheme.px(PANEL_W), maxf(MSTheme.px(80.0), MSTheme.button_h())))
	_race_btn.name = "Race"
	_race_btn.theme_type_variation = &"PrimaryButton"  ## the one primary action on the screen
	_race_btn.pressed.connect(func() -> void: race_pressed.emit())
	col.add_child(_race_btn)


## Text tab: no box. The active tab gets a 3 px red underline and pearl text; hover does not look selected.
func _tab_button(key: String) -> Button:
	var b: Button = _button(key, Vector2(0.0, MSTheme.px(56.0)))
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.theme_type_variation = &"GhostButton"
	var none := StyleBoxEmpty.new()
	var underline := StyleBoxFlat.new()
	underline.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	underline.border_width_bottom = 3
	underline.border_color = MSTheme.RED
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.set_border_width_all(MSTheme.FOCUS_PX)
	ring.border_color = MSTheme.PEARL
	b.add_theme_stylebox_override("normal", none)
	b.add_theme_stylebox_override("hover", none)
	b.add_theme_stylebox_override("pressed", underline)
	b.add_theme_stylebox_override("hover_pressed", underline)
	b.add_theme_stylebox_override("focus", ring)
	b.add_theme_font_override("font", MSTheme.font("bold"))
	b.add_theme_font_size_override("font_size", MSTheme.px(22))
	return b


func _build_paint_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", MSTheme.GRID_PX * 2)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", MSTheme.GRID_PX)
	grid.add_theme_constant_override("v_separation", MSTheme.GRID_PX)
	for c: Color in PAINTS:
		var b: Button = _swatch(c)
		grid.add_child(b)
		_swatch_buttons.append(b)
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
	page.add_child(_keyed_label("garage.hue", "tracked", MSTheme.px(16), MSTheme.STEEL))
	return page


func _build_rims_page() -> Control:
	var page := GridContainer.new()
	page.columns = 2
	page.add_theme_constant_override("h_separation", MSTheme.GRID_PX * 2)
	page.add_theme_constant_override("v_separation", MSTheme.GRID_PX * 2)
	for i: int in RIM_KEYS.size():
		var b: Button = _button(RIM_KEYS[i], Vector2(MSTheme.px(228.0), _touch_h() * 0.75))
		b.icon = _disc(int(MSTheme.ICON_PX * 1.6), RIM_COLOURS[i])
		b.expand_icon = false
		var col: Color = RIM_COLOURS[i]
		b.pressed.connect(func() -> void: rim_pressed.emit(col))
		page.add_child(b)
		_rim_buttons.append(b)
	return page


func _build_upgrades_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", MSTheme.GRID_PX * 2)
	for part: String in PARTS:
		page.add_child(_upgrade_row(part))
	return page


## One part per row: name and the gain on its stat, five level pips (red = owned), cost in GOLD, BUY.
func _upgrade_row(part: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MSTheme.GRID_PX)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size = Vector2(0.0, _touch_h())
	var name_col := VBoxContainer.new()
	name_col.custom_minimum_size = Vector2(MSTheme.px(150.0), 0.0)
	name_col.alignment = BoxContainer.ALIGNMENT_CENTER
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(_keyed_label(PART_KEYS[part], "bold", MSTheme.px(20), MSTheme.PEARL))
	var delta := MSTheme.make_label("", "digits", MSTheme.px(16), MSTheme.GO)
	name_col.add_child(delta)
	row.add_child(name_col)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", int(PIP_GAP_PX))
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	var pip_list: Array = []
	for i: int in GameState.MAX_UPGRADE_LEVEL:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(MSTheme.px(PIP_PX), MSTheme.px(PIP_PX))
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
		pip_list.append(pip)
	row.add_child(pips)
	var price := MSTheme.make_label("", "digits", MSTheme.px(22), MSTheme.GOLD)
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price)
	var buy: Button = _button("garage.buy", Vector2(MSTheme.px(124.0), _touch_h()))
	buy.pressed.connect(_on_buy_pressed.bind(part))
	buy.mouse_entered.connect(func() -> void: preview_requested.emit(part))
	buy.button_down.connect(func() -> void: preview_requested.emit(part))
	buy.mouse_exited.connect(func() -> void: preview_requested.emit(""))  ## the gain leaves with the pointer
	row.add_child(buy)
	_rows[part] = {"pips": pip_list, "price": price, "buy": buy, "delta": delta}
	return row


## Purchase confirmation: a modal over the layer. CANCEL has focus when it opens; Tab and the arrows stay inside it.
func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.name = "Confirm"
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.visible = false
	add_child(_confirm)
	var shade := ColorRect.new()
	shade.color = MSTheme.tint(MSTheme.GRAPHITE, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.add_child(shade)
	var card := PanelContainer.new()
	card.name = "ConfirmCard"
	card.add_theme_stylebox_override("panel", MSTheme.box(MSTheme.GRAPHITE_2, MSTheme.tint(MSTheme.TITANIUM, 0.3), 1))
	card.custom_minimum_size = Vector2(MSTheme.px(600.0), 0.0)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_confirm.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MSTheme.GRID_PX * 2)
	card.add_child(col)
	col.add_child(_keyed_label("garage.confirm_title", "tracked", MSTheme.px(18), MSTheme.STEEL))
	_confirm_item = MSTheme.make_label("", "display", MSTheme.px(44), MSTheme.PEARL)
	col.add_child(_confirm_item)
	var price_row := HBoxContainer.new()
	price_row.add_child(_keyed_label("garage.price", "tracked", MSTheme.px(18), MSTheme.STEEL))
	price_row.add_child(_spacer())
	_confirm_price = MSTheme.make_label("", "digits", MSTheme.px(32), MSTheme.GOLD)
	price_row.add_child(_confirm_price)
	col.add_child(price_row)
	var balance_row := HBoxContainer.new()
	balance_row.add_child(_keyed_label("garage.confirm_balance", "tracked", MSTheme.px(18), MSTheme.STEEL))
	balance_row.add_child(_spacer())
	_confirm_balance = MSTheme.make_label("", "digits", MSTheme.px(32), MSTheme.PEARL)
	balance_row.add_child(_confirm_balance)
	col.add_child(balance_row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", MSTheme.GRID_PX * 2)
	col.add_child(buttons)
	_confirm_cancel = _button("garage.confirm_cancel", Vector2(MSTheme.px(220.0), _touch_h()))
	_confirm_cancel.name = "ConfirmCancel"
	_confirm_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_cancel.pressed.connect(_close_confirm)
	buttons.add_child(_confirm_cancel)
	_confirm_ok = _button("garage.confirm_ok", Vector2(MSTheme.px(260.0), _touch_h()))
	_confirm_ok.name = "ConfirmOk"
	_confirm_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_ok.theme_type_variation = &"PrimaryButton"
	_confirm_ok.pressed.connect(_on_confirm_ok)
	buttons.add_child(_confirm_ok)
	# keep focus inside the modal: each button's neighbours are the other button
	for b: Button in [_confirm_cancel, _confirm_ok]:
		var other: Button = _confirm_ok if b == _confirm_cancel else _confirm_cancel
		b.focus_next = b.get_path_to(other)
		b.focus_previous = b.get_path_to(other)
		b.focus_neighbor_left = b.get_path_to(other)
		b.focus_neighbor_right = b.get_path_to(other)


# --- purchase confirmation -----------------------------------------------------

## Car or upgrade waiting for CONFIRM. Nothing is spent here.
func _open_confirm(kind: String, part: String) -> void:
	var item: String = str(_state.get("name", ""))
	var cost: int = int(_state.get("price", 0))
	if kind == "upgrade":
		var lvl: int = int((_state.get("levels", {}) as Dictionary).get(part, 0)) + 1
		item = "%s  %s" % [I18n.t(PART_KEYS[part]), I18n.t("garage.confirm_level") % lvl]
		cost = int((_state.get("costs", {}) as Dictionary).get(part, 0))
	var cash: int = int(_state.get("cash", GameState.get_cash()))
	_pending = {"kind": kind, "part": part, "item": item, "cost": cost, "balance": cash - cost}
	_confirm_item.text = item
	_confirm_price.text = I18n.t("garage.money") % cost
	_confirm_balance.text = I18n.t("garage.money") % (cash - cost)
	_return_focus = get_viewport().gui_get_focus_owner()
	_confirm.visible = true
	_confirm_cancel.grab_focus()


func _close_confirm() -> void:
	_confirm.visible = false
	_pending = {}
	if _return_focus != null and is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	_return_focus = null


func _on_confirm_ok() -> void:
	var p: Dictionary = _pending.duplicate()
	_close_confirm()
	if str(p.get("kind", "")) == "car":
		car_action_pressed.emit()
	elif str(p.get("kind", "")) == "upgrade":
		upgrade_pressed.emit(str(p["part"]))


## Escape and controller back cancel an open confirmation.
func _unhandled_input(event: InputEvent) -> void:
	if confirm_open() and event.is_action_pressed("ui_cancel"):
		_close_confirm()
		get_viewport().set_input_as_handled()


func confirm_open() -> bool:
	return _confirm != null and _confirm.visible


## {kind, part, item, cost, balance} of the open confirmation; empty when none is open.
func confirm_info() -> Dictionary:
	return _pending.duplicate()


## Buying a car: asks first when it is unowned and affordable, otherwise the garage decides (and shows the message).
func _on_car_action() -> void:
	if not bool(_state.get("owned", true)) and str(_state.get("block", "")) == "":
		_open_confirm("car", "")
	else:
		car_action_pressed.emit()


## An upgrade BUY: asks first when the cash covers it; otherwise the garage shows the short-cash message and shakes.
func _on_buy_pressed(part: String) -> void:
	var afford: bool = bool((_state.get("can_afford", {}) as Dictionary).get(part, false))
	if afford:
		_open_confirm("upgrade", part)
	else:
		upgrade_pressed.emit(part)


## Jumps to a card's car by repeating the existing one-step signal in the shorter direction.
func _jump_to(id: String) -> void:
	var ids: Array[String] = CarCatalog.available_ids()
	var cur: int = ids.find(str(_state.get("car_id", "")))
	var tgt: int = ids.find(id)
	if cur < 0 or tgt < 0 or cur == tgt:
		return
	var n: int = ids.size()
	var fwd: int = posmod(tgt - cur, n)
	var dir: int = 1 if fwd <= n - fwd else -1
	var steps: int = fwd if dir == 1 else n - fwd
	for i: int in steps:
		car_step_pressed.emit(dir)


# --- public API used by garage.gd -------------------------------------------

## Shows the car's data. state keys: name, cash, stats (dict), levels (dict part -> int),
## costs (dict part -> next cost, -1 at max), paint (Color), rim (Color), can_afford (dict part -> bool), car_id,
## class, owned, selected, price, block, rep_needed, car_count, preview (dict stat -> 0..1), and rep when given.
func refresh(state: Dictionary) -> void:
	_state = state.duplicate()
	_car_name.text = str(state.get("name", ""))
	_refresh_car(state)
	_cash_value.text = I18n.t("garage.money") % int(state.get("cash", 0))
	_rep_value.text = str(int(state.get("rep", GameState.get_rep())))
	_refresh_stats(state)
	_refresh_parts(state)
	_refresh_strip(state)
	var paint: Color = state.get("paint", Color.WHITE)
	_sync_strips(paint)
	_sync_swatches(paint)
	var rim: Color = state.get("rim", Color.WHITE)
	for i: int in _rim_buttons.size():
		_rim_buttons[i].disabled = false
		_rim_buttons[i].modulate = Color.WHITE if RIM_COLOURS[i].is_equal_approx(rim) else Color(1, 1, 1, 0.6)


## Message line under the tabs. error true draws it in danger red.
func show_message(key: String, error: bool = false) -> void:
	_msg_key = key
	_msg_error = error
	_msg.text = GarageText.t(key) if not key.is_empty() else ""
	_msg.add_theme_color_override("font_color", MSTheme.DANGER if error else MSTheme.TITANIUM)
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
	_show_page(page)


func get_page_visible(page: String) -> bool:
	return _pages.has(page) and (_pages[page] as Control).visible


## Rebuilds every visible string in the current language.
func apply_language() -> void:
	for pair: Variant in _keyed:
		var node: Node = pair[0]
		var key: String = pair[1]
		var prefix: String = str(pair[2])
		if node is Label:
			(node as Label).text = I18n.t(key)
		elif node is Button:
			(node as Button).text = prefix + I18n.t(key)
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


func get_tab_button(page: String) -> Button:
	return _tabs.get(page) as Button


func get_swatch_buttons() -> Array[Button]:
	return _swatch_buttons


func get_rim_buttons() -> Array[Button]:
	return _rim_buttons


## Car ids on the collection strip, in catalog order.
func get_strip_ids() -> Array[String]:
	return _strip_ids.duplicate()


func get_strip_button(id: String) -> Button:
	return (_cards[id] as Dictionary)["button"] as Button if _cards.has(id) else null


func get_message() -> String:
	return _msg.text


# --- internals --------------------------------------------------------------

func _refresh_car(state: Dictionary) -> void:
	var id: String = str(state.get("car_id", ""))
	_car_class.text = GarageText.t("garage.class_" + str(state.get("class", "street")))
	var status: Array = _status(id, false)
	var ink: Color = status[1] as Color
	_chip.text = str(status[0])
	_chip.add_theme_color_override("font_color", ink)
	_chip_box.add_theme_stylebox_override("panel", MSTheme.box(MSTheme.GRAPHITE_2, ink, 1))
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


## Stat bars and the numbers beside them. The bar is the 0..1 value; the number is the real unit (see GarageStats).
func _refresh_stats(state: Dictionary) -> void:
	var stats: Dictionary = state.get("stats", {})
	var preview: Dictionary = state.get("preview", {})
	var raw: Dictionary = _raw_values(state)
	for s: String in STATS:
		var now: float = float(stats.get(s, 0.0))
		(_bars[s] as ProgressBar).value = now
		var ghost: ProgressBar = _ghosts[s]
		var gained: bool = preview.has(s)
		ghost.value = float(preview.get(s, now))
		ghost.add_theme_stylebox_override("fill", _gain_fill(gained))
		var full: float = float(GarageStats.FULL[s])
		(_stat_values[s] as Label).text = _fmt(s, float(raw.get(s, now * full)))
		var d: Label = _stat_deltas[s]
		d.text = ("+" + _fmt(s, (float(preview[s]) - now) * full)) if gained else ""


func _refresh_parts(state: Dictionary) -> void:
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
		var delta: Label = row["delta"]
		var cost: int = int(costs.get(part, -1))
		if cost < 0:
			price.text = I18n.t("garage.max")
			buy.disabled = true
			buy.text = I18n.t("garage.max")
			delta.text = ""
		else:
			price.text = I18n.t("garage.money") % cost
			buy.disabled = false
			buy.text = I18n.t("garage.buy")
			price.add_theme_color_override("font_color", MSTheme.GOLD if bool(afford.get(part, true)) else MSTheme.DANGER)
			delta.text = _part_delta(part, state)


## Collection cards: the current car has the red top edge; state is SELECTED, OWNED, LOCKED or the price.
func _refresh_strip(state: Dictionary) -> void:
	var cur: String = str(state.get("car_id", ""))
	for id: String in _strip_ids:
		var c: Dictionary = _cards[id]
		var b: Button = c["button"]
		var current: bool = id == cur
		b.add_theme_stylebox_override("normal", _card_style(current, false))
		b.add_theme_stylebox_override("hover", _card_style(current, true))
		b.add_theme_stylebox_override("pressed", _card_style(current, true))
		var status: Array = _status(id, true)
		var lab: Label = c["state"]
		lab.text = str(status[0])
		lab.add_theme_color_override("font_color", status[1] as Color)


## [text, colour] for the chip (long: LOCKED with the rep needed) or a card (short: LOCKED). Real data only.
func _status(id: String, short: bool) -> Array:
	if GameState.get_selected_car() == id:
		return [I18n.t("garage.chip_selected"), MSTheme.PEARL]
	if GameState.has_car(id):
		return [I18n.t("garage.chip_owned"), MSTheme.GO]
	if CarCatalog.buy_block(id) == "rep":
		if short:
			return [I18n.t("garage.chip_locked"), MSTheme.STEEL]
		return [I18n.t("garage.chip_rep") % CarCatalog.rep_needed(id), MSTheme.STEEL]
	return [I18n.t("garage.money") % CarCatalog.price(id), MSTheme.GOLD]


## "+4 KM/H": what one more level of the part adds to its stat, in the stat's unit. "" without a spec.
func _part_delta(part: String, state: Dictionary) -> String:
	var spec: CarSpec = _spec_of(str(state.get("car_id", "")))
	if spec == null:
		return ""
	var levels: Dictionary = state.get("levels", {})
	var stat: String = PART_STAT[part]
	var now: Dictionary = GarageStats.compute(spec, levels)
	var nxt: Dictionary = GarageStats.preview_next(spec, levels, part)
	var gain: float = (float(nxt[stat]) - float(now[stat])) * float(GarageStats.FULL[stat])
	return "+%s %s" % [_fmt(stat, gain), I18n.t(STAT_UNIT_KEYS[stat])]


func _raw_values(state: Dictionary) -> Dictionary:
	var spec: CarSpec = _spec_of(str(state.get("car_id", "")))
	return GarageStats.values(spec, state.get("levels", {})) if spec != null else {}


func _spec_of(id: String) -> CarSpec:
	if not CarCatalog.is_available(id):
		return null
	return load(CarCatalog.spec_path(id)) as CarSpec


## Number in the stat's unit: km/h whole, the rest one decimal (two for grip). Turkish uses a decimal comma.
func _fmt(s: String, v: float) -> String:
	var txt: String = "%d" % roundi(v)
	if s == "handling":
		txt = "%.2f" % v
	elif s != "speed":
		txt = "%.1f" % v
	if Settings.language == "tr":
		txt = txt.replace(".", ",")
	return txt


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


## The chip matching the paint is ringed in pearl (2 px); the others get a hairline.
func _sync_swatches(paint: Color) -> void:
	for i: int in _swatch_buttons.size():
		var c: Color = PAINTS[i]
		var on: bool = c.is_equal_approx(paint)
		var b: Button = _swatch_buttons[i]
		b.add_theme_stylebox_override("normal", MSTheme.box(c, MSTheme.PEARL if on else MSTheme.tint(MSTheme.TITANIUM, 0.25), 2 if on else 1))
		b.add_theme_stylebox_override("hover", MSTheme.box(c, MSTheme.RED, 2))
		b.add_theme_stylebox_override("pressed", MSTheme.box(c, MSTheme.RED, 2))


func _card_style(current: bool, hover: bool) -> StyleBoxFlat:
	var bg: Color = MSTheme.GRAPHITE_3 if hover else MSTheme.GRAPHITE_2
	var sb: StyleBoxFlat = MSTheme.card(bg, MSTheme.tint(MSTheme.TITANIUM, 0.18), 1)
	if current:
		sb.set_border_width_all(0)
		sb.border_width_top = MSTheme.px(3.0)
		sb.border_color = MSTheme.RED
	return sb


## Bar styles are plain boxes: MSTheme.box() adds 12 px vertical content margins, which would make a 6 px bar 30 px tall.
func _track_box() -> StyleBoxFlat:
	return _plain(MSTheme.tint(MSTheme.TITANIUM, 0.14))


func _fill_box(c: Color) -> StyleBoxFlat:
	return _plain(c)


func _plain(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_content_margin_all(0.0)
	return sb


## Gain fill for the upgrade preview, an empty style otherwise so the ghost adds nothing to the live bar.
func _gain_fill(on: bool) -> StyleBox:
	if not on:
		return StyleBoxEmpty.new()
	return _fill_box(MSTheme.GO)


func _pip_on() -> StyleBoxFlat:
	return MSTheme.card(MSTheme.RED, MSTheme.RED, 0)


func _pip_off() -> StyleBoxFlat:
	return MSTheme.card(MSTheme.GRAPHITE_3, MSTheme.tint(MSTheme.TITANIUM, 0.3), 1)


func _show_page(p: String) -> void:
	for k: String in PAGES:
		(_pages[k] as Control).visible = k == p
		var tab: Button = _tabs[k]
		tab.button_pressed = k == p
		var ink: Color = MSTheme.PEARL if k == p else MSTheme.TITANIUM
		tab.add_theme_color_override("font_color", ink)
		tab.add_theme_color_override("font_hover_color", ink)
		tab.add_theme_color_override("font_pressed_color", MSTheme.PEARL)


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


func _swatch(c: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(MSTheme.px(SWATCH_PX), MSTheme.px(SWATCH_PX))
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void: paint_committed.emit(c))
	return b


func _button(key: String, min_size: Vector2 = Vector2.ZERO, prefix: String = "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size if min_size != Vector2.ZERO else Vector2(MSTheme.BUTTON_MIN_W, MSTheme.BUTTON_MIN_H)
	b.text = prefix + I18n.t(key)
	b.focus_mode = Control.FOCUS_ALL
	_keyed.append([b, key, prefix])
	return b


func _keyed_label(key: String, kind: String, px: int, color: Color) -> Label:
	var l: Label = MSTheme.make_label(I18n.t(key), kind, px, color, false)
	_keyed.append([l, key, ""])
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
