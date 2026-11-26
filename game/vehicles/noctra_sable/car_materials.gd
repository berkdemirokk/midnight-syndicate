class_name CarMaterials
extends RefCounted
## Engine materials for the Noctra Sable model, chosen by material NAME (the names from docs/art/CAR_01_BRIEF.md).
## Textures come from the imported GLB. The Godot glTF importer keeps emissive strength and normal maps but
## drops KHR_materials_clearcoat, so clearcoat is set here (see docs/design/CAR_INTEGRATION.md).
## Shared materials are cached by name. M_Paint, M_Rim and M_LightRear are per car, so one car never changes another.

const PER_CAR: PackedStringArray = ["M_Paint", "M_Rim", "M_LightRear", "M_Plate"]  ## the plate is per car: shared, every car wore the first loaded car's number
const KNOWN: PackedStringArray = [
	"M_Paint", "M_Pillar", "M_Glass", "M_Lens", "M_LightFront", "M_LightRear", "M_Carbon", "M_Rim", "M_Tire",
	"M_BrakeDisc", "M_Caliper", "M_Trim", "M_Chrome", "M_Interior", "M_Plate",
]
const DEFAULT_PAINT: Color = Color(0.557, 0.059, 0.118)  ## #8E0F1E candy red from the brief
const DEFAULT_RIM: Color = Color(0.314, 0.333, 0.369)  ## gunmetal, the GLB source albedo (was 0.08: read as black)
const GLASS_TINT: Color = Color(0.035, 0.05, 0.06, 0.8)  ## smoked glass, a little lighter than the old near-black slab; alpha = opacity
const GLASS_SPECULAR: float = 0.08  ## was 0.25; grazing Fresnel dominates, so the grey comes mostly from alpha (see WORLD_MATERIALS.md)
const GLASS_RIM: float = 0.9  ## rim light on the edges of the glass: the Fresnel edge that hints the interior (0.45 was barely visible)
const FINISH_SOLID: int = 0
const FINISH_METALLIC: int = 1
const FINISH_PEARL: int = 2
const DEFAULT_FINISH: int = FINISH_METALLIC
const PAINT_METALLIC: float = 0.55  ## metallic finish; solid uses 0.0, pearl PAINT_PEARL_METALLIC
const PAINT_PEARL_METALLIC: float = 0.6
const PAINT_PEARL_RIM: float = 0.35  ## pearl sheen at grazing angles (no iridescence in StandardMaterial3D on Godot 4.7)
const PAINT_ROUGHNESS: float = 0.3  ## base; the flake roughness map (0.67..1.0 red) gives 0.16..0.24: a tight lobe, so night lamps make crisp highlights instead of a pink wash
const PAINT_CLEAR: float = 1.0
const PAINT_CLEAR_ROUGHNESS: float = 0.04
const PAINT_FLAKE_SCALE: float = 0.035  ## flake normal strength, low on purpose (0.12 read as sandpaper on the wheel close-up)
const PAINT_PEEL_SCALE: float = 0.04  ## solid paint: orange peel only, no sparkle
const PAINT_FLAKE_TILING: float = 48.0  ## fine tiling of the 512 px flake normal: at race distance it averages out, no sandpaper
const RAIN_BEAD_SCALE: float = 0.4  ## bead normal strength on wet paint
const RAIN_BEAD_TILING: float = 1.5  ## repeats per metre: beads of 5 to 20 mm (2.4 read as sand)
const RAIN_PAINT_ROUGHNESS: float = 0.16  ## a wet clear coat is glossier than a dry one
const RIM_ROUGHNESS: float = 0.34  ## times the brushed map (0.55..1.0): streaked satin metal
const RIM_ANISOTROPY: float = 0.75  ## stretched highlight across the brushing
const TIRE_ROUGHNESS: float = 0.92  ## rubber: matte, with sidewall variation from the map
const TRIM_ROUGHNESS: float = 0.42  ## satin black plastic
const TRIM_GRAIN_SCALE: float = 0.25  ## fine grain normal on trim
const CHROME_ROUGHNESS: float = 0.08
const GLASS_ROUGHNESS: float = 0.1  ## base; the streak map scales it to 0.06..0.1 so reflections break into streaks
const GLASS_STREAK_SCALE: Vector3 = Vector3(1.5, 1.0, 1.5)  ## triplanar repeats per metre of the streak map (about 2 cm columns)
const LENS_ALPHA: float = 0.25
const CARBON_CLEAR: float = 0.6
const CARBON_CLEAR_ROUGHNESS: float = 0.2
const REAR_REST: float = 1.8  ## rear lamp emission multiplier at rest: above the glow threshold (1.3), so running lights bloom at night
const REAR_BRAKE: float = 5.0  ## rear lamp emission multiplier while braking
const SHADOW_CASTERS: PackedStringArray = [
	"body", "underbody", "trim", "wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR",
]

static var _shared: Dictionary = {}
static var _glass_streaks: ImageTexture
static var _tex: Dictionary = {}


## Gives every known surface its engine material and sets shadow casting by node name. Call once per car.
## finish is FINISH_SOLID, FINISH_METALLIC (flake, default) or FINISH_PEARL (flake plus iridescence).
static func apply(car: Node, paint: Color = DEFAULT_PAINT, finish: int = DEFAULT_FINISH) -> void:
	var per_car: Dictionary = {}
	for mi: MeshInstance3D in _mesh_instances(car):
		if mi.mesh == null:
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if SHADOW_CASTERS.has(mi.name) \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s: int in mi.mesh.get_surface_count():
			var src: StandardMaterial3D = mi.get_active_material(s) as StandardMaterial3D
			if src == null or not KNOWN.has(src.resource_name):
				continue
			var nm: String = src.resource_name
			var mat: StandardMaterial3D
			if PER_CAR.has(nm):
				if not per_car.has(nm):
					per_car[nm] = _build(nm, src, paint, finish)
				mat = per_car[nm]
			else:
				if not _shared.has(nm):
					_shared[nm] = _build(nm, src, paint, finish)
				mat = _shared[nm]
			mi.set_surface_override_material(s, mat)


static func set_paint(car: Node, colour: Color) -> void:
	_each_material(car, "M_Paint", func(m: StandardMaterial3D) -> void: m.albedo_color = colour)


static func set_rim_color(car: Node, colour: Color) -> void:
	_each_material(car, "M_Rim", func(m: StandardMaterial3D) -> void: m.albedo_color = colour)


## Rain on the clear coat: beads replace the flake normal on the paint (object-space triplanar, so every model
## gets them whatever its UVs are). Call once after apply() when it rains.
static func set_wet(car: Node, wet: bool) -> void:
	if not wet:
		return
	_each_material(car, "M_Paint", func(m: StandardMaterial3D) -> void:
		m.normal_enabled = true
		m.normal_texture = _tex_file("car_rain_beads_normal.png")
		m.normal_scale = RAIN_BEAD_SCALE
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(RAIN_BEAD_TILING, RAIN_BEAD_TILING, RAIN_BEAD_TILING)
		m.roughness_texture = null
		m.roughness = RAIN_PAINT_ROUGHNESS)


## Mirrors a street panorama in the paint (second pass, res://shaders/car_reflection.gdshader); null removes it.
static func set_reflection(car: Node, pano: Texture2D, strength: float = 0.5) -> void:
	_each_material(car, "M_Paint", func(m: StandardMaterial3D) -> void:
		if pano == null:
			m.next_pass = null
			return
		var mirror := ShaderMaterial.new()
		mirror.shader = load("res://shaders/car_reflection.gdshader")
		mirror.set_shader_parameter("pano", pano)
		mirror.set_shader_parameter("strength", strength)
		m.next_pass = mirror)


static func set_brake_lights(car: Node, on: bool) -> void:
	var level: float = REAR_BRAKE if on else REAR_REST
	_each_material(car, "M_LightRear", func(m: StandardMaterial3D) -> void: m.emission_energy_multiplier = level)


static func _build(nm: String, src: StandardMaterial3D, paint: Color, finish: int) -> StandardMaterial3D:
	var m: StandardMaterial3D = src.duplicate() as StandardMaterial3D
	m.resource_name = nm
	match nm:
		"M_Paint":
			m.albedo_color = paint
			m.metallic = 0.0 if finish == FINISH_SOLID else (PAINT_PEARL_METALLIC if finish == FINISH_PEARL else PAINT_METALLIC)
			m.roughness = PAINT_ROUGHNESS
			m.roughness_texture = _tex_file("car_flake_roughness.png")
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			m.clearcoat_enabled = true
			m.clearcoat = PAINT_CLEAR
			m.clearcoat_roughness = PAINT_CLEAR_ROUGHNESS
			m.normal_enabled = true
			m.normal_texture = _tex_file("car_flake_normal.png")  # orange peel + flake, one map
			m.normal_scale = PAINT_PEEL_SCALE if finish == FINISH_SOLID else PAINT_FLAKE_SCALE
			m.uv1_scale = Vector3(PAINT_FLAKE_TILING, PAINT_FLAKE_TILING, 1.0)
			m.rim_enabled = finish == FINISH_PEARL  ## pearl: grazing sheen on the body
			m.rim = PAINT_PEARL_RIM
		"M_Pillar":
			m.clearcoat_enabled = true
			m.clearcoat = PAINT_CLEAR
			m.clearcoat_roughness = PAINT_CLEAR_ROUGHNESS
		"M_Chrome":
			m.metallic = 1.0
			m.roughness = CHROME_ROUGHNESS
		"M_Tire":
			m.roughness = TIRE_ROUGHNESS
			m.roughness_texture = _tex_file("car_rubber_roughness.png")
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		"M_Trim":
			m.roughness = TRIM_ROUGHNESS
			m.normal_enabled = true
			m.normal_texture = _tex_file("car_grain_normal.png")
			m.normal_scale = TRIM_GRAIN_SCALE
		"M_Rim":
			m.albedo_color = DEFAULT_RIM
			m.metallic = 0.8  # full metal mirrored the day sky: rims read bright blue
			m.roughness = RIM_ROUGHNESS
			m.roughness_texture = _tex_file("car_brushed_roughness.png")
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			m.anisotropy_enabled = true
			m.anisotropy = RIM_ANISOTROPY
		"M_Glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY  ## no depth write: the interior behind shows through
			m.metallic = 0.0
			# Smoked glass: dark, a reduced specular so a bright ceiling bar does not turn the whole
			# windscreen into a white plate, and a roughness map so the reflections break into streaks.
			m.albedo_color = GLASS_TINT
			m.metallic_specular = GLASS_SPECULAR
			m.roughness = GLASS_ROUGHNESS
			m.roughness_texture = _glass_streak_map()
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = GLASS_STREAK_SCALE
			m.rim_enabled = true  ## Fresnel-like edge sheen: the glass reads as glass, not a black plate
			m.rim = GLASS_RIM
			m.rim_tint = 0.4
			m.render_priority = 1  ## draw after opaque, so the glass sits over the interior
		"M_Lens":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
			m.albedo_color = Color(1.0, 1.0, 1.0, LENS_ALPHA)
			m.roughness = 0.05  ## clear glass by day: crisp reflections, not a frosted lens
			m.metallic_specular = 0.9
			m.render_priority = 1
		"M_LightRear":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.102, 0.102)
			m.emission_energy_multiplier = REAR_REST
		"M_LightFront":
			m.emission_enabled = true
		"M_Carbon":
			m.clearcoat_enabled = true
			m.clearcoat = CARBON_CLEAR
			m.clearcoat_roughness = CARBON_CLEAR_ROUGHNESS
	return m


## Procedural maps from tools/gen_car_textures.py (original, project-owned). Loaded once, shared by every car.
static func _tex_file(file: String) -> Texture2D:
	if not _tex.has(file):
		_tex[file] = load("res://assets/vehicles/shared/" + file) as Texture2D
	return _tex[file]


## Vertical streak map for glass roughness: constant down each column, random across. Red channel 0.6..1.0.
static func _glass_streak_map() -> ImageTexture:
	if _glass_streaks != null:
		return _glass_streaks
	var size: int = 32
	var img: Image = Image.create(size, size, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # fixed, so every run and every car gets the same streaks
	for x: int in size:
		var v: float = 0.6 + 0.4 * rng.randf()
		if rng.randf() < 0.25:
			v = 1.0  # a few columns at the top of the range: stronger streak contrast
		for y: int in size:
			img.set_pixel(x, y, Color(v, v, v))
	_glass_streaks = ImageTexture.create_from_image(img)
	return _glass_streaks


static func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


static func _each_material(root: Node, nm: String, fn: Callable) -> void:
	for mi: MeshInstance3D in _mesh_instances(root):
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var m: StandardMaterial3D = mi.get_active_material(s) as StandardMaterial3D
			if m != null and m.resource_name == nm:
				fn.call(m)
