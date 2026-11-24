extends "res://devtools/capture_scenario.gd"
## Race flow capture on City 01 (the real track, race_config default track_scene), autopilot on, one lap.
## Shots: grid, countdown_2, racing_5s, racing_20s_nitro, results. The player car is the default RaceConfig car.
## Same flow as race_dev but on the city; the dev circuit is not used, so no DevWatermark is expected here.

const SCENE: String = "res://race/race_scene.tscn"
const CITY_SCENE: String = "res://world/city_01/city_01.tscn"
const SETTLE_FRAMES: int = 20
const GRID_SHOT_DELAY_S: float = 0.4
const RACING_SHOT_S: float = 5.0
const NITRO_SHOT_S: float = 20.0
const NITRO_WAIT_MAX_S: float = 3.0
const NITRO_MIN_KMH: float = 150.0  ## speed at which the nitro flame is clearly visible in the shot
const NITRO_SPEED_WAIT_MAX_S: float = 30.0
const RESULTS_WAIT_MAX_S: float = 150.0
const RESULTS_SETTLE_S: float = 2.0
const POLL_FRAMES: int = 1
const CAPTURE_LAPS: int = 1
const TICK_TWO: int = 2

var _scene: RaceScene
var _saw_two: bool = false
var _go_seen: bool = false


func run() -> void:
	var cfg := RaceConfig.new()
	cfg.autopilot = true
	cfg.laps = CAPTURE_LAPS
	cfg.track_scene = CITY_SCENE
	var packed: PackedScene = load(SCENE) as PackedScene
	_scene = packed.instantiate() as RaceScene
	_scene.config = cfg
	tree.root.add_child(_scene)
	await cap.wait_frames(SETTLE_FRAMES)
	_scene.race.countdown_tick.connect(_on_tick)
	_scene.race.race_started.connect(_on_go)
	await cap.wait_seconds(GRID_SHOT_DELAY_S)
	await cap.shot("grid")
	while not _saw_two:
		await cap.wait_frames(POLL_FRAMES)
		if not is_instance_valid(_scene):
			cap.fail("race scene vanished before the countdown")
			return
	await cap.shot("countdown_2")
	while not _go_seen:
		await cap.wait_frames(POLL_FRAMES)
	await cap.wait_seconds(RACING_SHOT_S)
	await cap.shot("racing_5s")
	await cap.wait_seconds(NITRO_SHOT_S - RACING_SHOT_S)
	# Flame strength scales with speed (car_fx: full at 250 km/h), so the shot waits for real speed.
	var waited: float = 0.0
	while _scene.player.speed_kmh < NITRO_MIN_KMH and waited < NITRO_SPEED_WAIT_MAX_S:
		await cap.wait_frames(POLL_FRAMES)
		waited += 1.0 / 60.0
	if _scene.player.speed_kmh < NITRO_MIN_KMH:
		cap.fail("player never reached %.0f km/h for the nitro shot" % NITRO_MIN_KMH)
	print("race_city: nitro shot at %.1f km/h" % _scene.player.speed_kmh)
	_scene.force_player_nitro(true)
	waited = 0.0
	while not _scene.player.nitro_active and waited < NITRO_WAIT_MAX_S:
		await cap.wait_frames(POLL_FRAMES)
		waited += 1.0 / 60.0
	if not _scene.player.nitro_active:
		cap.fail("player nitro never became active for the shot")
	await cap.shot("racing_20s_nitro")
	_scene.force_player_nitro(false)
	waited = 0.0
	while not _scene.results_screen.visible and waited < RESULTS_WAIT_MAX_S:
		await cap.wait_frames(POLL_FRAMES)
		waited += 1.0 / 60.0
	if not _scene.results_screen.visible:
		cap.fail("results screen never appeared")
		return
	await cap.wait_seconds(RESULTS_SETTLE_S)
	await cap.shot("results")


func _on_tick(seconds_left: int) -> void:
	if seconds_left == TICK_TWO:
		_saw_two = true


func _on_go() -> void:
	_go_seen = true
