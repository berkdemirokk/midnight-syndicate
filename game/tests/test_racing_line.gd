extends "res://tests/test_case.gd"
## Racing line (world/track.gd get_line_offset, get_line_speed): stays inside the road edges, sits on the inside
## of the sharpest bend, and a reversed track keeps both rules and restores exactly. Geometry only, no physics.

const TestTrack = preload("res://tests/helpers/test_track.gd")
const SAMPLE_M: float = 2.0
const EDGE_TOL_M: float = 0.05
const MIN_APEX_OFFSET_M: float = 1.0  ## the line must leave the centre at the sharpest bend by at least this


func _check_line(track: Track, what: String) -> void:
	var apex_s: float = 0.0
	var apex_k: float = 0.0
	var s: float = 0.0
	while s < track.length:
		var off: float = track.get_line_offset(s)
		var span: Vector2 = track.get_road_span(s)
		check(off >= span.x + Track.LINE_MARGIN_M - EDGE_TOL_M and off <= span.y - Track.LINE_MARGIN_M + EDGE_TOL_M,
			"%s line leaves the road at %.1f m: offset %.2f" % [what, s, off])
		var speed: float = track.get_line_speed(s)
		check(speed > 0.0 and speed <= track.max_speed + EDGE_TOL_M, "%s line speed %.2f at %.1f m" % [what, speed, s])
		var k: float = track.get_curvature(s)
		if absf(k) > absf(apex_k):
			apex_k = k
			apex_s = s
		s += SAMPLE_M
	var apex_off: float = track.get_line_offset(apex_s)
	check(signf(apex_off) == signf(apex_k) and absf(apex_off) >= MIN_APEX_OFFSET_M,
		"%s apex line not on the inside: offset %.2f, curvature %.4f at %.1f m" % [what, apex_off, apex_k, apex_s])
	metric("%s_apex_offset_m" % what, snappedf(apex_off, 0.01))
	metric("%s_apex_line_speed_ms" % what, snappedf(track.get_line_speed(apex_s), 0.01))
	metric("%s_apex_centre_speed_ms" % what, snappedf(track.get_target_speed(apex_s), 0.01))


func test_racing_line_inside_road_and_on_apex() -> void:
	var track: Track = TestTrack.build()
	add(track)
	_check_line(track, "forward")
	var nodes: Array[Node] = [track]
	await cleanup(nodes)


func test_racing_line_reversed_track() -> void:
	var track: Track = TestTrack.build()
	add(track)
	var before: PackedFloat32Array = PackedFloat32Array()
	for i: int in 40:
		before.append(track.get_line_offset(float(i) * 9.0))
	track.set_reversed(true)
	_check_line(track, "reversed")
	track.set_reversed(false)
	for i: int in 40:
		check(absf(track.get_line_offset(float(i) * 9.0) - before[i]) < EDGE_TOL_M,
			"line not restored after a reverse round trip at %.0f m" % (float(i) * 9.0))
	var nodes: Array[Node] = [track]
	await cleanup(nodes)
