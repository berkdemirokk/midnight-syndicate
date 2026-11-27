extends "res://tests/test_case.gd"
## Online race polish: the allow-listed track (game/net/net_track.gd, NetConfig.track_for), the live order rows
## (NetRaceAuthority.order_rows) and the client-side check of order messages (NetProtocol.clean_order).


func test_track_allow_list() -> void:
	check(NetConfig.track_for(NetConfig.TRACK_SCENE) == NetConfig.TRACK_SCENE, "the Bosphorus track is allow-listed")
	check(NetConfig.track_for("res://world/city_01/city_01.tscn") == "", "other scenes are refused (development circuit)")
	check(NetConfig.track_for("") == "", "an empty track name means the development circuit")
	check(NetTrack.instance("res://world/missing_track.tscn") == null, "a missing scene gives no track")
	check(NetConfig.track_usable(NetConfig.TRACK_SCENE), "a client can race the Bosphorus track")
	check(NetConfig.track_usable(""), "a client can race the development circuit when the server uses it")
	check(not NetConfig.track_usable("res://world/city_01/city_01.tscn"), "a client refuses a track off the allow-list")
	var t: Track = NetTrack.instance(NetConfig.TRACK_SCENE)
	check(t != null, "the Bosphorus scene instances as a Track")
	if t != null:
		t.free()


func test_clean_order_drops_bad_rows() -> void:
	var raw: Array = [
		{"pid": 1, "place": 1, "lap": 1, "dist": 500.0},
		{"pid": "2", "place": 2, "lap": 1, "dist": 400.0},
		{"pid": 3, "place": 9, "lap": 1, "dist": 300.0},
		{"pid": 4, "place": 3, "lap": 5, "dist": 200.0},
		{"pid": 5, "place": 4, "lap": 0, "dist": NAN},
		{"pid": 6, "place": 5, "lap": 0, "dist": 100},
		{"pid": 7, "place": 0, "lap": 0, "dist": 10.0},
		"junk",
	]
	var rows: Array[Dictionary] = NetProtocol.clean_order(raw, 2)
	check(rows.size() == 1, "only the one valid row survives (got %d)" % rows.size())
	if rows.size() == 1:
		check(rows[0]["pid"] == 1 and rows[0]["place"] == 1 and rows[0]["lap"] == 1 and rows[0]["dist"] == 500.0,
			"the valid row keeps its values")
	check(NetProtocol.clean_order("not an array", 2).is_empty(), "a non-array order is empty")


func test_order_rows_rank_by_distance() -> void:
	var track: Track = DevTrack.build()
	add(track)
	var race := NetRaceAuthority.new()
	race.setup(track, 2, {1: "Ahead", 2: "Behind"}, {1: 0, 2: 1})
	var p: Vector3 = track.get_point_at(race.driver(1).progress + 60.0)
	var t: Vector3 = track.get_tangent_at(race.driver(1).progress + 60.0)
	var st: Dictionary = NetProtocol.make_state(1, Transform3D(Basis.looking_at(-t, Vector3.UP), p + Vector3.UP * 0.47), Vector3.ZERO, 0.0)
	check(race.submit(1, st) == "", "the leading car's state is accepted")
	race.tick(0.5)
	var rows: Array[Dictionary] = race.order_rows()
	check(rows.size() == 2, "every racer has an order row")
	if rows.size() == 2:
		check(rows[0]["pid"] == 1 and rows[0]["place"] == 1, "the car 60 m ahead is first")
		check(rows[1]["pid"] == 2 and rows[1]["place"] == 2, "the other car is second")
		check(float(rows[0]["dist"]) > float(rows[1]["dist"]), "the first row has more metres")
		check(int(rows[0]["lap"]) == 0, "lap 0 before the line is crossed")
	tree.root.remove_child(track)
	track.free()
