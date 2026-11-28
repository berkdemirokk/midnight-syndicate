extends "res://devtools/capture_scenario.gd"
## Drift career event on the real race scene (Harbour Drift, autopilot player, no rivals). The autopilot does not
## drift, so the scenario starts one drift chain on the player car by hand (the same flags and signal the car sets),
## then ends it with drift_ended so the banked score reaches RaceManager and the HUD. Shots: drift_hud_chain (the
## chain running: total plus "+chain", clock counting down) and drift_hud_banked (the chain banked, the total shown).

const SCENE: String = "res://race/race_scene.tscn"
const EVENT: String = "drift_harbour"
const SETTLE_FRAMES: int = 20
const WAIT_STEP_S: float = 1.0 / 60.0
const WAIT_MAX_S: float = 40.0
const RACE_LEAD_S: float = 12.0  ## race time before the chain starts, so the clock has moved on
const CHAIN_SCORE: float = 412.0
const BANKED_SCORE: float = 640.0
const CHAIN_HOLD_S: float = 0.2

var _scene: RaceScene
var _go_seen: bool = false


func run() -> void:
	var cfg: RaceConfig = EventCatalog.config_for(EVENT)
	cfg.autopilot = true
	_scene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	_scene.config = cfg
	tree.root.add_child(_scene)
	await cap.wait_frames(SETTLE_FRAMES)
	if _scene.dev_car_used or _scene.dev_track_used or _scene.race.mode != RaceConfig.MODE_DRIFT:
		cap.fail("not the real drift event with the real car and track")
		return
	_scene.race.race_started.connect(func() -> void: _go_seen = true)
	var waited: float = 0.0
	while not _go_seen and waited < WAIT_MAX_S:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	if not _go_seen:
		cap.fail("drift race never started")
		return
	await cap.wait_seconds(RACE_LEAD_S)
	var car: ArcadeCar = _scene.player
	car.drift_started.emit()
	car.is_drifting = true
	car.drift_score = CHAIN_SCORE
	await cap.wait_seconds(CHAIN_HOLD_S)
	await cap.shot("drift_hud_chain")
	car.is_drifting = false
	car.drift_score = 0.0
	car.drift_ended.emit(BANKED_SCORE)
	await cap.wait_seconds(0.2)
	await cap.shot("drift_hud_banked")
