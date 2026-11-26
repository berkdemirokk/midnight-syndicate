extends "res://tests/test_case.gd"
## Spectator crowd of licensed figures (assets/world/kits/crowd): the figure GLBs load with one surface and within the
## LOD triangle budgets, the placements stand on the land side behind the barriers (never on the road, never within
## 0.6 m of the barrier line), and the placement is deterministic for one track and time of day.

const TRACK: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const MAX_TRIS: Array = [1100, 300]  ## LOD0, LOD1
const MIN_CLEAR_BARRIER_M: float = 0.6


func _tris(mesh: Mesh) -> int:
	var total: int = 0
	for i: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += (idx.size() if not idx.is_empty() else verts.size()) / 3
	return total


func test_figures_load_within_budget() -> void:
	for id: String in EventDressing.FIGURE_IDS:
		for lod: int in 2:
			var path: String = "%scrowd_%s_lod%d.glb" % [EventDressing.CROWD_DIR, id, lod]
			check(FileAccess.file_exists(path), "missing " + path)
			var mesh: Mesh = EventDressing._glb_mesh(path, [])
			check(mesh != null, "no mesh in " + path)
			if mesh == null:
				continue
			check(mesh.get_surface_count() == 1, "%s must have one material, has %d surfaces" % [path, mesh.get_surface_count()])
			var tris: int = _tris(mesh)
			metric("tris_crowd_%s_lod%d" % [id, lod], tris)
			check(tris <= MAX_TRIS[lod], "%s %d tris > %d" % [path, tris, MAX_TRIS[lod]])


func test_placement_clear_of_road_and_barriers() -> void:
	var track: Track = (load(TRACK) as PackedScene).instantiate() as Track
	add(track)
	await frames(2)
	var d := EventDressing.new()
	track.add_child(d)
	d.setup(track, "night")
	await frames(3)
	var edge: float = track.width * 0.5
	var crowd: int = 0
	var min_barrier_gap: float = INF
	for p: Dictionary in d.placements:
		if p.kind != "crowd":
			continue
		crowd += 1
		var lat: float = absf(float(p.lateral))
		check(lat > edge, "figure on the road at lateral %.2f (road edge %.2f)" % [lat, edge])
		var gap: float = lat - (edge + EventDressing.BARRIER_LAT_M)
		min_barrier_gap = minf(min_barrier_gap, gap)
		check(gap >= MIN_CLEAR_BARRIER_M, "figure %.2f m from the barrier line, need >= %.1f" % [gap, MIN_CLEAR_BARRIER_M])
		check(absf(float(p.yaw)) <= EventDressing.CROWD_YAW_RAD + 0.001, "yaw outside +-35 degrees")
		check(float(p.scale) >= EventDressing.CROWD_SCALE_MIN - 0.001 and float(p.scale) <= EventDressing.CROWD_SCALE_MAX + 0.001,
			"scale outside 0.94..1.06")
	check(crowd >= 40, "crowd placed only %d figures" % crowd)
	metric("crowd_figures", crowd)
	metric("min_barrier_gap_m", snappedf(min_barrier_gap, 0.01))
	await cleanup([track])


func test_cards_pick_a_front_cell() -> void:
	var track: Track = (load(TRACK) as PackedScene).instantiate() as Track
	add(track)
	await frames(2)
	var d := EventDressing.new()
	track.add_child(d)
	d.setup(track, "night")
	await frames(3)
	var seen: int = 0
	for p: Dictionary in d.placements:
		if p.kind == "crowd":
			seen += 1
			check(int(p.fig) >= 0 and int(p.fig) < EventDressing.CARD_CELLS, "card cell %d outside the front row" % int(p.fig))
	check(seen > 0, "no crowd cards placed")
	await cleanup([track])


func test_placement_is_deterministic() -> void:
	var track: Track = (load(TRACK) as PackedScene).instantiate() as Track
	add(track)
	await frames(2)
	var first: PackedStringArray = await _signature(track)
	var second: PackedStringArray = await _signature(track)
	check(first.size() > 0, "no placements to compare")
	check(first == second, "crowd placement differs between two runs with the same seed")
	await cleanup([track])


func _signature(track: Track) -> PackedStringArray:
	var d := EventDressing.new()
	track.add_child(d)
	d.setup(track, "night")
	await frames(3)
	var out := PackedStringArray()
	for p: Dictionary in d.placements:
		if p.kind == "crowd":
			out.append("%.3f,%.3f,%.3f,%d" % [p.pos.x, p.pos.y, p.pos.z, int(p.fig)])
	d.queue_free()
	await frames(1)
	return out
