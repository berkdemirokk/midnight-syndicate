class_name SpeedGauge
extends RefCounted
## Arc tachometer geometry: rpm sweep with a redline band and tick marks. It paints into the HUD's own canvas
## (RaceHUD._paint), as thick line segments, so the whole gauge shares the HUD's single line batch.
## Speed, gear and unit text are HudText items of RaceHUD.

const ARC_STEPS: int = 96  ## segments over the full sweep
const JOIN_PX: float = 0.6  ## segments overlap by this much so no seam shows (needs opaque colours: alpha would bead)
## Opaque stand-ins for MUTED at 25 percent and DANGER at 50 percent over the night scene. Translucent segments
## double-blend where they overlap and their AA ends leave seams, so the arc track and the redline are pre-blended.
const TRACK_COL: Color = Color(0.18, 0.205, 0.253)
const REDLINE_COL: Color = Color(0.53, 0.156, 0.154)

var start_deg: float = 135.0  ## bottom-left, clockwise in screen space
var sweep_deg: float = 270.0
var redline_norm: float = 0.85
var radius_px: float = 120.0
var arc_width_px: float = 12.0
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
	_arc(c, centre, a0, a0 + a_full, TRACK_COL, arc_width_px, JOIN_PX)
	if rpm_norm > 0.0:
		_arc(c, centre, a0, minf(a_rpm, red0), MSTheme.CYAN, arc_width_px, JOIN_PX)
	if rpm_norm > redline_norm:
		_arc(c, centre, red0, a_rpm, MSTheme.DANGER, arc_width_px, JOIN_PX)
	_arc(c, centre, red0, a0 + a_full, REDLINE_COL, 2.0, JOIN_PX)
	var tick_col: Color = MSTheme.tint(MSTheme.TEXT, 0.5)
	for i: int in tick_count:
		var a: float = a0 + a_full * float(i) / float(tick_count - 1)
		var dir: Vector2 = Vector2(cos(a), sin(a))
		c.draw_line(centre + dir * (radius_px - arc_width_px * 0.5 - tick_len_px),
			centre + dir * (radius_px - arc_width_px * 0.5 - 2.0), tick_col, 2.0, true)


func _arc(c: CanvasItem, centre: Vector2, a_from: float, a_to: float, col: Color, width: float, join: float) -> void:
	var span: float = a_to - a_from
	if span <= 0.0:
		return
	var steps: int = maxi(ceili(float(ARC_STEPS) * span / deg_to_rad(sweep_deg)), 1)
	var prev: Vector2 = centre + Vector2(cos(a_from), sin(a_from)) * radius_px
	for i: int in range(1, steps + 1):
		var a: float = a_from + span * float(i) / float(steps)
		var p: Vector2 = centre + Vector2(cos(a), sin(a)) * radius_px
		var chord: Vector2 = (p - prev).normalized() * join
		c.draw_line(prev - chord, p + chord, col, width, true)
		prev = p
