extends "res://devtools/capture_scenario.gd"
## Race evidence for the Kestrel GT-R as the player car: the real race scene, a real track, autopilot player, 5 rivals.
## Track by argument: --track=city (default) | maslak | bogaz. Shots: grid_<track>, racing_10s_<track>, pack_<track>.
## The perf JSON of each shot carries the draw call and primitive peaks to compare with the budgets.

const SCENE: String = "res://race/race_scene.tscn"
const TRACKS: Dictionary = {
	"city": "res://world/city_01/city_01.tscn",
	"maslak": "res://world/istanbul_maslak/istanbul_maslak.tscn",
	"bogaz": "res://world/istanbul_bogaz/istanbul_bogaz.tscn",
}
const CAR_SCENE: String = "res://vehicles/kestrel_gtr/kestrel_gtr.tscn"
const CAR_SPEC: String = "res://vehicles/specs/kestrel_gtr.tres"
const OPPONENTS: int = 5
const SETTLE_FRAMES: int = 20
const WAIT_STEP_S: float = 1.0 / 60.0
const WAIT_MAX_S: float = 40.0
const RACING_SHOT_S: float = 10.0
const PACK_MIN_RIVALS: int = 2
const PACK_RANGE_M: float = 80.0

var _scene: RaceScene
var _track_name: String = "city"
var _go_seen: bool = false
var _go_ms: int = 0


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			_track_name = arg.trim_prefix("--track=")
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = 2
	cfg.opponent_count = OPPONENTS
	cfg.track_scene = TRACKS[_track_name]  # (set before the _sable suffix below)
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	if "--car=sable" in OS.get_cmdline_user_args():  # baseline: the hero, same scenario, to separate car cost from track position
		cfg.car_scene = "res://vehicles/noctra_sable/noctra_sable.tscn"
		cfg.car_spec_path = "res://vehicles/specs/noctra_sable.tres"
		_track_name += "_sable"
	_scene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	_scene.config = cfg
	tree.root.add_child(_scene)
	await cap.wait_frames(SETTLE_FRAMES)
	if _scene.dev_car_used or _scene.dev_track_used or _scene.config_used.car_scene != cfg.car_scene:
		cap.fail("not the real race with the Kestrel GT-R")
		return
	_scene.race.race_started.connect(func() -> void:
		_go_seen = true
		_go_ms = Time.get_ticks_msec())
	await cap.wait_seconds(0.4)
	await cap.shot("grid_%s" % _track_name)
	var waited: float = 0.0
	while not _go_seen and waited < WAIT_MAX_S:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	if not _go_seen:
		cap.fail("race never started")
		return
	var since: float = (Time.get_ticks_msec() - _go_ms) / 1000.0
	if since < RACING_SHOT_S:
		await cap.wait_seconds(RACING_SHOT_S - since)
	await cap.shot("racing_10s_%s" % _track_name)
	waited = 0.0
	while _rivals_in_view() < PACK_MIN_RIVALS and waited < WAIT_MAX_S:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	await cap.shot("pack_%s" % _track_name)


func _rivals_in_view() -> int:
	var n: int = 0
	for c: ArcadeCar in _scene.cars:
		if c == _scene.player:
			continue
		var d: float = c.global_position.distance_to(_scene.player.global_position)
		if d <= PACK_RANGE_M and _scene.camera.is_position_in_frustum(c.global_position):
			n += 1
	return n
