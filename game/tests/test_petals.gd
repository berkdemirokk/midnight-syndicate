extends "res://tests/test_case.gd"
## Petals: an emitter that follows the camera, sized by the particle preset.


func test_petals_emit_and_follow_the_camera() -> void:
	var cam := Camera3D.new()
	add(cam)
	cam.global_position = Vector3(120.0, 2.0, -40.0)
	cam.make_current()
	var p := Petals.new()
	add(p)
	await frames(3)
	if Settings.get_preset_id() == "low":
		check(p.get_child_count() == 0, "petals on the Low preset")
	else:
		check(p.get_child_count() == 1 and (p.get_child(0) as GPUParticles3D).emitting, "no petal emitter")
		check(p.global_position.distance_to(cam.global_position + Vector3(0.0, 1.5, 0.0)) < 0.01, "petals do not follow the camera")
	await cleanup([p, cam])
