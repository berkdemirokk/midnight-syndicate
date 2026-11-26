class_name RaceScene
extends Node3D
## Race assembly. Reads a RaceConfig (the exported config, else Router params["config"], else the default),
## loads the track or the development circuit, spawns the opponents and the player through CarFactory,
## and wires the driver, chase camera, HUD, race manager, pause menu and results screen.
## Optional pieces (car FX, speed lines, rain) are attached only when their scene exists.
## Everything under World is rebuilt by retry(); the HUD, pause and results live on for the whole scene.

const CONFIG_PARAM: String = "config"
const GRID_BEAT_S: float = 1.5  ## time on the grid before the countdown starts
const GRID_INTRO_BACK_M: float = 30.0  ## grid intro starts this far behind the pack centre...
const GRID_INTRO_UP_M: float = 14.0  ## ...and this high, then sweeps down to the chase pose at GO
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
## Render layers (see also PlanarReflection.excluded_layers, rain.gd):
##   bit 0 (layer 1)  default: everything, incl. cars, track props, the wet road is also on bit 1 only
##   bit 1 (layer 2)  wet road (M_Asphalt meshes only): the planar mirror leaves it out
##   bit 9 (layer 10) rain particles: the planar mirror leaves them out
## A camera draws an object when ANY of its layer bits is in the cull mask, so an object the mirror must skip
## has NO default bit and no car fill bit, and the mirror also excludes bit 19 (see PlanarReflection.excluded_layers).
##   bit 2 (layer 3)  car LOD0 meshes (CarLod.DETAIL_LAYER_BIT), instead of bit 0: the planar mirror leaves them out
##   bit 3 (layer 4)  mirror-only copy of the car LOD1 (CarLod.MIRROR_LAYER_BIT): every camera except the mirror leaves it out
##   bit 4 (layer 5)  small props, dressing and parked cars (MIRROR_SKIP_BIT), instead of bit 0: left out of the mirror
##   bit 19 (layer 20) car fill: every car mesh also has it; only the car fill light sees it, so the fill
##                     lights cars and nothing else (no road, no buildings).
const ROAD_LAYER_BIT: int = 1 << 1
const CAR_FILL_LAYER: int = 19
const MIRROR_SKIP_BIT: int = 1 << 4
const CAR_LIGHT_MASK: int = (1 << CAR_FILL_LAYER) | CarLod.MIRROR_LAYER_BIT  ## fill and rim lights: car meshes and their mirror copy
## Prop MultiMesh nodes ("<prop file>_<chunk>_<mesh>") whose file name holds one of these stay out of the mirror.
const MIRROR_SKIP_PROPS: PackedStringArray = ["bench", "litter_bin", "planter", "newspaper", "bollard", "cone", "street_", "_LOD2"]  ## street_ = the street detail kit (dumpsters, AC units, fire escapes...)
const MIRROR_KEEP_PROPS: PackedStringArray = ["street_signal", "street_glow"]  ## lit pieces whose reflection on the wet road is worth the draws
const MIRROR_SKIP_ROOTS: PackedStringArray = ["Dressing", "ParkedCars", "SecondRow", "LOD2_Batches"]  ## far building batches: too small in the road reflection to pay for
const ASPHALT_MATERIAL_NAME: String = "M_Asphalt"
const ASPHALT_SHADER_PATH: String = "res://shaders/wet_asphalt.gdshader"
const SHADOW_PROXY_NAME: String = "SunShadowProxy"
const FILL_LIGHT_NAME: String = "CarFillLight"
const RIM_LIGHT_NAME: String = "CarRimLight"
const UNDERGLOW_RIVAL: Array[Color] = [Color(1.0, 0.2, 0.55), Color(0.2, 0.75, 1.0), Color(1.0, 0.55, 0.15), Color(0.35, 1.0, 0.5)]  ## rival underglow colours, by grid slot
const ISTANBUL_NAMES: PackedStringArray = ["Mert", "Emir", "Kerem", "Deniz", "Aras", "Baran", "Selim"]  ## rival names on the Istanbul tracks
const STREET_FRONTS_SCRIPT: String = "res://world/street_fronts/street_fronts.gd"  ## optional module: setup(track, time_of_day_id)
const BOGAZ_TRACK_KEY: String = "istanbul_bogaz"  ## track scenes with this in their path get the Bosphorus scenery
const REFLECTION_NAME: String = "PlanarReflection"
const WORLD_LAYER_MASK: int = 1  ## physics layer 1: world and static, the road surface
const PLANE_PROBE_UP_M: float = 1.0  ## the road probe starts this far above the car origin...
const PLANE_PROBE_DOWN_M: float = 6.0  ## ...and looks this far down
const PLANE_FOLLOW_RATE: float = 12.0  ## 1/s: the mirror plane eases to the road height under the car

@export var config: RaceConfig  ## null = Router params, else the default RaceConfig

var config_used: RaceConfig
var tod: TimeOfDay = TimeOfDay.preset("night")  ## the hour of this race, from config_used.time_of_day
var track: Track
var race: RaceManager
var player: ArcadeCar
var cars: Array[ArcadeCar] = []
var camera: ChaseCamera
var hud: RaceHUD
var pause_menu: PauseMenu
var results_screen: ResultsScreen
var player_ai: AIDriver  ## set only in autopilot mode
var recorder: ReplayRecorder  ## records the race for the replay, see start_replay()
var replay: ReplayPlayer  ## null unless a replay is playing
var _post_fx: PostFx = null  ## speed blur, grade and vignette under the HUD
var _speed_lines: Node = null  ## res://fx/speed_lines.tscn instance under the HUD's SpeedFx node
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
var _reflection: PlanarReflection = null  ## wet road mirror; null unless High, or when the track has no wet asphalt
var _road_mats: Array[ShaderMaterial] = []
var _nitro_forced: bool = false
var _results_up: bool = false  ## results overlay showing: mirror off, HUD hidden


func _ready() -> void:
	config_used = config if config != null else _config_from_router()
	Settings.attach_viewport(get_viewport())
	Settings.changed.connect(_on_settings_changed)
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
	# Whatever camera is current (chase, replay, a capture camera) must not draw the mirror-only car copies.
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null and (cam.cull_mask & CarLod.MIRROR_LAYER_BIT) != 0:
		cam.cull_mask &= ~CarLod.MIRROR_LAYER_BIT
	if race == null:
		return
	# Speed lines follow the player only (never an opponent).
	if _speed_lines != null and player != null and _speed_lines.has_method("set_speed"):
		_speed_lines.call("set_speed", player.speed_kmh, player.nitro_active)
	if _post_fx != null and player != null:
		_post_fx.set_speed(player.speed_kmh, player.nitro_active)
	if player != null and Engine.get_process_frames() % 20 == 0:
		WheelSpray.update_nearest(cars, player)
	if race.state == RaceManager.State.GRID:
		_grid_t += delta
		if _grid_t >= GRID_BEAT_S:
			race.start_countdown()
			_start_grid_intro()


func _physics_process(delta: float) -> void:
	if race == null or track == null or player == null:
		return
	if race.state == RaceManager.State.RACING and player.is_grounded and not wrong_way:
		_last_s = track.get_progress(player.global_position, _last_s)
	_follow_road_height(delta)
	_force_nitro_gate()


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
	_release_reflection()
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
		_speed_lines = (load(FX_SPEED_SCENE) as PackedScene).instantiate()
		speed_parent.add_child(_speed_lines)
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
	results_screen.replay_pressed.connect(start_replay)
	if not ResourceLoader.exists(GARAGE_SCENE):
		# shortcut: hides the private garage button until ResultsScreen exposes a visibility setter, upgrade then.
		var garage_btn: Button = results_screen.get("_garage_btn") as Button
		if garage_btn != null:
			garage_btn.visible = false


func _build_race() -> void:
	_grid_t = 0.0
	_last_s = -1.0
	wrong_way = false
	_nitro_forced = false
	_results_up = false
	hud.visible = true
	_reflection = null
	_road_mats.clear()
	tod = TimeOfDay.preset(config_used.time_of_day)
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	track = _load_track()
	_world.add_child(track)
	_collect_road()
	_tag_mirror_skipped()
	_ensure_environment()
	_spawn_cars()
	race = RaceManager.new()
	race.name = "RaceManager"
	race.total_laps = config_used.laps
	_world.add_child(race)
	race.setup(track, cars, player, _names)
	if config_used.traffic_enabled and not dev_track_used:
		var traffic := TrafficSystem.new()
		traffic.name = "Traffic"
		_world.add_child(traffic)
		traffic.setup(track, player, cars)
	if not dev_track_used and Settings.get_preset_id() != "low":  # Low budget is 250 draws: trees cost about 30
		var greenery := Greenery.new()
		greenery.name = "Greenery"
		_world.add_child(greenery)
		greenery.keep_open_view = config_used.track_scene.contains(BOGAZ_TRACK_KEY)
		Greenery.set_shade_fill(0.0 if tod.is_night() else (0.15 if config_used.time_of_day == "sunset" else 0.28))
		greenery.setup(track)
	# Bosphorus coast: the bridge, the far shore, the ferry and their reflections (they replace the flat bridge card).
	if not dev_track_used and config_used.track_scene.contains(BOGAZ_TRACK_KEY):
		var far := FarScenery.new()
		far.name = "FarScenery"
		_world.add_child(far)
		far.setup(track, config_used.time_of_day)
		var landmark := Landmarks.new()
		landmark.name = "Landmarks"
		_world.add_child(landmark)
		landmark.setup(track)
		landmark.set_night(1.0 if tod.is_night() else (0.6 if config_used.time_of_day == "sunset" else 0.0))
		# Licensed street fronts (CC BY models) replace the kit houses on the land side when the module is present.
		if ResourceLoader.exists(STREET_FRONTS_SCRIPT):
			var fronts: Node3D = (load(STREET_FRONTS_SCRIPT) as GDScript).new() as Node3D
			fronts.name = "StreetFronts"
			_world.add_child(fronts)
			fronts.call("setup", track, config_used.time_of_day)
		if Settings.get_preset_id() != "low":
			var dressing := EventDressing.new()  # race barriers with banners, flags, spectators, cafe terraces
			dressing.name = "EventDressing"
			_world.add_child(dressing)
			dressing.setup(track, config_used.time_of_day)
	ContactShadow.set_time_of_day(config_used.time_of_day)
	if _post_fx == null:
		_post_fx = PostFx.new()
		_post_fx.name = "PostFx"
		add_child(_post_fx)
	_post_fx.set_time_of_day(config_used.time_of_day)
	recorder = ReplayRecorder.new()
	recorder.name = "ReplayRecorder"
	_world.add_child(recorder)
	recorder.setup(cars)
	replay = null
	_apply_opponent_skills()
	_setup_player_driver()
	_make_camera()
	_apply_reflection()
	race.race_started.connect(_on_race_started)
	race.countdown_tick.connect(_on_countdown_tick)
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
				if "time_of_day" in t:
					t.set("time_of_day", tod.id)  # before _ready builds the environment
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
		tod.apply_after_settings(existing.environment)
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
	var rivals: Array[Dictionary] = []
	if config_used.rival_mix:
		rivals = CarCatalog.rival_models(opponents, hash(config_used.event_id))
	for i: int in opponents:
		var r_scene: String = config_used.car_scene
		var r_spec: CarSpec = spec
		if i < rivals.size():
			var loaded: CarSpec = load(str(rivals[i]["spec"])) as CarSpec
			if loaded != null:
				r_scene = str(rivals[i]["scene"])
				r_spec = loaded
		var car: ArcadeCar = CarFactory.create(r_scene, r_spec, config_used.opponent_paint(i))
		_add_car(car, true)
		_names.append(_opponent_name(i))
	player = CarFactory.create(config_used.car_scene, spec, _player_paint())
	_add_car(player)
	_names.append(config_used.player_name)
	dev_car_used = bool(player.get_meta("dev_car", false))


func _add_car(car: ArcadeCar, rival: bool = false) -> void:
	_world.add_child(car)
	cars.append(car)
	var lod: CarLod = _car_lod(car)
	if lod != null:
		if rival:
			lod.lod1_start_m = config_used.rival_lod1_start_m
			lod.lod2_start_m = config_used.rival_lod2_start_m
			if Settings.get_preset_id() == "low":
				lod.lod1_start_m = config_used.rival_lod1_start_low_m
				lod.lod2_start_m = config_used.rival_lod2_start_low_m
			lod.set_forced(lod.force_lod)  # rewrites the visibility ranges with the new switch distance
		lod.build_mirror_lod()
		# The mirror-only copies are never drawn by the race camera: they must not cast a second sun shadow beside the real LOD.
		for n: Node in lod.find_children("*", "MeshInstance3D", true, false):
			var cm: MeshInstance3D = n as MeshInstance3D
			if cm.layers == CarLod.MIRROR_LAYER_BIT:
				cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if lod != null and not tod.is_night() and tod.sun_shadows and Settings.get_preset_id() != "low":
		_add_shadow_proxy(lod)
	# Engine, tyres, nitro and impacts; rivals get the cheaper, quieter positional set.
	var audio := CarAudio.new()
	audio.name = "CarAudio"
	audio.is_player = not rival
	ContactShadow.attach(car, true)  # soft grounding blob: the Mobile renderer has no ambient occlusion
	if Settings.get_preset_id() != "low":
		var spray := WheelSpray.new()  # tyre spray on the wet road; only the player and the two nearest rivals emit
		spray.name = WheelSpray.NODE_NAME
		car.add_child(spray)
		spray.set_wetness(tod.audio_wetness)
		var glow := Underglow.new()
		glow.name = "Underglow"
		glow.player_light = not rival
		if rival:
			glow.color = UNDERGLOW_RIVAL[cars.size() % UNDERGLOW_RIVAL.size()]
		car.add_child(glow)
		glow.apply_time_of_day(config_used.time_of_day)
	audio.wetness = tod.audio_wetness  # night: the city road is always wet (rain or not, the asphalt shader is wet)
	car.add_child(audio)
	for n: Node in car.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		# Not the mirror-only copy: bit 19 would put it in the main camera's view. The fill lights see its own layer instead.
		if mi.layers & CarLod.MIRROR_LAYER_BIT == 0:
			mi.layers = mi.layers | (1 << CAR_FILL_LAYER)
	if ResourceLoader.exists(FX_CAR_SCENE):
		var fx: Node = (load(FX_CAR_SCENE) as PackedScene).instantiate()
		if fx is CarFx:
			(fx as CarFx).headlights_on = tod.headlights_on  # only at sunset and night
		car.add_child(fx)
		# Smoke, sparks and flames are particles: they must not be drawn again in the sun's shadow pass.
		for g: Node in fx.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Sun shadow of a car from its 7k-triangle LOD2 only: LOD0 and LOD1 stop casting (every car LOD0 cast cost about
## 25k primitives per car in the shadow pass), and a copy of LOD2 on the mirror-only layer, shadows only, casts instead.
## The race cameras skip that layer and the copy has no visibility range, so it is a plain shadow caster at any distance.
func _add_shadow_proxy(lod: CarLod) -> void:
	var src: Node3D = lod.get_node_or_null("LOD2") as Node3D
	if src == null:
		return
	for n: Node in lod.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proxy: Node3D = src.duplicate() as Node3D
	proxy.name = SHADOW_PROXY_NAME
	proxy.visible = true
	lod.add_child(proxy)
	for n: Node in proxy.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if not CarMaterials.SHADOW_CASTERS.has(String(mi.name)):
			mi.queue_free()  # glass, lamps and the like: not worth a draw in the shadow pass
			continue
		mi.layers = CarLod.MIRROR_LAYER_BIT
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mi.visibility_range_begin = 0.0
		mi.visibility_range_end = 0.0
		mi.visible = not String(mi.name).begins_with(CarLod.COL_NAME)


func _car_lod(car: ArcadeCar) -> CarLod:
	var visual: Node = car.get_node_or_null(CarFactory.VISUAL_NAME)
	if visual == null:
		return null
	for c: Node in visual.get_children():
		if c is CarLod:
			return c as CarLod
	return null


func _opponent_name(index: int) -> String:
	if config_used.track_scene.contains("istanbul") and index < ISTANBUL_NAMES.size():
		return ISTANBUL_NAMES[index]
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
	camera.cull_mask &= ~CarLod.MIRROR_LAYER_BIT
	camera.make_current()
	# Cars are dark silhouettes at night without this. Cool, low, no shadow; it sees only the car layer.
	var fill := OmniLight3D.new()
	fill.name = FILL_LIGHT_NAME
	fill.light_color = tod.car_fill_color if tod.car_fill_color.a > 0.0 else config_used.car_fill_color
	fill.light_energy = config_used.car_fill_energy * tod.car_fill_scale
	fill.omni_range = config_used.car_fill_range_m
	fill.light_cull_mask = CAR_LIGHT_MASK
	fill.shadow_enabled = false
	camera.add_child(fill)
	# Directional, camera-relative: shines from beyond the car toward the lens and down, on the car layer only.
	var rim := DirectionalLight3D.new()
	rim.name = RIM_LIGHT_NAME
	rim.light_color = tod.car_rim_color if tod.car_rim_color.a > 0.0 else config_used.car_rim_color
	rim.light_energy = config_used.car_rim_energy * tod.car_rim_scale
	rim.light_cull_mask = CAR_LIGHT_MASK
	rim.shadow_enabled = false
	var el: float = deg_to_rad(config_used.car_rim_elevation_deg)
	rim.basis = Basis.looking_at(Vector3(0.0, -sin(el), cos(el)), Vector3.UP)
	camera.add_child(rim)


## Small street furniture, dressing and parked cars move from the default layer to the mirror-skip layer (the real cameras see both).
## Signs, lamps, buildings and cars stay in the mirror: the neon streaks on the wet road are the look.
func _tag_mirror_skipped() -> void:
	for n: Node in track.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n as GeometryInstance3D
		var skip: bool = false
		for part: String in MIRROR_SKIP_PROPS:
			if gi.name.contains(part):
				skip = true
				break
		for part: String in MIRROR_KEEP_PROPS:
			if gi.name.contains(part):
				skip = false
		if not skip:
			var root: Node = gi.get_parent()
			while root != null and root != track and not skip:
				skip = MIRROR_SKIP_ROOTS.has(String(root.name))
				root = root.get_parent()
		if skip:
			gi.layers = (gi.layers & ~1) | MIRROR_SKIP_BIT  # a mirror camera skipping this bit must find no other it includes
			continue
		# Buildings: the mirror never needs the detailed LOD0 (it doubled 8 000 triangles per near house). LOD0 leaves the
		# mirror and a mirror-only copy of LOD1 covers the near range instead.
		var lod_name: String = _lod_ancestor(gi)
		if lod_name == "LOD0":
			gi.layers = (gi.layers & ~1) | MIRROR_SKIP_BIT
		elif lod_name == "LOD1" and gi is MeshInstance3D and gi.visibility_range_begin > 0.0:
			var copy: MeshInstance3D = gi.duplicate() as MeshInstance3D
			copy.name = String(gi.name) + "_mirror"
			copy.layers = CarLod.MIRROR_LAYER_BIT
			copy.visibility_range_end = gi.visibility_range_begin
			copy.visibility_range_begin = 0.0
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gi.get_parent().add_child(copy)


## "LOD0" / "LOD1" / "LOD2" when the node is a building LOD mesh or sits under one, else "".
func _lod_ancestor(n: Node) -> String:
	var p: Node = n  # the builder names the mesh itself LOD0/LOD1; split pieces sit under it
	while p != null and p != track:
		var nm: String = p.name
		if nm.length() == 4 and nm.begins_with("LOD"):
			return nm
		p = p.get_parent()
	return ""


## Wet road meshes (M_Asphalt on wet_asphalt.gdshader) go on the road layer, which the mirror skips.
func _collect_road() -> void:
	for n: Node in track.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var is_road: bool = false
		for s: int in mesh.get_surface_count():
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = mesh.surface_get_material(s)
			if _is_asphalt(mat):
				is_road = true
				if not _road_mats.has(mat):
					_road_mats.append(mat as ShaderMaterial)
		if is_road:
			mi.layers = ROAD_LAYER_BIT


func _is_asphalt(mat: Material) -> bool:
	var sm: ShaderMaterial = mat as ShaderMaterial
	return sm != null and sm.resource_name == ASPHALT_MATERIAL_NAME and sm.shader != null and sm.shader.resource_path == ASPHALT_SHADER_PATH


## High only. Medium has no mirror: it relies on the GGX lamp streaks and reflection probes of wet_asphalt.
## The mirror on High re-renders every second frame (the road reflection is stable between frames).
func _apply_reflection() -> void:
	var preset_id: String = Settings.get_preset_id()
	if preset_id != "high" or _road_mats.is_empty() or not tod.road_mirror:
		_release_reflection()
		return
	if _reflection == null:
		_reflection = PlanarReflection.new()
		_reflection.name = REFLECTION_NAME
		_world.add_child(_reflection)
		for m: ShaderMaterial in _road_mats:
			_reflection.add_target_material(m)
	_reflection.resolution_fraction = config_used.reflection_fraction_high
	_reflection.max_distance_m = config_used.reflection_max_distance_m
	_reflection.every_second_frame = true
	_reflection.set_enabled(not _results_up)


func _release_reflection() -> void:
	for m: ShaderMaterial in _road_mats:
		if is_instance_valid(m):
			m.set_shader_parameter("planar_enabled", 0.0)
	if _reflection != null:
		_reflection.set_enabled(false)
		_reflection.get_parent().remove_child(_reflection)  ## out of the tree now, so it is gone at once
		_reflection.queue_free()
	_reflection = null


func _on_settings_changed(section: String) -> void:
	if section == Settings.SECTION_GRAPHICS and track != null and _world != null:
		_apply_reflection()


## Mirror plane eases to the road height under the car (ray down from the car, world layer only).
func _follow_road_height(delta: float) -> void:
	if _reflection == null:
		return
	var from: Vector3 = player.global_position + Vector3.UP * PLANE_PROBE_UP_M
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * PLANE_PROBE_DOWN_M, WORLD_LAYER_MASK)
	q.exclude = [player.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var k: float = 1.0 - exp(-PLANE_FOLLOW_RATE * delta)
	_reflection.plane_height = lerpf(_reflection.plane_height, (hit["position"] as Vector3).y, k)


## Capture only: with force_nitro_above_kmh set, the autopilot's nitro gate opens once the car is that fast.
func _force_nitro_gate() -> void:
	var threshold: float = config_used.force_nitro_above_kmh
	if threshold <= 0.0 or player_ai == null:
		return
	var want: bool = player.speed_kmh >= threshold
	if want != _nitro_forced:
		_nitro_forced = want
		force_player_nitro(want)


func _attach_optional() -> void:
	if tod.rain and ResourceLoader.exists(FX_RAIN_SCENE):
		_world.add_child((load(FX_RAIN_SCENE) as PackedScene).instantiate())
	if tod.rain and get_node_or_null("RainOnLens") == null:
		var lens := RainOnLens.new()  # a few drops sliding on the lens, under the HUD; off on Low by itself
		lens.name = "RainOnLens"
		add_child(lens)
		lens.set_strength(1.0)


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


## Countdown camera: from high behind the pack, down over the cars to the chase pose at GO (see ChaseCamera).
func _start_grid_intro() -> void:
	var c: Vector3 = Vector3.ZERO
	for car: ArcadeCar in cars:
		c += car.global_position
	c /= float(cars.size())
	var fwd: Vector3 = track.get_tangent_at(track.get_progress(c))
	fwd.y = 0.0
	fwd = fwd.normalized()
	camera.start_grid_intro(c - fwd * GRID_INTRO_BACK_M + Vector3.UP * GRID_INTRO_UP_M, c + Vector3.UP, float(race.countdown_seconds))


## Replay after the race: results and HUD hide, the replay player takes the camera. Leaving it shows the results.
func start_replay() -> void:
	if recorder == null or not recorder.has_data() or replay != null:
		return
	results_screen.visible = false
	hud.visible = false
	if _touch != null:
		_touch.visible = false
	replay = ReplayPlayer.new()
	replay.name = "Replay"
	_world.add_child(replay)
	replay.setup(recorder, cars, track, player)
	_set_results_up(false)  # the replay shows the wet road
	replay.exited.connect(end_replay)


func end_replay() -> void:
	if replay == null:
		return
	replay.queue_free()
	replay = null
	camera.make_current()
	if _touch != null:
		_touch.visible = true
	results_screen.visible = true
	_set_results_up(true)


func _on_countdown_tick(seconds_left: int) -> void:
	UiSounds.countdown(seconds_left)


func _on_race_started() -> void:
	MusicPlayer.get_instance().play_race()
	if recorder != null:
		recorder.start()
	camera.set_mode(ChaseCamera.Mode.CHASE)
	if player_ai != null:
		player_ai.set_racing(true)


func _on_race_finished(results: Array[Dictionary]) -> void:
	last_results = results
	MusicPlayer.get_instance().duck(-10.0, 0.15)
	UiSounds.finish()
	get_tree().create_timer(2.5).timeout.connect(func() -> void: MusicPlayer.get_instance().unduck(1.0))
	for car: ArcadeCar in cars:
		var ca: CarAudio = car.get_node_or_null("CarAudio") as CarAudio
		if ca != null and not ca.is_player:
			ca.set_enabled(false)  # rivals fall silent behind the results; the player car idles on
	var rewards: Dictionary = {}
	for r: Dictionary in results:
		if bool(r.get("is_player", false)):
			rewards = GameState.record_result(config_used.event_id, float(r.get("total_time", 0.0)), int(r.get("position", 0)))
	if player_ai != null:
		player_ai.set_racing(false)
	if camera != null:
		camera.start_finish_orbit()  # slow cinematic orbit behind the results screen
	if recorder != null:
		recorder.stop()
	results_screen.set_replay_enabled(recorder != null and recorder.has_data())
	results_screen.show_results(results, rewards)
	results_screen.visible = true
	_set_results_up(true)


## Results up: no mirror pass and no race HUD behind the panel. The replay and a retry bring both back.
func _set_results_up(on: bool) -> void:
	_results_up = on
	hud.visible = not on and replay == null
	if _reflection != null:
		_reflection.set_enabled(not on)


func _on_wrong_way(is_wrong: bool) -> void:
	wrong_way = is_wrong


func _to_menu() -> void:
	Router.goto(MENU_SCENE)


func _to_garage() -> void:
	if ResourceLoader.exists(GARAGE_SCENE):
		Router.goto(GARAGE_SCENE)


## The paint chosen in the garage for the selected car, else the config's default.
func _player_paint() -> Color:
	if not config_used.use_garage_paint:
		return config_used.player_paint
	var setup: Dictionary = GameState.get_setup(GameState.get_selected_car())
	var c: Variant = setup.get("paint_color")
	if c is Color:
		return c
	if c is String and Color.html_is_valid(c):
		return Color.html(c)
	return config_used.player_paint
