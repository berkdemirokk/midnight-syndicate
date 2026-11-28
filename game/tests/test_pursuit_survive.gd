extends "res://tests/test_case.gd"
## Survive goal ("survive N minutes" pursuit events): the chase ends in ESCAPED after N seconds of chase time, a bust
## still wins, the escape goal is unchanged, and the pursuit event catalog is consistent. No scene needed for the rules.

const STEP_S: float = 0.5


func test_survive_goal_ends_in_escaped_after_chase_time() -> void:
	var p := PursuitState.new()
	p.start(1, 60.0)
	for i: int in 118:
		p.tick(STEP_S, 40.0, 100.0)  # 59 s of chase
	check(p.phase == PursuitState.Phase.CHASE, "not yet survived at 59 s")
	p.tick(STEP_S, 40.0, 100.0)
	p.tick(STEP_S, 40.0, 100.0)
	check(p.phase == PursuitState.Phase.ESCAPED, "survived at 60 s of chase")
	check(p.total_s >= 60.0, "chase time counted")


func test_survive_goal_does_not_count_cooldown() -> void:
	var p := PursuitState.new()
	p.start(1, 10.0)
	p.tick(5.0, 40.0, 100.0)
	p.tick(5.0, INF, 100.0)  # cooldown: the chase clock stops
	check(p.phase == PursuitState.Phase.COOLDOWN and p.total_s == 5.0, "cooldown time is not chase time")


func test_bust_wins_over_survive_goal() -> void:
	var p := PursuitState.new()
	p.start(1, 60.0)
	for i: int in 8:
		p.tick(STEP_S, 5.0, 0.0)  # boxed and stopped for 4 s, far from the 60 s goal
	check(p.phase == PursuitState.Phase.BUSTED, "bust at 4 s even with a survive goal")


func test_escape_goal_never_ends_by_timer() -> void:
	var p := PursuitState.new()
	p.start(1)
	for i: int in 600:
		p.tick(STEP_S, 40.0, 100.0)  # five minutes of chase
	check(p.phase == PursuitState.Phase.CHASE and p.survive_s == 0.0, "escape goal stays in the chase")


func test_reset_clears_survive_goal() -> void:
	var p := PursuitState.new()
	p.start(2, 30.0)
	p.tick(5.0, 40.0, 100.0)
	p.reset()
	check(p.survive_s == 0.0 and p.total_s == 0.0 and p.phase == PursuitState.Phase.INACTIVE, "reset clears the goal and the clock")


func test_pursuit_events_are_consistent() -> void:
	var saved: String = Settings.language
	var survive_count: int = 0
	for i: int in EventCatalog.count():
		var id: String = EventCatalog.id_at(i)
		var ev: Dictionary = EventCatalog.find(id)
		if not bool(ev.get("pursuit", false)):
			continue
		var cfg: RaceConfig = EventCatalog.config_for(id)
		check(cfg != null and cfg.pursuit and cfg.pursuit_event, "pursuit event opts in: " + id)
		check(ResourceLoader.exists(cfg.track_scene) if cfg.track_scene != "" else true, "track exists: " + id)
		if ev.has("survive_s"):
			survive_count += 1
			var s: float = float(ev["survive_s"])
			check(s >= 60.0 and s <= 600.0, "survive time is a few minutes: " + id)
			# 60 s is quicker than any 3-star lap (star_times start at 68 s): the race cannot end before the goal
			check(int(ev["laps"]) * 60.0 > s, "a survive run is long enough to outlast the goal: " + id)
		var key: String = EventCatalog.name_key(id)
		for lang: String in ["tr", "en"]:
			Settings.set_language(lang)
			check(I18n.t(key) != key, "name translated (" + lang + "): " + id)
		Settings.set_language(saved)
	check(survive_count >= 3, "at least three survive events")


func test_career_pursuit_events_are_gated_by_the_ladder() -> void:
	check(EventCatalog.previous_id("pursuit_harbour_chase") == "elim_maslak", "the first career chase follows the last mode event")
	check(EventCatalog.previous_id("pursuit_maslak_hunt") == "pursuit_harbour_chase", "Maslak hunt follows the harbour chase")
	check(EventCatalog.previous_id("pursuit_bogaz_gauntlet") == "pursuit_maslak_hunt", "the gauntlet follows the Maslak hunt")
	for id: String in ["pursuit_harbour_chase", "pursuit_maslak_hunt", "pursuit_bogaz_gauntlet"]:
		check(not EventCatalog.is_open(id), "career chase is on the ladder, not open: " + id)
