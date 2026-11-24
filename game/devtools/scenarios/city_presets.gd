extends "res://devtools/capture_scenario.gd"
## Performance table on City 01 for one preset per run: --preset=low|medium|high.
## Three fixed viewpoints on the racing line (neon_strip at the grid, downtown_overpass on the guardrail run,
## underpass inside the tunnel), then the full 6-car pack in a live race (player + 5 rivals, autopilot).
## Each view: 60 settle frames, a shot, then cap.measure over 300 frames with vsync off (the probe does that).
## Planar reflection is not attached in the game race path (only devtools use PlanarReflection), so it is reported off.
## Rain is the preset's rain_enabled through fx/rain.gd.

const CITY_SCENE: String = "res://world/city_01/city_01.tscn"
const RACE_SCENE: String = "res://race/race_scene.tscn"
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const LAYOUT: String = "res://assets/world/city_01/city_01_layout.json"
const RAIN_SCENE: String = "res://fx/rain.tscn"
const SAMPLE_M: float = 4.0  ## racing_line sample spacing in layout (551 points over 2203 m)
const LOOK_AHEAD_IDX: int = 8  ## 32 m ahead
const EYE_M: float = 1.3
const FOV_DEG: float = 70.0
const SETTLE_FRAMES: int = 60
const MEASURE_FRAMES: int = 300
const WAIT_STEP_S: float = 1.0 / 60.0
const PACK_OPPONENTS: int = 5
const PACK_LAPS: int = 2
const PACK_GO_WAIT_MAX_S: float = 30.0
const PACK_BACK_M: float = 30.0  ## camera behind the pack centroid
const PACK_UP_M: float = 6.0
const PACK_LOOK_M: float = 2.0
const PACK_RANGE_M: float = 80.0
const VIEWS: Array[Dictionary] = [
	{"name": "neon_strip", "s": 144.0},
	{"name": "downtown_overpass", "s": 850.0},  ## guardrail run s 688 to 1040
	{"name": "underpass", "s": 1620.0},  ## tunnel lights s 1467 to 1803
]

var _city: Node = null
var _race: RaceScene
var _track: Track
var _cam: Camera3D
var _line: Array[Vector3] = []
var _go_seen: bool = false
var _preset: String = ""


func run() -> void:
	_preset = Settings.get_preset_id()
	_line = _load_line()
	if _line.size() < LOOK_AHEAD_IDX + 2:
		cap.fail("racing line missing in layout")
		return
	_city = await cap.load_scene(CITY_SCENE)
	if _city == null:
		return
	_city.add_child((load(RAIN_SCENE) as PackedScene).instantiate())
	_cam = Camera3D.new()
	_cam.fov = FOV_DEG
	_city.add_child(_cam)
	_cam.current = true
	print("city_presets: preset=%s rain=%s planar=off" % [_preset, Settings.get_preset().rain_enabled])
	for view: Dictionary in VIEWS:
		var idx: int = clampi(roundi(float(view["s"]) / SAMPLE_M), 0, _line.size() - LOOK_AHEAD_IDX - 1)
		var p: Vector3 = _line[idx]
		var fwd: Vector3 = _line[idx + LOOK_AHEAD_IDX] - p
		fwd.y = 0.0
		_cam.global_position = p + Vector3(0.0, EYE_M, 0.0)
		_cam.look_at(p + fwd + Vector3(0.0, EYE_M, 0.0))
		await cap.wait_frames(SETTLE_FRAMES)
		var tag: String = "%s_%s" % [view["name"], _preset]
		await cap.shot(tag)
		await cap.measure(tag + "_300f", MEASURE_FRAMES)
	await _pack_view()


## Full pack: a live race with 6 cars. The camera follows the pack centroid from behind.
func _pack_view() -> void:
	if is_instance_valid(_city):
		_city.queue_free()
		await tree.process_frame
	var cfg := RaceConfig.new()
	cfg.autopilot = true
	cfg.laps = PACK_LAPS
	cfg.opponent_count = PACK_OPPONENTS
	cfg.track_scene = CITY_SCENE
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	_race = (load(RACE_SCENE) as PackedScene).instantiate() as RaceScene
	_race.config = cfg
	tree.root.add_child(_race)
	await cap.wait_frames(SETTLE_FRAMES)
	if _race.dev_track_used or _race.dev_car_used or _race.find_child("DevWatermark", true, false) != null:
		cap.fail("dev track, dev mule or DevWatermark present in the pack race")
		return
	_track = _race.track
	_race.race.race_started.connect(_on_go)
	var waited: float = 0.0
	while not _go_seen and waited < PACK_GO_WAIT_MAX_S:
		await cap.wait_frames(1)
		waited += WAIT_STEP_S
	if not _go_seen:
		cap.fail("pack race never started")
		return
	_cam = Camera3D.new()
	_cam.fov = FOV_DEG
	tree.root.add_child(_cam)
	_cam.current = true
	tree.process_frame.connect(_follow_pack)
	await cap.wait_frames(SETTLE_FRAMES)
	print("city_presets: pack in frame=%d of %d cars" % [_pack_in_frame(), _race.cars.size()])
	await cap.shot("pack_%s" % _preset)
	await cap.measure("pack_%s_300f" % _preset, MEASURE_FRAMES)
	tree.process_frame.disconnect(_follow_pack)


func _follow_pack() -> void:
	if _race == null or _track == null or _race.cars.is_empty():
		return
	var c: Vector3 = Vector3.ZERO
	for car: ArcadeCar in _race.cars:
		c += car.global_position
	c /= float(_race.cars.size())
	var fwd: Vector3 = _track.get_tangent_at(_track.get_progress(c))
	fwd.y = 0.0
	fwd = fwd.normalized()
	_cam.global_position = c - fwd * PACK_BACK_M + Vector3.UP * PACK_UP_M
	_cam.look_at(c + fwd * PACK_LOOK_M)


func _pack_in_frame() -> int:
	var n: int = 0
	for car: ArcadeCar in _race.cars:
		if _cam.is_position_in_frustum(car.global_position):
			n += 1
	return n


func _load_line() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if not layout is Dictionary:
		return out
	var pts: Array = (layout as Dictionary)["racing"]["racing_line"]
	for q: Variant in pts:
		var a: Array = q
		out.append(Vector3(float(a[0]), float(a[1]), float(a[2])))
	return out


func _on_go() -> void:
	_go_seen = true
