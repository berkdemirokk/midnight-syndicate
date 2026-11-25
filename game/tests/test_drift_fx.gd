extends "res://tests/test_case.gd"
## Drift FX: tyre smoke emission and wind, and skid mark ribbons (game/fx/tire_smoke.gd, skid_marks.gd).

const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const FlatWorld = preload("res://tests/helpers/flat_world.gd")


func test_smoke_emits_only_on_wheels_with_slip() -> void:
	var sm := TireSmoke.new()
	add(sm)
	await frames(1)
	sm.update_puffs(PackedVector3Array([Vector3(-0.8, 0, 0), Vector3(0.8, 0, 0)]), PackedFloat32Array([0.9, 0.0]), Vector3.RIGHT, 3.0)
	await frames(2)
	check(sm._emitters[0].emitting, "slipping wheel emitted no smoke")
	check(not sm._emitters[1].emitting, "grip wheel emitted smoke")
	check_range(sm._emitters[0].amount_ratio, 0.89, 0.91, "amount ratio does not follow slip")
	sm.stop()
	await cleanup([sm])


func test_smoke_puff_count_follows_particle_amount_scale() -> void:
	var sm := TireSmoke.new()
	add(sm)
	await frames(1)
	var scale_f: float = Settings.get_preset().particle_amount_scale
	check(sm._emitters[0].amount == maxi(1, int(round(sm.puff_amount * scale_f))), "puff count %d ignores particle_amount_scale %.2f" % [sm._emitters[0].amount, scale_f])
	await cleanup([sm])


func test_smoke_bursts_on_the_first_frame_of_a_slide() -> void:
	var sm := TireSmoke.new()
	add(sm)
	await frames(1)
	var pts := PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0)])
	sm.update_puffs(pts, PackedFloat32Array([0.0, 0.0]), Vector3.RIGHT, 0.0)
	sm.update_puffs(pts, PackedFloat32Array([1.0, 0.0]), Vector3.RIGHT, 3.0)
	await frames(2)
	check(sm._emitters[0].emitting, "slide did not start the emitter")
	check(sm._was_on[0] == 1 and sm._was_on[1] == 0, "slide edge not tracked per wheel")
	await cleanup([sm])


func test_smoke_culling_box_covers_the_trail() -> void:
	var sm := TireSmoke.new()
	add(sm)
	await frames(1)
	# Puffs trail ~8 m/s for 1.6 s, so the default 8 m box would cull them.
	check(sm._emitters[0].visibility_aabb.size.x >= 20.0, "smoke culling box %s too small for the trail" % sm._emitters[0].visibility_aabb)
	await cleanup([sm])


func test_smoke_trails_back_with_the_wind() -> void:
	var sm := TireSmoke.new()
	add(sm)
	await frames(1)
	# Car drives toward -Z; wind is the car's trail, so the puffs must travel toward +Z.
	sm.update_puffs(PackedVector3Array([Vector3.ZERO, Vector3.ZERO]), PackedFloat32Array([1.0, 1.0]), Vector3.ZERO, 0.0, Vector3(0, 0, 6))
	check(sm._pms[0].direction.z > 0.9, "puffs do not trail behind the car (direction %s)" % sm._pms[0].direction)
	check(sm._pms[0].initial_velocity_min > 0.0, "wind gives puffs no speed")
	await cleanup([sm])


func test_skid_ribbon_grows_while_sliding() -> void:
	var sk := SkidMarks.new()
	add(sk)
	await frames(1)
	for f: int in 10:
		var p := PackedVector3Array([Vector3(f * 0.5, 0, 0), Vector3(f * 0.5, 0, 5)])
		sk.update(p, PackedByteArray([1, 0]), 1.0 / 60.0)
	check(sk.live_points(0) >= 9, "left mark has %d points after 10 moves" % sk.live_points(0))
	check(sk.live_points(1) == 0, "grip wheel laid a mark")
	check(sk.triangle_count() > 0, "no ribbon triangles while sliding")
	check(sk.visible, "ribbon hidden while it has triangles")
	metric("skid_points", sk.live_points(0))
	await cleanup([sk])


func test_skid_ribbon_fades_out_after_eight_seconds() -> void:
	var sk := SkidMarks.new()
	add(sk)
	await frames(1)
	for f: int in 10:
		sk.update(PackedVector3Array([Vector3(f * 0.5, 0, 0), Vector3(f * 0.5, 0, 0)]), PackedByteArray([1, 1]), 1.0 / 60.0)
	check(sk.triangle_count() > 0, "no ribbon before the fade")
	for s: int in 7:
		sk.update(PackedVector3Array([Vector3.ZERO, Vector3.ZERO]), PackedByteArray([0, 0]), 1.0)
	check(sk.triangle_count() > 0, "ribbon gone after 7 s (should last ~8 s)")
	sk.update(PackedVector3Array([Vector3.ZERO, Vector3.ZERO]), PackedByteArray([0, 0]), 1.5)
	check(sk.triangle_count() == 0, "ribbon still drawn after 8.5 s")
	check(not sk.visible, "faded ribbon still visible")
	check(sk.live_points(0) == 0, "faded points still counted live")
	await cleanup([sk])


func test_skid_ribbon_ring_buffer_caps_points() -> void:
	var sk := SkidMarks.new()
	add(sk)
	await frames(1)
	for f: int in SkidMarks.MAX_POINTS + 40:
		sk.update(PackedVector3Array([Vector3(f * 0.5, 0, 0), Vector3.ZERO]), PackedByteArray([1, 0]), 0.001)
	check(sk.live_points(0) == SkidMarks.MAX_POINTS, "ring buffer holds %d points, expected %d" % [sk.live_points(0), SkidMarks.MAX_POINTS])
	await cleanup([sk])


func test_drifting_car_lays_skid_marks() -> void:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.47, 0.0)))
	var fx := load("res://fx/car_fx.tscn").instantiate() as CarFx
	car.add_child(fx)
	await frames(120)
	car.linear_velocity = Vector3(0.0, 0.0, -80.0 / 3.6)
	car.is_drifting = true
	await frames(30)
	check(fx.skid.live_points(0) + fx.skid.live_points(1) > 0, "drifting car laid no skid marks")
	await cleanup([car, ground])


func test_skid_ribbon_is_one_draw_call() -> void:
	var sk := SkidMarks.new()
	add(sk)
	await frames(1)
	sk.update(PackedVector3Array([Vector3.ZERO, Vector3(2, 0, 0)]), PackedByteArray([1, 1]), 0.1)
	sk.update(PackedVector3Array([Vector3(0.5, 0, 0), Vector3(2.5, 0, 0)]), PackedByteArray([1, 1]), 0.1)
	check(sk.mesh is ArrayMesh and (sk.mesh as ArrayMesh).get_surface_count() <= 1, "skid marks use more than one surface")
	check(sk.get_surface_override_material_count() <= 1, "skid marks use more than one material")
	await cleanup([sk])
