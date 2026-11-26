class_name EventCatalog
extends RefCounted
## Career ladder: six events on City 01 "Neon Wharf Loop", then four World Tour events in Istanbul (Maslak, Bogaz); each an id, text keys, a RaceConfig recipe, a reward
## multiplier and the star rule. Position events: 1st = 3 stars, podium = 2, finish = 1 (GameState.REWARD_STARS).
## Time events carry star_times = [3 stars, 2 stars, 1 star] in seconds; any finish earns at least 1 star, so a slow
## first try still opens the next event.
## Unknown ids (the dev circuit, tests) fall back to position stars and a 1.0 reward multiplier.
## Tuning note: the autopilot laps the loop in about 64 s (TEST_RESULTS), so the star times below are a first guess for
## a good human lap and want a play test.

const PODIUM_PLACES: int = 3
const TRACK_MASLAK: String = "res://world/istanbul_maslak/istanbul_maslak.tscn"
const TRACK_BOGAZ: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"

const EVENTS: Array[Dictionary] = [
	{"id": "wharf_sprint", "tod": "sunset", "laps": 1, "skills": [0.84, 0.82, 0.80], "level": 1, "mult": 1.0, "traffic": true},
	{"id": "neon_strip_circuit", "tod": "night", "laps": 2, "skills": [0.88, 0.86, 0.85, 0.83, 0.82], "level": 2, "mult": 1.3, "traffic": true},
	{"id": "midnight_time_trial", "tod": "night", "laps": 1, "skills": [], "level": 2, "mult": 1.2, "star_times": [72.0, 82.0, 100.0]},
	{"id": "overpass_duel", "tod": "day", "laps": 2, "skills": [0.96], "level": 3, "mult": 1.6},
	{"id": "harbour_run", "tod": "sunset", "laps": 3, "skills": [0.94, 0.93, 0.92, 0.91, 0.90], "level": 3, "mult": 2.0},
	{"id": "syndicate_final", "tod": "night", "laps": 3, "skills": [0.99, 0.98, 0.97, 0.96, 0.95], "level": 4, "mult": 3.0},
	# World Tour: Istanbul (unlocked after the Arden Bay final)
	{"id": "maslak_sprint", "tod": "day", "laps": 1, "skills": [0.92, 0.90, 0.88], "level": 3, "mult": 3.2, "track": TRACK_MASLAK, "place": "maslak"},
	{"id": "bogaz_circuit", "tod": "sunset", "laps": 2, "skills": [0.94, 0.93, 0.92, 0.91, 0.90], "level": 3, "mult": 3.5, "track": TRACK_BOGAZ, "place": "bogaz"},
	{"id": "maslak_night", "tod": "night", "laps": 2, "skills": [0.97, 0.96, 0.95, 0.94, 0.93], "level": 4, "mult": 4.0, "track": TRACK_MASLAK, "place": "maslak"},
	{"id": "bogaz_final", "tod": "night", "laps": 3, "skills": [0.99, 0.99, 0.98, 0.97, 0.96], "level": 4, "mult": 5.0, "track": TRACK_BOGAZ, "place": "bogaz"},
]


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
	return id_at(i + 1) if i >= 0 and i < EVENTS.size() - 1 else ""


## Text key prefix, e.g. "event.wharf_sprint" (+ ".name").
static func name_key(id: String) -> String:
	return "event.%s.name" % id


static func is_time_event(id: String) -> bool:
	return find(id).has("star_times")


static func reward_multiplier(id: String) -> float:
	return float(find(id).get("mult", 1.0))


## Stars for a finish. Time events use the star_times table, every other event the finishing position.
static func stars_for(id: String, time_s: float, position: int) -> int:
	var ev: Dictionary = find(id)
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
	c.rival_mix = true
	c.traffic_enabled = bool(ev.get("traffic", false))
	c.time_of_day = str(ev.get("tod", "night"))
	return c
