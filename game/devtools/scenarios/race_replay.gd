extends "res://devtools/capture_scenario.gd"
## Replay evidence on City 01: a real one-lap race (real track, real Noctra Sable, 5 opponents, autopilot), then the
## REPLAY button on the results screen. Shots: grid_intro_mid (shot at half progress of the countdown camera move), replay_tv_1..3
## (three different trackside cameras with the player in frame), replay_bumper (forced bumper insert, see below),
## replay_finish_orbit (last seconds of the replay). Fails if the dev track, dev mule or DevWatermark shows up, if
## the replay does not start, or if leaving the replay does not bring the results screen back.

const SCENE: String = "res://race/race_scene.tscn"
const CITY_SCENE: String = "res://world/city_01/city_01.tscn"
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const OPPONENTS: int = 5
const LAPS: int = 1
const SETTLE_FRAMES: int = 20
const WAIT_STEP_S: float = 1.0 / 60.0
const COUNTDOWN_WAIT_MAX_S: float = 25.0
const INTRO_MID_FRACTION: float = 0.5  ## the grid intro's progress at which grid_intro_mid is shot
const RESULTS_WAIT_MAX_S: float = 240.0
const RESULTS_SETTLE_S: float = 1.0
const TV_WAIT_MAX_S: float = 120.0
const TV_SHOTS: int = 3
const TV_SHOT_GAP_S: float = 0.5
const IN_FRAME_MAX_M: float = 25.0  ## a TV shot is taken within this range (the director's long-lens range)
const CENTRE_BAND: float = 0.3  ## fraction of the screen either side of the centre the player must sit in
const BUMPER_LEAD_S: float = 1.5  ## the bumper insert is forced and shot this long after it starts
const BUMPER_LEN_S: float = 4.0
const ORBIT_SHOT_BEFORE_END_S: float = 3.0  ## the finish orbit shot is taken this long before the replay ends
const TICK_THREE: int = 3

var _scene: RaceScene
var _tick_three: bool = false


func run() -> void:
	var cfg := RaceConfig.new()
	cfg.autopilot = true
	cfg.laps = LAPS
	cfg.opponent_count = OPPONENTS
	cfg.track_scene = CITY_SCENE
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	var packed: PackedScene = load(SCENE) as PackedScene
	_scene = packed.instantiate() as RaceScene
	_scene.config = cfg
	tree.root.add_child(_scene)
	await cap.wait_frames(SETTLE_FRAMES)
	if not _is_real_race():
		return
	_scene.race.countdown_tick.connect(_on_tick)
	var waited: float = 0.0
	while not _tick_three and waited < COUNTDOWN_WAIT_MAX_S:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	if not _tick_three:
		cap.fail("countdown never started")
		return
	# Wait on the intro's own progress, not wall time: the shot must be halfway through the move.
	waited = 0.0
	while _scene.camera.intro_progress() < INTRO_MID_FRACTION and _scene.camera.intro_active() and waited < COUNTDOWN_WAIT_MAX_S:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	if not _scene.camera.intro_active() or _scene.camera.intro_progress() >= 1.0:
		cap.fail("grid intro was over before the mid-intro shot")
		return
	await cap.shot("grid_intro_mid")
	print("race_replay: grid_intro_mid at intro progress %.2f" % _scene.camera.intro_progress())
	waited = 0.0
	while not _scene.results_screen.visible and waited < RESULTS_WAIT_MAX_S:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	if not _scene.results_screen.visible:
		cap.fail("results screen never appeared")
		return
	await cap.wait_seconds(RESULTS_SETTLE_S)
	if not _scene.recorder.has_data():
		cap.fail("no replay recording after the race")
		return
	print("race_replay: recording %.1f s, %d samples" % [_scene.recorder.duration_s(), _scene.recorder.sample_count()])
	_scene.results_screen._replay_btn.pressed.emit()
	await cap.wait_frames(2)
	var rp: ReplayPlayer = _scene.replay
	if rp == null:
		cap.fail("REPLAY did not start the replay")
		return
	var director: ReplayDirector = rp.director()
	var spots: Array[int] = []
	waited = 0.0
	while spots.size() < TV_SHOTS and waited < TV_WAIT_MAX_S:
		if director.kind == ReplayDirector.Kind.TV and not spots.has(director.current_spot) and _player_in_frame(rp):
			spots.append(director.current_spot)
			await cap.shot("replay_tv_%d" % spots.size())
			await cap.wait_seconds(TV_SHOT_GAP_S)
		else:
			await cap.wait_frames(1)
			waited += WAIT_STEP_S
	if spots.size() < TV_SHOTS:
		cap.fail("fewer than %d TV spots with the player in frame" % TV_SHOTS)
		return
	# Forced bumper insert, so the shot is deterministic. The director still skips it when its view is blocked.
	director.force_insert(ReplayDirector.Kind.BUMPER, rp.time_s(), BUMPER_LEN_S)
	await cap.wait_seconds(BUMPER_LEAD_S)
	if director.kind != ReplayDirector.Kind.BUMPER:
		cap.fail("bumper insert skipped (view blocked) at replay %.1f s" % rp.time_s())
		return
	await cap.shot("replay_bumper")
	waited = 0.0
	while rp.time_s() < rp.duration_s() - ORBIT_SHOT_BEFORE_END_S and waited < RESULTS_WAIT_MAX_S:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	if director.kind != ReplayDirector.Kind.ORBIT:
		cap.fail("finish orbit not active near the end of the replay")
		return
	await cap.shot("replay_finish_orbit")
	rp.exit_replay()
	await cap.wait_frames(3)
	if not _scene.results_screen.visible or _scene.replay != null:
		cap.fail("leaving the replay did not return to the results screen")
		return
	print("race_replay: TV spots %s, cuts %d" % [str(spots), director.cut_count])


## Fails the run when the dev track, the dev mule or the dev watermark is in play.
func _is_real_race() -> bool:
	if _scene.dev_track_used or _scene.dev_car_used or _scene.find_child("DevWatermark", true, false) != null:
		cap.fail("dev track, dev mule or DevWatermark present: not the real race")
		return false
	if _scene.config_used.track_scene != CITY_SCENE or _scene.config_used.car_scene != CAR_SCENE:
		cap.fail("race config is not City 01 with the Noctra Sable")
		return false
	return true


## The player's replay pose is near the middle of the screen (within 30 % of each axis) and not too far away.
func _player_in_frame(rp: ReplayPlayer) -> bool:
	var cam: Camera3D = rp.camera()
	var p: Vector3 = _scene.player.global_position + Vector3.UP * ReplayDirector.LOOK_HEIGHT_M
	if cam.is_position_behind(p) or not cam.is_position_in_frustum(p) or cam.global_position.distance_to(p) > IN_FRAME_MAX_M:
		return false
	var sp: Vector2 = cam.unproject_position(p)
	var vp: Vector2 = tree.root.get_visible_rect().size
	return absf(sp.x - vp.x * 0.5) < vp.x * CENTRE_BAND and absf(sp.y - vp.y * 0.5) < vp.y * CENTRE_BAND


func _on_tick(seconds_left: int) -> void:
	if seconds_left == TICK_THREE:
		_tick_three = true
