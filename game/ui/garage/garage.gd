extends Node3D
## Interactive 3D garage, STREET EMPIRE showroom: the same graphite studio as the main menu (ShowroomStage.build_studio:
## glossy mirror floor, overhead strips, red wash, fill and rim spots), a dark turntable with a red edge, one soft
## shadowed directional key plus a shadowless fill, a box-projected probe, the studio panorama in the paint, and the
## orbit camera. The old workshop room is gone (owner, 2026-11-28: "garaj çok kötü"); garage_layout.json still gives
## the orbit target and pitch limits. The 2D layer is GarageHud. State changes go through GameState and CarMaterials.

const LAYOUT_PATH: String = "res://assets/world/garage/garage_layout.json"
const MAIN_MENU: String = "res://ui/menus/main_menu.tscn"
const RACE_SCENE: String = "res://ui/menus/event_select.tscn"  ## RACE opens the career ladder (rewards count there)
const CAR_Y: float = 0.065  ## turntable plate top, from garage_layout.json
const CAR_TURN: float = PI  ## the car model faces +Z in Godot; the garage stand faces -Z
const CAMERA_FOV: float = 38.0  ## long lens: the configurator look (less distortion on the body)
const LOOK_SHIFT_M: float = 0.0  ## centred car: the stats column (left) and the configurator (right) frame it
const TURN_RATE: float = 0.12  ## rad/s of the turntable once idle spin is on
const TURN_EASE: float = 1.5  ## 1/s, how fast the turntable reaches its speed
const KEY_ORBIT_RATE: float = 1.4  ## rad/s while steer keys are held
const KEY_ZOOM_RATE: float = 0.6  ## fraction per second while accelerate or brake is held
const STAGE_SCRIPT: Script = preload("res://ui/showroom/showroom_stage.gd")
const ORBIT_MIN_DIST: float = 4.6  ## studio has no walls: the orbit may pull back further than the old room allowed
const ORBIT_MAX_DIST: float = 10.5
const TURNTABLE_R: float = 2.85
const DOUBLE_TAP_MS: int = 320
const DOUBLE_TAP_PX: float = 40.0
const KEY_ENERGY: float = 2.4 ## the paint is metallic: with a dark room it reads black, so the key does real work
const KEY_COLOUR: Color = Color(1.0, 0.96, 0.92)  ## near white: a cool key turns the red paint into navy
const FILL_ENERGY: float = 3.0  ## shadowless fill from the viewer's side, so the front and flanks catch light
const FILL_COLOUR: Color = Color(1.0, 0.98, 0.95)
const PROBE_INTENSITY: float = 3.5 ## metal reflects the probe only; the room is dark, so the probe needs gain
const KEY_SHADOW_DISTANCE_M: float = 18.0  ## the farthest corner of the room is 15.9 m from the camera; a longer reach only coarsens the map

var layout: Dictionary = {}
var orbit: GarageOrbit = GarageOrbit.new()
var car: CarLod = null
var _pano: Texture2D = null
var spec: CarSpec = null
var car_id: String = ""

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
var _preview_part: String = ""  ## upgrade row under the finger or cursor: its gain shows on the stat bars


func _ready() -> void:
	_pivot = $Pivot
	_lights = $Lights
	_camera = $Camera
	layout = _read_json(LAYOUT_PATH)
	orbit.configure(layout)
	orbit.min_dist = ORBIT_MIN_DIST
	orbit.max_dist = ORBIT_MAX_DIST
	orbit.set_pose(GarageOrbit.PRESETS["overview"]["yaw"], GarageOrbit.PRESETS["overview"]["pitch"], GarageOrbit.PRESETS["overview"]["dist"])
	car_id = CarCatalog.race_car_id()
	spec = load(CarCatalog.spec_path(car_id)) as CarSpec
	_pivot.position = Vector3(0.0, CAR_Y, 0.0)
	_spawn_car()
	_build_showroom()
	_build_lights()
	_build_probe()
	_build_environment()
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
		_hud.show_message("garage.car_not_owned", true)
		return false
	preview_paint(c)
	_refresh_hud()
	return true


func commit_rim(c: Color) -> bool:
	if not GameState.set_rim(car_id, c):
		_hud.show_message("garage.car_not_owned", true)
		return false
	if car != null:
		CarMaterials.set_rim_color(car, c)
	_refresh_hud()
	return true


## Buys the next level of part. A short message and a shake when the cash is short. Returns true on success.
func buy_upgrade(part: String) -> bool:
	if not GameState.has_car(car_id):
		_hud.show_message("garage.car_not_owned", true)
		return false
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
		"preview": _upgrade_preview(upgrades),
		"levels": levels,
		"costs": costs,
		"can_afford": afford,
		"paint": Color.from_string(str(setup["paint_color"]), CarMaterials.DEFAULT_PAINT),
		"rim": Color.from_string(str(setup["rim_color"]), CarMaterials.DEFAULT_RIM),
		"car_id": car_id,
		"class": CarCatalog.class_id(car_id),
		"owned": GameState.has_car(car_id),
		"selected": GameState.get_selected_car() == car_id,
		"price": CarCatalog.price(car_id),
		"block": CarCatalog.buy_block(car_id),
		"rep_needed": CarCatalog.rep_needed(car_id),
		"car_count": CarCatalog.available_ids().size(),
	}


# --- internals --------------------------------------------------------------

## Carousel step: dir +1 next, -1 previous, wraps. Shows that car on the turntable. Returns the new car id.
func step_car(dir: int) -> String:
	var ids: Array[String] = CarCatalog.available_ids()
	if ids.size() > 1:
		var i: int = ids.find(car_id)
		show_car(ids[posmod(i + dir, ids.size())])
	return car_id


## Puts id on the turntable; the paint, rim and upgrade tabs then work on it (once owned).
func show_car(id: String) -> void:
	if not CarCatalog.is_available(id):
		return
	car_id = id
	spec = load(CarCatalog.spec_path(id)) as CarSpec
	if car != null:
		car.free()
	_spawn_car()
	_refresh_hud()


## Buy the shown car when it is not owned, else select it. Returns true when something changed.
func car_action() -> bool:
	if GameState.has_car(car_id):
		var changed: bool = GameState.get_selected_car() != car_id and GameState.select_car(car_id)
		if changed:
			_hud.show_message("garage.car_selected_msg")
			_refresh_hud()
		return changed
	if CarCatalog.buy(car_id):
		GameState.select_car(car_id)
		_hud.show_message("garage.car_bought")
		_refresh_hud()
		return true
	if CarCatalog.buy_block(car_id) == "cash":
		_hud.show_message("garage.not_enough_car", true)
	return false


func _spawn_car() -> void:
	var packed: PackedScene = load(CarCatalog.scene_path(car_id)) as PackedScene
	car = packed.instantiate() as CarLod
	var setup: Dictionary = GameState.get_setup(car_id)
	car.force_lod0 = true
	car.paint_colour = Color.from_string(str(setup["paint_color"]), CarMaterials.DEFAULT_PAINT)
	car.rotation.y = CAR_TURN
	_pivot.add_child(car)
	CarMaterials.set_rim_color(car, Color.from_string(str(setup["rim_color"]), CarMaterials.DEFAULT_RIM))
	# the studio strips in the paint; one more pass over the body, so not on the Low preset
	if Settings.get_preset_id() != "low":
		if _pano == null:
			_pano = STAGE_SCRIPT.studio_pano()  # built once per run, shared with the main menu showroom
		CarMaterials.set_reflection(car, _pano, 0.85, 1.4, 2.2)


## Directional key (the one shadow) and a shadowless fill; the studio set adds no spots in the garage.
func _build_lights() -> void:
	_key = DirectionalLight3D.new()
	_key.name = "Key"
	_key.light_color = KEY_COLOUR
	_key.light_energy = KEY_ENERGY
	_key.shadow_enabled = true
	# one shadow map: the default four cascades over 100 m drew the car (the only shadow caster) up to four times
	# a frame for a room that is 16 m across
	_key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_key.directional_shadow_max_distance = KEY_SHADOW_DISTANCE_M
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
	_probe = ReflectionProbe.new()
	_probe.name = "StudioProbe"
	_probe.position = Vector3(0.0, 3.0, 0.0)
	_probe.size = Vector3(26.0, 8.0, 26.0)
	_probe.cull_mask = ((1 << 20) - 1) & ~ShowroomSet.MIRROR_LAYER_BIT  # strips and wash in the probe, not the floor
	_probe.box_projection = true
	_probe.intensity = PROBE_INTENSITY
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(_probe)


## The studio environment from build_studio, with the player's graphics preset applied (glow on or off).
func _build_environment() -> void:
	Settings.apply_to_environment(_env)
	_env.glow_hdr_threshold = 1.4  ## only genuinely hot pixels bloom


## Studio set (shared with the main menu), turntable, contact shadow under the car. The ShowroomSet node keeps the
## floor material, mirror and shadow references other code and tests read.
func _build_showroom() -> void:
	_set = ShowroomSet.new()
	_set.name = "Showroom"
	add_child(_set)
	var built: Dictionary = STAGE_SCRIPT.build_studio(_set, "lite" if Settings.get_preset_id() == "low" else "full", false, false)
	_env = built["env"]
	var we: Node = _set.get_node("Environment")
	we.reparent(self)  # the garage's WorldEnvironment lives at the scene root, as before ($Environment)
	_set.floor_material = built["floor_material"]
	_set.floor_material.set_shader_parameter("light_specular", 0.0)  # the directional key would glint on the floor near the lens
	_set.planar = built["planar"]
	_set.contact_shadow = ShowroomSet.make_contact_shadow(0.004)
	_pivot.add_child(_set.contact_shadow)
	_turntable = _make_turntable()
	add_child(_turntable)


## Dark glossy disc the car stands on (top at CAR_Y), with a thin racing-red edge; it turns with the car.
func _make_turntable() -> Node3D:
	var root := Node3D.new()
	root.name = "Turntable"
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = TURNTABLE_R
	cyl.bottom_radius = TURNTABLE_R
	cyl.height = CAR_Y
	cyl.radial_segments = 96
	disc.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.045, 0.048, 0.056)
	m.metallic = 0.0
	m.roughness = 0.6  # satin: a glossy plate mirrored the key as a white smear in the rear views
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	disc.material_override = m
	disc.position.y = CAR_Y * 0.5
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = TURNTABLE_R - 0.012
	tor.outer_radius = TURNTABLE_R + 0.005
	tor.rings = 96
	tor.ring_segments = 6
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = MSTheme.RED * 0.8
	ring.material_override = rm
	ring.scale = Vector3(1.0, 0.5, 1.0)
	ring.position.y = CAR_Y
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	return root


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
	_hud.preview_requested.connect(_on_preview_requested)
	_hud.car_step_pressed.connect(step_car)
	_hud.car_action_pressed.connect(car_action)
	_refresh_hud()


## Stats after one more level of the previewed part; empty when nothing is previewed or the part is maxed.
func _upgrade_preview(upgrades: Dictionary) -> Dictionary:
	if _preview_part.is_empty() or spec == null:
		return {}
	if int(upgrades.get(_preview_part, 0)) >= GameState.MAX_UPGRADE_LEVEL:
		return {}
	return GarageStats.preview_next(spec, upgrades, _preview_part)


func _on_preview_requested(part: String) -> void:
	if part == _preview_part:
		return
	_preview_part = part
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
