extends "res://tests/test_case.gd"
## Photo-textured row houses (PhotoFronts): houses fill the land-side frontages, stay out of the race corridor, cost a
## handful of triangles each, and glow at night only.

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
	check(pf._buildings.size() >= 40, "only %d houses placed" % pf._buildings.size())
	check(pf._replaced.size() >= 10, "only %d kit frontages replaced" % pf._replaced.size())
	for house: Node3D in pf._buildings:
		var mi := house as MeshInstance3D
		var tris: int = 0
		for s: int in mi.mesh.get_surface_count():
			tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		check(tris <= HOUSE_MAX_TRIS, "%s has %d triangles" % [house.name, tris])
		check(absf(track.get_lateral_offset(house.global_position)) >= ROAD_HALF_WIDTH_M,
				"%s stands in the race corridor" % house.name)
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
