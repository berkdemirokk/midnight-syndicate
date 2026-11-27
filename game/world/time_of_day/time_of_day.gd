class_name TimeOfDay
extends RefCounted
## Time-of-day presets: DAY, SUNSET and NIGHT (docs/design/TIME_OF_DAY.md). One preset holds everything that changes
## with the light: sun, ambient, sky, fog, exposure, emissive strength of windows, neon and signs, street lamps, how wet
## the road is, rain, car fill and rim lights and headlights. NIGHT is the look the game shipped with: applying it
## changes nothing in the environment (the track's own exported values stay in charge) and restores every material
## this class has scaled, so a night race after a day race in the same process is identical to a fresh one.
##
## Use: TimeOfDay.preset("day"). CityBuilder calls apply_environment / apply_lights / apply_materials while it builds,
## RaceScene reads the car, rain, headlight and road fields.

const DAY: String = "day"
const SUNSET: String = "sunset"
const NIGHT: String = "night"
const IDS: PackedStringArray = ["day", "sunset", "night"]

const DAY_SKY: Shader = preload("res://world/time_of_day/day_sky.gdshader")
const WINDOW_SHADER: String = "res://world/materials/window_atlas.gdshader"
const WATER_SHADER: String = "res://world/materials/water.gdshader"
const NEON_SHADER: String = "res://shaders/neon.gdshader"
const ASPHALT_SHADER: String = "res://shaders/wet_asphalt.gdshader"
const FACADE_SHADER: String = "res://shaders/wet_facade.gdshader"
const BASE_META: StringName = &"tod_base"
const SHADOW_BOX_NAME: String = "ShadowBox"
const SKYLINE_PREFIX: String = "M_Skyline"
## Standard materials that keep their emission whatever the hour (painted markings, tunnel stripe).
const KEEP_EMISSION: PackedStringArray = ["M_RoadPaint", "M_TunnelStripe", "M_CeilingStrip", "M_Signal_Red", "M_Aircraft_Red"]
## Light name prefixes (CityBuilder names lights "<source>_<index>").
const LAMP_PREFIXES: PackedStringArray = ["lamp_head_", "floodlight_", "wall_wash_", "string_light_", "ferry_pier_light_", "plaza_light_", "bay_crane_light_"]
const SIGN_FILL_PREFIXES: PackedStringArray = ["neon_fill_", "landmark_accent_", "bus_shelter_panel_"]

var id: String = NIGHT
var label: String = "Night"

# --- sun ---
var sun_elevation_deg: float = 40.0
var sun_azimuth_deg: float = 215.0  ## relative to the direction of travel at the start: 0 = sun dead ahead, 180 = dead behind
var sun_color: Color = Color.WHITE
var sun_energy: float = 1.0
var sun_shadows: bool = true  ## still off on the Low preset
var shadow_max_distance_m: float = 70.0
# --- ambient, sky, fog, grading ---
var ambient_energy: float = 1.0  ## ambient light from the sky radiance
var reflection_energy: float = 1.0
var ambient_sky_mix: float = 1.0  ## share of the ambient that comes from the sky; the rest is ambient_color
var ambient_color: Color = Color.WHITE
var sky_params: Dictionary = {}  ## day_sky.gdshader uniforms
var fog_color: Color = Color("#A9BED6")
var fog_begin_m: float = 220.0
var fog_end_m: float = 1200.0
var fog_sky_affect: float = 0.4
var exposure: float = 1.0
var glow_scale: float = 1.0  ## multiplies the graphics preset's glow intensity
var glow_threshold: float = 1.3
# --- emissive strength, 1 = as authored for night ---
var window_scale: float = 1.0
var neon_scale: float = 1.0
var skyline_scale: float = 1.0
var skyline_brighten: float = 1.0  ## multiplies the far skyline card tint (day: pale hazy towers instead of black cut-outs)
var pane_albedo_scale: float = 1.0  ## multiplies the window pane albedo (day: lighter, sky-blue glass)
var pane_reflect: float = 0.0  ## day: extra metallic on panes so they mirror the sky
var glass_sky_reflect: float = -1.0  ## window_atlas glass_reflect for this hour; below 0 keeps the authored (night) value
var sun_world: Vector3 = Vector3.UP  ## world sun vector for the glass sun glint; the track sets it before apply_materials
var crown_scale: float = 1.0  ## LED crown strips on tall towers (LedCrowns): 0 hides them
var impostor_desat: float = 0.0  ## far-building impostors: share of the tint pulled to grey (sunlit flat boxes read as solid colour blocks)
var impostor_scale: float = 1.0  ## brightness of the impostor tint
var container_albedo: float = 1.0  ## shipping containers and red newspaper boxes (saturated flat red blows out under a strong sun)
var pane_std_albedo: float = 1.0  ## Istanbul tracks: M_WindowAtlas is a StandardMaterial3D; this lightens its dark glass
var parked_albedo: float = 1.0  ## parked car paint: albedo multiplier (night paints are muted and dark)
var std_specular: float = 1.0  ## multiplies the specular of non-metal standard materials (dry day walls must not mirror the sky: they read navy blue)
var parked_metal: float = 1.0  ## parked car paint: metallic multiplier (a metallic dark paint mirrors the sky as flat grey)
# --- street lights ---
var lamps_on: bool = true
var sign_light_scale: float = 1.0  ## energy of the omni fills that sit under neon signs
# --- road ---
var road_wetness: float = 1.0  ## multiplies the asphalt material's wetness (night: as authored)
var road_puddles: float = 1.0
var road_brightness: float = 1.0  ## multiplies the asphalt tint (day: sun-bleached, lighter road)
var wall_wet: float = 1.0  ## multiplies the wet facade film (darkening, gloss, streaks)
var road_mirror: bool = true  ## the planar mirror of the wet road (High only)
var rain: bool = true
# --- cars ---
var headlights_on: bool = true
var car_fill_scale: float = 1.0
var car_rim_scale: float = 1.0
var car_fill_color: Color = Color(0, 0, 0, 0)  ## alpha 0 = the RaceConfig colour
var car_rim_color: Color = Color(0, 0, 0, 0)
var audio_wetness: float = 1.0


static func preset(preset_id: String) -> TimeOfDay:
	var t := TimeOfDay.new()
	match preset_id:
		DAY:
			t._make_day()
		SUNSET:
			t._make_sunset()
		_:
			pass  # night: the field defaults above are the shipped look
	return t


static func is_valid(preset_id: String) -> bool:
	return IDS.has(preset_id)


func is_night() -> bool:
	return id == NIGHT


## Unit vector from the ground toward the sun; heading_deg is the compass heading of the start direction (atan2(x, z)). 
func sun_vector(heading_deg: float = 0.0) -> Vector3:
	var e: float = deg_to_rad(sun_elevation_deg)
	var a: float = deg_to_rad(heading_deg + sun_azimuth_deg)
	return Vector3(sin(a) * cos(e), sin(e), cos(a) * cos(e)).normalized()


func _make_day() -> void:
	id = DAY
	label = "Day"
	sun_elevation_deg = 44.0
	sun_azimuth_deg = 140.0  # behind the start grid on the land side: the mosque and the faces the driver looks at are lit
	sun_color = Color(1.0, 0.95, 0.84)
	sun_energy = 3.0
	ambient_energy = 1.15  # sky fill: with baked AO the shaded street fronts need it, or they read near black
	ambient_sky_mix = 0.3
	ambient_color = Color(0.78, 0.83, 0.95)  # sky fill: a little cool, not blue paint
	road_brightness = 0.85
	reflection_energy = 1.0
	sky_params = {
		"zenith_colour": Color(0.14, 0.44, 1.0), "horizon_colour": Color(0.62, 0.80, 1.0),
		"ground_colour": Color(0.52, 0.60, 0.70), "sun_colour": Color(1.0, 0.96, 0.88),
		"sun_disk_energy": 9.0, "halo_energy": 0.5, "halo_power": 30.0,
		"band_energy": 0.0, "cloud_cover": 0.32,
		"cloud_lit": Color(1.0, 0.995, 0.98), "cloud_shade": Color(0.72, 0.80, 0.92),
	}
	fog_color = Color(0.62, 0.76, 0.95)
	fog_begin_m = 260.0
	fog_end_m = 1500.0
	fog_sky_affect = 0.15
	exposure = 0.8  # the night albedo lifts on walls clipped to white at 1.0
	glow_scale = 0.35
	glow_threshold = 2.2
	window_scale = 0.0
	neon_scale = 0.18
	skyline_scale = 0.0
	skyline_brighten = 2.6
	pane_albedo_scale = 4.0
	pane_reflect = -0.2
	glass_sky_reflect = 0.75
	crown_scale = 0.0
	impostor_desat = 0.5
	impostor_scale = 0.8
	container_albedo = 0.6
	std_specular = 0.3
	parked_albedo = 1.25  # 2.2 clipped white and silver cars to flat white
	parked_metal = 0.45
	lamps_on = false
	sign_light_scale = 0.0
	road_wetness = 0.12
	road_puddles = 0.0
	wall_wet = 0.1
	road_mirror = false
	rain = false
	headlights_on = false
	car_fill_scale = 0.35
	car_rim_scale = 0.3
	car_fill_color = Color(0.85, 0.92, 1.0)
	car_rim_color = Color(1.0, 0.96, 0.9)
	audio_wetness = 0.1


func _make_sunset() -> void:
	id = SUNSET
	label = "Sunset"
	sun_elevation_deg = 6.0
	sun_azimuth_deg = 28.0
	sun_color = Color(1.0, 0.70, 0.46)
	sun_energy = 1.1  # blue hour: the sun is almost down, the lamps carry the street (2.4 washed everything pink)
	ambient_energy = 0.85
	ambient_sky_mix = 0.3
	ambient_color = Color(0.36, 0.40, 0.62)
	reflection_energy = 1.0
	sky_params = {
		"zenith_colour": Color(0.05, 0.09, 0.30), "horizon_colour": Color(0.66, 0.50, 0.52),
		"ground_colour": Color(0.40, 0.25, 0.30), "sun_colour": Color(1.0, 0.62, 0.32),
		"sun_disk_energy": 10.0, "halo_energy": 1.6, "halo_power": 10.0,
		"band_colour": Color(1.0, 0.42, 0.22), "band_energy": 0.8, "band_height": 0.2, "band_spread": 1.6,
		"cloud_cover": 0.42, "cloud_lit": Color(0.98, 0.66, 0.56), "cloud_shade": Color(0.22, 0.24, 0.46),
	}
	fog_color = Color(0.40, 0.40, 0.56)
	fog_begin_m = 240.0
	fog_end_m = 1250.0
	fog_sky_affect = 0.5
	exposure = 1.0
	glow_scale = 1.0
	glow_threshold = 1.2
	window_scale = 0.9
	neon_scale = 0.8
	skyline_scale = 0.6
	skyline_brighten = 1.2
	pane_albedo_scale = 5.0
	pane_reflect = 0.3
	glass_sky_reflect = 0.8
	crown_scale = 0.0
	impostor_desat = 0.45
	impostor_scale = 0.75
	container_albedo = 0.28
	pane_std_albedo = 2.6
	std_specular = 0.6
	parked_albedo = 1.15
	parked_metal = 0.55
	lamps_on = true
	sign_light_scale = 0.8
	road_wetness = 0.85
	road_puddles = 0.7
	wall_wet = 0.35
	road_mirror = false  # the planar mirror turned the whole road into a pink sky channel and broke the primitive budget
	rain = false
	headlights_on = true
	car_fill_scale = 0.7
	car_rim_scale = 0.8
	car_fill_color = Color(0.95, 0.85, 0.9)
	car_rim_color = Color(1.0, 0.7, 0.5)
	audio_wetness = 0.5


## Environment, sky and the sun. NIGHT leaves everything the builder made untouched. sun is the builder's directional
## light (the moon at night): it becomes the sun with the one directional shadow.
func apply_environment(env: Environment, sun: DirectionalLight3D, heading_deg: float = 0.0) -> void:
	if is_night():
		return
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = DAY_SKY
	sky_mat.set_shader_parameter("sun_dir", sun_vector(heading_deg))
	sun_world = sun_vector(heading_deg)
	for k: String in sky_params:
		sky_mat.set_shader_parameter(k, sky_params[k])
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = ambient_sky_mix
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_light_color = fog_color
	env.fog_depth_begin = fog_begin_m
	env.fog_depth_end = fog_end_m
	env.fog_sky_affect = fog_sky_affect
	env.glow_hdr_threshold = glow_threshold
	env.tonemap_exposure = exposure
	sun.name = "Sun"
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.basis = Basis.looking_at(-sun_vector(heading_deg), Vector3.UP)
	var low: bool = Settings.get_preset_id() == "low"
	sun.shadow_enabled = sun_shadows and not low
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = shadow_max_distance_m
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.5


## After Settings.apply_to_environment (which writes the graphics preset's glow): scales that glow for this hour.
func apply_after_settings(env: Environment) -> void:
	if is_night():
		return
	env.glow_intensity *= glow_scale


## Street lamps, floodlights and string lights on or off; the fills under neon signs dim. Tunnel strips stay on.
func apply_lights(lighting: Node) -> void:
	for n: Node in lighting.get_children():
		var l: Light3D = n as Light3D
		if l == null:
			continue
		var nm: String = String(l.name)
		if not l.has_meta(BASE_META):
			l.set_meta(BASE_META, l.light_energy)
		var base: float = float(l.get_meta(BASE_META))
		if _has_prefix(nm, LAMP_PREFIXES):
			l.visible = lamps_on
		elif _has_prefix(nm, SIGN_FILL_PREFIXES):
			l.light_energy = base * sign_light_scale
			l.visible = sign_light_scale > 0.001


## Sun shadows are paid per caster (a caster is drawn again in the shadow pass), so only what shows a shadow keeps casting:
## buildings and props near the road. Road surface, ground, water, decals and every far LOD stop casting.
func apply_shadow_casters(root: Node) -> void:
	if is_night():
		return
	var first_row: Node = root.get_node_or_null("FirstRow")
	if first_row != null:
		for b: Node in first_row.get_children():
			_building_shadow_box(b)
	for n: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n as GeometryInstance3D
		if _is_non_caster(gi, root):
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# day only: ground shade strips and the warm bounce fill (DayBounce), built once the buildings exist
	var track: Track = root.get_parent() as Track
	if id == DAY and track != null:
		DayBounce.build(root, track, sun_world)


## A building casts its sun shadow from its LOD2 box (10 triangles, one draw) instead of LOD0 (3500 triangles, 14 draws):
## a shadows-only copy of LOD2 with no visibility range, while every real LOD stops casting. The shadow of a boxy
## tower is its box. Buildings without a LOD2 keep casting from their real meshes.
static func _building_shadow_box(building: Node) -> void:
	var lod2: MeshInstance3D = building.find_child("LOD2", true, false) as MeshInstance3D
	if lod2 == null or lod2.mesh == null:
		return
	var box: MeshInstance3D = lod2.duplicate() as MeshInstance3D
	box.name = SHADOW_BOX_NAME
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	box.visibility_range_begin = 0.0
	box.visibility_range_end = 0.0
	box.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	lod2.get_parent().add_child(box)
	for m: Node in building.find_children("*", "MeshInstance3D", true, false):
		if m != box:
			(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _under(n: Node, root: Node, names: PackedStringArray) -> bool:
	var cur: Node = n
	while cur != null and cur != root:
		if names.has(String(cur.name)):
			return true
		cur = cur.get_parent()
	return false


static func _is_non_caster(gi: GeometryInstance3D, root: Node) -> bool:
	var nm: String = String(gi.name)
	if nm.begins_with("ground") or nm.begins_with("water_") or nm.begins_with("decals_") or nm.begins_with("markings_"):
		return true
	if nm in ["LOD1", "LOD2"] or nm.contains("_LOD2") or nm.contains("_far_"):
		return true
	return _under(gi, root, PackedStringArray(["Road", "SecondRow", "LOD2_Batches"]))


## Walks every mesh under root once and scales window and sign glow, wetness and the pane glass for this hour.
## Materials are shared and static: the first scaling stores the authored value in meta, so any hour (night included)
## sets them from that, never from an earlier hour's result.
func apply_materials(root: Node) -> void:
	var seen: Dictionary = {}
	for n: Node in root.find_children("*", "GeometryInstance3D", true, false):
		if n.name == "LedCrowns":
			_tune_crowns(n as MultiMeshInstance3D, seen)
			continue
		if n is MultiMeshInstance3D and String(n.name).begins_with("Parked_paint_"):
			_tune_parked_paint((n as MultiMeshInstance3D).material_override)
		var mats: Array[Material] = []
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n
			if mi.material_override != null:
				mats.append(mi.material_override)
			if mi.mesh != null:
				for s: int in mi.mesh.get_surface_count():
					var m: Material = mi.get_surface_override_material(s)
					if m == null:
						m = mi.mesh.surface_get_material(s)
					if m != null:
						mats.append(m)
		elif n is MultiMeshInstance3D:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null:
				for s: int in mm.mesh.get_surface_count():
					var m2: Material = mm.mesh.surface_get_material(s)
					if m2 != null:
						mats.append(m2)
		for m: Material in mats:
			if not seen.has(m):
				seen[m] = true
				tune_material(m)


## LED crowns: one emissive box material. Hidden when crown_scale is 0, else scaled from the authored energy; the generic
## neon scaling must not touch it, so it goes into seen.
func _tune_crowns(mmi: MultiMeshInstance3D, seen: Dictionary) -> void:
	mmi.visible = crown_scale > 0.001
	if mmi.multimesh == null or mmi.multimesh.mesh == null:
		return
	var st: StandardMaterial3D = mmi.multimesh.mesh.surface_get_material(0) as StandardMaterial3D
	if st == null:
		return
	seen[st] = true
	if not st.has_meta(BASE_META):
		st.set_meta(BASE_META, st.emission_energy_multiplier)
	st.emission_energy_multiplier = float(st.get_meta(BASE_META)) * crown_scale


## Parked car paint (material_override of the Parked_paint_* MultiMeshes): lighter and less mirror-like in daylight.
func _tune_parked_paint(m: Material) -> void:
	var st: StandardMaterial3D = m as StandardMaterial3D
	if st == null:
		return
	if not st.has_meta(BASE_META):
		st.set_meta(BASE_META, {"c": st.albedo_color, "m": st.metallic})
	var b: Dictionary = st.get_meta(BASE_META)
	var c: Color = b["c"]
	var k: float = parked_albedo
	st.albedo_color = c if k == 1.0 else Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), c.a)
	st.metallic = float(b["m"]) * parked_metal


## One material, set for this hour from its authored values.
func tune_material(m: Material) -> void:
	if m is ShaderMaterial:
		var sm: ShaderMaterial = m
		if sm.shader == null:
			return
		match sm.shader.resource_path:
			WINDOW_SHADER:
				_tune_window(sm)
			NEON_SHADER:
				if not _keeps_emission(sm.resource_name):
					_scale_param(sm, "energy", neon_scale)
			WATER_SHADER:
				if sky_params.has("zenith_colour"):
					sm.set_shader_parameter("zenith_colour", sky_params["zenith_colour"])
					sm.set_shader_parameter("horizon_colour", sky_params["horizon_colour"])
					sm.set_shader_parameter("sky_fill", 0.3 if id == DAY else 0.2)
				else:
					sm.set_shader_parameter("sky_fill", 0.0)
			ASPHALT_SHADER:
				_scale_param(sm, "wetness", road_wetness)
				_scale_param(sm, "puddle_level", road_puddles)
				_scale_param(sm, "rain_intensity", 1.0 if rain else 0.0)
				_scale_tint(sm, "tint", road_brightness)
			FACADE_SHADER:
				for k: String in ["wall_darken", "wall_gloss", "wet_darken", "wet_gloss", "streak_darken", "streak_gloss", "grime"]:
					_scale_param(sm, k, wall_wet)
	elif m is StandardMaterial3D:
		var st: StandardMaterial3D = m
		var k: float = -1.0
		if st.resource_name.begins_with("M_Container_") or st.resource_name == "M_Metal_Red":
			k = container_albedo
		elif st.resource_name == "M_WindowAtlas":
			k = pane_std_albedo
		if k >= 0.0:
			if not st.has_meta(&"tod_albedo"):
				st.set_meta(&"tod_albedo", st.albedo_color)
			var cc: Color = st.get_meta(&"tod_albedo")
			st.albedo_color = Color(clampf(cc.r * k, 0.0, 1.0), clampf(cc.g * k, 0.0, 1.0), clampf(cc.b * k, 0.0, 1.0), cc.a)
		if st.metallic < 0.1 and st.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			if not st.has_meta(&"tod_specular"):
				st.set_meta(&"tod_specular", st.metallic_specular)
			st.metallic_specular = float(st.get_meta(&"tod_specular")) * std_specular
		if st.emission_enabled and not _keeps_emission(st.resource_name):
			if not st.has_meta(BASE_META):
				st.set_meta(BASE_META, st.emission_energy_multiplier)
			st.emission_energy_multiplier = float(st.get_meta(BASE_META)) * neon_scale


func _tune_window(sm: ShaderMaterial) -> void:
	var skyline: bool = sm.resource_name.begins_with(SKYLINE_PREFIX)
	_scale_param(sm, "glow_energy", skyline_scale if skyline else window_scale)
	if sm.resource_name == "M_ImpostorAtlas":
		var it: Variant = _base_param(sm, "tint")
		var ic: Color = it if it is Color else Color.WHITE
		var g: float = ic.get_luminance()
		var v3: Vector3 = Vector3(ic.r, ic.g, ic.b).lerp(Vector3(g, g, g), impostor_desat) * impostor_scale
		sm.set_shader_parameter("tint", Color(v3.x, v3.y, v3.z, ic.a))
	if skyline:
		var tint: Variant = _base_param(sm, "tint")
		if tint is Color:
			var c: Color = tint
			sm.set_shader_parameter("tint", Color(c.r * skyline_brighten, c.g * skyline_brighten, c.b * skyline_brighten, c.a))
		elif tint is Vector3:
			sm.set_shader_parameter("tint", (tint as Vector3) * skyline_brighten)
	elif sm.resource_name == "M_WindowAtlas":
		_scale_param(sm, "albedo_scale", pane_albedo_scale)
		# The glass mirrors this hour's sky (analytic, in the shader); night keeps the authored dim reflection.
		var base_reflect: Variant = _base_param(sm, "glass_reflect")
		if glass_sky_reflect >= 0.0 and sky_params.has("zenith_colour"):
			sm.set_shader_parameter("glass_reflect", glass_sky_reflect)
			sm.set_shader_parameter("sky_zenith", sky_params["zenith_colour"])
			sm.set_shader_parameter("sky_horizon", sky_params["horizon_colour"])
			sm.set_shader_parameter("sun_dir", sun_world)
			sm.set_shader_parameter("sun_colour", sun_color)
		elif base_reflect != null:
			sm.set_shader_parameter("glass_reflect", float(base_reflect))
			sm.set_shader_parameter("sky_zenith", Color(0.02, 0.035, 0.085))
			sm.set_shader_parameter("sky_horizon", Color(0.10, 0.08, 0.20))
			sm.set_shader_parameter("sun_colour", Color(0.0, 0.0, 0.0))
		var mv: Variant = _base_param(sm, "metallic_value")
		if mv != null:
			sm.set_shader_parameter("metallic_value", clampf(float(mv) + pane_reflect, 0.0, 1.0))


## Stores the authored value of a shader parameter on first use and returns it.
func _base_param(sm: ShaderMaterial, param: String) -> Variant:
	var key: StringName = StringName("tod_" + param)
	if not sm.has_meta(key):
		sm.set_meta(key, {"v": sm.get_shader_parameter(param)})  # boxed: set_meta(null) would erase the key
	return (sm.get_meta(key) as Dictionary)["v"]


func _scale_param(sm: ShaderMaterial, param: String, factor: float) -> void:
	var base: Variant = _base_param(sm, param)
	if base == null:
		return
	sm.set_shader_parameter(param, float(base) * factor)


## Multiplies a colour shader parameter's rgb by factor, from its authored value (unset = white).
func _scale_tint(sm: ShaderMaterial, param: String, factor: float) -> void:
	var base: Variant = _base_param(sm, param)
	var c: Color = base if base is Color else Color.WHITE
	sm.set_shader_parameter(param, Color(c.r * factor, c.g * factor, c.b * factor, c.a))


static func _keeps_emission(mat_name: String) -> bool:
	return _has_prefix(mat_name, KEEP_EMISSION)


static func _has_prefix(nm: String, prefixes: PackedStringArray) -> bool:
	for p: String in prefixes:
		if nm.begins_with(p):
			return true
	return false
