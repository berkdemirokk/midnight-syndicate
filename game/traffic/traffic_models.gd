class_name TrafficModels
extends RefCounted
## Shared meshes of the civilian traffic cars: the Arden Civic LODs (same GLBs as ParkedCars), split per LOD into
## body (everything except paint and lamps), paint (one material per colour), head and tail lamp surfaces.
## Baked once per process and shared by every TrafficCar.

const HEAD_NAME: String = "M_LightFront"
const TAIL_NAME: String = "M_LightRear"
const LOD_COUNT: int = 3

static var _cache: Array[Dictionary] = []
static var _paints: Array[StandardMaterial3D] = []


## {body, paint, head, tail: ArrayMesh, aabb: AABB} of the LOD (0 = most detail), model space, nose +Z.
static func lod(index: int) -> Dictionary:
	if _cache.is_empty():
		for i: int in LOD_COUNT:
			_cache.append(_bake(i))
	return _cache[clampi(index, 0, LOD_COUNT - 1)]


## Shared clear-coat paint of colour slot i (ParkedCars.paint_colours order).
static func paint_material(i: int) -> StandardMaterial3D:
	if _paints.is_empty():
		for c: Color in ParkedCars.paint_colours():
			var mat := StandardMaterial3D.new()
			mat.albedo_color = c
			mat.metallic = 0.7
			mat.roughness = 0.3
			mat.clearcoat_enabled = true
			mat.clearcoat = 1.0
			mat.clearcoat_roughness = 0.05
			_paints.append(mat)
	return _paints[posmod(i, _paints.size())]


static func paint_count() -> int:
	return ParkedCars.paint_colours().size()


static func _bake(index: int) -> Dictionary:
	var root: Node3D = (load(ParkedCars.LOD_PATHS[index]) as PackedScene).instantiate() as Node3D
	var meshes: Dictionary = {"body": ArrayMesh.new(), "paint": ArrayMesh.new(), "head": ArrayMesh.new(), "tail": ArrayMesh.new()}
	var box := AABB()
	var first: bool = true
	for mi: MeshInstance3D in ParkedCars._mesh_instances(root):
		var rel: Transform3D = ParkedCars._rel_xf(mi, root)
		for s: int in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			var nm: String = mat.resource_name if mat != null else ""
			var arrs: Array = mi.mesh.surface_get_arrays(s)
			ParkedCars._xform_arrays(arrs, rel)
			for v: Vector3 in (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				box = AABB(v, Vector3.ZERO) if first else box.expand(v)
				first = false
			var key: String = "body"
			if nm == ParkedCars.PAINT_NAME:
				key = "paint"
			elif nm == HEAD_NAME:
				key = "head"
			elif nm == TAIL_NAME:
				key = "tail"
			var target: ArrayMesh = meshes[key]
			target.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(s), arrs)
			if key == "body":
				target.surface_set_material(target.get_surface_count() - 1, mat)
	root.free()
	meshes["aabb"] = box
	return meshes
