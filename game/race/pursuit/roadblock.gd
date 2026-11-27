class_name Roadblock
extends Node3D
## Barrier props across a race road, built by PursuitMode.try_roadblock at heat 3+. Each barrier is a StaticBody3D,
## so car physics stop on it. The layout always leaves one lane open on the right. No barrier is built when a car is
## within CLEAR_M of it.

const BARRIER_WIDTH_M: float = 1.6  ## across the road
const BARRIER_DEPTH_M: float = 0.5
const BARRIER_HEIGHT_M: float = 0.9
const BARRIER_SPACING_M: float = 2.2
const EDGE_MARGIN_M: float = 1.0  ## gap between the left kerb line and the first barrier
const OPEN_LANE_M: float = 3.0  ## the open lane on the right must be at least this wide
const MIN_BARRIERS: int = 2
const MAX_BARRIERS: int = 3
const CLEAR_M: float = 12.0  ## no car this close to any barrier

var progress: float = 0.0  ## track progress of the barrier line


## Lateral centres of the barriers (m, positive = right). Empty when no layout leaves OPEN_LANE_M open on the right.
static func layout(width: float) -> PackedFloat32Array:
	for n: int in range(MAX_BARRIERS, MIN_BARRIERS - 1, -1):
		var offsets := PackedFloat32Array()
		for k: int in n:
			offsets.append(-width * 0.5 + EDGE_MARGIN_M + float(k) * BARRIER_SPACING_M)
		var right_edge: float = offsets[n - 1] + BARRIER_WIDTH_M * 0.5
		if width * 0.5 - right_edge >= OPEN_LANE_M:
			return offsets
	return PackedFloat32Array()


## Null when the road has no layout or a car is within CLEAR_M of a barrier. Positions are world space.
static func build(track: Track, s: float, car_positions: PackedVector3Array) -> Roadblock:
	var span: Vector2 = track.get_road_span(s)  # kerb lines relative to the line, which need not be the road centre
	var offsets: PackedFloat32Array = layout(span.y - span.x)
	if offsets.is_empty():
		return null
	var mid: float = (span.x + span.y) * 0.5
	var centre: Vector3 = track.get_point_at(s)
	var t: Vector3 = track.get_tangent_at(s)
	var right: Vector3 = Vector3(-t.z, 0.0, t.x)
	var orient: Basis = Basis.looking_at(t, Vector3.UP)
	var spots: PackedVector3Array = PackedVector3Array()
	for lat: float in offsets:
		var p: Vector3 = centre + right * (mid + lat)
		p.y += BARRIER_HEIGHT_M * 0.5
		for c: Vector3 in car_positions:
			if c.distance_to(p) < CLEAR_M:
				return null
		spots.append(p)
	var rb := Roadblock.new()
	rb.progress = s
	for p: Vector3 in spots:
		rb.add_child(_barrier(orient, p))
	return rb


static func _barrier(orient: Basis, p: Vector3) -> StaticBody3D:
	var size: Vector3 = Vector3(BARRIER_WIDTH_M, BARRIER_HEIGHT_M, BARRIER_DEPTH_M)
	var body := StaticBody3D.new()
	body.transform = Transform3D(orient, p)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#E8E8E8")
	mat.roughness = 0.7
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	body.add_child(mesh)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	return body
