class_name CarMaterials
extends RefCounted
## Engine materials for the Noctra Sable model, chosen by material NAME (the names from docs/art/CAR_01_BRIEF.md).
## Textures come from the imported GLB. The Godot glTF importer keeps emissive strength and normal maps but
## drops KHR_materials_clearcoat, so clearcoat is set here (see docs/design/CAR_INTEGRATION.md).
## Shared materials are cached by name. M_Paint, M_Rim and M_LightRear are per car, so one car never changes another.

const PER_CAR: PackedStringArray = ["M_Paint", "M_Rim", "M_LightRear"]
const KNOWN: PackedStringArray = [
	"M_Paint", "M_Pillar", "M_Glass", "M_Lens", "M_LightFront", "M_LightRear", "M_Carbon", "M_Rim", "M_Tire",
	"M_BrakeDisc", "M_Caliper", "M_Trim", "M_Chrome", "M_Interior", "M_Plate",
]
const DEFAULT_PAINT: Color = Color(0.557, 0.059, 0.118)  ## #8E0F1E candy red from the brief
const DEFAULT_RIM: Color = Color(0.314, 0.333, 0.369)  ## gunmetal, the GLB source albedo (was 0.08: read as black)
const GLASS_TINT: Color = Color(0.02, 0.03, 0.04, 0.85)  ## near-black smoked glass, alpha = opacity (0.62 read light grey; 0.42 brighter)
const GLASS_SPECULAR: float = 0.08  ## was 0.25; grazing Fresnel dominates, so the grey comes mostly from alpha (see WORLD_MATERIALS.md)
const PAINT_METALLIC: float = 0.85
const PAINT_ROUGHNESS: float = 0.32
const PAINT_CLEAR: float = 1.0
const PAINT_CLEAR_ROUGHNESS: float = 0.04
const PAINT_FLAKE_SCALE: float = 0.12  ## flake normal strength, low on purpose
const PAINT_FLAKE_TILING: float = 4.0  ## fine tiling of the 512 px flake normal
const GLASS_ROUGHNESS: float = 0.1  ## base; the streak map scales it to 0.06..0.1 so reflections break into streaks
const GLASS_STREAK_SCALE: Vector3 = Vector3(1.5, 1.0, 1.5)  ## triplanar repeats per metre of the streak map (about 2 cm columns)
const LENS_ALPHA: float = 0.25
const CARBON_CLEAR: float = 0.6
const CARBON_CLEAR_ROUGHNESS: float = 0.2
const REAR_REST: float = 0.6  ## rear lamp emission multiplier at rest
const REAR_BRAKE: float = 4.0  ## rear lamp emission multiplier while braking
const SHADOW_CASTERS: PackedStringArray = [
	"body", "underbody", "trim", "wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR",
]

static var _shared: Dictionary = {}
static var _glass_streaks: ImageTexture


## Gives every known surface its engine material and sets shadow casting by node name. Call once per car.
static func apply(car: Node, paint: Color = DEFAULT_PAINT) -> void:
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
					per_car[nm] = _build(nm, src, paint)
				mat = per_car[nm]
			else:
				if not _shared.has(nm):
					_shared[nm] = _build(nm, src, paint)
				mat = _shared[nm]
			mi.set_surface_override_material(s, mat)


static func set_paint(car: Node, colour: Color) -> void:
	_each_material(car, "M_Paint", func(m: StandardMaterial3D) -> void: m.albedo_color = colour)


static func set_rim_color(car: Node, colour: Color) -> void:
	_each_material(car, "M_Rim", func(m: StandardMaterial3D) -> void: m.albedo_color = colour)


static func set_brake_lights(car: Node, on: bool) -> void:
	var level: float = REAR_BRAKE if on else REAR_REST
	_each_material(car, "M_LightRear", func(m: StandardMaterial3D) -> void: m.emission_energy_multiplier = level)


static func _build(nm: String, src: StandardMaterial3D, paint: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = src.duplicate() as StandardMaterial3D
	m.resource_name = nm
	match nm:
		"M_Paint":
			m.albedo_color = paint
			m.metallic = PAINT_METALLIC
			m.roughness = PAINT_ROUGHNESS
			m.clearcoat_enabled = true
			m.clearcoat = PAINT_CLEAR
			m.clearcoat_roughness = PAINT_CLEAR_ROUGHNESS
			m.normal_enabled = true
			m.normal_scale = PAINT_FLAKE_SCALE
			m.uv1_scale = Vector3(PAINT_FLAKE_TILING, PAINT_FLAKE_TILING, 1.0)
		"M_Pillar":
			m.clearcoat_enabled = true
			m.clearcoat = PAINT_CLEAR
			m.clearcoat_roughness = PAINT_CLEAR_ROUGHNESS
		"M_Rim":
			m.albedo_color = DEFAULT_RIM
			m.metallic = 1.0
			m.roughness = 0.28
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
			m.render_priority = 1  ## draw after opaque, so the glass sits over the interior
		"M_Lens":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
			m.albedo_color = Color(1.0, 1.0, 1.0, LENS_ALPHA)
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
