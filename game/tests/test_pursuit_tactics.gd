extends "res://tests/test_case.gd"
## Pursuit tactics: boxing (heat 4+), the ram (heat 5, behind, cooldown), hiding spots (cooldown x2 out of sight), and
## the HUD hint. The rules are pure functions or PursuitState, so no scene is needed.

const STEP_S: float = 0.5
const BOGAZ: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"


func test_boxers_only_from_heat_4_and_one_per_side() -> void:
	check(PursuitMode.boxers_for_heat(3) == 0, "no boxing at heat 3")
	check(PursuitMode.boxers_for_heat(4) == 2 and PursuitMode.boxers_for_heat(5) == 2, "two boxers at heat 4 and 5")
	check(PursuitMode.boxer_side(4, 0) == -1 and PursuitMode.boxer_side(4, 1) == 1, "first car boxes left, second right")
	check(PursuitMode.boxer_side(4, 2) == 0, "the third car chases from behind")
	check(PursuitMode.boxer_side(3, 0) == 0, "heat 3 cars all chase")


func test_box_gap_is_signed_and_wraps_half_a_lap() -> void:
	check(is_equal_approx(PoliceDriver.box_gap_m(100.0, 50.0, 1000.0), 50.0), "police 50 m ahead of the player")
	check(is_equal_approx(PoliceDriver.box_gap_m(50.0, 100.0, 1000.0), -50.0), "police 50 m behind the player")
	check(is_equal_approx(PoliceDriver.box_gap_m(10.0, 990.0, 1000.0), 20.0), "wraps across the start line")
	check(PoliceDriver.box_gap_m(10.0, 990.0, 0.0) == 0.0, "no lap length, no gap")


func test_box_throttle_pushes_behind_holds_past_and_idles_at_the_point() -> void:
	check(PoliceDriver.box_throttle(5.0, 12.0) == 1.0, "far behind the box point: push")
	check(PoliceDriver.box_throttle(20.0, 12.0) == -1.0, "past the box point: hold back")
	check(PoliceDriver.box_throttle(12.0, 12.0) == 0.0, "on the box point: no override")


func test_ram_needs_heat_5_cooldown_done_behind_and_range() -> void:
	check(not PursuitMode.can_ram(4, 0.0, 3.0, true), "no ram at heat 4")
	check(PursuitMode.can_ram(5, 0.0, 3.0, true), "heat 5, behind, in range, cooldown done: ram")
	check(not PursuitMode.can_ram(5, 2.0, 3.0, true), "cooldown still running: no ram")
	check(not PursuitMode.can_ram(5, 0.0, 3.0, false), "a car ahead does not ram")
	check(not PursuitMode.can_ram(5, 0.0, PursuitMode.RAM_RANGE_M + 1.0, true), "too far to ram")
	check(not PursuitMode.can_ram(5, 0.0, 0.0, true), "no ram from zero distance (no direction)")


func test_hiding_spot_doubles_the_escape_cooldown_out_of_sight() -> void:
	check(HidingSpots.cooldown_mult(true, false) == 2.0, "in a spot, out of sight: x2")
	check(HidingSpots.cooldown_mult(true, true) == 1.0, "in a spot but seen: x1")
	check(HidingSpots.cooldown_mult(false, false) == 1.0, "outside a spot: x1")


func test_hiding_spot_ranges_by_track_distance() -> void:
	var lap: float = 1000.0
	check(HidingSpots.index_at(BOGAZ, 150.0, lap) == 0, "150 m on Bosphorus is the first spot")
	check(HidingSpots.index_at(BOGAZ, 300.0, lap) == -1, "300 m is between spots")
	check(HidingSpots.index_at(BOGAZ, 1150.0, lap) == 0, "progress wraps past one lap")
	check(HidingSpots.index_at("", 150.0, lap) == -1, "a track without spots has none")
	check(HidingSpots.spots_for(BOGAZ).size() >= 3 and HidingSpots.spots_for(BOGAZ).size() <= 4, "three or four spots per track")
	for track: String in HidingSpots.SPOTS.keys():
		for r: Vector2 in HidingSpots.spots_for(track):
			check(r.x >= 0.0 and r.y <= 1.0 and r.x < r.y, "spot range inside one lap: %s" % track)


func test_escape_cooldown_fills_twice_as_fast_in_a_spot() -> void:
	var fast := PursuitState.new()
	fast.start(1)
	fast.tick(STEP_S, INF, 0.0, 2.0)
	var ticks_fast: int = 1
	while fast.phase == PursuitState.Phase.COOLDOWN and ticks_fast < 100:
		fast.tick(STEP_S, INF, 0.0, 2.0)
		ticks_fast += 1
	var slow := PursuitState.new()
	slow.start(1)
	slow.tick(STEP_S, INF, 0.0, 1.0)
	var ticks_slow: int = 1
	while slow.phase == PursuitState.Phase.COOLDOWN and ticks_slow < 100:
		slow.tick(STEP_S, INF, 0.0, 1.0)
		ticks_slow += 1
	check(fast.phase == PursuitState.Phase.ESCAPED and slow.phase == PursuitState.Phase.ESCAPED, "both chases escape")
	check(ticks_fast * 2 == ticks_slow, "x2 spot takes half the ticks (%d vs %d)" % [ticks_fast, ticks_slow])


func test_hud_hint_shows_only_with_text_and_heat() -> void:
	var hud := PursuitHud.new()
	hud.set_hint("HIDE")
	check(not hud._hint.visible, "no hint before the chase (heat 0)")
	hud.set_heat(2, 5)
	hud.set_hint("HIDE")
	check(hud._hint.visible and hud._hint.text == "HIDE", "hint shows in a chase")
	hud.set_hint("")
	check(not hud._hint.visible, "empty text hides the hint")
	hud.free()
