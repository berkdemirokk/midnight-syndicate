extends "res://devtools/capture_scenario.gd"
## City 01 district looks on the racing line: eye height 1.3 m, FOV 70, race direction, wet road at wetness 1
## with rain on. Planar reflection on the High preset only (plane = local road height under the camera).
## Shots: neon_strip (start grid), downtown (overpass), waterfront, underpass (inside), old_market (hairpin),
## waterfront_stacks_line (racing line, aimed at the nearest land-side container stack), establishing_60m (60 m up, about
## 27 deg down, along the Neon Strip, lens shifted up so the skyline reads). Each shot carries a 300-frame perf probe.

const SCENE: String = "res://world/city_01/city_01.tscn"
const LAYOUT: String = "res://assets/world/city_01/city_01_layout.json"
const EYE_M: float = 1.3
const FOV_DEG: float = 70.0
const LOOK_AHEAD_IDX: int = 8  ## 8 samples x 4 m = 32 m ahead
const SAMPLE_M: float = 4.0
const SETTLE_FRAMES: int = 60
const MEASURE_FRAMES: int = 300
const ROAD_RAIN_INTENSITY: float = 1.0
const ESTABLISH_HEIGHT_M: float = 60.0
const ESTABLISH_BACK_M: float = 117.0  ## 60 m up and 117 m back from the Neon Strip point: the view looks about 27 deg down
const ESTABLISH_FOV_DEG: float = 95.0  ## wider frame than the racing shots: more rooftops and skyline above the street canyon
const NEON_MID_S: float = 144.0
const ROAD_LAYER_BIT: int = 1 << 1  ## road is kept out of the planar mirror (see PlanarReflection.excluded_layers)
const SHOTS: Array[Dictionary] = [
	{"name": "neon_strip", "s": 144.0},
	{"name": "downtown", "s": 590.0},  ## downtown lamp run is s 514 to 665; the old s 750 looked past every lamp
	{"name": "waterfront", "s": 1250.0, "yaw": 27.0},  ## yaw 27: promenade lamp run ahead-left (heading -15..-21) and the bay on the right edge; yaw 80 looked past every lamp
	{"name": "waterfront_stacks", "s": 1279.0, "yaw": 80.0},  ## yaw 80 faces the container stack and gantry crane across the quay (about 360 m east)
	{"name": "waterfront_lot", "s": 1175.0, "yaw": -55.0},  ## yaw -55 faces the land side: two container stacks and the gantry crane 40 to 60 m out behind the warehouses
	{"name": "waterfront_harbour", "s": 1385.0, "yaw": -40.0},  ## past the warehouse row: the sightline to the stack and crane clears its end
	{"name": "waterfront_stacks_line", "s": 1425.0, "aim": "container_stack"},  ## racing line past the warehouse row, looking at the nearest stack ahead
	{"name": "underpass", "s": 1620.0},
	{"name": "old_market", "s": 1950.0},
]

var _line: Array[Vector3] = []
var _road_mats: Array[ShaderMaterial] = []
var _planar: PlanarReflection
var _cam: Camera3D


func run() -> void:
	var city: Node = await cap.load_scene(SCENE)
	if city == null:
		return
	print("city_districts: lights dropped=%s over_volumes=%s" % [city.get("light_report")["dropped"], city.get("light_report")["over_volumes"]])
	for line: String in city.get("light_report")["log"]:
		print("city_districts: budget " + line)
	print("city_districts: floodlights in scene=%d" % city.find_children("floodlight_*", "SpotLight3D", true, false).size())
	for row: Dictionary in city.get("stats")["dressing"]:
		if String(row["kit"]) != "bollard":
			print("city_districts: dressing %s %s %s s=%.1f lat=%.2f pos=%s" % [row["kit"], row["district"], row["side"], float(row["s"]), float(row["lat"]), row["pos"]])
	_line = _load_line()
	if _line.size() < LOOK_AHEAD_IDX + 2:
		cap.fail("racing line missing in layout")
		return
	var road: Node = city.find_child("Road", true, false)
	if road == null:
		cap.fail("Road node not found")
		return
	_prepare_road(road)
	city.add_child((load("res://fx/rain.tscn") as PackedScene).instantiate())
	_planar = PlanarReflection.new()
	city.add_child(_planar)
	for m: ShaderMaterial in _road_mats:
		_planar.add_target_material(m)
		m.set_shader_parameter("wetness", 1.0)
		m.set_shader_parameter("rain_intensity", ROAD_RAIN_INTENSITY)
	var high: bool = Settings.get_preset_id() == "high"
	_planar.call("set_enabled", high)
	print("city_districts: preset=%s planar=%s road_mats=%d" % [Settings.get_preset_id(), high, _road_mats.size()])

	_cam = Camera3D.new()
	_cam.fov = FOV_DEG
	city.add_child(_cam)
	_cam.current = true

	for shot: Dictionary in SHOTS:
		var idx: int = clampi(roundi(float(shot["s"]) / SAMPLE_M), 0, _line.size() - LOOK_AHEAD_IDX - 1)
		var p: Vector3 = _line[idx]
		var fwd: Vector3 = _line[idx + LOOK_AHEAD_IDX] - p
		fwd.y = 0.0
		fwd = fwd.rotated(Vector3.UP, deg_to_rad(float(shot.get("yaw", 0.0))))
		var target: Vector3 = p + fwd + Vector3(0.0, EYE_M, 0.0)
		if shot.has("aim"):
			target = _aim_point(city, String(shot["aim"]), float(shot["s"]))
		_place(p + Vector3(0.0, EYE_M, 0.0), target, p.y)
		await _take(str(shot["name"]))

	var mid: int = roundi(NEON_MID_S / SAMPLE_M)
	var c: Vector3 = _line[mid]
	var f: Vector3 = (_line[mid + 1] - c).normalized()
	_place(c - f * ESTABLISH_BACK_M + Vector3(0.0, ESTABLISH_HEIGHT_M, 0.0), c, c.y)  # looks down the strip
	_cam.fov = ESTABLISH_FOV_DEG
	await _take("establishing_60m")
	_cam.fov = FOV_DEG


## Centre height of the nearest placed prop of this kit ahead of arc length s, from the dressing log of the build.
func _aim_point(city: Node, kit: String, s: float) -> Vector3:
	var best: Dictionary = {}
	for row: Dictionary in city.get("stats")["dressing"]:
		if String(row["kit"]) == kit and float(row["s"]) > s and (best.is_empty() or float(row["s"]) < float(best["s"])):
			best = row
	var pos: Array = best["pos"]
	return Vector3(float(pos[0]), float(pos[1]) + 8.0, float(pos[2]))


func _place(eye: Vector3, target: Vector3, plane_y: float) -> void:
	_cam.global_position = eye
	_cam.look_at(target)
	if _planar:
		_planar.plane_height = plane_y


func _take(shot_name: String) -> void:
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot(shot_name)
	await cap.measure(shot_name + "_measure", MEASURE_FRAMES)


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


func _prepare_road(road: Node) -> void:
	for n: Node in road.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		mi.layers = ROAD_LAYER_BIT
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s: int in mesh.get_surface_count():
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = mesh.surface_get_material(s)
			if mat is ShaderMaterial and mat.resource_name == "M_Asphalt" and not _road_mats.has(mat):
				_road_mats.append(mat as ShaderMaterial)
