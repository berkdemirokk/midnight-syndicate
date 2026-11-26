extends "res://tests/test_case.gd"
## Bosfor Atmaca (stock, modified, taxi): scene contract, four wheels, triangle budgets, size, seating on the
## suspension, and the modified car drives straight.

const SCENES: Dictionary = {
	"stock": "res://vehicles/bosfor_atmaca/atmaca_stock.tscn",
	"modified": "res://vehicles/bosfor_atmaca/atmaca_modified.tscn",
	"taxi": "res://vehicles/bosfor_atmaca/atmaca_taxi.tscn",
}
const SPECS: Dictionary = {
	"stock": "res://vehicles/specs/atmaca_stock.tres",
	"modified": "res://vehicles/specs/atmaca_modified.tres",
	"taxi": "res://vehicles/specs/atmaca_stock.tres",
}
const REQUIRED: PackedStringArray = [
	"body", "glass", "trim", "interior", "underbody", "plate_rear", "lights_front", "lights_rear",
	"wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR", "brake_FL", "brake_FR", "brake_RL", "brake_RR", "col_body",
]
const LEN_M: float = 4.30
const WIDTH_M: Dictionary = {"stock": 1.65, "modified": 1.76, "taxi": 1.65}
const HEIGHT_M: Dictionary = {"stock": 1.40, "modified": 1.35, "taxi": 1.51}  ## taxi: roof sign on top
const SIZE_TOL: float = 0.04  ## 3 percent in the brief plus mirrors and the lamp bezels
const TRI_MAX: Array[int] = [45000, 15000, 5000]
const MAX_GAP_M: float = 0.06


func _mesh_nodes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


func _tris(root: Node) -> int:
	var total: int = 0
	for mi: MeshInstance3D in _mesh_nodes(root):
		if mi.name == "col_body" or mi.mesh == null:
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


func test_all_three_load_with_four_wheels_and_budgets() -> void:
	for variant: String in SCENES:
		var car: CarLod = (load(SCENES[variant]) as PackedScene).instantiate() as CarLod
		check(car != null, "%s: scene is not a CarLod" % variant)
		if car == null:
			continue
		add(car)
		await frames(2)
		check(car.get_wheel_nodes().size() == 4, "%s: wheels %d" % [variant, car.get_wheel_nodes().size()])
		var lod0: Node = car.get_node("LOD0")
		for nm: String in REQUIRED:
			check(lod0.find_child(nm, true, false) != null, "%s: LOD0 has no node %s" % [variant, nm])
		for i: int in 3:
			var lod: Node = car.get_node("LOD%d" % i)
			var t: int = _tris(lod)
			metric("%s_lod%d_tris" % [variant, i], t)
			check(t > 500 and t <= TRI_MAX[i], "%s LOD%d tris %d outside budget %d" % [variant, i, t, TRI_MAX[i]])
			var col: Node = lod.find_child("col_body", true, false)
			if col != null:
				check(not (col as Node3D).is_visible_in_tree(), "%s LOD%d col_body renders" % [variant, i])
		# bounding box of LOD0 (col_body excluded)
		var box: AABB = AABB()
		var first: bool = true
		for mi: MeshInstance3D in _mesh_nodes(lod0):
			if mi.name == "col_body" or mi.mesh == null:
				continue
			var b: AABB = _to_root(mi, car) * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		check_range(box.size.z, LEN_M * (1.0 - SIZE_TOL), LEN_M * (1.0 + SIZE_TOL), "%s length" % variant)
		check_range(box.size.x, WIDTH_M[variant] * (1.0 - SIZE_TOL), WIDTH_M[variant] * (1.0 + SIZE_TOL), "%s width" % variant)
		check_range(box.size.y, HEIGHT_M[variant] * (1.0 - SIZE_TOL), HEIGHT_M[variant] * (1.0 + SIZE_TOL), "%s height" % variant)
		metric("%s_size" % variant, "%.2f x %.2f x %.2f" % [box.size.x, box.size.y, box.size.z])
		await cleanup([car])


func _ground() -> StaticBody3D:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	add(ground)
	return ground


func test_model_wheels_rest_on_the_suspension() -> void:
	for variant: String in ["stock", "modified"]:
		var spec: CarSpec = load(SPECS[variant]) as CarSpec
		var car: ArcadeCar = CarFactory.create(SCENES[variant], spec, Color.RED)
		var ground: StaticBody3D = _ground()
		add(car)
		car.global_position = Vector3(0.0, 1.0, 0.0)
		await frames(150)
		check(car.is_grounded, "%s: car did not settle" % variant)
		var lod: Node = car.get_node("Visual").get_child(0)
		for lod_name: String in ["LOD1", "LOD2"]:
			var w: Node3D = lod.get_node(lod_name).find_child("wheel_FL", true, false) as Node3D
			check(w != null, "%s %s has no wheel_FL" % [variant, lod_name])
			if w == null:
				continue
			var static_y: float = (car.global_transform.affine_inverse() * w.global_transform.origin).y
			var phys_y: float = car.get_wheel_local_position(0).y
			metric("%s_%s_wheel_gap_m" % [variant, lod_name], snappedf(static_y - phys_y, 0.001))
			check(absf(static_y - phys_y) < MAX_GAP_M, "%s %s wheel centre %.3f m off the suspension" % [variant, lod_name, static_y - phys_y])
		await cleanup([car, ground])


func test_modified_drives_straight() -> void:
	var spec: CarSpec = load(SPECS["modified"]) as CarSpec
	var car: ArcadeCar = CarFactory.create(SCENES["modified"], spec, Color.RED)
	var ground: StaticBody3D = _ground()
	add(car)
	car.global_position = Vector3(0.0, 1.0, 0.0)
	await frames(90)
	var start: Vector3 = car.global_position
	car.input.throttle = 1.0
	await frames(240)
	var d: Vector3 = car.global_position - start
	metric("modified_straight_travel_m", snappedf(d.length(), 0.1))
	metric("modified_straight_lateral_m", snappedf(absf(d.x), 0.01))
	metric("modified_speed_kmh", snappedf(car.speed_kmh, 0.1))
	check(d.length() > 15.0, "modified did not accelerate (%.1f m)" % d.length())
	check(absf(d.x) < 0.3, "modified drifted %.2f m sideways on a straight" % d.x)
	check(car.speed_kmh > 40.0, "modified too slow: %.1f km/h" % car.speed_kmh)
	car.input.clear()
	await cleanup([car, ground])
