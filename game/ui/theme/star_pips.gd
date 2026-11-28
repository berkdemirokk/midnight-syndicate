extends Control
## Star rating drawn as polygons (the brand fonts have no star glyph): `earned` filled GOLD of `count`, the rest as
## titanium outlines. Size follows the font size it is given. preload("res://ui/theme/star_pips.gd").new(px)

var count: int = 3
var earned: int = 0
var px: float = 20.0


func _init(size_px: float = 20.0, total: int = 3) -> void:
	px = size_px
	count = total
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(px * float(count) + px * 0.3 * float(count - 1), px)


func set_earned(n: int) -> void:
	earned = clampi(n, 0, count)
	queue_redraw()


static func star_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in 10:
		var a: float = -PI * 0.5 + float(i) * PI / 5.0
		var rr: float = r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts


func _draw() -> void:
	for i: int in count:
		var c := Vector2(px * 0.5 + float(i) * px * 1.3, px * 0.54)
		var pts: PackedVector2Array = star_points(c, px * 0.5)
		if i < earned:
			draw_colored_polygon(pts, MSTheme.GOLD)
		else:
			var loop: PackedVector2Array = pts.duplicate()
			loop.append(pts[0])
			draw_polyline(loop, MSTheme.tint(MSTheme.TITANIUM, 0.45), maxf(1.0, px * 0.07), true)
