extends "res://devtools/capture_scenario.gd"
## Evaluation studio for the Noctra Sable hero car. Built in code, for looking at the car only (not a game scene).
## Dark glossy floor, glow, one reflection probe, five long emissive light bars with matching lights.
## Shots: empty_studio (car hidden, baseline perf), front34, rear34, side, wheel_closeup, lights_on,
## lod1, lod2 (forced at 40 m and 100 m), paint_variants (three paints side by side).

const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const SETTLE_FRAMES: int = 30
const BAR_LAYER: int = 1  ## layer index 1 (value 2): bars are visible to the camera but not to the reflection probe
const SHOT_SETTLE_FRAMES: int = 8
const FLOOR_SIZE: float = 60.0
const FLOOR_ROUGHNESS: float = 0.15
const FLOOR_ALBEDO: Color = Color(0.02, 0.022, 0.028)
const SKY: Color = Color(0.012, 0.014, 0.022)
const GLOW_INTENSITY: float = 0.9
const GLOW_BLOOM: float = 0.06
const BAR_EMISSION: float = 1.2
const BAR_COLOUR: Color = Color(0.82, 0.9, 1.0)
const BAR_SPOT_ENERGY: float = 2.2
const BAR_SPOT_RANGE: float = 16.0
const KEY_ENERGY: float = 0.6
const CAM_FOV: float = 42.0
const CAR_SPACING: float = 3.4
const TARGET: Vector3 = Vector3(0.0, 0.55, 0.0)
const PAINTS: Array[Color] = [
	Color(0.557, 0.059, 0.118),  ## candy red, the brief's #8E0F1E
	Color(0.04, 0.09, 0.36),  ## deep blue
	Color(0.2, 0.21, 0.23),  ## graphite (lifted: at 0.12 it read as black)
]
const EYE_FRONT34: Vector3 = Vector3(-3.0, 1.1, 4.6)
const EYE_REAR34: Vector3 = Vector3(3.2, 1.2, -4.2)
const EYE_SIDE: Vector3 = Vector3(-5.4, 0.9, 0.0)
const EYE_WHEEL: Vector3 = Vector3(2.1, 0.55, 2.5)
const WHEEL_TARGET: Vector3 = Vector3(0.815, 0.335, 1.33)
const EYE_LOD1: Vector3 = Vector3(-14.0, 1.3, 38.0)  ## about 40 m from the car
const EYE_LOD2: Vector3 = Vector3(-34.0, 1.6, 94.0)  ## about 100 m from the car
const EYE_PAINT: Vector3 = Vector3(-3.6, 1.6, 8.0)

var _root: Node3D
var _cam: Camera3D
var _car: CarLod


func run() -> void:
	_root = Node3D.new()
	_root.name = "CarStudio"
	tree.root.add_child(_root)
	_root.add_child(_environment())
	_root.add_child(_floor())
	_root.add_child(_reflection_probe())
	_root.add_child(_key_light())
	_add_light_bars()
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_root.add_child(_cam)
	_cam.current = true
	_car = _spawn_car(PAINTS[0], false)
	await cap.wait_frames(SETTLE_FRAMES)

	_car.visible = false
	_aim(EYE_FRONT34)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("empty_studio")
	_car.visible = true

	_aim(EYE_FRONT34)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("front34")
	_aim(EYE_REAR34)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("rear34")
	_aim(EYE_SIDE)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("side")
	_aim_at(EYE_WHEEL, WHEEL_TARGET)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("wheel_closeup")

	CarMaterials.set_brake_lights(_car, true)
	_aim(EYE_REAR34)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("lights_on")
	CarMaterials.set_brake_lights(_car, false)

	_car.set_forced(1)
	_aim(EYE_LOD1)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("lod1")
	_car.set_forced(2)
	_aim(EYE_LOD2)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("lod2")
	_car.set_forced(-1)
	_car.queue_free()
	await cap.wait_frames(SHOT_SETTLE_FRAMES)

	var row: Array[CarLod] = []
	for i: int in PAINTS.size():
		row.append(_spawn_car(PAINTS[i], true, (i - 1) * CAR_SPACING))
	await cap.wait_frames(SETTLE_FRAMES)
	_aim(EYE_PAINT)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("paint_variants")


func _spawn_car(paint: Color, force0: bool, x: float = 0.0) -> CarLod:
	var packed: PackedScene = load(CAR_SCENE) as PackedScene
	var car: CarLod = packed.instantiate() as CarLod
	car.paint_colour = paint
	car.force_lod0 = force0
	car.position = Vector3(x, 0.0, 0.0)
	_root.add_child(car)
	return car


func _aim(eye: Vector3) -> void:
	_aim_at(eye, TARGET)


func _aim_at(eye: Vector3, target: Vector3) -> void:
	_cam.position = eye
	_cam.look_at(target)


func _environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	Settings.apply_to_environment(env)
	env.glow_enabled = true
	env.glow_intensity = GLOW_INTENSITY
	env.glow_bloom = GLOW_BLOOM
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	return we


func _floor() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FLOOR_ALBEDO
	mat.roughness = FLOOR_ROUGHNESS
	mat.metallic = 0.2
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _reflection_probe() -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.size = Vector3(40.0, 14.0, 40.0)
	probe.position = Vector3(0.0, 6.0, 0.0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.cull_mask = ((1 << 20) - 1) - (1 << BAR_LAYER)  ## the probe skips the bars, which are lit by their own lights
	return probe


func _key_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.light_color = Color(0.85, 0.92, 1.0)
	light.light_energy = KEY_ENERGY
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	return light


## Five long emissive bars: two overhead, two at the sides, one across the front. Each has a matching light.
func _add_light_bars() -> void:
	var bars: Array[Dictionary] = [
		{"pos": Vector3(0.0, 6.0, -3.0), "size": Vector3(9.0, 0.12, 0.3), "down": true},
		{"pos": Vector3(0.0, 6.0, 3.0), "size": Vector3(9.0, 0.12, 0.3), "down": true},
		{"pos": Vector3(-5.0, 2.4, 0.0), "size": Vector3(0.2, 0.2, 12.0), "down": false},
		{"pos": Vector3(5.0, 2.4, 0.0), "size": Vector3(0.2, 0.2, 12.0), "down": false},
		{"pos": Vector3(0.0, 1.8, 7.0), "size": Vector3(8.0, 0.18, 0.2), "down": false},
	]
	for b: Dictionary in bars:
		var pos: Vector3 = b["pos"]
		var size: Vector3 = b["size"]
		_root.add_child(_bar_mesh(pos, size))
		if b["down"]:
			_root.add_child(_bar_spot(pos))
		else:
			_root.add_child(_bar_omni(pos))


func _bar_mesh(pos: Vector3, size: Vector3) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BAR_COLOUR
	mat.emission_enabled = true
	mat.emission = BAR_COLOUR
	mat.emission_energy_multiplier = BAR_EMISSION
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1 << BAR_LAYER
	return mi


func _bar_spot(pos: Vector3) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.position = pos + Vector3(0.0, -0.2, 0.0)
	s.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	s.light_color = BAR_COLOUR
	s.light_energy = BAR_SPOT_ENERGY
	s.spot_range = BAR_SPOT_RANGE
	s.spot_angle = 55.0
	s.shadow_enabled = false
	return s


func _bar_omni(pos: Vector3) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = BAR_COLOUR
	o.light_energy = 1.0
	o.omni_range = 8.0
	o.shadow_enabled = false
	return o
