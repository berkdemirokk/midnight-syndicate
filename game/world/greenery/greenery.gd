class_name Greenery
extends Node3D
## Trees on the sidewalks outside the race corridor. setup(track) queues the placement; it runs on the next physics
## tick because the ray checks need the physics space. Per species and ~240 m chunk there are three MultiMeshInstance3D
## LOD nodes with visibility ranges (LOD0 near, LOD1 mid, LOD2 impostor cards) and one blob MultiMesh for the soft
## dark patch under each tree. Trees cast no real-time shadow.

const SPECIES_DIR: String = "res://assets/world/kits/trees/"
const PHOTO_DIR: String = "res://assets/world/kits/trees_photo/"
const FOLIAGE_SHADER: Shader = preload("res://shaders/foliage.gdshader")
const PHOTO_SHADER: Shader = preload("res://shaders/tree_photo.gdshader")
const BLOB_SHADER: Shader = preload("res://world/greenery/tree_blob.gdshader")
## Photo species: crossed cards with a photo of the tree (game/assets/world/kits/trees_photo, built by
## assets_src/ai_generated/chatgpt/prepare_photo_trees.py). h_m: card height = tree height at scale 1. w_ratio: card
## width / height. halves: trees per texture (planes: two in one atlas, picked per tree by INSTANCE_CUSTOM).
const PHOTO: Dictionary = {
	"plane": {"tex": "plane_atlas.png", "night": "plane_atlas_night.jpg", "h_m": 11.5, "w_ratio": 1.0, "halves": 2.0, "night_dim": 0.3},
	"cypress": {"tex": "cypress.png", "night": "", "h_m": 10.3, "w_ratio": 0.25, "halves": 1.0, "night_dim": 0.5},
	"judas": {"tex": "judas.png", "night": "", "h_m": 5.5, "w_ratio": 1.0, "halves": 1.0, "night_dim": 0.5},
}
const CORRIDOR_CLEAR_M: float = 1.0  ## a crown may overhang the pavement, but its inner edge stays this far outside the road edge
const CROWN_SHADOW: bool = true
static var _photo_meshes: Dictionary = {}  ## species -> card Mesh
static var _photo_materials: Dictionary = {}  ## species -> ShaderMaterial
static var _black: ImageTexture = null  ## night picture of species without one: black, so no glow

const CHUNK_M: float = 240.0
const SPACING_MIN_M: float = 9.0  ## was 18-30: about 70 trees per track read as bare streets
const SPACING_MAX_M: float = 16.0
const OPEN_VIEW_M: float = 36.0  ## no ground this far outward of a spot: it is the water side, the view matters more than shade
const OPEN_SKIP: float = 0.7  ## share of open-view spots left empty
const SIDEWALK_MIN_M: float = 2.5  ## from the road edge, clear of the kerb
const SIDEWALK_MAX_M: float = 6.5
const TRIES_PER_STEP: int = 3
const WORLD_MASK: int = 1  ## physics layer 1: buildings and static geometry, as rain.gd
const PROBE_RADIUS_M: float = 1.0
const CROWN_R_M: Dictionary = {"plane": 3.7, "judas": 2.4, "cypress": 0.9, "street": 1.1}  ## crown reach per species for the block probe: 90th percentile of the leaf radius (assets_src/world/kit_trees/prepare_licensed_trees.py)
const CROWN_CORRIDOR_M: Dictionary = {"plane": 5.0}  ## photo plane crown reach (about 0.4 to 0.5 of the 11.5 m height): the corridor clearance uses it
const ROOF_CHECK_M: float = 9.0  ## overpass or tunnel roof above the tree disqualifies the spot
const GRADE_TOL_M: float = 1.0  ## the tree must stand on the same grade as the racing line
const BLOB_LIFT_M: float = 0.04
const BLOB_RANGE_M: float = 220.0
## LOD distances, metres from the camera. Each switch fades over FADE_M (dither), so the next LOD takes over smoothly.
const LOD_RANGES: Array = [[0.0, 60.0], [60.0, 150.0], [150.0, 320.0]]
const FADE_M: float = 6.0  ## dither band at each switch: the hard pops at 60, 150 and 320 m were the visible ones

## Blob diameter in metres and per-tree scale range. Species geometry is built in assets_src/world/kit_trees.
const SPECIES: Dictionary = {
	"plane": {"blob_m": 10.0, "scale": Vector2(0.9, 1.1)},
	"judas": {"blob_m": 5.0, "scale": Vector2(0.9, 1.1)},
	"cypress": {"blob_m": 2.2, "scale": Vector2(0.9, 1.15)},
	"street": {"blob_m": 2.8, "scale": Vector2(0.9, 1.1)},
}
## Species weights by track. Bogaz: erguvan, cypress and planes; Maslak: planters and planes; City 01: planters.
const MIX: Dictionary = {
	"bogaz": {"judas": 0.45, "cypress": 0.2, "plane": 0.35},
	"maslak": {"street": 0.5, "plane": 0.5},
	"city": {"street": 1.0},
}

static var _meshes: Dictionary = {}  ## "species_lod" -> Mesh, shared by every Greenery
static var _blob_mesh: QuadMesh = null
static var _blob_material: ShaderMaterial = null

var placements: Array[Dictionary] = []  ## {species, pos, chunk, lateral} per tree, for tests and the demo
var rejected: Dictionary = {}  ## reason ("grade", "roof", "facade") -> spots refused, for the demo and tuning
var _track: Track = null
var _pending: bool = false
var _rng := RandomNumberGenerator.new()
var _probe := SphereShape3D.new()  ## trunk-and-crown-base clearance probe, radius in m


## Leaf tint per species (multiplies the atlas). Judas: muted blossom, the raw magenta glowed under the lamps. Cypress: its needles are painted almost black.
const LEAF_TINT: Dictionary = {"judas": Color(0.92, 0.66, 0.8), "cypress": Color(0.8, 0.95, 0.72), "street": Color(0.6, 0.76, 0.5)}
const BARK_TINT: Dictionary = {"plane": Color(0.6, 0.56, 0.5), "judas": Color(0.7, 0.66, 0.64), "cypress": Color(0.75, 0.66, 0.58), "street": Color(0.62, 0.58, 0.52)}  ## multiplies the model's bark texture
static var _leaf_materials: Array[ShaderMaterial] = []  ## every cached leaf material, so the hour can retune them


## Sky light inside the crowns for this race: about 0.5 by day, 0.2 at dusk, 0 at night. Call after setup().
static func set_shade_fill(v: float) -> void:
	_shade_fill = v
	for m: ShaderMaterial in _leaf_materials:
		m.set_shader_parameter("shade_fill", v)


static var _shade_fill: float = 0.0
var keep_open_view: bool = false  ## coast tracks set this before setup(): the water side stays mostly free of trees


func setup(track_in: Track) -> void:
	_track = track_in
	_probe.radius = PROBE_RADIUS_M
	_pending = true


func placed_count() -> int:
	return placements.size()


func species_counts() -> Dictionary:
	var out: Dictionary = {}
	for p: Dictionary in placements:
		out[p.species] = int(out.get(p.species, 0)) + 1
	return out


func _physics_process(_delta: float) -> void:
	if not _pending:
		return
	_pending = false
	_place()
	_build_nodes()


func _place() -> void:
	if _track == null or _track.length <= 0.0:
		push_error("Greenery needs a placed track with a racing line")
		return
	var mix: Dictionary = MIX.get(_mix_key(), MIX["city"])
	_rng.seed = int(_track.length * 1000.0)
	var length: float = _track.length
	var side: float = -1.0
	var s: float = _rng.randf_range(0.0, SPACING_MAX_M)
	while s < length:
		side = -side  # alternate sides
		var centre: Vector3 = _track.get_point_at(s)
		var fwd: Vector3 = _track.get_tangent_at(s)
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right: Vector3 = fwd.cross(Vector3.UP)
		# Up to three tries per step, each one pulled in towards the road: a block line close to the kerb
		# otherwise costs the whole step.
		var pos: Vector3 = centre
		var reason: String = "inside"
		var species: String = _pick(mix)
		var gap: float = _trunk_gap(species)
		for attempt: int in TRIES_PER_STEP:
			# Later tries move in toward the road but never closer than the kerb clearance (wider for a crown).
			var offset: float = _track.width * 0.5 + maxf(gap, _rng.randf_range(gap, SIDEWALK_MAX_M) - attempt * 1.0)
			pos = centre + right * side * offset
			reason = _rejection(pos, centre)
			# The centreline bends: measure the real lateral distance at the nearest point, not at this sample.
			if reason == "" and absf(_track.get_lateral_offset(pos, s)) < _track.width * 0.5 + gap - 0.5:
				reason = "corridor"
			if reason == "":
				break
		if reason == "":
			# Open side (a quay, the sea): keep the view. Most spots stay empty and the rest take a narrow species.
			if keep_open_view and _open_view(pos, right * side):
				if _rng.randf() < OPEN_SKIP or not (mix.has("cypress") or mix.has("street")):
					rejected["view"] = int(rejected.get("view", 0)) + 1
					s += _rng.randf_range(SPACING_MIN_M, SPACING_MAX_M)
					continue
				species = "cypress" if mix.has("cypress") else "street"
			# A wide crown must not poke into a facade: the picked species keeps its weight, a spot that cannot take it is skipped.
			if _crown_blocked(pos, float(CROWN_R_M.get(species, 1.5))):
				rejected["crown"] = int(rejected.get("crown", 0)) + 1
				s += _rng.randf_range(SPACING_MIN_M, SPACING_MAX_M)
				continue
			placements.append({"species": species, "pos": pos, "chunk": int(s / CHUNK_M),
				"lateral": _track.get_lateral_offset(pos, s), "yaw": _rng.randf() * TAU,
				"scale": _rng.randf_range(SPECIES[species].scale.x, SPECIES[species].scale.y), "variant": _rng.randi() % 2})
		else:
			rejected[reason] = int(rejected.get(reason, 0)) + 1
		s += _rng.randf_range(SPACING_MIN_M, SPACING_MAX_M)


## Trunk distance from the road's half width: the kerb clearance, or for a wide crown the crown reach plus CORRIDOR_CLEAR_M,
## so the crown may overhang the pavement but never the race corridor.
func _trunk_gap(species: String) -> float:
	return maxf(SIDEWALK_MIN_M, float(CROWN_CORRIDOR_M.get(species, CROWN_R_M.get(species, 1.5))) + CORRIDOR_CLEAR_M)


## "" when the spot is free, else why it is not: another grade, an overpass or tunnel roof above it, or static
## geometry (a building, a wall) around the trunk and crown base, which means the tree stands inside a block.
func _rejection(pos: Vector3, centre: Vector3) -> String:
	if absf(pos.y - centre.y) > GRADE_TOL_M:
		return "grade"
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var roof := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.UP * ROOF_CHECK_M, WORLD_MASK)
	if not space.intersect_ray(roof).is_empty():
		return "roof"
	for h: float in [1.2, 3.0]:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _probe
		q.transform = Transform3D(Basis(), pos + Vector3.UP * h)
		q.collision_mask = WORLD_MASK
		if not space.intersect_shape(q, 1).is_empty():
			return "inside"
	return ""


## True when the ground ends within OPEN_VIEW_M outward of the spot: that side is the water, the view matters there.
## (A sideways ray does not work: the track has invisible side walls.)
func _open_view(pos: Vector3, outward: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	# A block right behind the spot: built-up side, whatever lies behind the block.
	var eye: Vector3 = pos + Vector3.UP * 8.0
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + outward * 14.0, WORLD_MASK)).is_empty():
		return false
	for d: float in [OPEN_VIEW_M * 0.5, OPEN_VIEW_M]:
		var from: Vector3 = pos + outward * d + Vector3.UP * 30.0
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 32.0, WORLD_MASK)
		if space.intersect_ray(q).is_empty():
			return true
	return false


## True when static geometry (a facade, a balcony, a roof edge) is inside the crown's reach at crown height.
func _crown_blocked(pos: Vector3, radius: float) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var crown := SphereShape3D.new()
	crown.radius = radius
	# Probe heights keep the sphere underside a metre above the pavement: a wide crown probe touched the kerb at every spot.
	for h: float in [maxf(4.0, radius + 1.0), maxf(6.5, radius + 3.0)]:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = crown
		q.transform = Transform3D(Basis(), pos + Vector3.UP * h)
		q.collision_mask = WORLD_MASK
		if not space.intersect_shape(q, 1).is_empty():
			return true
	return false


func _mix_key() -> String:
	var id: String = (_track.scene_file_path + " " + _track.name).to_lower()
	if "bogaz" in id:
		return "bogaz"
	if "maslak" in id:
		return "maslak"
	return "city"


func _pick(mix: Dictionary) -> String:
	var r: float = _rng.randf()
	var acc: float = 0.0
	var last: String = ""
	for k: String in mix:
		acc += float(mix[k])
		last = k
		if r < acc:
			return k
	return last


func _build_nodes() -> void:
	var trees: Dictionary = {}  # "chunk|species" -> Array[Dictionary] (placements)
	var blobs: Dictionary = {}  # chunk -> Array[Transform3D]
	for p: Dictionary in placements:
		var key: String = "%d|%s" % [p.chunk, p.species]
		if not trees.has(key):
			trees[key] = []
		trees[key].append(p)
		if not blobs.has(p.chunk):
			blobs[p.chunk] = []
		var d: float = SPECIES[p.species].blob_m * p.scale
		var blob := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3.ONE * d), p.pos + Vector3.UP * BLOB_LIFT_M)
		blobs[p.chunk].append(blob)
	for key: String in trees:
		var parts: PackedStringArray = key.split("|")
		if PHOTO.has(parts[1]):
			_add_photo_multimesh(trees[key], parts[1], "%s_c%s_photo" % [parts[1], parts[0]])
			continue
		var xforms: Array = []
		for p: Dictionary in trees[key]:
			xforms.append(_xform(p))
		for lod: int in 3:
			_add_multimesh(xforms, _lod_mesh(parts[1], lod), LOD_RANGES[lod], "%s_c%s_l%d" % [parts[1], parts[0], lod])
	for chunk: int in blobs:
		_add_multimesh(blobs[chunk], _blob(), [0.0, BLOB_RANGE_M], "blob_c%d" % chunk)


func _add_multimesh(xforms: Array, mesh: Mesh, vis: Array, node_name: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.visibility_range_begin = vis[0]
	mmi.visibility_range_begin_margin = FADE_M if vis[0] > 0.0 else 0.0
	mmi.visibility_range_end = vis[1]
	mmi.visibility_range_end_margin = FADE_M
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _xform(p: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, p.yaw).scaled(Vector3.ONE * p.scale), p.pos)


## One MultiMesh per chunk for a photo species: all LODs in one node (the cards are 6 triangles), shadows on.
## Custom data x: the atlas half for a two-tree texture (planes), 0 otherwise.
func _add_photo_multimesh(group: Array, species: String, node_name: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _photo_mesh(species)
	mm.instance_count = group.size()
	var halves: float = float(PHOTO[species].halves)
	for i: int in group.size():
		var p: Dictionary = group[i]
		mm.set_instance_transform(i, _xform(p))
		mm.set_instance_custom_data(i, Color(0.5 * float(p.variant) if halves > 1.0 else 0.0, 0.0, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.visibility_range_begin = LOD_RANGES[0][0]
	mmi.visibility_range_end = LOD_RANGES[2][1]
	mmi.visibility_range_end_margin = FADE_M
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if CROWN_SHADOW else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Three crossed cards through the trunk axis (60 degree steps), double-sided, the tree photo on each.
static func _photo_mesh(species: String) -> Mesh:
	if _photo_meshes.has(species):
		return _photo_meshes[species]
	var cfg: Dictionary = PHOTO[species]
	var h: float = cfg.h_m
	var w: float = h * cfg.w_ratio
	var corners: Array[Vector3] = [Vector3(-w / 2.0, 0.0, 0.0), Vector3(w / 2.0, 0.0, 0.0), Vector3(w / 2.0, h, 0.0), Vector3(-w / 2.0, h, 0.0)]
	var uvs: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k: int in 3:
		var b := Basis(Vector3.UP, float(k) * PI / 3.0)
		var n: Vector3 = (b * Vector3(0.0, 0.3, 1.0)).normalized()  # tilted up: crowns read lit from above
		for i: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(uvs[i])
			st.add_vertex(b * corners[i])
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	mesh.surface_set_material(0, _photo_material(species))
	_photo_meshes[species] = mesh
	return mesh


static func _photo_material(species: String) -> ShaderMaterial:
	if _photo_materials.has(species):
		return _photo_materials[species]
	var cfg: Dictionary = PHOTO[species]
	var m := ShaderMaterial.new()
	m.shader = PHOTO_SHADER
	m.set_shader_parameter("albedo_tex", load(PHOTO_DIR + cfg.tex))
	m.set_shader_parameter("night_tex", load(PHOTO_DIR + cfg.night) if cfg.night != "" else _black_texture())
	m.set_shader_parameter("atlas_halves", cfg.halves)
	m.set_shader_parameter("night_dim", cfg.night_dim)
	m.set_shader_parameter("shade_fill", _shade_fill)
	_leaf_materials.append(m)
	_photo_materials[species] = m
	return m


static func _black_texture() -> ImageTexture:
	if _black == null:
		_black = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGB8))
	return _black


static func _lod_mesh(species: String, lod: int) -> Mesh:
	var id: String = "%s_%d" % [species, lod]
	if _meshes.has(id):
		return _meshes[id]
	var packed := load(SPECIES_DIR + "tree_%s_lod%d.glb" % [species, lod]) as PackedScene
	var inst: Node = packed.instantiate()
	var mi: MeshInstance3D = null
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		mi = n as MeshInstance3D
		break
	var mesh: ArrayMesh = mi.mesh as ArrayMesh
	inst.free()
	var leaf := ShaderMaterial.new()
	leaf.shader = FOLIAGE_SHADER
	leaf.set_shader_parameter("tint", LEAF_TINT.get(species, Color(0.72, 0.87, 0.64)))  # daylight mid-green: the lifted tint read as neon lime under the sun
	if lod == 2:
		leaf.set_shader_parameter("albedo_tex", load(SPECIES_DIR + "impostor_%s.png" % species))
		mesh.surface_set_material(0, leaf)
	else:
		leaf.set_shader_parameter("albedo_tex", load(SPECIES_DIR + "leaf_%s.png" % species))  # the model's own leaf texture
		var bark := StandardMaterial3D.new()
		bark.vertex_color_use_as_albedo = true  # vertex colour = baked AO only
		bark.albedo_texture = load(SPECIES_DIR + "bark_%s.png" % species)  # the model's own bark texture, tiled
		bark.albedo_color = BARK_TINT.get(species, Color(0.8, 0.76, 0.7))
		bark.roughness = 0.95
		mesh.surface_set_material(0, bark)  # GLB order: surface 0 bark, surface 1 leaves
		mesh.surface_set_material(1, leaf)
	leaf.set_shader_parameter("shade_fill", _shade_fill)
	_leaf_materials.append(leaf)
	_meshes[id] = mesh
	return mesh


static func _blob() -> Mesh:
	if _blob_mesh == null:
		_blob_mesh = QuadMesh.new()
		_blob_mesh.size = Vector2.ONE
		_blob_material = ShaderMaterial.new()
		_blob_material.shader = BLOB_SHADER
		_blob_mesh.material = _blob_material
	return _blob_mesh
