extends "res://tests/test_case.gd"
## Noctra Vela hot hatch: scene contract, size, wheel origins, budgets, seating on the suspension, straight-line drive.

const SCENE: String = "res://vehicles/noctra_vela/noctra_vela.tscn"
const SPEC_PATH: String = "res://vehicles/specs/noctra_vela.tres"
const SABLE_SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const REQUIRED: PackedStringArray = [
	"body", "glass", "trim", "interior", "underbody", "exhaust", "plate_rear", "lights_front", "lights_rear",
	"wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR", "brake_FL", "brake_FR", "brake_RL", "brake_RR", "col_body",
]
const LEN_M: float = 4.337  ## along Z; licensed "Rally Hatchback" since 2026-11-27: its source GLB bounding box
const WIDTH_M: float = 1.863  ## the body node only, along X (arches and mirrors are other nodes; the whole car is 2.10 m)
const HEIGHT_M: float = 1.523  ## along Y, with the roof scoop
const SIZE_TOL: float = 0.03
const AXLE_Z_M: float = 1.30
const FRONT_X_M: float = 0.775
const REAR_X_M: float = 0.775
const RADIUS_M: float = 0.325
const POS_TOL_M: float = 0.02
const TRI_LOD0_MAX: int = 90000  ## the licensed-car contract (test_car_licensed.gd)
const TRI_LOD1_MAX: int = 28000
const TRI_LOD2_MAX: int = 7000
const MAX_GAP_M: float = 0.06
const GRAVITY_SETTLE_FRAMES: int = 150

var _spawned: Array[Node] = []


func _spawn(force0: bool = false) -> CarLod:
	var car: CarLod = (load(SCENE) as PackedScene).instantiate() as CarLod
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


func _ground() -> StaticBody3D:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 900.0)
	cs.shape = box
	cs.position = Vector3(0.0, -0.5, -400.0)
	ground.add_child(cs)
	return ground


func test_vela_loads_with_four_wheels_and_all_nodes() -> void:
	var car: CarLod = _spawn()
	await frames(2)
	check(car.get_wheel_nodes().size() == 4, "get_wheel_nodes() should return 4 wheels, got %d" % car.get_wheel_nodes().size())
	for lod_name: String in ["LOD0", "LOD1", "LOD2"]:
		var lod: Node = car.get_node_or_null(lod_name)
		check(lod != null, "%s missing" % lod_name)
		if lod == null:
			continue
		for nm: String in ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR", "body", "col_body"]:
			check(lod.find_child(nm, true, false) != null, "%s has no node %s" % [lod_name, nm])
		var col: Node3D = lod.find_child("col_body", true, false) as Node3D
		if col != null:
			check(not col.is_visible_in_tree(), "%s/col_body renders" % lod_name)
	var lod0: Node = car.get_node("LOD0")
	for nm: String in REQUIRED:
		check(lod0.find_child(nm, true, false) != null, "LOD0 has no node %s" % nm)
	var paint: StandardMaterial3D = null
	for mi: MeshInstance3D in _mesh_nodes(car):
		for s: int in mi.mesh.get_surface_count() if mi.mesh != null else 0:
			var m: StandardMaterial3D = mi.get_active_material(s) as StandardMaterial3D
			if m != null and m.resource_name == "M_Paint":
				paint = m
	check(paint != null and paint.clearcoat_enabled, "M_Paint missing or without clearcoat (the game binds materials by name)")
	await cleanup(_spawned)
	_spawned.clear()


func test_vela_size_wheels_and_budgets() -> void:
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
	var body: MeshInstance3D = lod0.find_child("body", true, false) as MeshInstance3D
	var bw: float = (_to_root(body, car) * body.mesh.get_aabb()).size.x
	metric("bbox_size_m", [snappedf(box.size.x, 0.001), snappedf(box.size.y, 0.001), snappedf(box.size.z, 0.001)])
	metric("body_width_m", snappedf(bw, 0.001))
	check_range(box.size.z, LEN_M * (1.0 - SIZE_TOL), LEN_M * (1.0 + SIZE_TOL), "Vela length (Z)")
	check_range(box.size.y, HEIGHT_M * (1.0 - SIZE_TOL), HEIGHT_M * (1.0 + SIZE_TOL), "Vela height (Y)")
	check_range(bw, WIDTH_M * (1.0 - SIZE_TOL), WIDTH_M * (1.0 + SIZE_TOL), "Vela body width (X)")
	var pairs: Array = [["wheel_FL", FRONT_X_M, AXLE_Z_M], ["wheel_FR", -FRONT_X_M, AXLE_Z_M],
		["wheel_RL", REAR_X_M, -AXLE_Z_M], ["wheel_RR", -REAR_X_M, -AXLE_Z_M]]
	for p: Array in pairs:
		var w: Node3D = lod0.find_child(p[0], true, false) as Node3D
		if w == null:
			check(false, "%s missing" % p[0])
			continue
		var o: Vector3 = _to_root(w, car).origin
		check(absf(o.x - p[1]) <= POS_TOL_M and absf(o.z - p[2]) <= POS_TOL_M, "%s at (%.3f, %.3f), expected (%.3f, %.3f)" % [p[0], o.x, o.z, p[1], p[2]])
		check(absf(o.y - RADIUS_M) <= POS_TOL_M, "%s centre height %.3f, expected the tyre radius %.3f" % [p[0], o.y, RADIUS_M])
	var t0: int = _tris(car.get_node("LOD0"))
	var t1: int = _tris(car.get_node("LOD1"))
	var t2: int = _tris(car.get_node("LOD2"))
	metric("tris", {"lod0": t0, "lod1": t1, "lod2": t2})
	check(t0 <= TRI_LOD0_MAX, "LOD0 tris %d above %d" % [t0, TRI_LOD0_MAX])
	check(t1 <= TRI_LOD1_MAX, "LOD1 tris %d above %d" % [t1, TRI_LOD1_MAX])
	check(t2 <= TRI_LOD2_MAX, "LOD2 tris %d above %d" % [t2, TRI_LOD2_MAX])
	await cleanup(_spawned)
	_spawned.clear()


func test_vela_spec_is_lighter_and_quicker_than_the_sable() -> void:
	var v: CarSpec = load(SPEC_PATH) as CarSpec
	var s: CarSpec = load(SABLE_SPEC_PATH) as CarSpec
	check(v != null and s != null, "spec did not load")
	check(v.mass_kg < s.mass_kg, "Vela is not lighter than the Sable")
	check(v.top_speed_kmh < s.top_speed_kmh, "Vela top speed is not below the Sable's")
	check(v.steer_angle_low_deg > s.steer_angle_low_deg and v.steer_speed > s.steer_speed, "Vela steering is not quicker")
	check(is_equal_approx(v.wheelbase, 2.0 * AXLE_Z_M) and is_equal_approx(v.track_front, 2.0 * FRONT_X_M) and is_equal_approx(v.track_rear, 2.0 * REAR_X_M), "spec wheel layout differs from the model")
	check(is_equal_approx(v.wheel_radius_front, RADIUS_M) and is_equal_approx(v.wheel_radius_rear, RADIUS_M), "spec wheel radius differs from the model")


func test_vela_wheels_rest_on_the_suspension() -> void:
	var spec: CarSpec = load(SPEC_PATH) as CarSpec
	var car: ArcadeCar = CarFactory.create(SCENE, spec, Color.RED)
	var ground: StaticBody3D = _ground()
	add(ground)
	add(car)
	car.global_position = Vector3(0.0, 1.0, 0.0)
	await frames(GRAVITY_SETTLE_FRAMES)
	check(car.is_grounded, "car did not settle on the ground")
	var lod: Node = car.get_node("Visual").get_child(0)
	for lod_name: String in ["LOD0", "LOD1", "LOD2"]:
		var l: Node = lod.get_node_or_null(lod_name)
		check(l != null, "%s missing" % lod_name)
		if l == null:
			continue
		var w: Node3D = l.find_child("wheel_FL", true, false) as Node3D
		if w == null:
			check(false, "%s has no wheel_FL" % lod_name)
			continue
		var static_y: float = (car.global_transform.affine_inverse() * w.global_transform.origin).y
		var phys_y: float = car.get_wheel_local_position(0).y
		metric("%s_wheel_gap_m" % lod_name, snappedf(static_y - phys_y, 0.001))
		check(absf(static_y - phys_y) < MAX_GAP_M, "%s wheel centre %.3f m off the suspension (static %.3f, physics %.3f)" % [lod_name, static_y - phys_y, static_y, phys_y])
	await cleanup([car, ground])


func test_vela_drives_a_straight_line() -> void:
	var spec: CarSpec = load(SPEC_PATH) as CarSpec
	var car: ArcadeCar = CarFactory.create(SCENE, spec, Color.RED)
	var ground: StaticBody3D = _ground()
	add(ground)
	add(car)
	car.global_position = Vector3(0.0, 1.0, 0.0)
	await frames(GRAVITY_SETTLE_FRAMES)
	var z0: float = car.global_position.z
	for i: int in 300:
		car.input.throttle = 1.0
		car.input.steer = 0.0
		await frames(1)
	var travelled: float = z0 - car.global_position.z  ## the car drives toward -Z
	var heading: float = (-car.global_basis.z).dot(Vector3(0.0, 0.0, -1.0))
	metric("vela_straight_travelled_m", snappedf(travelled, 0.1))
	metric("vela_straight_speed_kmh", snappedf(car.speed_kmh, 0.1))
	metric("vela_straight_lateral_m", snappedf(car.global_position.x, 0.001))
	check(car.is_grounded, "car left the ground on a flat road")
	check(travelled > 40.0, "car only travelled %.1f m in 5 s of full throttle" % travelled)
	check(car.speed_kmh > 60.0, "speed after 5 s is only %.1f km/h" % car.speed_kmh)
	check(car.speed_kmh <= spec.top_speed_kmh * 1.02, "speed %.1f km/h is above the spec top speed" % car.speed_kmh)
	check(absf(car.global_position.x) < 0.5, "car wandered %.2f m sideways with the wheel straight" % car.global_position.x)
	check(heading > 0.9995, "car yawed off the straight line (heading dot %.5f)" % heading)
	await cleanup([car, ground])
