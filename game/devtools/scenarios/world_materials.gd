extends "res://devtools/capture_scenario.gd"
## Judging city materials at night: five buildings (one per district type) behind a road, kerb and
## sidewalk, neon signs, two street lamps. Built in code. Shots: wide, shopfront_close, windows_close,
## road_close, signs_close.

const SETTLE: int = 45
const ROAD_W: float = 14.0
const ROAD_L: float = 150.0
const KERB_W: float = 0.3
const KERB_H: float = 0.15
const SIDEWALK_W: float = 3.5
const BUILD_X: float = -20.0
const BUILD_SPACING: float = 26.0
const BUILDS: Array[String] = ["bld_neon_02_a", "bld_downtown_02_a", "bld_market_01_a", "bld_waterfront_01_a", "bld_parking_01_a"]
const KIT_B: String = "res://assets/world/kits/buildings/"
const KIT_P: String = "res://assets/world/kits/props/"
const SIGN_PROPS: Array[String] = ["prop_sign_box_lumen_cinema_4m", "prop_sign_blade_pixel_arcade", "prop_sign_open24h_moto_garage", "prop_sign_box_orbit_records_8m", "prop_sign_blade_hotel_arden"]
const SIGN_X: float = -10.7
const SIGN_Y: float = 6.5
const LAMP_X: float = -8.0
const LAMP_Y: float = 0.15
const LAMP_LIGHT_Y: float = 9.0
const LAMP_Z: Array[float] = [-30.0, 30.0]
const SHOTS: Dictionary = {
	"wide": [Vector3(4.0, 7.0, 70.0), Vector3(-18.0, 10.0, -10.0)],
	"shopfront_close": [Vector3(3.0, 2.4, -20.0), Vector3(-11.0, 3.0, -20.0)],
	"windows_close": [Vector3(3.0, 22.0, -46.0), Vector3(-11.0, 22.0, -46.0)],
	"road_close": [Vector3(-1.5, 1.6, 34.0), Vector3(-2.0, 0.0, 6.0)],
	"signs_close": [Vector3(2.0, 6.5, -4.0), Vector3(-10.7, 7.0, -4.0)],
}

var _root: Node3D
var _cam: Camera3D


func run() -> void:
	_root = Node3D.new()
	_root.name = "WorldMaterials"
	tree.root.add_child(_root)
	_root.add_child(_world_environment())
	_root.add_child(_moon_light())
	_root.add_child(_road())
	_root.add_child(_ground())
	_root.add_child(_buildings())
	_root.add_child(_signs())
	_root.add_child(_lamps())
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_root.add_child(_cam)
	_cam.current = true
	for name: String in SHOTS.keys():
		var pair: Array = SHOTS[name]
		_cam.position = pair[0]
		_cam.look_at(pair[1])
		await cap.wait_frames(SETTLE)
		await cap.shot(name)


func _world_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.024)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.12, 0.18)
	env.ambient_light_energy = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.07, 0.12)
	env.fog_density = 0.004
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_hdr_threshold = 1.0
	Settings.apply_to_environment(env)
	var we := WorldEnvironment.new()
	we.environment = env
	return we


func _moon_light() -> DirectionalLight3D:
	var d := DirectionalLight3D.new()
	d.light_color = Color(0.45, 0.55, 0.75)
	d.light_energy = 0.12
	d.shadow_enabled = false
	d.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
	return d


func _road() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0: float = -ROAD_W * 0.5
	var z0: float = -ROAD_L * 0.5
	for ix: int in int(ROAD_W):
		for iz: int in int(ROAD_L):
			# Red channel = puddle mask: mostly damp, a few standing patches (what the shader reads).
			var h: float = fposmod(sin(float(ix * 131 + iz * 17)) * 43758.5, 1.0)
			var a := Vector3(x0 + ix, 0.0, z0 + iz)
			var b := Vector3(x0 + ix + 1.0, 0.0, z0 + iz)
			var c := Vector3(x0 + ix, 0.0, z0 + iz + 1.0)
			var d := Vector3(x0 + ix + 1.0, 0.0, z0 + iz + 1.0)
			var pa: float = 0.9 if h > 0.86 else 0.25
			st.set_color(Color(pa, 0.0, 0.0))
			st.add_vertex(a)
			st.set_color(Color(pa, 0.0, 0.0))
			st.add_vertex(c)
			st.set_color(Color(pa, 0.0, 0.0))
			st.add_vertex(b)
			st.set_color(Color(pa, 0.0, 0.0))
			st.add_vertex(b)
			st.set_color(Color(pa, 0.0, 0.0))
			st.add_vertex(c)
			st.set_color(Color(pa, 0.0, 0.0))
			st.add_vertex(d)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Road"
	mi.mesh = st.commit()
	mi.material_override = MaterialLibrary.get_material("M_Asphalt")
	return mi


func _box(name: String, size: Vector3, pos: Vector3, mat_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = MaterialLibrary.get_material(mat_name)
	return mi


func _ground() -> Node3D:
	var g := Node3D.new()
	g.name = "Ground"
	g.add_child(_box("GroundL", Vector3(120.0, 0.1, 200.0), Vector3(-80.0, -0.05, 0.0), "M_Ground"))
	g.add_child(_box("GroundR", Vector3(120.0, 0.1, 200.0), Vector3(80.0, -0.05, 0.0), "M_Ground"))
	var kerb_x: float = -ROAD_W * 0.5 - KERB_W * 0.5
	var walk_x: float = -ROAD_W * 0.5 - KERB_W - SIDEWALK_W * 0.5
	g.add_child(_box("KerbL", Vector3(KERB_W, KERB_H, ROAD_L), Vector3(kerb_x, KERB_H * 0.5, 0.0), "M_Curb"))
	g.add_child(_box("KerbR", Vector3(KERB_W, KERB_H, ROAD_L), Vector3(-kerb_x, KERB_H * 0.5, 0.0), "M_Curb"))
	g.add_child(_box("PavingL", Vector3(SIDEWALK_W, KERB_H, ROAD_L), Vector3(walk_x, KERB_H * 0.5, 0.0), "M_Paving"))
	g.add_child(_box("PavingR", Vector3(SIDEWALK_W, KERB_H, ROAD_L), Vector3(-walk_x, KERB_H * 0.5, 0.0), "M_Paving"))
	return g


func _load_glb(path: String) -> Node3D:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		cap.fail("cannot load " + path)
		return Node3D.new()
	return packed.instantiate() as Node3D


func _buildings() -> Node3D:
	var holder := Node3D.new()
	holder.name = "Buildings"
	for i: int in BUILDS.size():
		var id: String = BUILDS[i]
		var b: Node3D = _load_glb(KIT_B + id + ".glb")
		b.name = id
		b.position = Vector3(BUILD_X, 0.15, (i - 2) * BUILD_SPACING)
		b.rotation = Vector3(0.0, PI * 0.5, 0.0)
		MaterialLibrary.apply(b, id)
		holder.add_child(b)
	return holder


func _signs() -> Node3D:
	var holder := Node3D.new()
	holder.name = "Signs"
	for i: int in SIGN_PROPS.size():
		var s: Node3D = _load_glb(KIT_P + SIGN_PROPS[i] + ".glb")
		s.name = SIGN_PROPS[i]
		s.position = Vector3(SIGN_X, SIGN_Y, (i - 2) * BUILD_SPACING + 4.0)
		s.rotation = Vector3(0.0, PI * 0.5, 0.0)
		MaterialLibrary.apply(s, "")
		holder.add_child(s)
	return holder


func _lamps() -> Node3D:
	var holder := Node3D.new()
	holder.name = "Lamps"
	for z: float in LAMP_Z:
		var lamp: Node3D = _load_glb(KIT_P + "prop_lamp_sodium.glb")
		lamp.position = Vector3(LAMP_X, LAMP_Y, z)
		lamp.rotation = Vector3(0.0, PI * 0.5, 0.0)
		MaterialLibrary.apply(lamp, "")
		holder.add_child(lamp)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.7, 0.42)
		light.light_energy = 7.0
		light.omni_range = 26.0
		light.shadow_enabled = false
		light.position = Vector3(LAMP_X + 1.8, LAMP_LIGHT_Y, z)
		holder.add_child(light)
	return holder
