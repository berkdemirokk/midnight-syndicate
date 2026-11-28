class_name Track
extends Node3D
## Racing line, start grid and speed profile of one track (Track scene contract, ARCHITECTURE.md).
## RacingLine is a Path3D with a closed Curve3D: the last point repeats the first one.
## Samples are world space and are taken at _ready, so the Track must not move afterwards.
## Forward is the curve direction. Right of the race direction is +X when the car drives -Z.
## Offsets wrap around length. Lateral offsets are positive to the right.

const UNSET_HINT: float = -1.0  ## get_progress without a hint searches the whole line
const CURVATURE_FLOOR: float = 1e-4  ## 1/m, radius 10 km; keeps divisions finite
const PROFILE_LAPS: int = 2  ## the closed-loop speed passes run this many laps around

@export var width: float = 14.0  ## drivable width in m; AI lane offsets stay inside it
@export var sample_spacing: float = 4.0  ## m between line samples
@export var lateral_accel_limit: float = 9.5  ## m/s^2 allowed in corners: v = sqrt(a * r)
@export var max_speed: float = 70.0  ## m/s, cap of the speed profile
@export var brake_decel: float = 11.0  ## m/s^2 that the backward pass assumes for braking
@export var accel_limit: float = 9.0  ## m/s^2 that the forward pass assumes for acceleration
@export var search_window: float = 120.0  ## m around a progress hint that get_progress searches first

var length: float = 0.0

var _ds: float = 0.0
var _count: int = 0
var _pos: PackedVector3Array = PackedVector3Array()
var _xz: PackedVector2Array = PackedVector2Array()
var _tan: PackedVector3Array = PackedVector3Array()
var _curv: PackedFloat32Array = PackedFloat32Array()  ## 1/m, positive = turning right
var _speed: PackedFloat32Array = PackedFloat32Array()  ## m/s target speed profile
var _grid: Array[Transform3D] = []
var _reversed: bool = false  ## true while the line and grid run the other way (set_reversed)
var _grid_forward: Array[Transform3D] = []  ## the grid in the authored direction, kept while reversed


func _ready() -> void:
	_build_line()
	_build_grid()


func _build_line() -> void:
	var path: Path3D = get_node_or_null("RacingLine") as Path3D
	if path == null or path.curve == null or path.curve.point_count < 3:
		push_error("Track %s needs a RacingLine Path3D with a closed curve" % name)
		return
	var curve: Curve3D = path.curve
	length = curve.get_baked_length()
	_count = maxi(3, roundi(length / sample_spacing))
	_ds = length / float(_count)
	_pos.resize(_count)
	_xz.resize(_count)
	_tan.resize(_count)
	_curv.resize(_count)
	_speed.resize(_count)
	var xf: Transform3D = path.global_transform
	for i: int in _count:
		_pos[i] = xf * curve.sample_baked(float(i) * _ds, true)
		_xz[i] = Vector2(_pos[i].x, _pos[i].z)
	for i: int in _count:
		var d: Vector3 = _pos[(i + 1) % _count] - _pos[(i - 1 + _count) % _count]
		d.y = 0.0
		_tan[i] = d.normalized() if d.length_squared() > 0.0 else Vector3(0.0, 0.0, -1.0)
	for i: int in _count:
		var a: Vector3 = _tan[(i - 1 + _count) % _count]
		var b: Vector3 = _tan[(i + 1) % _count]
		_curv[i] = -a.signed_angle_to(b, Vector3.UP) / (2.0 * _ds)  # a right turn is a negative angle about UP
	_build_speed_profile()


## Corner limit, then a backward pass for braking and a forward pass for acceleration around the loop.
func _build_speed_profile() -> void:
	for i: int in _count:
		_speed[i] = minf(max_speed, sqrt(lateral_accel_limit / maxf(absf(_curv[i]), CURVATURE_FLOOR)))
	var brake_step: float = 2.0 * brake_decel * _ds
	for k: int in _count * PROFILE_LAPS:
		var i: int = posmod(-k - 1, _count)
		var j: int = (i + 1) % _count
		_speed[i] = minf(_speed[i], sqrt(_speed[j] * _speed[j] + brake_step))
	var accel_step: float = 2.0 * accel_limit * _ds
	for k: int in _count * PROFILE_LAPS:
		var i: int = k % _count
		var j: int = (i + 1) % _count
		_speed[j] = minf(_speed[j], sqrt(_speed[i] * _speed[i] + accel_step))


func _build_grid() -> void:
	var grid_root: Node = get_node_or_null("StartGrid")
	if grid_root == null:
		return
	for c: Node in grid_root.get_children():
		if c is Marker3D:
			_grid.append((c as Marker3D).global_transform)


## Metres along the line of the closest point to world_pos. hint (a previous progress) narrows the search.
func get_progress(world_pos: Vector3, hint: float = UNSET_HINT) -> float:
	if _count == 0:
		return 0.0
	var p: Vector2 = Vector2(world_pos.x, world_pos.z)
	var best: int = _nearest_sample(p, hint)
	var best_d2: float = INF
	var best_prog: float = 0.0
	for step: int in 2:  # the two segments that touch the nearest sample: best-1 and best
		var k: int = posmod(best - 1 + step, _count)
		var a: Vector2 = _xz[k]
		var ab: Vector2 = _xz[(k + 1) % _count] - a
		var l2: float = ab.length_squared()
		var u: float = 0.0
		if l2 > 0.0:
			u = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var d2: float = p.distance_squared_to(a + ab * u)
		if d2 < best_d2:
			best_d2 = d2
			best_prog = (float(k) + u) * _ds
	return fposmod(best_prog, length)


func get_point_at(offset: float) -> Vector3:
	if _count == 0:
		return Vector3.ZERO
	var f: float = fposmod(offset, length) / _ds
	var i: int = int(f)
	return _pos[i % _count].lerp(_pos[(i + 1) % _count], f - float(i))


func get_point_ahead(offset: float, distance: float) -> Vector3:
	return get_point_at(offset + distance)


func get_tangent_at(offset: float) -> Vector3:
	if _count == 0:
		return Vector3(0.0, 0.0, -1.0)
	return _tan[_index_of(offset)]


## Target speed in m/s from the profile at this offset.
func get_target_speed(offset: float) -> float:
	if _count == 0:
		return 0.0
	return _speed[_index_of(offset)]


## 1/m, positive = turning right, negative = left.
func get_curvature(offset: float) -> float:
	if _count == 0:
		return 0.0
	return _curv[_index_of(offset)]


## Road edges at offset as signed metres from the line (x = left kerb, y = right kerb, positive = right). Default:
## the line is the road centre and the road is width wide. A track whose line is not the road centre overrides it.
func get_road_span(offset: float) -> Vector2:
	return Vector2(-width * 0.5, width * 0.5)


## Signed metres from the line, positive = right of the race direction.
func get_lateral_offset(world_pos: Vector3, hint: float = UNSET_HINT) -> float:
	if _count == 0:
		return 0.0
	var s: float = get_progress(world_pos, hint)
	var c: Vector3 = get_point_at(s)
	var t: Vector3 = get_tangent_at(s)
	return Vector3(world_pos.x - c.x, 0.0, world_pos.z - c.z).dot(Vector3(-t.z, 0.0, t.x))


## Start grid slot, Grid0 first in child order. Index wraps.
func get_grid_transform(index: int) -> Transform3D:
	if _grid.is_empty():
		return Transform3D.IDENTITY
	return _grid[posmod(index, _grid.size())]


## x and z of every line sample (copy), for a minimap.
func get_minimap_points() -> PackedVector2Array:
	return _xz.duplicate()


func _index_of(offset: float) -> int:
	return posmod(roundi(fposmod(offset, length) / _ds), _count)


func _nearest_sample(p: Vector2, hint: float) -> int:
	if hint >= 0.0 and search_window * 2.0 < length:
		var half: int = ceili(search_window / _ds)
		var centre: int = _index_of(hint)
		var best: int = -1
		var best_d2: float = INF
		for k: int in range(-half, half + 1):
			var i: int = posmod(centre + k, _count)
			var d2: float = p.distance_squared_to(_xz[i])
			if d2 < best_d2:
				best_d2 = d2
				best = i
		if best_d2 <= width * width:
			return best
	var nearest: int = 0
	var nearest_d2: float = INF
	for i: int in _count:
		var d2: float = p.distance_squared_to(_xz[i])
		if d2 < nearest_d2:
			nearest_d2 = d2
			nearest = i
	return nearest


## Runs the track the other way round (route variants, no new geometry): the racing line is flipped, the curvature
## sign follows, the speed profile is rebuilt and each grid slot moves to the mirror position behind the start line
## facing the new direction. Call after the Track is in the tree (its _ready has built the line). Idempotent.
func set_reversed(on: bool) -> void:
	if on == _reversed or _count == 0:
		_reversed = on
		return
	if on:
		_grid_forward = _grid.duplicate()
		var mirrored: Array[Transform3D] = []
		for xf: Transform3D in _grid:
			mirrored.append(_mirror_slot(xf))
		_grid = mirrored
	else:
		_grid = _grid_forward.duplicate()
	_flip_line()
	_reversed = on


func is_reversed() -> bool:
	return _reversed


## Grid slot xf moved to the mirror position of the line (same distance from progress 0 on the other side, same
## lateral position on the road) and turned to face the reversed tangent there.
func _mirror_slot(xf: Transform3D) -> Transform3D:
	var s: float = get_progress(xf.origin)
	var lat: float = get_lateral_offset(xf.origin)
	var d: float = fposmod(-s, length)  # distance behind the start line in the authored direction
	var c: Vector3 = get_point_at(d)
	var t: Vector3 = get_tangent_at(d)
	var origin: Vector3 = c + Vector3(-t.z, 0.0, t.x) * lat
	origin.y = xf.origin.y
	return Transform3D(Basis.looking_at(-t, Vector3.UP), origin)


## Sample j takes the old sample (count - j) so index 0 stays on the start line; tangent and curvature flip sign.
func _flip_line() -> void:
	var old_pos: PackedVector3Array = _pos.duplicate()
	var old_xz: PackedVector2Array = _xz.duplicate()
	var old_tan: PackedVector3Array = _tan.duplicate()
	var old_curv: PackedFloat32Array = _curv.duplicate()
	for j: int in _count:
		var src: int = (_count - j) % _count
		_pos[j] = old_pos[src]
		_xz[j] = old_xz[src]
		_tan[j] = -old_tan[src]
		_curv[j] = -old_curv[src]
	_build_speed_profile()
