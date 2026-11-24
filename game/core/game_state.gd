extends Node
## Player profile: cash, reputation, garage, car setups, career results and stats.
## JSON at save_path, with save_path + ".bak" holding the last good save. Bad data never
## crashes the game: invalid fields fall back to defaults.

signal cash_changed(new_cash: int)
signal profile_changed

const CURRENT_VERSION: int = 1
const STARTER_CAR: String = "noctra_sable"
const STARTER_CASH: int = 5000
const MAX_CASH: int = 1000000000
const MAX_UPGRADE_LEVEL: int = 5
const MAX_STARS: int = 3
const MAX_TIME_S: float = 100000.0
const UPGRADE_PARTS: PackedStringArray = ["engine", "tires", "nitro", "weight"]
## Upgrade from level n to n+1 costs base * (n + 1).
const UPGRADE_BASE_COST: Dictionary = {"engine": 800, "tires": 500, "nitro": 1200, "weight": 900}
## Rewards by finishing position (index 0 = 1st). Positions past the table earn nothing.
const REWARD_CASH: PackedInt32Array = [1000, 600, 300, 100]
const REWARD_REP: PackedInt32Array = [100, 60, 30, 10]
const REWARD_STARS: PackedInt32Array = [3, 2, 1]
const DEFAULT_PAINT: String = "#8e0f1e"  ## candy red, the starter car colour in docs/art/CAR_01_BRIEF.md
const DEFAULT_RIM: String = "#c0c0c0"

var save_path: String = "user://save.json"
var profile: Dictionary = {}
var _announced_cash: int = -1


func _ready() -> void:
	open_profile(save_path)


## Loads the profile at path (main file, then backup, then defaults). Does not write anything.
func open_profile(path: String) -> void:
	save_path = path
	profile = _load_from_disk()
	_announced_cash = get_cash()


func default_profile() -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"cash": STARTER_CASH,
		"rep": 0,
		"owned_cars": [STARTER_CAR],
		"selected_car": STARTER_CAR,
		"car_setups": {STARTER_CAR: _default_setup()},
		"career": {},
		"stats": {"races": 0, "wins": 0, "cash_earned": 0},
	}


func reset_profile() -> void:
	profile = default_profile()
	_commit()


# --- money and reputation ---------------------------------------------------

func get_cash() -> int:
	return int(profile["cash"])


func get_rep() -> int:
	return int(profile["rep"])


func add_cash(amount: int) -> void:
	if amount < 0:
		push_warning("GameState: add_cash with negative amount")
		return
	profile["cash"] = mini(get_cash() + amount, MAX_CASH)
	_commit()


## Returns false and changes nothing when amount is negative or more than the cash held.
func spend_cash(amount: int) -> bool:
	if amount < 0 or amount > get_cash():
		return false
	profile["cash"] = get_cash() - amount
	_commit()
	return true


func add_rep(amount: int) -> void:
	if amount < 0:
		push_warning("GameState: add_rep with negative amount")
		return
	profile["rep"] = mini(get_rep() + amount, MAX_CASH)
	_commit()


# --- garage -----------------------------------------------------------------

func has_car(car_id: String) -> bool:
	return (profile["owned_cars"] as Array).has(car_id)


## Returns false if the car is already owned or the id is empty.
func own_car(car_id: String) -> bool:
	if car_id.is_empty() or has_car(car_id):
		return false
	(profile["owned_cars"] as Array).append(car_id)
	_setups()[car_id] = _default_setup()
	_commit()
	return true


func get_selected_car() -> String:
	return profile["selected_car"]


func select_car(car_id: String) -> bool:
	if not has_car(car_id):
		return false
	profile["selected_car"] = car_id
	_commit()
	return true


func get_setup(car_id: String) -> Dictionary:
	var setups: Dictionary = _setups()
	if setups.has(car_id):
		return (setups[car_id] as Dictionary).duplicate(true)
	return _default_setup()


func set_paint(car_id: String, color: Color) -> bool:
	return _set_color(car_id, "paint_color", color)


func set_rim(car_id: String, color: Color) -> bool:
	return _set_color(car_id, "rim_color", color)


func get_upgrade_level(car_id: String, part: String) -> int:
	var setup: Dictionary = get_setup(car_id)
	return int((setup["upgrades"] as Dictionary).get(part, 0))


## Cost of the next level for part when the car is at level (0-based current level).
func upgrade_cost(part: String, level: int) -> int:
	return int(UPGRADE_BASE_COST[part]) * (level + 1)


## Returns false for an unowned car, unknown part, max level or too little cash.
func upgrade(car_id: String, part: String) -> bool:
	if not has_car(car_id) or not UPGRADE_PARTS.has(part):
		return false
	var upgrades: Dictionary = _setup_ref(car_id)["upgrades"]
	var level: int = upgrades[part]
	if level >= MAX_UPGRADE_LEVEL:
		return false
	var cost: int = upgrade_cost(part, level)
	if cost > get_cash():
		return false
	profile["cash"] = get_cash() - cost
	upgrades[part] = level + 1
	_commit()
	return true


# --- career -----------------------------------------------------------------

## Records a finished event and returns the rewards: {cash, rep, stars, new_best}.
## Returns an empty dictionary for a bad event id, time or position.
func record_result(event_id: String, time_s: float, position: int) -> Dictionary:
	# Written as a positive test so NaN (every comparison false) and infinity are rejected too.
	if event_id.is_empty() or not (time_s > 0.0 and time_s <= MAX_TIME_S) or position < 1:
		push_warning("GameState: bad result for event '%s'" % event_id)
		return {}
	var cash_reward: int = _reward(REWARD_CASH, position)
	var rep_reward: int = _reward(REWARD_REP, position)
	var stars: int = _reward(REWARD_STARS, position)
	var career: Dictionary = profile["career"]
	var rec: Dictionary = career.get(event_id, {"best_time": 0.0, "best_position": 0, "stars": 0})
	var new_best: bool = float(rec["best_time"]) <= 0.0 or time_s < float(rec["best_time"])
	if new_best:
		rec["best_time"] = time_s
	var best_pos: int = int(rec["best_position"])
	rec["best_position"] = position if best_pos <= 0 else mini(best_pos, position)
	rec["stars"] = maxi(int(rec["stars"]), stars)
	career[event_id] = rec
	profile["cash"] = mini(get_cash() + cash_reward, MAX_CASH)
	profile["rep"] = mini(get_rep() + rep_reward, MAX_CASH)
	var stats: Dictionary = profile["stats"]
	stats["races"] = int(stats["races"]) + 1
	if position == 1:
		stats["wins"] = int(stats["wins"]) + 1
	stats["cash_earned"] = int(stats["cash_earned"]) + cash_reward
	_commit()
	return {"cash": cash_reward, "rep": rep_reward, "stars": stars, "new_best": new_best}


# --- persistence ------------------------------------------------------------

## Writes the temp file and checks it reads back as JSON, keeps the previous valid save as .bak,
## then swaps the temp file in. A failed step leaves .bak (or the main file) as the last good save.
func save_profile() -> bool:
	var tmp_path: String = save_path + ".tmp"
	var bak_path: String = save_path + ".bak"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("GameState: cannot write %s" % tmp_path)
		return false
	f.store_string(JSON.stringify(profile))
	var write_ok: bool = f.get_error() == OK
	f.close()
	if not write_ok or _read_file(tmp_path) == null:
		push_error("GameState: save verification failed for %s" % tmp_path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
		return false
	var g_main: String = ProjectSettings.globalize_path(save_path)
	var g_tmp: String = ProjectSettings.globalize_path(tmp_path)
	var g_bak: String = ProjectSettings.globalize_path(bak_path)
	if _read_file(save_path) != null:
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(g_bak)
		if DirAccess.copy_absolute(g_main, g_bak) != OK:
			push_warning("GameState: backup of %s failed" % save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(g_main)
	var renamed: bool = DirAccess.rename_absolute(g_tmp, g_main) == OK
	if not renamed:
		push_error("GameState: cannot move %s into place" % tmp_path)
	return renamed


func _commit() -> void:
	var cash: int = get_cash()
	if cash != _announced_cash:
		_announced_cash = cash
		cash_changed.emit(cash)
	profile_changed.emit()
	save_profile()


func _load_from_disk() -> Dictionary:
	var main: Variant = _read_file(save_path)
	if main != null:
		return _sanitize(main)
	var bak: Variant = _read_file(save_path + ".bak")
	if bak != null:
		push_warning("GameState: main save unreadable, restored from backup")
		return _sanitize(bak)
	return default_profile()


## Returns the parsed dictionary, or null when the file is missing or not a JSON object.
func _read_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else null


## Migrates old saves, then rebuilds every field with type checks and clamps.
func _sanitize(raw: Dictionary) -> Dictionary:
	var data: Dictionary = _migrate(raw)
	var out: Dictionary = default_profile()
	out["cash"] = _as_int(data.get("cash"), STARTER_CASH, 0, MAX_CASH)
	out["rep"] = _as_int(data.get("rep"), 0, 0, MAX_CASH)

	var owned: Array = []
	var raw_owned: Variant = data.get("owned_cars")
	if raw_owned is Array:
		for c: Variant in raw_owned:
			if c is String and not (c as String).is_empty() and not owned.has(c):
				owned.append(c)
	if owned.is_empty():
		owned = [STARTER_CAR]
	out["owned_cars"] = owned
	var selected: Variant = data.get("selected_car")
	out["selected_car"] = selected if selected is String and owned.has(selected) else owned[0]

	var raw_setups: Dictionary = data.get("car_setups") if data.get("car_setups") is Dictionary else {}
	var setups: Dictionary = {}
	for car_id: String in owned:
		setups[car_id] = _sanitize_setup(raw_setups.get(car_id))
	out["car_setups"] = setups

	var career: Dictionary = {}
	var raw_career: Variant = data.get("career")
	if raw_career is Dictionary:
		for ev: Variant in raw_career:
			var rec: Variant = raw_career[ev]
			if ev is String and rec is Dictionary:
				career[ev] = {
					"best_time": _as_float(rec.get("best_time"), 0.0, 0.0, MAX_TIME_S),
					"best_position": _as_int(rec.get("best_position"), 0, 0, 1000),
					"stars": _as_int(rec.get("stars"), 0, 0, MAX_STARS),
				}
	out["career"] = career

	var stats: Dictionary = (out["stats"] as Dictionary)
	var raw_stats: Variant = data.get("stats")
	if raw_stats is Dictionary:
		for k: String in stats.keys():
			stats[k] = _as_int(raw_stats.get(k), int(stats[k]), 0, MAX_CASH)
	out["stats"] = stats
	return out


func _migrate(raw: Dictionary) -> Dictionary:
	var data: Dictionary = raw.duplicate(true)
	var version: int = _as_int(data.get("version"), 0, 0, CURRENT_VERSION)
	# Add one block per version bump. Version 0 stored the garage under "cars".
	if version < 1:
		if data.has("cars") and not data.has("owned_cars"):
			data["owned_cars"] = data["cars"]
		data.erase("cars")
		version = 1
	data["version"] = version
	return data


func _sanitize_setup(raw: Variant) -> Dictionary:
	var s: Dictionary = _default_setup()
	if not (raw is Dictionary):
		return s
	var d: Dictionary = raw
	s["paint_color"] = _as_color_html(d.get("paint_color"), DEFAULT_PAINT)
	s["rim_color"] = _as_color_html(d.get("rim_color"), DEFAULT_RIM)
	var raw_up: Variant = d.get("upgrades")
	if raw_up is Dictionary:
		var up: Dictionary = s["upgrades"]
		for part: String in UPGRADE_PARTS:
			up[part] = _as_int(raw_up.get(part), 0, 0, MAX_UPGRADE_LEVEL)
	return s


func _default_setup() -> Dictionary:
	return {
		"paint_color": DEFAULT_PAINT,
		"rim_color": DEFAULT_RIM,
		"upgrades": {"engine": 0, "tires": 0, "nitro": 0, "weight": 0},
	}


func _as_color_html(v: Variant, fallback: String) -> String:
	var base: Color = Color.from_string(fallback, Color.WHITE)
	if v is String:
		base = Color.from_string(v, base)
	return base.to_html(false)


func _as_int(v: Variant, fallback: int, lo: int, hi: int) -> int:
	if v is int or v is float:
		return clampi(int(v), lo, hi)
	return fallback


func _as_float(v: Variant, fallback: float, lo: float, hi: float) -> float:
	if v is int or v is float:
		return clampf(float(v), lo, hi)
	return fallback


func _reward(table: PackedInt32Array, position: int) -> int:
	return table[position - 1] if position <= table.size() else 0


func _setups() -> Dictionary:
	return profile["car_setups"] as Dictionary


## The stored setup for car_id, created with defaults if missing. Changes to it are not saved by themselves.
func _setup_ref(car_id: String) -> Dictionary:
	var setups: Dictionary = _setups()
	if not setups.has(car_id):
		setups[car_id] = _default_setup()
	return setups[car_id] as Dictionary


func _set_color(car_id: String, key: String, color: Color) -> bool:
	if not has_car(car_id):
		return false
	var setup: Dictionary = _setup_ref(car_id)
	setup[key] = color.to_html(false)
	_commit()
	return true
