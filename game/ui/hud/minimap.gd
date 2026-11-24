class_name MiniMap
extends Control
## Track outline with car dots. Points come from track.get_minimap_points() (fitted to this control, aspect kept).
## Dots sit on the outline at a 0..1 lap progress reported by RaceManager.get_lap_progress().

@export var pad_px: float = 16.0
@export var line_px: float = 3.0
@export var player_radius_px: float = 7.0
@export var rival_radius_px: float = 5.0
@export var skew_px: float = 24.0

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
	var t: float = fposmod(progress, 1.0)
	var pl: int = 1 if is_player else 0
	if is_equal_approx(_dot_t[index], t) and _dot_player[index] == pl:
		return
	_dot_t[index] = t
	_dot_player[index] = pl
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refit()


func _refit() -> void:
	_screen = PackedVector2Array()
	_cum = PackedFloat32Array()
	if _raw.size() < 2 or size.x <= 0.0 or size.y <= 0.0:
		queue_redraw()
		return
	var lo: Vector2 = _raw[0]
	var hi: Vector2 = _raw[0]
	for p: Vector2 in _raw:
		lo = lo.min(p)
		hi = hi.max(p)
	var span: Vector2 = (hi - lo).max(Vector2(0.0001, 0.0001))
	var inner: Vector2 = size - Vector2(pad_px, pad_px) * 2.0
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
	queue_redraw()


func _point_at(t: float) -> Vector2:
	var n: int = _cum.size()
	for i: int in range(1, n):
		if _cum[i] >= t:
			var seg: float = _cum[i] - _cum[i - 1]
			var k: float = 0.0 if seg <= 0.0 else (t - _cum[i - 1]) / seg
			return _screen[i - 1].lerp(_screen[i], k)
	return _screen[0]


func _draw() -> void:
	var frame: PackedVector2Array = PackedVector2Array([
		Vector2(skew_px, 0.0), Vector2(size.x, 0.0),
		Vector2(size.x - skew_px, size.y), Vector2(0.0, size.y)])
	draw_colored_polygon(frame, MSTheme.PANEL_BG)
	draw_polyline(PackedVector2Array([frame[0], frame[1], frame[2], frame[3], frame[0]]), MSTheme.BORDER, 1.0, true)
	if _screen.size() < 2:
		return
	draw_polyline(_screen, MSTheme.tint(MSTheme.TEXT, 0.35), line_px, true)
	for i: int in _dot_t.size():
		var p: Vector2 = _point_at(_dot_t[i])
		if _dot_player[i] == 1:
			draw_circle(p, player_radius_px + 4.0, MSTheme.tint(MSTheme.CYAN, 0.25))
			draw_circle(p, player_radius_px, MSTheme.CYAN)
		else:
			draw_circle(p, rival_radius_px, MSTheme.MAGENTA)
