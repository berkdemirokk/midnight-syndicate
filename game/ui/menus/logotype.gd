class_name Logotype
extends Control
## STREET EMPIRE wordmark painted in one _draw (docs/brand/BRAND_GUIDELINES.md): the two words in Anton leaning
## 8 degrees as one sheared shape (a per-glyph skew makes the baseline jump), split by the racing-red blade, with the
## tagline RULE THE CITY tracked in titanium under it. No glow, no outline, no gradient.

const WORD_PX: int = 96
const TAG_PX: int = 18
const BLADE_W_EM: float = 0.16  ## blade width as a fraction of the word size
const GAP_EM: float = 0.10  ## gap on each side of the blade
const TAG_GAP_PX: float = 10.0
const PAD_PX: float = 4.0
const CAP_RATIO: float = 0.73  ## Anton cap height / ascent (measured from the font file), so the blade matches the letters

var scale_k: float = 1.0
var show_tagline: bool = true
var word_a: String = "STREET"
var word_b: String = "EMPIRE"
var tagline: String = "RULE THE CITY"


func _init(k: float = 1.0, with_tagline: bool = true) -> void:
	scale_k = k
	show_tagline = with_tagline
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = measure()


func _word_px() -> int:
	return roundi(WORD_PX * scale_k)


func _tag_px() -> int:
	return roundi(TAG_PX * scale_k)


func measure() -> Vector2:
	var f: Font = MSTheme.font("display")
	var wp: int = _word_px()
	var w: float = f.get_string_size(word_a, HORIZONTAL_ALIGNMENT_LEFT, -1, wp).x \
		+ f.get_string_size(word_b, HORIZONTAL_ALIGNMENT_LEFT, -1, wp).x \
		+ float(wp) * (BLADE_W_EM + GAP_EM * 2.0)
	var h: float = f.get_ascent(wp) * CAP_RATIO + PAD_PX * 2.0
	if show_tagline:
		h += TAG_GAP_PX * scale_k + MSTheme.font("tracked").get_height(_tag_px())
	return Vector2(ceilf(w + PAD_PX * 2.0 + f.get_ascent(wp) * MSTheme.SKEW_RATIO), ceilf(h))


func _shear(baseline: float) -> Transform2D:
	return Transform2D(Vector2(1.0, 0.0), Vector2(-MSTheme.SKEW_RATIO, 1.0), Vector2(MSTheme.SKEW_RATIO * baseline, 0.0))


func _draw() -> void:
	var f: Font = MSTheme.font("display")
	var wp: int = _word_px()
	var cap: float = f.get_ascent(wp) * CAP_RATIO
	var base: float = PAD_PX + cap
	var x: float = PAD_PX
	var wa: float = f.get_string_size(word_a, HORIZONTAL_ALIGNMENT_LEFT, -1, wp).x
	draw_set_transform_matrix(_shear(base))
	draw_string(f, Vector2(x, base), word_a, HORIZONTAL_ALIGNMENT_LEFT, -1, wp, MSTheme.PEARL)
	x += wa + float(wp) * GAP_EM
	# Blade: a red parallelogram from baseline to cap height, sheared with the type.
	var bw: float = float(wp) * BLADE_W_EM
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + bw * 0.55, base - cap), Vector2(x + bw * 1.0, base - cap),
		Vector2(x + bw * 0.45, base), Vector2(x, base)]), MSTheme.RED)
	x += bw + float(wp) * GAP_EM
	draw_string(f, Vector2(x, base), word_b, HORIZONTAL_ALIGNMENT_LEFT, -1, wp, MSTheme.PEARL)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if show_tagline:
		var tf: Font = MSTheme.font("tracked")
		var tp: int = _tag_px()
		var ty: float = base + TAG_GAP_PX * scale_k + tf.get_ascent(tp)
		var rule_w: float = 28.0 * scale_k
		draw_rect(Rect2(PAD_PX, ty - tf.get_ascent(tp) * 0.42, rule_w, maxf(2.0, 2.0 * scale_k)), MSTheme.RED)
		draw_string(tf, Vector2(PAD_PX + rule_w + 12.0 * scale_k, ty), tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, tp, MSTheme.TITANIUM)
