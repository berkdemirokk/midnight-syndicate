class_name NitroBar
extends RefCounted
## Segmented nitro meter. Glows while nitro is firing; pulses when the tank is full.
## Paints into the HUD's own canvas: segment rects in the rect pass, the firing glow in the line pass.

const FULL_EPS: float = 0.999

var segments: int = 12
var gap_px: float = 4.0
var pulse_hz: float = 4.0
var glow_px: float = 4.0
var amount: float = 0.0
var active: bool = false
var _pulse_t: float = 0.0


func set_state(value: float, firing: bool, t_s: float) -> void:
	amount = clampf(value, 0.0, 1.0)
	active = firing
	_pulse_t = t_s


func paint_rects(c: CanvasItem, r: Rect2) -> void:
	var seg_w: float = (r.size.x - gap_px * float(segments - 1)) / float(segments)
	var lit: float = amount * float(segments)
	var full: bool = amount >= FULL_EPS
	var col: Color = MSTheme.CYAN
	if active:
		col = col.lightened(0.35)
	var pulse: float = 1.0
	if full:
		pulse = 0.6 + 0.4 * sin(_pulse_t * TAU * pulse_hz)
	var bg: Color = MSTheme.tint(MSTheme.TEXT, 0.08)
	for i: int in segments:
		var x: float = r.position.x + float(i) * (seg_w + gap_px)
		c.draw_rect(Rect2(x, r.position.y, seg_w, r.size.y), bg)
		var fill: float = clampf(lit - float(i), 0.0, 1.0)
		if fill > 0.0:
			c.draw_rect(Rect2(x, r.position.y, seg_w * fill, r.size.y), MSTheme.tint(col, pulse))


func paint_lines(c: CanvasItem, r: Rect2) -> void:
	if not active:
		return
	var seg_w: float = (r.size.x - gap_px * float(segments - 1)) / float(segments)
	var lit: float = amount * float(segments)
	var glow: Color = MSTheme.tint(MSTheme.CYAN.lightened(0.35), 0.18)
	for i: int in segments:
		if lit - float(i) <= 0.0:
			continue
		var box: Rect2 = Rect2(r.position.x + float(i) * (seg_w + gap_px), r.position.y, seg_w, r.size.y).grow(glow_px)
		var tl: Vector2 = box.position
		var tr: Vector2 = Vector2(box.end.x, box.position.y)
		var br: Vector2 = box.end
		var bl: Vector2 = Vector2(box.position.x, box.end.y)
		c.draw_multiline(PackedVector2Array([tl, tr, tr, br, br, bl, bl, tl]), glow, 2.0, true)
