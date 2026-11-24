class_name TouchControls
extends CanvasLayer
## On-screen controls for a PlayerDriver. Bottom-left: two steer zones. Bottom-right: brake pedal.
## Above the pedal: nitro and drift (handbrake). Touches are tracked by index in _input, so several
## fingers work together. The layout stays inside the display safe area.

enum Zone { NONE, STEER_LEFT, STEER_RIGHT, BRAKE, NITRO, DRIFT }

const ZONE_COUNT: int = 6
const LABELS: PackedStringArray = ["", "<", ">", "BRAKE", "NITRO", "DRIFT"]
const MIN_DIV: float = 0.0001  ## divisor floor, not a tunable

@export var force_visible: bool = false  ## show even when the device reports no touchscreen
@export var margin_px: float = 24.0
@export var steer_width_frac: float = 0.22  ## each steer zone, fraction of the usable width
@export var pedal_width_frac: float = 0.2
@export var zone_height_frac: float = 0.42  ## steer zones and pedal, fraction of the usable height
@export var button_size_frac: float = 0.12  ## nitro and drift, fraction of the smaller usable side
@export var idle_color: Color = Color(1.0, 1.0, 1.0, 0.12)
@export var pressed_color: Color = Color(1.0, 1.0, 1.0, 0.35)
@export var label_color: Color = Color(1.0, 1.0, 1.0, 0.55)
@export var label_size: int = 28

var _driver: PlayerDriver = null
var _pad: Control = null
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
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()


func _exit_tree() -> void:
	_touches.clear()
	_push()


## Emits to this driver from now on.
func bind(driver: PlayerDriver) -> void:
	_driver = driver
	_push()


## Zone rectangle in viewport pixels (Rect2() before the first layout).
func get_zone_rect(zone: int) -> Rect2:
	return _rects[zone]


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
	var zone_h: float = uh * zone_height_frac
	var base_y: float = usable.end.y - m - zone_h
	var zone_w: float = uw * steer_width_frac
	var left_x: float = usable.position.x + m
	var pedal_w: float = uw * pedal_width_frac
	var btn: float = minf(uw, uh) * button_size_frac
	var brake := Rect2(usable.end.x - m - pedal_w, base_y, pedal_w, zone_h)
	var nitro := Rect2(brake.end.x - btn, brake.position.y - m - btn, btn, btn)
	var drift := Rect2(nitro.position.x - m - btn, nitro.position.y, btn, btn)
	_rects[Zone.NONE] = Rect2()
	_rects[Zone.STEER_LEFT] = Rect2(left_x, base_y, zone_w, zone_h)
	_rects[Zone.STEER_RIGHT] = Rect2(left_x + zone_w + m, base_y, zone_w, zone_h)
	_rects[Zone.BRAKE] = brake
	_rects[Zone.NITRO] = nitro
	_rects[Zone.DRIFT] = drift


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
		_pad.draw_string(font, label_pos, LABELS[z], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, label_size, label_color)
