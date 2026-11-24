extends "res://tests/test_case.gd"
## Tests for the city material library (game/world/materials) against the shipped city_01 data.

const BUILDINGS_JSON: String = "res://assets/world/kits/buildings/catalog.json"
const PROPS_DIR: String = "res://assets/world/kits/props/"
const CITY_DIR: String = "res://assets/world/city_01/"
const SAMPLE_PROPS: Array[String] = [
	"prop_bench", "prop_bollard", "prop_bus_shelter", "prop_lamp_sodium", "prop_sign_box_lumen_cinema_4m",
	"prop_traffic_light", "prop_poster_01", "prop_litter_bin", "prop_jersey_barrier", "prop_fire_hydrant",
]


func test_json_names_all_bound() -> void:
	var names: PackedStringArray = _json_names()
	var missing: PackedStringArray = PackedStringArray()
	for n: String in names:
		if not MaterialLibrary.is_bound(n):
			missing.append(n)
	metric("json_names", names.size())
	check(names.size() > 60, "expected more than 60 names in the materials.json files, got %d" % names.size())
	check(missing.is_empty(), "names in materials.json with no library material: %s" % str(missing))


func test_glb_names_all_bound() -> void:
	var paths: Array[String] = _all_glbs()
	var glb_names: Dictionary = {}
	var surfaces: int = 0
	for p: String in paths:
		for n: String in _glb_material_names(p):
			glb_names[n] = true
			surfaces += 1
	var missing: Array[String] = []
	for n: String in glb_names.keys():
		if not MaterialLibrary.is_bound(n):
			missing.append(n)
	metric("glb_files", paths.size())
	metric("glb_surfaces", surfaces)
	metric("glb_distinct_names", glb_names.size())
	check(paths.size() >= 50, "expected at least 50 shipped GLBs, found %d" % paths.size())
	check(missing.is_empty(), "GLB material names with no library material: %s" % str(missing))


func test_shared_instances_across_buildings() -> void:
	var a: Material = MaterialLibrary.get_material("M_WindowAtlas")
	var b: Material = MaterialLibrary.get_material("M_WindowAtlas")
	check(a == b, "M_WindowAtlas is not one shared instance")
	var ids: Array[String] = _building_ids()
	check(ids.size() >= 2, "catalog lists fewer than two buildings")
	if ids.size() < 2:
		return
	var root_a: Node3D = _instance_glb(BUILDINGS_JSON.get_base_dir() + "/" + ids[0] + ".glb")
	var root_b: Node3D = _instance_glb(BUILDINGS_JSON.get_base_dir() + "/" + ids[1] + ".glb")
	MaterialLibrary.apply(root_a, ids[0])
	MaterialLibrary.apply(root_b, ids[1])
	var ma: Material = _override_named(root_a, "M_WindowAtlas")
	var mb: Material = _override_named(root_b, "M_WindowAtlas")
	check(ma != null and ma == mb, "M_WindowAtlas differs between %s and %s" % [ids[0], ids[1]])
	var ia: Material = _override_named(root_a, "M_ImpostorAtlas")
	var ib: Material = _override_named(root_b, "M_ImpostorAtlas")
	check(ia == null or ib == null or ia != ib, "impostor atlas must be per building")
	root_a.free()
	root_b.free()


func test_textures_referenced_exist() -> void:
	for id: String in _building_ids():
		var root: Node3D = _instance_glb(BUILDINGS_JSON.get_base_dir() + "/" + id + ".glb")
		MaterialLibrary.apply(root, id)
		root.free()
	for p: String in _all_props():
		var root_p: Node3D = _instance_glb(p)
		MaterialLibrary.apply(root_p, "")
		root_p.free()
	for n: String in MaterialLibrary.known_names():
		MaterialLibrary.get_material(n)
	var paths: PackedStringArray = MaterialLibrary.texture_paths_used()
	metric("textures_referenced", paths.size())
	check(paths.size() > 20, "expected more than 20 texture references, got %d" % paths.size())
	var missing: PackedStringArray = PackedStringArray()
	for p: String in paths:
		if not ResourceLoader.exists(p):
			missing.append(p)
	check(missing.is_empty(), "referenced textures missing: %s" % str(missing))


func test_apply_leaves_no_blank_surface() -> void:
	var before: int = MaterialLibrary.report_unbound().size()
	var blank: Array[String] = []
	var surfaces: int = 0
	var roots: Array[Array] = []
	for id: String in _building_ids():
		roots.append([_instance_glb(BUILDINGS_JSON.get_base_dir() + "/" + id + ".glb"), id])
	for p: String in SAMPLE_PROPS:
		roots.append([_instance_glb(PROPS_DIR + p + ".glb"), ""])
	for pair: Array in roots:
		var root: Node3D = pair[0]
		var id: String = pair[1]
		var bound: int = MaterialLibrary.apply(root, id)
		surfaces += bound
		for mi: MeshInstance3D in _meshes(root):
			for s: int in mi.mesh.get_surface_count():
				if mi.get_active_material(s) == null:
					blank.append("%s/%s surface %d" % [id, mi.name, s])
		root.free()
	metric("surfaces_bound", surfaces)
	metric("roots", roots.size())
	check(blank.is_empty(), "surfaces without a material: %s" % str(blank.slice(0, 8)))
	check(MaterialLibrary.report_unbound().size() == before, "apply() hit unbound names: %s" % str(MaterialLibrary.report_unbound()))


## Material names listed in the three materials.json files.
func _json_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for path: String in MaterialLibrary.MATERIAL_JSON:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(parsed is Dictionary, "cannot parse " + path)
		if not parsed is Dictionary:
			continue
		var mats: Variant = parsed.get("materials")
		if mats is Array:
			for m: Variant in mats:
				out.append(m["name"])
		elif mats is Dictionary:
			for k: String in mats.keys():
				out.append(k)
	return out


func _building_ids() -> Array[String]:
	var out: Array[String] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUILDINGS_JSON))
	check(parsed is Dictionary, "cannot parse buildings catalog")
	if parsed is Dictionary:
		for b: Variant in parsed["buildings"]:
			out.append(b["id"])
	return out


func _all_props() -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(PROPS_DIR):
		if f.ends_with(".glb"):
			out.append(PROPS_DIR + f)
	return out


func _all_glbs() -> Array[String]:
	var out: Array[String] = []
	for id: String in _building_ids():
		out.append(BUILDINGS_JSON.get_base_dir() + "/" + id + ".glb")
	out.append_array(_all_props())
	out.append(CITY_DIR + "city_01_road.glb")
	return out


func _instance_glb(path: String) -> Node3D:
	var packed: PackedScene = load(path) as PackedScene
	check(packed != null, "cannot load " + path)
	if packed == null:
		return Node3D.new()
	return packed.instantiate() as Node3D


func _glb_material_names(path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var root: Node3D = _instance_glb(path)
	for mi: MeshInstance3D in _meshes(root):
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			out.append(m.resource_name if m != null else "")
	root.free()
	return out


func _override_named(root: Node3D, mat_name: String) -> Material:
	for mi: MeshInstance3D in _meshes(root):
		for s: int in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			if m != null and m.resource_name == mat_name:
				return mi.get_surface_override_material(s)
	return null


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		out.append(root)
	for child: Node in root.get_children():
		out.append_array(_meshes(child))
	return out
