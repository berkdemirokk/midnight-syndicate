extends "res://tests/test_case.gd"
## Licensed street fronts (StreetFronts): the nine CC BY models load and stay in budget, the replaced kit buildings keep
## their occluder but not their LOD0 and LOD1, no placed building crosses the race corridor, the placement is
## deterministic, and the night look has lit glass and lights while the day has none.

const TRACK: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const DIR: String = "res://assets/world/kits/street_fronts/"
const SHOPS: PackedStringArray = ["cafe-front", "bookshop", "barber-shop", "florist", "pharmacy", "corner-shop"]
const MANSIONS: PackedStringArray = ["town-mansion", "italianate-mansion", "second-empire-mansion"]
const FILES: PackedStringArray = ["lod0", "lod1", "mirror"]
## LOD0, LOD1 and mirror triangle caps. Lead decision 2026-11-26: LOD1 and the mirror copy drop loose parts instead of
## collapsing (a collapse left stretched triangles across the facades), which lands at 1.5x the first targets; the mansions
## stall at about 18k in LOD0. The frame budget (500 draws / 450k primitives) is what decides, see evidence/.
const SHOP_MAX_TRIS: Array = [6000, 1300, 460]
const MANSION_MAX_TRIS: Array = [19000, 3300, 1400]
const TRI_SLACK: float = 1.02  ## the decimator lands within a few per cent of its target
const SURFACES_LOD0: int = 8
const SURFACES_LOD1: int = 2
const ALLOWED_SURFACES: PackedStringArray = ["M_Flat", "M_Glass"]
const ROAD_HALF_WIDTH_M: float = 7.0  ## the race corridor: the road is 14 m wide, the kerbs sit at +-7 m


func _tris(mesh: Mesh) -> int:
	var total: int = 0
	for i: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += (idx.size() if not idx.is_empty() else verts.size()) / 3
	return total


func _populate(tod: String) -> Array:
	var track: Track = (load(TRACK) as PackedScene).instantiate() as Track
	add(track)
	await frames(2)
	var sf := StreetFronts.new()
	sf.name = "StreetFronts"
	track.add_child(sf)
	sf.setup(track, tod)
	await frames(2)
	return [track, sf]


## Every placed building node. (find_children by name misses the renamed duplicates, so the list is kept by the script.)
func _buildings(sf: StreetFronts) -> Array[Node3D]:
	return sf._buildings.duplicate()


func test_assets_load_and_stay_in_budget() -> void:
	for id: String in SHOPS + MANSIONS:
		var is_shop: bool = id in SHOPS
		var caps: Array = SHOP_MAX_TRIS if is_shop else MANSION_MAX_TRIS
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + id + ".json"))
		check(meta is Dictionary, "meta missing for " + id)
		for lod: int in FILES.size():
			var path: String = DIR + "%s_%s.glb" % [id, FILES[lod]]
			var scene: PackedScene = load(path) as PackedScene
			check(scene != null, "GLB does not load " + path)
			if scene == null:
				continue
			var root: Node = scene.instantiate()
			var tris: int = 0
			var names: Dictionary = {}
			var surfaces: int = 0
			for mi: Node in root.find_children("*", "MeshInstance3D", true, false):
				var mesh: Mesh = (mi as MeshInstance3D).mesh
				tris += _tris(mesh)
				surfaces += mesh.get_surface_count()
				for i: int in mesh.get_surface_count():
					var src: Material = mesh.surface_get_material(i)
					names[src.resource_name if src != null else ""] = true
			root.free()
			metric("%s_lod%d_tris" % [id, lod], tris)
			check(tris <= int(float(caps[lod]) * TRI_SLACK), "%s %s %d tris > %d" % [id, FILES[lod], tris, caps[lod]])
			var max_surfaces: int = SURFACES_LOD0 if lod == 0 else SURFACES_LOD1
			check(surfaces <= max_surfaces, "%s LOD%d has %d surfaces" % [id, lod, surfaces])
			check(names.has("M_Flat"), "%s %s lacks M_Flat" % [id, FILES[lod]])
			## every LOD keeps the glass (cull_islands never drops glass parts): the lit windows are the night look
			check(names.has("M_Glass"), "%s %s lacks M_Glass" % [id, FILES[lod]])
			for k: Variant in names.keys():
				var key: String = String(k)
				check(ALLOWED_SURFACES.has(key) or key.begins_with("T_"), "%s LOD%d surface '%s'" % [id, lod, key])
			var copyright: String = FileAccess.get_file_as_string(DIR + id + ".json")
			check(copyright.contains("vinish.dev"), "%s meta lacks the credit" % id)


func test_replaced_kit_keeps_occluder_loses_lod0_lod1() -> void:
	var pair: Array = await _populate("day")
	var track: Track = pair[0]
	var sf: StreetFronts = pair[1]
	check(sf._replaced.size() > 0, "no kit building was replaced")
	metric("replaced_kit_buildings", sf._replaced.size())
	for root: Node3D in sf._replaced:
		for mi: Node in root.find_children("LOD0", "MeshInstance3D", true, false):
			check(not (mi as MeshInstance3D).visible, "%s LOD0 still visible" % root.name)
		for mi: Node in root.find_children("LOD1", "MeshInstance3D", true, false):
			check(not (mi as MeshInstance3D).visible, "%s LOD1 still visible" % root.name)
		check(root.find_children("Occluder", "OccluderInstance3D", false, false).size() == 1,
				"%s lost its collider occluder" % root.name)
	await cleanup([track])


func test_corridor_and_frontage() -> void:
	var pair: Array = await _populate("day")
	var track: Track = pair[0]
	var sf: StreetFronts = pair[1]
	var placed: Array[Node3D] = _buildings(sf)
	check(placed.size() > 0, "no buildings placed")
	metric("street_front_buildings", placed.size())
	metric("street_front_built_records", sf._buildings.size())
	metric("street_front_replaced", sf._replaced.size())
	metric("street_front_kept_kit", sf._kept)
	var worst: float = 1e9
	for node: Node3D in placed:
		var id: String = String(node.get_meta("asset"))
		var width: float = float(sf._info[id]["width_m"]) * node.global_transform.basis.x.length()
		var depth: float = float(sf._info[id]["depth_m"])
		# the front wall is local z 0 (street side is -Z), the body runs to +Z into the block
		for corner: Vector3 in [Vector3(-width / 2.0, 0.15, 0.0), Vector3(width / 2.0, 0.15, 0.0),
				Vector3(-width / 2.0, 0.15, depth), Vector3(width / 2.0, 0.15, depth)]:
			var lat: float = track.get_lateral_offset(node.to_global(corner))
			worst = minf(worst, lat)
			check(lat > ROAD_HALF_WIDTH_M, "%s corner at lateral %.2f inside the corridor" % [node.name, lat])
	metric("street_front_min_lateral_m", snappedf(worst, 0.01))
	await cleanup([track])


func test_deterministic_placement() -> void:
	var pair: Array = await _populate("day")
	var track: Track = pair[0]
	var sf: StreetFronts = pair[1]
	var a: Array[Dictionary] = sf._fill(18.44, 1234)
	var b: Array[Dictionary] = sf._fill(18.44, 1234)
	check(str(a) == str(b), "same seed gave a different row")
	var c: Array[Dictionary] = sf._fill(14.0, 99)
	var d: Array[Dictionary] = sf._fill(14.0, 99)
	check(str(c) == str(d), "same seed gave a different row (narrow frontage)")
	# the row must cover the frontage without overlap (scale up to FIT_TOL)
	var x: float = -9.22
	for slot: Dictionary in sf._fill(18.44, 1234):
		if slot["id"] in MANSIONS:
			continue
		var w: float = float(sf._info[slot["id"]]["width_m"]) * float(slot["sx"])
		check(float(slot["x"]) - w / 2.0 >= x - 0.05, "slot overlaps its neighbour")
		x = float(slot["x"]) + w / 2.0
	await cleanup([track])


func test_night_lit_glass_and_lights_day_none() -> void:
	var night_pair: Array = await _populate("night")
	var night_track: Track = night_pair[0]
	var sf: StreetFronts = night_pair[1]
	var lights: int = sf.find_children("*", "OmniLight3D", true, false).size()
	check(lights >= 1 and lights <= 6, "night needs 1..6 OmniLights, has %d" % lights)
	metric("night_street_lights", lights)
	check(float(sf._glass.get_shader_parameter("night")) == 1.0, "glass night uniform not 1 at night")
	check(sf._pools.visible, "night pools must show")
	await cleanup([night_track])
	var day_pair: Array = await _populate("day")
	var day_track: Track = day_pair[0]
	var day_sf: StreetFronts = day_pair[1]
	check(day_sf.find_children("*", "OmniLight3D", true, false).size() == 0, "day must have no OmniLight3D")
	check(float(day_sf._glass.get_shader_parameter("night")) == 0.0, "glass night uniform not 0 by day")
	await cleanup([day_track])
