class_name CarCatalog
extends RefCounted
## Cars the player can own: id -> class, price, rep needed, scene and spec paths. Entries whose scene or spec file is
## missing are hidden (is_available), so cars that other work adds later light up with no code change.
## Stats for the UI come from the CarSpec through GarageStats, so there is one source of truth.

const STARTER: String = "noctra_sable"
const DEFAULT_CARS: Array[Dictionary] = [
	{"id": "noctra_sable", "class": "street", "price": 0, "rep": 0},
	# Original 80s-90s Istanbul sedan, the cheap tuner (modified variant; stock and taxi run in traffic).
	{"id": "atmaca_modified", "class": "classic", "price": 4000, "rep": 0,
		"scene": "res://vehicles/bosfor_atmaca/atmaca_modified.tscn", "spec": "res://vehicles/specs/atmaca_modified.tres"},
	{"id": "noctra_vela", "class": "hatch", "price": 8000, "rep": 0},
	{"id": "arden_bruiser", "class": "muscle", "price": 15000, "rep": 300},
	{"id": "kestrel_gtr", "class": "gt", "price": 30000, "rep": 800},
	{"id": "kestrel_vanta", "class": "super", "price": 45000, "rep": 1200},  # CC BY 4.0 model, see THIRD_PARTY_LICENSES.md
	{"id": "arden_havoc", "class": "muscle", "price": 16000, "rep": 400},  # CC BY 4.0 model, see THIRD_PARTY_LICENSES.md
	{"id": "noctra_tayfun", "class": "tuner", "price": 0, "rep": 0},  # CC BY 4.0 model, see THIRD_PARTY_LICENSES.md
	{"id": "bosfor_yildirim", "class": "hyper", "price": 90000, "rep": 2500},  # CC BY 4.0 model, see THIRD_PARTY_LICENSES.md
	{"id": "kestrel_marten", "class": "sport", "price": 22000, "rep": 500},  # CC BY 4.0 model, see THIRD_PARTY_LICENSES.md
	{"id": "noctra_meridian", "class": "gt", "price": 28000, "rep": 700},  # CC BY 4.0 model, see THIRD_PARTY_LICENSES.md
]

## Tests swap this; the game never writes it.
static var cars: Array[Dictionary] = DEFAULT_CARS.duplicate(true)


static func scene_path(id: String) -> String:
	return str(info(id).get("scene", "res://vehicles/%s/%s.tscn" % [id, id]))


static func spec_path(id: String) -> String:
	return str(info(id).get("spec", "res://vehicles/specs/%s.tres" % id))


## The entry for id ({} when unknown).
static func info(id: String) -> Dictionary:
	for c: Dictionary in cars:
		if c["id"] == id:
			return c
	return {}


static func is_available(id: String) -> bool:
	return not info(id).is_empty() and ResourceLoader.exists(scene_path(id)) and ResourceLoader.exists(spec_path(id))


## Catalog order, available cars only.
static func available_ids() -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in cars:
		if is_available(str(c["id"])):
			out.append(str(c["id"]))
	return out


static func price(id: String) -> int:
	return int(info(id).get("price", 0))


static func class_id(id: String) -> String:
	return str(info(id).get("class", "street"))


static func rep_needed(id: String) -> int:
	return int(info(id).get("rep", 0))


## "" when the player can buy id now, else "owned", "unknown", "rep" or "cash".
static func buy_block(id: String) -> String:
	if not is_available(id):
		return "unknown"
	if GameState.has_car(id):
		return "owned"
	if GameState.get_rep() < rep_needed(id):
		return "rep"
	if GameState.get_cash() < price(id):
		return "cash"
	return ""


static func buy(id: String) -> bool:
	return buy_block(id).is_empty() and GameState.buy_car(id, price(id))


## 0..1 stat bars for id with the given upgrades (GarageStats.compute); {} when the spec is missing.
static func stats(id: String, upgrades: Dictionary = {}) -> Dictionary:
	var spec: CarSpec = load(spec_path(id)) as CarSpec
	return GarageStats.compute(spec, upgrades) if spec != null else {}


## The car the player races: the selected one if its files exist, else the starter.
static func race_car_id() -> String:
	var id: String = GameState.get_selected_car()
	return id if is_available(id) else STARTER


## n rival models, deterministic for a seed: [{id, scene, spec}]. cls limits it to one class ("" = all available).
## The caller (race_scene._spawn_cars) builds rival i from entry i instead of config.car_scene / car_spec_path.
static func rival_models(count: int, seed_value: int, cls: String = "") -> Array[Dictionary]:
	var pool: Array[String] = []
	for id: String in available_ids():
		if cls.is_empty() or class_id(id) == cls:
			pool.append(id)
	if pool.is_empty():
		pool.append(STARTER)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var start: int = rng.randi() % pool.size()
	var out: Array[Dictionary] = []
	for i: int in count:
		# Every model appears before any repeats; the start is seeded so grids differ between races.
		var id: String = pool[(start + i) % pool.size()]
		out.append({"id": id, "scene": scene_path(id), "spec": spec_path(id)})
	return out
