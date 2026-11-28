extends Control
## STREET EMPIRE line icons drawn in code (no icon font, no image files): crisp at any size, tinted by `colour`.
## kinds: speed, accel, grip, nitro, brush, rim, upgrade, flag, wallet, check, slashes, back.
## preload("res://ui/theme/ui_icon.gd").new("speed", 28.0, MSTheme.TITANIUM)

var kind: String = "speed"
var colour: Color = Color.WHITE
var px: float = 24.0


func _init(k: String = "speed", size_px: float = 24.0, col: Color = Color.WHITE) -> void:
	kind = k
	px = size_px
	colour = col
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(px * (1.6 if k == "slashes" else 1.0), px)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func set_colour(c: Color) -> void:
	colour = c
	queue_redraw()


## The same drawing baked into a texture (Button.icon needs one).
static func texture(k: String, size_px: int, col: Color) -> ImageTexture:
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if k == "flag":
		var cell: int = maxi(size_px / 6, 2)
		for y: int in range(size_px / 8, size_px * 5 / 8):
			for x: int in range(size_px / 6, size_px):
				var cx: int = (x - size_px / 6) / cell
				var cy: int = (y - size_px / 8) / cell
				img.set_pixel(x, y, col if (cx + cy) % 2 == 0 else Color(col.r, col.g, col.b, 0.25))
		for y: int in range(size_px / 8, size_px):
			for x: int in range(size_px / 10, size_px / 10 + maxi(size_px / 16, 2)):
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	var s: float = px
	var w: float = maxf(1.5, s * 0.085)
	var c := Vector2(s * 0.5, s * 0.5)
	match kind:
		"speed":
			draw_arc(c + Vector2(0, s * 0.08), s * 0.42, PI * 0.8, PI * 2.2, 24, colour, w, true)
			draw_line(c + Vector2(0, s * 0.08), c + Vector2(s * 0.24, -s * 0.16), colour, w, true)
			draw_circle(c + Vector2(0, s * 0.08), w * 1.1, colour)
		"accel":
			for i: int in 2:
				var x0: float = s * (0.12 + 0.34 * float(i))
				draw_polyline(PackedVector2Array([Vector2(x0, s * 0.18), Vector2(x0 + s * 0.3, s * 0.5), Vector2(x0, s * 0.82)]), colour, w, true)
		"grip":
			draw_arc(c, s * 0.42, 0.0, TAU, 32, colour, w, true)
			draw_circle(c, s * 0.12, colour)
			for a: float in [PI * 0.5, PI * 1.17, PI * 1.83]:
				draw_line(c, c + Vector2(cos(a), sin(a)) * s * 0.4, colour, w, true)
		"nitro":
			draw_colored_polygon(PackedVector2Array([Vector2(s * 0.58, s * 0.05), Vector2(s * 0.2, s * 0.56), Vector2(s * 0.47, s * 0.56),
				Vector2(s * 0.38, s * 0.95), Vector2(s * 0.8, s * 0.4), Vector2(s * 0.52, s * 0.4)]), colour)
		"brush":
			draw_line(Vector2(s * 0.85, s * 0.12), Vector2(s * 0.42, s * 0.58), colour, w * 1.6, true)
			draw_colored_polygon(PackedVector2Array([Vector2(s * 0.38, s * 0.52), Vector2(s * 0.5, s * 0.64), Vector2(s * 0.3, s * 0.9), Vector2(s * 0.1, s * 0.92), Vector2(s * 0.16, s * 0.72)]), colour)
		"rim":
			draw_arc(c, s * 0.44, 0.0, TAU, 32, colour, w, true)
			draw_arc(c, s * 0.14, 0.0, TAU, 16, colour, w, true)
			for i: int in 5:
				var a: float = -PI * 0.5 + TAU * float(i) / 5.0
				draw_line(c + Vector2(cos(a), sin(a)) * s * 0.14, c + Vector2(cos(a), sin(a)) * s * 0.42, colour, w, true)
		"upgrade":
			for i: int in 2:
				var y0: float = s * (0.5 + 0.28 * float(i)) - s * 0.12
				draw_polyline(PackedVector2Array([Vector2(s * 0.15, y0), Vector2(s * 0.5, y0 - s * 0.3), Vector2(s * 0.85, y0)]), colour, w * 1.2, true)
		"wallet":
			draw_rect(Rect2(s * 0.08, s * 0.25, s * 0.84, s * 0.6), colour, false, w)
			draw_line(Vector2(s * 0.16, s * 0.25), Vector2(s * 0.7, s * 0.1), colour, w, true)
			draw_rect(Rect2(s * 0.6, s * 0.45, s * 0.32, s * 0.2), colour, false, w)
		"check":
			draw_polyline(PackedVector2Array([Vector2(s * 0.14, s * 0.52), Vector2(s * 0.4, s * 0.78), Vector2(s * 0.88, s * 0.22)]), colour, w * 1.4, true)
		"back":
			draw_polyline(PackedVector2Array([Vector2(s * 0.62, s * 0.15), Vector2(s * 0.28, s * 0.5), Vector2(s * 0.62, s * 0.85)]), colour, w * 1.4, true)
		"slashes":
			for i: int in 2:
				var x0: float = s * (0.1 + 0.62 * float(i))
				draw_colored_polygon(PackedVector2Array([Vector2(x0 + s * 0.3, s * 0.2), Vector2(x0 + s * 0.62, s * 0.2), Vector2(x0 + s * 0.32, s * 0.8), Vector2(x0, s * 0.8)]), colour)
