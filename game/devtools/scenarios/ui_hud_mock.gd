extends "res://devtools/capture_scenario.gd"
## Race HUD over a dark blurred backdrop with mock values: 187 km/h, gear 4, nitro 60% firing,
## position 2 / 6, lap 2 / 3, running timers, drift popup 1 240, minimap with a sample loop and dots.

const SCENE: String = "res://ui/hud/race_hud.tscn"
const MockRace = preload("res://devtools/scenarios/ui_mock_race.gd")
const MOCK_RACE: String = "res://devtools/scenarios/ui_mock_race.gd"
const MOCK_TRACK: String = "res://devtools/scenarios/ui_mock_track.gd"
const SETTLE_FRAMES: int = 40
const TICK_FRAMES: int = 60
const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const PHONE_W: int = 2556
const PHONE_H: int = 1179
const RIVAL_COUNT: int = 4
const RIVAL_PROGRESS: Array[float] = [0.71, 0.55, 0.30, 0.12]
const PLAYER_PROGRESS: float = 0.42
const START_TIME_S: float = 74.2
const LAP_TIME_S: float = 22.84
const BEST_LAP_S: float = 58.61
const SPEED_KMH: float = 187.4
const GEAR: int = 4
const RPM_NORM: float = 0.82
const NITRO_AMOUNT: float = 0.6
const DRIFT_SCORE: float = 1240.0


func run() -> void:
	cap.set_size(DESKTOP_W, DESKTOP_H)
	var mock_race = MockRace
	var backdrop: CanvasLayer = mock_race.make_backdrop()
	tree.root.add_child(backdrop)
	var race = await _build()
	await cap.wait_frames(SETTLE_FRAMES)
	for i: int in TICK_FRAMES:
		race.race_time += 1.0 / 60.0
		await cap.wait_frames(1)
	await cap.shot("desktop_%dx%d" % [DESKTOP_W, DESKTOP_H])
	# The same HUD in English: the labels are read when the HUD is built, so rebuild it under the language.
	var saved_language: String = Settings.language
	Settings.set_language("en")
	race = await _build()
	await cap.wait_frames(SETTLE_FRAMES)
	for i: int in TICK_FRAMES:
		race.race_time += 1.0 / 60.0
		await cap.wait_frames(1)
	await cap.shot("desktop_en_%dx%d" % [DESKTOP_W, DESKTOP_H])
	Settings.set_language(saved_language)
	MSTheme.set_phone(true)
	cap.set_size(PHONE_W, PHONE_H)
	race = await _build()
	await cap.wait_frames(SETTLE_FRAMES)
	for i: int in TICK_FRAMES:
		race.race_time += 1.0 / 60.0
		await cap.wait_frames(1)
	await cap.shot("iphone_%dx%d" % [PHONE_W, PHONE_H])
	MSTheme.set_phone(false)


## Loads the HUD and binds the mock car, race and track. Returns the mock race so the caller can tick its clock.
func _build() -> Object:
	var mock_race = MockRace
	var hud: RaceHUD = await cap.load_scene(SCENE) as RaceHUD
	var car := ArcadeCar.new()
	var race = mock_race.new()
	race.total_laps = 3
	race.fake_position = 2
	race.fake_cars = 6
	race.fake_lap = 2
	race.fake_best = BEST_LAP_S
	race.fake_lap_time = LAP_TIME_S
	race.race_time = START_TIME_S
	race.rivals.append(car)
	race.fake_progress[car.get_instance_id()] = PLAYER_PROGRESS
	for i: int in RIVAL_COUNT:
		var rival := ArcadeCar.new()
		race.rivals.append(rival)
		race.fake_progress[rival.get_instance_id()] = RIVAL_PROGRESS[i]
	var track: Node3D = (load(MOCK_TRACK) as Script).new()
	hud.bind(car, race, track)
	car.speed_kmh = SPEED_KMH
	car.gear = GEAR
	car.rpm_norm = RPM_NORM
	car.nitro_amount = NITRO_AMOUNT
	car.nitro_active = true
	car.is_drifting = true
	car.drift_score = DRIFT_SCORE
	car.drift_started.emit()
	return race
