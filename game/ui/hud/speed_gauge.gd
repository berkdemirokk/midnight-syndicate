class_name SpeedGauge
extends Control
## Arc tachometer: rpm sweep with a redline band. Draws only; speed, gear and unit labels are children of RaceHUD.

@export var start_deg: float = 135.0  ## bottom-left, clockwise in screen space
@export var sweep_deg: float = 270.0
@export var redline_norm: float = 0.85
@export var radius_px: float = 120.0
@export var arc_width_px: float = 12.0
@export var tick_count: int = 9
@export var tick_len_px: float = 10.0
@export var centre_y_px: float = 120.0

var rpm_norm: float = 0.0


func set_rpm(v: float) -> void:
	var clamped: float = clampf(v, 0.0, 1.0)
	if is_equal_approx(clamped, rpm_norm):
		return
	rpm_norm = clamped
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = Vector2(size.x * 0.5, centre_y_px)
	var a0: float = deg_to_rad(start_deg)
	var a_full: float = deg_to_rad(sweep_deg)
	draw_arc(c, radius_px, a0, a0 + a_full, 96, MSTheme.tint(MSTheme.MUTED, 0.25), arc_width_px, true)
	var red0: float = a0 + a_full * redline_norm
	var a_rpm: float = a0 + a_full * rpm_norm
	if rpm_norm > 0.0:
		draw_arc(c, radius_px, a0, minf(a_rpm, red0), 96, MSTheme.CYAN, arc_width_px, true)
	if rpm_norm > redline_norm:
		draw_arc(c, radius_px, red0, a_rpm, 32, MSTheme.DANGER, arc_width_px, true)
	draw_arc(c, radius_px, red0, a0 + a_full, 32, MSTheme.tint(MSTheme.DANGER, 0.5), 2.0, true)
	for i: int in tick_count:
		var t: float = float(i) / float(tick_count - 1)
		var a: float = a0 + a_full * t
		var dir: Vector2 = Vector2(cos(a), sin(a))
		var p0: Vector2 = c + dir * (radius_px - arc_width_px * 0.5 - tick_len_px)
		var p1: Vector2 = c + dir * (radius_px - arc_width_px * 0.5 - 2.0)
		draw_line(p0, p1, MSTheme.tint(MSTheme.TEXT, 0.5), 2.0, true)
