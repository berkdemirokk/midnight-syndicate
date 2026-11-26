extends "res://tests/test_case.gd"
## Road look: the wet asphalt shader keeps its wet uniforms and gains the daylight detail uniform, and the
## road material built by MaterialLibrary binds it. The grain and patches are shader maths, checked by capture.

const SHADER: String = "res://shaders/wet_asphalt.gdshader"


func test_asphalt_shader_uniforms() -> void:
	var sh := load(SHADER) as Shader
	check(sh != null, "wet_asphalt shader loads")
	if sh == null:
		return
	var names: PackedStringArray = []
	for u: Dictionary in sh.get_shader_uniform_list():
		names.append(String(u["name"]))
	for key: String in ["wetness", "puddle_level", "rain_intensity", "tint", "planar_enabled", "planar_vp", "tile_metres", "dry_detail"]:
		check(names.has(key), "wet_asphalt keeps or gains uniform %s" % key)


func test_road_material_binds_daylight_detail() -> void:
	var m := MaterialLibrary.get_material("M_Asphalt") as ShaderMaterial
	check(m != null, "M_Asphalt builds a ShaderMaterial")
	if m == null:
		return
	check(m.shader != null and m.shader.resource_path == SHADER, "M_Asphalt uses wet_asphalt.gdshader")
	check(m.get_shader_parameter("albedo_tex") != null, "M_Asphalt has the albedo texture")
	check(m.get_shader_parameter("normal_tex") != null, "M_Asphalt has the normal texture")
	var dd: Variant = m.get_shader_parameter("dry_detail")
	# Unset means the shader default (1.0); when set it must stay in range.
	check(dd == null or (float(dd) >= 0.0 and float(dd) <= 1.0), "dry_detail within 0..1")
