extends "res://devtools/capture_scenario.gd"
## Time of day on every track: the real race scene, autopilot player, 5 rivals, one chase-view shot 10 s after GO
## for each track (City 01, Maslak, Bogaz) at day, sunset and night. Shots are named <track>_<tod> (plus _<preset>
## when the preset is not high), e.g. city_day.png, maslak_sunset_low.png.
## Optional user args: --only=<track>:<tod> (one combination, e.g. --only=maslak:day), --tracks=city,maslak,
## --tods=day,night. Fails when the dev track, dev mule or DevWatermark shows up, or the race never starts.

const SCENE: String = "res://race/race_scene.tscn"
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const TRACKS: Dictionary = {
	"city": "res://world/city_01/city_01.tscn",
	"maslak": "res://world/istanbul_maslak/istanbul_maslak.tscn",
	"bogaz": "res://world/istanbul_bogaz/istanbul_bogaz.tscn",
}
const TODS: PackedStringArray = ["day", "sunset", "night"]
const OPPONENTS: int = 5
const SETTLE_FRAMES: int = 20
const WAIT_MAX_S: float = 30.0
const RACING_SHOT_S: float = 10.0

var _scene: RaceScene
var _go_ms: int = 0
var _go_seen: bool = false


func run() -> void:
	var tracks: PackedStringArray = _list_arg("--tracks=", PackedStringArray(TRACKS.keys()))
	var tods: PackedStringArray = _list_arg("--tods=", TODS)
	var only: String = _arg("--only=")
	if only != "":
		tracks = PackedStringArray([only.get_slice(":", 0)])
		tods = PackedStringArray([only.get_slice(":", 1)])
	tree.auto_accept_quit = false
	for t: String in tracks:
		for tod_id: String in tods:
			await _one(t, tod_id)
			if not is_instance_valid(tree.root):
				return


func _one(track_key: String, tod_id: String) -> void:
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = 1 if "--flow" in OS.get_cmdline_user_args() else 2
	cfg.opponent_count = OPPONENTS
	cfg.track_scene = String(TRACKS[track_key])
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	cfg.time_of_day = tod_id
	_go_seen = false
	_scene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	_scene.config = cfg
	tree.root.add_child(_scene)
	await cap.wait_frames(SETTLE_FRAMES)
	if _scene.dev_track_used or _scene.dev_car_used or _scene.find_child("DevWatermark", true, false) != null:
		cap.fail("%s/%s: dev track, dev mule or DevWatermark present" % [track_key, tod_id])
		_scene.queue_free()
		return
	if "--flow" in OS.get_cmdline_user_args():
		await _flow(track_key, tod_id)
		_scene.queue_free()
		await cap.wait_frames(5)
		return
	_scene.race.race_started.connect(_on_go)
	var waited: float = 0.0
	while not _go_seen and waited < WAIT_MAX_S:
		await cap.wait_seconds(0.1)
		waited += 0.1
	if not _go_seen:
		cap.fail("%s/%s: race never started" % [track_key, tod_id])
		_scene.queue_free()
		return
	var since_go: float = (Time.get_ticks_msec() - _go_ms) / 1000.0
	if since_go < RACING_SHOT_S:
		await cap.wait_seconds(RACING_SHOT_S - since_go)
	var suffix: String = "" if Settings.get_preset_id() == "high" else "_" + Settings.get_preset_id()
	var sun: Light3D = _scene.track.find_child("Sun", true, false) as Light3D
	print("tod_tracks: %s/%s sun=%s shadow=%s" % [track_key, tod_id, str(sun != null), str(sun != null and sun.shadow_enabled)])
	if "--casters" in OS.get_cmdline_user_args():
		_print_casters()
	if "--red" in OS.get_cmdline_user_args():
		_print_reds()
	await cap.shot("%s_%s%s" % [track_key, tod_id, suffix])
	if "--sky" in OS.get_cmdline_user_args():
		await _sky_shot("%s_%s%s_sky" % [track_key, tod_id, suffix])
	_scene.queue_free()
	await cap.wait_frames(5)


## --flow: a one-lap race, then grid intro, results screen and one replay shot, all at this hour (<track>_<tod>_grid,
## _results, _replay). Slow (a whole lap).
func _flow(track_key: String, tod_id: String) -> void:
	var waited: float = 0.0
	while not _scene.camera.intro_active() and waited < 30.0:
		await cap.wait_seconds(0.1)
		waited += 0.1
	while _scene.camera.intro_active() and _scene.camera.intro_progress() < 0.5:
		await cap.wait_frames(1)
	await cap.shot("%s_%s_grid" % [track_key, tod_id])
	waited = 0.0
	while not _scene.results_screen.visible and waited < 300.0:
		await cap.wait_seconds(0.5)
		waited += 0.5
	if not _scene.results_screen.visible:
		cap.fail("%s/%s: results never appeared" % [track_key, tod_id])
		return
	await cap.wait_seconds(1.0)
	await cap.shot("%s_%s_results" % [track_key, tod_id])
	_scene.results_screen._replay_btn.pressed.emit()
	await cap.wait_seconds(6.0)
	await cap.shot("%s_%s_replay" % [track_key, tod_id])


## Diagnostic (--casters): shadow casters of the scene grouped by their top two ancestors under the race scene.
func _print_casters() -> void:
	var groups: Dictionary = {}
	for n: Node in _scene.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n as GeometryInstance3D
		if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or not gi.is_visible_in_tree():
			continue
		var rel: PackedStringArray = String(_scene.get_path_to(gi)).split("/")
		var key: String = "/".join(rel.slice(0, 4 if "Geometry" in rel else 3))
		groups[key] = int(groups.get(key, 0)) + 1
	for k: String in groups:
		print("tod_tracks: casters %s = %d" % [k, groups[k]])


## Diagnostic (--red): what covers screen pixel --px=x,y (default 1870,510): every mesh within 150 m whose projected
## AABB contains it, smallest first, with its materials.
func _print_reds() -> void:
	var px: PackedStringArray = (_arg("--px=") if _arg("--px=") != "" else "1870,510").split(",")
	var target := Vector2(float(px[0]), float(px[1]))
	var cam: Camera3D = _scene.camera
	var vp: Vector2 = Vector2(cam.get_viewport().get_visible_rect().size)
	print("tod_tracks: viewport %s" % str(vp))
	var hits: Array = []
	for nb: Node in _scene.find_children("*newspaper_box*", "MultiMeshInstance3D", true, false):
		var nm: MultiMesh = (nb as MultiMeshInstance3D).multimesh
		for si3: int in nm.mesh.get_surface_count():
			var mm3: StandardMaterial3D = nm.mesh.surface_get_material(si3) as StandardMaterial3D
			if mm3 != null:
				print("tod_tracks: paper %s %s albedo=%s metal=%s rough=%s shading=%s" % [nb.name, mm3.resource_name, str(mm3.albedo_color), str(mm3.metallic), str(mm3.roughness), str(mm3.shading_mode)])
	for n: Node in _scene.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n as GeometryInstance3D
		if not gi.is_visible_in_tree() or "RigidBody3D" in String(_scene.get_path_to(gi)):
			continue
		var box: AABB = gi.get_aabb()
		if gi is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = gi as MultiMeshInstance3D
			if mmi.multimesh == null or mmi.multimesh.mesh == null:
				continue
			var mb: AABB = mmi.multimesh.mesh.get_aabb()
			for k: int in mmi.multimesh.instance_count:
				var ixf: Transform3D = mmi.global_transform * mmi.multimesh.get_instance_transform(k)
				var lo2 := Vector2(1e9, 1e9)
				var hi2 := Vector2(-1e9, -1e9)
				var ok2: bool = true
				for i2: int in 8:
					var w2: Vector3 = ixf * mb.get_endpoint(i2)
					if cam.is_position_behind(w2):
						ok2 = false
						break
					var sp2: Vector2 = cam.unproject_position(w2)
					lo2 = lo2.min(sp2)
					hi2 = hi2.max(sp2)
				if ok2 and target.x >= lo2.x and target.x <= hi2.x and target.y >= lo2.y and target.y <= hi2.y:
					var mats2: PackedStringArray = []
					for si2: int in mmi.multimesh.mesh.get_surface_count():
						var m2: Material = mmi.multimesh.mesh.surface_get_material(si2)
						var sm2: StandardMaterial3D = m2 as StandardMaterial3D
						var tag: String = m2.resource_name if m2 != null else "null"
						if sm2 != null:
							tag += " albedo=%s metal=%s rough=%s emis=%s vc=%s" % [str(sm2.albedo_color), str(sm2.metallic), str(sm2.roughness), str(sm2.emission_enabled), str(sm2.vertex_color_use_as_albedo)]
						mats2.append(tag)
					print("tod_tracks: mmhit area=%.0f %s #%d mats=%s override=%s" % [(hi2.x - lo2.x) * (hi2.y - lo2.y), _scene.get_path_to(mmi), k, str(mats2), str(mmi.material_override)])
			continue
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		var ok: bool = true
		for i: int in 8:
			var w: Vector3 = gi.global_transform * box.get_endpoint(i)
			if cam.is_position_behind(w):
				ok = false
				break
			var sp: Vector2 = cam.unproject_position(w)
			lo = lo.min(sp)
			hi = hi.max(sp)
		if ok and target.x >= lo.x and target.x <= hi.x and target.y >= lo.y and target.y <= hi.y:
			var d: float = (gi.global_transform * box.get_center()).distance_to(cam.global_position)
			hits.append([(hi.x - lo.x) * (hi.y - lo.y), d, gi])
	hits.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for h: Array in hits.slice(0, 8):
		var g: GeometryInstance3D = h[2]
		var mn: PackedStringArray = []
		var mesh: Mesh = (g as MeshInstance3D).mesh if g is MeshInstance3D else null
		if mesh != null:
			for si: int in mesh.get_surface_count():
				var m: Material = (g as MeshInstance3D).get_surface_override_material(si)
				if m == null:
					m = mesh.surface_get_material(si)
				mn.append(m.resource_name if m != null else "null")
		print("tod_tracks: hit area=%.0f dist=%.1f %s mats=%s override=%s size=%s" % [h[0], h[1], _scene.get_path_to(g), str(mn), str(g.material_override), str(g.get_aabb().size)])


## Diagnostic (--sky): a wide camera 4 m above the player, looking along the car and 25 degrees up, so the sky,
## the sun and the skyline show without the HUD.
func _sky_shot(shot_name: String) -> void:
	var cam := Camera3D.new()
	cam.fov = 80.0
	tree.root.add_child(cam)
	var p: Vector3 = _scene.player.global_position
	var fwd: Vector3 = -_scene.player.global_transform.basis.z
	fwd.y = 0.0
	cam.global_position = p + Vector3.UP * 4.0
	cam.look_at(cam.global_position + fwd.normalized() * 10.0 + Vector3.UP * 5.0)
	cam.current = true
	_scene.hud.visible = false
	await cap.wait_frames(3)
	await cap.shot(shot_name)
	cam.queue_free()
	_scene.camera.make_current()
	_scene.hud.visible = true


func _on_go() -> void:
	_go_seen = true
	_go_ms = Time.get_ticks_msec()


func _arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func _list_arg(prefix: String, fallback: PackedStringArray) -> PackedStringArray:
	var v: String = _arg(prefix)
	return PackedStringArray(v.split(",")) if v != "" else fallback
