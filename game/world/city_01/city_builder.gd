class_name CityBuilder
extends Track
## City 01 track root (Track contract). On _ready it assembles the circuit from city_01_layout.json:
## road, first-row buildings (LOD children switched by visibility range), second-row LOD2 MultiMeshes,
## props as MultiMeshes per chunk with merged colliders, lights (budgeted), reflection probes, the
## environment, racing line, start grid and checkpoints. The JSON is the source of truth; nothing is cached.
## Build notes and numbers: docs/design/CITY_01_ENGINE.md.

const FAR_LOD_UPDATE_MS: int = 100
const FAR_LOD_CHUNKS: int = 3  ## prop chunks per LOD2 batch
const BUILDING_DIR: String = "res://assets/world/kits/buildings/"
const PROP_DIR: String = "res://assets/world/kits/props/"
const ISTANBUL_DIR: String = "res://assets/world/kits/istanbul/"  
const VEHICLE_LAYER_BIT: int = 1 << 1
const NIGHT_SKY: Shader = preload("res://world/materials/night_sky.gdshader")
const TRIGGER_LAYER_BIT: int = 1 << 2
const CHECKPOINT_HEIGHT_M: float = 6.0
const CHECKPOINT_DEPTH_M: float = 1.5
const ACCENT_SPOT_ANGLE_DEG: float = 35.0
const GRID_REST_M: float = 0.47  ## car origin height above the road, as in the vehicle tests
const FALL_FLOOR_Y_M: float = -30.0
const FALL_FLOOR_SIZE_M: float = 6000.0
const CORRIDOR_MARGIN_M: float = 0.5  ## corridor = kerb line + this, per centreline sample
const CORRIDOR_SEARCH: int = 40  ## centreline samples either side of a building's lap offset searched for its nearest sample
const CORRIDOR_NEAR_M: float = 12.0  ## footprint points further than this from every sample are not in the corridor
const PUSH_STEP_M: float = 0.25
const PUSH_MAX_M: float = 40.0
const SIDEWALK_LIFT_M: float = 0.2  ## sidewalk top above the road centreline height
## Kit props of the street dressing. cat sets the visibility band as in _build_props. front "road" turns the prop's
## front (local +Z) to the race line with its long axis (local X) along the road; "across" turns the long axis across it.
## half_l and half_w are the footprint half sizes along X and Z. walk: a sidewalk prop that keeps a walking lane.
const DRESS_KIT: Dictionary = {
	"bus_shelter": {"file": "prop_bus_shelter.glb", "cat": "furniture", "half_l": 1.7, "half_w": 0.8, "front": "road", "walk": true},
	"bench": {"file": "prop_bench.glb", "cat": "furniture", "half_l": 0.9, "half_w": 0.33, "front": "road", "walk": true},
	"litter_bin": {"file": "prop_litter_bin.glb", "cat": "furniture", "half_l": 0.31, "half_w": 0.31, "front": "road", "walk": true},
	"planter_shrub": {"file": "prop_planter_shrub.glb", "cat": "furniture", "half_l": 0.65, "half_w": 0.37, "front": "road", "walk": true},
	"newspaper_box": {"file": "prop_newspaper_box.glb", "cat": "furniture", "half_l": 0.28, "half_w": 0.28, "front": "road", "walk": true},
	"bollard": {"file": "prop_bollard.glb", "cat": "furniture", "half_l": 0.2, "half_w": 0.2, "front": "road", "walk": true},
	"lamp_sodium": {"file": "prop_lamp_sodium.glb", "cat": "lamp", "half_l": 0.26, "half_w": 0.26, "front": "road", "walk": true},
	"container_stack": {"file": "prop_container_stack.glb", "cat": "circuit", "half_l": 9.1, "half_w": 2.5, "front": "road", "walk": false},
	"gantry_crane": {"file": "prop_gantry_crane.glb", "cat": "circuit", "half_l": 28.9, "half_w": 2.15, "front": "road", "walk": false},
}
const DRESS_FREE_STEP_M: float = 0.25  ## step of the walking-lane scan outward from a sidewalk prop
const DRESS_SLACK_M: float = 0.1  ## kerb-side props sit this much inside the clearance line, not on it
const DRESS_OFFSETS: Array = [0.0, 2.0, -2.0, 4.0, -4.0, 6.0, -6.0, 8.0, -8.0, 10.0, -10.0, 12.0, -12.0, 14.0, -14.0, 16.0, -16.0, 18.0, -18.0, 20.0, -20.0]  ## along-road search order, 2 m steps: finds the gaps between buildings

@export_group("Track data (defaults = City 01)")
@export var layout_path: String = "res://assets/world/city_01/city_01_layout.json"
@export var road_glb: String = "res://assets/world/city_01/city_01_road.glb"
@export var catalog_path: String = "res://assets/world/kits/buildings/catalog.json"
@export var centre_path: String = "res://assets/world/city_01/city_01_centerline.json"
@export var time_of_day: String = "night"  ## "day", "sunset" or "night" (world/time_of_day); RaceScene sets it before the track enters the tree
@export_group("Glass look (alpha 0 = kit default)")
@export var pane_glow_tint: Color = Color(0.0, 0.0, 0.0, 0.0)  ## lit window colour of M_WindowAtlas and M_ImpostorAtlas: cool white for a glass district
@export var pane_albedo_tint: Color = Color(0.0, 0.0, 0.0, 0.0)  ## multiplies the pane albedo: blue-green glass
@export_group("LED crowns")
@export var crown_color: Color = Color(0.0, 0.0, 0.0, 0.0)  ## emissive LED band on the roof edge of tall first-row buildings, alpha 0 = none
@export var crown_min_height_m: float = 60.0
@export var crown_energy: float = 3.0
@export_group("General")
@export var lod0_end_m: float = 70.0  ## first-row building LOD0 up to here, LOD1 to lod1_end_m, LOD2 beyond
@export var lod1_end_m: float = 180.0
@export var lod_fade_m: float = 4.0  ## dithered cross-fade band on every LOD and category switch
@export var prop_lod1_begin_m: float = 60.0  ## props with a _lod1 file switch to it here
@export var prop_furniture_end_m: float = 90.0  ## small street furniture
@export var prop_far_end_m: float = 250.0  ## circuit, lamps, signs, overhead; bay backdrop is unlimited (0)
@export var sign_gap_m: float = 0.4  ## minimum free space between two signs on a facade
@export var sign_overlap_height_m: float = 1.5  ## signs further apart vertically never collide
@export var chunk_m: float = 240.0  ## road chunk length for prop MultiMeshes, merged colliders and light budget
@export var light_energy_scale: float = 0.6  ## layout energies are Blender-scale; tuned in the capture
## Street lamp spot energy multiplier per district. Waterfront and market lamps had no visible pool at 0.6 x 14.
@export var lamp_district_scale: Dictionary = {"neon": 1.0, "downtown": 4.0, "waterfront": 10.0, "market": 4.0, "underpass": 1.0}
@export var fog_begin_m: float = 220.0  ## depth fog starts here: city blocks stay crisp, the bay backdrop fades
@export var fog_end_m: float = 1200.0
@export var lamp_range_m: float = 18.0  ## was 22: a street lamp only has to reach the road below it; shorter range touches fewer volumes
@export var neon_fill_range_m: float = 8.0  ## was 12 to 14: the omni fills used up the 8-per-mesh budget on the overpass
@export var lamp_merge_m: float = 3.0  ## lamp heads closer than this are one double lamp: one spot is kept
@export_range(0.0, 8.0) var tunnel_light_energy_scale: float = 6.0  ## underpass ceiling omnis: walls and road get a pool every 12 m
@export_range(0, 8) var split_min_excess: int = 1  ## a mesh is only split when it is touched by more than 8 + this many lights of one type: every split costs draw calls, one or two lights over are cheaper to drop
@export_range(0.0, 8.0) var string_light_energy_scale: float = 3.0  ## market string lights: warm dapple on the street under them
@export var lamp_spot_angle_deg: float = 55.0  ## wide cone for street lamp heads
@export var light_fade_begin_m: float = 70.0
@export var light_fade_length_m: float = 30.0
@export var occluder_shrink: float = 0.9  ## occluder box as a fraction of the collider box
@export var probe_max_distance_m: float = 160.0
@export var flip_signs: bool = false  ## turn sign props 180 degrees if their text reads mirrored in a capture
@export var ambient_color: Color = Color("#1E2740")  ## night fill for unlit walls; was #1B2B4D, walls read black
@export_range(0.0, 4.0) var ambient_energy: float = 1.2  ## was 0.6: facades away from lamps were black slabs
@export_range(0.0, 1.0) var moon_energy: float = 0.25  ## weak cool directional fill for far facades and roofs, no shadows
@export var moon_color: Color = Color("#8FA8D8")
## Waterfront warehouse wall wash: warm low-energy spots over the road, aimed at the land-side facades.
@export var wall_wash_count: int = 3
@export var wall_wash_energy: float = 14.0  ## JSON-scale energy, x light_energy_scale; the lamp heads are 14 x 8 district boost
@export var wall_wash_color: String = "#FFB26B"
@export var wall_wash_range_m: float = 24.0
@export var wall_wash_height_m: float = 6.0
@export var wall_wash_target_m: float = 4.0  ## aim point above the building origin
@export var wall_wash_s_min: float = 1150.0  ## waterfront stretch with the warehouses in view of the capture
@export var wall_wash_s_max: float = 1400.0
@export var wall_wash_spacing_m: float = 35.0
## Waterfront floodlights: one cool-white spot above each container stack and gantry crane base, aimed at it.
## No distance fade: the stacks sit 100 to 300 m from the promenade, past the normal fade.
@export var parked_car_count: int = 80  ## Arden Civic traffic sedan (docs/art/TRAFFIC_CAR_BRIEF.md), LOD by distance
const PARKED_LOD_END_M: Array[float] = [35.0, 90.0, 150.0]  ## LOD0 to 35 m, LOD1 to 90 m, LOD2 to 150 m (from the cell centre)
@export var parked_spacing_m: float = 12.0  ## candidate spacing along the lap, both kerbs
@export var parked_clear_m: float = 1.0  ## free gap between the corridor edge and a parked car's near side
@export var parked_box_clear_m: float = 0.5  ## free space kept around building and prop boxes
@export var parked_seed: int = 7
@export var parked_cell_m: float = 40.0  ## parked cars are grouped in cells this size and culled per cell
@export var parked_worst_limit_m: float = -0.4  ## every car corner must sit at least this far outside the corridor

@export_group("Street dressing")
@export var dressing_enabled: bool = true
@export var dress_clear_m: float = 0.3  ## free gap between a dressing prop and the race corridor edge
@export var dress_walk_m: float = 1.2  ## a sidewalk prop leaves at least this much walking lane beside it
@export var dress_bollard_step_m: float = 6.0  ## quay-edge bollards on the water side
@export var dress_bollard_inset_m: float = 1.2  ## bollard centre this far in from the water-side building line
@export var dress_promenade_step_m: float = 40.0  ## bench and bin pair on the waterfront promenade
@export var dress_lamp_step_m: float = 30.0  ## sodium lamp grid on the promenade, filled where the layout has none
@export var dress_lamp_gap_m: float = 14.0  ## a grid lamp is skipped when a lamp is nearer than this
@export var dress_downtown_lamp_step_m: float = 30.0  ## downtown street lamps, alternating sides, where the layout has none (s 666-1008 had none)
@export var dress_downtown_lamp_color: String = "#DCE6FF"  ## cool white LED heads downtown, against the sodium waterfront
@export var dress_stack_lat_m: float = 22.0  ## land-side container stacks, lateral distance from the centreline
@export var dress_stack_from_end_m: float = 100.0  ## first land-side container stack, this far before the waterfront end
@export var dress_crane_from_end_m: float = 40.0  ## land-side gantry crane (58 m long), this far before the waterfront end
@export var dress_crane_lat_m: float = 46.0  ## land-side gantry crane, lateral distance from the centreline
@export var dress_shelter_step_m: float = 120.0  ## downtown bus shelters, alternating sides
@export var dress_deck_y_m: float = 0.5  ## centreline height above which the overpass deck is up
@export var dress_approach_m: float = 12.0  ## bollards stand this far out on each overpass approach
@export var downtown_collider_back_m: float = 1.5  ## downtown building collider boxes move this far onto the building line
const DOWNTOWN_DISTRICT: String = "Downtown canyon"

@export var floodlight_energy: float = 9.0  ## JSON-scale energy, x light_energy_scale
@export var floodlight_color: String = "#FFF1D6"
@export var floodlight_range_m: float = 30.0
@export var floodlight_height_m: float = 18.0
@export var floodlight_s_min: float = 1100.0
@export var floodlight_s_max: float = 1420.0

var stats: Dictionary = {}  ## counts recorded for the tests and the engine report
var light_report: Dictionary = {}  ## CityLights.budget summary (counts, log lines)
var light_volumes: Array = []  ## AABBs the light budget was checked against (tests recount with them)
var light_volumes_hard: Array = []  ## the same without prop MultiMeshes (soft volumes): the 8-lights rule is enforced on these
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
var _c_y: PackedFloat32Array = PackedFloat32Array()  ## centreline height per sample
var _c_land: PackedFloat32Array = PackedFloat32Array()  ## lateral distance to the land-side building line (right)
var _c_water: PackedFloat32Array = PackedFloat32Array()  ## lateral distance to the water-side building line (left)
var _c_dist: PackedStringArray = PackedStringArray()  ## district name per centreline sample
var _c_spacing: float = 2.0
var _solid: Array[Dictionary] = []  ## {inv, half}: world-to-box transform and half size of every building and box prop collider
var _dress_lap: float = 0.0
var _dress_obs: Array[Dictionary] = []  ## {pos: Vector2, r: float}: street furniture the dressing keeps clear of
var _dress_recs: Array[Dictionary] = []  ## placed dressing props: kit, footprint, transform and log fields
var _far_groups: Dictionary = {}  ## "asset|chunk" -> {asset, chunk, xfs, mm, centres, active}: first-row LOD2 batches
var _far_next_ms: int = 0
var _crown_xfs: Array[Transform3D] = []  ## LED crown strips (scaled unit boxes) of the tall first-row buildings
var _tint_cache: Dictionary = {}  ## "material|owner" -> tinted copy of a window material
var _dress_lights: Array = []  ## lights of the dressing props, in the layout's light format


func _ready() -> void:
	var t0: int = Time.get_ticks_usec()
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	if not layout is Dictionary:
		push_error("CityBuilder: cannot parse " + layout_path)
		return
	var d: Dictionary = layout
	_geo = get_node("Geometry") as Node3D
	_lighting = get_node("Lighting") as Node3D
	_checkpoints = get_node("Checkpoints") as Node3D
	_grid_root = get_node("StartGrid") as Node3D
	var racing: Dictionary = d["racing"]
	var lap: float = float(d["lap_length"])
	_dress_lap = lap  # _c_index needs the lap before the dressing pass
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
	_dress_districts(inst, lap, n_chunks)
	_build_parked_cars(lap)
	_build_lights(d["lights"], inst)
	_build_probes(d["reflection_probes"])
	_build_environment()
	_apply_time_of_day()
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
	var road: Node3D = _scene(road_glb).instantiate() as Node3D
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
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
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
		var root: Node3D = _scene(_bld_path(asset)).instantiate() as Node3D
		root.name = "%s_%03d" % [asset, int(stats["first_row"])]
		root.transform = xf
		MaterialLibrary.apply(root, asset)
		_retint(root, asset)
		_set_lod_ranges(root)
		_collect_far_lod(root, asset, d, xf, lap)
		if colliders.has(asset):
			_add_occluder(root, colliders[asset])
		first.add_child(root)
		if colliders.has(asset):
			var box_centre: Vector3 = _collider_centre(d, xf, colliders[asset]["center"] as Vector3)
			_solid.append(_box_entry(_rel_xf(root, self) * Transform3D(Basis(), box_centre), colliders[asset]["size"] as Vector3))
		stats["first_row"] = int(stats["first_row"]) + 1
		_collect_crown(d, xf)
	_emit_far_lod(first)
	_emit_crowns(first)
	for asset: String in lod2_xfs.keys():
		var arr: Array = lod2_xfs[asset]
		if colliders.has(asset):
			for xf_v: Variant in arr:
				_solid.append(_box_entry((xf_v as Transform3D) * Transform3D(Basis(), colliders[asset]["center"] as Vector3), colliders[asset]["size"] as Vector3))
		var lod2: Dictionary = _find_mesh(_prototype(_bld_path(asset), asset), "LOD2")
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


## Pulls the LOD2 impostor out of a first-row building (one MeshInstance3D per building was ~1 draw each) and files it
## under (asset, chunk). _emit_far_lod turns every group into one MultiMesh, _update_far_lod picks the instances by distance.
func _collect_far_lod(root: Node3D, asset: String, d: Dictionary, xf: Transform3D, lap: float) -> void:
	var lod2: Node = null
	for n: Node in _all_nodes(root):
		if n is MeshInstance3D and String(n.name) == "LOD2":
			lod2 = n
			break
	if lod2 == null:
		return
	var rel: Transform3D = _rel_xf(lod2, root)
	lod2.get_parent().remove_child(lod2)
	lod2.free()
	var chunk: int = _chunk_of(float(d.get("s_offset_m", 0.0)), lap, maxi(1, ceili(lap / chunk_m)))
	chunk = chunk / FAR_LOD_CHUNKS  # coarser than the prop chunks: fewer batches, still frustum-culled
	var key: String = "%s|%d" % [asset, chunk]
	if not _far_groups.has(key):
		_far_groups[key] = {"asset": asset, "chunk": chunk, "xfs": []}
	((_far_groups[key] as Dictionary)["xfs"] as Array).append(xf * rel)


## One MultiMeshInstance3D per (asset, chunk) holding the far LOD2 of every building in it, under first/LOD2_Batches.
## A MultiMesh has one visibility range for all instances, so the range is not used: the instance subset beyond lod1_end_m
## is chosen per building in _update_far_lod (visible_instance_count), which keeps the per-building switch of the old nodes.
## shortcut: no dithered fade at the LOD1 to LOD2 switch (far, night, fog), fade needs a per-instance range.
func _emit_far_lod(first: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "LOD2_Batches"
	first.add_child(holder)
	for key: String in _far_groups.keys():
		var g: Dictionary = _far_groups[key]
		var asset: String = String(g["asset"])
		var lod2: Dictionary = _find_mesh(_prototype(_bld_path(asset), asset), "LOD2")
		if lod2.is_empty():
			continue
		var xfs: Array = g["xfs"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = lod2["mesh"]
		mm.instance_count = xfs.size()
		mm.visible_instance_count = 0
		var box: AABB = (lod2["mesh"] as Mesh).get_aabb()
		var centres := PackedVector3Array()
		var all_box := AABB()
		for i: int in xfs.size():
			var t: Transform3D = xfs[i]
			mm.set_instance_transform(i, t)
			centres.append(t * box.get_center())
			all_box = (t * box) if i == 0 else all_box.merge(t * box)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_LOD2_%02d" % [asset, int(g["chunk"])]
		mmi.multimesh = mm
		mmi.custom_aabb = all_box  # cull the batch as a whole even when the subset changes
		holder.add_child(mmi)
		g["mm"] = mm
		g["centres"] = centres
		g["active"] = PackedInt32Array()
		stats["far_lod_multimeshes"] = int(stats.get("far_lod_multimeshes", 0)) + 1
		stats["far_lod_instances"] = int(stats.get("far_lod_instances", 0)) + xfs.size()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()  # wall clock: the draw_breakdown freeze sets time_scale 0
	if now < _far_next_ms:
		return
	_far_next_ms = now + FAR_LOD_UPDATE_MS
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		update_far_lod(cam.global_position)


## Shows, per batch, the buildings whose LOD2 centre is at least lod1_end_m from eye. Rewrites a batch only when its set changed.
func update_far_lod(eye: Vector3) -> void:
	var lim2: float = lod1_end_m * lod1_end_m
	for key: String in _far_groups.keys():
		var g: Dictionary = _far_groups[key]
		if not g.has("mm"):
			continue
		var centres: PackedVector3Array = g["centres"]
		var xfs: Array = g["xfs"]
		var act := PackedInt32Array()
		for i: int in centres.size():
			if eye.distance_squared_to(centres[i]) >= lim2:
				act.append(i)
		if act == (g["active"] as PackedInt32Array):
			continue
		g["active"] = act
		var mm: MultiMesh = g["mm"]
		for k: int in act.size():
			mm.set_instance_transform(k, xfs[act[k]] as Transform3D)
		mm.visible_instance_count = act.size()


## Centre of a first-row building's collider box in building space. Downtown boxes sit downtown_collider_back_m in front
## of the building line, which took 1.5 m of the sidewalk; they move back onto the line. The mesh and the physics do not move.
## shortcut: a fixed shift, not the measured building line per sample; a facade off the line would need the per-sample value.
func _collider_centre(d: Dictionary, xf: Transform3D, centre: Vector3) -> Vector3:
	if _c_pos.is_empty():
		return centre
	var s: float = float(d.get("s_offset_m", 0.0))
	var i: int = _c_index(s)
	if _c_dist[i] != DOWNTOWN_DISTRICT:
		return centre
	var wc: Vector3 = xf * centre
	var lat: float = (Vector2(wc.x, wc.z) - _c_pos[i]).dot(_c_right[i])
	var away: Vector2 = _c_right[i] * signf(lat)  # away from the centreline, which is the building side
	var shift: Vector3 = xf.basis.inverse() * Vector3(away.x, 0.0, away.y) * downtown_collider_back_m
	stats["downtown_collider_moves"] = int(stats.get("downtown_collider_moves", 0)) + 1
	return centre + shift


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
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(centre_path))
	if not data is Dictionary:
		push_error("CityBuilder: cannot parse " + centre_path)
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
		_c_y.append(p.y)
		_c_pos.append(Vector2(p.x, p.z))
		var rt: Vector2 = Vector2(r.x, r.z).normalized()
		_c_right.append(rt)
		_c_half.append(maxf(Vector2(lk.x, lk.z).length(), Vector2(rk.x, rk.z).length()) + CORRIDOR_MARGIN_M)
		var rb: Vector3 = _vec(e["right_building"]) - p
		var lb: Vector3 = _vec(e["left_building"]) - p
		_c_land.append(Vector2(rb.x, rb.z).dot(rt))
		_c_water.append(-Vector2(lb.x, lb.z).dot(rt))
		_c_dist.append(String(s.get("district_name", "")))


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
		if not ResourceLoader.exists(_prop_path(file)):
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
		var xfs: Array = b["xfs"]
		var near: Dictionary = _emit_prop_meshes(props, String(b["file"]), int(b["chunk"]), String(b["cat"]), xfs)
		var shapes: Array = near["shapes"]
		if shapes.is_empty() and String(b["file"]).contains("railing"):
			shapes = [_box_shape_of(near["meshes"])]  # the quay railings ship without a collider
		_add_prop_colliders(shapes, xfs, int(b["chunk"]))


## Mesh children of one prop group (one file, chunk and category): a near MultiMesh per mesh and a far LOD1 band
## when the kit ships a _lod1 file. Returns the prototype; the caller turns its shapes into colliders.
func _emit_prop_meshes(parent: Node3D, file: String, chunk: int, cat: String, xfs: Array) -> Dictionary:
	var path: String = _prop_path(file)
	var end_m: float = prop_far_end_m
	if cat == "furniture":
		end_m = prop_furniture_end_m
	elif cat == "bay" or cat == "skyline":
		end_m = 0.0
	var near: Dictionary = _prototype(path, "")
	var lod1_path: String = path.replace(".glb", "_lod1.glb")
	var has_lod1: bool = ResourceLoader.exists(lod1_path)
	var base: String = "%s_%02d" % [file.get_basename(), chunk]
	var near_end: float = prop_lod1_begin_m if has_lod1 else end_m
	for m: Dictionary in near["meshes"]:
		parent.add_child(_multimesh_node(m, xfs, base + "_" + String(m["name"]), 0.0, near_end))
		stats["prop_multimeshes"] = int(stats["prop_multimeshes"]) + 1
	if has_lod1:
		var lod1: Dictionary = _prototype(lod1_path, "")
		for m: Dictionary in lod1["meshes"]:
			parent.add_child(_multimesh_node(m, xfs, base + "_far_" + String(m["name"]), prop_lod1_begin_m, end_m))
			stats["prop_multimeshes"] = int(stats["prop_multimeshes"]) + 1
	return near


func _add_prop_colliders(shapes: Array, xfs: Array, chunk: int) -> void:
	if shapes.is_empty():
		return
	var body: StaticBody3D = _chunk_body(chunk)
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
		m.surface_set_material(s, _track_material(mat_name, owner_id))
	return m


## Library material, or a tinted copy of a window material when the track sets pane_glow_tint / pane_albedo_tint.
## The shared library instance is never touched, so City 01 keeps its look when both tracks load in one process.
func _track_material(mat_name: String, owner_id: String) -> Material:
	var base: Material = MaterialLibrary.get_material(mat_name, owner_id)
	if pane_glow_tint.a <= 0.0 and pane_albedo_tint.a <= 0.0:
		return base
	if mat_name != "M_WindowAtlas" and mat_name != "M_ImpostorAtlas":
		return base
	var key: String = "%s|%s|%s|%s" % [mat_name, owner_id, pane_glow_tint.to_html(), pane_albedo_tint.to_html()]
	if not _tint_cache.has(key):
		var m: ShaderMaterial = (base as ShaderMaterial).duplicate() as ShaderMaterial
		if pane_glow_tint.a > 0.0:
			var g := Vector3(pane_glow_tint.r, pane_glow_tint.g, pane_glow_tint.b)
			m.set_shader_parameter("glow_tint", g)
			m.set_shader_parameter("glow_tint_cool", g)
		if pane_albedo_tint.a > 0.0:
			var t: Color = m.get_shader_parameter("tint")
			m.set_shader_parameter("tint", Color(t.r * pane_albedo_tint.r, t.g * pane_albedo_tint.g, t.b * pane_albedo_tint.b))
		_tint_cache[key] = m
	return _tint_cache[key]


## Swaps the window surfaces of a first-row building for the track's tinted copies (no-op without a tint).
func _retint(root: Node3D, asset: String) -> void:
	if pane_glow_tint.a <= 0.0 and pane_albedo_tint.a <= 0.0:
		return
	for n: Node in _all_nodes(root):
		if not n is MeshInstance3D:
			continue
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var ov: Material = mi.get_surface_override_material(s)
			if ov != null and (ov.resource_name == "M_WindowAtlas" or ov.resource_name == "M_ImpostorAtlas"):
				mi.set_surface_override_material(s, _track_material(ov.resource_name, asset))


## LED crown: three thin strips (front and both sides, facing the street) on the roof edge of a tall first-row building.
func _collect_crown(d: Dictionary, xf: Transform3D) -> void:
	if crown_color.a <= 0.0:
		return
	var h: float = float(d.get("height_m", 0.0))
	if h < crown_min_height_m:
		return
	var w: float = float(d.get("width_m", 0.0))
	var dep: float = float(d.get("depth_m", 0.0))
	var t: float = 0.35
	var y: float = h + t * 0.5
	_crown_xfs.append(xf * Transform3D(Basis.from_scale(Vector3(w, t, t)), Vector3(0.0, y, -t * 0.5)))
	_crown_xfs.append(xf * Transform3D(Basis.from_scale(Vector3(t, t, dep)), Vector3(-w * 0.5 + t * 0.5, y, -dep * 0.5)))
	_crown_xfs.append(xf * Transform3D(Basis.from_scale(Vector3(t, t, dep)), Vector3(w * 0.5 - t * 0.5, y, -dep * 0.5)))


func _emit_crowns(parent: Node3D) -> void:
	if _crown_xfs.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.BLACK
	mat.emission_enabled = true
	mat.emission = Color(crown_color.r, crown_color.g, crown_color.b)
	mat.emission_energy_multiplier = crown_energy
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = mat
	mm.mesh = box
	mm.instance_count = _crown_xfs.size()
	for i: int in _crown_xfs.size():
		mm.set_instance_transform(i, _crown_xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LedCrowns"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	stats["crown_strips"] = _crown_xfs.size()


# --- street dressing ------------------------------------------------------------------------

## Waterfront and downtown street dressing, placed after the layout props from kit props only. The water-side quay edge
## gets bollards every dress_bollard_step_m; the land-side promenade gets a bench and bin pair every
## dress_promenade_step_m and a sodium lamp wherever the 30 m lamp grid has none; two container stacks and a gantry crane
## stand on the open land-side lot past the warehouse row. Downtown gets a bus shelter every dress_shelter_step_m on alternating
## sides, benches, planters and newspaper boxes between, and bollards on both approaches to the overpass deck.
## Every spot is checked against the corridor, the building lines, the boxes and the furniture; each placement is in
## stats["dressing"], each miss in stats["dressing_missed"].
func _dress_districts(inst: Array, lap: float, n_chunks: int) -> void:
	_dress_recs.clear()
	_dress_lights.clear()
	stats["dressing_missed"] = {}
	stats["dressing_reasons"] = {}
	stats["dressing"] = []
	if not dressing_enabled or _c_pos.is_empty():
		return
	_dress_lap = lap
	_dress_obs = _dress_obstacles(inst)
	var wf: Vector2 = _district_span("Waterfront")
	var dt: Vector2 = _district_span("Downtown canyon")
	if wf.y > wf.x:
		var s: float = wf.x
		while s <= wf.y:  # water side of the quay edge
			_dress_at("bollard", s, -1.0, _c_water[_c_index(s)] - dress_bollard_inset_m, "waterfront", lap)
			s += dress_bollard_step_m
		s = wf.x + 20.0
		while s <= wf.y - 10.0:  # promenade: bench and bin pair
			_dress_at("bench", s, 1.0, _kerb_lat(s, 0.33), "waterfront", lap)
			_dress_at("litter_bin", s + 4.0, 1.0, _kerb_lat(s + 4.0, 0.31), "waterfront", lap)
			s += dress_promenade_step_m
		s = wf.x + 15.0
		while s <= wf.y - 5.0:  # sodium lamp grid
			if _lamp_gap(inst, s) > dress_lamp_gap_m:
				_dress_at("lamp_sodium", s, 1.0, _kerb_lat(s, 0.26), "waterfront", lap)
			s += dress_lamp_step_m
		# The land-side warehouse row ends about 115 m before the waterfront end: the open lot there is where the stacks
		# and the crane can be seen from the racing line. Behind the row (old s) they were hidden by the warehouses.
		_dress_at("gantry_crane", wf.y - dress_crane_from_end_m, 1.0, dress_crane_lat_m, "waterfront", lap, [40.0, 52.0, 58.0])
		_dress_at("container_stack", wf.y - dress_stack_from_end_m, 1.0, dress_stack_lat_m, "waterfront", lap, [40.0, 46.0, 52.0, 58.0])
		_dress_at("container_stack", wf.y - 20.0, 1.0, dress_stack_lat_m, "waterfront", lap, [40.0, 46.0, 52.0, 58.0])
	if dt.y > dt.x:
		var k: int = 0
		var t: float = dt.x + 25.0
		while t <= dt.y - 10.0:  # downtown street level: shelter, then bench, newspaper box and planter between shelters
			var side: float = 1.0 if k % 2 == 0 else -1.0
			_dress_at("bus_shelter", t, side, _kerb_lat(t, 0.8), "downtown", lap)
			_dress_at("bench", t + 45.0, -side, _kerb_lat(t + 45.0, 0.33), "downtown", lap)
			_dress_at("newspaper_box", t + 70.0, side, _kerb_lat(t + 70.0, 0.28), "downtown", lap)
			_dress_at("planter_shrub", t + 95.0, -side, _kerb_lat(t + 95.0, 0.37), "downtown", lap)
			k += 1
			t += dress_shelter_step_m
		# Street lamps: the layout lights the Neon Strip only, so the downtown canyon road was black from s 666 on.
		var j: int = 0
		var u: float = dt.x + 10.0
		while u <= dt.y - 5.0:
			if _lamp_gap(inst, u, true) > dress_lamp_gap_m:
				_dress_at("lamp_sodium", u, 1.0 if j % 2 == 0 else -1.0, _kerb_lat(u, 0.26), "downtown", lap)
				j += 1
			u += dress_downtown_lamp_step_m
	_dress_approaches(lap)
	_dress_emit(lap, n_chunks)


## Bollards on both sidewalks at each end of the overpass deck: three at each end, dress_approach_m out from the ramp.
func _dress_approaches(lap: float) -> void:
	var runs: Array[Vector2] = []
	var start: float = -1.0
	for i: int in _c_pos.size():
		var up: bool = _c_y[i] > dress_deck_y_m
		if up and start < 0.0:
			start = i * _c_spacing
		elif not up and start >= 0.0:
			runs.append(Vector2(start, i * _c_spacing))
			start = -1.0
	for run: Vector2 in runs:
		for side: float in [-1.0, 1.0]:
			for off: float in [-dress_approach_m, -dress_approach_m + 4.0, -dress_approach_m + 8.0]:
				_dress_at("bollard", run.x + off, side, _kerb_lat(run.x + off, 0.2), _district_at(run.x + off), lap)
			for off: float in [dress_approach_m - 8.0, dress_approach_m - 4.0, dress_approach_m]:
				_dress_at("bollard", run.y + off, side, _kerb_lat(run.y + off, 0.2), _district_at(run.y + off), lap)


## Places one kit prop near arc length s on side sgn (+1 right, -1 left) at lateral distance lat. Tries the offsets in
## DRESS_OFFSETS in order. Returns false, and counts the miss, when none fits.
func _dress_at(kit: String, s: float, sgn: float, lat: float, district: String, lap: float, lat_extra: Array = []) -> bool:
	var lats: Array = [lat]
	if bool(DRESS_KIT[kit]["walk"]):
		lats.append_array([lat + 0.6, lat + 1.2])  # a sidewalk prop may sit a little further out when the kerb side is full
	lats.append_array(lat_extra)
	for lat_try: Variant in lats:
		for off: Variant in DRESS_OFFSETS:
			var at: float = fposmod(s + float(off), lap)
			if district == "downtown" and kit != "lamp_sodium" and _c_y[_c_index(at)] > dress_deck_y_m:
				_dress_why(kit, "deck")  # downtown furniture stands at street level; lamps also stand on the deck sidewalks
				continue
			var rec: Dictionary = _dress_fit(kit, at, sgn, float(lat_try), lap)
			if rec.has("why"):
				_dress_why(kit, String(rec["why"]))
				continue
			rec["kit"] = kit
			rec["district"] = district
			rec["s"] = at
			rec["side"] = "right" if sgn > 0.0 else "left"
			rec["lat"] = float(lat_try)
			_dress_recs.append(rec)
			if kit == "bus_shelter" or kit == "lamp_sodium":
				_dress_light(kit, rec, district)
			return true
	var missed: Dictionary = stats["dressing_missed"]
	missed[kit] = int(missed.get(kit, 0)) + 1
	return false


func _dress_why(kit: String, why: String) -> void:
	var reasons: Dictionary = stats["dressing_reasons"]
	var key: String = kit + ":" + why
	reasons[key] = int(reasons.get(key, 0)) + 1


## The record of one prop at this spot, or {} when it does not fit: outside the corridor by dress_clear_m, a walking lane
## of dress_walk_m beside a sidewalk prop inside the building line, clear of boxes and furniture.
func _dress_fit(kit: String, s: float, sgn: float, lat: float, lap: float) -> Dictionary:
	var k: Dictionary = DRESS_KIT[kit]
	var i: int = _c_index(s)
	var r: Vector2 = _c_right[i]
	var t: Vector2 = Vector2(r.y, -r.x)  # tangent: the right vector turned by 90 degrees
	var u: Vector2 = r * sgn
	var front: Vector2 = t if String(k["front"]) == "across" else -u
	var along: Vector2 = Vector2(front.y, -front.x)  # local X: the long axis of the footprint
	var hl: float = float(k["half_l"])
	var hw: float = float(k["half_w"])
	var c: Vector2 = _c_pos[i] + u * lat
	var pts: Array[Vector2] = _footprint_points(c, along, front, hl, hw)
	var worst: float = -INF
	var lo: float = INF
	var hi: float = -INF
	for p: Vector2 in pts:
		worst = maxf(worst, _corridor_margin(p, i))
		var l: float = (p - _c_pos[i]).dot(u)
		lo = minf(lo, l)
		hi = maxf(hi, l)
	if worst > -dress_clear_m:
		return {"why": "corridor"}
	var walk: float = -1.0
	if bool(k["walk"]):
		var build: float = _c_land[i] if sgn > 0.0 else _c_water[i]
		if build - hi < 0.0:
			return {"why": "building"}
		walk = maxf(lo - _c_half[i], _free_out(_c_pos[i], t, u, hl, hi, build))
		if walk < dress_walk_m:
			return {"why": "walk"}
	if _hits_solid(pts, c):
		return {"why": "box"}
	if _dress_clash(pts, c, along, front, hl, hw):
		return {"why": "clash"}
	var yaw: float = atan2(front.x, front.y)
	return {"xf": Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, _c_y[i] + SIDEWALK_LIFT_M, c.y)),
		"c": c, "pts": pts, "along": along, "front": front, "hl": hl, "hw": hw,
		"walk_m": walk, "worst_margin": worst}


## Free distance outward from lateral hi to the first solid (wall, box) or to the building line, along three points of
## the footprint's road-side extent. Between two buildings the building line is the limit; against a wall, the wall is.
func _free_out(p0: Vector2, t: Vector2, u: Vector2, hl: float, hi: float, build: float) -> float:
	var x: float = hi
	while x <= build:
		for a: float in [-hl * 0.9, 0.0, hl * 0.9]:
			var q: Vector2 = p0 + u * x + t * a
			if _hits_solid([q], q, 0.0):
				return x - hi
		x += DRESS_FREE_STEP_M
	return build - hi


## True when the footprint touches a furniture circle or another dressing footprint (both grown by dress_clear_m).
func _dress_clash(pts: Array[Vector2], c: Vector2, along: Vector2, front: Vector2, hl: float, hw: float) -> bool:
	for o: Dictionary in _dress_obs:
		var d: Vector2 = (o["pos"] as Vector2) - c
		var gx: float = d.dot(along) - clampf(d.dot(along), -hl, hl)
		var gz: float = d.dot(front) - clampf(d.dot(front), -hw, hw)
		if Vector2(gx, gz).length() < float(o["r"]):
			return true
	for rec: Dictionary in _dress_recs:
		var rc: Vector2 = rec["c"]
		var ra: Vector2 = rec["along"]
		var rf: Vector2 = rec["front"]
		var rl: float = float(rec["hl"]) + dress_clear_m
		var rw: float = float(rec["hw"]) + dress_clear_m
		for p: Vector2 in pts:
			if _in_box(p - rc, ra, rf, rl, rw):
				return true
		for q: Vector2 in rec["pts"]:
			if _in_box(q - c, along, front, hl + dress_clear_m, hw + dress_clear_m):
				return true
	return false


static func _in_box(v: Vector2, along: Vector2, front: Vector2, hl: float, hw: float) -> bool:
	return absf(v.dot(along)) <= hl and absf(v.dot(front)) <= hw


## Lights of a placed prop in the layout's light format: the shelter advert and the sodium lamp head.
func _dress_light(kit: String, rec: Dictionary, district: String) -> void:
	var xf: Transform3D = rec["xf"]
	if kit == "bus_shelter":
		_dress_lights.append({"type": "omni", "position": _arr(xf * Vector3(0.0, 2.2, 0.1)), "range": 6.0,
			"source": "bus_shelter_panel", "district": district, "color": "#FFEBCC", "energy": 3.0})
	else:
		_dress_lights.append({"type": "spot", "position": _arr(xf * Vector3(0.0, 9.1, 1.8)), "range": 28.0,
			"source": "lamp_head", "district": district,
			"color": dress_downtown_lamp_color if district == "downtown" else "#FFB26B", "energy": 14.0,
			"direction": [0.0, -1.0, 0.0]})  # clamped to lamp_range_m like every lamp head


## Builds the placed props in groups of one file, chunk and category, as the layout props are.
func _dress_emit(lap: float, n_chunks: int) -> void:
	var root := Node3D.new()
	root.name = "Dressing"
	_geo.add_child(root)
	var groups: Dictionary = {}
	var counts: Dictionary = {}
	var rows: Array = []
	for rec: Dictionary in _dress_recs:
		var kit: String = rec["kit"]
		var file: String = DRESS_KIT[kit]["file"]
		var cat: String = DRESS_KIT[kit]["cat"]
		var chunk: int = _chunk_of(float(rec["s"]), lap, n_chunks)
		var key: String = "%s|%d|%s" % [file, chunk, cat]
		if not groups.has(key):
			groups[key] = {"file": file, "chunk": chunk, "cat": cat, "xfs": []}
		((groups[key] as Dictionary)["xfs"] as Array).append(rec["xf"])
		counts[kit] = int(counts.get(kit, 0)) + 1
		var origin: Vector3 = (rec["xf"] as Transform3D).origin
		rows.append({"kit": kit, "district": rec["district"], "side": rec["side"], "s": snappedf(float(rec["s"]), 0.1),
			"lat": snappedf(float(rec["lat"]), 0.01), "pos": _arr(origin), "walk_m": snappedf(float(rec["walk_m"]), 0.01),
			"worst_margin": snappedf(float(rec["worst_margin"]), 0.01)})
	for key: String in groups.keys():
		var g: Dictionary = groups[key]
		var near: Dictionary = _emit_prop_meshes(root, String(g["file"]), int(g["chunk"]), String(g["cat"]), g["xfs"])
		_add_prop_colliders(near["shapes"], g["xfs"], int(g["chunk"]))
	stats["dressing"] = rows
	stats["dressing_counts"] = counts
	print("CityBuilder: dressing placed %d %s, missed %s, reasons %s" % [_dress_recs.size(), counts, stats["dressing_missed"], stats["dressing_reasons"]])


## Furniture the dressing keeps clear of: the layout's street furniture and lamps as circles of their catalog size.
## Boxes (guardrails, barriers, railings) are already in _solid.
func _dress_obstacles(inst: Array) -> Array[Dictionary]:
	var half: Dictionary = {}
	var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROP_DIR + "catalog.json"))
	for it: Variant in cat["items"]:
		var d: Dictionary = it
		var sz: Array = d["size"]
		half[String(d["id"])] = maxf(float(sz[0]), float(sz[2])) * 0.5
	var out: Array[Dictionary] = []
	for v: Variant in inst:
		var d: Dictionary = v
		if String(d["kind"]) != "prop" or not (String(d.get("category", "")) in ["furniture", "lamp"]):
			continue
		var p: Vector3 = _vec(d["position"])
		out.append({"pos": Vector2(p.x, p.z), "r": float(half.get(String(d["asset"]), 0.5)) + dress_clear_m})
	return out


## Distance along the road from s to the nearest sodium lamp of the waterfront, layout or placed.
## Distance along the lap to the nearest lamp: waterfront sodium lamps of the layout (any_lamp: every layout lamp prop)
## and every placed dressing lamp.
func _lamp_gap(inst: Array, s: float, any_lamp: bool = false) -> float:
	var best: float = INF
	for v: Variant in inst:
		var d: Dictionary = v
		if String(d["kind"]) != "prop":
			continue
		var asset: String = String(d["asset"])
		var hit: bool = asset.begins_with("lamp") if any_lamp else (asset == "lamp_sodium" and String(d.get("district", "")) == "waterfront")
		if hit:
			best = minf(best, absf(float(d["s_offset_m"]) - s))
	for rec: Dictionary in _dress_recs:
		if String(rec["kit"]) == "lamp_sodium":
			best = minf(best, absf(float(rec["s"]) - s))
	return best


## Lateral distance from the centreline to the kerb-side edge of a sidewalk prop of half width half_w, with a clear gap.
func _kerb_lat(s: float, half_w: float) -> float:
	return _c_half[_c_index(s)] + dress_clear_m + half_w + DRESS_SLACK_M


func _c_index(s: float) -> int:
	return posmod(roundi(fposmod(s, _dress_lap) / _c_spacing), _c_pos.size())


## Arc length span [start, end) of a district by its name in the centreline data. Zero span when it is missing.
func _district_span(name: String) -> Vector2:
	var first: int = -1
	var last: int = -1
	for i: int in _c_dist.size():
		if _c_dist[i] == name:
			if first < 0:
				first = i
			last = i
	if first < 0:
		return Vector2.ZERO
	return Vector2(first * _c_spacing, (last + 1) * _c_spacing)


func _district_at(s: float) -> String:
	return _c_dist[_c_index(s)]


static func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


# --- parked cars ----------------------------------------------------------------------------

func _parked_range(mmi: MultiMeshInstance3D, begin_m: float, end_m: float) -> void:
	mmi.visibility_range_begin = begin_m
	mmi.visibility_range_begin_margin = lod_fade_m if begin_m > 0.0 else 0.0
	mmi.visibility_range_end = end_m
	mmi.visibility_range_end_margin = lod_fade_m
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Parked cars on the kerb side outside the race corridor, kept clear of building and box prop colliders.
## Candidates are every parked_spacing_m along the centreline on both sides; accepted ones are thinned evenly to
## parked_car_count. Each colour is one MultiMesh (a paint override), plus one body MultiMesh for all cars.
## Cars get no colliders, so the corridor test cannot see them: the placement itself keeps them out of the corridor.
func _build_parked_cars(lap: float) -> void:
	var car: Dictionary = ParkedCars.bake(2)
	var lods: Array[Dictionary] = [ParkedCars.bake(0), ParkedCars.bake(1), car]
	var aabb: AABB = car["aabb"]
	var half_w: float = aabb.size.x * 0.5
	var half_l: float = aabb.size.z * 0.5
	var lift: float = -aabb.position.y  ## origin height that puts the lowest point of the car on the road
	for b: Dictionary in _collect_prop_boxes():
		_solid.append(b)
	var step: int = maxi(1, roundi(parked_spacing_m / _c_spacing))
	var found: Array[Dictionary] = []
	var worst: float = -INF
	var n: int = _c_pos.size()
	for i: int in range(0, n, step):
		var fwd3: Vector3 = Vector3(_c_pos[(i + 1) % n].x - _c_pos[(i - 1 + n) % n].x, 0.0,
			_c_pos[(i + 1) % n].y - _c_pos[(i - 1 + n) % n].y).normalized()
		var fwd: Vector2 = Vector2(fwd3.x, fwd3.z)
		var right: Vector2 = _c_right[i]
		for side: float in [-1.0, 1.0]:
			var centre: Vector2 = _c_pos[i] + right * side * (_c_half[i] + parked_clear_m + half_w)
			var pts: Array[Vector2] = _footprint_points(centre, fwd, right, half_l, half_w)
			var margin: float = -INF
			for p: Vector2 in pts:
				margin = maxf(margin, _corridor_margin(p, i))
			if margin > parked_worst_limit_m:
				continue
			if _hits_solid(pts, centre):
				continue
			worst = maxf(worst, margin)
			var place: Transform3D = Transform3D(Basis.looking_at(Vector3(fwd.x, 0.0, fwd.y), Vector3.UP),
				Vector3(centre.x, _c_y[i] + lift, centre.y))
			found.append({"xf": place, "margin": margin})
	var rng := RandomNumberGenerator.new()
	rng.seed = parked_seed
	var parked := Node3D.new()
	parked.name = "ParkedCars"
	_geo.add_child(parked)
	var count: int = mini(parked_car_count, found.size())
	var colours: Array[Color] = ParkedCars.paint_colours()
	var names: PackedStringArray = ParkedCars.paint_names()
	var per_colour: Array = []
	for c: int in colours.size():
		per_colour.append([])
	var body_xfs: Array[Transform3D] = []
	for k: int in count:
		var pick: Dictionary = found[(k * found.size()) / count]
		var place: Transform3D = pick["xf"]
		# The model is authored nose +Z; the car's Visual turns it 180 degrees. Half the cars face the other way.
		var model: Transform3D = place * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		if rng.randf() < 0.5:
			model = place
		body_xfs.append(model)
		(per_colour[rng.randi_range(0, colours.size() - 1)] as Array).append(model)
	# Cars are grouped into cells of parked_cell_m with the node at the cell centre, so each group can
	# be culled by distance (one MultiMesh over the whole city was drawn everywhere: 90 cars x 6.8k
	# triangles in every view, primitives 213k -> 1.44M in the Neon Strip).
	var cells: Dictionary = {}  # Vector2i -> {"body": Array[Transform3D], "paint": Array (per colour)}
	for k2: int in body_xfs.size():
		var xf: Transform3D = body_xfs[k2]
		var key := Vector2i(floori(xf.origin.x / parked_cell_m), floori(xf.origin.z / parked_cell_m))
		if not cells.has(key):
			var pc: Array = []
			for c3: int in colours.size():
				pc.append([])
			cells[key] = {"body": [], "paint": pc}
		(cells[key]["body"] as Array).append(xf)
	for c4: int in colours.size():
		for xf2: Transform3D in (per_colour[c4] as Array):
			var key2 := Vector2i(floori(xf2.origin.x / parked_cell_m), floori(xf2.origin.z / parked_cell_m))
			((cells[key2]["paint"] as Array)[c4] as Array).append(xf2)
	var paint_mats: Array[StandardMaterial3D] = []
	for c: int in colours.size():
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colours[c]
		mat.metallic = 0.7
		mat.roughness = 0.3
		mat.clearcoat_enabled = true
		mat.clearcoat = 1.0
		mat.clearcoat_roughness = 0.05
		paint_mats.append(mat)
	for key3: Vector2i in cells.keys():
		var centre3 := Vector3((float(key3.x) + 0.5) * parked_cell_m, 0.0, (float(key3.y) + 0.5) * parked_cell_m)
		var cell := Node3D.new()
		cell.name = "ParkedCell_%d_%d" % [key3.x, key3.y]
		cell.position = centre3
		parked.add_child(cell)
		var to_local := Transform3D(Basis.IDENTITY, -centre3)
		var bx: Array[Transform3D] = []
		for xf3: Transform3D in (cells[key3]["body"] as Array):
			bx.append(to_local * xf3)
		for lod: int in lods.size():
			var near_m: float = 0.0 if lod == 0 else PARKED_LOD_END_M[lod - 1]
			var far_m: float = PARKED_LOD_END_M[lod]
			var body := MultiMeshInstance3D.new()
			body.name = "Parked_body_lod%d" % lod
			body.multimesh = _multimesh_of(lods[lod]["body"], bx)
			_parked_range(body, near_m, far_m)
			cell.add_child(body)
			for c5: int in colours.size():
				var px: Array[Transform3D] = []
				for xf4: Transform3D in ((cells[key3]["paint"] as Array)[c5] as Array):
					px.append(to_local * xf4)
				if px.is_empty():
					continue
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "Parked_paint_%s_lod%d" % [names[c5], lod]
				mmi.multimesh = _multimesh_of(lods[lod]["paint"], px)
				mmi.material_override = paint_mats[c5]
				_parked_range(mmi, near_m, far_m)
				cell.add_child(mmi)
	stats["parked_cells"] = cells.size()
	stats["parked_cars"] = count
	stats["parked_candidates"] = found.size()
	stats["parked_worst_margin_m"] = worst
	stats["parked_colour_counts"] = per_colour.map(func(a: Array) -> int: return a.size())
	print("CityBuilder: parked cars %d of %d candidates, worst corridor margin %.2f m" % [count, found.size(), worst])


func _footprint_points(centre: Vector2, fwd: Vector2, right: Vector2, half_l: float, half_w: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for a: float in [-1.0, 0.0, 1.0]:
		for b: float in [-1.0, 0.0, 1.0]:
			if a == 0.0 and b == 0.0:
				continue
			out.append(centre + fwd * (a * half_l) + right * (b * half_w))
	return out


## True when any footprint point, at car height, is inside a solid box grown by parked_box_clear_m.
func _hits_solid(pts: Array[Vector2], centre: Vector2, clear: float = -1.0) -> bool:
	var grow: float = parked_box_clear_m if clear < 0.0 else clear
	for box: Dictionary in _solid:
		var o: Vector3 = box["pos"]
		if Vector2(o.x - centre.x, o.z - centre.y).length() > grow + 30.0:
			continue
		var inv: Transform3D = box["inv"]
		var half: Vector3 = (box["half"] as Vector3) + Vector3.ONE * grow
		for p: Vector2 in pts:
			var l: Vector3 = inv * Vector3(p.x, 0.6, p.y)
			if absf(l.x) <= half.x and absf(l.y) <= half.y and absf(l.z) <= half.z:
				return true
	return false


## Box colliders of the props (building boxes are in _solid already), in this node's space.
func _collect_prop_boxes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for body: Variant in _bodies.values():
		for cs: Node in (body as Node).get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D:
				var size: Vector3 = ((cs as CollisionShape3D).shape as BoxShape3D).size
				out.append(_box_entry(_rel_xf(cs, self), size))
	return out


func _box_entry(xf: Transform3D, size: Vector3) -> Dictionary:
	return {"inv": xf.affine_inverse(), "half": size * 0.5, "pos": xf.origin}


func _multimesh_of(mesh: Mesh, xfs: Array) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	return mm


# --- lights, probes, environment ------------------------------------------------------------

func _build_lights(raw: Array, inst: Array) -> void:
	var lights: Array = []
	var lamp_pos: Array[Vector3] = []
	for v: Variant in raw + _dress_lights:
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
	lights.append_array(_wall_wash_lights(inst))
	lights.append_array(_floodlights(inst))
	_split_over_budget(lights)
	var vols: Dictionary = _budget_volumes()
	light_volumes = vols["aabbs"]
	light_volumes_hard = []
	for i: int in light_volumes.size():
		if not bool(vols["soft"][i]):
			light_volumes_hard.append(light_volumes[i])
	var report: Dictionary = CityLights.budget(lights, light_volumes, vols["names"], vols["soft"])
	var keep: Array = report["keep"]
	light_report = {"dropped": report["dropped"], "worst_all": report["worst_all"], "worst_kept": report["worst_kept"],
		"over_volumes": report["over_volumes"], "soft_over": report["soft_over"], "volumes": light_volumes.size(), "log": report["log"]}
	stats["lights_dropped"] = report["dropped"]
	# Sodium lamp heads of the waterfront promenade that survived the budget: [kept, total].
	var lamp_total: int = 0
	var lamp_kept: int = 0
	for i: int in lights.size():
		var sl: Dictionary = lights[i]["src"]
		if String(sl.get("source", "")) == "lamp_head" and String(sl.get("district", "")) == "waterfront":
			lamp_total += 1
			lamp_kept += int(keep[i])
	stats["waterfront_lamps_kept"] = [lamp_kept, lamp_total]
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
		light.distance_fade_enabled = src_name != "floodlight"
		light.distance_fade_begin = light_fade_begin_m
		light.distance_fade_length = light_fade_length_m
		_lighting.add_child(light)
		stats["lights"] = int(stats["lights"]) + 1


## One warm spot per warehouse, spaced along the waterfront stretch: over the road, aimed at the facade.
func _wall_wash_lights(inst: Array) -> Array:
	var out: Array = []
	var path: Path3D = get_node("RacingLine") as Path3D
	var last_s: float = -INF
	for v: Variant in inst:
		if out.size() >= wall_wash_count:
			break
		var d: Dictionary = v
		if String(d["kind"]) != "building" or String(d["district"]) != "waterfront" or not String(d["asset"]).begins_with("bld_waterfront"):
			continue
		var s: float = float(d["s_offset_m"])
		if s < wall_wash_s_min or s > wall_wash_s_max or s - last_s < wall_wash_spacing_m:
			continue
		last_s = s
		var b: Vector3 = _vec(d["position"])
		var road_pt: Vector3 = path.to_global(path.curve.get_closest_point(path.to_local(b)))
		var spot_pos: Vector3 = Vector3(road_pt.x, wall_wash_height_m, road_pt.z)
		var dir: Vector3 = (b + Vector3(0.0, wall_wash_target_m, 0.0) - spot_pos).normalized()
		out.append({"type": "spot", "pos": spot_pos, "range": wall_wash_range_m,
			"src": {"source": "wall_wash", "district": "waterfront", "color": wall_wash_color,
				"energy": wall_wash_energy, "direction": [dir.x, dir.y, dir.z]}})
	return out


## One cool-white spot above each waterfront container stack and gantry crane, aimed down at its base. Layout props in the
## s range, and every placed dressing stack or crane (their s is past floodlight_s_max, so no range test for those).
func _floodlights(inst: Array) -> Array:
	var out: Array = []
	for v: Variant in inst:
		var d: Dictionary = v
		if String(d["kind"]) != "prop" or String(d["district"]) != "waterfront":
			continue
		var asset: String = String(d["asset"])
		if asset != "container_stack" and asset != "gantry_crane":
			continue
		var s: float = float(d["s_offset_m"])
		if s < floodlight_s_min or s > floodlight_s_max:
			continue
		out.append(_floodlight_at(_vec(d["position"])))
	for rec: Dictionary in _dress_recs:
		var kit: String = rec["kit"]
		if (kit == "container_stack" or kit == "gantry_crane") and String(rec["district"]) == "waterfront":
			out.append(_floodlight_at((rec["xf"] as Transform3D).origin))
	stats["floodlights"] = out.size()
	return out


func _floodlight_at(b: Vector3) -> Dictionary:
	var spot_pos: Vector3 = b + Vector3(0.0, floodlight_height_m, 0.0)
	var dir: Vector3 = (b + Vector3(0.0, 4.0, 0.0) - spot_pos).normalized()
	return {"type": "spot", "pos": spot_pos, "range": floodlight_range_m,
		"src": {"source": "floodlight", "district": "waterfront", "color": floodlight_color,
			"energy": floodlight_energy, "direction": [dir.x, dir.y, dir.z]}}


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
	# Gradient night sky with a horizon light-pollution glow; a flat colour read as a dead backdrop behind the skyline.
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = NIGHT_SKY
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = ambient_energy
	env.fog_enabled = true
	env.fog_light_color = Color.html("#101A2E")
	# Depth fog, not exponential: exponential at 0.0045 put 74 percent fog on the bay 300 m out, so the skyline was gone.
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = fog_begin_m
	env.fog_depth_end = fog_end_m
	env.fog_sky_affect = 0.2
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.0
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = moon_color
	moon.light_energy = moon_energy
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-35.0, 140.0, 0.0)
	var start_dir: Vector3 = get_tangent_at(0.0)
	var heading_deg: float = rad_to_deg(atan2(start_dir.x, start_dir.z))
	TimeOfDay.preset(time_of_day).apply_environment(env, moon, heading_deg)  # night: no change; day and sunset turn the moon into the sun
	_lighting.add_child(moon)
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_lighting.add_child(we)


## Lamps and sign fills on or off, window, neon and road materials set for the hour (also restores night).
func _apply_time_of_day() -> void:
	var tod: TimeOfDay = TimeOfDay.preset(time_of_day)
	tod.apply_lights(_lighting)
	tod.apply_materials(self)
	tod.apply_shadow_casters(_geo)


# --- helpers --------------------------------------------------------------------------------

static func _bld_path(asset: String) -> String:
	var p: String = BUILDING_DIR + asset + ".glb"
	return p if ResourceLoader.exists(p) else ISTANBUL_DIR + asset + ".glb"


static func _prop_path(file: String) -> String:
	var p: String = PROP_DIR + file
	return p if ResourceLoader.exists(p) else ISTANBUL_DIR + file


func _scene(path: String) -> PackedScene:
	if not _packed.has(path):
		_packed[path] = load(path) as PackedScene
	return _packed[path]


## Cuts every budgeted mesh that more than 8 omni or 8 spot lights touch into pieces that fewer lights touch,
## so the budget keeps the lights instead of dropping them (MeshSplitter). Same node filter as _budget_volumes.
func _split_over_budget(lights: Array) -> void:
	var pieces: int = 0
	var cut: int = 0
	for n: Node in _all_nodes(_geo):
		if not n is MeshInstance3D or _budget_skip(String(n.name)):
			continue
		var k: int = MeshSplitter.split(n as MeshInstance3D, lights, split_min_excess)
		if k > 0:
			cut += 1
			pieces += k
	stats["split_meshes"] = cut
	stats["split_pieces"] = pieces


static func _budget_skip(nm: String) -> bool:
	return nm.begins_with("ground") or nm.begins_with("decals_") or nm.begins_with("markings_") or nm.begins_with("water_") or nm.begins_with("Parked")


## World AABBs of the meshes that are lit up close: road pieces, building LOD0 and near prop MultiMeshes.
## Far groups (LOD1/LOD2, prop far bands) are left out: their lights are faded by then. The map-sized ground
## plane and the flat paint decals and water are left out too: their AABBs cover the whole circuit.
func _budget_volumes() -> Dictionary:
	var aabbs: Array = []
	var names: PackedStringArray = PackedStringArray()
	var soft: Array = []
	for n: Node in _all_nodes(_geo):
		var nm: String = String(n.name)
		if _budget_skip(nm):
			continue
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and nm not in ["LOD1", "LOD2"]:
			aabbs.append((n as Node3D).global_transform * (n as MeshInstance3D).get_aabb())
			names.append(nm)
			soft.append(n is MultiMeshInstance3D)
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null and "_LOD2" not in nm and "_far_" not in nm:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			aabbs.append((n as Node3D).global_transform * _multimesh_box(mm))
			names.append(nm)
			soft.append(n is MultiMeshInstance3D)
	return {"aabbs": aabbs, "names": names, "soft": soft}


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


## Local AABB of a MultiMesh from its instances (MultiMesh.get_aabb is empty under the headless renderer, which hid the overlaps in tests).
func _multimesh_box(mm: MultiMesh) -> AABB:
	var base: AABB = mm.mesh.get_aabb() if mm.mesh != null else AABB()
	var box: AABB = AABB()
	for i: int in mm.instance_count:
		var b: AABB = mm.get_instance_transform(i) * base
		box = b if i == 0 else box.merge(b)
	return box
