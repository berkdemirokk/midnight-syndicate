class_name MiniMap
extends RefCounted
## Round minimap, heading up. The track outline is fitted inside the ring once (set_track), then rotated every frame
## by the player's heading, so the arrow in the centre always points up the screen and the map turns around it.
## Rivals sit on the outline at their lap progress. Painted into the HUD's own canvas in three passes so each batches:
## paint_rects (disc), paint_lines (ring and outline), paint_dots (rival discs and the player arrow).

const DISC_PX: int = 32
const FIT: float = 0.78  ## outline radius as a share of the ring, so the track never touches the rim
## Opaque pre-blends (translucent chords bead where they meet): the route is titanium over graphite, the rim a
## hairline of titanium at 30 percent. The player arrow is racing red, rivals pearl.
static var TRACK_COL: Color = MSTheme.GRAPHITE_2.lerp(MSTheme.TITANIUM, 0.6)
static var RING_COL: Color = MSTheme.GRAPHITE_2.lerp(MSTheme.TITANIUM, 0.3)
static var ARROW_COL: Color = MSTheme.RED
static var RIVAL_COL: Color = MSTheme.PEARL
static var ARROW_OUTLINE_COL: Color = Color(0.0, 0.0, 0.0, 0.75)

static var _disc: ImageTexture = null

var radius_px: float = 116.0
var line_px: float = 4.0
var rival_radius_px: float = 5.0
var arrow_px: float = 13.0

var _local: PackedVector2Array = PackedVector2Array()  ## outline centred on the origin, fitted to FIT * radius
var _cum: PackedFloat32Array = PackedFloat32Array()  ## cumulative length of _local, 0..1
var _rot: PackedVector2Array = PackedVector2Array()  ## _local turned by the current heading
var _cs: float = 0.0
var _sn: float = -1.0  ## heading 0: the map is turned so forward is up
var _dot_t: PackedFloat32Array = PackedFloat32Array()
var _dot_player: PackedByteArray = PackedByteArray()
var _dot_shown: PackedByteArray = PackedByteArray()  ## 0 hides a rival, e.g. one eliminated from the race


func set_track(points: PackedVector2Array) -> void:
	_local = PackedVector2Array()
	_cum = PackedFloat32Array()
	if points.size() < 2:
		return
	var mid: Vector2 = Vector2.ZERO
	for p: Vector2 in points:
		mid += p
	mid /= float(points.size())
	var far: float = 0.0
	for p: Vector2 in points:
		far = maxf(far, p.distance_to(mid))
	var s: float = radius_px * FIT / maxf(far, 0.0001)
	for p: Vector2 in points:
		_local.append((p - mid) * s)
	_local.append(_local[0])
	var total: float = 0.0
	_cum.append(0.0)
	for i: int in range(1, _local.size()):
		total += _local[i].distance_to(_local[i - 1])
		_cum.append(total)
	if total > 0.0:
		for i: int in _cum.size():
			_cum[i] /= total
	_rot.resize(_local.size())
	set_forward(Vector2(0.0, -1.0))


func set_dot_count(n: int) -> void:
	_dot_t.resize(n)
	_dot_player.resize(n)
	_dot_shown.resize(n)


func dot_shown(index: int) -> bool:
	return index >= 0 and index < _dot_shown.size() and _dot_shown[index] == 1


func set_dot(index: int, progress: float, is_player: bool, shown: bool = true) -> void:
	if index < 0 or index >= _dot_t.size():
		return
	_dot_t[index] = fposmod(progress, 1.0)
	_dot_player[index] = 1 if is_player else 0
	_dot_shown[index] = 1 if shown else 0


## forward: the player's heading on the map plane (x, z). Turns the whole map so that heading points up.
func set_forward(forward: Vector2) -> void:
	var phi: float = -PI * 0.5 - atan2(forward.y, forward.x)
	_cs = cos(phi)
	_sn = sin(phi)
	for i: int in _local.size():
		_rot[i] = _turn(_local[i])


## Direction of north on screen, unit length. The N marker sits on the rim in this direction.
func north_dir() -> Vector2:
	return _turn(Vector2(0.0, -1.0))


func _turn(p: Vector2) -> Vector2:
	return Vector2(p.x * _cs - p.y * _sn, p.x * _sn + p.y * _cs)


func _point_at(t: float) -> Vector2:
	var n: int = _cum.size()
	for i: int in range(1, n):
		if _cum[i] >= t:
			var seg: float = _cum[i] - _cum[i - 1]
			var k: float = 0.0 if seg <= 0.0 else (t - _cum[i - 1]) / seg
			return _local[i - 1].lerp(_local[i], k)
	return _local[0]


## Round panel fill. Drawn in the rect pass.
func paint_rects(c: CanvasItem, centre: Vector2) -> void:
	c.draw_circle(centre, radius_px, MSTheme.PLATE_BG)


func paint_lines(c: CanvasItem, centre: Vector2) -> void:
	c.draw_multiline(SpeedGauge.ring_segments(centre, radius_px, 0.0, TAU, 64), RING_COL, 3.0, true)
	if _rot.size() < 2:
		return
	var pts := PackedVector2Array()
	for i: int in range(1, _rot.size()):
		var chord: Vector2 = (_rot[i] - _rot[i - 1]).normalized() * 0.75
		pts.append(centre + _rot[i - 1] - chord)
		pts.append(centre + _rot[i] + chord)
	c.draw_multiline(pts, TRACK_COL, line_px, true)  # opaque: translucent segments bead where they meet


func paint_dots(c: CanvasItem, centre: Vector2) -> void:
	if _rot.size() >= 2:
		var tex: ImageTexture = _disc_texture()
		for i: int in _dot_t.size():
			if _dot_player[i] == 0 and _dot_shown[i] == 1:
				var p: Vector2 = centre + _turn(_point_at(_dot_t[i]))
				c.draw_texture_rect(tex, Rect2(p - Vector2.ONE * rival_radius_px, Vector2.ONE * rival_radius_px * 2.0), false, RIVAL_COL)
	# Player arrow, pointing up the screen (the map turns, so forward is always up).
	# Dark outline under the arrow first, so it reads on bright signage and on the track line.
	var a: float = arrow_px
	c.draw_colored_polygon(_arrow(centre, a * 1.3), ARROW_OUTLINE_COL)
	c.draw_colored_polygon(_arrow(centre, a), ARROW_COL)


static func _arrow(centre: Vector2, a: float) -> PackedVector2Array:
	return PackedVector2Array([centre + Vector2(0.0, -a), centre + Vector2(a * 0.75, a * 0.7),
		centre + Vector2(0.0, a * 0.3), centre + Vector2(-a * 0.75, a * 0.7)])


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
