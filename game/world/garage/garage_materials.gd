class_name GarageMaterials
extends RefCounted
## Garage room materials. Reads materials.json (written by assets_src/world/garage) and binds one
## StandardMaterial3D per room material name onto the room GLB. The GLB carries flat colours only; maps come
## from the CC0 sets in assets/textures/cc0 and the project-owned pegboard texture.
## UVs are world metres, so the texture repeat is 1 / uv_tiling_m.

const DATA_PATH: String = "res://assets/world/garage/materials.json"
const CC0_DIR: String = "res://assets/textures/cc0/"
const GARAGE_DIR: String = "res://assets/world/garage/"
const EMISSION_SCALE: float = 1.0  ## multiplies the HDR emissive strength from materials.json

static var _table: Dictionary = {}
static var _built: Dictionary = {}


## Name -> entry dictionary from materials.json. Read once.
static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			for e: Variant in (parsed as Dictionary).get("materials", []):
				if e is Dictionary:
					_table[str((e as Dictionary)["name"])] = e
	return _table


## Material for one room material name, built once and shared. Null for unknown names.
static func material(nm: String) -> StandardMaterial3D:
	if _built.has(nm):
		return _built[nm] as StandardMaterial3D
	if not table().has(nm):
		return null
	var m: StandardMaterial3D = _build(table()[nm] as Dictionary)
	_built[nm] = m
	return m


## Overrides every surface whose material name is in materials.json. Returns the number of surfaces bound.
static func bind(root: Node) -> int:
	var bound: int = 0
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(s)
			if src == null:
				continue
			var m: StandardMaterial3D = material(src.resource_name)
			if m != null:
				mi.set_surface_override_material(s, m)
				bound += 1
	return bound


static func _build(e: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = str(e["name"])
	var base: Array = e["base_color_linear"]
	m.albedo_color = Color(float(base[0]), float(base[1]), float(base[2]))
	m.roughness = float(e["roughness"])
	m.metallic = float(e["metallic"])
	var tiling: float = maxf(float(e["uv_tiling_m"]), 0.01)
	m.uv1_scale = Vector3.ONE / tiling
	var cc0: Variant = e.get("cc0_texture_id")
	if cc0 is String and not (cc0 as String).is_empty():
		_set_cc0(m, cc0 as String)
	var gen: Variant = e.get("generated_texture")
	if gen is String and not (gen as String).is_empty():
		m.albedo_texture = load(GARAGE_DIR + (gen as String).get_file()) as Texture2D
	var strength: float = float(e["emissive_strength"])
	if strength > 0.0:
		var ec: Array = e["emissive_color_linear"]
		m.emission_enabled = true
		m.emission = Color(float(ec[0]), float(ec[1]), float(ec[2]))
		m.emission_energy_multiplier = strength * EMISSION_SCALE
	return m


static func _set_cc0(m: StandardMaterial3D, id: String) -> void:
	var dir: String = CC0_DIR + id + "/"
	m.albedo_texture = load(dir + "basecolor.jpg") as Texture2D
	m.normal_enabled = true
	m.normal_texture = load(dir + "normal.jpg") as Texture2D
	m.roughness_texture = load(dir + "roughness.jpg") as Texture2D
