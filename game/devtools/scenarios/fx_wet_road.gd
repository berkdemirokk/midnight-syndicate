extends "res://devtools/capture_scenario.gd"
## Test rig, not art: a 14 m x 200 m road with a painted puddle mask and wear groove, a row of lamps,
## neon panels on plain dark walls. Shots: dry, wet, wet + rain, wet + planar reflection.
## Built in code so the look can be judged with no level art in the way.

const ROAD_W: float = 14.0
const ROAD_L: float = 200.0
const PUDDLE_SEED: int = 7
const PUDDLE_COUNT: int = 26
const SETTLE: int = 30
const MEASURE_FRAMES: int = 300
const CAM_POS: Vector3 = Vector3(2.5, 1.5, 55.0)
const CAM_LOOK: Vector3 = Vector3(-1.0, 0.8, -60.0)
const TEX_ROOT: String = "res://assets/textures/cc0/asphalt_02/"
const LAMP_STEP: float = 20.0
const LAMP_Y: float = 7.5
const LAMP_X: float = 9.0
const NEON_COLORS: Array[Color] = [Color(0.2, 0.95, 1.0), Color(1.0, 0.2, 0.85), Color(1.0, 0.65, 0.15)]

var _road_mat: ShaderMaterial
var _rain: Node3D
var _planar: PlanarReflection


func run() -> void:
	var root := Node3D.new()
	root.name = "FxWetRoad"
	tree.root.add_child(root)
	root.add_child(_world_environment())
	root.add_child(_road())
	root.add_child(_walls())
	root.add_child(_lamps())
	root.add_child(_neons())
	root.add_child(_fill_light())
	_rain = (load("res://fx/rain.tscn") as PackedScene).instantiate()
	root.add_child(_rain)
	_planar = PlanarReflection.new()
	_planar.plane_height = 0.0
	root.add_child(_planar)
	_planar.add_target_material(_road_mat)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.position = CAM_POS
	root.add_child(cam)
	cam.current = true
	cam.look_at(CAM_LOOK)

	_set_state(0.0, 0.0, false, false)
	await cap.wait_frames(SETTLE)
	await cap.shot("dry")
	await cap.measure("dry_measure", MEASURE_FRAMES)

	_set_state(1.0, 0.0, false, false)
	await cap.wait_frames(SETTLE)
	await cap.shot("wet")
	await cap.measure("wet_measure", MEASURE_FRAMES)

	_set_state(1.0, 1.0, true, false)
	await cap.wait_frames(SETTLE)
	await cap.shot("wet_rain")
	await cap.measure("wet_rain_measure", MEASURE_FRAMES)

	_set_state(1.0, 1.0, true, true)
	await cap.wait_frames(SETTLE)
	await cap.shot("wet_rain_planar")
	await cap.measure("wet_rain_planar_measure", MEASURE_FRAMES)


func _set_state(wet: float, rain_i: float, rain_on: bool, planar_on: bool) -> void:
	_road_mat.set_shader_parameter("wetness", wet)
	_road_mat.set_shader_parameter("rain_intensity", rain_i)
	_rain.call("set_enabled", rain_on)
	_planar.call("set_enabled", planar_on)


func _world_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.14, 0.2)
	env.ambient_light_energy = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.1)
	env.fog_density = 0.008
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_hdr_threshold = 1.0
	Settings.apply_to_environment(env)
	var we := WorldEnvironment.new()
	we.environment = env
	return we


func _fill_light() -> DirectionalLight3D:
	var d := DirectionalLight3D.new()
	d.light_color = Color(0.5, 0.6, 0.8)
	d.light_energy = 0.35  ## test rig fill so the road near the camera is readable; not art
	d.shadow_enabled = false
	d.rotation_degrees = Vector3(-70.0, 20.0, 0.0)
	return d


func _road() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = PUDDLE_SEED
	var puddles: Array[Vector4] = []
	for i: int in PUDDLE_COUNT:
		puddles.append(Vector4(rng.randf_range(-ROAD_W * 0.5, ROAD_W * 0.5), rng.randf_range(-ROAD_L * 0.5, ROAD_L * 0.5), rng.randf_range(2.5, 6.0), 1.0))
	var x0: float = -ROAD_W * 0.5
	var z0: float = -ROAD_L * 0.5
	var cells_x: int = int(ROAD_W)
	var cells_z: int = int(ROAD_L)
	for ix: int in cells_x:
		for iz: int in cells_z:
			var a := Vector3(x0 + ix, 0.0, z0 + iz)
			var b := Vector3(x0 + ix + 1.0, 0.0, z0 + iz)
			var c := Vector3(x0 + ix, 0.0, z0 + iz + 1.0)
			var d := Vector3(x0 + ix + 1.0, 0.0, z0 + iz + 1.0)
			for v: Vector3 in [a, b, c, b, d, c]:
				st.set_color(_vertex_colour(v, puddles))
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(v.x, v.z))
				st.add_vertex(v)
	var mesh: ArrayMesh = st.commit()
	_road_mat = _make_road_material()
	mesh.surface_set_material(0, _road_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Road"
	mi.layers = 1 << 1  # layer 2: left out of the planar mirror view (PlanarReflection.excluded_layers)
	return mi


## R = puddle mask from the painted blobs, G = wear: the racing groove along x = -2.
func _vertex_colour(v: Vector3, puddles: Array[Vector4]) -> Color:
	var r: float = 0.0
	for p: Vector4 in puddles:
		var dd: float = Vector2(v.x - p.x, (v.z - p.y) * 0.8).length()
		r = maxf(r, 1.0 - smoothstep(p.z * 0.6, p.z, dd))
	var g: float = 1.0 - smoothstep(0.6, 1.4, absf(v.x + 2.0))
	return Color(r, g, 0.0, 1.0)


func _make_road_material() -> ShaderMaterial:
	var sh := load("res://shaders/wet_asphalt.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("albedo_tex", load(TEX_ROOT + "basecolor.jpg"))
	mat.set_shader_parameter("normal_tex", load(TEX_ROOT + "normal.jpg"))
	mat.set_shader_parameter("roughness_tex", load(TEX_ROOT + "roughness.jpg"))
	mat.set_shader_parameter("tile_metres", 4.0)
	mat.set_shader_parameter("puddle_level", 1.0)
	mat.set_shader_parameter("tint", Color(1, 1, 1, 1))
	return mat


func _walls() -> Node3D:
	var n := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.045, 0.055)
	mat.roughness = 0.9
	for s: float in [-1.0, 1.0]:
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 14.0, ROAD_L)
		box.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.position = Vector3(s * (ROAD_W * 0.5 + 6.0), 7.0, 0.0)
		n.add_child(mi)
	return n


func _lamps() -> Node3D:
	var n := Node3D.new()
	var head := SphereMesh.new()
	head.radius = 0.25
	head.height = 0.5
	var z: float = -ROAD_L * 0.5 + 10.0
	var i: int = 0
	while z < ROAD_L * 0.5:
		for s: float in [-1.0, 1.0]:
			var sodium: bool = (i % 2) == 0
			var col: Color = Color(1.0, 0.6, 0.22) if sodium else Color(0.7, 0.85, 1.0)
			var light := OmniLight3D.new()
			light.light_color = col
			light.light_energy = 6.0
			light.omni_range = 22.0
			light.shadow_enabled = false
			light.position = Vector3(s * LAMP_X, LAMP_Y, z)
			n.add_child(light)
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = col * 4.0
			var mi := MeshInstance3D.new()
			mi.mesh = head
			mi.material_override = m
			mi.position = light.position
			n.add_child(mi)
		z += LAMP_STEP
		i += 1
	return n


func _neons() -> Node3D:
	var n := Node3D.new()
	var sh := load("res://shaders/neon.gdshader") as Shader
	var i: int = 0
	for s: float in [-1.0, 1.0]:
		var z: float = -60.0
		while z <= 60.0:
			var mat := ShaderMaterial.new()
			mat.shader = sh
			mat.set_shader_parameter("base_color", NEON_COLORS[i % NEON_COLORS.size()])
			mat.set_shader_parameter("energy", 6.0)
			var quad := QuadMesh.new()
			quad.size = Vector2(3.0, 1.6)
			quad.material = mat
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.position = Vector3(s * (ROAD_W * 0.5 - 0.1), 4.0, z)
			mi.rotation_degrees = Vector3(0.0, -90.0 * s, 0.0)
			n.add_child(mi)
			z += 22.0
			i += 1
	return n
