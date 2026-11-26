class_name NitroBar
extends RefCounted
## Round nitro button: a ring that fills clockwise with the tank, a lightning mark in the middle.
## The ring glows while nitro is firing and pulses when the tank is full. Painted into the HUD's own canvas:
## the disc in the rect pass, the ring, glow and mark in the line pass.

const FULL_EPS: float = 0.999
const PULSE_HZ: float = 4.0
const VIOLET: Color = Color(0.706, 0.361, 1.0)  ## #B45CFF, the HUD accent
const TRACK_RING_COL: Color = Color(0.14, 0.15, 0.18)  ## empty ring, pre-blended (translucent chords bead)
const GLOW_RING_COL: Color = Color(0.38, 0.2, 0.52)  ## violet glow while firing, pre-blended
const BOLT_UNITS: Array[Vector2] = [Vector2(0.18, -0.55), Vector2(-0.22, 0.08), Vector2(0.04, 0.08),
	Vector2(-0.18, 0.55), Vector2(0.24, -0.06), Vector2(-0.02, -0.06)]  ## in units of the radius, from the centre

var radius_px: float = 50.0
var ring_px: float = 9.0
var amount: float = 0.0
var active: bool = false
var _pulse_t: float = 0.0


func set_state(value: float, firing: bool, t_s: float) -> void:
	amount = clampf(value, 0.0, 1.0)
	active = firing
	_pulse_t = t_s


func paint_rects(c: CanvasItem, centre: Vector2) -> void:
	c.draw_circle(centre, radius_px + ring_px, MSTheme.PLATE_BG)


## Each ring and the bolt are one draw_multiline: one draw call each (see SpeedGauge.ring_segments).
func paint_lines(c: CanvasItem, centre: Vector2) -> void:
	var a0: float = -PI * 0.5
	c.draw_multiline(SpeedGauge.ring_segments(centre, radius_px, 0.0, TAU, 64), TRACK_RING_COL, ring_px, true)
	var col: Color = MSTheme.CYAN.lightened(0.35) if active else MSTheme.CYAN
	if amount >= FULL_EPS:
		col = MSTheme.tint(col, 0.6 + 0.4 * sin(_pulse_t * TAU * PULSE_HZ))
	if amount > 0.0:
		c.draw_multiline(SpeedGauge.ring_segments(centre, radius_px, a0, a0 + TAU * amount, 64), col, ring_px, true)
	if active:
		c.draw_multiline(SpeedGauge.ring_segments(centre, radius_px + ring_px * 0.5 + 3.0, 0.0, TAU, 64),
			GLOW_RING_COL, 4.0, true)
	var bolt_col: Color = MSTheme.TEXT if amount > 0.0 else MSTheme.tint(MSTheme.TEXT, 0.35)
	var bolt := PackedVector2Array()
	for i: int in range(1, BOLT_UNITS.size()):
		bolt.append(centre + BOLT_UNITS[i - 1] * radius_px * 0.8)
		bolt.append(centre + BOLT_UNITS[i] * radius_px * 0.8)
	c.draw_multiline(bolt, bolt_col, 4.0, true)
