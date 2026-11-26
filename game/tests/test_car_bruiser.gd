extends "res://tests/test_case.gd"
## Arden Bruiser (muscle coupe): scene contract, bounding box, wheel origins, budgets, LODs, paint, spec character
## (heavy, strong acceleration, loose rear) and that the model rests on the suspension the spec describes.

const SCENE: String = "res://vehicles/arden_bruiser/arden_bruiser.tscn"
const SPEC: String = "res://vehicles/specs/arden_bruiser.tres"
const HERO_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const REQUIRED: PackedStringArray = [
	"body", "glass", "trim", "interior", "underbody", "exhaust", "plate_rear", "lights_front", "lights_rear",
	"wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR", "brake_FL", "brake_FR", "brake_RL", "brake_RR", "col_body",
]
const LEN_M: float = 4.85
const WIDTH_M: float = 1.92
const HEIGHT_M: float = 1.36
const SIZE_TOL: float = 0.03
const AXLE_M: float = 1.425
const FRONT_RADIUS_M: float = 0.345
const REAR_RADIUS_M: float = 0.358
const POS_TOL_M: float = 0.02
const TRI_LOD0_MAX: int = 85000
const TRI_LOD1_MAX: int = 26000
const TRI_LOD2_MAX: int = 7000
const MAX_MATERIALS_LOD0: int = 15
const MAX_DRAW_OBJECTS_LOD0: int = 20
const MAX_GAP_M: float = 0.06
const PAINT_TEST: Color = Color(0.0, 0.0, 1.0)

var _spawned: Array[Node] = []


func _spawn(force0: bool = false) -> CarLod:
	var packed: PackedScene = load(SCENE) as PackedScene
	var car: CarLod = packed.instantiate() as CarLod
	car.set("force_lod0", force0)
	add(car)
	_spawned.append(car)
	return car


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


func _to_root(node: Node3D, root: Node) -> Transform3D:
	var xf: Transform3D = Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _tris(root: Node) -> int:
	var total: int = 0
	for mi: MeshInstance3D in _meshes(root):
		if not mi.visible or mi.mesh == null:
			continue
		var am: ArrayMesh = mi.mesh as ArrayMesh
		for s: int in mi.mesh.get_surface_count():
			var idx: int = am.surface_get_array_index_len(s) if am != null else 0
			if idx == 0 and am != null:
				idx = am.surface_get_array_len(s)
			total += idx / 3
	return total


func _material(root: Node, nm: String) -> StandardMaterial3D:
	for mi: MeshInstance3D in _meshes(root):
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var m: StandardMaterial3D = mi.get_active_material(s) as StandardMaterial3D
			if m != null and m.resource_name == nm:
				return m
	return null


func _done() -> void:
	await cleanup(_spawned)
	_spawned.clear()


func test_scene_has_three_lods_and_required_nodes() -> void:
	var car: CarLod = _spawn()
	await frames(2)
	for lod_name: String in ["LOD0", "LOD1", "LOD2"]:
		check(car.get_node_or_null(lod_name) != null, "%s missing" % lod_name)
	check(car.get_wheel_nodes().size() == 4, "get_wheel_nodes() should return 4 wheels")
	var lod0: Node = car.get_node("LOD0")
	for nm: String in REQUIRED:
		check(lod0.find_child(nm, true, false) != null, "LOD0 has no node %s" % nm)
	for lod_name: String in ["LOD0", "LOD1", "LOD2"]:
		var col: Node3D = car.get_node(lod_name).find_child("col_body", true, false) as Node3D
		if col != null:
			check(not col.is_visible_in_tree(), "%s/col_body renders" % lod_name)
	await _done()


func test_lod0_bounding_box_matches_brief() -> void:
	var car: CarLod = _spawn()
	await frames(1)
	var lod0: Node3D = car.get_node("LOD0") as Node3D
	var box: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in _meshes(lod0):
		if mi.name == "col_body" or not mi.visible or mi.mesh == null:
			continue
		var b: AABB = _to_root(mi, car) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var sz: Vector3 = box.size
	metric("bbox_size_m", [snappedf(sz.x, 0.001), snappedf(sz.y, 0.001), snappedf(sz.z, 0.001)])
	check_range(sz.z, LEN_M * (1.0 - SIZE_TOL), LEN_M * (1.0 + SIZE_TOL), "length (Z)")
	check_range(sz.x, WIDTH_M * (1.0 - SIZE_TOL), WIDTH_M * (1.0 + SIZE_TOL), "width (X)")
	check_range(sz.y, HEIGHT_M * (1.0 - SIZE_TOL), HEIGHT_M * (1.0 + SIZE_TOL), "height (Y)")
	await _done()


func test_wheel_origins_at_wheel_centres() -> void:
	var car: CarLod = _spawn()
	await frames(1)
	var lod0: Node3D = car.get_node("LOD0") as Node3D
	var pairs: Array = [["wheel_FL", AXLE_M, FRONT_RADIUS_M], ["wheel_FR", AXLE_M, FRONT_RADIUS_M],
		["wheel_RL", -AXLE_M, REAR_RADIUS_M], ["wheel_RR", -AXLE_M, REAR_RADIUS_M]]
	for p: Array in pairs:
		var w: Node3D = lod0.find_child(p[0], true, false) as Node3D
		if w == null:
			check(false, "%s missing" % p[0])
			continue
		var o: Vector3 = _to_root(w, car).origin
		check(absf(o.z - p[1]) <= POS_TOL_M, "%s z=%.3f expected %.3f" % [p[0], o.z, p[1]])
		check(absf(o.y - p[2]) <= POS_TOL_M, "%s y=%.3f expected %.3f" % [p[0], o.y, p[2]])
	await _done()


func test_budgets() -> void:
	var car: CarLod = _spawn()
	await frames(1)
	var t0: int = _tris(car.get_node("LOD0"))
	var t1: int = _tris(car.get_node("LOD1"))
	var t2: int = _tris(car.get_node("LOD2"))
	metric("tris", {"lod0": t0, "lod1": t1, "lod2": t2})
	check(t0 > 40000 and t0 <= TRI_LOD0_MAX, "LOD0 tris %d outside 40000..%d" % [t0, TRI_LOD0_MAX])
	check(t1 <= TRI_LOD1_MAX, "LOD1 tris %d above %d" % [t1, TRI_LOD1_MAX])
	check(t2 <= TRI_LOD2_MAX, "LOD2 tris %d above %d" % [t2, TRI_LOD2_MAX])
	var names: Dictionary = {}
	var draws: int = 0
	for mi: MeshInstance3D in _meshes(car.get_node("LOD0")):
		if mi.name == "col_body" or not mi.visible or mi.mesh == null:
			continue
		draws += 1
		for s: int in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(s)
			if m != null:
				names[m.resource_name] = true
	metric("lod0_materials", names.size())
	metric("lod0_draw_objects", draws)
	check(names.size() <= MAX_MATERIALS_LOD0, "LOD0 uses %d materials" % names.size())
	check(draws <= MAX_DRAW_OBJECTS_LOD0, "LOD0 has %d draw objects" % draws)
	await _done()


func test_paint_is_per_car_and_brake_lights_work() -> void:
	var a: CarLod = _spawn()
	var b: CarLod = _spawn()
	await frames(1)
	CarMaterials.set_paint(a, PAINT_TEST)
	var pa: StandardMaterial3D = _material(a, "M_Paint")
	var pb: StandardMaterial3D = _material(b, "M_Paint")
	check(pa != null and pb != null and pa != pb, "paint material not per car")
	if pa != null and pb != null:
		check(pa.albedo_color.is_equal_approx(PAINT_TEST), "paint of car A not changed")
		check(not pb.albedo_color.is_equal_approx(PAINT_TEST), "paint leaked into car B")
	CarMaterials.set_brake_lights(a, true)
	var lamp: StandardMaterial3D = _material(a, "M_LightRear")
	check(lamp != null and is_equal_approx(lamp.emission_energy_multiplier, CarMaterials.REAR_BRAKE), "brake lights not bright")
	await _done()


func test_lod_switching_and_wheel_sets() -> void:
	var car: CarLod = _spawn()
	await frames(1)
	var cam: Camera3D = add(Camera3D.new()) as Camera3D
	cam.position = Vector3(0.0, 1.2, 10.0)
	cam.current = true
	cam.look_at(Vector3(0.0, 0.5, 0.0))
	await frames(2)
	check(car.get_active_lod() == 0, "10 m should be LOD0, got %d" % car.get_active_lod())
	cam.position = Vector3(0.0, 1.2, 40.0)
	await frames(2)
	check(car.get_active_lod() == 1, "40 m should be LOD1, got %d" % car.get_active_lod())
	var w: Array[Node3D] = car.get_wheel_nodes()
	check(w.size() == 4 and w[0].get_parent().name == "LOD1", "wheels of the active LOD should be LOD1's")
	cam.position = Vector3(0.0, 1.2, 100.0)
	await frames(2)
	check(car.get_active_lod() == 2, "100 m should be LOD2, got %d" % car.get_active_lod())
	await _done()
	var cams: Array[Node] = [cam]
	await cleanup(cams)


func test_factory_paint_survives_entering_the_tree() -> void:
	var spec: CarSpec = load(SPEC) as CarSpec
	var car: ArcadeCar = CarFactory.create(SCENE, spec, PAINT_TEST)
	add(car)
	await frames(2)
	var m: StandardMaterial3D = _material(car, "M_Paint")
	check(m != null and m.albedo_color.is_equal_approx(PAINT_TEST), "factory paint lost")
	check(not bool(car.get_meta("dev_car", true)), "factory fell back to the dev mule")
	await cleanup([car])


func test_spec_is_heavy_strong_and_loose() -> void:
	var s: CarSpec = load(SPEC) as CarSpec
	var h: CarSpec = load(HERO_SPEC) as CarSpec
	check(s != null and h != null, "spec did not load")
	if s == null or h == null:
		return
	check(s.display_name == "Arden Bruiser", "display_name is %s" % s.display_name)
	check(s.mass_kg > h.mass_kg * 1.25, "not heavy: %.0f kg vs hero %.0f" % [s.mass_kg, h.mass_kg])
	check(s.engine_force / s.mass_kg > h.engine_force / h.mass_kg * 1.1, "acceleration not stronger than the hero")
	check(s.grip_rear < s.grip_front and s.grip_rear < h.grip_rear, "rear is not looser than front and hero")
	check(s.drift_rear_grip_mult < h.drift_rear_grip_mult, "drift rear grip not lower than the hero")
	check(s.drift_entry_slip_deg < h.drift_entry_slip_deg and s.drift_entry_speed_kmh < h.drift_entry_speed_kmh, "drift entry not easier than the hero")
	check(is_equal_approx(s.wheelbase, 2.85), "wheelbase %.2f" % s.wheelbase)
	metric("accel_ratio_vs_hero", snappedf((s.engine_force / s.mass_kg) / (h.engine_force / h.mass_kg), 0.01))


func test_model_wheels_rest_on_the_suspension() -> void:
	var spec: CarSpec = load(SPEC) as CarSpec
	var car: ArcadeCar = CarFactory.create(SCENE, spec, Color.RED)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	add(ground)
	add(car)
	car.global_position = Vector3(0.0, 1.0, 0.0)
	await frames(150)
	check(car.is_grounded, "car did not settle on the ground")
	var lod: Node = car.get_node("Visual").get_child(0)
	for lod_name: String in ["LOD0", "LOD1", "LOD2"]:
		var l: Node = lod.get_node_or_null(lod_name)
		var w: Node3D = l.find_child("wheel_FL", true, false) as Node3D if l != null else null
		check(w != null, "%s has no wheel_FL" % lod_name)
		if w == null:
			continue
		var static_y: float = (car.global_transform.affine_inverse() * w.global_transform.origin).y
		var phys_y: float = car.get_wheel_local_position(0).y
		metric("%s_wheel_gap_m" % lod_name, snappedf(static_y - phys_y, 0.001))
		check(absf(static_y - phys_y) < MAX_GAP_M, "%s wheel %.3f m off the suspension" % [lod_name, static_y - phys_y])
	await cleanup([car, ground])
