class_name DayBounce
extends Node3D
## Day-only fake occlusion and bounce, no bake. Dark gradient strips on the ground at the foot of every first-row
## frontage that faces the road, and along both kerbs, plus one warm shadowless fill light. The Mobile renderer has no
## ambient occlusion or GI, so without this the shaded walls read as an even sky blue. Two MultiMesh draw calls and one
## light, all built once. Night and sunset never build it (TimeOfDay.apply_shadow_casters calls build for DAY only).

const SHADER: Shader = preload("res://shaders/day_ground_shade.gdshader")
const FRONT_W: float = 1.4  ## m: width of the strip at a frontage
const KERB_W: float = 1.0  ## m: width of the strip along a kerb
const KERB_STEP: float = 4.0  ## m between kerb strips
const SAMPLE_M: float = 8.0  ## m between track samples used for the nearest-road lookup
const FRONT_MAX_M: float = 24.0  ## a frontage farther than this from the road gets no strip
const LIFT: float = 0.03  ## m above the road height, so strips never z-fight the ground
const FILL_COLOUR: Color = Color(1.0, 0.86, 0.68)  ## sunlit stone
const FILL_ENERGY: float = 0.5
const FRONT_STRENGTH: float = 0.7
const KERB_STRENGTH: float = 0.3


## Builds the node under root (CityBuilder's Geometry node, a child of the track). sun_dir is the direction toward the sun.
static func build(root: Node, track: Track, sun_dir: Vector3) -> DayBounce:
	var node := DayBounce.new()
	node.name = "DayBounce"
	root.add_child(node)
	var samples: PackedVector3Array = _samples(track)
	if samples.size() < 2:
		return node
	var first: Node = root.get_node_or_null("FirstRow")
	if first != null:
		node._frontages(first, samples, track.width)
	node._kerbs(track)
	node._fill(sun_dir)
	return node


## Pure: a strip at a frontage belongs where the road lies in the outward direction (dot > 0.3).
static func faces_road(outward: Vector3, to_road: Vector3) -> bool:
	if to_road.length_squared() < 0.0001:
		return false
	return outward.dot(to_road.normalized()) > 0.3


## Pure: gradient alpha of a strip at u (0 at the wall or kerb, 1 at the outer edge).
static func shade_alpha(u: float, strength: float) -> float:
	return strength * pow(1.0 - clampf(u, 0.0, 1.0), 2.0)


static func _samples(track: Track) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var n: int = int(track.length / SAMPLE_M)
	for i: int in range(n + 1):
		out.append(track.get_point_at(float(i) * SAMPLE_M))
	return out


## Unit quad on the ground, UV.x across the strip (0 at the wall), UV.y along it.
static func _quad() -> ArrayMesh:
	var v: PackedVector3Array = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1)])
	var uv: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	var idx: PackedInt32Array = PackedInt32Array([0, 2, 1, 1, 2, 3])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## One MultiMesh (one draw call) of strips: origin at the wall or kerb, x axis = outward * width, z axis = along * length.
func _strips(list: Array, width: float, strength: float, name_: String) -> void:
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _quad()
	mm.instance_count = list.size()
	for i: int in range(list.size()):
		var s: Array = list[i]  # [origin, outward, along, length]
		var outward: Vector3 = s[1]
		var along: Vector3 = s[2]
		var b := Basis(outward * width, Vector3.UP, along * float(s[3]))
		mm.set_instance_transform(i, Transform3D(b, s[0]))
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("strength", strength)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _frontages(first: Node, samples: PackedVector3Array, road_w: float) -> void:
	var list: Array = []
	for b: Node in first.get_children():
		var box: AABB = _world_aabb(b)
		if box.size.x <= 0.0 or box.size.z <= 0.0:
			continue
		var x0: float = box.position.x
		var x1: float = box.end.x
		var z0: float = box.position.z
		var z1: float = box.end.z
		# each edge: origin on the wall at the ground, along direction, outward normal, length
		var edges: Array = [
			[Vector3(x0, 0, z0), Vector3(1, 0, 0), Vector3(0, 0, -1), x1 - x0],
			[Vector3(x0, 0, z1), Vector3(1, 0, 0), Vector3(0, 0, 1), x1 - x0],
			[Vector3(x0, 0, z0), Vector3(0, 0, 1), Vector3(-1, 0, 0), z1 - z0],
			[Vector3(x1, 0, z0), Vector3(0, 0, 1), Vector3(1, 0, 0), z1 - z0],
		]
		for e: Array in edges:
			var mid: Vector3 = (e[0] as Vector3) + (e[1] as Vector3) * (float(e[3]) * 0.5)
			mid.y = box.position.y
			var near: Vector3 = _nearest(samples, mid)
			if Vector2(near.x - mid.x, near.z - mid.z).length() > FRONT_MAX_M:
				continue
			var to_road: Vector3 = near - mid
			to_road.y = 0.0
			if not faces_road(e[2], to_road):
				continue
			var origin: Vector3 = e[0]
			origin.y = near.y + LIFT
			list.append([origin, e[2], e[1], e[3]])
	_strips(list, FRONT_W, FRONT_STRENGTH, "FrontShade")


func _kerbs(track: Track) -> void:
	var list: Array = []
	var off: float = track.width * 0.5
	var n: int = int(track.length / KERB_STEP)
	for i: int in range(n):
		var s: float = float(i) * KERB_STEP
		var p: Vector3 = track.get_point_at(s)
		var t: Vector3 = track.get_tangent_at(s)
		t.y = 0.0
		if t.length_squared() < 0.0001:
			continue
		t = t.normalized()
		var side: Vector3 = Vector3(-t.z, 0, t.x)
		for k: float in [-1.0, 1.0]:
			var outward: Vector3 = side * k
			var origin: Vector3 = p + outward * off
			origin.y = p.y + LIFT
			list.append([origin, outward, t, KERB_STEP + 0.5])
	_strips(list, KERB_W, KERB_STRENGTH, "KerbShade")


## Warm shadowless fill from the side opposite the sun, low, so shaded walls get warm bounce instead of flat blue.
func _fill(sun_dir: Vector3) -> void:
	var sw: Vector3 = sun_dir
	var dir: Vector3 = Vector3(-sw.x, -0.35, -sw.z).normalized()
	var fill := DirectionalLight3D.new()
	fill.name = "DayFill"
	fill.light_color = FILL_COLOUR
	fill.light_energy = FILL_ENERGY
	fill.shadow_enabled = false
	fill.basis = Basis.looking_at(dir, Vector3.UP)
	add_child(fill)


static func _nearest(samples: PackedVector3Array, p: Vector3) -> Vector3:
	var best: Vector3 = samples[0]
	var best_d: float = INF
	for s: Vector3 in samples:
		var d: float = Vector2(s.x - p.x, s.z - p.z).length_squared()
		if d < best_d:
			best_d = d
			best = s
	return best


static func _world_aabb(b: Node) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for m: Node in b.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out
