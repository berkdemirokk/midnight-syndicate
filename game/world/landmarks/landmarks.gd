class_name Landmarks
extends Node3D
## Original Ottoman neo-baroque waterfront mosque beside the Bogaz track, on the sea side: a quay over the water with a
## paved square and a domed prayer hall with two minarets. Scenery only: the quay and the hall have box colliders, and
## the quay starts at the seaside railing, so the road is never blocked. Built by assets_src/world/kit_landmarks.
## setup(track) places it; call it after add_child, with the track in the tree (track samples are world space).
## set_night(amount) switches the look: 0 day (pale stone, dark glass), 1 night (warm floodlight wash, glowing windows).

const DIR: String = "res://assets/world/kits/landmarks/"
const SHADER: Shader = preload("res://world/landmarks/landmark.gdshader")
const LOD_FILES: PackedStringArray = ["landmark_mosque_lod0.glb", "landmark_mosque_lod1.glb", "landmark_mosque_lod2.glb"]
const LOD_RANGES: Array = [[0.0, 120.0], [120.0, 320.0], [320.0, 1400.0]]  ## metres from the camera
const PLACE_S_M: float = 300.0  ## metres along the racing line: the straight with open water on the left
const EDGE_LAT_M: float = -13.0  ## lateral of the quay's landward edge: the seaside railing (sea side is negative)
const CC0_DIR: String = "res://assets/textures/cc0/"
const WORLD_LAYER: int = 1  ## buildings and static geometry, as Greenery and rain
const MIRROR_SKIP_BIT: int = 1 << 4  ## props layer: the planar mirror leaves it out (PlanarReflection.excluded_layers)
## mirror-only copy of LOD1: only the planar mirror's cull mask includes it. Not CarLod's bit 3: the car fill and rim
## lights see bit 3 (race_scene CAR_LIGHT_MASK), so a copy on bit 3 would be lit like a car.
const MIRROR_ONLY_BIT: int = 1 << 5
const HALL_CENTRE_LOCAL: Vector3 = Vector3(0.0, 8.0, -18.0)  ## local (Godot) centre of the prayer hall, at the walls' mid-height
const WARM: Color = Color(1.0, 0.64, 0.3)  ## sodium floodlight gold (0.74, 0.46 read as cold white on pale stone)

## Surface name (glTF material name from the kit) -> look. glow is emission at night in units of the shader.
const MATERIALS: Dictionary = {
	"M_Stone": {"base": Color(0.93, 0.86, 0.74), "rough": 0.55, "metal": 0.0, "glow": 0.0, "flood": 0.85, "course": 0.0, "tex": "sandstone_blocks_08", "tile": 2.6, "glow_color": Color(1.0, 0.74, 0.46)},
	"M_Dome": {"base": Color(0.42, 0.5, 0.5), "rough": 0.35, "metal": 0.5, "glow": 0.0, "flood": 0.3, "glow_color": WARM},
	"M_Glass": {"base": Color(0.12, 0.15, 0.2), "rough": 0.15, "metal": 0.0, "glow": 1.8, "flood": 0.0, "glow_color": Color(1.0, 0.7, 0.35)},
	"M_Lamp": {"base": Color(1.0, 0.88, 0.6), "rough": 0.3, "metal": 0.0, "glow": 6.0, "flood": 0.0, "glow_color": Color(1.0, 0.85, 0.55)},
	"M_Iron": {"base": Color(0.1, 0.1, 0.11), "rough": 0.4, "metal": 0.8, "glow": 0.0, "flood": 0.1, "glow_color": WARM},
	"M_Paving": {"tex": "marble_01", "tile": 3.0, "base": Color(0.78, 0.76, 0.72), "rough": 0.25, "metal": 0.0, "glow": 0.0, "flood": 0.25, "glow_color": WARM},
}

var placed_s: float = PLACE_S_M
var _night: float = 1.0
var _materials: Dictionary = {}  ## surface name -> ShaderMaterial, one set per Landmarks
var _lights: Array[OmniLight3D] = []


func setup(track: Track) -> void:
	var c: Vector3 = track.get_point_at(placed_s)
	var t: Vector3 = track.get_tangent_at(placed_s)
	t.y = 0.0
	t = t.normalized()
	var r: Vector3 = t.cross(Vector3.UP)  ## right of the race direction, the Track convention (+X when driving -Z)
	global_transform = Transform3D(Basis(t, Vector3.UP, r), c + r * EDGE_LAT_M)
	for i: int in LOD_FILES.size():
		var root: Node3D = (load(DIR + LOD_FILES[i]) as PackedScene).instantiate() as Node3D
		add_child(root)
		for mi: Node in root.find_children("*", "MeshInstance3D", true, false):
			_style(mi as MeshInstance3D, i)
	_add_collider()
	_add_lights()
	set_night(_night)


func _process(_delta: float) -> void:
	# The current camera (chase, replay, capture) must not draw the mirror-only copy; the mirror camera is not current.
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		cam.cull_mask &= ~MIRROR_ONLY_BIT


## 0 day, 1 night. Emission and the two OmniLights follow it.
func set_night(amount: float) -> void:
	_night = clampf(amount, 0.0, 1.0)
	for m: Variant in _materials.values():
		(m as ShaderMaterial).set_shader_parameter("night", _night)
	for l: OmniLight3D in _lights:
		l.visible = _night > 0.0
		l.light_energy = _light_energy(l.name)


## World position of the prayer hall centre (for cameras and tests).
func hall_centre() -> Vector3:
	return to_global(HALL_CENTRE_LOCAL)


func _style(mi: MeshInstance3D, lod: int) -> void:
	mi.visibility_range_begin = float(LOD_RANGES[lod][0])
	mi.visibility_range_end = float(LOD_RANGES[lod][1])
	if lod == 0:
		mi.layers = (mi.layers & ~1) | MIRROR_SKIP_BIT  ## the wet-road mirror leaves the near LOD0 out
	for i: int in mi.mesh.get_surface_count():
		var src: Material = mi.mesh.surface_get_material(i)
		var surface: String = src.resource_name if src != null else ""
		if not MATERIALS.has(surface):
			push_error("Landmarks: unknown surface material '%s' in %s" % [surface, mi.get_path()])
			continue
		mi.set_surface_override_material(i, _material(surface))
	if lod == 1:
		## mirror-only copy of LOD1 for the near range: the mirror draws it where it left LOD0 out, the cameras never do
		var mirror: MeshInstance3D = mi.duplicate() as MeshInstance3D
		mirror.layers = MIRROR_ONLY_BIT
		mirror.visibility_range_begin = 0.0
		mirror.visibility_range_end = float(LOD_RANGES[0][1])
		mirror.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.get_parent().add_child(mirror)


func _material(surface: String) -> ShaderMaterial:
	if _materials.has(surface):
		return _materials[surface] as ShaderMaterial
	var p: Dictionary = MATERIALS[surface]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.resource_name = surface
	m.set_shader_parameter("base_color", p.base)
	m.set_shader_parameter("roughness", p.rough)
	m.set_shader_parameter("metallic", p.metal)
	m.set_shader_parameter("glow", p.glow)
	m.set_shader_parameter("flood", p.flood)
	m.set_shader_parameter("course_m", float(p.get("course", 0.0)))
	if p.has("tex"):  # photo-based CC0 set (Poly Haven), projected in model space
		m.set_shader_parameter("albedo_tex", load(CC0_DIR + str(p.tex) + "/basecolor.jpg"))
		m.set_shader_parameter("rough_tex", load(CC0_DIR + str(p.tex) + "/roughness.jpg"))
		m.set_shader_parameter("tex_mix", 1.0)
		m.set_shader_parameter("tex_tile_m", float(p.tile))
	m.set_shader_parameter("glow_color", p.glow_color)
	m.set_shader_parameter("night", _night)
	_materials[surface] = m
	return m


## Two boxes: the quay (80 x 32 m, top at the kerb height 0.15 m) and the prayer hall. Nothing else blocks a car.
func _add_collider() -> void:
	var body := StaticBody3D.new()
	body.name = "Collider"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	add_child(body)
	_box(body, Vector3(80.0, 1.75, 32.0), Vector3(0.0, -0.725, -16.0))
	_box(body, Vector3(20.0, 15.85, 20.0), Vector3(0.0, 8.075, -18.0))


func _box(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	body.add_child(cs)


## Two real lights in total: the road-side flood over the square and the sea-side flood on the back of the hall.
func _add_lights() -> void:
	_lights.append(_light("FrontFlood", Vector3(0.0, 9.0, -1.5), 46.0))  ## was (0, 6, -4): 2 m from the portico arches, burnt them out
	_lights.append(_light("SeaFlood", Vector3(0.0, 10.0, -36.0), 40.0))


func _light(light_name: String, at: Vector3, range_m: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = light_name
	l.position = at
	l.omni_range = range_m
	l.light_color = WARM
	l.shadow_enabled = false
	add_child(l)
	return l


func _light_energy(light_name: String) -> float:
	var full: float = 0.95 if light_name == "FrontFlood" else 0.9  # 2.2 / 1.6 burnt the stone to white
	return full * _night
