class_name RaceScene
extends Node3D
## Race assembly. Reads a RaceConfig (the exported config, else Router params["config"], else the default),
## loads the track or the development circuit, spawns the opponents and the player through CarFactory,
## and wires the driver, chase camera, HUD, race manager, pause menu and results screen.
## Optional pieces (car FX, speed lines, rain) are attached only when their scene exists.
## Everything under World is rebuilt by retry(); the HUD, pause and results live on for the whole scene.

const CONFIG_PARAM: String = "config"
const GRID_BEAT_S: float = 1.5  ## time on the grid before the countdown starts
const MAX_OPPONENTS: int = 7  ## the grid has 8 slots
const CAR_RESET_HEIGHT_M: float = 0.47  ## car origin height on the line, as in the AI reset
const DEV_WATERMARK: String = "DEV TRACK"
const WATERMARK_PX: int = 180
const WATERMARK_ALPHA: float = 0.22  ## low enough to read the HUD through it, high enough to never be missed
const OVERLAY_LAYER: int = 20  ## above the HUD layer
const AI_NAME: String = "AIDriver"
const SPEED_FX_NODE: String = "SpeedFx"
const FORCED_NITRO_GAP_MS: float = -1000.0  ## AI nitro gate open at any speed
const FORCED_NITRO_CURVATURE: float = 1.0  ## AI nitro allowed in any corner
const ENV_BG: Color = Color(0.03, 0.04, 0.06)
const ENV_AMBIENT: Color = Color(0.25, 0.28, 0.36)
const ENV_AMBIENT_ENERGY: float = 0.5
const HUD_SCENE: String = "res://ui/hud/race_hud.tscn"
const PAUSE_SCENE: String = "res://ui/menus/pause_menu.tscn"
const RESULTS_SCENE: String = "res://ui/menus/results_screen.tscn"
const TOUCH_SCENE: String = "res://vehicles/touch/touch_controls.tscn"
const MENU_SCENE: String = "res://ui/menus/main_menu.tscn"
const GARAGE_SCENE: String = "res://ui/garage/garage.tscn"
const FX_CAR_SCENE: String = "res://fx/car_fx.tscn"
const FX_SPEED_SCENE: String = "res://fx/speed_lines.tscn"
const FX_RAIN_SCENE: String = "res://fx/rain.tscn"

@export var config: RaceConfig  ## null = Router params, else the default RaceConfig

var config_used: RaceConfig
var track: Track
var race: RaceManager
var player: ArcadeCar
var cars: Array[ArcadeCar] = []
var camera: ChaseCamera
var hud: RaceHUD
var pause_menu: PauseMenu
var results_screen: ResultsScreen
var player_ai: AIDriver  ## set only in autopilot mode
var last_results: Array[Dictionary] = []
var dev_track_used: bool = false
var dev_car_used: bool = false
var wrong_way: bool = false

var _world: Node3D = null
var _overlay: CanvasLayer = null
var _watermark: Label = null
var _touch: Node = null
var _grid_t: float = 0.0
var _last_s: float = -1.0
var _names: PackedStringArray = PackedStringArray()
var _default_nitro_gap: float = 0.0
var _default_nitro_curvature: float = 0.0


func _ready() -> void:
	config_used = config if config != null else _config_from_router()
	Settings.attach_viewport(get_viewport())
	_build_chrome()
	_build_race()


## Re-reads the config for the first race. Router params are consumed here.
func _config_from_router() -> RaceConfig:
	var params: Dictionary = Router.take_params()
	var given: Variant = params.get(CONFIG_PARAM, null)
	if given is RaceConfig:
		return given as RaceConfig
	return RaceConfig.new()


func _process(delta: float) -> void:
	if race == null:
		return
	if race.state == RaceManager.State.GRID:
		_grid_t += delta
		if _grid_t >= GRID_BEAT_S:
			race.start_countdown()


func _physics_process(_delta: float) -> void:
	if race == null or track == null or player == null:
		return
	if race.state == RaceManager.State.RACING and player.is_grounded and not wrong_way:
		_last_s = track.get_progress(player.global_position, _last_s)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_car") and race != null and race.state != RaceManager.State.FINISHED:
		reset_player()
		get_viewport().set_input_as_handled()


## Puts the player back on the racing line at its last progress, facing forward, at zero speed.
func reset_player() -> void:
	if player == null or track == null:
		return
	var s: float = _last_s if _last_s >= 0.0 else track.get_progress(player.global_position)
	var p: Vector3 = track.get_point_at(s)
	var t: Vector3 = track.get_tangent_at(s)
	player.reset_to(Transform3D(Basis.looking_at(t, Vector3.UP), p + Vector3(0.0, CAR_RESET_HEIGHT_M, 0.0)))
	_last_s = s


## Fresh race from the grid with the same config. Used by RETRY and by the pause menu's restart.
func retry() -> void:
	if _world != null:
		_world.queue_free()
	_world = null
	if _touch != null:
		_touch.queue_free()
		_touch = null
	race = null
	player = null
	player_ai = null
	camera = null
	track = null
	cars.clear()
	results_screen.visible = false
	last_results.clear()
	_build_race()


## Capture and test hook: keeps the autopilot's nitro gate open so the player burns nitro whenever it has charge.
func force_player_nitro(on: bool) -> void:
	if player_ai == null or player == null:
		return
	if on:
		player_ai.nitro_min_gap_ms = FORCED_NITRO_GAP_MS
		player_ai.nitro_max_curvature = FORCED_NITRO_CURVATURE
		player.nitro_amount = 1.0
	else:
		player_ai.nitro_min_gap_ms = _default_nitro_gap
		player_ai.nitro_max_curvature = _default_nitro_curvature


func _build_chrome() -> void:
	hud = (load(HUD_SCENE) as PackedScene).instantiate() as RaceHUD
	add_child(hud)
	var speed_parent: Node = hud.find_child(SPEED_FX_NODE, true, false)
	if speed_parent != null and ResourceLoader.exists(FX_SPEED_SCENE):
		speed_parent.add_child((load(FX_SPEED_SCENE) as PackedScene).instantiate())
	_overlay = CanvasLayer.new()
	_overlay.name = "Overlay"
	_overlay.layer = OVERLAY_LAYER
	add_child(_overlay)
	pause_menu = (load(PAUSE_SCENE) as PackedScene).instantiate() as PauseMenu
	_overlay.add_child(pause_menu)
	pause_menu.restart_requested.connect(retry)
	results_screen = (load(RESULTS_SCENE) as PackedScene).instantiate() as ResultsScreen
	_overlay.add_child(results_screen)
	results_screen.visible = false
	results_screen.retry_pressed.connect(retry)
	results_screen.menu_pressed.connect(_to_menu)
	results_screen.garage_pressed.connect(_to_garage)
	if not ResourceLoader.exists(GARAGE_SCENE):
		# shortcut: hides the private garage button until ResultsScreen exposes a visibility setter, upgrade then.
		var garage_btn: Button = results_screen.get("_garage_btn") as Button
		if garage_btn != null:
			garage_btn.visible = false


func _build_race() -> void:
	_grid_t = 0.0
	_last_s = -1.0
	wrong_way = false
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	track = _load_track()
	_world.add_child(track)
	_ensure_environment()
	_spawn_cars()
	race = RaceManager.new()
	race.name = "RaceManager"
	race.total_laps = config_used.laps
	_world.add_child(race)
	race.setup(track, cars, player, _names)
	_apply_opponent_skills()
	_setup_player_driver()
	_make_camera()
	race.race_started.connect(_on_race_started)
	race.race_finished.connect(_on_race_finished)
	race.wrong_way_changed.connect(_on_wrong_way)
	hud.bind(player, race, track)
	if dev_track_used:
		_ensure_watermark()
	_attach_optional()
	camera.snap()


## The track scene when it exists and is a Track, else the development circuit.
func _load_track() -> Track:
	if ResourceLoader.exists(config_used.track_scene):
		var packed: PackedScene = load(config_used.track_scene) as PackedScene
		if packed != null:
			var inst: Node = packed.instantiate()
			var t: Track = inst as Track
			if t != null:
				dev_track_used = false
				return t
			inst.free()
			push_error("RaceScene: %s is not a Track scene, using the development circuit" % config_used.track_scene)
	dev_track_used = true
	return DevTrack.build()


## Keeps the track's own WorldEnvironment when it has one, else adds a plain dark one. Both get Settings applied.
func _ensure_environment() -> void:
	var existing: WorldEnvironment = track.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if existing != null and existing.environment != null:
		Settings.apply_to_environment(existing.environment)
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = ENV_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ENV_AMBIENT
	env.ambient_light_energy = ENV_AMBIENT_ENERGY
	var we := WorldEnvironment.new()
	we.name = "DefaultEnvironment"
	we.environment = env
	_world.add_child(we)
	Settings.apply_to_environment(env)


func _spawn_cars() -> void:
	var spec: CarSpec = load(config_used.car_spec_path) as CarSpec
	cars.clear()
	_names = PackedStringArray()
	var opponents: int = clampi(config_used.opponent_count, 0, MAX_OPPONENTS)
	for i: int in opponents:
		var car: ArcadeCar = CarFactory.create(config_used.car_scene, spec, config_used.opponent_paint(i))
		_add_car(car)
		_names.append(_opponent_name(i))
	player = CarFactory.create(config_used.car_scene, spec, config_used.player_paint)
	_add_car(player)
	_names.append(config_used.player_name)
	dev_car_used = bool(player.get_meta("dev_car", false))


func _add_car(car: ArcadeCar) -> void:
	_world.add_child(car)
	cars.append(car)
	if ResourceLoader.exists(FX_CAR_SCENE):
		car.add_child((load(FX_CAR_SCENE) as PackedScene).instantiate())


func _opponent_name(index: int) -> String:
	if index < config_used.opponent_names.size():
		return config_used.opponent_names[index]
	return "Driver %d" % (index + 1)


func _apply_opponent_skills() -> void:
	for i: int in cars.size() - 1:
		var d: AIDriver = cars[i].get_node_or_null(AI_NAME) as AIDriver
		if d != null:
			d.skill = config_used.opponent_skill(i)


## Autopilot: an AIDriver on the player. Otherwise keyboard, controller and touch through PlayerDriver.
func _setup_player_driver() -> void:
	player_ai = null
	if config_used.autopilot:
		player_ai = AIDriver.new()
		player_ai.name = AI_NAME
		player_ai.skill = config_used.autopilot_skill
		player.add_child(player_ai)
		player_ai.setup(track)
		player_ai.set_traffic(cars)
		_default_nitro_gap = player_ai.nitro_min_gap_ms
		_default_nitro_curvature = player_ai.nitro_max_curvature
		return
	var pd := PlayerDriver.new()
	pd.name = "PlayerDriver"
	player.add_child(pd)
	# reset_car is handled once, in _unhandled_input, for both driver paths (PlayerDriver's signal is not wired).
	if ResourceLoader.exists(TOUCH_SCENE):
		_touch = (load(TOUCH_SCENE) as PackedScene).instantiate()
		hud.add_child(_touch)
		(_touch as TouchControls).bind(pd)


## Orbit over the grid, chase at GO. The chase camera follows the player only.
func _make_camera() -> void:
	camera = ChaseCamera.new()
	camera.name = "ChaseCamera"
	_world.add_child(camera)
	camera.set_target(player)
	camera.set_mode(ChaseCamera.Mode.ORBIT)
	camera.make_current()


func _attach_optional() -> void:
	if ResourceLoader.exists(FX_RAIN_SCENE):
		_world.add_child((load(FX_RAIN_SCENE) as PackedScene).instantiate())


func _ensure_watermark() -> void:
	if _watermark != null:
		return
	var tint: Color = Color(MSTheme.TEXT.r, MSTheme.TEXT.g, MSTheme.TEXT.b, WATERMARK_ALPHA)
	_watermark = MSTheme.make_label(DEV_WATERMARK, "bold", WATERMARK_PX, tint, true)
	_watermark.name = "DevWatermark"
	_watermark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_watermark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_watermark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_watermark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Own layer above the overlay, so the results and pause screens cannot cover it.
	var layer := CanvasLayer.new()
	layer.name = "DevWatermarkLayer"
	layer.layer = OVERLAY_LAYER + 1
	add_child(layer)
	layer.add_child(_watermark)


func _on_race_started() -> void:
	camera.set_mode(ChaseCamera.Mode.CHASE)
	if player_ai != null:
		player_ai.set_racing(true)


func _on_race_finished(results: Array[Dictionary]) -> void:
	last_results = results
	var rewards: Dictionary = {}
	for r: Dictionary in results:
		if bool(r.get("is_player", false)):
			rewards = GameState.record_result(config_used.event_id, float(r.get("total_time", 0.0)), int(r.get("position", 0)))
	if player_ai != null:
		player_ai.set_racing(false)
	results_screen.show_results(results, rewards)
	results_screen.visible = true


func _on_wrong_way(is_wrong: bool) -> void:
	wrong_way = is_wrong


func _to_menu() -> void:
	Router.goto(MENU_SCENE)


func _to_garage() -> void:
	if ResourceLoader.exists(GARAGE_SCENE):
		Router.goto(GARAGE_SCENE)
