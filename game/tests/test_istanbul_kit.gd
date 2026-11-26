extends "res://tests/test_case.gd"
## Istanbul kit: catalog, GLBs, materials and textures are present and consistent.

const DIR: String = "res://assets/world/kits/istanbul/"


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func test_catalog_files_and_materials() -> void:
	var cat: Dictionary = _json(DIR + "catalog.json")
	check(not cat.is_empty(), "istanbul catalog.json missing")
	var mats: Dictionary = _json(DIR + "materials.json").get("materials", {})
	var buildings: Array = cat.get("buildings", [])
	var items: Array = cat.get("items", [])
	check(buildings.size() == 6, "expected 6 buildings, got %d" % buildings.size())
	check(items.size() == 10, "expected 10 items, got %d" % items.size())
	var known: PackedStringArray = MaterialLibrary.known_names()
	var all: Array = []
	all.append_array(buildings)
	all.append_array(items)
	for e: Variant in all:
		var d: Dictionary = e
		var f: String = DIR + String(d["file"])
		check(FileAccess.file_exists(f), "missing GLB " + f)
		for m: Variant in d["materials"]:
			var n: String = String(m)
			check(known.has(n) or mats.has(n) or n == "M_CollisionOnly", "%s uses unbound material %s" % [d["id"], n])
	for b: Variant in buildings:
		var bd: Dictionary = b
		check(int(bd["tris"]["LOD1"]) <= 0.3 * int(bd["tris"]["LOD0"]), "%s LOD1 over 30 percent of LOD0" % bd["id"])
		check(int(bd["tris"]["LOD0"]) <= 12000, "%s LOD0 over the 12000 triangle budget" % bd["id"])
		check(int(bd["tris"]["LOD1"]) <= 1200, "%s LOD1 over the 1200 triangle budget" % bd["id"])
		for p: Variant in bd["impostor_textures"]:
			check(FileAccess.file_exists(DIR + String(p)), "missing impostor " + String(p))
			check(FileAccess.file_exists("res://assets/world/kits/buildings/" + String(p)), "impostor not copied to buildings/textures: " + String(p))


func test_texture_paths_exist() -> void:
	var mats: Dictionary = _json(DIR + "materials.json").get("materials", {})
	for k: String in mats:
		var r: Dictionary = mats[k]
		var paths: Array = []
		if r.has("textures"):
			paths.append_array((r["textures"] as Dictionary).values())
		if r.has("texture_file"):
			paths.append(r["texture_file"])
		for p: Variant in paths:
			var res: String = "res://" + String(p).trim_prefix("game/")
			check(FileAccess.file_exists(res), "%s texture missing: %s" % [k, res])


func test_lod0_vertex_colours_are_baked_ao() -> void:
	## every building's LOD0 carries the baked ambient occlusion as vertex colours, and not all of it is white
	var cat: Dictionary = _json(DIR + "catalog.json")
	for b: Variant in cat.get("buildings", []):
		var d: Dictionary = b
		var scene: PackedScene = load(DIR + String(d["file"])) as PackedScene
		check(scene != null, "GLB does not load " + String(d["file"]))
		if scene == null:
			continue
		var root: Node = scene.instantiate()
		var coloured: int = 0
		var dark: int = 0
		for mi: MeshInstance3D in _meshes(root):
			if not mi.name.begins_with("LOD0") or mi.mesh == null:
				continue
			for i: int in mi.mesh.get_surface_count():
				var cols: Variant = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
				if cols == null:
					continue
				coloured += 1
				for c: Color in cols:
					if c.r < 0.99:
						dark += 1
						break
		root.free()
		check(coloured > 0, "%s LOD0 has no vertex colours (baked AO missing)" % d["id"])
		check(dark > 0, "%s LOD0 vertex colours are all white" % d["id"])


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c: Node in root.get_children():
		out.append_array(_meshes(c))
	return out


func test_skyline_materials_build() -> void:
	for n: String in IstanbulMaterials.SKYLINES:
		var m: Material = IstanbulMaterials.build(n)
		check(m is ShaderMaterial, n + " is not a ShaderMaterial")
		check((m as ShaderMaterial).get_shader_parameter("albedo_tex") != null, n + " has no texture")
