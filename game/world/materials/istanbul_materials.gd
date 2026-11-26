class_name IstanbulMaterials
extends RefCounted
## Materials of the Istanbul kit (assets/world/kits/istanbul). Only the three far skyline cards need code:
## they are the existing window_atlas shader on a single texture (albedo = emission), like M_Skyline, but
## with skyline_towers = 0 because the card mesh is already cut to its own silhouette.
## Every other new name (M_Plaster_Butter, M_Wood_Yali_Dark, M_Roof_Tile, M_Cobble, M_Cart_Teal, ...) is a
## plain recipe in istanbul/materials.json and goes through MaterialLibrary._standard / _facade unchanged.
##
## Wiring (material_library.gd, owned by the lead, NOT edited here):
##   1. add "res://assets/world/kits/istanbul/materials.json" to MATERIAL_JSON (last entry);
##   2. in _build(), first line:  if IstanbulMaterials.handles(mat_name): return IstanbulMaterials.build(mat_name)
##   3. impostor textures: istanbul LOD2 atlases are also copied to kits/buildings/textures/ so the existing
##      _impostor(building_id) lookup works without change.

const JSON_PATH: String = "res://assets/world/kits/istanbul/materials.json"
const TEX_DIR: String = "res://assets/world/kits/istanbul/textures/"
const SKYLINES: Dictionary = {
	"M_Skyline_Asia": "skyline_asia.png",
	"M_Skyline_Bridge": "skyline_bridge.png",
	"M_Skyline_Domes": "skyline_domes.png",
}
const WINDOW_SHADER: String = "res://world/materials/window_atlas.gdshader"


static func handles(mat_name: String) -> bool:
	return SKYLINES.has(mat_name)


static func build(mat_name: String) -> Material:
	var tex: Texture2D = load(TEX_DIR + String(SKYLINES[mat_name])) as Texture2D
	var t: WorldMaterialTuning = MaterialLibrary.tuning
	var sm := ShaderMaterial.new()
	sm.resource_name = mat_name
	sm.shader = load(WINDOW_SHADER) as Shader
	sm.set_shader_parameter("albedo_tex", tex)
	sm.set_shader_parameter("emissive_tex", tex)
	sm.set_shader_parameter("tint", t.skyline_tint)
	sm.set_shader_parameter("albedo_scale", 1.0)
	sm.set_shader_parameter("roughness_value", 0.9)
	sm.set_shader_parameter("glow_tint", Vector3(t.window_glow_tint.r, t.window_glow_tint.g, t.window_glow_tint.b))
	sm.set_shader_parameter("glow_energy", t.skyline_window_energy)
	sm.set_shader_parameter("glow_threshold", t.window_glow_threshold)
	sm.set_shader_parameter("glow_saturation", t.window_glow_saturation)
	sm.set_shader_parameter("skyline_towers", 0.0)
	return sm
