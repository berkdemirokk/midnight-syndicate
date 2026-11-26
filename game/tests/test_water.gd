extends "res://tests/test_case.gd"
## Sea material (world/materials/water.gdshader, M_Water): the two generated slope maps load and are centred and
## varied, the shader exposes the uniforms the time of day drives, and the library builds the material with both maps.

const SWELL_PATH: String = "res://assets/world/water/water_swell.png"
const CHOP_PATH: String = "res://assets/world/water/water_chop.png"
const SHADER_PATH: String = "res://world/materials/water.gdshader"
const DRIVEN_UNIFORMS: PackedStringArray = ["zenith_colour", "horizon_colour", "sky_fill", "deep_colour", "shallow_colour"]


func test_slope_maps_centred_and_varied() -> void:
	for p: String in [SWELL_PATH, CHOP_PATH]:
		var img: Image = (load(p) as Texture2D).get_image()
		check(img != null, "%s did not load" % p)
		if img == null:
			continue
		check(img.get_width() == 512 and img.get_height() == 512, "%s is %dx%d, expected 512x512" % [p, img.get_width(), img.get_height()])
		var sum: float = 0.0
		var sum2: float = 0.0
		var n: int = 0
		for y: int in range(0, img.get_height(), 4):
			for x: int in range(0, img.get_width(), 4):
				var c: Color = img.get_pixel(x, y)
				sum += c.r
				sum2 += c.r * c.r
				n += 1
		var mean: float = sum / n
		var sd: float = sqrt(maxf(sum2 / n - mean * mean, 0.0))
		metric("water_slope_sd_%s" % p.get_file().get_basename(), snappedf(sd, 0.001))
		check(absf(mean - 0.5) < 0.05, "%s slope not centred: mean red %.3f" % [p, mean])
		check(sd > 0.08, "%s slope too flat: sd %.3f" % [p, sd])


func test_material_builds_with_maps_and_uniforms() -> void:
	var m: Material = MaterialLibrary.get_material("M_Water")
	check(m is ShaderMaterial, "M_Water is not a ShaderMaterial")
	if not (m is ShaderMaterial):
		return
	var sm: ShaderMaterial = m
	check(sm.shader != null and sm.shader.resource_path == SHADER_PATH, "M_Water does not use water.gdshader")
	check(sm.get_shader_parameter("swell_tex") is Texture2D, "swell_tex not set")
	check(sm.get_shader_parameter("chop_tex") is Texture2D, "chop_tex not set")
	var names: PackedStringArray = PackedStringArray()
	for u: Dictionary in sm.shader.get_shader_uniform_list():
		names.append(String(u["name"]))
	for k: String in DRIVEN_UNIFORMS:
		check(names.has(k), "water.gdshader has no uniform %s (time of day drives it)" % k)


func test_shader_no_screen_space_or_depth() -> void:
	var src: String = FileAccess.get_file_as_string(SHADER_PATH)
	check(src.find("SCREEN_TEXTURE") < 0 and src.find("DEPTH_TEXTURE") < 0 and src.find("SCREEN_UV") < 0,
		"water.gdshader reads screen or depth data; the sea must stay screen-space free")
