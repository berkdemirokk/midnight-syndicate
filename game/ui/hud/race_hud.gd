class_name RaceHUD
extends CanvasLayer
## Race HUD. Reads ArcadeCar and RaceManager state and reacts to race signals; it never drives race logic.
## Every displayed string is cached in _shown, so a text is reshaped only when its value changes.
## get_readout() returns that cache for tests and captures.
## Draw cost: the whole HUD is painted from one canvas item (_paint) in four passes (rects, lines, dots, text) so
## Godot batches each pass into one draw call. Text is HudText, not Label: see hud_text.gd. Budget: <= 25 draws.

const GAUGE_W: float = 340.0
const GAUGE_H: float = 312.0
const GAUGE_CENTRE_FRAC: float = 0.76  ## horizontal centre of the speedometer, fraction of the safe frame (clear of the car at 0.5 to 0.65)
const GAUGE_CENTRE_Y: float = 142.0  ## arc centre, from the top of the gauge box
const GAUGE_GEAR_Y: float = 246.0
const GAUGE_GEAR_W: float = 56.0
const GAUGE_GEAR_H: float = 34.0
const SPEED_H: float = 130.0  ## about one line of the 112 px digits, centred on the arc centre
const UNIT_Y: float = 204.0
const NITRO_W: float = 320.0
const NITRO_H: float = 20.0
const NITRO_LEFT_FRAC: float = 0.3
const MINIMAP_PX: float = 240.0
const CENTRE_TOP_PX: float = 120.0
const POS_PX: int = 80
const POS_SUFFIX_PX: int = 28
const POS_TOTAL_PX: int = 28
const SPEED_PX: int = 96  ## fits inside the arc (inner diameter 228 px) with room to spare
const UNIT_PX: int = 20
const LAP_PX: int = 40
const TOP_SCRIM_PX: float = 300.0  ## height of the dark gradient behind the top HUD clusters
const TOP_SCRIM_ALPHA: float = 0.6
const SCRIM_STEP_PX: int = 3  ## the gradient is stacked rects of this height, so it joins the rect batch
const SCRIM_HOLD_AT: float = 0.75  ## the gradient holds 60 percent of its alpha here, under the lap/time rows
const SMALL_PX: int = 18
const TIME_PX: int = 24
const NITRO_LABEL_PX: int = 18
const COUNTDOWN_PX: int = 200
const DRIFT_PX: int = 40
const BANK_PX: int = 28
const WRONG_PX: int = 48
const FINISH_PX: int = 28
const GEAR_PAD_X: float = 24.0
const GEAR_PAD_Y: float = 12.0
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
const PANEL_SKEW: float = MSTheme.SKEW_RATIO * 0.5  ## same shear as MSTheme.box()
const PLATE_PAD: float = 14.0  ## backing plates under every cluster: HUD text stays readable on bright signage
const PHONE_HUD_SCALE: float = 1.4  ## 24 px timers are 8.6 pt on an iPhone at the 1080 px base: scale the whole frame
const POPUP_PAD_X: float = 24.0


## The single canvas item the HUD paints into.
class HudCanvas:
	extends Control
	var painter: Callable

	func _draw() -> void:
		painter.call(self)


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
var _frame: HudCanvas
var _speed_fx: Control
var _minimap: MiniMap
var _speedo: SpeedGauge
var _nitro: NitroBar
var _texts: Array[HudText] = []  ## sorted by pixel size, the order HudText.paint needs
var _pos_num: HudText
var _pos_suffix: HudText
var _pos_total: HudText
var _lap_head: HudText
var _lap_val: HudText
var _cap_time: HudText
var _cap_lap: HudText
var _cap_best: HudText
var _time_val: HudText
var _lap_cur_val: HudText
var _best_val: HudText
var _speed_label: HudText
var _unit_label: HudText
var _gear_label: HudText
var _nitro_label: HudText
var _countdown: HudText
var _drift_label: HudText
var _bank_label: HudText
var _wrong_label: HudText
var _finish_label: HudText


func _ready() -> void:
	_build()
	_apply_insets()
	_root.resized.connect(_apply_insets)


## 1.0 on desktop, PHONE_HUD_SCALE on a touch phone.
static func hud_scale() -> float:
	return PHONE_HUD_SCALE if MSTheme.phone else 1.0


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_speed_fx = Control.new()
	_speed_fx.name = "SpeedFx"
	_speed_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_speed_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_speed_fx)

	_frame = HudCanvas.new()
	_frame.name = "Frame"
	_frame.painter = _paint
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_frame)

	_speedo = SpeedGauge.new()
	_nitro = NitroBar.new()
	_minimap = MiniMap.new()
	_minimap.size_px = Vector2(MINIMAP_PX, MINIMAP_PX)
	_build_texts()


func _text(kind: String, px: int, col: Color, initial: String) -> HudText:
	var t := HudText.new(kind, px, col, true)
	t.set_text(initial)
	_texts.append(t)
	return t


func _build_texts() -> void:
	_pos_num = _text("digits", POS_PX, MSTheme.TEXT, "1")
	_pos_suffix = _text("digits", POS_SUFFIX_PX, MSTheme.CYAN, "ST")
	_pos_total = _text("digits", POS_TOTAL_PX, MSTheme.MUTED, "/ 1")
	_lap_head = _text("tracked", SMALL_PX, MSTheme.MUTED, I18n.t("hud.lap"))
	_lap_val = _text("digits", LAP_PX, MSTheme.TEXT, "1 / 1")
	_cap_time = _text("tracked", SMALL_PX, MSTheme.MUTED, I18n.t("hud.time"))
	_cap_lap = _text("tracked", SMALL_PX, MSTheme.MUTED, I18n.t("hud.lap_time"))
	_cap_best = _text("tracked", SMALL_PX, MSTheme.MUTED, I18n.t("hud.best"))
	_time_val = _text("digits", TIME_PX, MSTheme.TEXT, I18n.t("hud.no_time"))
	_lap_cur_val = _text("digits", TIME_PX, MSTheme.TEXT, I18n.t("hud.no_time"))
	_best_val = _text("digits", TIME_PX, MSTheme.TEXT, I18n.t("hud.no_time"))
	_speed_label = _text("digits", SPEED_PX, MSTheme.TEXT, "0")
	_unit_label = _text("tracked", UNIT_PX, MSTheme.MUTED, I18n.t("hud.kmh"))
	_gear_label = _text("digits", POS_SUFFIX_PX, MSTheme.CYAN, "N")
	_nitro_label = _text("tracked", NITRO_LABEL_PX, MSTheme.CYAN, I18n.t("hud.nitro"))
	_drift_label = _text("digits", DRIFT_PX, MSTheme.CYAN, "")
	_bank_label = _text("digits", BANK_PX, MSTheme.MAGENTA, "")
	_wrong_label = _text("digits", WRONG_PX, MSTheme.DANGER, I18n.t("hud.wrong_way"))
	_finish_label = _text("digits", FINISH_PX, MSTheme.TEXT, I18n.t("hud.finished"))
	_countdown = _text("digits", COUNTDOWN_PX, MSTheme.TEXT, "")
	for t: HudText in [_drift_label, _bank_label, _wrong_label, _finish_label, _countdown]:
		t.visible = false
	_texts.sort_custom(func(a: HudText, b: HudText) -> bool: return a.size_px < b.size_px)


## Keeps the HUD clear of notches and rounded corners. Zero insets on desktop.
func _apply_insets() -> void:
	var ins: Vector4 = MSTheme.safe_insets()
	var k: float = hud_scale()
	var m: float = MSTheme.SAFE_MARGIN_PX
	_frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_frame.position = Vector2(ins.x + m, ins.y + m)
	_frame.size = (_root.size - Vector2(ins.x + ins.z + m * 2.0, ins.y + ins.w + m * 2.0)) / k
	_frame.scale = Vector2(k, k)


## Lays every element out and paints it. Pass order is what makes the batches: rects, lines, dots, text.
func _paint(c: Control) -> void:
	var sz: Vector2 = c.size
	var sep: float = float(MSTheme.GRID_PX * 2)

	# Top-left: position, suffix and total on one row, minimap under it.
	_pos_num.pos = Vector2.ZERO
	var col_x: float = _pos_num.width() + float(MSTheme.GRID_PX)
	_pos_suffix.pos = Vector2(col_x, 0.0)
	_pos_total.pos = Vector2(col_x, _pos_suffix.height())
	var row_h: float = maxf(_pos_num.height(), _pos_suffix.height() + _pos_total.height())
	var map_origin: Vector2 = Vector2(0.0, row_h + sep)

	# Top-right: LAP header, lap value, then a two column grid of timers.
	var cap_w: float = maxf(_cap_time.width(), maxf(_cap_lap.width(), _cap_best.width()))
	var val_w: float = maxf(_time_val.width(), maxf(_lap_cur_val.width(), _best_val.width()))
	var grid_w: float = cap_w + float(MSTheme.GRID_PX * 3) + val_w
	var box_x: float = sz.x - maxf(grid_w, maxf(_lap_head.width(), _lap_val.width()))
	_lap_head.pos = Vector2(sz.x - _lap_head.width(), 0.0)
	var lap_y: float = _lap_head.height() + sep
	_lap_val.pos = Vector2(sz.x - _lap_val.width(), lap_y)
	var grid_y: float = lap_y + _lap_val.height() + sep
	var stat_h: float = maxf(_cap_time.height(), _time_val.height())
	var stats: Array = [[_cap_time, _time_val], [_cap_lap, _lap_cur_val], [_cap_best, _best_val]]
	for i: int in stats.size():
		var cap: HudText = stats[i][0]
		var val: HudText = stats[i][1]
		var y: float = grid_y + float(i) * (stat_h + float(MSTheme.GRID_PX))
		cap.pos = Vector2(box_x, y + (stat_h - cap.height()) * 0.5)  # labels centre vertically in their cell
		val.pos = Vector2(box_x + cap_w + float(MSTheme.GRID_PX * 3) + (val_w - val.width()), y)

	# Bottom: speedometer (arc, speed, unit, gear box) and nitro bar.
	var gauge_l: float = sz.x * GAUGE_CENTRE_FRAC - GAUGE_W * 0.5
	var gauge_t: float = sz.y - GAUGE_H
	var arc_centre: Vector2 = Vector2(gauge_l + GAUGE_W * 0.5, gauge_t + GAUGE_CENTRE_Y)
	_speed_label.pos = Vector2(gauge_l + (GAUGE_W - _speed_label.width()) * 0.5,
		gauge_t + GAUGE_CENTRE_Y - SPEED_H * 0.5 + maxf((SPEED_H - _speed_label.height()) * 0.5, 0.0))
	_unit_label.pos = Vector2(gauge_l + (GAUGE_W - _unit_label.width()) * 0.5,
		gauge_t + UNIT_Y + (float(UNIT_PX + MSTheme.GRID_PX) - _unit_label.height()) * 0.5)
	var gear_size: Vector2 = Vector2(maxf(GAUGE_GEAR_W, _gear_label.width() + GEAR_PAD_X * 2.0),
		maxf(GAUGE_GEAR_H, _gear_label.height() + GEAR_PAD_Y * 2.0))
	var gear_rect: Rect2 = Rect2(Vector2(gauge_l + GAUGE_W * 0.5 - GAUGE_GEAR_W * 0.5, gauge_t + GAUGE_GEAR_Y), gear_size)
	_gear_label.pos = gear_rect.position + Vector2(GEAR_PAD_X, GEAR_PAD_Y)
	var nitro_rect: Rect2 = Rect2(sz.x * NITRO_LEFT_FRAC, sz.y - NITRO_H, NITRO_W, NITRO_H)
	_nitro_label.pos = Vector2(nitro_rect.position.x, nitro_rect.position.y - sep - _nitro_label.height())

	# Centre column: drift popup, bank flash, wrong-way and finish text stack under the top edge.
	var cy: float = CENTRE_TOP_PX
	for t: HudText in [_drift_label, _bank_label, _wrong_label, _finish_label]:
		if t.visible:
			t.pos = Vector2((sz.x - t.width()) * 0.5, cy)
			cy += t.height() + sep
	_countdown.pos = (sz - Vector2(_countdown.width(), _countdown.height())) * 0.5
	_countdown.pivot = sz * 0.5

	# Backing plates, measured from the layout above.
	var pos_w: float = col_x + maxf(_pos_suffix.width(), _pos_total.width())
	var pos_plate: Rect2 = Rect2(-PLATE_PAD, -PLATE_PAD * 0.5, pos_w + PLATE_PAD * 2.5, row_h + PLATE_PAD)
	var stats_bottom: float = grid_y + float(stats.size()) * (stat_h + float(MSTheme.GRID_PX)) - float(MSTheme.GRID_PX)
	var lap_plate: Rect2 = Rect2(box_x - PLATE_PAD * 1.5, -PLATE_PAD * 0.5, sz.x - box_x + PLATE_PAD * 2.5, stats_bottom + PLATE_PAD * 1.5)
	var gauge_top: float = gauge_t + GAUGE_CENTRE_Y - speedo_radius()
	var gauge_plate: Rect2 = Rect2(arc_centre.x - speedo_radius() - PLATE_PAD * 1.5, gauge_top - PLATE_PAD,
		speedo_radius() * 2.0 + PLATE_PAD * 3.0, gear_rect.end.y - gauge_top + PLATE_PAD * 2.0)
	var nitro_plate: Rect2 = Rect2(nitro_rect.position.x - PLATE_PAD * 1.5, _nitro_label.pos.y - PLATE_PAD * 0.5,
		NITRO_W + PLATE_PAD * 3.0, nitro_rect.end.y - _nitro_label.pos.y + PLATE_PAD * 1.5)

	# Pass 1: rects.
	_paint_scrim(c)
	for plate: Rect2 in [pos_plate, lap_plate, gauge_plate, nitro_plate]:
		_paint_skew_fill(c, plate, MSTheme.PLATE_BG)
	for t: HudText in [_drift_label, _bank_label, _wrong_label, _finish_label]:
		if t.visible and t.text != "":
			_paint_skew_fill(c, Rect2(t.pos.x - POPUP_PAD_X, t.pos.y, t.width() + POPUP_PAD_X * 2.0, t.height()), MSTheme.tint(MSTheme.PLATE_BG, MSTheme.PLATE_BG.a * t.modulate.a))
	_minimap.paint_rects(c, map_origin)
	_paint_skew_fill(c, gear_rect)
	_nitro.paint_rects(c, nitro_rect)
	# Pass 2: lines.
	_speedo.paint_lines(c, arc_centre)
	_minimap.paint_lines(c, map_origin)
	_paint_skew_border(c, gear_rect)
	_nitro.paint_lines(c, nitro_rect)
	# Pass 3: dots, one shared texture.
	_minimap.paint_dots(c, map_origin)
	# Pass 4: text, outlines first.
	HudText.paint(c, _texts)


func speedo_radius() -> float:
	return _speedo.radius_px


## Dark gradient under the top clusters, as stacked rects. The top edge is the screen edge, not the safe frame.
func _paint_scrim(c: Control) -> void:
	var k: float = hud_scale()
	var left: float = -c.position.x / k
	var top: float = -c.position.y / k
	var steps: int = ceili(TOP_SCRIM_PX / float(SCRIM_STEP_PX))
	for i: int in steps:
		var t: float = (float(i) + 0.5) / float(steps)
		var a: float = TOP_SCRIM_ALPHA * 0.6 * (1.0 - t) / (1.0 - SCRIM_HOLD_AT) if t >= SCRIM_HOLD_AT \
			else lerpf(TOP_SCRIM_ALPHA, TOP_SCRIM_ALPHA * 0.6, t / SCRIM_HOLD_AT)
		c.draw_rect(Rect2(left, top + float(i * SCRIM_STEP_PX), _root.size.x / k, float(SCRIM_STEP_PX)), Color(0.0, 0.0, 0.0, a))


## Panel fill sheared like MSTheme.box(): a skewed rect keeps the rect batch.
func _paint_skew_fill(c: CanvasItem, r: Rect2, col: Color = MSTheme.PANEL_BG) -> void:
	c.draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(PANEL_SKEW, 1.0), Vector2(-PANEL_SKEW * (r.position.y + r.size.y * 0.5), 0.0)))
	c.draw_rect(r, col)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)


func _paint_skew_border(c: CanvasItem, r: Rect2) -> void:
	var inner: Rect2 = r.grow(-0.5)
	var mid: float = r.position.y + r.size.y * 0.5
	var pts := PackedVector2Array()
	for p: Vector2 in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
		pts.append(Vector2(p.x + PANEL_SKEW * (p.y - mid), p.y))
	c.draw_multiline(PackedVector2Array([pts[0], pts[1], pts[1], pts[2], pts[2], pts[3], pts[3], pts[0]]), MSTheme.BORDER, 1.0, true)


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
	if _frame != null:
		_frame.queue_redraw()  # timers and the rpm arc change every frame, so one redraw per frame is the floor
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
	_countdown.color = col
	_countdown.set_text(text)
	_shown["countdown"] = text
	_countdown.visible = true
	_shown["countdown_visible"] = true
	_countdown.modulate.a = 1.0
	_countdown.scale = COUNTDOWN_PUNCH
	if _countdown_tw != null and _countdown_tw.is_valid():
		_countdown_tw.kill()
	_countdown_tw = create_tween()
	_countdown_tw.tween_property(_countdown, "scale", 1.0, COUNTDOWN_PUNCH_S) \
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


func _set_text(key: String, label: HudText, text: String) -> void:
	if _shown.get(key, "") == text:
		return
	_shown[key] = text
	label.set_text(text)


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
