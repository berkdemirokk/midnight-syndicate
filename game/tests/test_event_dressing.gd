extends "res://tests/test_case.gd"
## Event dressing: kit files and surface counts, shader contract, placement off the race corridor on the Bosphorus
## track, day versus night pieces, and the per-chunk node layout the draw budget depends on.

const TRACK: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const KIT: String = "res://assets/world/kits/event/"
const PNGS: PackedStringArray = ["banner_atlas.png", "crowd_atlas.png", "flag_tr.png", "awning_atlas.png",
	"awning_glow.png", "light_pool.png"]
const GLBS: Dictionary = {"event_barrier_0.glb": 1, "event_barrier_1.glb": 1, "event_barrier_2.glb": 1,
	"event_flag.glb": 2, "event_awning.glb": 1, "event_cafe_set.glb": 1}
const MAX_TRIS: int = 400  ## per kit piece; the whole kit is a few hundred triangles each
const MIN_PER_KIND: Dictionary = {"barrier": 150, "crowd": 40, "flag": 30, "cafe": 5}


func _tris(mesh: Mesh) -> int:
	var total: int = 0
	for i: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += (idx.size() if not idx.is_empty() else verts.size()) / 3
	return total


func test_kit_files_and_budget() -> void:
	for f: String in PNGS:
		check(ResourceLoader.exists(KIT + f), "missing texture " + f)
	for f: String in GLBS:
		check(FileAccess.file_exists(KIT + f), "missing GLB " + f)
		var mesh: Mesh = EventDressing._kit_mesh(f, [])
		check(mesh != null, "no mesh in " + f)
		if mesh == null:
			continue
		check(mesh.get_surface_count() == GLBS[f], "%s surfaces %d, want %d" % [f, mesh.get_surface_count(), GLBS[f]])
		var tris: int = _tris(mesh)
		metric("tris_" + f.get_basename(), tris)
		check(tris <= MAX_TRIS, "%s %d tris > %d" % [f, tris, MAX_TRIS])


func test_shader_contract() -> void:
	var flag: String = FileAccess.get_file_as_string("res://shaders/flag_wave.gdshader")
	check("UV.x" in flag, "flag must be pinned at the pole through UV.x")
	check("VERTEX.z" in flag and "TIME" in flag, "flag wave must be a vertex sine in TIME")
	check("blend_" not in flag and "ALPHA" not in flag, "flag must be opaque, not blended")
	var crowd: String = FileAccess.get_file_as_string("res://shaders/crowd_card.gdshader")
	check("INSTANCE_CUSTOM" in crowd, "crowd cards need per-instance custom data")
	check("discard" in crowd, "crowd cards must alpha-test")
	check("blend_" not in crowd and "ALPHA" not in crowd, "crowd cards must not blend")


func test_placement_off_corridor_on_bogaz() -> void:
	var track: Track = (load(TRACK) as PackedScene).instantiate() as Track
	add(track)
	await frames(2)
	var d := EventDressing.new()
	track.add_child(d)
	d.setup(track, "night")
	await frames(3)
	var kinds: Dictionary = d.kind_counts()
	var barriers: int = 0
	for k: String in kinds:
		if k.begins_with("barrier"):
			barriers += int(kinds[k])
	var counts: Dictionary = {"barrier": barriers, "crowd": int(kinds.get("crowd", 0)),
		"flag": int(kinds.get("flag", 0)), "cafe": int(kinds.get("cafe", 0))}
	for k: String in MIN_PER_KIND:
		check(counts[k] >= MIN_PER_KIND[k], "%s placed %d, want >= %d" % [k, counts[k], MIN_PER_KIND[k]])
		metric("placed_" + k, counts[k])
	var edge: float = track.width * 0.5
	var min_lat: float = INF
	for p: Dictionary in d.placements:
		var lat: float = absf(float(p.lateral))
		min_lat = minf(min_lat, lat)
		check(lat > edge + 0.5, "%s inside the race corridor at lateral %.2f" % [p.kind, lat])
		check(absf(float(p.face.length()) - 1.0) < 0.01, "face direction not normalised for %s" % p.kind)
	metric("min_lateral_m", snappedf(min_lat, 0.01))
	metric("rejected", d.rejected)
	await cleanup([track])


func test_day_builds_no_lights() -> void:
	var track: Track = (load(TRACK) as PackedScene).instantiate() as Track
	add(track)
	await frames(2)
	var d := EventDressing.new()
	track.add_child(d)
	d.setup(track, "day")
	await frames(3)
	for n: Node in d.get_children():
		var nm: String = String(n.name)
		check(not (nm.begins_with("cafe_bulb") or nm.begins_with("cafe_pool") or nm.begins_with("cafe_cable")),
			"day must not build " + nm)
	check(d.get_children().size() > 0, "day still builds barriers, crowds, flags and awnings")
	await cleanup([track])


func test_night_per_chunk_nodes_have_ranges() -> void:
	var track: Track = (load(TRACK) as PackedScene).instantiate() as Track
	add(track)
	await frames(2)
	var d := EventDressing.new()
	track.add_child(d)
	d.setup(track, "night")
	await frames(3)
	var nodes: int = 0
	for n: Node in d.get_children():
		nodes += 1
		if n is GeometryInstance3D:
			var gi: GeometryInstance3D = n as GeometryInstance3D
			check(gi.visibility_range_end > 0.0, "%s has no visibility range" % n.name)
			check(gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts shadows" % n.name)
	metric("event_nodes_night", nodes)
	await cleanup([track])
