extends "res://tests/test_case.gd"
## CC BY 4.0 cars from vinish.dev (Kestrel Vanta, Arden Havoc): scene contract, source size within 5 %, wheel origins,
## budgets, LOD switching, paint and brake lights, spec character, and that the model rests on the suspension.
## Same checks as test_car_bruiser.gd, run for both cars.

const CARS: Array[Dictionary] = [
	{
		"id": "kestrel_vanta", "scene": "res://vehicles/kestrel_vanta/kestrel_vanta.tscn",
		"spec": "res://vehicles/specs/kestrel_vanta.tres", "name": "Kestrel Vanta",
		"len": 4.456, "width": 2.145, "height": 1.16,  # source GLB bounding box (metres), mid-engine-supercar.glb
		"axle": 1.32, "front_r": 0.33, "rear_r": 0.355, "wheelbase": 2.64,
	},
	{
		"id": "noctra_tayfun", "scene": "res://vehicles/noctra_tayfun/noctra_tayfun.tscn",
		"spec": "res://vehicles/specs/noctra_tayfun.tres", "name": "Noctra Tayfun",
		"len": 4.335, "width": 2.027, "height": 1.259,  # source GLB bounding box (metres), widebody-drift-coupe.glb
		"axle": 1.23, "front_r": 0.335, "rear_r": 0.35, "wheelbase": 2.46,
	},
	{
		"id": "noctra_meridian", "scene": "res://vehicles/noctra_meridian/noctra_meridian.tscn",
		"spec": "res://vehicles/specs/noctra_meridian.tres", "name": "Noctra Meridian",
		"len": 4.783, "width": 2.075, "height": 1.327,  # source GLB bounding box (metres), grand-tourer.glb
		"axle": 1.4, "front_r": 0.355, "rear_r": 0.36, "wheelbase": 2.8,
	},
	{
		"id": "kestrel_marten", "scene": "res://vehicles/kestrel_marten/kestrel_marten.tscn",
		"spec": "res://vehicles/specs/kestrel_marten.tres", "name": "Kestrel Marten",
		"len": 4.335, "width": 1.996, "height": 1.259,  # source GLB bounding box (metres), rear-engine-sports-coupe.glb
		"axle": 1.23, "front_r": 0.335, "rear_r": 0.35, "wheelbase": 2.46,
	},
	{
		"id": "arden_havoc", "scene": "res://vehicles/arden_havoc/arden_havoc.tscn",
		"spec": "res://vehicles/specs/arden_havoc.tres", "name": "Arden Havoc",
		"len": 4.87, "width": 2.11, "height": 1.368,  # source GLB bounding box (metres), muscle-coupe.glb
		"axle": 1.395, "front_r": 0.35, "rear_r": 0.36, "wheelbase": 2.79,
	},
]
const REQUIRED: PackedStringArray = [
	"body", "glass", "trim", "interior", "underbody", "exhaust", "plate_rear", "lights_front", "lights_rear",
	"wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR", "brake_FL", "brake_FR", "brake_RL", "brake_RR", "col_body",
]
const SIZE_TOL: float = 0.05
const POS_TOL_M: float = 0.02
const TRI_LOD0_MAX: int = 90000
const TRI_LOD1_MAX: int = 28000
const TRI_LOD2_MAX: int = 7000
const MAX_MATERIALS_LOD0: int = 14
const MAX_DRAW_OBJECTS_LOD0: int = 20
const MAX_GAP_M: float = 0.06
const PAINT_TEST: Color = Color(0.0, 0.0, 1.0)
const HERO_SPEC: String = "res://vehicles/specs/noctra_sable.tres"

var _spawned: Array[Node] = []


func _spawn(scene: String, force0: bool = false) -> CarLod:
	var packed: PackedScene = load(scene) as PackedScene
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
	for c: Dictionary in CARS:
		var car: CarLod = _spawn(c["scene"])
		await frames(2)
		for lod_name: String in ["LOD0", "LOD1", "LOD2"]:
			check(car.get_node_or_null(lod_name) != null, "%s %s missing" % [c["id"], lod_name])
		check(car.get_wheel_nodes().size() == 4, "%s get_wheel_nodes() should return 4 wheels" % c["id"])
		var lod0: Node = car.get_node("LOD0")
		for nm: String in REQUIRED:
			check(lod0.find_child(nm, true, false) != null, "%s LOD0 has no node %s" % [c["id"], nm])
		for lod_name: String in ["LOD0", "LOD1", "LOD2"]:
			var col: Node3D = car.get_node(lod_name).find_child("col_body", true, false) as Node3D
			if col != null:
				check(not col.is_visible_in_tree(), "%s %s/col_body renders" % [c["id"], lod_name])
		await _done()


func test_lod0_bounding_box_matches_source() -> void:
	for c: Dictionary in CARS:
		var car: CarLod = _spawn(c["scene"])
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
		metric("%s_bbox_size_m" % c["id"], [snappedf(sz.x, 0.001), snappedf(sz.y, 0.001), snappedf(sz.z, 0.001)])
		check_range(sz.z, float(c["len"]) * (1.0 - SIZE_TOL), float(c["len"]) * (1.0 + SIZE_TOL), "%s length (Z)" % c["id"])
		check_range(sz.x, float(c["width"]) * (1.0 - SIZE_TOL), float(c["width"]) * (1.0 + SIZE_TOL), "%s width (X)" % c["id"])
		check_range(sz.y, float(c["height"]) * (1.0 - SIZE_TOL), float(c["height"]) * (1.0 + SIZE_TOL), "%s height (Y)" % c["id"])
		await _done()


func test_wheel_origins_at_wheel_centres() -> void:
	for c: Dictionary in CARS:
		var car: CarLod = _spawn(c["scene"])
		await frames(1)
		var lod0: Node3D = car.get_node("LOD0") as Node3D
		var axle: float = float(c["axle"])
		var pairs: Array = [["wheel_FL", axle, float(c["front_r"])], ["wheel_FR", axle, float(c["front_r"])],
			["wheel_RL", -axle, float(c["rear_r"])], ["wheel_RR", -axle, float(c["rear_r"])]]
		for p: Array in pairs:
			var w: Node3D = lod0.find_child(p[0], true, false) as Node3D
			if w == null:
				check(false, "%s %s missing" % [c["id"], p[0]])
				continue
			var o: Vector3 = _to_root(w, car).origin
			check(absf(o.z - p[1]) <= POS_TOL_M, "%s %s z=%.3f expected %.3f" % [c["id"], p[0], o.z, p[1]])
			check(absf(o.y - p[2]) <= POS_TOL_M, "%s %s y=%.3f expected %.3f" % [c["id"], p[0], o.y, p[2]])
		await _done()


func test_budgets() -> void:
	for c: Dictionary in CARS:
		var car: CarLod = _spawn(c["scene"])
		await frames(1)
		var t0: int = _tris(car.get_node("LOD0"))
		var t1: int = _tris(car.get_node("LOD1"))
		var t2: int = _tris(car.get_node("LOD2"))
		metric("%s_tris" % c["id"], {"lod0": t0, "lod1": t1, "lod2": t2})
		check(t0 > 40000 and t0 <= TRI_LOD0_MAX, "%s LOD0 tris %d outside 40000..%d" % [c["id"], t0, TRI_LOD0_MAX])
		check(t1 <= TRI_LOD1_MAX, "%s LOD1 tris %d above %d" % [c["id"], t1, TRI_LOD1_MAX])
		check(t2 <= TRI_LOD2_MAX, "%s LOD2 tris %d above %d" % [c["id"], t2, TRI_LOD2_MAX])
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
		metric("%s_lod0_materials" % c["id"], names.size())
		metric("%s_lod0_draw_objects" % c["id"], draws)
		check(names.size() <= MAX_MATERIALS_LOD0, "%s LOD0 uses %d materials" % [c["id"], names.size()])
		check(draws <= MAX_DRAW_OBJECTS_LOD0, "%s LOD0 has %d draw objects" % [c["id"], draws])
		await _done()


func test_paint_is_per_car_and_brake_lights_work() -> void:
	for c: Dictionary in CARS:
		var a: CarLod = _spawn(c["scene"])
		var b: CarLod = _spawn(c["scene"])
		await frames(1)
		CarMaterials.set_paint(a, PAINT_TEST)
		var pa: StandardMaterial3D = _material(a, "M_Paint")
		var pb: StandardMaterial3D = _material(b, "M_Paint")
		check(pa != null and pb != null and pa != pb, "%s paint material not per car" % c["id"])
		if pa != null and pb != null:
			check(pa.albedo_color.is_equal_approx(PAINT_TEST), "%s paint of car A not changed" % c["id"])
			check(not pb.albedo_color.is_equal_approx(PAINT_TEST), "%s paint leaked into car B" % c["id"])
		CarMaterials.set_brake_lights(a, true)
		var lamp: StandardMaterial3D = _material(a, "M_LightRear")
		check(lamp != null and is_equal_approx(lamp.emission_energy_multiplier, CarMaterials.REAR_BRAKE), "%s brake lights not bright" % c["id"])
		await _done()


func test_lod_switching_and_wheel_sets() -> void:
	for c: Dictionary in CARS:
		var car: CarLod = _spawn(c["scene"])
		await frames(1)
		var cam: Camera3D = add(Camera3D.new()) as Camera3D
		cam.position = Vector3(0.0, 1.2, 10.0)
		cam.current = true
		cam.look_at(Vector3(0.0, 0.5, 0.0))
		await frames(2)
		check(car.get_active_lod() == 0, "%s 10 m should be LOD0, got %d" % [c["id"], car.get_active_lod()])
		cam.position = Vector3(0.0, 1.2, 40.0)
		await frames(2)
		check(car.get_active_lod() == 1, "%s 40 m should be LOD1, got %d" % [c["id"], car.get_active_lod()])
		var w: Array[Node3D] = car.get_wheel_nodes()
		check(w.size() == 4 and w[0].get_parent().name == "LOD1", "%s wheels of the active LOD should be LOD1's" % c["id"])
		cam.position = Vector3(0.0, 1.2, 100.0)
		await frames(2)
		check(car.get_active_lod() == 2, "%s 100 m should be LOD2, got %d" % [c["id"], car.get_active_lod()])
		var cams: Array[Node] = [cam]
		await cleanup(cams)
		await _done()


func test_spec_is_a_real_car_and_matches_the_model() -> void:
	var h: CarSpec = load(HERO_SPEC) as CarSpec
	for c: Dictionary in CARS:
		var s: CarSpec = load(c["spec"]) as CarSpec
		check(s != null, "%s spec did not load" % c["id"])
		if s == null or h == null:
			continue
		check(s.display_name == c["name"], "%s display_name is %s" % [c["id"], s.display_name])
		check(absf(s.wheelbase - float(c["wheelbase"])) <= POS_TOL_M * 2.0, "%s wheelbase %.2f vs model %.2f" % [c["id"], s.wheelbase, c["wheelbase"]])
		check(absf(s.wheel_radius_front - float(c["front_r"])) <= POS_TOL_M, "%s front radius does not match the model" % c["id"])
		check(absf(s.wheel_radius_rear - float(c["rear_r"])) <= POS_TOL_M, "%s rear radius does not match the model" % c["id"])
		check(s.top_speed_kmh > 200.0 and s.grip_front > 0.5, "%s is not a usable car" % c["id"])


func test_model_wheels_rest_on_the_suspension() -> void:
	for c: Dictionary in CARS:
		var spec: CarSpec = load(c["spec"]) as CarSpec
		var car: ArcadeCar = CarFactory.create(c["scene"], spec, Color.RED)
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
		check(car.is_grounded, "%s did not settle on the ground" % c["id"])
		var lod: Node = car.get_node("Visual").get_child(0)
		for lod_name: String in ["LOD0", "LOD1", "LOD2"]:
			var l: Node = lod.get_node_or_null(lod_name)
			var w: Node3D = l.find_child("wheel_FL", true, false) as Node3D if l != null else null
			check(w != null, "%s %s has no wheel_FL" % [c["id"], lod_name])
			if w == null:
				continue
			var static_y: float = (car.global_transform.affine_inverse() * w.global_transform.origin).y
			var phys_y: float = car.get_wheel_local_position(0).y
			metric("%s_%s_wheel_gap_m" % [c["id"], lod_name], snappedf(static_y - phys_y, 0.001))
			check(absf(static_y - phys_y) < MAX_GAP_M, "%s %s wheel %.3f m off the suspension" % [c["id"], lod_name, static_y - phys_y])
		await cleanup([car, ground])

