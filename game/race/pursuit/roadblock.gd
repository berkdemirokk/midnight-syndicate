class_name Roadblock
extends Node3D
## Barrier props across a race road, built by PursuitMode.try_roadblock at heat 3+. Each barrier is a StaticBody3D,
## so car physics stop on it. The layout always leaves one lane open on the right. No barrier is built when a car is
## within CLEAR_M of it.

const BARRIER_WIDTH_M: float = 2.0  ## across the road: the 4 m event kit barrier scaled to half its length on X
const BARRIER_MODEL_M: float = 4.0  ## length of the event kit barrier as modelled
const KIT_BARRIER: String = "res://assets/world/kits/event/event_barrier_%d.glb"  ## 0..2: three banner variants
const BOARD_SHADER: Shader = preload("res://shaders/board_sponsor.gdshader")
const BOARD_ATLAS: String = "res://assets/world/kits/event_photo/sponsor_boards_atlas.jpg"
const BARRIER_DEPTH_M: float = 0.6
const BARRIER_HEIGHT_M: float = 0.8
const BARRIER_SPACING_M: float = 2.0  ## barriers touch, as a jersey line does
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
	var orient: Basis = Basis(right, Vector3.UP, -t)  ## local X across the road, local +Z (road face) toward the traffic
	var spots: PackedVector3Array = PackedVector3Array()
	for lat: float in offsets:
		var p: Vector3 = centre + right * (mid + lat)
		for c: Vector3 in car_positions:
			if c.distance_to(p) < CLEAR_M:
				return null
		spots.append(p)
	var rb := Roadblock.new()
	rb.progress = s
	for k: int in spots.size():
		rb.add_child(_barrier(orient, spots[k], k))
	return rb


## Event kit barrier (concrete jersey with sponsor boards), scaled to BARRIER_WIDTH_M across the road. Its origin sits
## on the road; the box collider stands on it, so car physics stop on the barrier.
static func _barrier(orient: Basis, p: Vector3, k: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.transform = Transform3D(orient, p)
	var model: Node3D = (load(KIT_BARRIER % (k % 3)) as PackedScene).instantiate() as Node3D
	model.scale = Vector3(BARRIER_WIDTH_M / BARRIER_MODEL_M, 1.0, 1.0)
	var board := ShaderMaterial.new()
	board.shader = BOARD_SHADER
	board.set_shader_parameter("boards", load(BOARD_ATLAS))
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		for s: int in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, board)
	body.add_child(model)
	var shape := BoxShape3D.new()
	shape.size = Vector3(BARRIER_WIDTH_M, BARRIER_HEIGHT_M, BARRIER_DEPTH_M)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, BARRIER_HEIGHT_M * 0.5, 0.0)
	body.add_child(col)
	return body
