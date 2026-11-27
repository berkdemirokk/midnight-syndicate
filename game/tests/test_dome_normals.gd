extends "res://tests/test_case.gd"
## Dome normals (Landmarks.smooth_dome_mesh): the kit's dome, turret and pencil caps are smooth surfaces, so their
## vertex normals must be welded across each triangle fan, while the crease rule keeps hard edges (rib sides, rims).
## Only ARRAY_NORMAL of the M_Dome surfaces changes: vertices, indices, surfaces and materials stay as shipped.

const DIR: String = "res://assets/world/kits/landmarks/"
const LOD_FILES: PackedStringArray = ["landmark_mosque_lod0.glb", "landmark_mosque_lod1.glb", "landmark_mosque_lod2.glb"]


func _mat(resource_name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = resource_name
	return m


## Two triangles sharing an edge, each with its own vertices (as the kit builds them), in a fold of the given angle.
func _fold_mesh(second_normal: Vector3, second_verts: PackedVector3Array, material: String) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
	verts.append_array(second_verts)
	var normals := PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
	for k: int in 3:
		normals.append(second_normal)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _mat(material))
	return mesh


func test_coplanar_neighbours_weld() -> void:
	# a flat strip: the shared edge (1,0,0)-(0,1,0) gets one normal from both triangles, still straight up
	var mesh := _fold_mesh(Vector3(0, 0, 1), PackedVector3Array([Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]), "M_Dome")
	var out: Mesh = Landmarks.smooth_dome_mesh(mesh)
	var n: PackedVector3Array = (out.surface_get_arrays(0))[Mesh.ARRAY_NORMAL]
	for v: Vector3 in n:
		check(v.distance_to(Vector3(0, 0, 1)) < 1e-4, "flat strip normal stays up, got %s" % str(v))


func test_ninety_degree_fold_keeps_hard_edge() -> void:
	# second triangle in the x = 0 plane: its normal is (-1, 0, 0), 90 degrees from the first, so the shared point keeps
	# each face's own normal (a rib side or a rim must not blend into the dome)
	var mesh := _fold_mesh(Vector3(-1, 0, 0), PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)]), "M_Dome")
	var out: Mesh = Landmarks.smooth_dome_mesh(mesh)
	var n: PackedVector3Array = (out.surface_get_arrays(0))[Mesh.ARRAY_NORMAL]
	check(n[0].distance_to(Vector3(0, 0, 1)) < 1e-4, "first face keeps its normal at the fold, got %s" % str(n[0]))
	check(n[3].distance_to(Vector3(-1, 0, 0)) < 1e-4, "second face keeps its normal at the fold, got %s" % str(n[3]))


func test_other_materials_untouched() -> void:
	var mesh := _fold_mesh(Vector3(0, 0, 1), PackedVector3Array([Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]), "M_Stone")
	var out: Mesh = Landmarks.smooth_dome_mesh(mesh)
	var before: PackedVector3Array = (mesh.surface_get_arrays(0))[Mesh.ARRAY_NORMAL]
	var after: PackedVector3Array = (out.surface_get_arrays(0))[Mesh.ARRAY_NORMAL]
	check(before == after, "a non-dome surface keeps its normals")
	check(out.surface_get_material(0).resource_name == "M_Stone", "the material is kept")


func test_kit_domes_smooth_and_keep_shape() -> void:
	for lod: int in LOD_FILES.size():
		var scene: PackedScene = load(DIR + LOD_FILES[lod]) as PackedScene
		check(scene != null, "GLB loads " + LOD_FILES[lod])
		if scene == null:
			continue
		var root: Node = scene.instantiate()
		for mi: Node in root.find_children("*", "MeshInstance3D", true, false):
			var src: Mesh = (mi as MeshInstance3D).mesh
			var out: Mesh = Landmarks.smooth_dome_mesh(src)
			check(out.get_surface_count() == src.get_surface_count(), "same surface count in %s" % LOD_FILES[lod])
			for i: int in src.get_surface_count():
				var a: Array = src.surface_get_arrays(i)
				var b: Array = out.surface_get_arrays(i)
				check(out.surface_get_material(i) == src.surface_get_material(i), "material kept in %s surface %d" % [LOD_FILES[lod], i])
				check((a[Mesh.ARRAY_VERTEX] as PackedVector3Array) == (b[Mesh.ARRAY_VERTEX] as PackedVector3Array), "vertices kept in %s surface %d" % [LOD_FILES[lod], i])
				check(a[Mesh.ARRAY_INDEX] == b[Mesh.ARRAY_INDEX], "indices kept in %s surface %d" % [LOD_FILES[lod], i])
				var mat: Material = src.surface_get_material(i)
				if mat == null or mat.resource_name != "M_Dome":
					var worst: float = 0.0  ## the mesh re-encodes normals, so compare within float precision
					var old_plain: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
					var new_plain: PackedVector3Array = b[Mesh.ARRAY_NORMAL]
					for k: int in old_plain.size():
						worst = maxf(worst, old_plain[k].distance_to(new_plain[k]))
					check(worst < 1e-3, "non-dome normals kept in %s surface %d (worst %f)" % [LOD_FILES[lod], i, worst])
					continue
				var old_n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
				var new_n: PackedVector3Array = b[Mesh.ARRAY_NORMAL]
				var moved: int = 0
				var unit_ok: bool = true
				for k: int in new_n.size():
					unit_ok = unit_ok and absf(new_n[k].length() - 1.0) < 1e-3
					if new_n[k].dot(old_n[k]) < cos(deg_to_rad(5.0)):
						moved += 1
				check(unit_ok, "dome normals are unit length in %s" % LOD_FILES[lod])
				check(moved > new_n.size() / 4, "dome normals smoothed in %s surface %d (%d of %d moved)" % [LOD_FILES[lod], i, moved, new_n.size()])
		root.free()
