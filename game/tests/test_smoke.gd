extends "res://tests/test_case.gd"
## Proves the harness itself: physics steps run headless and a body falls under gravity.


func test_rigidbody_falls() -> void:
	var body := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	body.add_child(shape)
	body.position = Vector3(0, 10, 0)
	add(body)
	await frames(60)
	metric("y_after_1s", body.global_position.y)
	check_range(body.global_position.y, 4.0, 6.0, "sphere height after 1 s of free fall from 10 m")
	await cleanup([body])


func test_input_actions_exist() -> void:
	for a: String in ["accelerate", "brake", "steer_left", "steer_right", "handbrake", "nitro", "pause"]:
		check(InputMap.has_action(a), "missing input action " + a)
