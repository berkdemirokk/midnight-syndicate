class_name TouchControls
extends CanvasLayer
## On-screen controls for a PlayerDriver. Bottom-left: two steer zones above the minimap. Bottom-right: brake pedal
## above the tachometer, nitro and drift above the pedal. Top centre: the pause button, beside the lap strip.
## Every zone keeps clear of the HUD gauges (minimap, tachometer, nitro) by the RaceHUD offsets.
signal pause_pressed

enum Zone { NONE, STEER_LEFT, STEER_RIGHT, BRAKE, NITRO, DRIFT }

const ZONE_COUNT: int = 6
const MIN_DIV: float = 0.0001  ## divisor floor, not a tunable
const PAUSE_SIDE_PX: float = 88.0  ## the pause button at 1080 px; on a phone the 44 pt target (MSTheme.button_h) is larger
const PAUSE_GAP_PX: float = 16.0  ## between the lap strip and the pause button
@export var force_visible: bool = false  ## show even when the device reports no touchscreen
@export var margin_px: float = 24.0
@export var steer_width_frac: float = 0.22  ## each steer zone, fraction of the usable width
@export var pedal_width_frac: float = 0.2
@export var zone_height_frac: float = 0.36  ## steer zones and pedal, fraction of the usable height
@export var button_size_frac: float = 0.12  ## nitro and drift, fraction of the smaller usable side
@export var idle_color: Color = Color(1.0, 1.0, 1.0, 0.12)
@export var pressed_color: Color = Color(1.0, 1.0, 1.0, 0.35)
@export var label_color: Color = Color(1.0, 1.0, 1.0, 0.55)
@export var label_size: int = 28

var _driver: PlayerDriver = null
var _pad: Control = null
var _pause_btn: Button = null
var _rects: Array[Rect2] = []
var _touches: Dictionary = {}  ## touch index -> Zone
var _held_mask: int = 0  ## bit z set when zone z is held, for the redraw without allocating


func _ready() -> void:
	visible = force_visible or DisplayServer.is_touchscreen_available()
	_rects.resize(ZONE_COUNT)
	_pad = Control.new()
	add_child(_pad)
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.draw.connect(_on_pad_draw)
	_pause_btn = Button.new()
	_pause_btn.name = "PauseButton"
	_pause_btn.tooltip_text = I18n.t("touch.pause")
	_pause_btn.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed", "focus"]:
		_pause_btn.add_theme_stylebox_override(state, MSTheme.card(MSTheme.PLATE_BG, MSTheme.CYAN, 2))
	_pause_btn.draw.connect(_on_pause_draw)
	_pause_btn.pressed.connect(func() -> void: pause_pressed.emit())
	add_child(_pause_btn)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()


## Emits to this driver from now on.
func bind(driver: PlayerDriver) -> void:
	_driver = driver
	_push()


## Zone rectangle in viewport pixels (Rect2() before the first layout).
func get_zone_rect(zone: int) -> Rect2:
	return _rects[zone]


## Pause button rectangle in viewport pixels.
func get_pause_rect() -> Rect2:
	return _pause_btn.get_rect()


func _exit_tree() -> void:
	_touches.clear()
	_push()


## A paused tree stops _input, so releases during the pause menu or in the background are lost: drop every held touch.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_touches.clear()
		_push()


func _input(event: InputEvent) -> void:
	if not visible or _driver == null:
		return
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			var z: int = _zone_at(st.position)
			if z != Zone.NONE:
				_touches[st.index] = z
				_push()
		elif _touches.erase(st.index):
			_push()
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		if _touches.has(sd.index):
			var z2: int = _zone_at(sd.position)
			var is_steer: bool = z2 == Zone.STEER_LEFT or z2 == Zone.STEER_RIGHT
			if is_steer and _touches[sd.index] != z2:
				_touches[sd.index] = z2
				_push()


func _on_viewport_resized() -> void:
	_layout(get_viewport().get_visible_rect().size)
	_push()


func _layout(vp: Vector2) -> void:
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var usable: Rect2 = _usable_rect(vp)
	var m: float = margin_px
	var uw: float = usable.size.x
	var uh: float = usable.size.y
	var k: float = RaceHUD.hud_scale()
	# HUD gauge boxes in viewport pixels, from the RaceHUD offsets (they scale with the HUD frame).
	var mm_h: float = (RaceHUD.MM_PAD * 2.0 + RaceHUD.MM_R * 2.0) * k  ## minimap, bottom left
	var tach_h: float = (RaceHUD.TACH_OFF_Y + RaceHUD.TACH_PLATE_R) * k  ## tachometer plate, bottom right
	var zone_h: float = uh * zone_height_frac
	var zone_w: float = uw * steer_width_frac
	var left_x: float = usable.position.x + m
	var steer_bottom: float = usable.end.y - mm_h - m
	var pedal_w: float = uw * pedal_width_frac
	var pedal_bottom: float = usable.end.y - tach_h - m
	var btn: float = minf(uw, uh) * button_size_frac
	var brake := Rect2(usable.end.x - m - pedal_w, pedal_bottom - zone_h, pedal_w, zone_h)
	# Nitro and drift stack in the gap left of the pedal, bottom-aligned with it: the top corners hold the HUD clock.
	var nitro := Rect2(brake.position.x - m - btn, brake.end.y - btn, btn, btn)
	var drift := Rect2(nitro.position.x, nitro.position.y - m - btn, btn, btn)
	_rects[Zone.NONE] = Rect2()
	_rects[Zone.STEER_LEFT] = Rect2(left_x, steer_bottom - zone_h, zone_w, zone_h)
	_rects[Zone.STEER_RIGHT] = Rect2(left_x + zone_w + m, steer_bottom - zone_h, zone_w, zone_h)
	_rects[Zone.BRAKE] = brake
	_rects[Zone.NITRO] = nitro
	_rects[Zone.DRIFT] = drift
	# Beside the lap strip, right of centre; the position board and the clock keep the two top corners.
	var side: float = maxf(PAUSE_SIDE_PX, MSTheme.button_h())
	var strip_edge: float = (RaceHUD.STRIP_W * 0.5 + RaceHUD.PLATE_PAD + PAUSE_GAP_PX) * k
	_pause_btn.position = Vector2(vp.x * 0.5 + strip_edge, usable.position.y + m * 0.5)
	_pause_btn.size = Vector2(side, side)


## The display safe area in viewport pixels; the whole pad when the platform reports none.
func _usable_rect(vp: Vector2) -> Rect2:
	var screen: Vector2 = Vector2(DisplayServer.screen_get_size())
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if screen.x <= 0.0 or screen.y <= 0.0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Rect2(Vector2.ZERO, vp)
	var k: Vector2 = vp / screen
	return Rect2(Vector2(safe.position) * k, Vector2(safe.size) * k)


func _zone_at(p: Vector2) -> int:
	for z: int in range(1, ZONE_COUNT):
		if _rects[z].has_point(p):
			return z
	return Zone.NONE


## Recomputes the four driver values from the touches held and redraws.
func _push() -> void:
	var left: int = 0
	var right: int = 0
	var brake: bool = false
	var nitro: bool = false
	var drift: bool = false
	_held_mask = 0
	for z: Variant in _touches.values():
		_held_mask |= 1 << int(z)
		match int(z):
			Zone.STEER_LEFT:
				left += 1
			Zone.STEER_RIGHT:
				right += 1
			Zone.BRAKE:
				brake = true
			Zone.NITRO:
				nitro = true
			Zone.DRIFT:
				drift = true
	if _driver != null and is_instance_valid(_driver):
		_driver.set_touch_steer(float(right - left))
		_driver.set_touch_brake(brake)
		_driver.set_touch_nitro(nitro)
		_driver.set_touch_handbrake(drift)
	if _pad != null and is_instance_valid(_pad):
		_pad.queue_redraw()


func _on_pad_draw() -> void:
	var font: Font = ThemeDB.fallback_font
	for z: int in range(1, ZONE_COUNT):
		var r: Rect2 = _rects[z]
		if r.size == Vector2.ZERO:
			continue
		_pad.draw_rect(r, pressed_color if ((_held_mask >> z) & 1) == 1 else idle_color)
		var label_pos := Vector2(r.position.x, r.position.y + r.size.y * 0.5 + label_size * 0.35)
		_pad.draw_string(font, label_pos, _label(z), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, label_size, label_color)


## Steer arrows stay as glyphs; the pedal labels go through I18n.
func _label(zone: int) -> String:
	match zone:
		Zone.STEER_LEFT:
			return "<"
		Zone.STEER_RIGHT:
			return ">"
		Zone.BRAKE:
			return I18n.t("touch.brake")
		Zone.NITRO:
			return I18n.t("touch.nitro")
		Zone.DRIFT:
			return I18n.t("touch.drift")
	return ""


## Two bars and no text, so the pause glyph needs no translation.
func _on_pause_draw() -> void:
	var s: Vector2 = _pause_btn.size
	var bar: Vector2 = Vector2(s.x * 0.14, s.y * 0.42)
	var y: float = s.y * 0.29
	_pause_btn.draw_rect(Rect2(Vector2(s.x * 0.31, y), bar), MSTheme.CYAN)
	_pause_btn.draw_rect(Rect2(Vector2(s.x * 0.55, y), bar), MSTheme.CYAN)
