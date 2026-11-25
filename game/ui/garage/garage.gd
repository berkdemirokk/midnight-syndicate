extends Node3D
## Interactive 3D garage. The room (GLB, materials bound by name), a turntable with the Noctra Sable at its centre,
## eight lights matched to the room fixtures, one soft shadowed key, a box-projected reflection probe, and the
## orbit camera. The 2D layer is GarageHud. Game state changes go through GameState; paint goes through CarMaterials.

const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const LAYOUT_PATH: String = "res://assets/world/garage/garage_layout.json"
const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const MAIN_MENU: String = "res://ui/menus/main_menu.tscn"
const RACE_SCENE: String = "res://race/race_scene.tscn"
const CAR_Y: float = 0.065  ## turntable plate top, from garage_layout.json
const CAR_TURN: float = PI  ## the car model faces +Z in Godot; the garage stand faces -Z
const CAMERA_FOV: float = 50.0
const LOOK_SHIFT_M: float = 0.45  ## looks this far right of the car, so the car sits left of centre beside the panel
const TURN_RATE: float = 0.12  ## rad/s of the turntable once idle spin is on
const TURN_EASE: float = 1.5  ## 1/s, how fast the turntable reaches its speed
const KEY_ORBIT_RATE: float = 1.4  ## rad/s while steer keys are held
const KEY_ZOOM_RATE: float = 0.6  ## fraction per second while accelerate or brake is held
const DOUBLE_TAP_MS: int = 320
const DOUBLE_TAP_PX: float = 40.0
const SPOT_NAMES: PackedStringArray = ["ceiling_strip_y0", "ceiling_strip_y4"]
const LIGHT_NAMES: PackedStringArray = [
	"ceiling_strip_y0", "ceiling_strip_y4", "ceiling_strip_y2", "warm_tube_back_L",
	"warm_tube_back_R", "neon_sign_magenta", "neon_sign_underline", "work_lamp_bench",
]
const SPOT_ENERGY: float = 5.0  ## 8 made hot pools on the glossy floor in the rear view
const SPOT_RANGE: float = 9.0
const SPOT_ANGLE_DEG: float = 55.0
const OMNI_ENERGY: float = 3.0
const OMNI_RANGE: float = 6.0
const KEY_ENERGY: float = 2.4 ## the paint is metallic: with a dark room it reads black, so the key does real work
const KEY_COLOUR: Color = Color(1.0, 0.96, 0.92)  ## near white: a cool key turns the red paint into navy
const FILL_ENERGY: float = 3.0  ## shadowless fill from the viewer's side, so the front and flanks catch light
const FILL_COLOUR: Color = Color(1.0, 0.98, 0.95)
const PROBE_INTENSITY: float = 3.5 ## metal reflects the probe only; the room is dark, so the probe needs gain
const GLOW_INTENSITY: float = 0.6
const GLOW_BLOOM: float = 0.06
const BG_COLOUR: Color = Color(0.012, 0.014, 0.022)
const AMBIENT_COLOUR: Color = Color(0.05, 0.06, 0.09)

var layout: Dictionary = {}
var orbit: GarageOrbit = GarageOrbit.new()
var car: CarLod = null
var spec: CarSpec = null
var car_id: String = ""

var _room: Node3D
var _turntable: Node3D = null
var _pivot: Node3D
var _lights: Node3D
var _camera: Camera3D
var _probe: ReflectionProbe
var _key: DirectionalLight3D
var _env: Environment
var _set: ShowroomSet
var _hud: GarageHud
var _turn_angle: float = 0.0
var _turn_speed: float = 0.0
var _touches: Dictionary = {}
var _pinch_px: float = 0.0
var _last_tap_ms: int = -100000
var _last_tap_px: Vector2 = Vector2.ZERO


func _ready() -> void:
	_room = $Room
	_pivot = $Pivot
	_lights = $Lights
	_camera = $Camera
	layout = _read_json(LAYOUT_PATH)
	orbit.configure(layout)
	orbit.set_pose(GarageOrbit.PRESETS["overview"]["yaw"], GarageOrbit.PRESETS["overview"]["pitch"], GarageOrbit.PRESETS["overview"]["dist"])
	car_id = GameState.get_selected_car()
	spec = load(SPEC_PATH) as CarSpec
	_turntable = _room.find_child("turntable", true, false) as Node3D
	GarageMaterials.bind(_room)
	for n: Node in _room.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.position = Vector3(0.0, CAR_Y, 0.0)
	_spawn_car()
	_build_lights()
	_build_probe()
	_build_environment()
	_build_showroom()
	_camera.fov = CAMERA_FOV
	_camera.current = true
	_build_hud()
	Settings.attach_viewport(get_viewport())
	Settings.changed.connect(_on_settings_changed)
	_update_camera()


func _process(delta: float) -> void:
	_keyboard_orbit(delta)
	orbit.step(delta)
	var want: float = TURN_RATE if orbit.is_idle_spinning() else 0.0
	_turn_speed = lerpf(_turn_speed, want, 1.0 - exp(-TURN_EASE * delta))
	_turn_angle = wrapf(_turn_angle + _turn_speed * delta, 0.0, TAU)
	_pivot.rotation.y = _turn_angle
	if _turntable != null:
		_turntable.rotation.y = _turn_angle
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			orbit.zoom(0.92)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			orbit.zoom(1.08)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
			reset_view()
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null:
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and _touches.is_empty():
			orbit.drag(mm.relative)
		return
	var st: InputEventScreenTouch = event as InputEventScreenTouch
	if st != null:
		if st.pressed:
			_touches[st.index] = st.position
			if _touches.size() == 1:
				_check_double_tap(st.position)
			if _touches.size() == 2:
				_pinch_px = _touch_gap()
		else:
			_touches.erase(st.index)
		return
	var sd: InputEventScreenDrag = event as InputEventScreenDrag
	if sd != null:
		_touches[sd.index] = sd.position
		if _touches.size() == 1:
			orbit.drag(sd.relative)
		elif _touches.size() == 2:
			var gap: float = _touch_gap()
			if gap > 1.0 and _pinch_px > 1.0:
				orbit.zoom(_pinch_px / gap)
			_pinch_px = gap


## Preset view: eased transition to front, side, rear34 or overview.
func go_view(view: String) -> bool:
	return orbit.go_preset(view)


func reset_view() -> void:
	go_view("overview")


## Live preview while a colour is dragged: no save.
func preview_paint(c: Color) -> void:
	if car != null:
		CarMaterials.set_paint(car, c)


## Applies and saves the paint for the car.
func commit_paint(c: Color) -> bool:
	if not GameState.set_paint(car_id, c):
		return false
	preview_paint(c)
	_refresh_hud()
	return true


func commit_rim(c: Color) -> bool:
	if not GameState.set_rim(car_id, c):
		return false
	if car != null:
		CarMaterials.set_rim_color(car, c)
	_refresh_hud()
	return true


## Buys the next level of part. A short message and a shake when the cash is short. Returns true on success.
func buy_upgrade(part: String) -> bool:
	var lvl: int = GameState.get_upgrade_level(car_id, part)
	if lvl >= GameState.MAX_UPGRADE_LEVEL:
		_hud.show_message("garage.max_reached", true)
		return false
	if GameState.upgrade(car_id, part):
		_hud.show_message("garage.upgraded")
		_refresh_hud()
		return true
	_hud.show_message("garage.not_enough", true)
	_hud.shake_buy(part)
	return false


func get_hud() -> GarageHud:
	return _hud


func get_camera() -> Camera3D:
	return _camera


func get_probe() -> ReflectionProbe:
	return _probe


## Numbers the HUD shows: name, cash, stats, upgrade levels and costs, paint and rim.
func state() -> Dictionary:
	var setup: Dictionary = GameState.get_setup(car_id)
	var upgrades: Dictionary = setup["upgrades"]
	var levels: Dictionary = {}
	var costs: Dictionary = {}
	var afford: Dictionary = {}
	for part: String in GameState.UPGRADE_PARTS:
		var lvl: int = int(upgrades.get(part, 0))
		levels[part] = lvl
		var cost: int = -1 if lvl >= GameState.MAX_UPGRADE_LEVEL else GameState.upgrade_cost(part, lvl)
		costs[part] = cost
		afford[part] = cost < 0 or cost <= GameState.get_cash()
	return {
		"name": spec.display_name if spec != null else car_id,
		"cash": GameState.get_cash(),
		"stats": GarageStats.compute(spec, upgrades),
		"levels": levels,
		"costs": costs,
		"can_afford": afford,
		"paint": Color.from_string(str(setup["paint_color"]), CarMaterials.DEFAULT_PAINT),
		"rim": Color.from_string(str(setup["rim_color"]), CarMaterials.DEFAULT_RIM),
	}


# --- internals --------------------------------------------------------------

func _spawn_car() -> void:
	var packed: PackedScene = load(CAR_SCENE) as PackedScene
	car = packed.instantiate() as CarLod
	var setup: Dictionary = GameState.get_setup(car_id)
	car.force_lod0 = true
	car.paint_colour = Color.from_string(str(setup["paint_color"]), CarMaterials.DEFAULT_PAINT)
	car.rotation.y = CAR_TURN
	_pivot.add_child(car)
	CarMaterials.set_rim_color(car, Color.from_string(str(setup["rim_color"]), CarMaterials.DEFAULT_RIM))


func _build_lights() -> void:
	var by_name: Dictionary = {}
	for l: Variant in layout.get("lights", []):
		by_name[str((l as Dictionary)["name"])] = l
	for nm: String in LIGHT_NAMES:
		var d: Dictionary = by_name[nm]
		var p: Vector3 = _v3(d["position"])
		var c: Array = d["colour"]
		var col: Color = Color(float(c[0]), float(c[1]), float(c[2]))
		if SPOT_NAMES.has(nm):
			var s := SpotLight3D.new()
			s.name = nm
			s.light_color = col
			s.light_energy = SPOT_ENERGY
			s.spot_range = SPOT_RANGE
			s.spot_angle = SPOT_ANGLE_DEG
			s.shadow_enabled = false
			s.position = p
			s.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  ## spot points along -Z by default, turn it down
			_lights.add_child(s)
		else:
			var o := OmniLight3D.new()
			o.name = nm
			o.light_color = col
			o.light_energy = OMNI_ENERGY
			o.omni_range = OMNI_RANGE
			o.shadow_enabled = false
			o.position = p
			_lights.add_child(o)
	_key = DirectionalLight3D.new()
	_key.name = "Key"
	_key.light_color = KEY_COLOUR
	_key.light_energy = KEY_ENERGY
	_key.shadow_enabled = true
	_key.light_angular_distance = 1.5
	_key.rotation_degrees = Vector3(-62.0, 28.0, 0.0)
	_lights.add_child(_key)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = FILL_COLOUR
	fill.light_energy = FILL_ENERGY
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-30.0, 180.0, 0.0)
	_lights.add_child(fill)


func _build_probe() -> void:
	var c: Array = layout["reflection_probe"]["centre"]
	var h: Array = layout["reflection_probe"]["half_extents"]
	_probe = ReflectionProbe.new()
	_probe.name = "RoomProbe"
	_probe.position = _v3(c)
	_probe.size = _v3(h) * 2.0
	_probe.box_projection = true
	_probe.intensity = PROBE_INTENSITY
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(_probe)


func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = BG_COLOUR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = AMBIENT_COLOUR
	_env.ambient_light_energy = 0.5
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.fog_enabled = false
	Settings.apply_to_environment(_env)
	_env.glow_intensity = GLOW_INTENSITY
	_env.glow_bloom = GLOW_BLOOM
	_env.glow_hdr_threshold = 1.5  ## only genuinely hot pixels bloom: the lamp strips no longer clip into flat sprites
	_env.glow_hdr_scale = 1.5
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = _env
	add_child(we)


## Mirror floor and turntable plate, soft contact shadow, warm rim and cool fill lights, neon accents.
func _build_showroom() -> void:
	_set = ShowroomSet.new()
	_set.name = "Showroom"
	add_child(_set)
	_set.attach_garage(_room, _pivot, CAR_Y, Settings.get_preset_id() != "low")


func _build_hud() -> void:
	_hud = GarageHud.new()
	_hud.name = "Hud"
	$UI.add_child(_hud)
	_hud.back_pressed.connect(func() -> void: Router.goto(MAIN_MENU))
	_hud.race_pressed.connect(func() -> void: Router.goto(RACE_SCENE))
	_hud.view_pressed.connect(go_view)
	_hud.paint_previewed.connect(preview_paint)
	_hud.paint_committed.connect(commit_paint)
	_hud.rim_pressed.connect(commit_rim)
	_hud.upgrade_pressed.connect(buy_upgrade)
	_refresh_hud()


func _refresh_hud() -> void:
	if _hud != null:
		_hud.refresh(state())


func _update_camera() -> void:
	var pos: Vector3 = orbit.camera_position()
	var fwd: Vector3 = (orbit.target - pos).normalized()
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	_camera.position = pos
	_camera.look_at(orbit.target + right * LOOK_SHIFT_M, Vector3.UP)


func _keyboard_orbit(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() != null:
		return  ## arrows move the focus when a button has it
	var steer: float = Input.get_axis("steer_left", "steer_right")
	if absf(steer) > 0.01:
		orbit.nudge(-steer * KEY_ORBIT_RATE * delta, 0.0)
	var zoom: float = Input.get_axis("brake", "accelerate")
	if absf(zoom) > 0.01:
		orbit.zoom(1.0 - zoom * KEY_ZOOM_RATE * delta)


func _check_double_tap(p: Vector2) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_tap_ms <= DOUBLE_TAP_MS and p.distance_to(_last_tap_px) <= DOUBLE_TAP_PX:
		reset_view()
		_last_tap_ms = -100000
	else:
		_last_tap_ms = now
		_last_tap_px = p


func _touch_gap() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


func _on_settings_changed(section: String) -> void:
	if section == "general" and _hud != null:
		_hud.apply_language()
	if section == "graphics":
		Settings.apply_to_environment(_env)
		Settings.apply_to_viewport(get_viewport())


static func _v3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


static func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
