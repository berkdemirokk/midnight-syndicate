class_name EventDressing
extends Node3D
## Race-event dressing outside the race corridor on the coast road: concrete race barriers with banners on both
## sides, spectators behind them, flags on poles, and land-side cafe terraces (striped awning, warm bulbs on a
## sagging cable, a light pool). setup(track, time_of_day_id) queues the placement; it runs on the next physics tick,
## because the ray and shape checks need the physics space. Per 240 m chunk every kind is one MultiMeshInstance3D
## with a visibility range (hard pops, as greenery.gd); each cable is one MeshInstance3D. Day builds no bulbs, cables
## or light pools.

const KIT: String = "res://assets/world/kits/event/"
const CROWD_SHADER: Shader = preload("res://shaders/crowd_card.gdshader")
const FLAG_SHADER: Shader = preload("res://shaders/flag_wave.gdshader")
const BANNER_TEX: String = KIT + "banner_atlas.png"
const CROWD_TEX: String = KIT + "crowd_atlas.png"
const FLAG_TEX: String = KIT + "flag_tr.png"
const ATLAS_TEX: String = KIT + "awning_atlas.png"
const GLOW_TEX: String = KIT + "awning_glow.png"
const POOL_TEX: String = KIT + "light_pool.png"

const CHUNK_M: float = 240.0
const WORLD_MASK: int = 1  ## physics layer 1: buildings, road and sidewalk colliders, as greenery.gd
const GRADE_TOL_M: float = 1.0  ## ground under a piece must be this close to the racing line's height
const ROOF_CHECK_M: float = 9.0  ## an overpass or tunnel roof above the piece disqualifies the spot
const BODY_RADIUS_M: float = 0.3  ## clearance around a barrier, flag or terrace spot
const CROWD_BODY_M: float = 0.6  ## a spectator card is 0.9 m wide; a facade inside this radius of the card is a spot to skip
const BARRIER_STEP_M: float = 4.0  ## one barrier segment per 4 m, both sides of the road
const BARRIER_LAT_M: float = 0.9  ## barrier centre beyond the road half width; its road face stands about 0.6 m out
const CROWD_LAT_M: float = 2.4  ## spectator centre beyond the road half width, behind the barriers
const CROWD_GAP_M: float = 0.85
const CROWD_ENABLED: bool = false  ## the flat spectator cards read as toy figures up close: off until real figures exist
const CROWD_GROUP_MIN: int = 5
const CROWD_GROUP_MAX: int = 12
const CROWD_STEP_EARLY_M: float = 45.0  ## groups every 45 m before EARLY_END_M (the start line), then every 120 m
const CROWD_STEP_M: float = 120.0
const EARLY_END_M: float = 350.0
const CROWD_H_M: float = 1.8  ## card height; the card stands on the ground by its bottom edge
const CROWD_W_M: float = 0.9
const FLAG_STEP_M: float = 36.0
const FLAG_LAT_M: float = 4.2
const CAFE_STEP_M: float = 170.0
const CAFE_OFFSET_M: float = 60.0
const CAFE_LAT_M: float = 6.0  ## awning origin; its road-side front is 1.15 m nearer the road
const CAFE_TABLE_X_M: float = 1.2  ## the two cafe sets stand at +-1.2 m along the awning
const POOL_SIZE_M: Vector2 = Vector2(4.4, 3.0)
const BULB_COUNT: int = 9
const BULB_SAG_M: float = 0.25
const CABLE_Y_M: float = 2.2  ## cable height at the awning ends, above the ground
const CABLE_X_M: float = 1.95  ## cable ends, along the awning
const CABLE_Z_M: float = 1.2  ## cable run in front of the awning lip, towards the road
const RANGE_BARRIER_M: float = 260.0
const RANGE_CROWD_M: float = 200.0
const RANGE_FLAG_M: float = 300.0
const RANGE_CAFE_M: float = 220.0

## Per time of day: lit (bulbs, cables, light pools built), spectator tone, bulb emission, pool strength, awning glow.
const TOD: Dictionary = {
	"day": {"lit": false, "tone": Vector3(0.78, 0.76, 0.72), "bulb": 0.0, "pool": 0.0, "glow": 0.0},
	"sunset": {"lit": true, "tone": Vector3(0.62, 0.52, 0.44), "bulb": 2.5, "pool": 0.55, "glow": 0.2},
	"night": {"lit": true, "tone": Vector3(0.5, 0.42, 0.38), "bulb": 4.0, "pool": 1.0, "glow": 0.35},
}

var placements: Array[Dictionary] = []  ## {kind, pos, s, lateral, chunk, face, ...} per piece, for tests and the demo
var rejected: Dictionary = {}  ## reason ("ground", "roof", "inside") -> spots refused, for the demo and tuning
var _track: Track = null
var _tod: String = "night"
var _pending: bool = false
var _rng := RandomNumberGenerator.new()


func setup(track_in: Track, time_of_day_id: String) -> void:
	_track = track_in
	_tod = time_of_day_id if TOD.has(time_of_day_id) else "night"
	_pending = true


func placed_count() -> int:
	return placements.size()


func kind_counts() -> Dictionary:
	var out: Dictionary = {}
	for p: Dictionary in placements:
		out[p.kind] = int(out.get(p.kind, 0)) + 1
	return out


func _physics_process(_delta: float) -> void:
	if not _pending:
		return
	_pending = false
	_place()
	_build_nodes()


func _place() -> void:
	if _track == null or _track.length <= 0.0:
		push_error("EventDressing needs a placed track with a racing line")
		return
	_rng.seed = int(_track.length * 1000.0) + 7
	_place_barriers()
	_place_crowds()
	_place_flags()
	_place_cafes()


func _place_barriers() -> void:
	var s: float = 0.0
	while s < _track.length:
		for side: float in [-1.0, 1.0]:
			_put_any("barrier_%d" % _rng.randi_range(0, 2), s, side, [BARRIER_LAT_M], {})
		s += BARRIER_STEP_M


func _place_crowds() -> void:
	if not CROWD_ENABLED:
		return
	var s: float = _rng.randf_range(10.0, 30.0)
	while s < _track.length:
		var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
		var n: int = _rng.randi_range(CROWD_GROUP_MIN, CROWD_GROUP_MAX)
		for i: int in n:
			var along: float = s + (float(i) - float(n) * 0.5) * CROWD_GAP_M + _rng.randf_range(-0.15, 0.15)
			var extra: Dictionary = {"cell": _rng.randi_range(0, 15), "hue": _rng.randf_range(-0.06, 0.06),
				"phase": _rng.randf()}
			_put_any("crowd", along, side, [CROWD_LAT_M, CROWD_LAT_M + 0.5, CROWD_LAT_M + 1.0, CROWD_LAT_M - 0.4, CROWD_LAT_M + 1.6], extra)
		var step: float = CROWD_STEP_EARLY_M if s < EARLY_END_M else CROWD_STEP_M
		s += step * _rng.randf_range(0.8, 1.2)


func _place_flags() -> void:
	var side: float = 1.0
	var s: float = 20.0
	while s < _track.length:
		side = -side
		_put_any("flag", s, side, [FLAG_LAT_M, FLAG_LAT_M - 0.6, FLAG_LAT_M + 0.8, FLAG_LAT_M + 1.6], {})
		s += FLAG_STEP_M


func _place_cafes() -> void:
	var s: float = CAFE_OFFSET_M
	while s < _track.length:
		var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
		_put_any("cafe", s, side, [CAFE_LAT_M, CAFE_LAT_M - 0.8, CAFE_LAT_M + 1.0, CAFE_LAT_M + 2.0], {})
		s += CAFE_STEP_M


## Tries the offsets (metres beyond the road half width, on the given side) in order; the first free spot wins.
func _put_any(kind: String, s: float, side: float, offsets: Array, extra: Dictionary) -> bool:
	var edge: float = _track.width * 0.5
	for off: float in offsets:
		if _put(kind, s, side * (edge + off), extra):
			return true
	return false


## Places one piece at lateral offset lat on arc length s, its front (+Z) towards the road. Returns true when placed.
func _put(kind: String, s: float, lat: float, extra: Dictionary) -> bool:
	var along: float = fposmod(s, _track.length)
	var c: Vector3 = _track.get_point_at(along)
	var right: Vector3 = _right_at(along)
	var pos: Vector3 = c + right * lat
	var gy: float = _ground(pos, c.y)
	if is_nan(gy) and kind != "crowd":
		# Beyond the sidewalk collider there is no ground collider (the ground mesh has none): take the racing line's
		# height when the sidewalk is there, 2 m nearer the road. Spectators need a real floor under them.
		var near: Vector3 = pos - right * signf(lat) * 2.0
		if not is_nan(_ground(near, c.y)):
			gy = c.y
	if is_nan(gy):
		rejected["ground"] = int(rejected.get("ground", 0)) + 1
		return false
	pos.y = gy
	var body: float = CROWD_BODY_M if kind == "crowd" else BODY_RADIUS_M
	if not _clear(pos, body):
		rejected["inside"] = int(rejected.get("inside", 0)) + 1
		return false
	var rec: Dictionary = {"kind": kind, "pos": pos, "s": along, "lateral": _track.get_lateral_offset(pos, along),
		"chunk": int(along / CHUNK_M), "face": -right * signf(lat)}
	rec.merge(extra)
	placements.append(rec)
	return true


func _right_at(s: float) -> Vector3:
	var fwd: Vector3 = _track.get_tangent_at(s)
	fwd.y = 0.0
	return fwd.normalized().cross(Vector3.UP)


## Ground height under pos when it sits on the racing line's grade and nothing roofs it, else NAN.
func _ground(pos: Vector3, ref_y: float) -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos + Vector3.DOWN * 2.0, WORLD_MASK)
	var hit: Dictionary = space.intersect_ray(down)
	if hit.is_empty():
		return NAN
	var y: float = (hit["position"] as Vector3).y
	if absf(y - ref_y) > GRADE_TOL_M:
		return NAN
	var roof := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * (y + 0.5), pos + Vector3.UP * (y + ROOF_CHECK_M),
		WORLD_MASK)
	if not space.intersect_ray(roof).is_empty():
		return NAN
	return y


## True when no static geometry (facade, balcony, wall, bollard) is within radius of the body height on the spot.
func _clear(pos: Vector3, radius: float) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var body := SphereShape3D.new()
	body.radius = radius
	for h: float in [0.6, 1.5]:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = body
		q.transform = Transform3D(Basis(), pos + Vector3.UP * h)
		q.collision_mask = WORLD_MASK
		if not space.intersect_shape(q, 1).is_empty():
			return false
	return true


## Basis with local +Z along dir (horizontal) and local +X along the road: the piece's front faces dir.
static func _facing(dir: Vector3) -> Basis:
	var z: Vector3 = dir.normalized()
	var x: Vector3 = Vector3.UP.cross(z).normalized()
	return Basis(x, Vector3.UP, z)


func _build_nodes() -> void:
	var groups: Dictionary = {}  # "kind|chunk" -> Array of placements
	for p: Dictionary in placements:
		var key: String = "%s|%d" % [p.kind, p.chunk]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(p)
	var inv: Transform3D = global_transform.affine_inverse()
	for key: String in groups:
		var parts: PackedStringArray = key.split("|")
		_build_group(parts[0], int(parts[1]), groups[key], inv)


func _build_group(kind: String, chunk: int, items: Array, inv: Transform3D) -> void:
	var lit: bool = TOD[_tod].lit
	var xf: Array[Transform3D] = []
	var tag: String = "%s_c%d" % [kind, chunk]
	if kind.begins_with("barrier"):
		for p: Dictionary in items:
			xf.append(Transform3D(_facing(p.face), p.pos))
		_add(tag, _kit_mesh("event_%s.glb" % kind, [_banner_material()]), xf, RANGE_BARRIER_M)
	elif kind == "crowd":
		var custom: Array[Color] = []
		for p: Dictionary in items:
			xf.append(Transform3D(_facing(p.face), p.pos + Vector3.UP * (CROWD_H_M * 0.5)))
			custom.append(Color(float(p.cell), float(p.hue), float(p.phase), 0.0))
		_add(tag, _quad_mesh(CROWD_W_M, CROWD_H_M, _crowd_material()), xf, RANGE_CROWD_M, custom)
	elif kind == "flag":
		for p: Dictionary in items:
			xf.append(Transform3D(_facing(p.face), p.pos))
		_add(tag, _kit_mesh("event_flag.glb", [_pole_material(), _flag_material()]), xf, RANGE_FLAG_M)
	elif kind == "cafe":
		_build_cafes(chunk, items, inv, lit)


func _build_cafes(chunk: int, items: Array, inv: Transform3D, lit: bool) -> void:
	var awning: Array[Transform3D] = []
	var sets: Array[Transform3D] = []
	var pools: Array[Transform3D] = []
	var bulbs: Array[Transform3D] = []
	var cable := PackedVector3Array()  # local space, joined into one line mesh per chunk
	for p: Dictionary in items:
		var frame := Transform3D(_facing(p.face), p.pos)
		awning.append(frame)
		for x: float in [-CAFE_TABLE_X_M, CAFE_TABLE_X_M]:
			sets.append(frame * Transform3D(Basis(), Vector3(x, 0.0, -0.1)))
		if not lit:
			continue
		var pool_basis: Basis = (frame.basis * Basis(Vector3.RIGHT, -PI * 0.5)).scaled(
			Vector3(POOL_SIZE_M.x, POOL_SIZE_M.y, 1.0))
		pools.append(Transform3D(pool_basis, p.pos + Vector3.UP * 0.03))
		var run: Array[Vector3] = _cable_run(frame)
		for world: Vector3 in run:
			bulbs.append(Transform3D(Basis(), world))
		for i: int in range(1, run.size()):
			cable.append(inv * run[i - 1])
			cable.append(inv * run[i])
	_add("cafe_awning_c%d" % chunk, _kit_mesh("event_awning.glb", [_awning_material()]), awning, RANGE_CAFE_M)
	_add("cafe_set_c%d" % chunk, _kit_mesh("event_cafe_set.glb", [_wood_material()]), sets, RANGE_CAFE_M)
	if not lit:
		return
	_add("cafe_pool_c%d" % chunk, _pool_quad(), pools, RANGE_CAFE_M)
	_add("cafe_bulb_c%d" % chunk, _bulb_sphere(), bulbs, RANGE_CAFE_M)
	if not cable.is_empty():
		_add_lines("cafe_cable_c%d" % chunk, cable)


## World points of the BULB_COUNT bulbs on the sagging cable in front of an awning with the given frame.
func _cable_run(frame: Transform3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i: int in BULB_COUNT:
		var t: float = float(i) / float(BULB_COUNT - 1)
		var x: float = lerpf(-CABLE_X_M, CABLE_X_M, t)
		var y: float = CABLE_Y_M - BULB_SAG_M * (1.0 - pow(2.0 * t - 1.0, 2.0))
		out.append(frame * Vector3(x, y, CABLE_Z_M))
	return out


## One MultiMeshInstance3D per kind and chunk. Each entry in xf is a piece's transform in world space; the node is
## a child of this node, so the transform goes through inv first.
func _add(node_name: String, mesh: Mesh, xf: Array, range_m: float, custom: Array[Color] = []) -> void:
	if xf.is_empty():
		return
	var inv: Transform3D = global_transform.affine_inverse()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = not custom.is_empty()
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i: int in xf.size():
		mm.set_instance_transform(i, inv * (xf[i] as Transform3D))
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, custom[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.visibility_range_begin = 0.0
	mmi.visibility_range_end = range_m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _add_lines(node_name: String, verts: PackedVector3Array) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh.surface_set_material(0, _cable_material())
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.visibility_range_begin = 0.0
	mi.visibility_range_end = RANGE_CAFE_M
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Mesh of a kit GLB (its first MeshInstance3D), with the given materials set per surface.
static func _kit_mesh(file: String, materials: Array) -> Mesh:
	var inst: Node = (load(KIT + file) as PackedScene).instantiate()
	var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mesh: ArrayMesh = (mi.mesh as ArrayMesh).duplicate() as ArrayMesh
	inst.free()
	for i: int in materials.size():
		mesh.surface_set_material(i, materials[i])
	return mesh


static func _quad_mesh(w: float, h: float, mat: Material) -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	q.material = mat
	return q


static func _pool_quad() -> Mesh:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(POOL_TEX) as Texture2D
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	return _quad_mesh(1.0, 1.0, m)


func _bulb_sphere() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.14
	s.radial_segments = 6
	s.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.1, 0.07, 0.05)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.72, 0.38)
	m.emission_energy_multiplier = float(TOD[_tod].bulb)
	s.material = m
	return s


func _banner_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(BANNER_TEX) as Texture2D
	m.roughness = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # kit winding is not reliable: two-sided, lit from the front
	m.metallic_specular = 0.6
	return m


func _crowd_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CROWD_SHADER
	m.set_shader_parameter("crowd_atlas", load(CROWD_TEX))
	m.set_shader_parameter("tone", TOD[_tod].tone)
	return m


func _pole_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.22, 0.22, 0.24)
	m.roughness = 0.5
	m.metallic = 0.6
	return m


func _flag_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FLAG_SHADER
	m.set_shader_parameter("flag_tex", load(FLAG_TEX))
	return m


func _awning_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(ATLAS_TEX) as Texture2D
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glow: float = TOD[_tod].glow
	m.emission_enabled = glow > 0.0
	m.emission = Color(1.0, 0.7, 0.4)
	m.emission_texture = load(GLOW_TEX) as Texture2D
	m.emission_energy_multiplier = glow
	return m


func _wood_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(ATLAS_TEX) as Texture2D
	m.roughness = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _cable_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.04, 0.04, 0.05)
	return m
