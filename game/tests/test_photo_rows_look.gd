extends "res://tests/test_case.gd"
## Istanbul photo rows (PhotoFronts, Ortakoy): walls and roofs carry metre UVs and tangents, roof planes use the roof
## alpha band, the eave has a fascia and a soffit and reaches EAVE_M out, and the bogaz group wires the plaster and tile.


func _group() -> Dictionary:
	return (PhotoFronts.SETS["istanbul_bogaz"]["groups"] as Array)[0]


func test_house_mesh_has_tangents_and_metre_uvs() -> void:
	var pf := PhotoFronts.new()
	var mesh: ArrayMesh = pf._house_mesh(0, _group())
	check((mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TANGENT) != 0, "house mesh has no tangents")
	var arrays: Array = mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var walls: int = 0
	for i: int in cols.size():
		if cols[i].a < 0.25:
			walls += 1
			check(uvs[i].length() > 0.0, "wall vertex %d has no metre UV" % i)
	check(walls > 0, "no wall vertices in the house mesh")
	pf.free()


func test_roof_planes_eave_fascia_and_soffit() -> void:
	var pf := PhotoFronts.new()
	var mesh: ArrayMesh = pf._house_mesh(1, _group())
	var arrays: Array = mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var roof: int = 0
	var soffit: bool = false
	var front_z: float = 0.0
	for i: int in cols.size():
		if absf(cols[i].a - PhotoFronts.ROOF_ALPHA) < 0.02:  # vertex colours are stored as 8 bit
			roof += 1
		if normals[i].y < -0.9:
			soffit = true
		front_z = minf(front_z, verts[i].z)
	check(roof > 0, "no roof plane carries the roof alpha")
	check(soffit, "no soffit under the eave")
	check(is_equal_approx(front_z, -PhotoFronts.EAVE_M), "eave reaches %.3f, expected %.3f" % [front_z, -PhotoFronts.EAVE_M])
	pf.free()


func test_bogaz_group_wires_plaster_and_tile() -> void:
	var pf := PhotoFronts.new()
	pf._load_groups([_group()])
	check(pf._facades.size() > 0, "no facade material built for the bogaz rows")
	for m: ShaderMaterial in pf._facades:
		check(bool(m.get_shader_parameter("textured_walls")), "textured_walls is off on a bogaz facade")
		for p: String in ["wall_tex", "wall_nrm", "roof_tex"]:
			check(m.get_shader_parameter(p) is Texture2D, "%s is not set on a bogaz facade" % p)
	pf.free()


func test_plain_groups_keep_plain_roofs() -> void:
	var pf := PhotoFronts.new()
	var group: Dictionary = _group().duplicate()
	group["textured"] = false
	var cols: PackedColorArray = (pf._house_mesh(1, group).surface_get_arrays(0)[Mesh.ARRAY_COLOR])
	for i: int in cols.size():
		check(absf(cols[i].a - PhotoFronts.ROOF_ALPHA) > 0.02, "a plain group roof carries the roof alpha")
	pf.free()
