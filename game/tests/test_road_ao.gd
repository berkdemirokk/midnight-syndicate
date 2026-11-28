extends "res://tests/test_case.gd"
## Road contact AO: the wet asphalt shader samples a baked AO texture on UV2, every track road GLB carries that UV map
## and its baked PNG next to it, and MaterialLibrary.bind_road_ao attaches the texture to M_Asphalt surfaces.

const SHADER: String = "res://shaders/wet_asphalt.gdshader"
const ROADS: Array[String] = [
	"res://assets/world/city_01/city_01_road",
	"res://assets/world/istanbul_bogaz/istanbul_bogaz_road",
	"res://assets/world/istanbul_maslak/istanbul_maslak_road",
]


func test_asphalt_shader_has_ao_uniforms() -> void:
	var sh := load(SHADER) as Shader
	check(sh != null, "wet_asphalt shader loads")
	if sh == null:
		return
	var names: PackedStringArray = []
	for u: Dictionary in sh.get_shader_uniform_list():
		names.append(String(u["name"]))
	check(names.has("ao_tex"), "wet_asphalt has the baked AO sampler ao_tex")
	check(names.has("ao_strength"), "wet_asphalt has ao_strength")


func test_road_glbs_carry_uv2_and_ao_png() -> void:
	for base: String in ROADS:
		var glb: String = base + ".glb"
		var png: String = base + "_ao.png"
		check(ResourceLoader.exists(png), "%s exists" % png.get_file())
		var uv2_prims: int = _count_primitives_with(glb, "TEXCOORD_1")
		check(uv2_prims > 0, "%s has UV2 (TEXCOORD_1) on %d primitives" % [glb.get_file(), uv2_prims])


func test_bind_road_ao_sets_texture_on_asphalt() -> void:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	var m := ShaderMaterial.new()
	m.resource_name = "M_Asphalt"
	m.shader = load(SHADER) as Shader
	mi.set_surface_override_material(0, m)
	var bound: int = MaterialLibrary.bind_road_ao(root, ROADS[1] + "_ao.png")
	check(bound == 1, "one M_Asphalt surface bound")
	check(m.get_shader_parameter("ao_tex") is Texture2D, "ao_tex set on M_Asphalt")
	check(MaterialLibrary.bind_road_ao(root, "res://assets/world/none_ao.png") == 0, "missing AO PNG binds nothing")
	root.free()


## Number of mesh primitives in a GLB whose attributes include attr. Reads only the JSON chunk.
func _count_primitives_with(glb_path: String, attr: String) -> int:
	var f := FileAccess.open(glb_path, FileAccess.READ)
	if f == null:
		return -1
	var head: PackedByteArray = f.get_buffer(20)
	if head.size() < 20:
		return -1
	var doc: Variant = JSON.parse_string(f.get_buffer(head.decode_u32(12)).get_string_from_utf8())
	if not doc is Dictionary:
		return -1
	var n: int = 0
	for mesh: Dictionary in (doc as Dictionary).get("meshes", []):
		for prim: Dictionary in mesh.get("primitives", []):
			if (prim.get("attributes", {}) as Dictionary).has(attr):
				n += 1
	return n
