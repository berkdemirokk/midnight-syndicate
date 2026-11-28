extends "res://tests/test_case.gd"
## Heat escalation thresholds and the roadblock gate on heat change. Pure rules (PursuitState), no scene.

const STEP_S: float = 0.5  ## exact in binary, so 50 steps are exactly 25 s


func test_heat_steps_every_25_seconds_of_chase() -> void:
	var p := PursuitState.new()
	p.start(1)

	var got: Array[int] = []
	for i: int in 200:
		p.tick(STEP_S, 40.0, 100.0)  # chasing at 40 m: never cools down, never busts
		if i % 50 == 49:
			got.append(p.heat)
	check(p.phase == PursuitState.Phase.CHASE, "still in the chase after 100 s")
	check(got == [2, 3, 4, 5], "heat 2, 3, 4, 5 at 25, 50, 75, 100 s (got %s)" % str(got))
	check(p.heat == 5, "heat stays at the maximum")


func test_roadblock_eligible_only_from_heat_3_in_chase() -> void:
	var p := PursuitState.new()
	p.start(1)
	check(not p.can_request_roadblock(), "no roadblock at heat 1")
	p.tick(25.0, 40.0, 100.0)
	check(p.heat == 2 and not p.can_request_roadblock(), "no roadblock at heat 2")
	p.tick(25.0, 40.0, 100.0)
	check(p.heat == 3 and p.can_request_roadblock(), "roadblock eligible on the step into heat 3")
	p.tick(5.0, INF, 100.0)
	check(p.phase == PursuitState.Phase.COOLDOWN and not p.can_request_roadblock(), "no roadblock while cooling down")


func test_started_at_higher_heat_is_clamped() -> void:
	var p := PursuitState.new()
	p.start(9)
	check(p.heat == PursuitState.MAX_HEAT, "start heat clamped to 5")
	p.start(0)
	check(p.heat == 1, "start heat clamped to 1")
