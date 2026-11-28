extends "res://devtools/capture_scenario.gd"
## Race HUD with the touch layer (pause button, steer, brake, nitro and drift zones) over the mock backdrop, on the
## phone layout at 2532x1170 and on an iPad at 2732x2048. Then the pause menu, opened as from the touch pause button.

const HUD_SCENE: String = "res://ui/hud/race_hud.tscn"
const TOUCH_SCENE: String = "res://vehicles/touch/touch_controls.tscn"
const PAUSE_SCENE: String = "res://ui/menus/pause_menu.tscn"
const MockRace = preload("res://devtools/scenarios/ui_mock_race.gd")
const MOCK_TRACK: String = "res://devtools/scenarios/ui_mock_track.gd"
const SETTLE_FRAMES: int = 40
const TICK_FRAMES: int = 60
const PHONE_W: int = 2532
const PHONE_H: int = 1170
const IPAD_W: int = 2732
const IPAD_H: int = 2048
const START_TIME_S: float = 74.2
const SPEED_KMH: float = 187.4
const GEAR: int = 4
const NITRO_AMOUNT: float = 0.6
const PLAYER_PROGRESS: float = 0.42


func run() -> void:
	var backdrop: CanvasLayer = MockRace.make_backdrop()
	tree.root.add_child(backdrop)
	MSTheme.set_phone(true)
	var sizes: Array[Vector2i] = [Vector2i(PHONE_W, PHONE_H), Vector2i(IPAD_W, IPAD_H)]
	for s: Vector2i in sizes:
		cap.set_size(s.x, s.y)
		var race = await _build()
		var touch: TouchControls = await _touch()
		await cap.wait_frames(SETTLE_FRAMES)
		await cap.shot("hud_touch_%dx%d" % [s.x, s.y])
		for i: int in TICK_FRAMES:
			race.race_time += 1.0 / 60.0
			await cap.wait_frames(1)
		var pause: PauseMenu = _add(PAUSE_SCENE) as PauseMenu
		pause.pause()
		await cap.wait_frames(SETTLE_FRAMES)
		await cap.shot("pause_touch_%dx%d" % [s.x, s.y])
		pause.resume()
		await cap.wait_frames(2)
	MSTheme.set_phone(false)


## The HUD with the mock car, race and track, as the HUD test scenario does.
func _build() -> Object:
	var hud: RaceHUD = await cap.load_scene(HUD_SCENE) as RaceHUD
	var car := ArcadeCar.new()
	var race = MockRace.new()
	race.total_laps = 3
	race.fake_position = 2
	race.fake_cars = 6
	race.fake_lap = 2
	race.fake_best = 58.61
	race.fake_lap_time = 22.84
	race.race_time = START_TIME_S
	race.rivals.append(car)
	race.fake_progress[car.get_instance_id()] = PLAYER_PROGRESS
	var track: Node3D = (load(MOCK_TRACK) as Script).new()
	hud.bind(car, race, track)
	car.speed_kmh = SPEED_KMH
	car.gear = GEAR
	car.nitro_amount = NITRO_AMOUNT
	car.nitro_active = true
	return race


## The touch layer, shown on the desktop build as on a phone, laid out for the current viewport.
func _touch() -> TouchControls:
	var touch: TouchControls = _add(TOUCH_SCENE) as TouchControls
	touch.force_visible = true
	touch.visible = true
	touch._on_viewport_resized()
	return touch


## Adds a scene under the root without the harness load_scene, which frees the scene it loaded before.
func _add(path: String) -> Node:
	var n: Node = (load(path) as PackedScene).instantiate()
	tree.root.add_child(n)
	return n
