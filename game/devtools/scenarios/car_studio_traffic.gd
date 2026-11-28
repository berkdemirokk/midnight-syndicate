extends "res://devtools/capture_scenario.gd"
## Evaluation studio for the traffic pool (TrafficModels): the Arden Civic (reference) and the three CC BY 4.0 models
## Yellow City Cab (traffic_cab), City Van (traffic_van), Panel Van (traffic_panel_van), at LOD1 (the level traffic
## draws at a distance). Built the way TrafficCar builds its visual: LOD meshes, paint material, lamp materials, turned
## Visual node. Shots: traffic_row (all four), traffic_cab_34, traffic_van_34, traffic_panel_van_34.

const SETTLE_FRAMES: int = 30
const SHOT_SETTLE_FRAMES: int = 8
const CAM_FOV: float = 42.0
const SPACING: float = 6.0
const LOD: int = 1

var _root: Node3D
var _cam: Camera3D
var _set: ShowroomSet
var _holders: Array[Node3D] = []


func run() -> void:
	_root = Node3D.new()
	_root.name = "TrafficStudio"
	tree.root.add_child(_root)
	var we := WorldEnvironment.new()
	we.environment = ShowroomSet.make_environment()
	_root.add_child(we)
	_set = ShowroomSet.new()
	_root.add_child(_set)
	_set.build_studio()
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_root.add_child(_cam)
	_cam.current = true
	for m: int in TrafficModels.model_count():
		_holders.append(_spawn(m, (m - 1.5) * SPACING))
	await cap.wait_frames(SETTLE_FRAMES)
	_aim_at(Vector3(0.0, 2.6, 22.0), Vector3(0.0, 0.9, 0.0))
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("traffic_row")
	var names: Array[String] = ["traffic_cab_34", "traffic_van_34", "traffic_panel_van_34"]
	for m: int in range(1, TrafficModels.model_count()):
		var x: float = (m - 1.5) * SPACING
		_aim_at(Vector3(x - 3.4, 1.5, 5.6), Vector3(x, 0.9, 0.0))
		await cap.wait_frames(SHOT_SETTLE_FRAMES)
		await cap.shot(names[m - 1])


func _spawn(model: int, x: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Model%d" % model
	holder.position = Vector3(x, 0.0, 0.0)
	_root.add_child(holder)
	var visual := Node3D.new()
	visual.basis = Basis(Vector3.UP, PI)  # the traffic car turns its visual to face +Z
	holder.add_child(visual)
	var first: int = maxi(LOD, TrafficModels.first_lod_of(model))
	var m: Dictionary = TrafficModels.lod(first, model)
	var box: AABB = m["aabb"]
	visual.position.y = -box.position.y
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(0.9, 0.95, 1.0)
	head.emission_enabled = true
	head.emission = Color(0.85, 0.93, 1.0)
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.25, 0.01, 0.01)
	tail.emission_enabled = true
	tail.emission = Color(1.0, 0.0, 0.0)
	for key: String in ["body", "paint", "head", "tail"]:
		var mi := MeshInstance3D.new()
		mi.name = key
		mi.mesh = m[key] as Mesh
		if key == "paint":
			mi.material_override = TrafficModels.paint_material(2)
		elif key == "head":
			mi.material_override = head
		elif key == "tail":
			mi.material_override = tail
		visual.add_child(mi)
	return holder


func _aim_at(eye: Vector3, target: Vector3) -> void:
	_cam.position = eye
	_cam.look_at(target)
