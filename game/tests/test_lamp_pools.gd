extends "res://tests/test_case.gd"
## Rival lamps are glow pools on the road, not SpotLight3D. The player keeps its two spots.

const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"


func test_six_car_night_race_has_two_spots_and_five_pools() -> void:
	var spec := load(SPEC_PATH) as CarSpec
	var cars: Array[Node] = []
	for i: int in 6:
		var car := ArcadeCar.new()
		car.spec = spec
		add(car)
		var fx := load("res://fx/car_fx.tscn").instantiate() as CarFx
		fx.lamp_pools = i > 0  # slot 0 is the player
		car.add_child(fx)
		cars.append(car)
	await frames(3)
	var spots: int = 0
	var pools: int = 0
	for car: Node in cars:
		spots += car.find_children("*", "SpotLight3D", true, false).size()
		pools += car.find_children("LampPool", "MeshInstance3D", true, false).size()
	check(spots == 2, "%d SpotLight3D in a 6-car night race, expected 2 (the player only)" % spots)
	check(pools == 5, "%d lamp pools, expected 5 (cars - 1)" % pools)
	await cleanup(cars)


func test_rival_pool_shows_with_lamps_and_has_no_spot() -> void:
	var h := Headlights.new()
	h.lamp_pools = true
	add(h)
	await frames(1)
	var pool: MeshInstance3D = h.get_node_or_null("LampPool") as MeshInstance3D
	check(pool != null, "rival headlights built no LampPool quad")
	if pool != null:
		check(not pool.visible, "pool shows with lamps off (day)")
		h.set_on(true)
		check(pool.visible, "pool hidden with lamps on")
	check(h.find_children("*", "SpotLight3D", false, false).is_empty(), "rival headlights built a SpotLight3D")
	await cleanup([h])
