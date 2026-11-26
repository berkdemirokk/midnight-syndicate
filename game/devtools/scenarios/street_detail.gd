extends "res://devtools/capture_scenario.gd"
## Street detail close-ups on the three tracks: side lanes seen from the road and from the sidewalk, a junction signal.
## Reads the shipped layouts: every street_alley_floor instance is a lane (position = lane mouth, local +Z faces the road),
## every street_signal instance a mast. Camera eye 1.3 m (road) or 1.7 m (sidewalk), FOV 70. Shots per track:
## lane_<n>_road (14 m out on the road, looking 18 m down the lane), lane_<n>_walk (5 m out, looking down the lane),
## signal (racing line, 22 m before the mast). No wet road or planar reflection here: lane dressing is what is judged.

const TRACKS: Array[Dictionary] = [
	{"id": "city", "scene": "res://world/city_01/city_01.tscn", "layout": "res://assets/world/city_01/city_01_layout.json"},
	{"id": "maslak", "scene": "res://world/istanbul_maslak/istanbul_maslak.tscn", "layout": "res://assets/world/istanbul_maslak/istanbul_maslak_layout.json"},
	{"id": "bogaz", "scene": "res://world/istanbul_bogaz/istanbul_bogaz.tscn", "layout": "res://assets/world/istanbul_bogaz/istanbul_bogaz_layout.json"},
]
const LANES_PER_TRACK: int = 3
const SETTLE_FRAMES: int = 90
const MEASURE_FRAMES: int = 120

var _cam: Camera3D


func run() -> void:
	for t: Dictionary in TRACKS:
		var world: Node = await cap.load_scene(String(t["scene"]))
		if world == null:
			return
		var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(String(t["layout"])))
		if _cam == null or not is_instance_valid(_cam):
			_cam = Camera3D.new()
			_cam.fov = 70.0
		if _cam.get_parent() != null:
			_cam.get_parent().remove_child(_cam)
		world.add_child(_cam)
		_cam.current = true
		var lanes: Array = []
		var masts: Array = []
		for v: Variant in layout["instances"]:
			var d: Dictionary = v
			if String(d["kind"]) != "prop":
				continue
			if String(d["asset"]) == "street_alley_floor":
				lanes.append(d)
			elif String(d["asset"]) == "street_signal":
				masts.append(d)
		var pick: Array = []
		for k: int in LANES_PER_TRACK:
			if lanes.size() > 0:
				pick.append(lanes[mini(lanes.size() - 1, int(float(k + 0.5) * float(lanes.size()) / float(LANES_PER_TRACK)))])
		var n: int = 0
		for d: Dictionary in pick:
			var pos: Array = d["position"]
			var p := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
			var front := Vector3(sin(float(d["yaw"])), 0.0, cos(float(d["yaw"])))
			_cam.global_position = p + front * 14.0 + Vector3(0.0, 1.3, 0.0)
			_cam.look_at(p - front * 18.0 + Vector3(0.0, 2.5, 0.0))
			await _take("%s_lane_%d_road" % [t["id"], n])
			_cam.global_position = p + front * 5.0 + Vector3(0.0, 1.7, 0.0)
			_cam.look_at(p - front * 16.0 + Vector3(0.0, 1.8, 0.0))
			await _take("%s_lane_%d_walk" % [t["id"], n])
			n += 1
		if masts.size() > 0:
			var m: Dictionary = masts[masts.size() / 2]
			var mp: Array = m["position"]
			var pole := Vector3(float(mp[0]), float(mp[1]), float(mp[2]))
			var line: Array = layout["racing"]["racing_line"]
			var best: int = 0
			var best_d: float = 1e12
			for i: int in line.size():
				var q: Array = line[i]
				var dd: float = Vector2(float(q[0]) - pole.x, float(q[2]) - pole.z).length()
				if dd < best_d:
					best_d = dd
					best = i
			var a: Array = line[maxi(0, best - 6)]
			_cam.global_position = Vector3(float(a[0]), float(a[1]) + 1.3, float(a[2]))
			_cam.look_at(pole + Vector3(0.0, 5.0, 0.0))
			await _take("%s_signal" % t["id"])


func _take(shot_name: String) -> void:
	await cap.wait_frames(SETTLE_FRAMES)
	await cap.shot(shot_name)
	await cap.measure(shot_name + "_measure", MEASURE_FRAMES)
