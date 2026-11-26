class_name Greenery
extends Node3D
## Trees on the sidewalks outside the race corridor. setup(track) queues the placement; it runs on the next physics
## tick because the ray checks need the physics space. Per species and ~240 m chunk there are three MultiMeshInstance3D
## LOD nodes with visibility ranges (LOD0 near, LOD1 mid, LOD2 impostor cards) and one blob MultiMesh for the soft
## dark patch under each tree. Trees cast no real-time shadow.

const SPECIES_DIR: String = "res://assets/world/kits/trees/"
const FOLIAGE_SHADER: Shader = preload("res://shaders/foliage.gdshader")
const BLOB_SHADER: Shader = preload("res://world/greenery/tree_blob.gdshader")
const LEAF_ATLAS: String = "res://assets/world/kits/trees/leaf_atlas.png"

const CHUNK_M: float = 240.0
const SPACING_MIN_M: float = 18.0
const SPACING_MAX_M: float = 30.0
const SIDEWALK_MIN_M: float = 2.5  ## from the road edge, clear of the kerb
const SIDEWALK_MAX_M: float = 6.5
const TRIES_PER_STEP: int = 3
const WORLD_MASK: int = 1  ## physics layer 1: buildings and static geometry, as rain.gd
const PROBE_RADIUS_M: float = 1.0
const ROOF_CHECK_M: float = 9.0  ## overpass or tunnel roof above the tree disqualifies the spot
const GRADE_TOL_M: float = 1.0  ## the tree must stand on the same grade as the racing line
const BLOB_LIFT_M: float = 0.04
const BLOB_RANGE_M: float = 220.0
## LOD distances, metres from the camera. Pops are hard: no fade margins (shortcut: fade needs the dither shader).
const LOD_RANGES: Array = [[0.0, 60.0], [60.0, 150.0], [150.0, 320.0]]

## Blob diameter in metres and per-tree scale range. Species geometry is built in assets_src/world/kit_trees.
const SPECIES: Dictionary = {
	"plane": {"blob_m": 9.0, "scale": Vector2(0.9, 1.1)},
	"judas": {"blob_m": 5.0, "scale": Vector2(0.9, 1.1)},
	"cypress": {"blob_m": 2.6, "scale": Vector2(0.9, 1.15)},
	"street": {"blob_m": 3.2, "scale": Vector2(0.9, 1.1)},
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
		for attempt: int in TRIES_PER_STEP:
			var offset: float = _track.width * 0.5 + _rng.randf_range(SIDEWALK_MIN_M, SIDEWALK_MAX_M) - attempt * 1.0
			pos = centre + right * side * offset
			reason = _rejection(pos, centre)
			if reason == "":
				break
		if reason == "":
			var species: String = _pick(mix)
			placements.append({"species": species, "pos": pos, "chunk": int(s / CHUNK_M),
				"lateral": _track.get_lateral_offset(pos, s), "yaw": _rng.randf() * TAU,
				"scale": _rng.randf_range(SPECIES[species].scale.x, SPECIES[species].scale.y)})
		else:
			rejected[reason] = int(rejected.get(reason, 0)) + 1
		s += _rng.randf_range(SPACING_MIN_M, SPACING_MAX_M)


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
	var trees: Dictionary = {}  # "chunk|species" -> Array[Transform3D]
	var blobs: Dictionary = {}  # chunk -> Array[Transform3D]
	for p: Dictionary in placements:
		var xf := Transform3D(Basis(Vector3.UP, p.yaw).scaled(Vector3.ONE * p.scale), p.pos)
		var key: String = "%d|%s" % [p.chunk, p.species]
		if not trees.has(key):
			trees[key] = []
		trees[key].append(xf)
		if not blobs.has(p.chunk):
			blobs[p.chunk] = []
		var d: float = SPECIES[p.species].blob_m * p.scale
		var blob := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3.ONE * d), p.pos + Vector3.UP * BLOB_LIFT_M)
		blobs[p.chunk].append(blob)
	for key: String in trees:
		var parts: PackedStringArray = key.split("|")
		for lod: int in 3:
			_add_multimesh(trees[key], _lod_mesh(parts[1], lod), LOD_RANGES[lod], "%s_c%s_l%d" % [parts[1], parts[0], lod])
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
	mmi.visibility_range_end = vis[1]
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


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
	if lod == 2:
		leaf.set_shader_parameter("albedo_tex", load(SPECIES_DIR + "impostor_%s.png" % species))
		mesh.surface_set_material(0, leaf)
	else:
		leaf.set_shader_parameter("albedo_tex", load(LEAF_ATLAS))
		var bark := StandardMaterial3D.new()
		bark.vertex_color_use_as_albedo = true
		bark.roughness = 0.92
		mesh.surface_set_material(0, bark)  # GLB order: surface 0 bark, surface 1 leaves
		mesh.surface_set_material(1, leaf)
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
