extends "res://tests/test_case.gd"
## Race replay: recorder ring buffer and sampling, playback positions against the recording, freezing and
## restoring the cars, director spot choice with a wall in the way, the results REPLAY signal and the grid
## intro end pose. Runs at --fixed-fps 60 so frames are physics ticks.

const FlatWorld = preload("res://tests/helpers/flat_world.gd")
const RECORD_FRAMES: int = 120  ## 2 s at 60 Hz
const POS_TOL_M: float = 0.05
const CAR_SPEED_MS: float = 20.0
const CHECK_SAMPLES: PackedInt32Array = [0, 7, 19, 33, 50]
const WALL_THICKNESS_M: float = 0.5
const WALL_SIZE: Vector3 = Vector3(3.0, 6.0, WALL_THICKNESS_M)  ## narrow: blocks the spot's own line of sight, not its neighbours'
const INTRO_S: float = 1.0
const INTRO_FRAMES: int = 150
const HANDOVER_TOL_M: float = 0.05
const RING_EXTRA: int = 50

var _nodes: Array[Node] = []


func _car(pos: Vector3) -> ArcadeCar:
	var car := ArcadeCar.new()
	car.position = pos
	car.input = VehicleInput.new()
	_nodes.append(add(car))
	return car


func _done() -> void:
	await cleanup(_nodes)
	_nodes.clear()


## The ring holds its size and the oldest samples are overwritten once it is full (no growth while recording).
func test_recorder_ring_is_preallocated_and_wraps() -> void:
	var rec := ReplayRecorder.new()
	_nodes.append(add(rec))
	var cars: Array[ArcadeCar] = [_car(Vector3(0.0, 0.8, 0.0))]
	rec.setup(cars)
	var size_before: int = rec.buffer_size()
	rec.start()
	await frames(RECORD_FRAMES)
	rec.stop()
	check(rec.buffer_size() == size_before, "ring buffer resized while recording: %d -> %d" % [size_before, rec.buffer_size()])
	check(rec.sample_count() >= 60 and rec.sample_count() <= 62, "expected about 60 samples in 2 s at 30 Hz, got %d" % rec.sample_count())
	# Wrap: capture far more samples than the ring holds, straight through the capture call.
	var capacity: int = int(ReplayRecorder.MAX_SECONDS * ReplayRecorder.SAMPLE_HZ)
	rec.start()
	for i: int in capacity + RING_EXTRA:
		rec._capture()
	rec.stop()
	check(rec.sample_count() == capacity, "wrapped ring should hold exactly %d samples, has %d" % [capacity, rec.sample_count()])
	check(rec.buffer_size() == size_before, "buffer size changed after wrap")
	check(rec.duration_s() > 299.0 and rec.duration_s() <= 300.0, "duration after wrap should be about 300 s, is %.2f" % rec.duration_s())
	metric("replay_ring_samples", rec.sample_count())
	await _done()


## Playback at the sample times reproduces the recording within 5 cm, the midpoints are between their neighbours,
## and the cars are frozen and their physics is off while the replay plays, restored on exit.
func test_playback_matches_recording_and_freezes_cars() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground()
	_nodes.append(add(ground))
	var car0: ArcadeCar = _car(Vector3(0.0, 0.8, 0.0))
	var car1: ArcadeCar = _car(Vector3(6.0, 0.8, 0.0))
	car0.linear_velocity = Vector3(0.0, 0.0, -CAR_SPEED_MS)
	await frames(2)
	var rec := ReplayRecorder.new()
	_nodes.append(add(rec))
	var cars: Array[ArcadeCar] = [car0, car1]
	rec.setup(cars)
	rec.start()
	await frames(RECORD_FRAMES)
	rec.stop()
	check(rec.has_data(), "no samples recorded")
	var track: Track = DevTrack.build()
	_nodes.append(add(track))
	await frames(2)
	var player := ReplayPlayer.new()
	_nodes.append(add(player))
	player.setup(rec, cars, track, car0)
	check(car0.freeze and not car0.is_physics_processing(), "cars are not frozen during the replay")
	player.toggle_play()  ## pause, so the clock only moves when the test seeks
	var worst: float = 0.0
	for k: int in CHECK_SAMPLES:
		player.seek(float(k) * ReplayRecorder.SAMPLE_PERIOD_S)
		await frames(2)
		var err: float = car0.global_position.distance_to(rec.origin_at(0, k))
		worst = maxf(worst, err)
		check(err <= POS_TOL_M, "sample %d: replay %.3f m from the recording" % [k, err])
	# Midpoints between two samples sit between them (the car moves in a straight line).
	var k_mid: int = 20
	player.seek((float(k_mid) + 0.5) * ReplayRecorder.SAMPLE_PERIOD_S)
	await frames(2)
	var mid_ref: Vector3 = (rec.origin_at(0, k_mid) + rec.origin_at(0, k_mid + 1)) * 0.5
	check(car0.global_position.distance_to(mid_ref) <= POS_TOL_M, "midpoint off the straight line between samples")
	metric("replay_worst_sample_error_m", worst)
	player.exit_replay()
	await frames(2)
	check(not car0.freeze and car0.is_physics_processing(), "cars were not restored on exit")
	await _done()


## The director never picks a spot whose view of the car is blocked: a wall across the view makes it skip it.
func test_director_skips_blocked_spot() -> void:
	var track: Track = DevTrack.build()
	_nodes.append(add(track))
	await frames(2)
	var director := ReplayDirector.new()
	director.setup(track)
	var p_s: float = director.spot_progress[3] - 10.0  ## spot 3 is 10 m ahead of the car, spot 4 about 75 m ahead: both in range
	var car_pos: Vector3 = track.get_point_at(p_s) + Vector3.UP * 0.8
	var target: Vector3 = car_pos + Vector3.UP * ReplayDirector.LOOK_HEIGHT_M
	var space: PhysicsDirectSpaceState3D = tree.root.get_world_3d().direct_space_state
	var first: int = director.choose_spot(p_s, car_pos, space, [])
	check(first >= 0, "no spot with a clear view on the dev track")
	if first < 0:
		await _done()
		return
	var spot: Vector3 = director.spot_positions[first]
	var dir: Vector3 = (target - spot).normalized()
	var wall := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = WALL_SIZE
	var cs := CollisionShape3D.new()
	cs.shape = shape
	wall.add_child(cs)
	wall.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), (spot + target) * 0.5)
	_nodes.append(add(wall))
	await frames(2)
	space = tree.root.get_world_3d().direct_space_state
	var second: int = director.choose_spot(p_s, car_pos, space, [])
	check(second != first, "director picked spot %d although a wall blocks its view" % first)
	check(second >= 0, "director found no clear alternative spot after the wall")
	if second >= 0:
		check(director.ray_clear(space, director.spot_positions[second], target, []), "spot %d has a blocked view" % second)
	metric("director_blocked_spot", first)
	metric("director_next_spot", second)
	await _done()


## Rival cars occlude: a vehicle-layer blocker between camera and car blocks the view. A camera started inside a
## wall is blocked too (hit_from_inside), so the director never places a camera inside geometry.
func test_vehicles_and_wall_interior_block_view() -> void:
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 2
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 4.0, 4.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	blocker.add_child(cs)
	blocker.position = Vector3(0.0, 2.0, 0.0)
	_nodes.append(add(blocker))
	await frames(2)
	var space: PhysicsDirectSpaceState3D = tree.root.get_world_3d().direct_space_state
	var director := ReplayDirector.new()
	check(not director.ray_clear(space, Vector3(0.0, 2.0, 20.0), Vector3(0.0, 2.0, -20.0), []), "a rival car does not block the view")
	check(not director.ray_clear(space, Vector3(0.0, 2.0, 0.0), Vector3(0.0, 2.0, 20.0), []), "a camera inside a wall is not blocked")
	check(director.ray_clear(space, Vector3(10.0, 2.0, 20.0), Vector3(10.0, 2.0, -20.0), []), "a clear ray is reported blocked")
	await _done()


## The grid intro ends in the chase pose: no jump at the hand-over to CHASE.
func test_grid_intro_ends_at_chase_pose() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground()
	_nodes.append(add(ground))
	var car: ArcadeCar = _car(Vector3(0.0, 0.8, 0.0))
	var cam := ChaseCamera.new()
	cam.target = car
	_nodes.append(add(cam))
	await frames(10)
	cam.start_grid_intro(Vector3(0.0, 14.0, 30.0), Vector3(0.0, 0.8, 0.0), INTRO_S)
	check(cam.intro_active(), "intro did not start")
	var prev: Vector3 = cam.global_position
	var was_active: bool = true
	var handover_step: float = -1.0
	var frames_run: int = 0
	while frames_run < INTRO_FRAMES:
		await frames(1)
		frames_run += 1
		if was_active and not cam.intro_active():
			handover_step = cam.global_position.distance_to(prev)
			break
		prev = cam.global_position
		was_active = cam.intro_active()
	check(handover_step >= 0.0, "intro never ended")
	# After the hand-over the chase pose holds: the next frame moves no more than a normal chase frame does.
	var after: Vector3 = cam.global_position
	await frames(1)
	var chase_step: float = cam.global_position.distance_to(after)
	check(handover_step <= HANDOVER_TOL_M and chase_step <= HANDOVER_TOL_M, "camera jumps at the intro hand-over: %.3f m" % handover_step)
	metric("intro_handover_step_m", handover_step)
	await _done()


## The results screen's REPLAY button emits replay_pressed, and the race scene is wired to it.
func test_results_replay_signal_reaches_race_scene() -> void:
	var packed: PackedScene = load("res://race/race_scene.tscn") as PackedScene
	var scene: RaceScene = packed.instantiate() as RaceScene
	var cfg := RaceConfig.new()
	cfg.autopilot = true
	cfg.laps = 1
	cfg.opponent_count = 1
	cfg.track_scene = "res://does_not_exist/none.tscn"
	cfg.car_scene = "res://does_not_exist/none.tscn"
	scene.config = cfg
	_nodes.append(add(scene))
	await frames(2)
	var heard: Array[int] = [0]
	scene.results_screen.replay_pressed.connect(func() -> void: heard[0] += 1)
	check(scene.results_screen.replay_pressed.is_connected(scene.start_replay), "replay_pressed is not connected to RaceScene.start_replay")
	scene.results_screen._replay_btn.pressed.emit()
	check(heard[0] == 1, "REPLAY button did not emit replay_pressed")
	check(scene.replay == null, "replay started without a recording")
	# With a recording, the same press starts the replay, and leaving it returns to the results.
	check(scene.cars.size() > 0, "race scene has no cars to record")
	if scene.cars.size() > 0:
		scene.recorder.setup(scene.cars)
		scene.recorder.start()
		await frames(RECORD_FRAMES / 4)
		scene.recorder.stop()
		scene.results_screen._replay_btn.pressed.emit()
		check(scene.replay != null, "REPLAY with a recording did not start the replay")
		if scene.replay != null:
			scene.replay.exit_replay()
			await frames(2)
			check(scene.replay == null, "leaving the replay did not clear it")
			check(scene.results_screen.visible, "leaving the replay did not show the results")
	await _done()
