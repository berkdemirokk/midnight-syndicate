extends "res://tests/test_case.gd"
## StreetProps: CC0 street furniture in front of the photo rows on every track, clear of the race corridor.

const TRACKS: Array[String] = ["res://world/istanbul_bogaz/istanbul_bogaz.tscn", "res://world/istanbul_maslak/istanbul_maslak.tscn", "res://world/city_01/city_01.tscn"]


func test_every_track_gets_props_outside_the_corridor() -> void:
	for path: String in TRACKS:
		var track: Track = (load(path) as PackedScene).instantiate() as Track
		add(track)
		await frames(2)
		var pf := PhotoFronts.new()
		track.add_child(pf)
		pf.setup(track, "day")
		await frames(2)
		var total: int = 0
		for k: String in pf.props.placed:
			total += int(pf.props.placed[k])
		metric(path.get_file() + "_props", total)
		metric(path.get_file() + "_kinds", pf.props.placed.keys().size())
		check(total >= 40, "%s: only %d props" % [path.get_file(), total])
		check(pf.props.get_child_count() > 0, "%s: no MultiMesh built" % path.get_file())
		for cell: Vector2i in pf.props._cells:  # the headless renderer keeps no MultiMesh data: check the placement list
			for prop: String in pf.props._cells[cell]:
				for xf: Transform3D in pf.props._cells[cell][prop]:
					var at: Vector3 = xf.origin
					check(absf(track.get_lateral_offset(at)) >= StreetProps.CLEAR_M - 0.01, "%s prop in the corridor at %s" % [path.get_file(), at])
		await cleanup([track])
