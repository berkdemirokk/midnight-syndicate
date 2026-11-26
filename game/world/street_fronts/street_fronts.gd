class_name StreetFronts
extends Node3D
## Licensed shop houses and mansions (CC BY 4.0, vinish.dev, credit lines in game/ui/credits_third_party.txt) on the land
## side of the Bogaz track, in the first MAX_S_M metres of the lap. Each first-row kit building there is replaced by a row
## of these models on the same front line, width, yaw and ground height: the kit's LOD0 and LOD1 are hidden, its collider
## and occluder stay. The models face the street (-Z in their own frame, the kit's front is +Z) and stand behind the
## front line, so nothing comes into the race corridor. Far LOD2 impostors of the kit stay (they only show beyond 180 m).
## setup(track, time_of_day_id) builds everything once; the race scene calls it when this file exists.
## Night: lit windows (street_glass.gdshader), a warm pavement pool in front of each shop, and at most LIGHT_COUNT real
## OmniLights at the shops nearest the start grid. Day and sunset: no lights.

const DIR: String = "res://assets/world/kits/street_fronts/"
const LAYOUT: String = "res://assets/world/istanbul_bogaz/istanbul_bogaz_layout.json"
const GLASS_SHADER: Shader = preload("res://world/street_fronts/street_glass.gdshader")
const POOL_SHADER: Shader = preload("res://shaders/glow_pool.gdshader")
const SHOPS: PackedStringArray = ["cafe-front", "bookshop", "barber-shop", "florist", "pharmacy", "corner-shop"]
const MANSIONS: PackedStringArray = ["town-mansion", "italianate-mansion", "second-empire-mansion"]
const LAND_SIDE: String = "right"  ## the layout side with the land; the sea, the mosque and the quay are on "left"
const MAX_S_M: float = 900.0
const MATCH_M: float = 3.0  ## a kit root this close to its layout position is that building (corridor pushes move it a little)
const LOD0_END_M: float = 15.0  ## LOD0 to 15 m (spec 55 m): the street and gameplay shots stay within +25k primitives of base
const LOD1_END_M: float = 180.0  ## the kit LOD2 impostor shows from 180 m: the new LOD1 must end where it starts
const FADE_M: float = 4.0
const MIRROR_LAYER: int = 1 << 3  ## drawn by the wet-road mirror only
const NO_MIRROR_LAYER: int = 1 << 4  ## kept out of the wet-road mirror
const SLOT_M: float = 6.0  ## a shop takes about this much frontage
const CORRIDOR_CLEAR_M: float = 7.3  ## the kerbs are at 7 m: the models stay this far from the centre line
const FIT_TOL: float = 0.08  ## models may be scaled along their width by this much to close a gap
const MANSION_CHANCE: float = 0.08  ## a mansion costs about 3x a shop in triangles (its LOD1 does not decimate below ~2.4k)
const MANSION_MIN_WIDTH_M: float = 14.0
const LIGHT_COUNT: int = 6
const LIGHT_RANGE_M: float = 9.0
const LIGHT_ENERGY: float = 1.2
const WARM: Color = Color(1.0, 0.66, 0.36)
const POOL_RADIUS_M: float = 2.2
const POOL_FRONT_M: float = 1.8  ## the pool centre this far in front of the shop front
const POOL_STRENGTH: float = 0.7
const LIGHT_HEIGHT_M: float = 3.2
const LIGHT_OUT_M: float = 1.2

var _tod: String = "day"
var _info: Dictionary = {}  ## asset id -> meta dictionary (width_m, depth_m, ...)
var _lods: Dictionary = {}  ## asset id -> [lod0 Mesh, lod1 Mesh]
var _flat: StandardMaterial3D = null
var _glass: ShaderMaterial = null
var _pool_mat: ShaderMaterial = null
var _pools: MultiMeshInstance3D = null
var _lights: Array[OmniLight3D] = []
var _shop_fronts: Array[Transform3D] = []  ## world transform of every placed shop (origin on its front line)
var _buildings: Array[Node3D] = []  ## placed buildings, for the tests
var _replaced: Array[Node3D] = []  ## kit roots whose LOD0 and LOD1 were hidden
var _kept: int = 0  ## kit frontages kept because the models would have reached the race corridor


func setup(track: Track, time_of_day_id: String) -> void:
	_tod = time_of_day_id
	_load_library()
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var kit: Array[Node3D] = _kit_roots(track)
	var fronts := Node3D.new()
	fronts.name = "Fronts"
	add_child(fronts)
	for v: Variant in layout["instances"]:
		var d: Dictionary = v
		if String(d["kind"]) != "building" or String(d["side"]) != LAND_SIDE or float(d["s_offset_m"]) >= MAX_S_M:
			continue
		var root: Node3D = _nearest_root(kit, String(d["asset"]), _vec(d["position"]))
		if root == null:
			push_warning("StreetFronts: no kit building for %s at s=%.1f" % [d["asset"], float(d["s_offset_m"])])
			continue
		_replace(track, root, d, fronts)
	if _tod == "night":
		_add_pools()
		_add_lights(layout)
	_apply_time()


## 0 day, sunset, night: the glass look, the pools and the lights follow the time of day.
func _apply_time() -> void:
	var night: bool = _tod == "night"
	if _glass != null:
		_glass.set_shader_parameter("night", 1.0 if night else 0.0)
		_glass.set_shader_parameter("sunset", 1.0 if _tod == "sunset" else 0.0)
	if _pools != null:
		_pools.visible = night
	for l: OmniLight3D in _lights:
		l.visible = night


## Kit building roots: the children of every FirstRow node of the track (city_builder names them asset_NNN).
func _kit_roots(track: Track) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for rows: Node in track.find_children("FirstRow", "Node3D", true, false):
		for c: Node in rows.get_children():
			if c is Node3D:
				out.append(c as Node3D)
	return out


func _nearest_root(kit: Array[Node3D], asset: String, at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d: float = MATCH_M
	for root: Node3D in kit:
		if not root.name.begins_with(asset + "_"):
			continue
		var dist: float = root.global_position.distance_to(at)
		if dist < best_d:
			best_d = dist
			best = root
	return best


## Hides the kit's LOD0 and LOD1 (its collider and occluder stay) and fills the frontage with the models.
## A frontage whose models would reach into the race corridor (a curve turns its ends towards the road) keeps its kit building.
func _replace(track: Track, root: Node3D, d: Dictionary, parent: Node3D) -> void:
	var width: float = float(d["width_m"])
	var seed_value: int = int(round(float(d["s_offset_m"]) * 10.0)) * 31 + int(root.global_position.x * 7.0)
	var slots: Array[Dictionary] = _fill(width, seed_value)
	for slot: Dictionary in slots:
		if not _clear_of_road(track, root.global_transform, slot):
			_kept += 1
			return
	for mi: Node in root.find_children("LOD0", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = false
	for mi: Node in root.find_children("LOD1", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = false
	_replaced.append(root)
	for slot: Dictionary in slots:
		_place(root.global_transform, slot, parent)


## True when the four corners of a slot's footprint are at least CORRIDOR_CLEAR_M from the centre line on the land side.
func _clear_of_road(track: Track, root_xf: Transform3D, slot: Dictionary) -> bool:
	## Model corners in the kit's frame: the model is turned by PI about Y and scaled by sx along its width, so its
	## front wall (model z 0) is kit z 0 and its body runs to kit -Z.
	var id: String = slot["id"]
	var sx: float = float(slot["sx"])
	var half: float = float(_info[id]["width_m"]) / 2.0
	var x: float = float(slot["x"])
	var depth: float = float(_info[id]["depth_m"])
	for p: Vector3 in [Vector3(x - half * sx, 0.15, 0.0), Vector3(x + half * sx, 0.15, 0.0),
			Vector3(x - half * sx, 0.15, -depth), Vector3(x + half * sx, 0.15, -depth)]:
		if absf(track.get_lateral_offset(root_xf * p)) < CORRIDOR_CLEAR_M:
			return false
	return true


## The slots of one frontage, from -width / 2 to +width / 2 along the front line. Either one mansion that fits the width
## within FIT_TOL, or a row of shop houses sized to the frontage. Seeded, so the same frontage always gets the same row.
func _fill(width: float, seed_value: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array[Dictionary] = []
	if width >= MANSION_MIN_WIDTH_M and rng.randf() < MANSION_CHANCE:
		var first: int = rng.randi() % MANSIONS.size()
		for k: int in MANSIONS.size():
			var id: String = MANSIONS[(first + k) % MANSIONS.size()]
			var sx: float = width / float(_info[id]["width_m"])
			if absf(sx - 1.0) <= FIT_TOL:
				out.append({"id": id, "x": 0.0, "sx": sx})
				return out
	var n: int = maxi(1, roundi(width / SLOT_M))
	var seg: float = width / float(n)
	for i: int in n:
		var fits: Array[String] = []
		for id: String in SHOPS:
			if absf(seg / float(_info[id]["width_m"]) - 1.0) <= FIT_TOL:
				fits.append(id)
		var pick: String = fits[rng.randi() % fits.size()] if not fits.is_empty() else SHOPS[rng.randi() % SHOPS.size()]
		var sx2: float = clampf(seg / float(_info[pick]["width_m"]), 1.0 - FIT_TOL, 1.0 + FIT_TOL)
		out.append({"id": pick, "x": -width / 2.0 + seg * (float(i) + 0.5), "sx": sx2})
	return out


## One building: a Node3D at the front line with LOD0 (near, shadows), LOD1 (far) and the mirror-only copy (cheap, drawn by the mirror to LOD1_END_M).
## The model's front is -Z, so it is turned by PI about Y, and its origin is the middle of the front wall.
func _place(root_xf: Transform3D, slot: Dictionary, parent: Node3D) -> void:
	var id: String = slot["id"]
	var sx: float = float(slot["sx"])
	var local := Transform3D(Basis(Vector3.UP, PI) * Basis.from_scale(Vector3(sx, 1.0, 1.0)),
			Vector3(float(slot["x"]), 0.0, 0.0))
	var node := Node3D.new()
	node.name = "Front_%s_%03d" % [id, _buildings.size()]  ## unique: Godot renames a duplicate name to @Node3D@N
	node.set_meta("asset", id)
	parent.add_child(node)
	node.global_transform = root_xf * local
	var lod0 := MeshInstance3D.new()
	lod0.name = "LOD0"
	lod0.mesh = _lods[id][0]
	lod0.layers = (lod0.layers & ~1) | NO_MIRROR_LAYER
	lod0.visibility_range_begin = 0.0
	lod0.visibility_range_end = LOD0_END_M
	lod0.visibility_range_end_margin = FADE_M
	lod0.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	lod0.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(lod0)
	var lod1 := MeshInstance3D.new()
	lod1.name = "LOD1"
	lod1.mesh = _lods[id][1]
	lod1.layers = (lod1.layers & ~1) | NO_MIRROR_LAYER  ## the mirror gets the cheap copy below instead (LOD1 there cost 2x)
	lod1.visibility_range_begin = LOD0_END_M
	lod1.visibility_range_begin_margin = FADE_M
	lod1.visibility_range_end = LOD1_END_M
	lod1.visibility_range_end_margin = FADE_M
	lod1.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	lod1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(lod1)
	var mirror := MeshInstance3D.new()
	mirror.name = "MirrorLOD1"
	mirror.mesh = _lods[id][2]
	mirror.layers = MIRROR_LAYER
	mirror.visibility_range_begin = 0.0
	mirror.visibility_range_end = LOD1_END_M
	mirror.visibility_range_end_margin = FADE_M
	mirror.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mirror.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mirror)
	_buildings.append(node)
	if id in SHOPS:
		_shop_fronts.append(node.global_transform)


## Meshes are shared by every building of one asset: one ArrayMesh per asset and LOD (LOD0, LOD1, mirror copy), its surfaces
## styled by material name.
func _load_library() -> void:
	_flat = StandardMaterial3D.new()
	_flat.resource_name = "M_Flat"
	_flat.vertex_color_use_as_albedo = true
	_flat.roughness = 0.8
	_glass = ShaderMaterial.new()
	_glass.resource_name = "M_Glass"
	_glass.shader = GLASS_SHADER
	_glass.set_shader_parameter("lit_night", 0.55)
	_glass.set_shader_parameter("lit_sunset", 0.35)
	_pool_mat = ShaderMaterial.new()
	_pool_mat.shader = POOL_SHADER
	_pool_mat.set_shader_parameter("tint", WARM)
	_pool_mat.set_shader_parameter("strength", POOL_STRENGTH)
	_pool_mat.set_shader_parameter("radius_m", POOL_RADIUS_M)
	for id: String in SHOPS + MANSIONS:
		if _lods.has(id):
			continue
		_info[id] = JSON.parse_string(FileAccess.get_file_as_string(DIR + id + ".json"))
		var pair: Array[Mesh] = []
		for file: String in ["%s_lod0.glb" % id, "%s_lod1.glb" % id, "%s_mirror.glb" % id]:
			var scene: PackedScene = load(DIR + file) as PackedScene
			var inst: Node = scene.instantiate()
			var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
			var mesh: ArrayMesh = mi.mesh as ArrayMesh
			for s: int in mesh.get_surface_count():
				_style_surface(mesh, s, id)
			pair.append(mesh)
			inst.free()
		_lods[id] = pair


func _style_surface(mesh: ArrayMesh, s: int, id: String) -> void:
	var src: Material = mesh.surface_get_material(s)
	var surface: String = src.resource_name if src != null else ""
	if surface == "M_Flat":
		mesh.surface_set_material(s, _flat)
	elif surface == "M_Glass":
		mesh.surface_set_material(s, _glass)
	elif surface.begins_with("T_") and src is StandardMaterial3D:
		(src as StandardMaterial3D).vertex_color_use_as_albedo = true
	else:
		push_error("StreetFronts: unknown surface '%s' in %s" % [surface, id])


## Night only: one warm pool of light on the pavement in front of every shop, as one MultiMesh (one draw call).
func _add_pools() -> void:
	if _shop_fronts.is_empty():
		return
	var quad := PlaneMesh.new()
	quad.size = Vector2(POOL_RADIUS_M * 2.0, POOL_RADIUS_M * 2.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = _shop_fronts.size()
	for i: int in _shop_fronts.size():
		var xf: Transform3D = _shop_fronts[i]
		var at: Vector3 = to_local(xf * Vector3(0.0, 0.0, -POOL_FRONT_M))
		at.y = 0.03
		mm.set_instance_transform(i, Transform3D(Basis(), at))
	_pools = MultiMeshInstance3D.new()
	_pools.name = "ShopPools"
	_pools.multimesh = mm
	_pools.material_override = _pool_mat
	_pools.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pools)


## Night only: the LIGHT_COUNT shops nearest the start grid get one warm OmniLight above their shop front.
func _add_lights(layout: Dictionary) -> void:
	var grid: Array = layout["racing"]["grid_slots"]
	var centre := Vector3.ZERO
	for v: Variant in grid:
		centre += _vec((v as Dictionary)["pos"])
	centre /= maxf(1.0, float(grid.size()))
	var order: Array[Transform3D] = _shop_fronts.duplicate()
	order.sort_custom(func(a: Transform3D, b: Transform3D) -> bool:
		return a.origin.distance_squared_to(centre) < b.origin.distance_squared_to(centre))
	for i: int in mini(LIGHT_COUNT, order.size()):
		var xf: Transform3D = order[i]
		var l := OmniLight3D.new()
		l.name = "ShopLight%d" % i
		l.light_color = WARM
		l.omni_range = LIGHT_RANGE_M
		l.light_energy = LIGHT_ENERGY
		l.shadow_enabled = false
		add_child(l)
		l.position = to_local(xf * Vector3(0.0, LIGHT_HEIGHT_M, -LIGHT_OUT_M))
		_lights.append(l)


static func _vec(v: Variant) -> Vector3:
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
