extends "res://tests/test_case.gd"
## Regression: the car model sits on its suspension. Before the fix the body floated 0.49 m over the wheels the
## physics placed (LOD0 wheels hung below the body, LOD1/LOD2 cars hovered with their wheels in the air).

const MAX_GAP_M: float = 0.06


func test_model_wheels_rest_on_the_suspension() -> void:
	var spec: CarSpec = load("res://vehicles/specs/noctra_sable.tres") as CarSpec
	var car: ArcadeCar = CarFactory.create("res://vehicles/noctra_sable/noctra_sable.tscn", spec, Color.RED)
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
	for lod_name: String in ["LOD1", "LOD2"]:
		var l: Node = lod.get_node_or_null(lod_name)
		check(l != null, "%s missing" % lod_name)
		if l == null:
			continue
		var w: Node3D = l.find_child("wheel_FL", true, false) as Node3D
		check(w != null, "%s has no wheel_FL" % lod_name)
		if w == null:
			continue
		var static_y: float = (car.global_transform.affine_inverse() * w.global_transform.origin).y
		var phys_y: float = car.get_wheel_local_position(0).y
		metric("%s_wheel_gap_m" % lod_name, snappedf(static_y - phys_y, 0.001))
		check(absf(static_y - phys_y) < MAX_GAP_M, "%s wheel centre %.3f m off the suspension (static %.3f, physics %.3f)" % [lod_name, static_y - phys_y, static_y, phys_y])
	await cleanup([car, ground])
