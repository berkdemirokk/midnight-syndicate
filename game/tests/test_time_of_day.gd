extends "res://tests/test_case.gd"
## Time of day (world/time_of_day/time_of_day.gd): presets, the night no-op, environment, lights, material scaling and restore,
## RaceConfig field, and a real city race at day (sun with one shadow, no rain, no headlights, no lamps).

const CITY_PATH: String = "res://world/city_01/city_01.tscn"
const SCENE_PATH: String = "res://race/race_scene.tscn"
const WINDOW_SHADER: String = "res://world/materials/window_atlas.gdshader"
const NEON_SHADER: String = "res://shaders/neon.gdshader"
const ASPHALT_SHADER: String = "res://shaders/wet_asphalt.gdshader"
const EPS: float = 0.0001


func _shader_mat(path: String, res_name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.resource_name = res_name
	m.shader = load(path) as Shader
	return m


func test_presets() -> void:
	var day: TimeOfDay = TimeOfDay.preset("day")
	var sunset: TimeOfDay = TimeOfDay.preset("sunset")
	var night: TimeOfDay = TimeOfDay.preset("night")
	check(day.id == "day" and sunset.id == "sunset" and night.id == "night", "preset ids")
	check(TimeOfDay.preset("nonsense").is_night(), "an unknown id is night")
	check(TimeOfDay.is_valid("day") and not TimeOfDay.is_valid("noon"), "is_valid")
	# day: strong sun, dim signs, glass windows, no lamps, dry road, no rain, no headlights
	check(day.sun_energy > sunset.sun_energy * 0.9 and day.sun_elevation_deg > 40.0, "day sun is high and strong")
	check(not day.lamps_on and day.window_scale == 0.0 and day.neon_scale < 0.3, "day: lamps off, windows not emissive, neon dim")
	check(day.road_wetness < 0.3 and not day.rain and not day.headlights_on, "day: dry road, no rain, no headlights")
	# sunset: low warm sun, lamps and headlights on, no rain
	check(sunset.sun_elevation_deg < 15.0 and sunset.sun_color.r > sunset.sun_color.b, "sunset: low warm sun")
	check(sunset.lamps_on and sunset.headlights_on and not sunset.rain, "sunset: lamps and headlights on, no rain")
	# night is the shipped look
	check(night.lamps_on and night.headlights_on and night.rain and night.window_scale == 1.0 and night.neon_scale == 1.0, "night defaults")
	check(day.sun_shadows and day.shadow_max_distance_m >= 60.0 and day.shadow_max_distance_m <= 80.0, "day shadow distance 60 to 80 m")
	# the sun vector follows elevation
	check_range(day.sun_vector().y, sin(deg_to_rad(day.sun_elevation_deg)) - EPS, sin(deg_to_rad(day.sun_elevation_deg)) + EPS, "sun vector height")
	# heading rotates the azimuth: dead ahead at 0 offset
	var ahead := TimeOfDay.new()
	ahead.sun_elevation_deg = 0.0
	ahead.sun_azimuth_deg = 0.0
	var v: Vector3 = ahead.sun_vector(90.0)
	check(v.x > 0.99, "sun_azimuth 0 stands in the heading direction")


func test_night_environment_untouched() -> void:
	var env := Environment.new()
	env.ambient_light_energy = 1.2
	env.tonemap_exposure = 1.0
	var sky := Sky.new()
	env.sky = sky
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.25
	sun.shadow_enabled = false
	sun.name = "Moon"
	TimeOfDay.preset("night").apply_environment(env, sun, 33.0)
	check(env.sky == sky and is_equal_approx(env.ambient_light_energy, 1.2), "night leaves the environment")
	check(sun.name == "Moon" and not sun.shadow_enabled and is_equal_approx(sun.light_energy, 0.25), "night leaves the moon")
	var env2 := Environment.new()
	env2.glow_intensity = 0.8
	TimeOfDay.preset("night").apply_after_settings(env2)
	check(is_equal_approx(env2.glow_intensity, 0.8), "night leaves the glow")
	sun.free()


func test_day_environment() -> void:
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	var day: TimeOfDay = TimeOfDay.preset("day")
	day.apply_environment(env, sun, 40.0)
	check(env.sky != null and env.sky.sky_material is ShaderMaterial, "day sets a sky shader")
	var sm: ShaderMaterial = env.sky.sky_material as ShaderMaterial
	check(sm.shader.resource_path.ends_with("day_sky.gdshader"), "day sky shader")
	var sd: Vector3 = sm.get_shader_parameter("sun_dir")
	check(sd.distance_to(day.sun_vector(40.0)) < EPS, "the sky sun disk sits where the light comes from")
	check(env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY, "day ambient comes from the sky")
	check(sun.name == "Sun" and is_equal_approx(sun.light_energy, day.sun_energy), "the directional light becomes the sun")
	var dir: Vector3 = -sun.global_transform.basis.z if sun.is_inside_tree() else -sun.basis.z
	check(dir.distance_to(-day.sun_vector(40.0)) < 0.001, "the sun shines from the sun vector toward the ground")
	var low: bool = Settings.get_preset_id() == "low"
	check(sun.shadow_enabled == not low, "one directional shadow, none on Low")
	check(sun.directional_shadow_max_distance <= 80.0 and sun.directional_shadow_max_distance >= 60.0, "shadow distance 60 to 80 m")
	var env2 := Environment.new()
	env2.glow_intensity = 0.8
	day.apply_after_settings(env2)
	check(env2.glow_intensity < 0.8, "day pulls the glow back")
	sun.free()


func test_material_scaling_and_restore() -> void:
	var win: ShaderMaterial = _shader_mat(WINDOW_SHADER, "M_WindowAtlas")
	win.set_shader_parameter("glow_energy", 3.0)
	win.set_shader_parameter("albedo_scale", 0.22)
	win.set_shader_parameter("metallic_value", 0.55)
	var sky: ShaderMaterial = _shader_mat(WINDOW_SHADER, "M_Skyline_Asia")
	sky.set_shader_parameter("glow_energy", 2.2)
	sky.set_shader_parameter("tint", Vector3(0.4, 0.4, 0.5))
	var neon: ShaderMaterial = _shader_mat(NEON_SHADER, "M_Neon_Cyan")
	neon.set_shader_parameter("energy", 4.0)
	var strip: ShaderMaterial = _shader_mat(NEON_SHADER, "M_CeilingStrip")
	strip.set_shader_parameter("energy", 0.3)
	var road: ShaderMaterial = _shader_mat(ASPHALT_SHADER, "M_Asphalt")
	road.set_shader_parameter("wetness", 1.0)
	road.set_shader_parameter("puddle_level", 0.6)
	road.set_shader_parameter("rain_intensity", 0.2)
	var post := StandardMaterial3D.new()
	post.resource_name = "M_Poster_01"
	post.emission_enabled = true
	post.emission_energy_multiplier = 2.2
	var paint := StandardMaterial3D.new()
	paint.resource_name = "M_RoadPaint"
	paint.emission_enabled = true
	paint.emission_energy_multiplier = 0.05
	var day: TimeOfDay = TimeOfDay.preset("day")
	for m: Material in [win, sky, neon, strip, road, post, paint]:
		day.tune_material(m)
	check(float(win.get_shader_parameter("glow_energy")) == 0.0, "day: window glow off")
	check(float(win.get_shader_parameter("albedo_scale")) > 0.22, "day: pane glass lighter")
	check(float(sky.get_shader_parameter("glow_energy")) == 0.0, "day: skyline glow off")
	check((sky.get_shader_parameter("tint") as Vector3).x > 0.4, "day: skyline cards paler")
	check_range(float(neon.get_shader_parameter("energy")), 0.1, 1.0, "day neon energy")
	check(is_equal_approx(float(strip.get_shader_parameter("energy")), 0.3), "tunnel ceiling strip keeps its light at day")
	check(float(road.get_shader_parameter("wetness")) < 0.3 and float(road.get_shader_parameter("puddle_level")) == 0.0, "day: dry road")
	check(post.emission_energy_multiplier < 1.0, "day: poster emission dimmed")
	check(is_equal_approx(paint.emission_energy_multiplier, 0.05), "road paint keeps its emission")
	# sunset then night restores the authored values exactly
	var sunset: TimeOfDay = TimeOfDay.preset("sunset")
	for m: Material in [win, sky, neon, strip, road, post, paint]:
		sunset.tune_material(m)
	check_range(float(win.get_shader_parameter("glow_energy")), 0.5, 2.9, "sunset window glow")  # blue hour: windows almost at night strength (was capped at 2.5 for the pink sunset)
	var night: TimeOfDay = TimeOfDay.preset("night")
	for m: Material in [win, sky, neon, strip, road, post, paint]:
		night.tune_material(m)
	check(is_equal_approx(float(win.get_shader_parameter("glow_energy")), 3.0), "night restores window glow")
	check(is_equal_approx(float(win.get_shader_parameter("albedo_scale")), 0.22), "night restores pane albedo")
	check(is_equal_approx(float(win.get_shader_parameter("metallic_value")), 0.55), "night restores pane metallic")
	check(is_equal_approx(float(sky.get_shader_parameter("glow_energy")), 2.2), "night restores skyline glow")
	check((sky.get_shader_parameter("tint") as Vector3).distance_to(Vector3(0.4, 0.4, 0.5)) < EPS, "night restores skyline tint")
	check(is_equal_approx(float(neon.get_shader_parameter("energy")), 4.0), "night restores neon")
	check(is_equal_approx(float(road.get_shader_parameter("wetness")), 1.0), "night restores wetness")
	check(is_equal_approx(float(road.get_shader_parameter("puddle_level")), 0.6), "night restores puddles")
	check(is_equal_approx(float(road.get_shader_parameter("rain_intensity")), 0.2), "night restores rain ripples")
	check(is_equal_approx(post.emission_energy_multiplier, 2.2), "night restores poster emission")


func test_lights_toggle() -> void:
	var root := Node3D.new()
	var names: PackedStringArray = ["lamp_head_001", "floodlight_002", "string_light_003", "neon_fill_004", "tunnel_strip_005", "traffic_light_red_006"]
	for n: String in names:
		var o := OmniLight3D.new()
		o.name = n
		o.light_energy = 2.0
		root.add_child(o)
	var day: TimeOfDay = TimeOfDay.preset("day")
	day.apply_lights(root)
	check(not (root.get_node("lamp_head_001") as Light3D).visible, "day: street lamp off")
	check(not (root.get_node("floodlight_002") as Light3D).visible, "day: floodlight off")
	check(not (root.get_node("string_light_003") as Light3D).visible, "day: string light off")
	check(not (root.get_node("neon_fill_004") as Light3D).visible or (root.get_node("neon_fill_004") as Light3D).light_energy < 0.5, "day: neon fill off or dim")
	check((root.get_node("tunnel_strip_005") as Light3D).visible, "tunnel strip stays on at day")
	check((root.get_node("traffic_light_red_006") as Light3D).visible, "traffic light stays on at day")
	TimeOfDay.preset("sunset").apply_lights(root)
	check((root.get_node("lamp_head_001") as Light3D).visible, "sunset: street lamp on")
	TimeOfDay.preset("night").apply_lights(root)
	check((root.get_node("lamp_head_001") as Light3D).visible and is_equal_approx((root.get_node("neon_fill_004") as Light3D).light_energy, 2.0), "night restores lamps and neon fills")
	root.free()


func test_race_config_field() -> void:
	var c := RaceConfig.new()
	check(c.time_of_day == "night", "RaceConfig defaults to night (the shipped look)")


## One real city race at day: sun with its shadow, no rain, no headlights, no street lamp spot visible.
func test_city_race_at_day() -> void:
	var cfg := RaceConfig.new()
	cfg.autopilot = true
	cfg.opponent_count = 1
	cfg.track_scene = CITY_PATH
	cfg.time_of_day = "day"
	var scene: RaceScene = (load(SCENE_PATH) as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	add(scene)
	await frames(5)
	check(scene.tod.id == "day", "the race scene uses the day preset")
	var sun: DirectionalLight3D = scene.track.find_child("Sun", true, false) as DirectionalLight3D
	check(sun != null, "the city has a Sun")
	if sun != null:
		check(sun.shadow_enabled == (Settings.get_preset_id() != "low"), "sun shadow follows the preset")
		check(sun.light_energy > 1.0, "sun energy")
	check(scene.track.find_child("Moon", true, false) == null, "no moon at day")
	check(scene.track.find_child("DayBounce", true, false) != null, "day has the ground shade and warm fill (DayBounce)")
	check(scene.find_children("*", "RainFx", true, false).is_empty(), "no rain at day")
	var lit_spots: int = 0
	for n: Node in scene.track.find_children("lamp_head_*", "Light3D", true, false):
		if (n as Light3D).visible:
			lit_spots += 1
	check(lit_spots == 0, "street lamps are off at day, %d are on" % lit_spots)
	var head_on: int = 0
	for n: Node in scene.player.find_children("*", "SpotLight3D", true, false):
		if (n as SpotLight3D).visible:
			head_on += 1
	check(head_on == 0, "headlights are off at day")
	var fill: Light3D = scene.camera.get_node_or_null(RaceScene.FILL_LIGHT_NAME) as Light3D
	check(fill != null and fill.light_energy < cfg.car_fill_energy, "car fill is tuned down at day")
	var proxy: bool = scene.player.find_child(RaceScene.SHADOW_PROXY_NAME, true, false) != null
	check(proxy == (Settings.get_preset_id() != "low"), "cars cast the sun shadow from a LOD2 proxy (not on Low)")
	scene.queue_free()
	await frames(2)
	# the shared materials come back for a night race in the same process
	var night_cfg := RaceConfig.new()
	night_cfg.autopilot = true
	night_cfg.opponent_count = 1
	night_cfg.track_scene = CITY_PATH
	var night_scene: RaceScene = (load(SCENE_PATH) as PackedScene).instantiate() as RaceScene
	night_scene.config = night_cfg
	add(night_scene)
	await frames(5)
	check(night_scene.tod.is_night(), "default race is night")
	check(night_scene.track.find_child("Moon", true, false) != null and night_scene.track.find_child("Sun", true, false) == null, "night keeps the moon")
	var lamps_on_night: int = 0
	for n: Node in night_scene.track.find_children("lamp_head_*", "Light3D", true, false):
		if (n as Light3D).visible:
			lamps_on_night += 1
	check(lamps_on_night > 0, "street lamps are on at night")
	var win: ShaderMaterial = MaterialLibrary.get_material("M_WindowAtlas") as ShaderMaterial
	check(float(win.get_shader_parameter("glow_energy")) > 0.5, "window glow is back at night")
	night_scene.queue_free()
	await frames(2)


func test_props_crowns_and_restore() -> void:
	var crown_mat := StandardMaterial3D.new()
	crown_mat.emission_enabled = true
	crown_mat.emission_energy_multiplier = 3.0
	var box := BoxMesh.new()
	box.material = crown_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = 1
	var crowns := MultiMeshInstance3D.new()
	crowns.name = "LedCrowns"
	crowns.multimesh = mm
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.2, 0.1, 0.1)
	paint.metallic = 0.7
	var parked := MultiMeshInstance3D.new()
	parked.name = "Parked_paint_red_lod0"
	parked.multimesh = mm
	parked.material_override = paint
	var cont := StandardMaterial3D.new()
	cont.resource_name = "M_Container_Red"
	cont.albedo_color = Color(0.45, 0.07, 0.05)
	var pane := StandardMaterial3D.new()
	pane.resource_name = "M_WindowAtlas"
	pane.albedo_color = Color(0.12, 0.15, 0.22)
	var imp: ShaderMaterial = _shader_mat(WINDOW_SHADER, "M_ImpostorAtlas")
	imp.set_shader_parameter("tint", Color(1.0, 0.2, 0.1))
	var root := Node3D.new()
	root.add_child(crowns)
	root.add_child(parked)
	var day: TimeOfDay = TimeOfDay.preset("day")
	day.apply_materials(root)
	for m: Material in [cont, pane, imp]:
		day.tune_material(m)
	check(not crowns.visible, "day: LED crowns hidden")
	check(paint.albedo_color.r > 0.2 and paint.metallic < 0.7, "day: parked paint lighter and less metallic")
	check(cont.albedo_color.r < 0.45, "day: container paint darker")
	var tint: Color = imp.get_shader_parameter("tint")
	check(tint.r - tint.g < 0.8, "day: impostor tint desaturated")
	var night: TimeOfDay = TimeOfDay.preset("night")
	night.apply_materials(root)
	for m: Material in [cont, pane, imp]:
		night.tune_material(m)
	check(crowns.visible and is_equal_approx(crown_mat.emission_energy_multiplier, 3.0), "night: LED crowns back at full strength")
	check(paint.albedo_color.is_equal_approx(Color(0.2, 0.1, 0.1)) and is_equal_approx(paint.metallic, 0.7), "night restores parked paint")
	check(cont.albedo_color.is_equal_approx(Color(0.45, 0.07, 0.05)), "night restores container paint")
	check(pane.albedo_color.is_equal_approx(Color(0.12, 0.15, 0.22)), "night restores Istanbul pane albedo")
	check((imp.get_shader_parameter("tint") as Color).is_equal_approx(Color(1.0, 0.2, 0.1)), "night restores impostor tint")
	var sunset: TimeOfDay = TimeOfDay.preset("sunset")
	sunset.apply_materials(root)
	check(not crowns.visible and (sunset.pane_std_albedo > 1.0), "sunset: crowns hidden, Istanbul panes lighter")
	root.free()
