extends "res://devtools/capture_scenario.gd"
## Builds a small lit 3D scene in code, shoots it and runs a measure. Proves the harness works end to end.

const SHOT_NAME: String = "selftest_sphere"
const MEASURE_NAME: String = "selftest_measure"
const MEASURE_FRAMES: int = 600
const SETTLE_FRAMES: int = 30
const CAMERA_POS: Vector3 = Vector3(0.0, 2.2, 6.0)
const LOOK_AT: Vector3 = Vector3(0.0, 0.8, 0.0)
const SPHERE_RADIUS: float = 1.0
const FLOOR_SIZE: float = 20.0
const KEY_ENERGY: float = 2.0
const RIM_ENERGY: float = 4.0
const RIM_RANGE: float = 10.0
const RIM_POS: Vector3 = Vector3(-2.5, 1.5, 1.0)
const KEY_ROTATION_DEG: Vector3 = Vector3(-45.0, 30.0, 0.0)


func run() -> void:
	var root := Node3D.new()
	root.name = "SelftestScene"
	tree.root.add_child(root)
	root.add_child(_world_environment())
	root.add_child(_floor())
	root.add_child(_sphere())
	root.add_child(_key_light())
	root.add_child(_rim_light())
	var cam := Camera3D.new()
	cam.position = CAMERA_POS
	root.add_child(cam)
	cam.current = true
	cam.look_at(LOOK_AT)
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot(SHOT_NAME)
	await cap.measure(MEASURE_NAME, MEASURE_FRAMES)


func _world_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.4)
	env.ambient_light_energy = 0.5
	Settings.apply_to_environment(env)
	var we := WorldEnvironment.new()
	we.environment = env
	return we


func _floor() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.24, 0.27)
	mat.roughness = 0.6
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _sphere() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.45, 0.15)
	mat.metallic = 0.1
	mat.roughness = 0.35
	var mesh := SphereMesh.new()
	mesh.radius = SPHERE_RADIUS
	mesh.height = SPHERE_RADIUS * 2.0
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0.0, SPHERE_RADIUS, 0.0)
	return mi


func _key_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.light_color = Color(1.0, 0.95, 0.85)
	light.light_energy = KEY_ENERGY
	light.shadow_enabled = true
	light.rotation_degrees = KEY_ROTATION_DEG
	return light


func _rim_light() -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = Color(0.2, 0.8, 1.0)
	light.light_energy = RIM_ENERGY
	light.omni_range = RIM_RANGE
	light.position = RIM_POS
	return light
