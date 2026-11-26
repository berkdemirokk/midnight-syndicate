class_name Logotype
extends Control
## MIDNIGHT SYNDICATE wordmark painted in one _draw: the whole line is sheared as one shape (a per-glyph skew
## made the baseline jump), with a magenta offset shadow, a cyan second line and a speed-line slash under it.

const TOP_PX: int = 124
const SUB_PX: int = 46
const SHADOW_OFFSET: Vector2 = Vector2(6.0, 5.0)
const SUB_GAP_PX: float = 4.0
const BAR_H: float = 7.0
const BAR_GAP_PX: float = 14.0
const PAD_PX: float = 16.0

var scale_k: float = 1.0
var _top: String = "MIDNIGHT"
var _sub: String = "SYNDICATE"


func _init(k: float = 1.0) -> void:
	scale_k = k
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = measure()


func measure() -> Vector2:
	var f: Font = MSTheme.font("bold")
	var tp: int = roundi(TOP_PX * scale_k)
	var w: float = f.get_string_size(_top, HORIZONTAL_ALIGNMENT_LEFT, -1, tp).x
	var h: float = f.get_height(tp) + (MSTheme.font("tracked").get_height(roundi(SUB_PX * scale_k))) + BAR_GAP_PX + BAR_H + PAD_PX
	return Vector2(w + PAD_PX * 2.0 + 24.0 * scale_k, h)


func _shear(baseline: float, x0: float) -> Transform2D:
	return Transform2D(Vector2(1.0, 0.0), Vector2(-MSTheme.SKEW_RATIO, 1.0), Vector2(x0 + MSTheme.SKEW_RATIO * baseline, 0.0))


func _draw() -> void:
	var bold: Font = MSTheme.font("bold")
	var tracked: Font = MSTheme.font("tracked")
	var tp: int = roundi(TOP_PX * scale_k)
	var sp: int = roundi(SUB_PX * scale_k)
	var base_top: float = bold.get_ascent(tp) + 2.0
	var width: float = bold.get_string_size(_top, HORIZONTAL_ALIGNMENT_LEFT, -1, tp).x

	# Magenta shadow, then the white wordmark with a hairline cyan edge.
	draw_set_transform_matrix(_shear(base_top, PAD_PX) * Transform2D(0.0, Vector2.ONE, 0.0, SHADOW_OFFSET))
	draw_string(bold, Vector2.ZERO + Vector2(0.0, base_top), _top, HORIZONTAL_ALIGNMENT_LEFT, -1, tp, MSTheme.tint(MSTheme.MAGENTA, 0.95))
	draw_set_transform_matrix(_shear(base_top, PAD_PX))
	draw_string_outline(bold, Vector2(0.0, base_top), _top, HORIZONTAL_ALIGNMENT_LEFT, -1, tp, 2, MSTheme.tint(MSTheme.CYAN, 0.9))
	draw_string(bold, Vector2(0.0, base_top), _top, HORIZONTAL_ALIGNMENT_LEFT, -1, tp, MSTheme.TEXT)

	# SYNDICATE, tracked and cyan, sheared the same way.
	var base_sub: float = base_top + bold.get_descent(tp) + SUB_GAP_PX + tracked.get_ascent(sp)
	draw_set_transform_matrix(_shear(base_sub, PAD_PX + 6.0 * scale_k))
	draw_string(tracked, Vector2(0.0, base_sub), _sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sp, MSTheme.CYAN)
	draw_set_transform_matrix(Transform2D.IDENTITY)

	# Slash bar: a thick magenta parallelogram fading into speed lines.
	var by: float = base_sub + tracked.get_descent(sp) + BAR_GAP_PX
	var sk: float = BAR_H * MSTheme.SKEW_RATIO
	var bar_w: float = width * 0.62
	draw_colored_polygon(PackedVector2Array([
		Vector2(PAD_PX + sk, by), Vector2(PAD_PX + bar_w, by),
		Vector2(PAD_PX + bar_w - sk, by + BAR_H), Vector2(PAD_PX, by + BAR_H)]), MSTheme.MAGENTA)
	for i: int in 3:
		var x0: float = PAD_PX + bar_w + 14.0 + float(i) * 34.0
		var len: float = (width * 0.38 - 14.0 - float(i) * 34.0) * (1.0 - 0.28 * float(i))
		if len > 4.0:
			draw_line(Vector2(x0, by + BAR_H * 0.5), Vector2(x0 + len, by + BAR_H * 0.5), MSTheme.tint(MSTheme.CYAN, 0.75 - 0.2 * float(i)), 2.0)
