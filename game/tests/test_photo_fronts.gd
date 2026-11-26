extends "res://tests/test_case.gd"
## Photo-textured row houses (PhotoFronts): rows replace the first-row kit buildings of the whole lap, stay out of the
## race corridor, cost a handful of triangles a house, and glow at night only.

const TRACK: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const ROAD_HALF_WIDTH_M: float = 7.0
const HOUSE_MAX_TRIS: int = 24


func _populate(tod: String) -> Array:
	var track: Track = (load(TRACK) as PackedScene).instantiate() as Track
	add(track)
	await frames(2)
	var pf := PhotoFronts.new()
	pf.name = "StreetFronts"
	track.add_child(pf)
	pf.setup(track, tod)
	await frames(2)
	return [track, pf]


func test_houses_fill_the_frontages_outside_the_corridor() -> void:
	var made: Array = await _populate("day")
	var track: Track = made[0]
	var pf: PhotoFronts = made[1]
	check(pf._buildings.size() >= 60, "only %d rows placed" % pf._buildings.size())
	check(pf._replaced.size() == pf._buildings.size(), "rows %d and replaced kit buildings %d differ" % [pf._buildings.size(), pf._replaced.size()])
	var houses: int = 0
	for row: Node3D in pf._buildings:
		var mi := row as MeshInstance3D
		var tris: int = 0
		for s: int in mi.mesh.get_surface_count():
			tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		houses += int(row.get_meta("houses"))
		check(tris <= HOUSE_MAX_TRIS * int(row.get_meta("houses")), "%s has %d triangles" % [row.name, tris])
		check(mi.mesh.get_surface_count() <= 2, "%s has %d surfaces" % [row.name, mi.mesh.get_surface_count()])
		check(absf(track.get_lateral_offset(row.global_position)) >= ROAD_HALF_WIDTH_M,
				"%s stands in the race corridor" % row.name)
	metric("rows", pf._buildings.size())
	metric("houses", houses)
	await cleanup([track])


func test_glow_at_night_only() -> void:
	var day: Array = await _populate("day")
	var pf_day: PhotoFronts = day[1]
	check(not pf_day._facades.is_empty(), "no facade material")
	for m: ShaderMaterial in pf_day._facades:
		check(is_equal_approx(float(m.get_shader_parameter("night")), 0.0), "facade glows by day")
		check(m.get_shader_parameter("albedo_tex") is Texture2D, "facade picture missing")
	await cleanup([day[0]])
	var night: Array = await _populate("night")
	var pf_night: PhotoFronts = night[1]
	for m: ShaderMaterial in pf_night._facades:
		check(float(m.get_shader_parameter("night")) > 0.5, "facade does not glow at night")
		check(m.get_shader_parameter("night_tex") is Texture2D, "night picture missing")
	await cleanup([night[0]])


func test_city_tracks_get_rows() -> void:
	for scene_path: String in ["res://world/istanbul_maslak/istanbul_maslak.tscn", "res://world/city_01/city_01.tscn"]:
		if not PhotoFronts.has_set(scene_path):
			continue
		var track: Track = (load(scene_path) as PackedScene).instantiate() as Track
		add(track)
		await frames(2)
		var pf := PhotoFronts.new()
		track.add_child(pf)
		pf.setup(track, "night")
		await frames(2)
		check(pf._buildings.size() >= 20, "%s: only %d rows" % [scene_path, pf._buildings.size()])
		metric(scene_path.get_file() + "_rows", pf._buildings.size())
		await cleanup([track])
