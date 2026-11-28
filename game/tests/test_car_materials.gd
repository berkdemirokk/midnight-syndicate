extends "res://tests/test_case.gd"
## Shared car materials: procedural maps load, paint finishes differ as set, glass/rim/tyre/trim properties
## are set, and every surface still gets exactly one material (no extra draw calls).

const SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const MAPS: PackedStringArray = [
	"car_flake_normal.png", "car_flake_roughness.png", "car_rubber_roughness.png",
	"car_brushed_roughness.png", "car_grain_normal.png", "car_carbon_weave.png", "car_carbon_normal.png",
]
const PROPS: PackedStringArray = [
	"anisotropy_enabled", "anisotropy", "rim_enabled", "rim", "rim_tint", "normal_texture", "roughness_texture",
	"clearcoat_enabled",
]


func _car() -> CarLod:
	# Not added to the tree: apply() only needs the nodes, so the test stays fast and does not run _ready.
	var packed: PackedScene = load(SCENE) as PackedScene
	return packed.instantiate() as CarLod


func _material(root: Node, nm: String) -> StandardMaterial3D:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var m: StandardMaterial3D = mi.get_active_material(s) as StandardMaterial3D
			if m != null and m.resource_name == nm:
				return m
	return null


func _surfaces(root: Node) -> Array[int]:
	# [known surfaces, of those with an engine override]: the counts must match after apply, or a part lost its material.
	var total: int = 0
	var overridden: int = 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var src: StandardMaterial3D = mi.mesh.surface_get_material(s) as StandardMaterial3D
			if src == null or not CarMaterials.KNOWN.has(src.resource_name):
				continue
			total += 1
			if mi.get_surface_override_material(s) != null:
				overridden += 1
	return [total, overridden]


func test_procedural_maps_load() -> void:
	for f: String in MAPS:
		var t: Texture2D = load("res://assets/vehicles/shared/" + f) as Texture2D
		check(t != null, "map missing or not imported: %s" % f)
		if t != null:
			check(t.get_width() >= 256 and t.get_width() == t.get_height(), "map %s is not square 256+" % f)


func test_engine_properties_exist() -> void:
	# Godot renames these between versions. Fail here with the name, not in a silent no-op.
	for p: String in PROPS:
		check(_has_prop(StandardMaterial3D.new(), p), "StandardMaterial3D has no property %s" % p)


func _has_prop(obj: Object, p: String) -> bool:
	for d: Dictionary in obj.get_property_list():
		if d["name"] == p:
			return true
	return false


func test_finishes_differ_and_keep_material_count() -> void:
	var car: CarLod = _car()
	var before: Array[int] = _surfaces(car)
	CarMaterials.apply(car, CarMaterials.DEFAULT_PAINT, CarMaterials.FINISH_SOLID)
	var solid: StandardMaterial3D = _material(car, "M_Paint")
	check(solid != null and solid.metallic == 0.0, "solid finish is not non-metallic")
	check(solid != null and not solid.rim_enabled, "solid finish has the pearl sheen")
	check(solid != null and is_equal_approx(solid.normal_scale, CarMaterials.PAINT_PEEL_SCALE), "solid finish normal is not orange peel only")
	CarMaterials.apply(car, CarMaterials.DEFAULT_PAINT, CarMaterials.FINISH_PEARL)
	var pearl: StandardMaterial3D = _material(car, "M_Paint")
	check(pearl != null and pearl.rim_enabled and is_equal_approx(pearl.metallic, CarMaterials.PAINT_PEARL_METALLIC), "pearl finish: rim %s metallic %s" % [pearl.rim_enabled if pearl else "-", pearl.metallic if pearl else "-"])
	check(pearl != null and pearl.clearcoat_enabled, "pearl finish lost its clearcoat")
	CarMaterials.apply(car, CarMaterials.DEFAULT_PAINT, CarMaterials.FINISH_METALLIC)
	var metal: StandardMaterial3D = _material(car, "M_Paint")
	check(metal != null and not metal.rim_enabled and is_equal_approx(metal.metallic, CarMaterials.PAINT_METALLIC), "metallic finish: rim %s metallic %s" % [metal.rim_enabled if metal else "-", metal.metallic if metal else "-"])
	var after: Array[int] = _surfaces(car)
	check(after[0] == before[0], "surface count changed: %d -> %d" % [before[0], after[0]])
	check(after[1] == after[0], "%d of %d surfaces without an engine material" % [after[0] - after[1], after[0]])
	metric("surfaces", after[0])
	car.free()


func test_surface_materials_set_properties() -> void:
	var car: CarLod = _car()
	CarMaterials.apply(car)
	var glass: StandardMaterial3D = _material(car, "M_Glass")
	check(glass != null and glass.rim_enabled and is_equal_approx(glass.rim, CarMaterials.GLASS_RIM), "glass has no rim edge")
	var rim: StandardMaterial3D = _material(car, "M_Rim")
	check(rim != null and rim.anisotropy_enabled, "rim is not anisotropic")
	var tire: StandardMaterial3D = _material(car, "M_Tire")
	check(tire != null and tire.roughness_texture != null, "tyre has no sidewall roughness map")
	var trim: StandardMaterial3D = _material(car, "M_Trim")
	check(trim != null and trim.normal_texture != null, "trim has no grain normal")
	var chrome: StandardMaterial3D = _material(car, "M_Chrome")
	check(chrome == null or chrome.metallic == 1.0, "chrome is not metallic")
	car.free()


func test_look_constants_in_range() -> void:
	# carpaint pass: a sharper street mirror and a glass tint that lets the interior show (alpha is opacity).
	check(CarMaterials.REFLECTION_BLUR_MAX > 0.0 and CarMaterials.REFLECTION_BLUR_MAX <= 2.0, "reflection blur cap out of range")
	check(CarMaterials.GLASS_TINT.a >= 0.5 and CarMaterials.GLASS_TINT.a <= 0.7, "glass opacity out of range")


func test_reflection_blur_cap_reaches_mirror_shader() -> void:
	# the carpaint sharpening is only real if the capped value is what the mirror shader reads
	var car: CarLod = _car()
	CarMaterials.apply(car)
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGB8))
	CarMaterials.set_reflection(car, tex, 0.5, 2.5, 0.0)
	var paint: StandardMaterial3D = _material(car, "M_Paint")
	var mirror: ShaderMaterial = paint.next_pass as ShaderMaterial if paint != null else null
	check(mirror != null, "paint has no mirror pass")
	if mirror != null:
		check(is_equal_approx(float(mirror.get_shader_parameter("blur")), CarMaterials.REFLECTION_BLUR_MAX), "mirror blur not capped")
	car.free()


func test_glass_tint_and_specular_reach_glass_material() -> void:
	var car: CarLod = _car()
	CarMaterials.apply(car)
	var glass: StandardMaterial3D = _material(car, "M_Glass")
	check(glass != null and is_equal_approx(glass.albedo_color.a, CarMaterials.GLASS_TINT.a), "glass alpha is not GLASS_TINT.a")
	check(glass != null and is_equal_approx(glass.metallic_specular, CarMaterials.GLASS_SPECULAR), "glass specular is not GLASS_SPECULAR")
	car.free()
