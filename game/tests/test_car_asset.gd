extends "res://tests/test_case.gd"
## Noctra Sable hero car: scene contract, col_body, bounding box, wheel origins, paint isolation, budgets, LOD switching.

const SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const REQUIRED: PackedStringArray = [
	"body", "glass", "trim", "interior", "underbody", "exhaust", "plate_rear", "lights_front", "lights_rear",
	"wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR", "brake_FL", "brake_FR", "brake_RL", "brake_RR", "col_body",
]
const LEN_M: float = 4.45  ## along Z, nose at +Z
const WIDTH_M: float = 1.96  ## along X
const HEIGHT_M: float = 1.19  ## along Y
const SIZE_TOL: float = 0.03
const FRONT_AXLE_M: float = 1.33
const FRONT_RADIUS_M: float = 0.335
const REAR_RADIUS_M: float = 0.35
const POS_TOL_M: float = 0.02
const TRI_LOD0_RANGE: Vector2 = Vector2(45000, 90000)
const TRI_LOD1_MAX: int = 28000
const TRI_LOD2_MAX: int = 7000
const MAX_MATERIALS_LOD0: int = 15  ## lead allowed M_Pillar on top of the brief's 14
const MAX_DRAW_OBJECTS_LOD0: int = 20
const PAINT_TEST: Color = Color(0.0, 0.0, 1.0)

var _spawned: Array[Node] = []


func _spawn(force0: bool = false) -> CarLod:
	var packed: PackedScene = load(SCENE) as PackedScene
	var car: CarLod = packed.instantiate() as CarLod
	car.set("force_lod0", force0)
	add(car)
	_spawned.append(car)
	return car


func _mesh_nodes(root: Node) -> Array[MeshInstance3D]:
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


func _material(root: Node, nm: String) -> StandardMaterial3D:
	for mi: MeshInstance3D in _mesh_nodes(root):
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var m: StandardMaterial3D = mi.get_active_material(s) as StandardMaterial3D
			if m != null and m.resource_name == nm:
				return m
	return null


func _tris(root: Node) -> int:
	var total: int = 0
	for mi: MeshInstance3D in _mesh_nodes(root):
		if not mi.visible or mi.mesh == null:
			continue
		var am: ArrayMesh = mi.mesh as ArrayMesh
		for s: int in mi.mesh.get_surface_count():
			var idx: int = am.surface_get_array_index_len(s) if am != null else 0
			if idx == 0 and am != null:
				idx = am.surface_get_array_len(s)
			total += idx / 3
	return total


func _visible_names(root: Node) -> Dictionary:
	var names: Dictionary = {}
	for mi: MeshInstance3D in _mesh_nodes(root):
		if mi.is_visible_in_tree():
			names[mi.name] = true
	return names


func _camera_at(p: Vector3) -> Camera3D:
	var cam: Camera3D = add(Camera3D.new()) as Camera3D
	cam.position = p
	cam.current = true
	cam.look_at(Vector3(0.0, 0.5, 0.0))
	return cam


func test_scene_instantiates_with_three_lods() -> void:
	var car: CarLod = _spawn()
	await frames(2)
	check(car.get_node_or_null("LOD0") != null, "LOD0 missing")
	check(car.get_node_or_null("LOD1") != null, "LOD1 missing")
	check(car.get_node_or_null("LOD2") != null, "LOD2 missing")
	check(car.get_wheel_nodes().size() == 4, "get_wheel_nodes() should return 4 wheels, got %d" % car.get_wheel_nodes().size())
	await cleanup(_spawned)
	_spawned.clear()


func test_required_nodes_exist_in_lod0() -> void:
	var car: CarLod = _spawn()
	await frames(1)
	var lod0: Node = car.get_node("LOD0")
	for nm: String in REQUIRED:
		check(lod0.find_child(nm, true, false) != null, "LOD0 has no node %s" % nm)
	await cleanup(_spawned)
	_spawned.clear()


func test_col_body_never_visible() -> void:
	var car: CarLod = _spawn()
	await frames(1)
	var found: int = 0
	for lod_name: String in ["LOD0", "LOD1", "LOD2"]:
		var col: Node = car.get_node(lod_name).find_child("col_body", true, false)
		if col == null:
			continue
		found += 1
		check(not (col as Node3D).visible, "%s/col_body is visible" % lod_name)
		check(not (col as Node3D).is_visible_in_tree(), "%s/col_body renders" % lod_name)
	metric("col_body_nodes", found)
	await cleanup(_spawned)
	_spawned.clear()


func test_lod0_bounding_box_matches_brief() -> void:
	var car: CarLod = _spawn()
	await frames(1)
	var lod0: Node3D = car.get_node("LOD0") as Node3D
	var box: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in _mesh_nodes(lod0):
		if mi.name == "col_body" or not mi.visible or mi.mesh == null:
			continue
		var b: AABB = _to_root(mi, car) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var sz: Vector3 = box.size
	metric("bbox_size_m", [snappedf(sz.x, 0.001), snappedf(sz.y, 0.001), snappedf(sz.z, 0.001)])
	check_range(sz.z, LEN_M * (1.0 - SIZE_TOL), LEN_M * (1.0 + SIZE_TOL), "LOD0 length (Z)")
	check_range(sz.x, WIDTH_M * (1.0 - SIZE_TOL), WIDTH_M * (1.0 + SIZE_TOL), "LOD0 width (X)")
	check_range(sz.y, HEIGHT_M * (1.0 - SIZE_TOL), HEIGHT_M * (1.0 + SIZE_TOL), "LOD0 height (Y)")
	await cleanup(_spawned)
	_spawned.clear()


func test_wheel_origins_at_wheel_centres() -> void:
	var car: CarLod = _spawn()
	await frames(1)
	var lod0: Node3D = car.get_node("LOD0") as Node3D
	var pairs: Array = [["wheel_FL", FRONT_AXLE_M, FRONT_RADIUS_M], ["wheel_FR", FRONT_AXLE_M, FRONT_RADIUS_M],
		["wheel_RL", -FRONT_AXLE_M, REAR_RADIUS_M], ["wheel_RR", -FRONT_AXLE_M, REAR_RADIUS_M]]
	for p: Array in pairs:
		var w: Node3D = lod0.find_child(p[0], true, false) as Node3D
		if w == null:
			check(false, "%s missing" % p[0])
			continue
		var o: Vector3 = _to_root(w, car).origin
		check(absf(o.z - p[1]) <= POS_TOL_M, "%s z=%.3f expected %.3f" % [p[0], o.z, p[1]])
		check(absf(o.y - p[2]) <= POS_TOL_M, "%s y(radius)=%.3f expected %.3f" % [p[0], o.y, p[2]])
	await cleanup(_spawned)
	_spawned.clear()


func test_paint_changes_only_own_car() -> void:
	var a: CarLod = _spawn()
	var b: CarLod = _spawn()
	await frames(1)
	var trim_before: Color = _material(a, "M_Trim").albedo_color
	CarMaterials.set_paint(a, PAINT_TEST)
	var pa: StandardMaterial3D = _material(a, "M_Paint")
	var pb: StandardMaterial3D = _material(b, "M_Paint")
	check(pa.albedo_color.is_equal_approx(PAINT_TEST), "paint of car A not changed")
	check(not pb.albedo_color.is_equal_approx(PAINT_TEST), "paint leaked into car B")
	check(pa != pb, "car A and B share one paint material")
	check(_material(a, "M_Trim").albedo_color.is_equal_approx(trim_before), "set_paint changed M_Trim")
	check(pa.clearcoat_enabled, "M_Paint clearcoat is off")
	for nm: String in ["M_Glass", "M_Rim", "M_LightRear"]:
		check(_material(a, nm) != null, "%s missing on car A" % nm)
	await cleanup(_spawned)
	_spawned.clear()


func test_triangle_and_material_budgets() -> void:
	var car: CarLod = _spawn()
	await frames(1)
	var t0: int = _tris(car.get_node("LOD0"))
	var t1: int = _tris(car.get_node("LOD1"))
	var t2: int = _tris(car.get_node("LOD2"))
	metric("tris", {"lod0": t0, "lod1": t1, "lod2": t2})
	check(t0 >= TRI_LOD0_RANGE.x and t0 <= TRI_LOD0_RANGE.y, "LOD0 tris %d outside 45000..90000" % t0)
	check(t1 <= TRI_LOD1_MAX, "LOD1 tris %d above 28000" % t1)
	check(t2 <= TRI_LOD2_MAX, "LOD2 tris %d above 7000" % t2)
	var names: Dictionary = {}
	var draws: int = 0
	for mi: MeshInstance3D in _mesh_nodes(car.get_node("LOD0")):
		if mi.name == "col_body" or not mi.visible or mi.mesh == null:
			continue
		draws += 1
		for s: int in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(s)
			if m != null:
				names[m.resource_name] = true
	metric("lod0_materials", names.size())
	metric("lod0_draw_objects", draws)
	check(names.size() <= MAX_MATERIALS_LOD0, "LOD0 uses %d materials, max 15" % names.size())
	check(draws <= MAX_DRAW_OBJECTS_LOD0, "LOD0 has %d objects, max 20" % draws)
	await cleanup(_spawned)
	_spawned.clear()


func test_brake_lights_toggle() -> void:
	var car: CarLod = _spawn()
	await frames(1)
	CarMaterials.set_brake_lights(car, true)
	check(is_equal_approx(_material(car, "M_LightRear").emission_energy_multiplier, CarMaterials.REAR_BRAKE), "brake lights not bright")
	CarMaterials.set_brake_lights(car, false)
	check(is_equal_approx(_material(car, "M_LightRear").emission_energy_multiplier, CarMaterials.REAR_REST), "brake lights not at rest level")
	await cleanup(_spawned)
	_spawned.clear()


func test_lod_switching_by_distance() -> void:
	var car: CarLod = _spawn()
	await frames(1)
	var cam: Camera3D = _camera_at(Vector3(0.0, 1.2, 10.0))
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
	check(car.lod_for_distance(21.9) == 0 and car.lod_for_distance(22.1) == 1, "LOD0/LOD1 boundary not at 22 m")
	check(car.lod_for_distance(69.9) == 1 and car.lod_for_distance(70.1) == 2, "LOD1/LOD2 boundary not at 70 m")
	var lod0_mi: MeshInstance3D = car.get_node("LOD0").find_child("body", true, false) as MeshInstance3D
	check(is_equal_approx(lod0_mi.visibility_range_end, 22.0), "LOD0 body range end is %.2f, expected 22" % lod0_mi.visibility_range_end)
	await cleanup(_spawned)
	_spawned.clear()
	var cam_nodes: Array[Node] = [cam]
	await cleanup(cam_nodes)


func test_force_lod0_keeps_lod0_only() -> void:
	var car: CarLod = _spawn(true)
	var cam: Camera3D = _camera_at(Vector3(0.0, 1.2, 100.0))
	await frames(2)
	check(car.get_node("LOD0").visible, "forced car LOD0 hidden")
	check(not car.get_node("LOD1").visible and not car.get_node("LOD2").visible, "forced car draws LOD1 or LOD2")
	check(car.get_active_lod() == 0, "forced car active LOD is %d" % car.get_active_lod())
	await cleanup(_spawned)
	_spawned.clear()
	var cam_nodes: Array[Node] = [cam]
	await cleanup(cam_nodes)


## Regression (2026-11-24): CarLod._ready() re-applied its default red after CarFactory had set the
## paint, so every rival in a race came out candy red.
func test_factory_paint_survives_entering_the_tree() -> void:
	var car: ArcadeCar = CarFactory.create(SCENE, CarSpec.new(), PAINT_TEST)
	add(car)
	await frames(2)
	var m: StandardMaterial3D = _material(car, "M_Paint")
	check(m != null, "no M_Paint material on the factory car")
	if m != null:
		check(m.albedo_color.is_equal_approx(PAINT_TEST), "factory paint lost: %s" % m.albedo_color)
	await cleanup([car])


func test_mirror_lod_stands_in_for_lod0() -> void:
	var car: CarLod = _spawn()
	await frames(2)
	car.build_mirror_lod()
	car.build_mirror_lod()  # second call is a no-op
	var copy: Node3D = car.get_mirror_lod()
	check(copy != null and car.find_children(CarLod.MIRROR_LOD_NAME, "", true, false).size() == 1, "exactly one mirror LOD expected")
	if copy != null:
		var lod1_meshes: Array[MeshInstance3D] = _mesh_nodes(car.get_node("LOD1"))
		var copy_meshes: Array[MeshInstance3D] = _mesh_nodes(copy)
		check(copy_meshes.size() == lod1_meshes.size() and copy_meshes.size() > 0, "mirror LOD mesh count differs from LOD1")
		for i: int in mini(copy_meshes.size(), lod1_meshes.size()):
			check(copy_meshes[i].mesh == lod1_meshes[i].mesh, "mirror LOD must share the LOD1 mesh resource")
			check(copy_meshes[i].layers == CarLod.MIRROR_LAYER_BIT, "mirror LOD mesh is not on the mirror-only layer")
			check(is_equal_approx(copy_meshes[i].visibility_range_end, CarLod.MIRROR_LOD2_START_M), "mirror LOD1 range end is not the LOD2 copy's start")
	var copy2: Node3D = car.find_child(CarLod.MIRROR_LOD2_NAME, true, false) as Node3D
	check(copy2 != null, "no mirror LOD2 copy")
	if copy2 != null:
		for mi: MeshInstance3D in _mesh_nodes(copy2):
			check(mi.layers == CarLod.MIRROR_LAYER_BIT and is_equal_approx(mi.visibility_range_begin, CarLod.MIRROR_LOD2_START_M) and is_equal_approx(mi.visibility_range_end, car.lod2_start_m), "mirror LOD2 copy layer or range wrong")
	for mi: MeshInstance3D in _mesh_nodes(car.get_node("LOD0")):
		check(mi.layers == CarLod.DETAIL_LAYER_BIT, "LOD0 mesh %s is not on the detail layer alone" % mi.name)
	for mi: MeshInstance3D in _mesh_nodes(car.get_node("LOD1")):
		check(mi.layers == CarLod.DETAIL_LAYER_BIT, "LOD1 mesh %s is not on the detail layer alone (the mirror sees the copies)" % mi.name)
	car.set_forced(2)
	check(not car.get_mirror_lod().visible and not (car.find_child(CarLod.MIRROR_LOD2_NAME, true, false) as Node3D).visible, "mirror LOD still visible with LOD2 forced")
	await cleanup(_spawned)
	_spawned.clear()
