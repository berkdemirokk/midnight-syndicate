extends "res://tests/test_case.gd"
## Contact shadow (fx/contact_shadow.gd): follows the road under a moving car, fades when airborne, shares one material,
## strength by time of day, parked-car MultiMesh per cell, and stays out of the planar mirror. Daylight parked paint
## must not be pushed past white (the blown-out parked cars in bogaz_day).

const FLOOR_Y: float = 0.0
const LIFT: float = 0.03
const EPS: float = 0.01


func _floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	cs.shape = box
	cs.position = Vector3(0.0, FLOOR_Y - 0.5, 0.0)
	body.add_child(cs)
	return body


func test_follows_road_and_tilts_to_normal() -> void:
	var floor_body: StaticBody3D = add(_floor()) as StaticBody3D
	var car := Node3D.new()
	add(car)
	car.global_position = Vector3(0.0, 0.47, 0.0)
	var s: ContactShadow = ContactShadow.attach(car, true)
	await frames(3)
	check(absf(s.global_position.y - (FLOOR_Y + LIFT)) < EPS, "blob sits on the road (y=%.3f)" % s.global_position.y)
	check(s.global_basis.y.dot(Vector3.UP) > 0.99, "blob normal is up on flat road")
	check(s.get_instance_shader_parameter("lift_fade") > 0.99, "a car at rest is not faded")
	# A car in the air: the blob fades out.
	car.global_position = Vector3(0.0, 4.0, 0.0)
	await frames(3)
	check(s.get_instance_shader_parameter("lift_fade") < 0.01, "airborne car fades the blob (fade=%s)" % str(s.get_instance_shader_parameter("lift_fade")))
	check(s.layers == ContactShadow.MIRROR_SKIP_BIT and (s.layers & 1) == 0, "blob is left out of the mirror")
	cleanup([car, floor_body])
	await frames(2)


func test_shared_material_and_strength_by_hour() -> void:
	var car_a := Node3D.new()
	var car_b := Node3D.new()
	add(car_a)
	add(car_b)
	var a: ContactShadow = ContactShadow.attach(car_a, false)
	var b: ContactShadow = ContactShadow.attach(car_b, false)
	check(a.material_override == b.material_override, "blobs share one material")
	check(a.position.is_equal_approx(Vector3(0.0, LIFT, 0.0)), "traffic blob sits at the car origin")
	ContactShadow.set_time_of_day("sunset")
	var soft: float = float(ContactShadow.shared_material().get_shader_parameter("strength"))
	ContactShadow.set_time_of_day("day")
	var noon: float = float(ContactShadow.shared_material().get_shader_parameter("strength"))
	ContactShadow.set_time_of_day("night")
	var night: float = float(ContactShadow.shared_material().get_shader_parameter("strength"))
	check(soft < noon and soft < night, "sunset is the softest (sunset %.2f, day %.2f, night %.2f)" % [soft, noon, night])
	check(noon > 0.0 and night <= 1.0, "strengths in range")
	ContactShadow.set_time_of_day("day")
	cleanup([car_a, car_b])
	await frames(2)


func test_parked_multimesh_one_per_cell() -> void:
	var xfs: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 2.0)),
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-3.0, 0.2, 5.0)),
	]
	var mmi: MultiMeshInstance3D = ContactShadow.shadow_multimesh(xfs, 150.0)
	check(mmi.multimesh.instance_count == 2, "one blob per parked car")
	check(mmi.layers == ContactShadow.MIRROR_SKIP_BIT, "parked blobs are left out of the mirror")
	check(mmi.visibility_range_end == 150.0, "parked blobs use the cell range")
	# MultiMesh data is not readable headless, so the placement is checked through the helper the MultiMesh uses.
	var t: Transform3D = ContactShadow.blob_xf(xfs[1])
	check(absf(t.origin.y - (0.2 + LIFT)) < EPS and absf(t.origin.x + 3.0) < EPS, "blob at the car, on the road (%s)" % str(t.origin))
	check(absf(t.basis.y.dot(Vector3.UP) - 1.0) < EPS, "blob lies flat")
	mmi.free()


func test_parked_day_paint_not_blown_out() -> void:
	var day: TimeOfDay = TimeOfDay.preset("day")
	var white: Color = ParkedCars.parked_paint_colours()[ParkedCars.paint_names().find("white")]
	var lit: float = maxf(white.r, maxf(white.g, white.b)) * day.parked_albedo
	check(lit <= 0.9, "white parked paint in daylight stays below clipping (albedo %.2f)" % lit)
