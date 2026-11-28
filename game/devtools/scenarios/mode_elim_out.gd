extends "res://devtools/capture_scenario.gd"
## Elimination career event on the real race scene (Wharf Elimination: four cars, three laps, autopilot player).
## Waits for the first car out at the end of lap 1 and shoots the HUD just after it: the cars-left readout and the
## "OUT" line. If the player is the car out, the results overlay is the shot instead (named elim_player_out).
## With --elim-slow-rivals the rivals are slowed (capture only) so a rival is the first out and the HUD is the shot.

const SCENE: String = "res://race/race_scene.tscn"
const EVENT: String = "elim_wharf"
const SETTLE_FRAMES: int = 20
const WAIT_STEP_S: float = 1.0 / 60.0
const WAIT_MAX_S: float = 150.0  ## about the first lap of City 01 plus the grid
const AFTER_OUT_S: float = 0.4

var _scene: RaceScene
var _go_seen: bool = false
var _out_car: ArcadeCar = null
var _out_place: int = 0


func _on_car_out(car: ArcadeCar, place: int) -> void:
	if _out_car == null:
		_out_car = car
		_out_place = place


func run() -> void:
	var cfg: RaceConfig = EventCatalog.config_for(EVENT)
	cfg.autopilot = true
	if "--elim-slow-rivals" in OS.get_cmdline_user_args():
		cfg.opponent_skills = [0.6, 0.58, 0.56]  # capture only: a rival goes out first, so the HUD "out" line is the shot
	_scene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	_scene.config = cfg
	tree.root.add_child(_scene)
	await cap.wait_frames(SETTLE_FRAMES)
	if _scene.dev_car_used or _scene.dev_track_used or _scene.race.mode != RaceConfig.MODE_ELIMINATION:
		cap.fail("not the real elimination event with the real car and track")
		return
	_scene.race.race_started.connect(func() -> void: _go_seen = true)
	_scene.race.car_eliminated.connect(_on_car_out)
	var waited: float = 0.0
	while not _go_seen and waited < WAIT_MAX_S:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	if not _go_seen:
		cap.fail("elimination race never started")
		return
	waited = 0.0
	while _out_car == null and waited < WAIT_MAX_S:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	if _out_car == null:
		cap.fail("no car went out within %d s" % int(WAIT_MAX_S))
		return
	await cap.wait_seconds(AFTER_OUT_S)
	if _out_car == _scene.player:
		await cap.shot("elim_player_out")
	else:
		print("ELIM_DEMO out_place=%d cars_left=%d" % [_out_place, _scene.race.active_count()])
		await cap.shot("elim_out_cars_left")
