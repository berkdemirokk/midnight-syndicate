extends "res://devtools/capture_scenario.gd"
## Contact shadows on City 01: the real race scene (autopilot player, no rivals) at day and night, each shot twice:
## shadow_<tod>_without.png (no blob under the player car, none under the parked cars) and shadow_<tod>_with.png
## (blobs on). Parked cars are wired here the way CityBuilder should do it (one blob MultiMesh per parked cell), if the
## cells have none yet. Optional: --tods=day,night.

const SCENE: String = "res://race/race_scene.tscn"
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const TRACK: String = "res://world/city_01/city_01.tscn"
const TODS: PackedStringArray = ["day", "night"]
const SETTLE_FRAMES: int = 20
const WAIT_MAX_S: float = 30.0
const RACING_SHOT_S: float = 6.0
const PARKED_FAR_M: float = 150.0

var _go_seen: bool = false


func run() -> void:
	var tods: PackedStringArray = TODS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--tods="):
			tods = a.trim_prefix("--tods=").split(",")
	tree.auto_accept_quit = false
	for tod_id: String in tods:
		await _one(tod_id)
		if not is_instance_valid(tree.root):
			return


func _one(tod_id: String) -> void:
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = 2
	cfg.opponent_count = 0
	cfg.track_scene = TRACK
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	cfg.time_of_day = tod_id
	_go_seen = false
	var scene := (load(SCENE) as PackedScene).instantiate() as RaceScene
	scene.config = cfg
	tree.root.add_child(scene)
	await cap.wait_frames(SETTLE_FRAMES)
	scene.race.race_started.connect(func() -> void: _go_seen = true)
	var waited: float = 0.0
	while not _go_seen and waited < WAIT_MAX_S:
		await cap.wait_seconds(0.1)
		waited += 0.1
	if not _go_seen:
		cap.fail("shadow_demo/%s: race never started" % tod_id)
		scene.queue_free()
		return
	await cap.wait_seconds(RACING_SHOT_S)
	var player: ArcadeCar = scene.player
	var player_shadow: Node = player.find_child("ContactShadow", false, false) if player != null else null
	if player != null and player_shadow == null:
		ContactShadow.attach(player, true)
	ContactShadow.set_time_of_day(tod_id)
	var parked: Array[Node] = _wire_parked(scene)
	if "--after" in OS.get_cmdline_user_args():
		_apply_parked_paint(scene, tod_id)
	_set_blobs(scene, false)
	await cap.wait_frames(3)
	await cap.shot("shadow_%s_without" % tod_id)
	_set_blobs(scene, true)
	await cap.wait_frames(3)
	await cap.shot("shadow_%s_with" % tod_id)
	if player != null:
		# Low side view, child of the player car so it moves with it: the blob shows on the road beside the car.
		var side := Camera3D.new()
		side.fov = 50.0
		side.position = Vector3(6.5, 2.6, 0.0)
		side.rotation_degrees = Vector3(-16.0, 90.0, 0.0)
		player.add_child(side)
		side.make_current()
		var blob: ContactShadow = player.find_child("ContactShadow", false, false) as ContactShadow
		if blob != null:
			print("shadow_demo: DEBUG blob pos=%s basis_y=%s visible=%s fade=%s car_y=%.2f" % [str(blob.global_position), str(blob.global_basis.y), str(blob.is_visible_in_tree()), str(blob.get_instance_shader_parameter("lift_fade")), player.global_position.y])
		_set_blobs(scene, false)
		await cap.wait_frames(3)
		await cap.shot("shadow_%s_side_without" % tod_id)
		_set_blobs(scene, true)
		await cap.wait_frames(3)
		await cap.shot("shadow_%s_side_with" % tod_id)
		side.queue_free()
		scene.camera.make_current()
		await _parked_shots(scene, tod_id)
	print("shadow_demo: %s parked blob nodes=%d player blob=%s" % [tod_id, parked.size(), str(player != null)])
	scene.queue_free()
	await cap.wait_frames(5)


## Adds one blob MultiMesh per parked cell (no-op for cells that have one). Returns the blob nodes.
func _wire_parked(scene: RaceScene) -> Array[Node]:
	var out: Array[Node] = []
	for cell: Node in scene.find_children("ParkedCell_*", "Node3D", true, false):
		var old: Node = cell.find_child("ContactShadowParked", false, false)
		if old != null:
			out.append(old)
			continue
		var body: MultiMeshInstance3D = cell.get_node_or_null("Parked_body_lod0") as MultiMeshInstance3D
		if body == null or body.multimesh == null:
			continue
		var xfs: Array[Transform3D] = []
		for i: int in body.multimesh.instance_count:
			xfs.append(body.multimesh.get_instance_transform(i))
		var blob: MultiMeshInstance3D = ContactShadow.shadow_multimesh(xfs, PARKED_FAR_M)
		cell.add_child(blob)
		out.append(blob)
	return out


## Low view of the parked car nearest the player (15 to 40 m away), from its side, without and with the blob.
func _parked_shots(scene: RaceScene, tod_id: String) -> void:
	var best_pos := Vector3.ZERO
	var best_basis := Basis.IDENTITY
	var best_d: float = INF
	var ref: Vector3 = scene.player.global_position
	for cell: Node in scene.find_children("ParkedCell_*", "Node3D", true, false):
		var body: MultiMeshInstance3D = cell.get_node_or_null("Parked_paint_white_lod0") as MultiMeshInstance3D  # the white cars
		if body == null or body.multimesh == null:
			continue
		var cxf: Transform3D = (cell as Node3D).global_transform
		for i: int in body.multimesh.instance_count:
			var xf: Transform3D = cxf * body.multimesh.get_instance_transform(i)
			var d: float = xf.origin.distance_to(ref)
			if d > 12.0 and d < 400.0 and d < best_d:
				best_d = d
				best_pos = xf.origin
				best_basis = xf.basis
	if best_d == INF:
		cap.fail("shadow_demo/%s: no white parked car 12 to 400 m away" % tod_id)
		return
	var cam := Camera3D.new()
	cam.fov = 50.0
	scene.add_child(cam)
	cam.global_position = best_pos + best_basis.x.normalized() * 5.5 + Vector3.UP * 2.0
	cam.look_at(best_pos + Vector3.UP * 0.5, Vector3.UP)
	cam.make_current()
	_set_blobs(scene, false)
	await cap.wait_frames(3)
	await cap.shot("shadow_%s_parked_without" % tod_id)
	_set_blobs(scene, true)
	await cap.wait_frames(3)
	await cap.shot("shadow_%s_parked_with" % tod_id)
	cam.queue_free()
	scene.camera.make_current()


## --after: stands in for city_builder using ParkedCars.parked_paint_colours() (the lead's one-line wiring; this
## scenario does not edit city_builder). Same TimeOfDay multiplier as the build applies.
func _apply_parked_paint(scene: RaceScene, tod_id: String) -> void:
	var colours: Array[Color] = ParkedCars.parked_paint_colours()
	var names: PackedStringArray = ParkedCars.paint_names()
	var mult: float = TimeOfDay.preset(tod_id).parked_albedo
	for n: Node in scene.find_children("Parked_paint_*", "MultiMeshInstance3D", true, false):
		var key: String = String(n.name).trim_prefix("Parked_paint_").get_slice("_lod", 0)
		var idx: int = names.find(key)
		var st: StandardMaterial3D = (n as MultiMeshInstance3D).material_override as StandardMaterial3D
		if idx < 0 or st == null:
			continue
		var c: Color = colours[idx]
		st.albedo_color = Color(clampf(c.r * mult, 0.0, 1.0), clampf(c.g * mult, 0.0, 1.0), clampf(c.b * mult, 0.0, 1.0))


func _set_blobs(scene: RaceScene, on: bool) -> void:
	for n: Node in scene.find_children("ContactShadow*", "", true, false):
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).visible = on
