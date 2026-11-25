class_name SkidMarks
extends MeshInstance3D
## Dark tyre marks on the road under the rear wheels while they slide. One ArrayMesh per car (one surface,
## so one draw call). Each wheel keeps a ring buffer of points; every mark fades out over FADE_S.
## top_level: the marks stay where they were laid. CarFx feeds it, and a gap in marking starts a new run.

const FADE_S: float = 8.0
const WIDTH_M: float = 0.22
const STEP_M: float = 0.4  ## a new point after this much travel
const MAX_POINTS: int = 160  ## per wheel: 64 m of mark at STEP_M
const LIFT_M: float = 0.015  ## above the road, against z-fighting
const RAY_UP_M: float = 0.6
const RAY_DOWN_M: float = 1.5
const JUMP_M: float = 15.0  ## a wheel this far from its last point in one update was teleported: new run
const RUBBER: Color = Color(0.03, 0.03, 0.035, 1.0)  ## dark wet rubber; the glossy material picks up the road

## Flat arrays, slot = wheel * MAX_POINTS + ring index (nested packed arrays would copy on write).
var _pos: PackedVector3Array = PackedVector3Array()
var _born: PackedFloat32Array = PackedFloat32Array()
var _run: PackedInt32Array = PackedInt32Array()
var _head: PackedInt32Array = PackedInt32Array([0, 0])
var _count: PackedInt32Array = PackedInt32Array([0, 0])
var _open: PackedByteArray = PackedByteArray([0, 0])  ## 1 while a wheel is marking
var _last_raw: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])  ## wheel point of the last mark, before the road probe
var _runs: int = 0
var _now: float = 0.0
var _tris: int = 0
var _mesh: ArrayMesh = ArrayMesh.new()


func _init() -> void:
	_pos.resize(2 * MAX_POINTS)
	_born.resize(2 * MAX_POINTS)
	_run.resize(2 * MAX_POINTS)


func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _mesh
	visible = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.3  ## slightly glossy on the wet road
	mat.metallic_specular = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat


## points[w]: world contact point of rear wheel w; marking[w] != 0 while it slides.
## space: physics space to find the road under each point (null: the point is used as it is).
func update(points: PackedVector3Array, marking: PackedByteArray, delta: float, space: PhysicsDirectSpaceState3D = null, exclude: Array[RID] = []) -> void:
	_now += delta
	var pushed: bool = false
	for w: int in 2:
		if w >= points.size() or w >= marking.size() or marking[w] == 0:
			_open[w] = 0
			continue
		var raw: Vector3 = points[w]
		var moved: float = raw.distance_to(_last_raw[w])
		if _open[w] == 1 and moved < STEP_M:
			continue
		if _open[w] == 1 and moved > JUMP_M:
			_open[w] = 0  # teleport: the new mark must not join the old one
		if _open[w] == 0:
			_runs += 1
			_open[w] = 1
		_push(w, _road_point(raw, space, exclude), raw)
		pushed = true
	if pushed or _tris > 0:  # fading needs a rebuild each frame; nothing alive means nothing to build
		_rebuild()


## Points on wheel w that have not faded yet.
func live_points(w: int) -> int:
	var n: int = 0
	for k: int in _count[w]:
		if _alpha(_born[_slot(w, k)]) > 0.0:
			n += 1
	return n


## Triangles in the current mesh (0 when nothing is visible).
func triangle_count() -> int:
	return _tris


func _push(w: int, p: Vector3, raw: Vector3) -> void:
	var s: int = w * MAX_POINTS + _head[w]
	_pos[s] = p
	_born[s] = _now
	_run[s] = _runs
	_head[w] = (_head[w] + 1) % MAX_POINTS
	_count[w] = mini(_count[w] + 1, MAX_POINTS)
	_last_raw[w] = raw


## Slot of the k-th point of wheel w, oldest first.
func _slot(w: int, k: int) -> int:
	var ring: int = (_head[w] - _count[w] + k + MAX_POINTS) % MAX_POINTS
	return w * MAX_POINTS + ring


func _alpha(born: float) -> float:
	return clampf(1.0 - (_now - born) / FADE_S, 0.0, 1.0)


func _rebuild() -> void:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for w: int in 2:
		for k: int in maxi(_count[w] - 1, 0):
			var s0: int = _slot(w, k)
			var s1: int = _slot(w, k + 1)
			if _run[s0] != _run[s1]:
				continue
			var a0: float = _alpha(_born[s0])
			var a1: float = _alpha(_born[s1])
			if a0 <= 0.0 or a1 <= 0.0:
				continue
			var p0: Vector3 = _pos[s0]
			var p1: Vector3 = _pos[s1]
			var d: Vector3 = p1 - p0
			d.y = 0.0
			if d.length_squared() < 0.0001:
				continue
			var side: Vector3 = d.cross(Vector3.UP).normalized() * (WIDTH_M * 0.5)
			var c0 := Color(RUBBER.r, RUBBER.g, RUBBER.b, a0)
			var c1 := Color(RUBBER.r, RUBBER.g, RUBBER.b, a1)
			var v0: Vector3 = p0 - side
			var v1: Vector3 = p0 + side
			var v2: Vector3 = p1 + side
			var v3: Vector3 = p1 - side
			verts.append_array([v0, v1, v2, v0, v2, v3])
			cols.append_array([c0, c0, c1, c0, c1, c1])
	_tris = verts.size() / 3
	_mesh.clear_surfaces()
	visible = _tris > 0
	if _tris > 0:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = cols
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## The road height under a wheel point (ray down from just above it), lifted by LIFT_M.
func _road_point(p: Vector3, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> Vector3:
	if space == null:
		return p + Vector3.UP * LIFT_M
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * RAY_UP_M, p + Vector3.DOWN * RAY_DOWN_M)
	q.exclude = exclude
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return p + Vector3.UP * LIFT_M
	return (hit["position"] as Vector3) + (hit["normal"] as Vector3) * LIFT_M
