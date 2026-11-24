class_name MaterialLibrary
extends RefCounted
## One shared material per material name from the three city_01 materials.json files. Bind by name on
## any imported node tree with MaterialLibrary.apply(root, building_id). Shared materials are the same
## instance everywhere (instancing friendly). The impostor atlas is the exception: one per building id.
## Unknown names get a magenta debug material and are listed by report_unbound().
## All state is static: there is no instance to create.

const MATERIAL_JSON: Array[String] = [
	"res://assets/world/city_01/road/materials.json",
	"res://assets/world/kits/buildings/materials.json",
	"res://assets/world/kits/props/materials.json",
]
const CC0_ROOT: String = "res://assets/textures/cc0/"
const BUILDING_TEX: String = "res://assets/world/kits/buildings/textures/"
const PROP_TEX: String = "res://assets/world/kits/props/"
const ASPHALT_SHADER: String = "res://shaders/wet_asphalt.gdshader"
const NEON_SHADER: String = "res://shaders/neon.gdshader"
const TUNNEL_SHADER: String = "res://shaders/tunnel_light.gdshader"
const WATER_SHADER: String = "res://world/materials/water.gdshader"
const WINDOW_SHADER: String = "res://world/materials/window_atlas.gdshader"
## CC0 set used for names whose JSON entry carries no texture of its own.
const CC0_SETS: Dictionary = {
	"M_Curb": "brushed_concrete_03",
	"M_Paving": "concrete_pavers_02",
	"M_Ground": "concrete_pavement_03",
	"M_Concrete_Wall": "concrete_wall_006",
}
const ASPHALT_SET: String = "asphalt_02"
const WATER_NORMAL_SET: String = "asphalt_04"
## Names rendered unshaded with neon.gdshader (HDR colour that feeds the glow).
const NEON_PREFIXES: Array[String] = ["M_Neon_", "M_Bulb_", "M_Lamp_", "M_Signal_Red", "M_CeilingStrip", "M_TunnelLight", "M_Aircraft_Red"]

static var tuning: WorldMaterialTuning = WorldMaterialTuning.new()
static var _recipes: Dictionary = {}          # name -> recipe Dictionary (from the JSON files)
static var _shared: Dictionary = {}           # name -> Material (shared instance)
static var _per_building: Dictionary = {}     # "name|building_id" -> Material
static var _unbound: Dictionary = {}          # name -> hits that fell back to magenta
static var _textures_used: Dictionary = {}    # res:// path -> true
static var _debug: StandardMaterial3D


## True when the name has a recipe in one of the materials.json files.
static func is_bound(mat_name: String) -> bool:
	_ensure_loaded()
	return _recipes.has(mat_name)


static func known_names() -> PackedStringArray:
	_ensure_loaded()
	return PackedStringArray(_recipes.keys())


## Material for one name. Unknown names return the magenta debug material and are counted.
static func get_material(mat_name: String, building_id: String = "") -> Material:
	_ensure_loaded()
	if not _recipes.has(mat_name):
		_unbound[mat_name] = int(_unbound.get(mat_name, 0)) + 1
		return _magenta()
	if mat_name == "M_ImpostorAtlas" and building_id != "":
		var key: String = mat_name + "|" + building_id
		if not _per_building.has(key):
			_per_building[key] = _impostor(building_id)
		return _per_building[key]
	if not _shared.has(mat_name):
		_shared[mat_name] = _build(mat_name)
	return _shared[mat_name]


## Binds every mesh surface under root to its library material. Returns the number of surfaces bound.
static func apply(root: Node, building_id: String = "") -> int:
	var bound: int = 0
	for mi: MeshInstance3D in _meshes(root):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s: int in mesh.get_surface_count():
			var src: Material = mesh.surface_get_material(s)
			var mat_name: String = src.resource_name if src != null else ""
			mi.set_surface_override_material(s, get_material(mat_name, building_id))
			bound += 1
		_set_lod_range(mi)
	return bound


## Building GLBs ship LOD0, LOD1 and LOD2 as sibling nodes. Godot keeps all three visible unless a
## visibility range is set, and the LOD2 impostor box would cover the facade, so each LOD gets a range.
static func _set_lod_range(mi: MeshInstance3D) -> void:
	var lod: int = -1
	var n: Node = mi
	while n != null and lod < 0:
		var nm: String = n.name
		if nm.length() == 4 and nm.begins_with("LOD") and nm.substr(3, 1).is_valid_int():
			lod = nm.substr(3, 1).to_int()
		n = n.get_parent()
	if lod < 0:
		return
	mi.visibility_range_begin = 0.0 if lod == 0 else (tuning.lod0_end_m if lod == 1 else tuning.lod1_end_m)
	mi.visibility_range_end = tuning.lod0_end_m if lod == 0 else (tuning.lod1_end_m if lod == 1 else 0.0)


## Names that fell back to magenta since start, with hit counts. Empty means nothing is blank.
static func report_unbound() -> Dictionary:
	return _unbound.duplicate()


## Every res:// texture path handed to a material so far (tests check each one exists).
static func texture_paths_used() -> PackedStringArray:
	return PackedStringArray(_textures_used.keys())


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child: Node in root.get_children():
		out.append_array(_meshes(child))
	return out


static func _ensure_loaded() -> void:
	if not _recipes.is_empty():
		return
	for path: String in MATERIAL_JSON:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			push_error("MaterialLibrary: cannot parse " + path)
			continue
		var mats: Variant = parsed.get("materials")
		var entries: Array = []
		if mats is Array:
			entries = mats  # road: list of dicts with "name"
		elif mats is Dictionary:
			for k: String in mats.keys():  # kits: dict keyed by name
				var e: Dictionary = mats[k]
				e["name"] = k
				entries.append(e)
		for e: Variant in entries:
			var d: Dictionary = e
			var n: String = d["name"]
			if _recipes.has(n):
				continue  # first file wins if a name repeats
			_recipes[n] = _recipe_from(d, path)


static func _recipe_from(d: Dictionary, json_path: String) -> Dictionary:
	var colour: Color = _colour(d.get("base_colour_srgb", d.get("base_color")))
	var emit: Color = _colour(d.get("emissive_srgb", d.get("emission_color")))
	var tex: Dictionary = {}
	var from_kit: bool = json_path.contains("kits/props")
	if d.get("textures") is Dictionary:
		for k: String in d["textures"]:
			tex[k] = "res://" + String(d["textures"][k]).trim_prefix("game/")
	var texture: String = ""
	if d.get("texture") is String:
		texture = PROP_TEX + String(d["texture"])
	return {
		"colour": colour,
		"roughness": float(d.get("roughness", 0.5)),
		"metallic": float(d.get("metallic", 0.0)),
		"emit": emit,
		"emit_strength": float(d.get("emissive_strength", d.get("emission_strength", 0.0))),
		"textures": tex,
		"texture": texture,
		"tile_m": float(d.get("uv_tile_m", tuning.texture_tile_m)),
		"kit": from_kit,
	}


static func _colour(v: Variant) -> Color:
	if v is String:
		return Color.html(v) if String(v).begins_with("#") else Color.BLACK
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return Color.BLACK


static func _build(mat_name: String) -> Material:
	var r: Dictionary = _recipes[mat_name]
	if mat_name == "M_Asphalt":
		return _asphalt()
	if mat_name == "M_Water":
		return _water()
	if mat_name == "M_WindowAtlas":
		var w: ShaderMaterial = _emissive_atlas(mat_name, BUILDING_TEX + "window_atlas_basecolor.png", BUILDING_TEX + "window_atlas_emissive.png", tuning.window_energy_scale)
		# Panes are glass, not lit plaster: dark, glossy, reflective.
		w.set_shader_parameter("albedo_scale", tuning.pane_albedo_scale)
		w.set_shader_parameter("roughness_value", tuning.pane_roughness)
		w.set_shader_parameter("metallic_value", tuning.pane_metallic)
		w.set_shader_parameter("cell_size_m", tuning.pane_cell_size_m)
		w.set_shader_parameter("lit_fraction", tuning.pane_lit_fraction)
		return w
	if mat_name == "M_ShopInterior":
		return _emissive_atlas(mat_name, BUILDING_TEX + "shop_interior_basecolor.png", BUILDING_TEX + "shop_interior_emissive.png", tuning.shop_energy_scale)
	if mat_name == "M_ShopGlass":
		return _glass(mat_name, r)
	if mat_name == "M_TunnelLight":
		return _tunnel_light(r)
	if _is_neon(mat_name):
		return _neon(mat_name, r)
	return _standard(mat_name, r)


static func _tunnel_light(r: Dictionary) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.resource_name = "M_TunnelLight"
	sm.shader = load(TUNNEL_SHADER) as Shader
	sm.set_shader_parameter("base_color", r["emit"])
	sm.set_shader_parameter("energy", tuning.tunnel_light_energy)
	sm.set_shader_parameter("run_dir", tuning.tunnel_run_dir.normalized())
	sm.set_shader_parameter("lit_m", tuning.tunnel_light_lit_m)
	sm.set_shader_parameter("period_m", tuning.tunnel_light_period_m)
	return sm


static func _is_neon(mat_name: String) -> bool:
	for p: String in NEON_PREFIXES:
		if mat_name.begins_with(p) or mat_name == p:
			return true
	return false


static func _standard(mat_name: String, r: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	var tex: Dictionary = r["textures"]
	var kit_tex: bool = r["kit"]
	if tex.is_empty() and CC0_SETS.has(mat_name):
		tex = _cc0_set(CC0_SETS[mat_name])
	var wet: float = tuning.wetness if not tex.is_empty() else 0.0
	var c: Color = r["colour"]
	m.albedo_color = Color(c.r * (1.0 - 0.3 * wet), c.g * (1.0 - 0.3 * wet), c.b * (1.0 - 0.3 * wet))
	m.roughness = clampf(float(r["roughness"]) * (1.0 - 0.5 * wet), 0.08, 1.0)
	m.metallic = float(r["metallic"])
	if tex.has("basecolor"):
		m.albedo_texture = _tex(tex["basecolor"])
	if tex.has("normal"):
		m.normal_enabled = true
		m.normal_texture = _tex(tex["normal"])
	if tex.has("roughness"):
		m.roughness_texture = _tex(tex["roughness"])
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if not tex.is_empty() and not kit_tex:
		# Walls and ground have no UVs in metres, so project them in world space.
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / float(r["tile_m"])
	if String(r["texture"]) != "":
		m.albedo_texture = _tex(r["texture"])
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission = Color.WHITE
		m.emission_energy_multiplier = float(r["emit_strength"]) * (tuning.skyline_emission_scale if mat_name == "M_Skyline" else 1.0)
		return m
	var emit_strength: float = float(r["emit_strength"])
	if mat_name == "M_TunnelStripe":
		m.albedo_color = tuning.tunnel_stripe_colour
		m.roughness = tuning.tunnel_stripe_roughness
		return m
	if mat_name == "M_Curb":
		m.albedo_color = _scale_rgb(m.albedo_color, tuning.kerb_albedo_scale)
	if mat_name == "M_Paving":
		m.albedo_color = _scale_rgb(m.albedo_color, tuning.sidewalk_albedo_scale)
	if mat_name == "M_RoadPaint":
		# Wet worn paint: grey-white, glossy, readable under lamps and headlights, never brighter
		# than the lit scene around it.
		m.albedo_color = Color(tuning.road_paint_albedo, tuning.road_paint_albedo, tuning.road_paint_albedo * 0.97)
		m.roughness = tuning.road_paint_roughness
		emit_strength = tuning.road_paint_glow
	if emit_strength > 0.0:
		m.emission_enabled = true
		m.emission = r["emit"]
		m.emission_energy_multiplier = emit_strength
	return m


static func _neon(mat_name: String, r: Dictionary) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.resource_name = mat_name
	sm.shader = load(NEON_SHADER) as Shader
	var colour: Color = r["emit"] if r["emit"] != Color.BLACK else r["colour"]
	sm.set_shader_parameter("base_color", colour)
	var energy: float = float(r["emit_strength"]) * tuning.neon_energy_scale
	if mat_name.begins_with("M_CeilingStrip"):
		energy *= tuning.ceiling_energy_scale
	sm.set_shader_parameter("energy", clampf(energy, 0.0, 16.0))
	return sm


static func _scale_rgb(c: Color, s: float) -> Color:
	return Color(c.r * s, c.g * s, c.b * s, c.a)


static func _asphalt() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.resource_name = "M_Asphalt"
	sm.shader = load(ASPHALT_SHADER) as Shader
	var set_tex: Dictionary = _cc0_set(ASPHALT_SET)
	sm.set_shader_parameter("albedo_tex", _tex(set_tex["basecolor"]))
	sm.set_shader_parameter("normal_tex", _tex(set_tex["normal"]))
	sm.set_shader_parameter("roughness_tex", _tex(set_tex["roughness"]))
	sm.set_shader_parameter("tile_metres", tuning.asphalt_tile_m)
	sm.set_shader_parameter("wetness", 1.0)
	sm.set_shader_parameter("puddle_level", tuning.asphalt_puddle_level)
	sm.set_shader_parameter("rain_intensity", tuning.asphalt_rain)
	return sm


static func _water() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.resource_name = "M_Water"
	sm.shader = load(WATER_SHADER) as Shader
	sm.set_shader_parameter("normal_tex", _tex(_cc0_set(WATER_NORMAL_SET)["normal"]))
	sm.set_shader_parameter("scroll", tuning.water_scroll)
	return sm


## Window and shop atlases glow only above a threshold (window_atlas.gdshader), see the shader header.
static func _emissive_atlas(mat_name: String, base_path: String, emit_path: String, scale: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.resource_name = mat_name
	sm.shader = load(WINDOW_SHADER) as Shader
	var r: Dictionary = _recipes[mat_name]
	sm.set_shader_parameter("albedo_tex", _tex(base_path))
	sm.set_shader_parameter("emissive_tex", _tex(emit_path))
	var facade: Color = r["colour"] * tuning.facade_albedo_scale
	sm.set_shader_parameter("tint", Color(facade.r, facade.g, facade.b))
	sm.set_shader_parameter("glow_tint", Vector3(tuning.window_glow_tint.r, tuning.window_glow_tint.g, tuning.window_glow_tint.b))
	sm.set_shader_parameter("glow_energy", float(r["emit_strength"]) * scale)
	sm.set_shader_parameter("glow_threshold", tuning.window_glow_threshold)
	sm.set_shader_parameter("glow_saturation", tuning.window_glow_saturation)
	return sm


static func _glass(mat_name: String, r: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.albedo_color = Color(r["colour"].r, r["colour"].g, r["colour"].b, tuning.glass_alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 0.8
	return m


## Far buildings. The impostor emissive texture is grey across the whole facade, so it goes through
## the same threshold as the window atlas; without it a far tower renders as a white slab.
static func _impostor(building_id: String) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.resource_name = "M_ImpostorAtlas"
	sm.shader = load(WINDOW_SHADER) as Shader
	sm.set_shader_parameter("albedo_tex", _tex(BUILDING_TEX + "impostor_%s_basecolor.png" % building_id))
	sm.set_shader_parameter("emissive_tex", _tex(BUILDING_TEX + "impostor_%s_emissive.png" % building_id))
	sm.set_shader_parameter("tint", Color.WHITE)
	sm.set_shader_parameter("albedo_scale", tuning.impostor_albedo_scale)
	sm.set_shader_parameter("roughness_value", 0.8)
	sm.set_shader_parameter("glow_tint", Vector3(tuning.window_glow_tint.r, tuning.window_glow_tint.g, tuning.window_glow_tint.b))
	sm.set_shader_parameter("glow_energy", float(_recipes["M_ImpostorAtlas"]["emit_strength"]) * tuning.window_energy_scale)
	sm.set_shader_parameter("glow_threshold", tuning.window_glow_threshold)
	sm.set_shader_parameter("glow_saturation", tuning.window_glow_saturation)
	return sm


static func _cc0_set(set_id: String) -> Dictionary:
	var root: String = CC0_ROOT + set_id + "/"
	return {"basecolor": root + "basecolor.jpg", "normal": root + "normal.jpg", "roughness": root + "roughness.jpg"}


static func _tex(path: String) -> Texture2D:
	_textures_used[path] = true
	var t: Texture2D = load(path) as Texture2D
	if t == null:
		push_error("MaterialLibrary: missing texture " + path)
	return t


static func _magenta() -> StandardMaterial3D:
	if _debug == null:
		_debug = StandardMaterial3D.new()
		_debug.resource_name = "M_Unbound_Debug"
		_debug.albedo_color = Color(1.0, 0.0, 1.0)
		_debug.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _debug
