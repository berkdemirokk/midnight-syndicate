extends "res://tests/test_case.gd"
## Kestrel GT-R (second car): scene contract, LOD budgets, wheels, seating on the suspension, driving, and its
## place against the Noctra Sable R (fastest, heavier, less agile).

const SCENE: String = "res://vehicles/kestrel_gtr/kestrel_gtr.tscn"
const SPEC_PATH: String = "res://vehicles/specs/kestrel_gtr.tres"
const HERO_SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const FlatWorld = preload("res://tests/helpers/flat_world.gd")
const REQUIRED: PackedStringArray = [
	"body", "glass", "trim", "interior", "underbody", "exhaust", "plate_rear", "lights_front", "lights_rear",
	"wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR", "brake_FL", "brake_FR", "brake_RL", "brake_RR", "col_body",
]
const LEN_M: float = 4.652  ## licensed "Electric Super GT" since 2026-11-27: its source GLB bounding box
const WIDTH_M: float = 2.096
const HEIGHT_M: float = 1.40
const SIZE_TOL: float = 0.03
const MAX_GAP_M: float = 0.06
const TRI_LOD0_MAX: int = 90000  ## the licensed-car contract (test_car_licensed.gd)
const TRI_LOD1_MAX: int = 28000
const TRI_LOD2_MAX: int = 7000


func _mesh_nodes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


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


func _to_root(node: Node3D, root: Node) -> Transform3D:
	var xf: Transform3D = Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func test_loads_with_four_wheels_and_all_nodes() -> void:
	var packed: PackedScene = load(SCENE) as PackedScene
	check(packed != null, "kestrel_gtr.tscn did not load")
	if packed == null:
		return
	var car: CarLod = packed.instantiate() as CarLod
	check(car != null, "scene root is not a CarLod")
	if car == null:
		return
	add(car)
	await frames(2)
	check(car.get_wheel_nodes().size() == 4, "get_wheel_nodes() returned %d, expected 4" % car.get_wheel_nodes().size())
	for lod_name: String in ["LOD0", "LOD1", "LOD2"]:
		var lod: Node = car.get_node_or_null(lod_name)
		check(lod != null, "%s missing" % lod_name)
		if lod == null:
			continue
		for nm: String in ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR", "body", "col_body"]:
			check(lod.find_child(nm, true, false) != null, "%s has no node %s" % [lod_name, nm])
	var lod0: Node = car.get_node("LOD0")
	for nm: String in REQUIRED:
		check(lod0.find_child(nm, true, false) != null, "LOD0 has no node %s" % nm)
		var col: Node = lod0.find_child("col_body", true, false)
		if col != null:
			check(not (col as Node3D).is_visible_in_tree(), "col_body renders")
	await cleanup([car])


func test_budgets_and_bounding_box() -> void:
	var car: CarLod = (load(SCENE) as PackedScene).instantiate() as CarLod
	add(car)
	await frames(1)
	var t0: int = _tris(car.get_node("LOD0"))
	var t1: int = _tris(car.get_node("LOD1"))
	var t2: int = _tris(car.get_node("LOD2"))
	metric("tris", {"lod0": t0, "lod1": t1, "lod2": t2})
	check(t0 >= 45000 and t0 <= TRI_LOD0_MAX, "LOD0 tris %d outside 45000..%d" % [t0, TRI_LOD0_MAX])
	check(t1 <= TRI_LOD1_MAX, "LOD1 tris %d above %d" % [t1, TRI_LOD1_MAX])
	check(t2 <= TRI_LOD2_MAX, "LOD2 tris %d above %d" % [t2, TRI_LOD2_MAX])
	var box: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in _mesh_nodes(car.get_node("LOD0")):
		if mi.name == "col_body" or not mi.visible or mi.mesh == null:
			continue
		var b: AABB = _to_root(mi, car) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	metric("bbox_size_m", [snappedf(box.size.x, 0.001), snappedf(box.size.y, 0.001), snappedf(box.size.z, 0.001)])
	check_range(box.size.z, LEN_M * (1.0 - SIZE_TOL), LEN_M * (1.0 + 2.0 * SIZE_TOL), "LOD0 length (Z)")
	check_range(box.size.x, WIDTH_M * (1.0 - SIZE_TOL), WIDTH_M * (1.0 + SIZE_TOL), "LOD0 width (X)")
	check_range(box.size.y, HEIGHT_M * (1.0 - SIZE_TOL), HEIGHT_M * (1.0 + SIZE_TOL), "LOD0 height (Y)")
	await cleanup([car])


func test_model_seats_on_the_suspension() -> void:
	var spec: CarSpec = load(SPEC_PATH) as CarSpec
	var car: ArcadeCar = CarFactory.create(SCENE, spec, Color.RED)
	check(not bool(car.get_meta("dev_car")), "factory fell back to the dev car")
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	add(car)
	car.global_position = Vector3(0.0, 1.0, 0.0)
	await frames(150)
	check(car.is_grounded, "car did not settle on the ground")
	var lod: Node = car.get_node("Visual").get_child(0)
	for lod_name: String in ["LOD0", "LOD1", "LOD2"]:
		var l: Node = lod.get_node_or_null(lod_name)
		check(l != null, "%s missing" % lod_name)
		if l == null:
			continue
		for wn: Array in [["wheel_FL", 0], ["wheel_RR", 3]]:
			var w: Node3D = l.find_child(wn[0], true, false) as Node3D
			check(w != null, "%s has no %s" % [lod_name, wn[0]])
			if w == null:
				continue
			var static_y: float = (car.global_transform.affine_inverse() * w.global_transform.origin).y
			var phys_y: float = car.get_wheel_local_position(wn[1]).y
			metric("%s_%s_gap_m" % [lod_name, wn[0]], snappedf(static_y - phys_y, 0.001))
			check(absf(static_y - phys_y) < MAX_GAP_M, "%s %s centre %.3f m off the suspension" % [lod_name, wn[0], static_y - phys_y])
	await cleanup([car, ground])


func test_drives_and_outruns_the_sable() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var spec: CarSpec = load(SPEC_PATH) as CarSpec
	var hero: CarSpec = load(HERO_SPEC_PATH) as CarSpec
	check(spec.top_speed_kmh > hero.top_speed_kmh, "Kestrel top speed %.0f not above the Sable %.0f" % [spec.top_speed_kmh, hero.top_speed_kmh])
	check(spec.mass_kg > hero.mass_kg, "Kestrel is not heavier than the Sable")
	check(spec.grip_front < hero.grip_front and spec.steer_angle_low_deg < hero.steer_angle_low_deg, "Kestrel is not less agile than the Sable")
	check(is_equal_approx(spec.wheelbase, 2.92), "wheelbase %.2f, the model has 2.92" % spec.wheelbase)
	var car: ArcadeCar = CarFactory.create(SCENE, spec, Color.RED)
	add(car)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.47, 0.0)))
	await frames(90)
	check(car.is_grounded, "car not grounded after 1.5 s")
	car.input.throttle = 1.0
	var t100: float = -1.0
	for tick: int in 60 * 20:
		await frames(1)
		if t100 < 0.0 and car.speed_kmh >= 100.0:
			t100 = float(tick + 1) / 60.0
			break
	metric("kestrel_0_100_s", t100)
	check_range(t100, 3.0, 8.0, "Kestrel 0-100 km/h (s)")
	# keep the throttle down: it must keep accelerating well past 200 km/h and stay under its top speed
	for tick: int in 60 * 14:
		await frames(1)
	metric("kestrel_speed_after_14s_kmh", snappedf(car.speed_kmh, 0.1))
	check(car.speed_kmh > 200.0, "Kestrel only %.0f km/h after 14 s more" % car.speed_kmh)
	check(car.speed_kmh <= spec.top_speed_kmh * 1.02, "Kestrel %.0f km/h is above its top speed %.0f" % [car.speed_kmh, spec.top_speed_kmh])
	check(car.is_grounded, "Kestrel left the ground on a flat road")
	await cleanup([car, ground])
