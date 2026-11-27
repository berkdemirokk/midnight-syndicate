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
## Photo walls: a straight-on picture of one hall wall on a quad just in front of each of the four hall walls (and its
## night picture as glow map), when the picture is shipped. See docs/art/PHOTO_TEXTURE_PIPELINE.md.
const PHOTO_WALL: String = "res://assets/world/kits/photo_fronts/mosque_wall_01.jpg"
const PHOTO_WALL_NIGHT: String = "res://assets/world/kits/photo_fronts/mosque_wall_01_night.jpg"
const PHOTO_SHADER: Shader = preload("res://world/street_fronts/photo_facade.gdshader")
const HALL_HALF_M: float = 10.0
const WALL_TOP_M: float = 15.0
const PHOTO_OFF_M: float = 0.62  ## in front of the window surrounds (0.54 m proud of the glass)
const PHOTO_END_M: float = 320.0  ## to the end of LOD1
const PHOTO_GLOW: float = 1.3
const HALL_CENTRE_LOCAL: Vector3 = Vector3(0.0, 8.0, -18.0)  ## local (Godot) centre of the prayer hall, at the walls' mid-height
const WARM: Color = Color(1.0, 0.64, 0.3)  ## sodium floodlight gold (0.74, 0.46 read as cold white on pale stone)
const DOME_MATERIAL: String = "M_Dome"  ## the lathe-built domes, turret caps, pencil caps and the rib prisms on the dome
const CREASE_COS: float = 0.5  ## faces more than 60 degrees apart keep a hard edge (rib sides, the dome rim)

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
var _photo: ShaderMaterial = null


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
	_add_photo_walls()
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
	if _photo != null:
		_photo.set_shader_parameter("night", _night * PHOTO_GLOW)
		_photo.set_shader_parameter("tint", Vector3(0.9, 0.78, 0.6).lerp(Vector3(0.6, 0.55, 0.5), _night))  # by day: the sandstone of the towers
	for l: OmniLight3D in _lights:
		l.visible = _night > 0.0
		l.light_energy = _light_energy(l.name)


func _add_photo_walls() -> void:
	if not ResourceLoader.exists(PHOTO_WALL):
		return
	_photo = ShaderMaterial.new()
	_photo.shader = PHOTO_SHADER
	_photo.set_shader_parameter("albedo_tex", load(PHOTO_WALL))
	if ResourceLoader.exists(PHOTO_WALL_NIGHT):
		_photo.set_shader_parameter("night_tex", load(PHOTO_WALL_NIGHT))
	if ResourceLoader.exists(PHOTO_WALL.replace(".jpg", "_normal.png")):
		_photo.set_shader_parameter("normal_tex", load(PHOTO_WALL.replace(".jpg", "_normal.png")))
		_photo.set_shader_parameter("relief", 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(HALL_HALF_M * 2.0, WALL_TOP_M)
	quad.material = _photo
	for k: int in 4:  # road side, right, sea side, left
		var basis := Basis(Vector3.UP, float(k) * PI / 2.0)
		var wall := MeshInstance3D.new()
		wall.name = "PhotoWall%d" % k
		wall.mesh = quad
		wall.visibility_range_end = PHOTO_END_M
		add_child(wall)
		wall.transform = Transform3D(basis, Vector3(HALL_CENTRE_LOCAL.x, WALL_TOP_M / 2.0, HALL_CENTRE_LOCAL.z) + basis.z * (HALL_HALF_M + PHOTO_OFF_M))


## World position of the prayer hall centre (for cameras and tests).
func hall_centre() -> Vector3:
	return to_global(HALL_CENTRE_LOCAL)


func _style(mi: MeshInstance3D, lod: int) -> void:
	mi.mesh = smooth_dome_mesh(mi.mesh)  ## a new mesh for this instance only: the cached GLB stays as shipped
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


## The kit builds every triangle with its own vertices, so the dome's normals were the flat face normals (the facets
## read as panels). Same vertices, indices, surfaces and materials: only ARRAY_NORMAL of the DOME_MATERIAL surfaces
## changes, to the average of the faces that share the point and lie within CREASE_COS of this face.
## shortcut: assumes each index is used by one triangle (true for the kit); a shared index would take its last corner's normal.
static func smooth_dome_mesh(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i: int in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(i)
		var mat: Material = src.surface_get_material(i)
		var kind: int = src.surface_get_primitive_type(i)
		if mat != null and mat.resource_name == DOME_MATERIAL and kind == Mesh.PRIMITIVE_TRIANGLES:
			arrays[Mesh.ARRAY_NORMAL] = _smooth_normals(arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_INDEX])
		out.add_surface_from_arrays(kind, arrays)
		out.surface_set_material(i, mat)
	return out


static func _smooth_normals(verts: PackedVector3Array, index: Variant) -> PackedVector3Array:
	var idx := PackedInt32Array()
	if index == null:
		idx.resize(verts.size())
		for k: int in verts.size():
			idx[k] = k
	else:
		idx = index
	var tris: int = idx.size() / 3
	var face_n := PackedVector3Array()  ## area-weighted face normals (cross product, length = twice the area)
	face_n.resize(tris)
	var touching: Dictionary = {}  ## welded position -> triangles that use it
	for t: int in tris:
		var a: Vector3 = verts[idx[3 * t]]
		face_n[t] = (verts[idx[3 * t + 1]] - a).cross(verts[idx[3 * t + 2]] - a)
		for k: int in 3:
			var key: Vector3i = _weld_key(verts[idx[3 * t + k]])
			if not touching.has(key):
				touching[key] = []
			(touching[key] as Array).append(t)
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for t: int in tris:
		var own: Vector3 = face_n[t].normalized()
		for k: int in 3:
			var sum := Vector3.ZERO
			for f: int in touching[_weld_key(verts[idx[3 * t + k]])]:
				if face_n[f].normalized().dot(own) >= CREASE_COS:
					sum += face_n[f]
			normals[idx[3 * t + k]] = sum.normalized() if not sum.is_zero_approx() else Vector3.UP
	return normals


static func _weld_key(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x * 10000.0), roundi(p.y * 10000.0), roundi(p.z * 10000.0))


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
