class_name ParkedCars
extends RefCounted
## Shared meshes for the parked cars of city 01, baked from the Arden Civic traffic sedan (LOD0-2) in model space.
## "body" holds every non-paint surface (headlights left out), "paint" holds the M_Paint surfaces so one
## MultiMesh per colour can colour them with a material override. Placement is done by CityBuilder.

const LOD_PATHS: PackedStringArray = [
	"res://assets/vehicles/arden_civic/arden_civic_lod0.glb",
	"res://assets/vehicles/arden_civic/arden_civic_lod1.glb",
	"res://assets/vehicles/arden_civic/arden_civic_lod2.glb",
]
const PAINT_NAME: String = "M_Paint"
const HEADLIGHT_NAME: String = "M_LightFront"  ## parked cars have their headlights off


## Muted night paints, one MultiMesh each. Order matches paint_names().
static func paint_colours() -> Array[Color]:
	return [Color(0.085, 0.09, 0.10), Color(0.03, 0.05, 0.11), Color(0.20, 0.04, 0.05),
		Color(0.72, 0.73, 0.75), Color(0.45, 0.47, 0.50), Color(0.015, 0.015, 0.02)]


static func paint_names() -> PackedStringArray:
	return PackedStringArray(["dark_grey", "navy", "maroon", "white", "silver", "black"])


## Returns {body: ArrayMesh, paint: ArrayMesh, aabb: AABB} with the model's own origin and orientation.
static func bake(lod: int = 2) -> Dictionary:
	var root: Node3D = (load(LOD_PATHS[clampi(lod, 0, LOD_PATHS.size() - 1)]) as PackedScene).instantiate() as Node3D
	var body := ArrayMesh.new()
	var paint := ArrayMesh.new()
	var box := AABB()
	var first: bool = true
	for mi: MeshInstance3D in _mesh_instances(root):
		var rel: Transform3D = _rel_xf(mi, root)
		var mesh: Mesh = mi.mesh
		for s: int in mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			var nm: String = mat.resource_name if mat != null else ""
			if nm == HEADLIGHT_NAME:
				continue
			var arrs: Array = mesh.surface_get_arrays(s)
			_xform_arrays(arrs, rel)
			var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				box = AABB(v, Vector3.ZERO) if first else box.expand(v)
				first = false
			var is_paint: bool = nm == PAINT_NAME
			var target: ArrayMesh = paint if is_paint else body
			target.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrs)
			if not is_paint:
				target.surface_set_material(target.get_surface_count() - 1, mat)
	root.free()
	return {"body": body, "paint": paint, "aabb": box}


static func _mesh_instances(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c: Node in n.get_children():
		out.append_array(_mesh_instances(c))
	return out


static func _rel_xf(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != root and cur is Node3D:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Bakes a surface's vertices, normals and tangents with rel. Normals use the inverse transpose.
static func _xform_arrays(arrs: Array, rel: Transform3D) -> void:
	var b: Basis = rel.basis
	var nb: Basis = b.inverse().transposed()
	var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	for i: int in verts.size():
		verts[i] = rel * verts[i]
	arrs[Mesh.ARRAY_VERTEX] = verts
	if arrs[Mesh.ARRAY_NORMAL] != null:
		var norms: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
		for i: int in norms.size():
			norms[i] = (nb * norms[i]).normalized()
		arrs[Mesh.ARRAY_NORMAL] = norms
	if arrs[Mesh.ARRAY_TANGENT] != null:
		var tan: PackedFloat32Array = arrs[Mesh.ARRAY_TANGENT]
		for i: int in tan.size() / 4:
			var d: Vector3 = (b * Vector3(tan[4 * i], tan[4 * i + 1], tan[4 * i + 2])).normalized()
			tan[4 * i] = d.x
			tan[4 * i + 1] = d.y
			tan[4 * i + 2] = d.z
		arrs[Mesh.ARRAY_TANGENT] = tan
