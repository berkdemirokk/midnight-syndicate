extends "res://tests/test_case.gd"
## Tyre smoke: no slip/drift smoke at bump speeds, capped puff size, see-through alpha, near fade.

const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const FlatWorld = preload("res://tests/helpers/flat_world.gd")


func _run_at(kmh: float, drifting: bool, throttle: float) -> bool:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.47, 0.0)))
	var fx := load("res://fx/car_fx.tscn").instantiate() as CarFx
	car.add_child(fx)
	await frames(120)
	car.linear_velocity = Vector3(0.0, 0.0, -kmh / 3.6)
	car.is_drifting = drifting
	car.input.throttle = throttle
	await frames(1)
	var on: bool = false
	for e: GPUParticles3D in fx.smoke._emitters:
		on = on or e.emitting
	await cleanup([car, ground])
	return on


func test_slow_spin_does_not_smoke() -> void:
	var on: bool = await _run_at(25.0, true, 1.0)
	check(not on, "drift flag at 25 km/h emitted tyre smoke")


func test_fast_drift_still_smokes() -> void:
	var on: bool = await _run_at(80.0, true, 0.0)
	check(on, "drift at 80 km/h emitted no tyre smoke")


func test_puff_size_alpha_and_near_fade_are_capped() -> void:
	var sm := TireSmoke.new()
	add(sm)
	await frames(1)
	check(TireSmoke.MAX_PUFF_M <= 2.0, "puff width cap %.2f m too big" % TireSmoke.MAX_PUFF_M)
	check(TireSmoke.PUFF_PEAK_ALPHA <= 0.3, "puff alpha %.2f too opaque" % TireSmoke.PUFF_PEAK_ALPHA)
	var mat := (sm._emitters[0].draw_pass_1 as QuadMesh).material as StandardMaterial3D
	check(mat.distance_fade_min_distance >= 2.5, "puffs not faded near the lens")
	check(sm._emitters[0].draw_pass_1.size.x * (sm._pms[0].scale_max) <= TireSmoke.MAX_PUFF_M + 0.001, "scale exceeds cap")
	await cleanup([sm])
