class_name EventCatalog
extends RefCounted
## Career ladder: six events on City 01 "Neon Wharf Loop", then four World Tour events in Istanbul (Maslak, Bogaz); each an id, text keys, a RaceConfig recipe, a reward
## multiplier and the star rule. Position events: 1st = 3 stars, podium = 2, finish = 1 (GameState.REWARD_STARS).
## Time events carry star_times = [3 stars, 2 stars, 1 star] in seconds; any finish earns at least 1 star, so a slow
## first try still opens the next event.
## Unknown ids (the dev circuit, tests) fall back to position stars and a 1.0 reward multiplier.
## Drift events ("mode": "drift") run a timed solo session and earn stars from the drift score ("star_scores", 3/2/1 stars).
## Elimination events ("mode": "elimination") run cars - 1 laps; the last car out ends every lap, and the player's
## elimination ends the race with a placed result.
## Chapters ("chapter" 1-4) are contiguous runs of the ladder order; "boss" marks the race that closes one.
## "reverse": true runs the track the other way (Track.set_reversed); the event keeps its id, order and rewards.
## Tuning note: the autopilot laps the loop in about 64 s (TEST_RESULTS), so the star times below are a first guess for
## a good human lap and want a play test.

const PODIUM_PLACES: int = 3
const TRACK_MASLAK: String = "res://world/istanbul_maslak/istanbul_maslak.tscn"
const TRACK_BOGAZ: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"

const EVENTS: Array[Dictionary] = [
	# Showcase and first race: the Ortakoy coast at night, open from the first start ("open": true). One lap of about a
	# minute against street-class cars ("cls"): before, the seeded rival draw put a 352 km/h hypercar on this grid.
	{"id": "ortakoy_night", "tod": "night", "laps": 1, "skills": [0.70, 0.68, 0.66], "level": 1, "mult": 1.5, "track": TRACK_BOGAZ, "place": "ortakoy", "open": true, "cls": "street", "chapter": 1},
	{"id": "wharf_sprint", "tod": "sunset", "laps": 1, "skills": [0.84, 0.82, 0.80], "level": 1, "mult": 1.0, "traffic": true, "cls": "street", "chapter": 1},
	{"id": "neon_strip_circuit", "tod": "night", "laps": 2, "skills": [0.88, 0.86, 0.85, 0.83, 0.82], "level": 2, "mult": 1.3, "traffic": true, "reverse": true, "chapter": 1},
	{"id": "midnight_time_trial", "tod": "night", "laps": 1, "skills": [], "level": 2, "mult": 1.2, "star_times": [72.0, 82.0, 100.0], "chapter": 1},
	{"id": "overpass_duel", "tod": "day", "laps": 2, "skills": [0.96], "level": 3, "mult": 1.6, "reverse": true, "chapter": 1, "boss": true},
	{"id": "harbour_run", "tod": "sunset", "laps": 3, "skills": [0.94, 0.93, 0.92, 0.91, 0.90], "level": 3, "mult": 2.0, "chapter": 2},
	{"id": "syndicate_final", "tod": "night", "laps": 3, "skills": [0.99, 0.98, 0.97, 0.96, 0.95], "level": 4, "mult": 3.0, "chapter": 2},
	# World Tour: Istanbul (unlocked after the Arden Bay final)
	{"id": "maslak_sprint", "tod": "day", "laps": 1, "skills": [0.92, 0.90, 0.88], "level": 3, "mult": 3.2, "track": TRACK_MASLAK, "place": "maslak", "chapter": 2},
	{"id": "bogaz_circuit", "tod": "sunset", "laps": 2, "skills": [0.94, 0.93, 0.92, 0.91, 0.90], "level": 3, "mult": 3.5, "track": TRACK_BOGAZ, "place": "bogaz", "reverse": true, "chapter": 2},
	{"id": "maslak_night", "tod": "night", "laps": 2, "skills": [0.97, 0.96, 0.95, 0.94, 0.93], "level": 4, "mult": 4.0, "track": TRACK_MASLAK, "place": "maslak", "chapter": 2},
	{"id": "bogaz_final", "tod": "night", "laps": 3, "skills": [0.99, 0.99, 0.98, 0.97, 0.96], "level": 4, "mult": 5.0, "track": TRACK_BOGAZ, "place": "bogaz", "chapter": 2},
	# Extended tour: existing event ids and order remain unchanged.
	{"id": "maslak_time_trial", "tod": "day", "laps": 1, "skills": [], "level": 2, "mult": 2, "place": "maslak", "star_times": [75, 90, 110], "track": TRACK_MASLAK, "chapter": 2},
	{"id": "bogaz_duel", "tod": "day", "laps": 1, "skills": [0.93], "level": 3, "mult": 2.5, "place": "bogaz", "track": TRACK_BOGAZ, "reverse": true, "chapter": 2, "boss": true},
	{"id": "wharf_return", "tod": "day", "laps": 2, "skills": [0.91, 0.9, 0.88], "level": 3, "mult": 2.5, "chapter": 3},
	{"id": "maslak_rush", "tod": "sunset", "laps": 2, "skills": [0.93, 0.92, 0.91], "level": 3, "mult": 3, "place": "maslak", "traffic": true, "track": TRACK_MASLAK, "reverse": true, "chapter": 3},
	{"id": "bogaz_time_trial", "tod": "sunset", "laps": 1, "skills": [], "level": 3, "mult": 3, "place": "bogaz", "star_times": [75, 90, 110], "track": TRACK_BOGAZ, "chapter": 3},
	{"id": "wharf_duel", "tod": "night", "laps": 2, "skills": [0.96], "level": 3, "mult": 3.2, "reverse": true, "chapter": 3},
	{"id": "maslak_endurance", "tod": "day", "laps": 3, "skills": [0.94, 0.93, 0.92, 0.91, 0.9], "level": 3, "mult": 3.5, "place": "maslak", "track": TRACK_MASLAK, "chapter": 3},
	{"id": "bogaz_rush", "tod": "day", "laps": 2, "skills": [0.94, 0.92, 0.9], "level": 3, "mult": 3.5, "place": "bogaz", "traffic": true, "track": TRACK_BOGAZ, "chapter": 3},
	{"id": "wharf_time_trial", "tod": "sunset", "laps": 1, "skills": [], "level": 3, "mult": 3.5, "star_times": [68, 78, 95], "chapter": 3},
	{"id": "maslak_duel", "tod": "night", "laps": 2, "skills": [0.97], "level": 4, "mult": 4, "place": "maslak", "track": TRACK_MASLAK, "reverse": true, "chapter": 3, "boss": true},
	{"id": "bogaz_blue_hour", "tod": "sunset", "laps": 3, "skills": [0.95, 0.94, 0.93, 0.92, 0.91], "level": 4, "mult": 4, "place": "bogaz", "track": TRACK_BOGAZ, "chapter": 4},
	{"id": "wharf_endurance", "tod": "night", "laps": 3, "skills": [0.96, 0.95, 0.94, 0.93, 0.92], "level": 4, "mult": 4.2, "reverse": true, "chapter": 4},
	{"id": "maslak_elite", "tod": "sunset", "laps": 2, "skills": [0.98, 0.97, 0.96, 0.95, 0.94], "level": 4, "mult": 4.3, "place": "maslak", "track": TRACK_MASLAK, "reverse": true, "chapter": 4},
	{"id": "bogaz_night_duel", "tod": "night", "laps": 2, "skills": [0.98], "level": 4, "mult": 4.5, "place": "bogaz", "track": TRACK_BOGAZ, "reverse": true, "chapter": 4},
	{"id": "wharf_elite", "tod": "day", "laps": 2, "skills": [0.98, 0.97, 0.96, 0.95, 0.94], "level": 4, "mult": 4.5, "chapter": 4},
	{"id": "maslak_master", "tod": "night", "laps": 3, "skills": [0.99, 0.98, 0.97, 0.96, 0.95], "level": 4, "mult": 4.7, "place": "maslak", "track": TRACK_MASLAK, "chapter": 4},
	{"id": "bogaz_master", "tod": "day", "laps": 3, "skills": [0.99, 0.98, 0.97, 0.96, 0.95], "level": 4, "mult": 4.8, "place": "bogaz", "track": TRACK_BOGAZ, "chapter": 4},
	{"id": "wharf_championship", "tod": "night", "laps": 3, "skills": [0.99, 0.99, 0.98, 0.97, 0.96], "level": 4, "mult": 5, "chapter": 4},
	{"id": "istanbul_championship", "tod": "night", "laps": 3, "skills": [0.99, 0.99, 0.98, 0.97, 0.96], "level": 4, "mult": 5.5, "place": "bogaz", "track": TRACK_BOGAZ, "chapter": 4, "boss": true},
	# Modes, appended after the championship so existing saves keep every unlock (the ladder unlocks in order).
	# Provisional tuning: score thresholds and time limits want a human playtest.
	{"id": "drift_harbour", "mode": "drift", "tod": "sunset", "laps": 1, "skills": [], "level": 2, "mult": 2.0, "time_limit": 60.0, "star_scores": [1000, 600, 250]},
	{"id": "elim_wharf", "mode": "elimination", "tod": "day", "laps": 3, "skills": [0.90, 0.88, 0.86], "level": 2, "mult": 2.5, "cls": "street"},
	{"id": "drift_bogaz", "mode": "drift", "tod": "night", "laps": 1, "skills": [], "level": 3, "mult": 3.5, "place": "bogaz", "track": TRACK_BOGAZ, "time_limit": 75.0, "star_scores": [1400, 800, 350]},
	{"id": "elim_maslak", "mode": "elimination", "tod": "sunset", "laps": 4, "skills": [0.95, 0.94, 0.93, 0.92], "level": 3, "mult": 4.0, "place": "maslak", "track": TRACK_MASLAK},
	# Career pursuit events, right after the last mode event so the ladder gates them in turn (an open row in front of
	# them would unlock the first one at once). A survive run has laps x 60 s > survive_s: the race must not end first.
	{"id": "pursuit_harbour_chase", "tod": "night", "laps": 3, "skills": [0.96, 0.95, 0.94], "level": 3, "mult": 2.5, "survive_s": 120.0, "traffic": true, "cls": "street", "pursuit": true},
	{"id": "pursuit_maslak_hunt", "tod": "night", "laps": 2, "skills": [0.97, 0.96, 0.95], "level": 4, "mult": 2.75, "place": "maslak", "track": TRACK_MASLAK, "pursuit": true},
	{"id": "pursuit_bogaz_gauntlet", "tod": "sunset", "laps": 4, "skills": [0.98, 0.97, 0.96], "level": 4, "mult": 3.25, "survive_s": 180.0, "place": "bogaz", "track": TRACK_BOGAZ, "pursuit": true},
	# Police chase on the Bosphorus at night: "open" (never locked, never gates the ladder), "pursuit" opts in to PursuitMode.
	{"id": "bogaz_escape", "tod": "night", "laps": 2, "skills": [0.9, 0.88, 0.86], "level": 3, "mult": 3.0, "place": "bogaz", "track": TRACK_BOGAZ, "open": true, "pursuit": true, "cls": "street"},
	# Pursuit runs, open: independent of the career ladder, on all three tracks. "survive_s" = the survive goal (chase time, no bust).
	{"id": "pursuit_wharf_escape", "tod": "night", "laps": 2, "skills": [0.9, 0.88, 0.86], "level": 2, "mult": 1.5, "traffic": true, "cls": "street", "open": true, "pursuit": true},
	{"id": "pursuit_wharf_survive", "tod": "sunset", "laps": 3, "skills": [0.92, 0.9, 0.88], "level": 2, "mult": 1.75, "survive_s": 150.0, "traffic": true, "cls": "street", "open": true, "pursuit": true},
	{"id": "pursuit_maslak_escape", "tod": "day", "laps": 2, "skills": [0.92, 0.9, 0.88], "level": 3, "mult": 1.75, "place": "maslak", "track": TRACK_MASLAK, "open": true, "pursuit": true},
	{"id": "pursuit_maslak_survive", "tod": "sunset", "laps": 3, "skills": [0.94, 0.92, 0.9], "level": 3, "mult": 2.0, "survive_s": 150.0, "place": "maslak", "track": TRACK_MASLAK, "open": true, "pursuit": true},
	{"id": "pursuit_bogaz_survive", "tod": "night", "laps": 3, "skills": [0.94, 0.93, 0.92], "level": 3, "mult": 2.0, "survive_s": 150.0, "place": "bogaz", "track": TRACK_BOGAZ, "open": true, "pursuit": true},
]


## Race mode of an event: RaceConfig.MODE_RACE unless the event names another one.
static func mode_of(id: String) -> String:
	return str(find(id).get("mode", RaceConfig.MODE_RACE))


## True for drift events: stars come from the drift score, not from the finishing position.
static func is_score_event(id: String) -> bool:
	return find(id).has("star_scores")


## True for showcase events that never lock and never gate the ladder.
static func is_open(id: String) -> bool:
	return bool(find(id).get("open", false))


static func count() -> int:
	return EVENTS.size()


static func index_of(id: String) -> int:
	for i: int in EVENTS.size():
		if EVENTS[i]["id"] == id:
			return i
	return -1


## The event dictionary for id, or an empty one.
static func find(id: String) -> Dictionary:
	var i: int = index_of(id)
	return EVENTS[i] if i >= 0 else {}


static func id_at(index: int) -> String:
	return str(EVENTS[index]["id"])


## Id of the event before id, or "" for the first event and unknown ids.
static func previous_id(id: String) -> String:
	var i: int = index_of(id)
	return id_at(i - 1) if i > 0 else ""


## Id of the event after id, or "" for the last event and unknown ids.
static func next_id(id: String) -> String:
	var i: int = index_of(id)
	if i < 0:
		return ""
	for j: int in range(i + 1, EVENTS.size()):  # showcase events are skipped: the ladder ends at its last event
		if not is_open(id_at(j)):
			return id_at(j)
	return ""


## Text key prefix, e.g. "event.wharf_sprint" (+ ".name").
static func name_key(id: String) -> String:
	if find(id).get("reverse", false):  # reverse variants carry their own "Ters yon" / "Reverse" names
		return "event.%s.reverse.name" % id
	return "event.%s.name" % id


## Career chapter of an event (1-4), 0 for the tail (modes and pursuit runs, unchained to a chapter).
static func chapter_of(id: String) -> int:
	return int(find(id).get("chapter", 0))


## True for the boss race that closes a chapter.
static func is_boss(id: String) -> bool:
	return bool(find(id).get("boss", false))


static func chapter_name_key(chapter: int) -> String:
	return "chapter.%d.name" % chapter


static func is_time_event(id: String) -> bool:
	return find(id).has("star_times")


static func reward_multiplier(id: String) -> float:
	return float(find(id).get("mult", 1.0))


## Stars for a finish. Time events use the star_times table, drift events the star_scores table (score given),
## every other event the finishing position.
static func stars_for(id: String, time_s: float, position: int, score: float = -1.0) -> int:
	var ev: Dictionary = find(id)
	if ev.has("star_scores"):
		var earned: int = 0
		for limit: float in ev["star_scores"]:  # descending: 3, 2, 1 stars
			if score >= limit:
				earned += 1
		return maxi(earned, 1) if time_s > 0.0 else 0  # a finished drift session always earns a star
	if ev.has("star_times"):
		var stars: int = 0
		for limit: float in ev["star_times"]:
			if time_s <= limit:
				stars += 1
		return maxi(stars, 1) if time_s > 0.0 else 0
	if position < 1:
		return 0
	if ev.is_empty():
		return GameState.REWARD_STARS[position - 1] if position <= GameState.REWARD_STARS.size() else 0
	return 3 if position == 1 else (2 if position <= PODIUM_PLACES else 1)  # ladder events: finishing always earns a star


## Cash and rep a win pays on this event (the preview shown on the select screen).
static func win_rewards(id: String) -> Dictionary:
	var m: float = reward_multiplier(id)
	return {"cash": roundi(GameState.REWARD_CASH[0] * m), "rep": roundi(GameState.REWARD_REP[0] * m)}


## RaceConfig for id; null for an unknown id. race_scene reads it from Router params["config"].
static func config_for(id: String) -> RaceConfig:
	var ev: Dictionary = find(id)
	if ev.is_empty():
		return null
	var c := RaceConfig.new()
	c.event_id = id
	var car_id: String = CarCatalog.race_car_id()  # the player races the garage's selected car
	c.car_scene = CarCatalog.scene_path(car_id)
	c.car_spec_path = CarCatalog.spec_path(car_id)
	if ev.has("track"):
		c.track_scene = str(ev["track"])
	c.laps = int(ev["laps"])
	var skills := PackedFloat32Array()
	for s: float in ev["skills"]:
		skills.append(s)
	c.opponent_skills = skills
	c.opponent_count = skills.size()
	c.mode = mode_of(id)
	if c.mode == RaceConfig.MODE_ELIMINATION:
		c.laps = c.opponent_count  # cars - 1 laps: one car is out at the end of each lap
	if c.mode == RaceConfig.MODE_DRIFT:
		c.time_limit_s = float(ev.get("time_limit", 60.0))
	c.rival_mix = true
	c.rival_class = str(ev.get("cls", ""))
	c.traffic_enabled = bool(ev.get("traffic", false))
	c.time_of_day = str(ev.get("tod", "night"))
	c.reverse_route = bool(ev.get("reverse", false))
	c.pursuit = bool(ev.get("pursuit", false))
	c.pursuit_event = c.pursuit
	return c
