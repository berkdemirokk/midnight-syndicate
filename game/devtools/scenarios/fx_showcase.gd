extends "res://devtools/capture_scenario.gd"
## Test rig, not art: a dark ground with a grey block standing in for the car. One shot each for
## nitro flame, tyre smoke, hit sparks and headlights, each at its strongest moment.

const BLOCK_SIZE: Vector3 = Vector3(1.9, 0.9, 4.2)
const SETTLE: int = 30
const MEASURE_FRAMES: int = 300
const CAM_POS: Vector3 = Vector3(3.5, 1.8, 7.5)
const CAM_LOOK: Vector3 = Vector3(0.0, 0.6, 1.0)
const CAM_FRONT_POS: Vector3 = Vector3(0.0, 1.6, 6.0)
const CAM_FRONT_LOOK: Vector3 = Vector3(0.0, 0.0, -8.0)


func run() -> void:
	var root := Node3D.new()
	root.name = "FxShowcase"
	tree.root.add_child(root)
	root.add_child(_world_environment())
	root.add_child(_ground())
	root.add_child(_block())
	# Rig light so lit smoke reads as grey (the rig has no scene lights; the smoke is not unshaded).
	var key := OmniLight3D.new()
	key.position = Vector3(1.5, 2.5, 4.5)
	key.omni_range = 14.0
	key.light_energy = 2.5
	key.light_color = Color(0.85, 0.9, 1.0)
	root.add_child(key)
	# CarFx normally sits under an ArcadeCar; here the stand-in block plays the car.
	var holder := Node3D.new()
	holder.position = Vector3(0.0, BLOCK_SIZE.y * 0.5, 0.0)
	root.add_child(holder)
	var flames := NitroFlame.new()
	holder.add_child(flames)
	flames.set_exhaust_points(PackedVector3Array([Vector3(-0.45, -0.15, 2.1), Vector3(0.45, -0.15, 2.1)]))
	var smoke := TireSmoke.new()
	holder.add_child(smoke)
	var sparks := Sparks.new()
	holder.add_child(sparks)
	var heads := Headlights.new()
	heads.lamp_points = PackedVector3Array([Vector3(-0.6, 0.0, -2.1), Vector3(0.6, 0.0, -2.1)])
	heads.set_on(false)
	holder.add_child(heads)
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.position = CAM_POS
	root.add_child(cam)
	cam.current = true
	cam.look_at(CAM_LOOK)
	var cam_front := Camera3D.new()
	cam_front.fov = 55.0
	cam_front.position = CAM_FRONT_POS
	root.add_child(cam_front)
	await cap.wait_frames(SETTLE)

	# 1. Nitro at full strength, just after ignition.
	flames.set_active(true)
	flames.set_strength(1.0)
	flames.pop()
	await cap.wait_seconds(0.25)
	await cap.shot("nitro_flame")
	await cap.measure("nitro_flame_measure", MEASURE_FRAMES)
	flames.set_active(false)

	# 2. Tyre smoke from both rear wheels while drifting left.
	var wheels := PackedVector3Array([root.to_global(Vector3(-0.82, 0.0, 1.3)), root.to_global(Vector3(0.82, 0.0, 1.3))])
	var slip := PackedFloat32Array([0.9, 0.9])
	smoke.update_puffs(wheels, slip, Vector3(1.0, 0.0, 0.0), 8.0)
	await cap.wait_seconds(0.9)
	await cap.shot("tire_smoke")
	await cap.measure("tire_smoke_measure", MEASURE_FRAMES)
	smoke.stop()
	# Let the old puffs fade out (1.2 s) so the sparks shot is not contaminated by smoke.
	await cap.wait_seconds(1.4)

	# 3. Hot sparks at a scrape point on the block's side.
	sparks.burst(root.to_global(Vector3(1.0, 0.2, 0.6)))
	await cap.wait_frames(8)  # GPU particles need a few frames before the first draw
	await cap.shot("sparks")
	await cap.measure("sparks_measure", MEASURE_FRAMES)
	sparks.stop()
	await cap.wait_seconds(1.5)

	# 4. Headlights on, camera behind the block looking down the beam so the lit ground shows.
	heads.set_on(true)
	cam_front.current = true
	cam_front.look_at(CAM_FRONT_LOOK)
	await cap.wait_frames(10)
	await cap.shot("headlights")
	await cap.measure("headlights_measure", MEASURE_FRAMES)


func _world_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.12, 0.18)
	env.ambient_light_energy = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_hdr_threshold = 1.0
	Settings.apply_to_environment(env)
	var we := WorldEnvironment.new()
	we.environment = env
	return we


func _ground() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.24, 0.26)
	mat.roughness = 0.5
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(60, 60)
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _block() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.37, 0.4)
	mat.roughness = 0.4
	mat.metallic = 0.2
	var box := BoxMesh.new()
	box.size = BLOCK_SIZE
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = Vector3(0.0, BLOCK_SIZE.y * 0.5, 0.0)
	return mi
