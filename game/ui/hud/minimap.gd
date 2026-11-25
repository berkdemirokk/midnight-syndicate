class_name MiniMap
extends RefCounted
## Track outline with car dots. Points come from track.get_minimap_points() (fitted to size_px, aspect kept).
## Dots sit on the outline at a 0..1 lap progress reported by RaceManager.get_lap_progress().
## Paints into the HUD's own canvas in three passes so each one batches: paint_rects (panel), paint_lines (frame
## edge and track outline), paint_dots (one shared disc texture).

const DISC_PX: int = 32
const TRACK_COL: Color = Color(0.374, 0.395, 0.434)  ## TEXT at 35 percent over PANEL_BG, pre-blended

static var _disc: ImageTexture = null

var pad_px: float = 16.0
var line_px: float = 3.0
var player_radius_px: float = 7.0
var rival_radius_px: float = 5.0
var skew_px: float = 24.0
var size_px: Vector2 = Vector2(240.0, 240.0)

var _screen: PackedVector2Array = PackedVector2Array()
var _cum: PackedFloat32Array = PackedFloat32Array()  ## cumulative length of _screen, 0..1
var _dot_t: PackedFloat32Array = PackedFloat32Array()
var _dot_player: PackedByteArray = PackedByteArray()
var _raw: PackedVector2Array = PackedVector2Array()


func set_track(points: PackedVector2Array) -> void:
	_raw = points
	_refit()


func set_dot_count(n: int) -> void:
	_dot_t.resize(n)
	_dot_player.resize(n)


func set_dot(index: int, progress: float, is_player: bool) -> void:
	if index < 0 or index >= _dot_t.size():
		return
	_dot_t[index] = fposmod(progress, 1.0)
	_dot_player[index] = 1 if is_player else 0


func _refit() -> void:
	_screen = PackedVector2Array()
	_cum = PackedFloat32Array()
	if _raw.size() < 2:
		return
	var lo: Vector2 = _raw[0]
	var hi: Vector2 = _raw[0]
	for p: Vector2 in _raw:
		lo = lo.min(p)
		hi = hi.max(p)
	var span: Vector2 = (hi - lo).max(Vector2(0.0001, 0.0001))
	var inner: Vector2 = size_px - Vector2(pad_px, pad_px) * 2.0
	var s: float = minf(inner.x / span.x, inner.y / span.y)
	var offset: Vector2 = Vector2(pad_px, pad_px) + (inner - span * s) * 0.5
	for p: Vector2 in _raw:
		_screen.append(offset + (p - lo) * s)
	_screen.append(_screen[0])
	var total: float = 0.0
	_cum.append(0.0)
	for i: int in range(1, _screen.size()):
		total += _screen[i].distance_to(_screen[i - 1])
		_cum.append(total)
	if total > 0.0:
		for i: int in _cum.size():
			_cum[i] /= total


func _point_at(t: float) -> Vector2:
	var n: int = _cum.size()
	for i: int in range(1, n):
		if _cum[i] >= t:
			var seg: float = _cum[i] - _cum[i - 1]
			var k: float = 0.0 if seg <= 0.0 else (t - _cum[i - 1]) / seg
			return _screen[i - 1].lerp(_screen[i], k)
	return _screen[0]


func _frame(origin: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		origin + Vector2(skew_px, 0.0), origin + Vector2(size_px.x, 0.0),
		origin + Vector2(size_px.x - skew_px, size_px.y), origin + Vector2(0.0, size_px.y)])


## Panel fill. A sheared rect, so it stays in the HUD's rect batch.
func paint_rects(c: CanvasItem, origin: Vector2) -> void:
	var shear: float = skew_px / size_px.y
	c.draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(-shear, 1.0), origin + Vector2(skew_px, 0.0)))
	c.draw_rect(Rect2(Vector2.ZERO, Vector2(size_px.x - skew_px, size_px.y)), MSTheme.PANEL_BG)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)


func paint_lines(c: CanvasItem, origin: Vector2) -> void:
	var f: PackedVector2Array = _frame(origin)
	c.draw_multiline(PackedVector2Array([f[0], f[1], f[1], f[2], f[2], f[3], f[3], f[0]]), MSTheme.BORDER, 1.0, true)
	if _screen.size() < 2:
		return
	var pts := PackedVector2Array()
	for i: int in range(1, _screen.size()):
		var chord: Vector2 = (_screen[i] - _screen[i - 1]).normalized() * 0.75
		pts.append(origin + _screen[i - 1] - chord)
		pts.append(origin + _screen[i] + chord)
	c.draw_multiline(pts, TRACK_COL, line_px, true)  # opaque: translucent segments bead where they meet


func paint_dots(c: CanvasItem, origin: Vector2) -> void:
	if _screen.size() < 2:
		return
	var tex: ImageTexture = _disc_texture()
	for i: int in _dot_t.size():
		var p: Vector2 = origin + _point_at(_dot_t[i])
		if _dot_player[i] == 1:
			_dot(c, tex, p, player_radius_px + 4.0, MSTheme.tint(MSTheme.CYAN, 0.25))
			_dot(c, tex, p, player_radius_px, MSTheme.CYAN)
		else:
			_dot(c, tex, p, rival_radius_px, MSTheme.MAGENTA)


func _dot(c: CanvasItem, tex: Texture2D, p: Vector2, r: float, col: Color) -> void:
	c.draw_texture_rect(tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


## White disc with an anti-aliased rim, tinted per dot.
static func _disc_texture() -> ImageTexture:
	if _disc != null:
		return _disc
	var img := Image.create(DISC_PX, DISC_PX, false, Image.FORMAT_RGBA8)
	var c: float = DISC_PX * 0.5
	for y: int in DISC_PX:
		for x: int in DISC_PX:
			var d: float = Vector2(x + 0.5 - c, y + 0.5 - c).length()
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(c - d, 0.0, 1.0)))
	_disc = ImageTexture.create_from_image(img)
	return _disc
