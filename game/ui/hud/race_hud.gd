class_name RaceHUD
extends CanvasLayer
## Race HUD. Reads ArcadeCar and RaceManager state and reacts to race signals; it never drives race logic.
## Layout (heading up, reference style): top left position and leaderboard of four rows around the player; top centre
## lap progress strip with the track name and length; top right completion and race clock; bottom left round minimap;
## bottom right round tachometer, speed, gear and a round nitro button.
## Every displayed string is cached in _shown, so a text is reshaped only when its value changes.
## get_readout() returns that cache for tests and captures.
## Draw cost: the whole HUD is painted from one canvas item (_paint) in four passes (rects, lines, dots, text) so
## Godot batches each pass into a few draw calls. Text is HudText, not Label: see hud_text.gd. Budget: <= 24 draws.

const VIOLET: Color = Color(0.706, 0.361, 1.0)  ## #B45CFF, the accent; CYAN is the secondary colour
const GEAR_RING_COL: Color = Color(0.06, 0.43, 0.49)  ## BORDER pre-blended (translucent chords bead)
const TRACK_LEN_FALLBACK: float = 2200.0  ## metres, for captures and tests whose track has no length
const GAP_MIN_MS: float = 8.0  ## gaps divide by at least this speed, so a stopped car does not blow them up

## Three pixel sizes only: every size is one more draw call per pass, so the whole HUD uses 80, 40 and 20.
const BIG_PX: int = 80  ## position, speed, countdown
const MID_PX: int = 40  ## completion, clock, gear, popups, position total
const SMALL_PX: int = 20  ## leaderboard, track line, scale numbers, labels
const POS_PX: int = BIG_PX
const POS_TOTAL_PX: int = MID_PX
const PCT_PX: int = MID_PX
const CLOCK_PX: int = MID_PX
const ROW_PX: int = SMALL_PX
const SPEED_PX: int = BIG_PX
const GEAR_PX: int = MID_PX
const DRIFT_PX: int = MID_PX
const BANK_PX: int = MID_PX
const WRONG_PX: int = MID_PX
const FINISH_PX: int = MID_PX
const COUNTDOWN_PX: int = BIG_PX
const COUNTDOWN_BASE: float = 2.4  ## the countdown is drawn at 2.4x its pixel size
const COUNTDOWN_PUNCH: float = 1.5
const COUNTDOWN_PUNCH_S: float = 0.25
const COUNTDOWN_HOLD_S: float = 0.8
const COUNTDOWN_FADE_S: float = 0.25

const LB_ROWS: int = 4
const LB_ROW_H: float = 32.0
const LB_W: float = 300.0
const LB_PAD_X: float = 12.0
const LB_NAME_X: float = 56.0
const LB_NAME_CHARS: int = 12

const STRIP_W: float = 520.0
const STRIP_H: float = 6.0
const STRIP_Y: float = 14.0
const STRIP_MARK_PX: float = 7.0
const CENTRE_TOP_PX: float = 84.0

const MM_R: float = 116.0  ## minimap radius
const MM_PAD: float = 16.0

const TACH_R: float = 124.0  ## arc radius of the tachometer
const TACH_ARC_W: float = 12.0
const TACH_PLATE_R: float = 150.0
const TACH_OFF_X: float = 300.0  ## centre of the tachometer, from the right and bottom edge
const TACH_OFF_Y: float = 186.0
const TACH_NUM_R: float = 88.0  ## radius of the 0..8 scale numbers
const GEAR_R: float = 28.0
const GEAR_DY: float = 74.0  ## gear ring below the tachometer centre, in the gap of the arc
const NITRO_R: float = 50.0
const NITRO_OFF_X: float = 84.0
const NITRO_OFF_Y: float = 150.0

const TOP_SCRIM_PX: float = 300.0  ## height of the dark gradient behind the top HUD clusters
const TOP_SCRIM_ALPHA: float = 0.6
const SCRIM_STEP_PX: int = 3  ## the gradient is stacked rects of this height, so it joins the rect batch
const SCRIM_HOLD_AT: float = 0.75  ## the gradient holds 60 percent of its alpha here, under the lap rows
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
const PHONE_HUD_SCALE: float = 1.4  ## 20 px labels are about 6 pt on an iPhone at the 1080 px base: scale the whole frame
const POPUP_PAD_X: float = 24.0
const OUT_SHOW_S: float = 2.5  ## elimination: the "out" line stays this long after a car leaves the race


## The single canvas item the HUD paints into.
class HudCanvas:
	extends Control
	var painter: Callable

	func _draw() -> void:
		painter.call(self)


var _car: ArcadeCar = null
var _race: RaceManager = null
var _track: Node3D = null
var _cars: Array[ArcadeCar] = []  ## every car in the race, player included
var _rivals: Array[ArcadeCar] = []
var _online_rows: Array = []  ## online race: the server's live order, rows of {car, name, place, distance}; empty offline
var _connections: Array = []  ## [Signal, Callable] pairs made by bind()
var _shown: Dictionary = {}
var _pulse_t: float = 0.0
var _sample_t: float = 0.0
var _last_progress: float = 0.0
var _wrong_t: float = 0.0
var _countdown_tw: Tween = null
var _ints: Dictionary = {}  ## last integer behind each readout; strings are built only when it changes
var _bank_tw: Tween = null
var _strip_p: float = 0.0  ## player lap progress, 0..1, for the top strip
var _me_row: int = -1  ## leaderboard row of the player this frame, -1 when not shown

var _root: Control
var _frame: HudCanvas
var _speed_fx: Control
var _minimap: MiniMap
var _speedo: SpeedGauge
var _nitro: NitroBar
var _texts: Array[HudText] = []  ## sorted by pixel size, the order HudText.paint needs
var _pos_num: HudText
var _pos_total: HudText
var _lb_place: Array[HudText] = []
var _lb_name: Array[HudText] = []
var _lb_gap: Array[HudText] = []
var _pct: HudText
var _clock: HudText
var _lap_val: HudText
var _track_label: HudText
var _speed_label: HudText
var _unit_label: HudText
var _gear_label: HudText
var _tach_nums: Array[HudText] = []
var _north: HudText
var _nitro_label: HudText
var _countdown: HudText
var _drift_label: HudText
var _bank_label: HudText
var _mode_label: HudText  ## drift score and chain, or cars left
var _out_label: HudText  ## elimination: the car that just went out
var _out_t: float = 0.0
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
	_speedo.radius_px = TACH_R
	_speedo.arc_width_px = TACH_ARC_W
	_nitro = NitroBar.new()
	_nitro.radius_px = NITRO_R
	_minimap = MiniMap.new()
	_minimap.radius_px = MM_R
	_build_texts()


func _text(kind: String, px: int, col: Color, initial: String) -> HudText:
	var t := HudText.new(kind, px, col, true)
	t.set_text(initial)
	_texts.append(t)
	return t


func _build_texts() -> void:
	_pos_num = _text("slant", POS_PX, MSTheme.TEXT, "1")
	_pos_total = _text("digits", POS_TOTAL_PX, MSTheme.MUTED, "/ 1")
	for i: int in LB_ROWS:
		_lb_place.append(_text("digits", ROW_PX, MSTheme.TEXT, ""))
		_lb_name.append(_text("digits", ROW_PX, MSTheme.TEXT, ""))
		_lb_gap.append(_text("digits", ROW_PX, MSTheme.MUTED, ""))
	_pct = _text("digits", PCT_PX, MSTheme.TEXT, "% 0")
	_clock = _text("digits", CLOCK_PX, MSTheme.TEXT, I18n.t("hud.no_time"))
	_lap_val = _text("digits", ROW_PX, MSTheme.MUTED, "1 / 1")
	_track_label = _text("digits", ROW_PX, MSTheme.TEXT, "")
	_speed_label = _text("digits", SPEED_PX, MSTheme.TEXT, "0")
	_unit_label = _text("digits", ROW_PX, MSTheme.MUTED, I18n.t("hud.kmh"))
	_gear_label = _text("digits", GEAR_PX, MSTheme.CYAN, "N")
	for i: int in 9:
		_tach_nums.append(_text("digits", SMALL_PX, MSTheme.MUTED, str(i)))
	_north = _text("digits", SMALL_PX, MSTheme.MUTED, "N")
	_nitro_label = _text("digits", ROW_PX, MSTheme.CYAN, I18n.t("hud.nitro"))
	_drift_label = _text("digits", DRIFT_PX, MSTheme.CYAN, "")
	_bank_label = _text("digits", BANK_PX, MSTheme.MAGENTA, "")
	_mode_label = _text("digits", MID_PX, MSTheme.CYAN, "")
	_out_label = _text("digits", FINISH_PX, MSTheme.DANGER, "")
	_wrong_label = _text("digits", WRONG_PX, MSTheme.DANGER, I18n.t("hud.wrong_way"))
	_finish_label = _text("digits", FINISH_PX, MSTheme.TEXT, I18n.t("hud.finished"))
	_countdown = _text("digits", COUNTDOWN_PX, MSTheme.TEXT, "")
	_countdown.scale = COUNTDOWN_BASE
	for t: HudText in [_drift_label, _bank_label, _wrong_label, _finish_label, _mode_label, _out_label, _countdown]:
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
	var pad: float = float(MSTheme.GRID_PX)

	# Top left: big position, then the leaderboard window around the player.
	_pos_total.pos = Vector2(_pos_num.width() + pad * 0.5, _pos_num.height() - _pos_total.height() - pad)
	var lb_top: float = _pos_num.height() + pad * 0.5
	var tl_w: float = maxf(_pos_num.width() + pad * 0.5 + _pos_total.width(), LB_W)
	for i: int in LB_ROWS:
		var ty: float = lb_top + float(i) * LB_ROW_H + (LB_ROW_H - 4.0 - _lb_place[i].height()) * 0.5
		_lb_place[i].pos = Vector2(LB_PAD_X, ty)
		_lb_name[i].pos = Vector2(LB_NAME_X, ty)
		_lb_gap[i].pos = Vector2(LB_W - LB_PAD_X - _lb_gap[i].width(), ty)
	var tl_plate: Rect2 = Rect2(-PLATE_PAD, -PLATE_PAD * 0.5, tl_w + PLATE_PAD * 2.0,
		lb_top + float(LB_ROWS) * LB_ROW_H + PLATE_PAD * 0.5)

	# Top centre: lap strip with the track name and length under it.
	var strip_l: float = sz.x * 0.5 - STRIP_W * 0.5
	_track_label.pos = Vector2(sz.x * 0.5 - _track_label.width() * 0.5, STRIP_Y + STRIP_H + pad)
	var strip_plate: Rect2 = Rect2(strip_l - PLATE_PAD, STRIP_Y - PLATE_PAD * 0.5, STRIP_W + PLATE_PAD * 2.0,
		_track_label.pos.y + _track_label.height() - STRIP_Y + PLATE_PAD)

	# Top right: completion, race clock, lap.
	_pct.pos = Vector2(sz.x - _pct.width(), 0.0)
	_clock.pos = Vector2(sz.x - _clock.width(), _pct.height() - pad * 0.5)
	_lap_val.pos = Vector2(sz.x - _lap_val.width(), _clock.pos.y + _clock.height())
	var tr_w: float = maxf(_pct.width(), maxf(_clock.width(), _lap_val.width()))
	var tr_plate: Rect2 = Rect2(sz.x - tr_w - PLATE_PAD * 1.5, -PLATE_PAD * 0.5, tr_w + PLATE_PAD * 2.5,
		_lap_val.pos.y + _lap_val.height() + PLATE_PAD * 0.5)

	# Bottom left: round minimap, N marker on the rim.
	var mm_c: Vector2 = Vector2(MM_PAD + MM_R, sz.y - MM_PAD - MM_R)
	var nd: Vector2 = _minimap.north_dir()
	_north.pos = mm_c + nd * (MM_R - 18.0) - Vector2(_north.width(), _north.height()) * 0.5

	# Bottom right: tachometer, speed, gear ring, nitro button.
	var tc: Vector2 = Vector2(sz.x - TACH_OFF_X, sz.y - TACH_OFF_Y)
	_speed_label.pos = tc - Vector2(_speed_label.width(), _speed_label.height()) * 0.5 + Vector2(0.0, -22.0)
	_unit_label.pos = Vector2(tc.x - _unit_label.width() * 0.5, tc.y + 24.0)
	var gear_c: Vector2 = tc + Vector2(0.0, GEAR_DY)
	_gear_label.pos = gear_c - Vector2(_gear_label.width(), _gear_label.height()) * 0.5
	for i: int in _tach_nums.size():
		var a: float = deg_to_rad(_speedo.start_deg + _speedo.sweep_deg * float(i) / float(_tach_nums.size() - 1))
		var n: HudText = _tach_nums[i]
		n.pos = tc + Vector2(cos(a), sin(a)) * TACH_NUM_R - Vector2(n.width(), n.height()) * 0.5
	var nc: Vector2 = Vector2(sz.x - NITRO_OFF_X, sz.y - NITRO_OFF_Y)
	_nitro_label.pos = Vector2(nc.x - _nitro_label.width() * 0.5, nc.y + NITRO_R + 16.0)

	# Centre column: drift popup, bank flash, wrong-way and finish text stack under the top strip.
	var cy: float = CENTRE_TOP_PX
	for t: HudText in [_mode_label, _drift_label, _out_label, _bank_label, _wrong_label, _finish_label]:
		if t.visible:
			t.pos = Vector2((sz.x - t.width()) * 0.5, cy)
			cy += t.height() + pad * 2.0
	_countdown.pos = (sz - Vector2(_countdown.width(), _countdown.height())) * 0.5
	_countdown.pivot = sz * 0.5

	# Pass 1: rects.
	_paint_scrim(c)
	_paint_skew_fill(c, tl_plate, MSTheme.PLATE_BG)
	_paint_skew_fill(c, strip_plate, MSTheme.PLATE_BG)
	_paint_skew_fill(c, tr_plate, MSTheme.PLATE_BG)
	if _me_row >= 0:
		var y: float = lb_top + float(_me_row) * LB_ROW_H
		_paint_skew_fill(c, Rect2(0.0, y, LB_W, LB_ROW_H - 4.0), MSTheme.tint(VIOLET, 0.9))
	for t: HudText in [_mode_label, _drift_label, _out_label, _bank_label, _wrong_label, _finish_label]:
		if t.visible and t.text != "":
			_paint_skew_fill(c, Rect2(t.pos.x - POPUP_PAD_X, t.pos.y, t.width() + POPUP_PAD_X * 2.0, t.height()),
				MSTheme.tint(MSTheme.PLATE_BG, MSTheme.PLATE_BG.a * t.modulate.a))
	var strip: Rect2 = Rect2(strip_l, STRIP_Y, STRIP_W, STRIP_H)
	c.draw_rect(strip, MSTheme.tint(MSTheme.TEXT, 0.2))
	c.draw_rect(Rect2(strip_l, STRIP_Y, STRIP_W * _strip_p, STRIP_H), VIOLET)
	for r: ArcadeCar in _rivals:
		var rp: float = _race.get_lap_progress(r) if _race != null else 0.0
		c.draw_rect(Rect2(strip_l + STRIP_W * fposmod(rp, 1.0) - 1.5, STRIP_Y - 3.0, 3.0, STRIP_H + 6.0),
			MSTheme.tint(MSTheme.TEXT, 0.6))
	c.draw_circle(tc, TACH_PLATE_R, MSTheme.PLATE_BG)
	_minimap.paint_rects(c, mm_c)
	_nitro.paint_rects(c, nc)
	# Pass 2: lines.
	_speedo.paint_lines(c, tc)
	c.draw_multiline(SpeedGauge.ring_segments(gear_c, GEAR_R, 0.0, TAU, 32), GEAR_RING_COL, 2.0, true)
	_minimap.paint_lines(c, mm_c)
	_nitro.paint_lines(c, nc)
	# Pass 3: dots.
	_minimap.paint_dots(c, mm_c)
	c.draw_texture_rect(MiniMap._disc_texture(), Rect2(Vector2(strip_l + STRIP_W * _strip_p, STRIP_Y + STRIP_H * 0.5) - Vector2.ONE * STRIP_MARK_PX, Vector2.ONE * STRIP_MARK_PX * 2.0), false, MSTheme.TEXT)
	# Pass 4: text, outlines first.
	HudText.paint(c, _texts)


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


## Panel fill sheared like MSTheme.box(): a skewed rect keeps the rect batch (a quad polygon measured 6 draws more).
func _paint_skew_fill(c: CanvasItem, r: Rect2, col: Color = MSTheme.PANEL_BG) -> void:
	c.draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(PANEL_SKEW, 1.0), Vector2(-PANEL_SKEW * (r.position.y + r.size.y * 0.5), 0.0)))
	c.draw_rect(r, col)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)


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
		_connect(race.car_eliminated, _on_car_eliminated)
	_cars = _all_cars()
	_rivals.clear()
	for c: ArcadeCar in _cars:
		if c != car:
			_rivals.append(c)
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


## Every car of the race: from the race standings when the race is set up, else from get_cars(), plus the player.
func _all_cars() -> Array[ArcadeCar]:
	var out: Array[ArcadeCar] = []
	if _race == null:
		return out
	if _race.has_method("get_standings"):
		for row: Variant in _race.call("get_standings"):
			if row is Dictionary and row["car"] is ArcadeCar:
				out.append(row["car"])
	if out.is_empty() and _race.has_method("get_cars"):
		for c: Variant in _race.call("get_cars"):
			if c is ArcadeCar:
				out.append(c as ArcadeCar)
	if _car != null and not out.has(_car):
		out.append(_car)
	return out


func _setup_minimap() -> void:
	if _track != null and _track.has_method("get_minimap_points"):
		_minimap.set_track(_points_from(_track.call("get_minimap_points")))
	_minimap.set_dot_count(1 + _rivals.size())
	var track_title: String = I18n.t("hud.track_name")
	var custom: Variant = _track.get("track_name") if _track != null else null
	if custom is String and custom != "":
		track_title = custom
	_set_text("track", _track_label, I18n.t("hud.track_info") % [track_title, _track_length() / 1000.0])


## Lap length in metres from the track, or the fallback when the track has none.
func _track_length() -> float:
	var v: Variant = _track.get("length") if _track != null else null
	if v is float and float(v) > 0.0:
		return float(v)
	return TRACK_LEN_FALLBACK


## Race standings in place order. Without a set-up race, the cars ordered by lap progress.
func _standings() -> Array:
	if not _online_rows.is_empty():
		return _online_rows
	var rows: Array = []
	if _race == null:
		return rows
	if _race.has_method("get_standings"):
		rows = _race.call("get_standings")
	if rows.is_empty():
		var len: float = _track_length()
		for i: int in _cars.size():
			var c: ArcadeCar = _cars[i]
			var label: String = I18n.t("hud.you") if c == _car else "%s %d" % [I18n.t("hud.rival"), i]
			rows.append({"car": c, "name": label, "place": 0, "distance": _race.get_lap_progress(c) * len})
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] > b["distance"])
		for i: int in rows.size():
			rows[i]["place"] = i + 1
	return rows


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
	_refresh_mode(delta)
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


## Centiseconds, the resolution of the race clock. Floor, same as fmt_time.
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
	var lap: int = _race.get_lap(_car)
	var laps_total: int = maxi(_race.total_laps, 1)
	var lap_p: float = _race.get_lap_progress(_car)
	_strip_p = fposmod(lap_p, 1.0)
	var timed: bool = _race.mode == RaceConfig.MODE_DRIFT
	var lap_changed: bool = _int_changed("lap", lap)
	var laps_changed: bool = _int_changed("laps_total", laps_total)
	if lap_changed or laps_changed:
		# A timed drift session has no laps: its clock and percent count the time limit instead.
		_set_text("lap", _lap_val, "" if timed else I18n.t("hud.lap_of") % [lap, laps_total])
	var pct: int = clampi(roundi((float(lap - 1) + lap_p) / float(laps_total) * 100.0), 0, 100)
	var clock_s: float = _race.race_time
	if timed:
		clock_s = maxf(_race.time_limit_s - _race.race_time, 0.0)
		pct = clampi(roundi(_race.race_time / maxf(_race.time_limit_s, 0.1) * 100.0), 0, 100)
	if _int_changed("pct", pct):
		_set_text("pct", _pct, I18n.t("hud.percent") % pct)
	if _int_changed("time", _centis(clock_s)):
		_set_text("time", _clock, fmt_time(clock_s))
	var total: int = _online_rows.size() if not _online_rows.is_empty() else _race.get_car_count()
	if _int_changed("car_count", total):
		_set_text("position_total", _pos_total, I18n.t("hud.of") % total)
	_refresh_position()
	_refresh_leaderboard()


func _refresh_position() -> void:
	var pos: int = _online_place() if not _online_rows.is_empty() else _race.get_position(_car)
	if _int_changed("position", pos):
		_set_text("position", _pos_num, str(pos))


## Place of the player in the online order (the race only knows the local car online).
func _online_place() -> int:
	for row: Dictionary in _online_rows:
		if row["car"] == _car:
			return int(row["place"])
	return _race.get_position(_car)


## Online race: the server's live order replaces the race's own standings, which hold only the local car.
func set_online_rows(rows: Array) -> void:
	_online_rows = rows


## Four rows around the player: the window starts one place above the player, or at the top of the order.
func _refresh_leaderboard() -> void:
	var rows: Array = _standings()
	var n: int = rows.size()
	_me_row = -1
	if n == 0:
		return
	var me: int = 0
	for i: int in n:
		if rows[i]["car"] == _car:
			me = i
	var start: int = clampi(me - 1, 0, maxi(n - LB_ROWS, 0))
	var my_d: float = float(rows[me]["distance"])
	var v: float = maxf(_car.speed_kmh / 3.6, GAP_MIN_MS)
	for i: int in LB_ROWS:
		var show: bool = start + i < n
		_lb_place[i].visible = show
		_lb_name[i].visible = show
		_lb_gap[i].visible = show
		if not show:
			continue
		var row: Dictionary = rows[start + i]
		var mine: bool = start + i == me
		if mine:
			_me_row = i
		var shown_name: String = I18n.t("hud.you") if mine else str(row["name"])
		_lb_place[i].set_text(str(int(row["place"])))
		_lb_name[i].set_text(shown_name.left(LB_NAME_CHARS))
		var out: bool = _race != null and _race.is_eliminated(row["car"] as ArcadeCar)
		_lb_gap[i].set_text(I18n.t("hud.out_tag") if out else "0.00" if mine else _gap_text(float(row["distance"]) - my_d, v))
		_lb_gap[i].color = MSTheme.TEXT if mine else MSTheme.MUTED


## Gap in seconds from the player. A row ahead (more distance) reads "-", a row behind reads "+".
static func _gap_text(ahead_m: float, speed_ms: float) -> String:
	var t: float = minf(absf(ahead_m) / speed_ms, 99.99)
	return ("-" if ahead_m > 0.0 else "+") + "%.2f" % t


## Heading up minimap: the player's forward direction on the map plane, and every rival's lap progress.
func _refresh_minimap() -> void:
	var fwd: Vector3 = -(_car.global_transform.basis.z if _car.is_inside_tree() else _car.transform.basis.z)
	_minimap.set_forward(Vector2(fwd.x, fwd.z))
	_minimap.set_dot(0, _race.get_lap_progress(_car), true)
	for i: int in _rivals.size():
		# An eliminated car is frozen on the track: hide its dot rather than leave it stuck there.
		var out: bool = _race.is_eliminated(_rivals[i])
		_minimap.set_dot(i + 1, _race.get_lap_progress(_rivals[i]), false, not out)


## Drift: the banked score and the running chain. Elimination: cars left, and the car that just went out.
func _refresh_mode(delta: float) -> void:
	var mode: String = _race.mode if _race != null else RaceConfig.MODE_RACE
	if mode == RaceConfig.MODE_DRIFT:
		var text: String = "%s  %s" % [I18n.t("mode.drift"), group_int(int(_race.drift_score_now()))]
		if _car.is_drifting:
			text += "  ·  %s +%s" % [I18n.t("hud.chain"), group_int(int(_car.drift_score))]
		_set_text("mode", _mode_label, text)
		_mode_label.visible = true
	elif mode == RaceConfig.MODE_ELIMINATION:
		_set_text("mode", _mode_label, I18n.t("hud.cars_left") % [_race.active_count(), _race.get_car_count()])
		_mode_label.visible = true
	else:
		_mode_label.visible = false
	_out_t = maxf(_out_t - delta, 0.0)
	_out_label.visible = _out_t > 0.0


func _on_car_eliminated(_car_out: ArcadeCar, place: int) -> void:
	_set_text("out", _out_label, I18n.t("hud.out") % ("%d%s" % [place, I18n.ordinal(place)]))
	_out_t = OUT_SHOW_S


func _refresh_drift() -> void:
	# A timed drift session shows the chain in the mode readout instead of a second popup.
	var drifting: bool = _car.is_drifting and (_race == null or _race.mode != RaceConfig.MODE_DRIFT)
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
	_countdown.scale = COUNTDOWN_BASE * COUNTDOWN_PUNCH
	if _countdown_tw != null and _countdown_tw.is_valid():
		_countdown_tw.kill()
	_countdown_tw = create_tween()
	_countdown_tw.tween_property(_countdown, "scale", COUNTDOWN_BASE, COUNTDOWN_PUNCH_S) \
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
	if _shown.has(key) and _shown[key] == text:  # has(): a first "" must still clear the label's initial text
		return
	_shown[key] = text
	label.set_text(text)


## mm:ss.cc, the layout the race clock uses.
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
