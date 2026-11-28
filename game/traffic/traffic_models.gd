class_name TrafficModels
extends RefCounted
## Shared meshes of the civilian traffic cars: the Arden Civic LODs (same GLBs as ParkedCars) and three CC BY 4.0 vans
## and cabs (LOD1 and LOD2 only). Each model is split per LOD into body (everything except paint and lamps), paint
## (one material per colour), head and tail lamp surfaces. Baked once per process and model, shared by every TrafficCar.

const HEAD_NAME: String = "M_LightFront"
const TAIL_NAME: String = "M_LightRear"
const LOD_COUNT: int = 3

## Pool order: index 0 is the Arden Civic (ParkedCars), the rest are the prepared traffic models by car id.
const MODEL_IDS: Array[String] = ["arden_civic", "traffic_cab", "traffic_van", "traffic_panel_van"]

static var _cache: Dictionary = {}  ## "model:lod" -> bake
static var _paints: Array[StandardMaterial3D] = []


## shortcut: only the Arden Civic is in the pool. The three CC BY traffic models are baked and recorded but fail the
## studio gate (boxy read, paint not tinted in evidence/screens/car_studio_traffic). upgrade: fix the bake, then return MODEL_IDS.size().
static func model_count() -> int:
	return 1


static func lod_path(model: int, index: int) -> String:
	if model == 0:
		return ParkedCars.LOD_PATHS[clampi(index, 0, LOD_COUNT - 1)]
	var id: String = MODEL_IDS[posmod(model, MODEL_IDS.size())]
	return "res://assets/vehicles/%s/%s_lod%d.glb" % [id, id, clampi(index, 0, LOD_COUNT - 1)]


## The cabs and vans ship without LOD0 (traffic draws LOD1 and LOD2 only): their first LOD is 1.
static func first_lod_of(model: int) -> int:
	return 0 if ResourceLoader.exists(lod_path(model, 0)) else 1


## {body, paint, head, tail: ArrayMesh, aabb: AABB} of the LOD (0 = most detail) of a model, model space, nose +Z.
static func lod(index: int, model: int = 0) -> Dictionary:
	var key: String = "%d:%d" % [model, clampi(index, 0, LOD_COUNT - 1)]
	if not _cache.has(key):
		_cache[key] = _bake(clampi(index, 0, LOD_COUNT - 1), model)
	return _cache[key]


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


static func _bake(index: int, model: int) -> Dictionary:
	var root: Node3D = (load(lod_path(model, index)) as PackedScene).instantiate() as Node3D
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
