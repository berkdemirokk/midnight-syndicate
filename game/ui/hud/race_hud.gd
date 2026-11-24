class_name RaceHUD
extends CanvasLayer
## Race HUD. Reads ArcadeCar and RaceManager state and reacts to race signals; it never drives race logic.
## Every displayed string is cached in _shown, so a label is rewritten only when its value changes.
## get_readout() returns that cache for tests and captures.

const GAUGE_W: float = 320.0
const GAUGE_H: float = 264.0
const GAUGE_CENTRE_FRAC: float = 0.6  ## horizontal centre of the speedometer, fraction of the safe frame
const GAUGE_CENTRE_Y: float = 120.0  ## passed to SpeedGauge.centre_y_px in _build_speedo
const GAUGE_GEAR_Y: float = 224.0
const GAUGE_GEAR_W: float = 56.0
const GAUGE_GEAR_H: float = 34.0
const SPEED_H: float = 150.0  ## about one line of the 112 px digits, centred on the arc centre
const UNIT_Y: float = 184.0
const NITRO_W: float = 320.0
const NITRO_H: float = 20.0
const NITRO_LEFT_FRAC: float = 0.3
const NITRO_BLOCK_H: float = 56.0
const MINIMAP_PX: float = 240.0
const CENTRE_BOX_W: float = 480.0
const CENTRE_TOP_PX: float = 120.0
const POS_PX: int = 72
const POS_SUFFIX_PX: int = 24
const POS_TOTAL_PX: int = 28
const SPEED_PX: int = 112
const UNIT_PX: int = 20
const LAP_PX: int = 40
const SMALL_PX: int = 18
const TIME_PX: int = 24
const NITRO_LABEL_PX: int = 18
const COUNTDOWN_PX: int = 200
const DRIFT_PX: int = 40
const BANK_PX: int = 28
const WRONG_PX: int = 48
const FINISH_PX: int = 28
const COUNTDOWN_HOLD_S: float = 0.8
const COUNTDOWN_FADE_S: float = 0.25
const COUNTDOWN_PUNCH: float = 1.5
const COUNTDOWN_PUNCH_S: float = 0.25
const BANK_FLASH_S: float = 1.6
const BANK_FLASH_BOOST: float = 1.6
const WRONG_SAMPLE_S: float = 0.25
const WRONG_SHOW_S: float = 0.5
const WRONG_MIN_KMH: float = 20.0
const WRONG_MAX_STEP: float = 0.5  ## larger progress jumps are a lap wrap, not a reversal
const WRONG_BLINK_HZ: float = 3.0
const REVERSE_MS: float = 0.5

var _car: ArcadeCar = null
var _race: RaceManager = null
var _track: Node3D = null
var _rivals: Array[ArcadeCar] = []
var _connections: Array = []  ## [Signal, Callable] pairs made by bind()
var _shown: Dictionary = {}
var _pulse_t: float = 0.0
var _sample_t: float = 0.0
var _last_progress: float = 0.0
var _wrong_t: float = 0.0
var _countdown_tw: Tween = null
var _ints: Dictionary = {}  ## last integer behind each readout; strings are built only when it changes
var _bank_tw: Tween = null

var _root: Control
var _frame: Control
var _speed_fx: Control
var _pos_num: Label
var _pos_suffix: Label
var _pos_total: Label
var _minimap: MiniMap
var _lap_val: Label
var _time_val: Label
var _lap_cur_val: Label
var _best_val: Label
var _speedo: SpeedGauge
var _speed_label: Label
var _gear_label: Label
var _nitro: NitroBar
var _countdown: Label
var _drift_label: Label
var _bank_label: Label
var _wrong_label: Label
var _finish_label: Label


func _ready() -> void:
	_build()
	_apply_insets()


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = MSTheme.build()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_speed_fx = Control.new()
	_speed_fx.name = "SpeedFx"
	_speed_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_speed_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_speed_fx)

	_frame = Control.new()
	_frame.name = "Frame"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_frame)

	_build_position_block()
	_build_lap_block()
	_build_speedo()
	_build_nitro()
	_build_centre_column()
	_build_countdown()


func _build_position_block() -> void:
	var box := VBoxContainer.new()
	box.name = "Position"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MSTheme.GRID_PX)
	_pos_num = MSTheme.make_label("1", "digits", POS_PX, MSTheme.TEXT, true)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_pos_suffix = MSTheme.make_label("ST", "slant", POS_SUFFIX_PX, MSTheme.CYAN, true)
	_pos_total = MSTheme.make_label("/ 1", "digits", POS_TOTAL_PX, MSTheme.MUTED, true)
	col.add_child(_pos_suffix)
	col.add_child(_pos_total)
	row.add_child(_pos_num)
	row.add_child(col)
	box.add_child(row)
	_minimap = MiniMap.new()
	_minimap.custom_minimum_size = Vector2(MINIMAP_PX, MINIMAP_PX)
	box.add_child(_minimap)
	_frame.add_child(box)


func _build_lap_block() -> void:
	var box := VBoxContainer.new()
	box.name = "Lap"
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lap_head: Label = MSTheme.make_label(I18n.t("hud.lap"), "tracked", SMALL_PX, MSTheme.MUTED, true)
	lap_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(lap_head)
	_lap_val = MSTheme.make_label("1 / 1", "digits", LAP_PX, MSTheme.TEXT, true)
	_lap_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_lap_val)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", MSTheme.GRID_PX * 3)
	_time_val = _add_stat(grid, I18n.t("hud.time"))
	_lap_cur_val = _add_stat(grid, I18n.t("hud.lap_time"))
	_best_val = _add_stat(grid, I18n.t("hud.best"))
	box.add_child(grid)
	_frame.add_child(box)


func _add_stat(grid: GridContainer, caption: String) -> Label:
	grid.add_child(MSTheme.make_label(caption, "tracked", SMALL_PX, MSTheme.MUTED, true))
	var v: Label = MSTheme.make_label(I18n.t("hud.no_time"), "digits", TIME_PX, MSTheme.TEXT, true)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(v)
	return v


func _build_speedo() -> void:
	_speedo = SpeedGauge.new()
	_speedo.name = "Speedo"
	_speedo.custom_minimum_size = Vector2(GAUGE_W, GAUGE_H)
	_speedo.anchor_left = GAUGE_CENTRE_FRAC
	_speedo.anchor_right = GAUGE_CENTRE_FRAC
	_speedo.anchor_top = 1.0
	_speedo.anchor_bottom = 1.0
	_speedo.offset_left = -GAUGE_W * 0.5
	_speedo.offset_right = GAUGE_W * 0.5
	_speedo.offset_top = -GAUGE_H
	_speedo.offset_bottom = 0.0
	_speedo.centre_y_px = GAUGE_CENTRE_Y
	_speedo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_speedo)
	_speed_label = MSTheme.make_label("0", "digits", SPEED_PX, MSTheme.TEXT, true)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speed_label.position = Vector2(0.0, GAUGE_CENTRE_Y - SPEED_H * 0.5)
	_speed_label.size = Vector2(GAUGE_W, SPEED_H)
	_speedo.add_child(_speed_label)
	var unit: Label = MSTheme.make_label(I18n.t("hud.kmh"), "tracked", UNIT_PX, MSTheme.MUTED, true)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit.position = Vector2(0.0, UNIT_Y)
	unit.size = Vector2(GAUGE_W, UNIT_PX + MSTheme.GRID_PX)
	_speedo.add_child(unit)
	var gear_box := PanelContainer.new()
	gear_box.custom_minimum_size = Vector2(GAUGE_GEAR_W, GAUGE_GEAR_H)
	gear_box.position = Vector2(GAUGE_W * 0.5 - GAUGE_GEAR_W * 0.5, GAUGE_GEAR_Y)
	gear_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_label = MSTheme.make_label("N", "digits", POS_SUFFIX_PX, MSTheme.CYAN, true)
	_gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear_box.add_child(_gear_label)
	_speedo.add_child(gear_box)


func _build_nitro() -> void:
	var box := VBoxContainer.new()
	box.name = "Nitro"
	box.anchor_left = NITRO_LEFT_FRAC
	box.anchor_right = NITRO_LEFT_FRAC
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 0.0
	box.offset_right = NITRO_W
	box.offset_top = -NITRO_BLOCK_H
	box.offset_bottom = 0.0
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(MSTheme.make_label(I18n.t("hud.nitro"), "tracked", NITRO_LABEL_PX, MSTheme.CYAN, true))
	_nitro = NitroBar.new()
	_nitro.custom_minimum_size = Vector2(NITRO_W, NITRO_H)
	box.add_child(_nitro)
	_frame.add_child(box)


## Drift popup, wrong-way warning and finish text share one centred column under the top edge.
func _build_centre_column() -> void:
	var box := VBoxContainer.new()
	box.name = "CentreColumn"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -CENTRE_BOX_W * 0.5
	box.offset_right = CENTRE_BOX_W * 0.5
	box.offset_top = CENTRE_TOP_PX
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drift_label = MSTheme.make_label("", "digits", DRIFT_PX, MSTheme.CYAN, true)
	_bank_label = MSTheme.make_label("", "digits", BANK_PX, MSTheme.MAGENTA, true)
	_wrong_label = MSTheme.make_label(I18n.t("hud.wrong_way"), "slant", WRONG_PX, MSTheme.DANGER, true)
	_finish_label = MSTheme.make_label(I18n.t("hud.finished"), "slant", FINISH_PX, MSTheme.TEXT, true)
	for l: Label in [_drift_label, _bank_label, _wrong_label, _finish_label]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.visible = false
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	_frame.add_child(box)


func _build_countdown() -> void:
	_countdown = MSTheme.make_label("", "slant", COUNTDOWN_PX, MSTheme.TEXT, true)
	_countdown.name = "Countdown"
	_countdown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown.visible = false
	_frame.add_child(_countdown)


## Keeps the HUD clear of notches and rounded corners. Zero insets on desktop.
func _apply_insets() -> void:
	var ins: Vector4 = MSTheme.safe_insets()
	_frame.offset_left = ins.x + MSTheme.SAFE_MARGIN_PX
	_frame.offset_top = ins.y + MSTheme.SAFE_MARGIN_PX
	_frame.offset_right = -(ins.z + MSTheme.SAFE_MARGIN_PX)
	_frame.offset_bottom = -(ins.w + MSTheme.SAFE_MARGIN_PX)


## Connects to one car and one race. Earlier bindings are dropped first.
func bind(car: ArcadeCar, race: RaceManager, track: Node3D = null) -> void:
	_unbind()
	_car = car
	_race = race
	_track = track
	_pulse_t = 0.0
	_sample_t = 0.0
	_wrong_t = 0.0
	_last_progress = 0.0
	if car != null:
		_connect(car.drift_started, _on_drift_started)
		_connect(car.drift_ended, _on_drift_ended)
	if race != null:
		_connect(race.countdown_tick, _on_countdown_tick)
		_connect(race.race_started, _on_race_started)
		_connect(race.position_changed, _on_position_changed)
		_connect(race.race_finished, _on_race_finished)
		_rivals.clear()
		if race.has_method("get_cars"):
			var all: Array = race.call("get_cars")
			for c: Variant in all:
				if c is ArcadeCar and c != car:
					_rivals.append(c as ArcadeCar)
	_setup_minimap()


func get_readout() -> Dictionary:
	return _shown.duplicate()


func _connect(sig: Signal, cb: Callable) -> void:
	if not sig.is_connected(cb):
		sig.connect(cb)
		_connections.append([sig, cb])


func _unbind() -> void:
	for pair: Array in _connections:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if sig.is_connected(cb):
			sig.disconnect(cb)
	_connections.clear()


func _setup_minimap() -> void:
	if _track != null and _track.has_method("get_minimap_points"):
		_minimap.set_track(_points_from(_track.call("get_minimap_points")))
	_minimap.set_dot_count(1 + _rivals.size())


func _points_from(v: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if v is PackedVector2Array:
		return v
	if v is PackedVector3Array:
		var pv: PackedVector3Array = v
		for p: Vector3 in pv:
			out.append(Vector2(p.x, p.z))
		return out
	if v is Array:
		var arr: Array = v
		for p: Variant in arr:
			if p is Vector2:
				out.append(p)
			elif p is Vector3:
				out.append(Vector2(p.x, p.z))
	return out


func _process(delta: float) -> void:
	if _car == null:
		return
	_pulse_t += delta
	_refresh_speed()
	_nitro.set_state(_car.nitro_amount, _car.nitro_active, _pulse_t)
	_refresh_drift()
	if _race != null:
		_refresh_race()
		_refresh_minimap()
		_refresh_wrong_way(delta)


## True when the integer behind a readout changed. Keeps per-frame string building out of the HUD.
func _int_changed(key: String, v: int) -> bool:
	if _ints.has(key) and int(_ints[key]) == v:
		return false
	_ints[key] = v
	return true


## Centiseconds, the resolution of every race timer. Floor, same as fmt_time.
static func _centis(seconds: float) -> int:
	return int(maxf(seconds, 0.0) * 100.0)


func _refresh_speed() -> void:
	var kmh: int = maxi(roundi(_car.speed_kmh), 0)
	if _int_changed("speed", kmh):
		_set_text("speed", _speed_label, str(kmh))
	var gkey: int = _car.gear if _car.gear > 0 else (-1 if _car.forward_speed < -REVERSE_MS else 0)
	if _int_changed("gear", gkey):
		_set_text("gear", _gear_label, _gear_text())
	_speedo.set_rpm(_car.rpm_norm)


func _gear_text() -> String:
	if _car.gear > 0:
		return str(_car.gear)
	if _car.forward_speed < -REVERSE_MS:
		return I18n.t("hud.gear_reverse")
	return I18n.t("hud.gear_neutral")


func _refresh_race() -> void:
	_refresh_position()
	var lap: int = _race.get_lap(_car)
	var laps_total: int = _race.total_laps
	var lap_changed: bool = _int_changed("lap", lap)
	var laps_changed: bool = _int_changed("laps_total", laps_total)
	if lap_changed or laps_changed:
		_set_text("lap", _lap_val, I18n.t("hud.lap_of") % [lap, laps_total])
	if _int_changed("time", _centis(_race.race_time)):
		_set_text("time", _time_val, fmt_time(_race.race_time))
	var lap_time: float = _race.get_current_lap_time(_car)
	if _int_changed("lap_time", _centis(lap_time)):
		_set_text("lap_time", _lap_cur_val, fmt_time(lap_time))
	var best: float = _race.get_best_lap_time(_car)
	if _int_changed("best", -1 if best <= 0.0 else _centis(best)):
		_set_text("best", _best_val, I18n.t("hud.no_time") if best <= 0.0 else fmt_time(best))


func _refresh_position() -> void:
	var pos: int = _race.get_position(_car)
	if _int_changed("position", pos):
		_set_text("position", _pos_num, str(pos))
		_set_text("position_suffix", _pos_suffix, I18n.ordinal(pos))
	var total: int = _race.get_car_count()
	if _int_changed("car_count", total):
		_set_text("position_total", _pos_total, I18n.t("hud.of") % total)


func _refresh_minimap() -> void:
	_minimap.set_dot(0, _race.get_lap_progress(_car), true)
	for i: int in _rivals.size():
		_minimap.set_dot(i + 1, _race.get_lap_progress(_rivals[i]), false)


func _refresh_drift() -> void:
	var drifting: bool = _car.is_drifting
	_drift_label.visible = drifting
	_shown["drift_visible"] = drifting
	if drifting and _int_changed("drift", int(_car.drift_score)):
		_set_text("drift", _drift_label, "%s  %s" % [I18n.t("hud.drift"), group_int(int(_car.drift_score))])


## Samples lap progress a few times a second. Steady backward progress at speed shows the warning.
func _refresh_wrong_way(delta: float) -> void:
	_sample_t += delta
	if _sample_t >= WRONG_SAMPLE_S:
		_sample_t = 0.0
		var p: float = _race.get_lap_progress(_car)
		var step: float = p - _last_progress
		_last_progress = p
		if absf(step) <= WRONG_MAX_STEP and step < 0.0 and _car.speed_kmh >= WRONG_MIN_KMH:
			_wrong_t += WRONG_SAMPLE_S
		else:
			_wrong_t = 0.0
	var showing: bool = _wrong_t >= WRONG_SHOW_S
	_wrong_label.visible = showing
	_shown["wrong_way"] = showing
	if showing:
		_wrong_label.modulate.a = 0.5 + 0.5 * sin(_pulse_t * TAU * WRONG_BLINK_HZ)


func _on_drift_started() -> void:
	_drift_label.visible = true
	_shown["drift_visible"] = true


func _on_drift_ended(score: float) -> void:
	_set_text("bank", _bank_label, "%s  +%s" % [I18n.t("hud.banked"), group_int(int(score))])
	_bank_label.visible = true
	_shown["bank_visible"] = true
	_bank_label.modulate = Color(BANK_FLASH_BOOST, BANK_FLASH_BOOST, BANK_FLASH_BOOST, 1.0)
	if _bank_tw != null and _bank_tw.is_valid():
		_bank_tw.kill()
	_bank_tw = create_tween()
	_bank_tw.tween_property(_bank_label, "modulate", Color(1.0, 1.0, 1.0, 0.0), BANK_FLASH_S)


func _on_countdown_tick(seconds_left: int) -> void:
	var go: bool = seconds_left <= 0
	var text: String = I18n.t("hud.go") if go else str(seconds_left)
	var col: Color = MSTheme.CYAN
	if not go:
		col = MSTheme.DANGER if seconds_left == 1 else MSTheme.AMBER
	_countdown.add_theme_color_override("font_color", col)
	_countdown.text = text
	_shown["countdown"] = text
	_countdown.visible = true
	_shown["countdown_visible"] = true
	_countdown.modulate.a = 1.0
	_countdown.pivot_offset = _countdown.size * 0.5
	_countdown.scale = Vector2.ONE * COUNTDOWN_PUNCH
	if _countdown_tw != null and _countdown_tw.is_valid():
		_countdown_tw.kill()
	_countdown_tw = create_tween()
	_countdown_tw.tween_property(_countdown, "scale", Vector2.ONE, COUNTDOWN_PUNCH_S) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if go:
		_countdown_tw.tween_interval(COUNTDOWN_HOLD_S)
		_countdown_tw.tween_property(_countdown, "modulate:a", 0.0, COUNTDOWN_FADE_S)
		_countdown_tw.tween_callback(_hide_countdown)


func _hide_countdown() -> void:
	_countdown.visible = false
	_shown["countdown_visible"] = false


func _on_race_started() -> void:
	_shown["race_started"] = true


func _on_position_changed(_car_changed: ArcadeCar, _pos: int) -> void:
	if _race != null and _car != null:
		_refresh_position()


func _on_race_finished(_results: Array[Dictionary]) -> void:
	_finish_label.visible = true
	_shown["finished_visible"] = true


func _set_text(key: String, label: Label, text: String) -> void:
	if _shown.get(key, "") == text:
		return
	_shown[key] = text
	label.text = text


## mm:ss.cc, the layout every race timer uses.
static func fmt_time(seconds: float) -> String:
	var t: float = maxf(seconds, 0.0)
	var m: int = int(t / 60.0)
	var s: int = int(t) % 60
	var c: int = int(t * 100.0) % 100
	return "%02d:%02d.%02d" % [m, s, c]


## Thousands grouped with a space: 1240 -> "1 240".
static func group_int(v: int) -> String:
	var digits: String = str(absi(v))
	var out: String = ""
	var n: int = digits.length()
	for i: int in n:
		if i > 0 and (n - i) % 3 == 0:
			out += " "
		out += digits[i]
	return ("-" if v < 0 else "") + out
