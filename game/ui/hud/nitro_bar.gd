class_name NitroBar
extends Control
## Segmented nitro meter. Glows while nitro is firing; pulses when the tank is full.

@export var segments: int = 12
@export var gap_px: float = 4.0
@export var pulse_hz: float = 4.0
@export var glow_px: float = 4.0

const FULL_EPS: float = 0.999

var amount: float = 0.0
var active: bool = false
var _pulse_t: float = 0.0
var _last_amount: float = -1.0
var _last_active: bool = false


func set_state(value: float, firing: bool, t_s: float) -> void:
	var v: float = clampf(value, 0.0, 1.0)
	_pulse_t = t_s
	var full: bool = v >= FULL_EPS
	if is_equal_approx(v, _last_amount) and firing == _last_active and not firing and not full:
		return
	amount = v
	active = firing
	_last_amount = v
	_last_active = firing
	queue_redraw()


func _process(_delta: float) -> void:
	# Redraw every frame only while the glow or pulse is animating.
	if active or amount >= FULL_EPS:
		queue_redraw()


func _draw() -> void:
	var seg_w: float = (size.x - gap_px * float(segments - 1)) / float(segments)
	var lit: float = amount * float(segments)
	var full: bool = amount >= FULL_EPS
	var col: Color = MSTheme.CYAN
	if active:
		col = col.lightened(0.35)
	var pulse: float = 1.0
	if full:
		pulse = 0.6 + 0.4 * sin(_pulse_t * TAU * pulse_hz)
	for i: int in segments:
		var x: float = float(i) * (seg_w + gap_px)
		var fill: float = clampf(lit - float(i), 0.0, 1.0)
		draw_rect(Rect2(x, 0.0, seg_w, size.y), MSTheme.tint(MSTheme.TEXT, 0.08))
		if fill > 0.0:
			draw_rect(Rect2(x, 0.0, seg_w * fill, size.y), MSTheme.tint(col, pulse))
		if active and fill > 0.0:
			draw_rect(Rect2(x, 0.0, seg_w, size.y).grow(glow_px), MSTheme.tint(col, 0.18), false, 2.0)
