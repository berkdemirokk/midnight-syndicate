class_name SpeedGauge
extends RefCounted
## Round tachometer geometry: rpm sweep with a redline band and tick marks. It paints into the HUD's own canvas
## (RaceHUD._paint). Each arc is one draw_arc command and the ticks are one draw_multiline, so the gauge costs a
## handful of draw calls; one draw_line per segment cost about twenty. The scale numbers and the speed are HudText.

const ARC_POINTS_PER_TURN: int = 120  ## arc segments for a full sweep, scaled by the arc span
const JOIN_PX: float = 0.6  ## segments overlap by this much so no seam shows (needs opaque colours: alpha beads)
## Opaque stand-ins for MUTED at 25 percent and DANGER at 50 percent over the night scene. Pre-blended so the arc
## pieces do not double-blend where they meet at their antialiased ends.
const TRACK_COL: Color = Color(0.18, 0.205, 0.253)
const REDLINE_COL: Color = Color(0.53, 0.156, 0.154)

var start_deg: float = 135.0  ## bottom-left, clockwise in screen space
var sweep_deg: float = 270.0
var redline_norm: float = 0.85
var radius_px: float = 132.0
var arc_width_px: float = 14.0
var tick_count: int = 9
var tick_len_px: float = 10.0
var rpm_norm: float = 0.0


func set_rpm(v: float) -> void:
	rpm_norm = clampf(v, 0.0, 1.0)


func paint_lines(c: CanvasItem, centre: Vector2) -> void:
	var a0: float = deg_to_rad(start_deg)
	var a_full: float = deg_to_rad(sweep_deg)
	var red0: float = a0 + a_full * redline_norm
	var a_rpm: float = a0 + a_full * rpm_norm
	_arc(c, centre, a0, a0 + a_full, TRACK_COL, arc_width_px)
	if rpm_norm > 0.0:
		_arc(c, centre, a0, minf(a_rpm, red0), MSTheme.CYAN, arc_width_px)
	if rpm_norm > redline_norm:
		_arc(c, centre, red0, a_rpm, MSTheme.DANGER, arc_width_px)
	_arc(c, centre, red0, a0 + a_full, REDLINE_COL, 2.0)
	var ticks := PackedVector2Array()
	for i: int in tick_count:
		var a: float = a0 + a_full * float(i) / float(tick_count - 1)
		var dir: Vector2 = Vector2(cos(a), sin(a))
		ticks.append(centre + dir * (radius_px - arc_width_px * 0.5 - tick_len_px))
		ticks.append(centre + dir * (radius_px - arc_width_px * 0.5 - 2.0))
	c.draw_multiline(ticks, MSTheme.tint(MSTheme.TEXT, 0.5), 2.0, true)


func _arc(c: CanvasItem, centre: Vector2, a_from: float, a_to: float, col: Color, width: float) -> void:
	var span: float = a_to - a_from
	if span <= 0.0:
		return
	var steps: int = maxi(ceili(float(ARC_POINTS_PER_TURN) * span / deg_to_rad(sweep_deg)), 1)
	c.draw_multiline(ring_segments(centre, radius_px, a_from, a_to, steps), col, width, true)


## Chord pairs along an arc, overlapping by JOIN_PX so no seam shows. One draw_multiline is one draw call;
## draw_arc and one draw_line per segment each cost a draw call of their own.
static func ring_segments(centre: Vector2, radius: float, a_from: float, a_to: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var prev: Vector2 = centre + Vector2(cos(a_from), sin(a_from)) * radius
	for i: int in range(1, steps + 1):
		var a: float = a_from + (a_to - a_from) * float(i) / float(steps)
		var p: Vector2 = centre + Vector2(cos(a), sin(a)) * radius
		var chord: Vector2 = (p - prev).normalized() * JOIN_PX
		out.append(prev - chord)
		out.append(p + chord)
		prev = p
	return out
