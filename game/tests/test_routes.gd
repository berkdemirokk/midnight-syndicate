extends "res://tests/test_case.gd"
## Route variants: Track.set_reversed runs a track the other way on the existing geometry. Checks the mirrored racing
## line (points, tangents, curvature), the grid slots (distance behind the new start, facing the new direction), the
## round trip back to the authored direction, and one full AI lap through RaceManager on the reversed Bogaz coast.

const BOGAZ: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const SAMPLE_STEP_M: float = 60.0
const POS_TOL_M: float = 0.5
const GRID_TOL_M: float = 2.0
const FACE_DOT_MIN: float = 0.8
const AI_COUNT: int = 3
const RACE_LIMIT_S: float = 180.0
const HZ: float = 60.0

var _results: Array[Dictionary] = []
var _finished_events: int = 0


func _on_finished(results: Array[Dictionary]) -> void:
	_finished_events += 1
	_results = results


func _load_track() -> Track:
	var t: Track = (load(BOGAZ) as PackedScene).instantiate() as Track
	add(t)
	return t


func _offsets(length: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var o: float = 0.0
	while o < length:
		out.append(o)
		o += SAMPLE_STEP_M
	return out


func test_reverse_line_mirrors_forward() -> void:
	var track: Track = await _load_track()
	var len: float = track.length
	var offs: PackedFloat32Array = _offsets(len)
	var fwd_pos: PackedVector3Array = PackedVector3Array()
	var fwd_curv: PackedFloat32Array = PackedFloat32Array()
	for o: float in offs:
		fwd_pos.append(track.get_point_at(o))
		fwd_curv.append(track.get_curvature(o))
	check(not track.is_reversed(), "track starts in the authored direction")
	track.set_reversed(true)
	check(track.is_reversed(), "set_reversed(true) did not stick")
	check(absf(track.length - len) < 0.01, "reversing changed the lap length")
	var worst: float = 0.0
	var curv_worst: float = 0.0
	for i: int in offs.size():
		var p_rev: Vector3 = track.get_point_at(len - offs[i])
		worst = maxf(worst, p_rev.distance_to(fwd_pos[i]))
		curv_worst = maxf(curv_worst, absf(track.get_curvature(len - offs[i]) + fwd_curv[i]))
	metric("reverse_point_error_max_m", snappedf(worst, 0.001))
	metric("reverse_curvature_error_max", snappedf(curv_worst, 0.000001))
	check(worst < POS_TOL_M, "reversed line is %.2f m off the mirrored authored line" % worst)
	check(curv_worst < 1e-4, "curvature did not flip sign: worst error %.6f" % curv_worst)
	track.set_reversed(false)
	var back: float = 0.0
	for i: int in offs.size():
		back = maxf(back, track.get_point_at(offs[i]).distance_to(fwd_pos[i]))
	check(back < 0.001, "round trip changed the line by %.4f m" % back)
	await cleanup([track])


func test_reverse_grid_faces_new_direction() -> void:
	var track: Track = await _load_track()
	var slots: int = track.get_node("StartGrid").get_child_count()
	var len: float = track.length
	# authored slot i: progress s, lateral offset, and the authored line point at the mirror distance d = -s
	var auth_s := PackedFloat32Array()
	var auth_lat := PackedFloat32Array()
	var auth_mirror_pt: Array[Vector3] = []
	var auth_dy := PackedFloat32Array()  # slot height above the line at its own progress
	var auth_line_y := PackedFloat32Array()
	var fwd_ok: int = 0
	for xf: Transform3D in _grid_transforms(track):
		var s: float = track.get_progress(xf.origin)
		auth_s.append(s)
		auth_lat.append(track.get_lateral_offset(xf.origin))
		auth_mirror_pt.append(track.get_point_at(fposmod(-s, len)))
		auth_dy.append(xf.origin.y - track.get_point_at(s).y)
		auth_line_y.append(track.get_point_at(s).y)
		if (-xf.basis.z).dot(track.get_tangent_at(s)) > FACE_DOT_MIN:
			fwd_ok += 1
	check(fwd_ok == slots, "authored grid: only %d of %d slots face the line" % [fwd_ok, slots])
	metric("authored_grid_progress_first_m", snappedf(auth_s[0], 0.1))
	metric("authored_grid_progress_last_m", snappedf(auth_s[slots - 1], 0.1))
	track.set_reversed(true)
	var rev_ok: int = 0
	var progress_worst: float = 0.0
	var mirror_worst: float = 0.0
	var height_worst: float = 0.0
	var line_dy_worst: float = 0.0
	var i: int = 0
	for xf: Transform3D in _grid_transforms(track):
		var s: float = track.get_progress(xf.origin)
		# mirror keeps the numeric progress: the reversed line at s is the authored line at len - s
		var ds: float = absf(wrapf(s - auth_s[i], -len * 0.5, len * 0.5))
		progress_worst = maxf(progress_worst, ds)
		# slot sits on the authored mirror point, offset by its lateral distance from the road centre
		var c: Vector3 = auth_mirror_pt[i]
		var planar: float = Vector2(xf.origin.x - c.x, xf.origin.z - c.z).length()
		mirror_worst = maxf(mirror_worst, absf(planar - absf(auth_lat[i])))
		height_worst = maxf(height_worst, absf(xf.origin.y - (c.y + auth_dy[i])))
		line_dy_worst = maxf(line_dy_worst, absf(c.y - auth_line_y[i]))  # how far the old absolute-height copy was off
		if (-xf.basis.z).dot(track.get_tangent_at(s)) > FACE_DOT_MIN:
			rev_ok += 1
		i += 1
	metric("reverse_grid_progress_error_max_m", snappedf(progress_worst, 0.01))
	metric("reverse_grid_mirror_error_max_m", snappedf(mirror_worst, 0.01))
	metric("reverse_grid_height_error_max_m", snappedf(height_worst, 0.01))
	metric("grid_line_elevation_delta_max_m", snappedf(line_dy_worst, 0.01))
	check(height_worst < 0.05, "reversed slots are %.2f m off their height above the line" % height_worst)
	check(rev_ok == slots, "reversed grid: only %d of %d slots face the new direction" % [rev_ok, slots])
	check(progress_worst < GRID_TOL_M, "reversed slots moved %.2f m of progress" % progress_worst)
	check(mirror_worst < GRID_TOL_M, "reversed slots are %.2f m off the mirror of the authored grid" % mirror_worst)
	track.set_reversed(false)
	await cleanup([track])


func _grid_transforms(track: Track) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i: int in track.get_node("StartGrid").get_child_count():
		out.append(track.get_grid_transform(i))
	return out


func _make_car(skill: float, seed_value: int) -> ArcadeCar:
	var car := ArcadeCar.new()
	car.spec = load("res://vehicles/specs/noctra_sable.tres") as CarSpec
	add(car)
	var d := AIDriver.new()
	d.name = "AIDriver"
	d.skill = skill
	d.noise_seed = seed_value
	car.add_child(d)
	return car


func test_ai_cars_finish_one_lap_reversed() -> void:
	var track: Track = await _load_track()
	track.set_reversed(true)
	var manager := RaceManager.new()
	manager.total_laps = 1
	add(manager)
	var cars: Array[ArcadeCar] = []
	var names: PackedStringArray = PackedStringArray()
	for i: int in AI_COUNT:
		cars.append(_make_car(1.0 - 0.03 * float(i), i + 1))
		names.append("AI %d" % (i + 1))
	_finished_events = 0
	_results.clear()
	manager.race_finished.connect(_on_finished)
	manager.setup(track, cars, null, names)
	manager.start_countdown()
	var limit_ticks: int = roundi(RACE_LIMIT_S * HZ)
	var ticks: int = 0
	while manager.state != RaceManager.State.FINISHED and ticks < limit_ticks:
		await frames(1)
		ticks += 1
	metric("reversed_race_time_s", snappedf(manager.race_time, 0.01))
	check(manager.state == RaceManager.State.FINISHED, "reversed 1-lap race did not finish in %.0f s" % RACE_LIMIT_S)
	check(_finished_events == 1, "race_finished fired %d times" % _finished_events)
	check(_results.size() == AI_COUNT, "%d cars classified, expected %d" % [_results.size(), AI_COUNT])
	var nodes: Array[Node] = [manager, track]
	for car: ArcadeCar in cars:
		nodes.append(car)
	await cleanup(nodes)


## Every shipped loop reverses cleanly: each reversed slot faces the new direction, stays on the road and keeps its
## height above the line (City 01 and Maslak have no reverse lap test yet; this guards their grids).
func test_reverse_grid_on_every_track() -> void:
	for path: String in ["res://world/city_01/city_01.tscn", BOGAZ, "res://world/istanbul_maslak/istanbul_maslak.tscn"]:
		var track: Track = (load(path) as PackedScene).instantiate() as Track
		add(track)
		await frames(1)
		var slots: int = track.get_node("StartGrid").get_child_count()
		var dy: PackedFloat32Array = PackedFloat32Array()
		for xf: Transform3D in _grid_transforms(track):
			dy.append(xf.origin.y - track.get_point_at(track.get_progress(xf.origin)).y)
		track.set_reversed(true)
		var ok: int = 0
		var lat_worst: float = 0.0
		var dy_worst: float = 0.0
		var i: int = 0
		for xf: Transform3D in _grid_transforms(track):
			var s: float = track.get_progress(xf.origin)
			if (-xf.basis.z).dot(track.get_tangent_at(s)) > FACE_DOT_MIN:
				ok += 1
			lat_worst = maxf(lat_worst, absf(track.get_lateral_offset(xf.origin)))
			dy_worst = maxf(dy_worst, absf(xf.origin.y - track.get_point_at(s).y - dy[i]))
			i += 1
		var key: String = path.get_file().get_basename()
		metric("reverse_grid_lateral_max_m_" + key, snappedf(lat_worst, 0.01))
		check(slots > 0 and ok == slots, "%s reversed: %d of %d slots face the new direction" % [key, ok, slots])
		check(lat_worst < track.width * 0.5, "%s reversed: a slot is %.1f m off the line (road half width %.1f)" % [key, lat_worst, track.width * 0.5])
		check(dy_worst < 0.05, "%s reversed: slot height above the line off by %.2f m" % [key, dy_worst])
		await cleanup([track])
