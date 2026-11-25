class_name CityBuilder
extends Track
## City 01 track root (Track contract). On _ready it assembles the circuit from city_01_layout.json:
## road, first-row buildings (LOD children switched by visibility range), second-row LOD2 MultiMeshes,
## props as MultiMeshes per chunk with merged colliders, lights (budgeted), reflection probes, the
## environment, racing line, start grid and checkpoints. The JSON is the source of truth; nothing is cached.
## Build notes and numbers: docs/design/CITY_01_ENGINE.md.

const LAYOUT_PATH: String = "res://assets/world/city_01/city_01_layout.json"
const ROAD_GLB: String = "res://assets/world/city_01/city_01_road.glb"
const BUILDING_DIR: String = "res://assets/world/kits/buildings/"
const PROP_DIR: String = "res://assets/world/kits/props/"
const CATALOG_PATH: String = "res://assets/world/kits/buildings/catalog.json"
const VEHICLE_LAYER_BIT: int = 1 << 1
const TRIGGER_LAYER_BIT: int = 1 << 2
const CHECKPOINT_HEIGHT_M: float = 6.0
const CHECKPOINT_DEPTH_M: float = 1.5
const ACCENT_SPOT_ANGLE_DEG: float = 35.0
const GRID_REST_M: float = 0.47  ## car origin height above the road, as in the vehicle tests
const FALL_FLOOR_Y_M: float = -30.0
const FALL_FLOOR_SIZE_M: float = 6000.0
const CENTRE_PATH: String = "res://assets/world/city_01/city_01_centerline.json"
const CORRIDOR_MARGIN_M: float = 0.5  ## corridor = kerb line + this, per centreline sample
const CORRIDOR_SEARCH: int = 40  ## centreline samples either side of a building's lap offset searched for its nearest sample
const CORRIDOR_NEAR_M: float = 12.0  ## footprint points further than this from every sample are not in the corridor
const PUSH_STEP_M: float = 0.25
const PUSH_MAX_M: float = 40.0

@export var lod0_end_m: float = 70.0  ## first-row building LOD0 up to here, LOD1 to lod1_end_m, LOD2 beyond
@export var lod1_end_m: float = 180.0
@export var lod_fade_m: float = 4.0  ## dithered cross-fade band on every LOD and category switch
@export var prop_lod1_begin_m: float = 60.0  ## props with a _lod1 file switch to it here
@export var prop_furniture_end_m: float = 90.0  ## small street furniture
@export var prop_far_end_m: float = 250.0  ## circuit, lamps, signs, overhead; bay backdrop is unlimited (0)
@export var sign_gap_m: float = 0.4  ## minimum free space between two signs on a facade
@export var sign_overlap_height_m: float = 1.5  ## signs further apart vertically never collide
@export var chunk_m: float = 120.0  ## road chunk length for prop MultiMeshes, merged colliders and light budget
@export var light_energy_scale: float = 0.6  ## layout energies are Blender-scale; tuned in the capture
## Street lamp spot energy multiplier per district. Waterfront and market lamps had no visible pool at 0.6 x 14.
@export var lamp_district_scale: Dictionary = {"neon": 1.0, "downtown": 4.0, "waterfront": 8.0, "market": 4.0, "underpass": 1.0}
@export var fog_begin_m: float = 220.0  ## depth fog starts here: city blocks stay crisp, the bay backdrop fades
@export var fog_end_m: float = 1200.0
@export var lamp_range_m: float = 18.0  ## was 22: a street lamp only has to reach the road below it; shorter range touches fewer volumes
@export var neon_fill_range_m: float = 8.0  ## was 12 to 14: the omni fills used up the 8-per-mesh budget on the overpass
@export var lamp_merge_m: float = 3.0  ## lamp heads closer than this are one double lamp: one spot is kept
@export_range(0.0, 8.0) var tunnel_light_energy_scale: float = 2.0  ## underpass ceiling omnis: walls and road get a pool every 12 m
@export_range(0.0, 8.0) var string_light_energy_scale: float = 3.0  ## market string lights: warm dapple on the street under them
@export var lamp_spot_angle_deg: float = 55.0  ## wide cone for street lamp heads
@export var light_fade_begin_m: float = 70.0
@export var light_fade_length_m: float = 30.0
@export var occluder_shrink: float = 0.9  ## occluder box as a fraction of the collider box
@export var probe_max_distance_m: float = 160.0
@export var flip_signs: bool = false  ## turn sign props 180 degrees if their text reads mirrored in a capture
@export var ambient_color: Color = Color("#1E2740")  ## night fill for unlit walls; was #1B2B4D, walls read black
@export_range(0.0, 4.0) var ambient_energy: float = 1.2  ## was 0.6: facades away from lamps were black slabs

var stats: Dictionary = {}  ## counts recorded for the tests and the engine report
var light_report: Dictionary = {}  ## CityLights.budget summary (counts, log lines)
var light_volumes: Array = []  ## AABBs the light budget was checked against (tests recount with them)
var load_time_ms: float = 0.0

var _geo: Node3D
var _lighting: Node3D
var _checkpoints: Node3D
var _grid_root: Node3D
var _packed: Dictionary = {}  ## res path -> PackedScene
var _proto: Dictionary = {}  ## "path|owner" -> {meshes: Array, shapes: Array}
var _bodies: Dictionary = {}  ## chunk index -> merged StaticBody3D of props with colliders
var _c_pos: PackedVector2Array = PackedVector2Array()  ## centreline samples (x, z), 2 m apart
var _c_right: PackedVector2Array = PackedVector2Array()  ## unit right vector per sample (x, z)
var _c_half: PackedFloat32Array = PackedFloat32Array()  ## corridor half width per sample: kerb + margin
var _c_spacing: float = 2.0


func _ready() -> void:
	var t0: int = Time.get_ticks_usec()
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if not layout is Dictionary:
		push_error("CityBuilder: cannot parse " + LAYOUT_PATH)
		return
	var d: Dictionary = layout
	_geo = get_node("Geometry") as Node3D
	_lighting = get_node("Lighting") as Node3D
	_checkpoints = get_node("Checkpoints") as Node3D
	_grid_root = get_node("StartGrid") as Node3D
	var racing: Dictionary = d["racing"]
	var lap: float = float(d["lap_length"])
	stats ={"first_row": 0, "second_row_instances": 0, "second_row_multimeshes": 0, "prop_instances": 0,
		"prop_multimeshes": 0, "prop_colliders": 0, "missing_props": 0, "occluders": 0, "lights": 0,
		"lights_dropped": 0, "probes": 0, "road_surfaces": 0, "road_colliders": 0, "corridor_pushes": []}
	_build_racing_line(racing["racing_line"])
	_build_line()  # Track: samples the line and the speed profile
	_build_start_grid(racing["grid_slots"])
	_build_grid()  # Track: collects Grid0..Grid7
	_build_checkpoints(racing["start_line"], racing["gates"])
	var n_chunks: int = maxi(1, ceili(lap / chunk_m))
	var inst: Array = d["instances"]
	_build_road()
	_load_corridor()
	_build_buildings(inst, lap)
	_build_props(inst, lap, n_chunks)
	_build_lights(d["lights"])
	_build_probes(d["reflection_probes"])
	_build_environment()
	load_time_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	stats["load_time_ms"] = load_time_ms


# --- racing line, grid, checkpoints ---------------------------------------------------------

func _build_racing_line(raw: Array) -> void:
	var path: Path3D = get_node("RacingLine") as Path3D
	var p: PackedVector3Array = PackedVector3Array()
	for v: Variant in raw:
		p.append(_vec(v))
	if p.size() > 1 and p[0].distance_to(p[p.size() - 1]) < 0.01:
		p.resize(p.size() - 1)  # the closed curve repeats the first point itself
	var n: int = p.size()
	var curve := Curve3D.new()
	for i: int in n + 1:
		var c: int = i % n
		var h: Vector3 = (p[(c + 1) % n] - p[(c - 1 + n) % n]) / 6.0  # Catmull-Rom handles for 4 m spacing
		curve.add_point(p[c], -h, h)
	path.curve = curve


func _build_start_grid(slots: Array) -> void:
	for i: int in slots.size():
		var pos: Vector3 = _vec((slots[i] as Dictionary)["pos"])
		var t: Vector3 = get_tangent_at(get_progress(pos))
		var m := Marker3D.new()
		m.name = "Grid%d" % i
		# RaceManager spawns cars at the marker origin: the origin is the car rest height above the road.
		m.transform = Transform3D(Basis.looking_at(Vector3(t.x, 0.0, t.z), Vector3.UP), pos + Vector3.UP * GRID_REST_M)
		_grid_root.add_child(m)


func _build_checkpoints(start: Dictionary, gates: Array) -> void:
	var entries: Array = [start]
	entries.append_array(gates)
	for i: int in entries.size():
		var e: Dictionary = entries[i]
		var t: Vector3 = _vec(e["tangent"])
		var area := Area3D.new()
		area.name = "CP%d" % i
		area.collision_layer = TRIGGER_LAYER_BIT
		area.collision_mask = VEHICLE_LAYER_BIT
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, CHECKPOINT_HEIGHT_M, CHECKPOINT_DEPTH_M)
		shape.shape = box
		area.add_child(shape)
		area.transform = Transform3D(Basis.looking_at(Vector3(t.x, 0.0, t.z), Vector3.UP),
			_vec(e["pos"]) + Vector3.UP * CHECKPOINT_HEIGHT_M * 0.5)
		_checkpoints.add_child(area)


# --- road and buildings ---------------------------------------------------------------------

func _build_road() -> void:
	var road: Node3D = _scene(ROAD_GLB).instantiate() as Node3D
	road.name = "Road"
	stats["road_surfaces"] = MaterialLibrary.apply(road)
	# The "ground" plane collider sits at about -0.3 m, above the underpass approach where the road drops below it,
	# so cars stepped off it. The road and sidewalk colliders cover the drivable surface; the ground mesh stays.
	var ground: Node = road.get_node_or_null("ground")
	var removed: int = 0
	if ground != null:
		for c: Node in ground.get_children():
			if c is StaticBody3D:
				ground.remove_child(c)
				c.free()
				removed += 1
	stats["ground_colliders_removed"] = removed
	var colliders: int = 0
	for n: Node in _all_nodes(road):
		if n is StaticBody3D:
			colliders += 1
	stats["road_colliders"] = colliders
	_geo.add_child(road)
	_add_fall_floor()


## Catch plane far below the circuit so a car that leaves the walls falls onto something instead of forever.
func _add_fall_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "FallFloor"
	body.position = Vector3(0.0, FALL_FLOOR_Y_M, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FALL_FLOOR_SIZE_M, 1.0, FALL_FLOOR_SIZE_M)
	shape.shape = box
	body.add_child(shape)
	_geo.add_child(body)


func _build_buildings(inst: Array, lap: float) -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var colliders: Dictionary = {}
	for b: Variant in catalog["buildings"]:
		var bd: Dictionary = b
		var c: Dictionary = bd["collider"]
		colliders[String(bd["id"])] = {"size": _vec(c["size"]), "center": _vec(c["center"])}
	var first := Node3D.new()
	first.name = "FirstRow"
	var second := Node3D.new()
	second.name = "SecondRow"
	_geo.add_child(first)
	_geo.add_child(second)
	var lod2_xfs: Dictionary = {}  # asset -> Array of building transforms
	for v: Variant in inst:
		var d: Dictionary = v
		var kind: String = String(d["kind"])
		var asset: String = String(d["asset"])
		var xf := Transform3D(Basis(Vector3.UP, float(d["yaw"])), _vec(d["position"]))
		if kind == "building" and colliders.has(asset):
			xf = _clear_corridor(xf, asset, float(d.get("s_offset_m", 0.0)), lap, colliders[asset])
		if kind == "building_lod2_only":
			if not lod2_xfs.has(asset):
				lod2_xfs[asset] = []
			(lod2_xfs[asset] as Array).append(xf)
			continue
		if kind != "building":
			continue
		var root: Node3D = _scene(BUILDING_DIR + asset + ".glb").instantiate() as Node3D
		root.name = "%s_%03d" % [asset, int(stats["first_row"])]
		root.transform = xf
		MaterialLibrary.apply(root, asset)
		_set_lod_ranges(root)
		if colliders.has(asset):
			_add_occluder(root, colliders[asset])
		first.add_child(root)
		stats["first_row"] = int(stats["first_row"]) + 1
	for asset: String in lod2_xfs.keys():
		var arr: Array = lod2_xfs[asset]
		var lod2: Dictionary = _find_mesh(_prototype(BUILDING_DIR + asset + ".glb", asset), "LOD2")
		if lod2.is_empty():
			push_warning("CityBuilder: no LOD2 in " + asset)
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = lod2["mesh"]
		mm.instance_count = arr.size()
		var rel: Transform3D = lod2["xf"]
		for i: int in arr.size():
			mm.set_instance_transform(i, (arr[i] as Transform3D) * rel)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = asset + "_LOD2"
		mmi.multimesh = mm
		second.add_child(mmi)
		stats["second_row_multimeshes"] = int(stats["second_row_multimeshes"]) + 1
		stats["second_row_instances"] = int(stats["second_row_instances"]) + arr.size()


## LOD children of a building: LOD0 to lod0_end_m, LOD1 to lod1_end_m, LOD2 beyond, cross-faded.
func _set_lod_ranges(n: Node) -> void:
	if n is MeshInstance3D and String(n.name) in ["LOD0", "LOD1", "LOD2"]:
		var mi := n as MeshInstance3D
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		match String(n.name):
			"LOD0":
				mi.visibility_range_begin = 0.0
				mi.visibility_range_begin_margin = 0.0
				mi.visibility_range_end = lod0_end_m
				mi.visibility_range_end_margin = lod_fade_m
			"LOD1":
				mi.visibility_range_begin = lod0_end_m
				mi.visibility_range_begin_margin = lod_fade_m
				mi.visibility_range_end = lod1_end_m
				mi.visibility_range_end_margin = lod_fade_m
			_:
				mi.visibility_range_begin = lod1_end_m
				mi.visibility_range_begin_margin = lod_fade_m
				mi.visibility_range_end = 0.0
				mi.visibility_range_end_margin = 0.0
	for c: Node in n.get_children():
		_set_lod_ranges(c)


## Reads the centreline file: per sample position, right vector and corridor half width (kerb line + margin).
func _load_corridor() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CENTRE_PATH))
	if not data is Dictionary:
		push_error("CityBuilder: cannot parse " + CENTRE_PATH)
		return
	var samples: Array = (data as Dictionary)["samples"]
	var edges: Array = (data as Dictionary)["edges"]
	_c_spacing = float((data as Dictionary)["lap_length"]) / float(samples.size())
	for i: int in samples.size():
		var s: Dictionary = samples[i]
		var e: Dictionary = edges[i]
		var p: Vector3 = _vec(s["pos"])
		var r: Vector3 = _vec(s["right"])
		var lk: Vector3 = _vec(e["left_kerb"]) - p
		var rk: Vector3 = _vec(e["right_kerb"]) - p
		_c_pos.append(Vector2(p.x, p.z))
		_c_right.append(Vector2(r.x, r.z).normalized())
		_c_half.append(maxf(Vector2(lk.x, lk.z).length(), Vector2(rk.x, rk.z).length()) + CORRIDOR_MARGIN_M)


## Signed margin of point q (x, z) inside the corridor: positive = inside kerb line + margin.
## Points further than CORRIDOR_NEAR_M from the centreline are reported as -INF (not in the corridor).
func _corridor_margin(q: Vector2, hint: int) -> float:
	var n: int = _c_pos.size()
	var best_d2: float = INF
	var best: int = -1
	for k: int in range(-CORRIDOR_SEARCH, CORRIDOR_SEARCH + 1):
		var i: int = posmod(hint + k, n)
		var d2: float = q.distance_squared_to(_c_pos[i])
		if d2 < best_d2:
			best_d2 = d2
			best = i
	if best < 0 or best_d2 > CORRIDOR_NEAR_M * CORRIDOR_NEAR_M:
		return -INF
	var lat: float = (q - _c_pos[best]).dot(_c_right[best])
	return _c_half[best] - absf(lat)


## Largest corridor margin over the footprint boundary (0.5 m steps): above 0 means the footprint enters the corridor.
func _footprint_margin(xf: Transform3D, centre: Vector3, size: Vector3, hint: int) -> float:
	var worst: float = -INF
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var corners: Array[Vector2] = []
	for c: Vector3 in [Vector3(-hx, 0.0, -hz), Vector3(hx, 0.0, -hz), Vector3(hx, 0.0, hz), Vector3(-hx, 0.0, hz)]:
		var w: Vector3 = xf * (centre + c)
		corners.append(Vector2(w.x, w.z))
	for k: int in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var steps: int = maxi(1, ceili(a.distance_to(b) / 0.5))
		for j: int in steps + 1:
			worst = maxf(worst, _corridor_margin(a.lerp(b, float(j) / float(steps)), hint))
	return worst


## Pushes a first-row building straight back along its facing normal until its footprint clears the corridor.
## Every correction is logged in stats["corridor_pushes"] and printed.
func _clear_corridor(xf: Transform3D, asset: String, s: float, lap: float, c: Dictionary) -> Transform3D:
	if _c_pos.is_empty():
		return xf
	var hint: int = roundi(fposmod(s, lap) / _c_spacing)
	var centre: Vector3 = c["center"]
	var size: Vector3 = c["size"]
	if _footprint_margin(xf, centre, size, hint) <= 0.0:
		return xf
	var ci: int = hint % _c_pos.size()
	var front: Vector3 = xf.basis.z.normalized()
	var front2: Vector2 = Vector2(front.x, front.z)
	var world_c: Vector3 = xf * centre
	var lat_c: float = (Vector2(world_c.x, world_c.z) - _c_pos[ci]).dot(_c_right[ci])
	# Away from the road: the push must increase the lateral offset of the building centre.
	var sign_dir: float = signf(lat_c) * signf(front2.dot(_c_right[ci]))
	if sign_dir == 0.0:
		sign_dir = 1.0
	var dir: Vector3 = front * sign_dir
	var moved: float = 0.0
	var out: Transform3D = xf
	while moved < PUSH_MAX_M and _footprint_margin(out, centre, size, hint) > 0.0:
		moved += PUSH_STEP_M
		out.origin = xf.origin + dir * moved
	var log_line: String = "CityBuilder: corridor push %s s=%.1f by %.2f m (%s)" % [asset, s, moved, "clear" if moved < PUSH_MAX_M else "NOT CLEAR"]
	print(log_line)
	(stats["corridor_pushes"] as Array).append({"asset": asset, "s": s, "push_m": moved, "position": out.origin})
	return out


## One box per first-row building, inside its collider box. Blocks the view of the buildings behind it.
func _add_occluder(root: Node3D, c: Dictionary) -> void:
	var occ := OccluderInstance3D.new()
	occ.name = "Occluder"
	var box := BoxOccluder3D.new()
	box.size = (c["size"] as Vector3) * occluder_shrink
	occ.occluder = box
	occ.position = c["center"]
	root.add_child(occ)
	stats["occluders"] = int(stats["occluders"]) + 1


# --- props ----------------------------------------------------------------------------------

func _build_props(inst: Array, lap: float, n_chunks: int) -> void:
	var props := Node3D.new()
	props.name = "Props"
	_geo.add_child(props)
	var buckets: Dictionary = {}
	var kept_signs: Array[Dictionary] = []
	for v: Variant in inst:
		var d: Dictionary = v
		if String(d["kind"]) != "prop":
			continue
		if String(d.get("category", "")) == "sign" and _sign_overlaps(d, kept_signs):
			# The layout put two signs on neighbouring anchors that are closer than the signs are wide.
			stats["signs_dropped_overlap"] = int(stats.get("signs_dropped_overlap", 0)) + 1
			continue
		var file: String = String(d["file"]).get_file()
		if not ResourceLoader.exists(PROP_DIR + file):
			stats["missing_props"] = int(stats["missing_props"]) + 1
			push_warning("CityBuilder: missing prop " + file)
			continue
		var cat: String = String(d.get("category", "circuit"))
		var xf := Transform3D(Basis(Vector3.UP, float(d["yaw"])), _vec(d["position"]))
		if flip_signs and cat == "sign":
			xf = xf * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		var chunk: int = _chunk_of(float(d.get("s_offset_m", 0.0)), lap, n_chunks)
		var key: String = "%s|%d|%s" % [file, chunk, cat]
		if not buckets.has(key):
			buckets[key] = {"file": file, "chunk": chunk, "cat": cat, "xfs": []}
		(buckets[key]["xfs"] as Array).append(xf)
		stats["prop_instances"] = int(stats["prop_instances"]) + 1
	for key: String in buckets.keys():
		var b: Dictionary = buckets[key]
		var path: String = PROP_DIR + String(b["file"])
		var xfs: Array = b["xfs"]
		var end_m: float = prop_far_end_m
		if String(b["cat"]) == "furniture":
			end_m = prop_furniture_end_m
		elif String(b["cat"]) == "bay":
			end_m = 0.0
		var near: Dictionary = _prototype(path, "")
		var lod1_path: String = path.replace(".glb", "_lod1.glb")
		var has_lod1: bool = ResourceLoader.exists(lod1_path)
		var base: String = "%s_%02d" % [String(b["file"]).get_basename(), int(b["chunk"])]
		var near_end: float = prop_lod1_begin_m if has_lod1 else end_m
		for m: Dictionary in near["meshes"]:
			props.add_child(_multimesh_node(m, xfs, base + "_" + String(m["name"]), 0.0, near_end))
			stats["prop_multimeshes"] = int(stats["prop_multimeshes"]) + 1
		if has_lod1:
			var lod1: Dictionary = _prototype(lod1_path, "")
			for m: Dictionary in lod1["meshes"]:
				props.add_child(_multimesh_node(m, xfs, base + "_far_" + String(m["name"]), prop_lod1_begin_m, end_m))
				stats["prop_multimeshes"] = int(stats["prop_multimeshes"]) + 1
		var shapes: Array = near["shapes"]
		if shapes.is_empty() and String(b["file"]).contains("railing"):
			shapes = [_box_shape_of(near["meshes"])]  # the quay railings ship without a collider
		if not shapes.is_empty():
			var body: StaticBody3D = _chunk_body(int(b["chunk"]))
			for xf_v: Variant in xfs:
				for s: Dictionary in shapes:
					var cs := CollisionShape3D.new()
					cs.shape = s["shape"]
					cs.transform = (xf_v as Transform3D) * (s["xf"] as Transform3D)
					body.add_child(cs)
					stats["prop_colliders"] = int(stats["prop_colliders"]) + 1


func _chunk_body(chunk: int) -> StaticBody3D:
	if not _bodies.has(chunk):
		var body := StaticBody3D.new()
		body.name = "Colliders_%02d" % chunk
		_geo.add_child(body)
		_bodies[chunk] = body
	return _bodies[chunk]


## True when sign d would overlap an already kept sign on the same side at about the same height.
## Appends d to kept when it does not.
func _sign_overlaps(d: Dictionary, kept: Array[Dictionary]) -> bool:
	var p: Vector3 = _vec(d["position"])
	var w: float = _sign_width(String(d["asset"]))
	for k: Dictionary in kept:
		if String(k["side"]) != String(d.get("side", "")):
			continue
		var q: Vector3 = k["p"]
		if absf(q.y - p.y) > sign_overlap_height_m:
			continue
		if Vector2(p.x - q.x, p.z - q.z).length() < (w + float(k["w"])) * 0.5 + sign_gap_m:
			return true
	kept.append({"p": p, "w": w, "side": String(d.get("side", ""))})
	return false


## Footprint width along the facade, from the asset id naming convention of the props kit.
static func _sign_width(asset: String) -> float:
	if asset.ends_with("_12x5"):
		return 12.0
	if asset.ends_with("_8m"):
		return 8.0
	if asset.ends_with("_4m"):
		return 4.0
	if asset.begins_with("sign_blade"):
		return 1.0
	return 2.6


## One MultiMeshInstance3D for one mesh child of a prop, with every instance of the group. Range end 0 = unlimited.
func _multimesh_node(m: Dictionary, xfs: Array, node_name: String, begin: float, end: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m["mesh"]
	mm.instance_count = xfs.size()
	var rel: Transform3D = m["xf"]
	for i: int in xfs.size():
		mm.set_instance_transform(i, (xfs[i] as Transform3D) * rel)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mmi.visibility_range_begin = begin
	mmi.visibility_range_begin_margin = lod_fade_m if begin > 0.0 else 0.0
	mmi.visibility_range_end = end
	mmi.visibility_range_end_margin = lod_fade_m if end > 0.0 else 0.0
	return mmi


## Mesh children and collision shapes of a prototype GLB, library materials bound. Cached per path and owner.
func _prototype(path: String, owner_id: String) -> Dictionary:
	var key: String = path + "|" + owner_id
	if _proto.has(key):
		return _proto[key]
	var root: Node3D = _scene(path).instantiate() as Node3D
	var meshes: Array = []
	var shapes: Array = []
	for n: Node in _all_nodes(root):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			meshes.append({"name": String(n.name), "mesh": _library_mesh((n as MeshInstance3D).mesh, owner_id), "xf": _rel_xf(n, root)})
		elif n is CollisionShape3D and (n as CollisionShape3D).shape != null:
			shapes.append({"shape": (n as CollisionShape3D).shape, "xf": _rel_xf(n, root)})
	root.free()  # the prototype never enters the tree; its meshes and shapes survive as resources
	var info: Dictionary = {"meshes": meshes, "shapes": shapes}
	_proto[key] = info
	return info


## Box collider over all mesh children of a prototype, as {shape, xf} like a collision shape.
func _box_shape_of(meshes: Array) -> Dictionary:
	var box := AABB()
	var first: bool = true
	for m: Dictionary in meshes:
		var part: AABB = ((m["xf"] as Transform3D) * (m["mesh"] as Mesh).get_aabb())
		box = part if first else box.merge(part)
		first = false
	var shape := BoxShape3D.new()
	shape.size = box.size
	return {"shape": shape, "xf": Transform3D(Basis(), box.get_center())}


func _library_mesh(src: Mesh, owner_id: String) -> Mesh:
	var m: ArrayMesh = src.duplicate(true) as ArrayMesh
	for s: int in m.get_surface_count():
		var src_mat: Material = m.surface_get_material(s)
		var mat_name: String = src_mat.resource_name if src_mat != null else ""
		m.surface_set_material(s, MaterialLibrary.get_material(mat_name, owner_id))
	return m


# --- lights, probes, environment ------------------------------------------------------------

func _build_lights(raw: Array) -> void:
	var lights: Array = []
	var lamp_pos: Array[Vector3] = []
	for v: Variant in raw:
		var d: Dictionary = v
		var p: Vector3 = _vec(d["position"])
		var rng: float = float(d["range"])
		var src_name: String = String(d["source"])
		if src_name == "lamp_head":
			# Double lamps carry two heads 1.8 m apart; one spot is enough and frees budget for the rest.
			var dup: bool = false
			for q: Vector3 in lamp_pos:
				dup = dup or q.distance_to(p) < lamp_merge_m
			if dup:
				continue
			lamp_pos.append(p)
			rng = minf(rng, lamp_range_m)
		elif src_name == "neon_fill":
			rng = minf(rng, neon_fill_range_m)  # short fills: fewer volumes touched, so street lamps survive the budget
		lights.append({"type": String(d["type"]), "pos": p, "range": rng, "src": d})
	var vols: Dictionary = _budget_volumes()
	light_volumes = vols["aabbs"]
	var report: Dictionary = CityLights.budget(lights, light_volumes, vols["names"])
	var keep: Array = report["keep"]
	light_report = {"dropped": report["dropped"], "worst_all": report["worst_all"], "worst_kept": report["worst_kept"],
		"over_volumes": report["over_volumes"], "volumes": light_volumes.size(), "log": report["log"]}
	stats["lights_dropped"] = report["dropped"]
	for i: int in lights.size():
		if not keep[i]:
			continue
		var l: Dictionary = lights[i]
		var src: Dictionary = l["src"]
		var light: Light3D
		if l["type"] == "spot":
			var spot := SpotLight3D.new()
			var is_lamp: bool = String(src["source"]) == "lamp_head"
			spot.spot_range = float(l["range"])
			spot.spot_angle = lamp_spot_angle_deg if is_lamp else ACCENT_SPOT_ANGLE_DEG
			var dir: Vector3 = _vec(src["direction"]).normalized()
			spot.transform = Transform3D(Basis.looking_at(dir, Vector3.FORWARD if absf(dir.y) > 0.99 else Vector3.UP), l["pos"])
			light = spot
		else:
			var omni := OmniLight3D.new()
			omni.omni_range = float(l["range"])
			omni.position = l["pos"]
			light = omni
		light.name = "%s_%03d" % [String(src["source"]), i]
		light.light_color = Color.html(String(src["color"]))
		var boost: float = 1.0
		var src_name: String = String(src["source"])
		if src_name == "tunnel_strip":
			boost = tunnel_light_energy_scale
		elif src_name == "string_light":
			boost = string_light_energy_scale
		elif src_name == "lamp_head":
			boost = float(lamp_district_scale.get(String(src["district"]), 1.0))
		light.light_energy = float(src["energy"]) * light_energy_scale * boost
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = light_fade_begin_m
		light.distance_fade_length = light_fade_length_m
		_lighting.add_child(light)
		stats["lights"] = int(stats["lights"]) + 1


func _build_probes(raw: Array) -> void:
	var probes := Node3D.new()
	probes.name = "ReflectionProbes"
	_lighting.add_child(probes)
	for i: int in raw.size():
		var d: Dictionary = raw[i]
		var ext: Vector3 = _vec(d["extents_half"])
		var rp := ReflectionProbe.new()
		rp.name = "Probe%02d" % i
		rp.size = ext * 2.0
		rp.box_projection = true
		rp.interior = false
		rp.update_mode = ReflectionProbe.UPDATE_ONCE
		rp.set("max_distance", probe_max_distance_m)
		rp.transform = Transform3D(Basis(Vector3.UP, float(d["yaw"])), _vec(d["position"]))
		probes.add_child(rp)
		stats["probes"] = int(stats["probes"]) + 1


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.html("#070A14")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = ambient_energy
	env.fog_enabled = true
	env.fog_light_color = Color.html("#101A2E")
	# Depth fog, not exponential: exponential at 0.0045 put 74 percent fog on the bay 300 m out, so the skyline was gone.
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = fog_begin_m
	env.fog_depth_end = fog_end_m
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_lighting.add_child(we)


# --- helpers --------------------------------------------------------------------------------

func _scene(path: String) -> PackedScene:
	if not _packed.has(path):
		_packed[path] = load(path) as PackedScene
	return _packed[path]


## World AABBs of the meshes that are lit up close: road pieces, building LOD0 and near prop MultiMeshes.
## Far groups (LOD1/LOD2, prop far bands) are left out: their lights are faded by then. The map-sized ground
## plane and the flat paint decals and water are left out too: their AABBs cover the whole circuit.
func _budget_volumes() -> Dictionary:
	var aabbs: Array = []
	var names: PackedStringArray = PackedStringArray()
	for n: Node in _all_nodes(_geo):
		var nm: String = String(n.name)
		if nm.begins_with("ground") or nm.begins_with("decals_") or nm.begins_with("markings_") or nm.begins_with("water_"):
			continue
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and nm not in ["LOD1", "LOD2"]:
			aabbs.append((n as Node3D).global_transform * (n as MeshInstance3D).get_aabb())
			names.append(nm)
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null and "_LOD2" not in nm and "_far_" not in nm:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			aabbs.append((n as Node3D).global_transform * mm.get_aabb())
			names.append(nm)
	return {"aabbs": aabbs, "names": names}


func _chunk_of(s: float, lap: float, n_chunks: int) -> int:
	return clampi(int(floorf(fposmod(s, lap) / chunk_m)), 0, n_chunks - 1)


func _find_mesh(info: Dictionary, node_name: String) -> Dictionary:
	for m: Dictionary in info["meshes"]:
		if m["name"] == node_name:
			return m
	return {}


func _rel_xf(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != root and cur is Node3D:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _all_nodes(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c: Node in n.get_children():
		out.append_array(_all_nodes(c))
	return out


static func _vec(v: Variant) -> Vector3:
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
