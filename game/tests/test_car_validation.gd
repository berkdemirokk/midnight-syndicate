extends "res://tests/test_case.gd"
## Car validation (2026-11-28): every shipped catalog car (CarCatalog.DEFAULT_CARS) has a loadable scene with LOD0-2
## and the required nodes, a spec with physical values in range, wheels whose centres sit at their spec radius on the
## ground, rivals fast enough for the final track speed, and at most 20 visible mesh nodes at LOD0.
## Not the render budget: the studio perf JSON counts 39 objects/draw calls per car at LOD0 (over 20), a known FAIL
## recorded in docs/design/CAR_VALIDATION_2026-11-28.md. This test only guards the node count against growth.

const REQUIRED: PackedStringArray = [
	"body", "glass", "trim", "interior", "underbody", "exhaust", "plate_rear", "lights_front", "lights_rear",
	"wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR", "brake_FL", "brake_FR", "brake_RL", "brake_RR", "col_body",
]
const LOD0_NODES_MAX: int = 20
const WHEEL_Y_TOL_M: float = 0.03
const TRACK_MAX_SPEED_KMH: float = 252.0  ## Track.max_speed: a rival slower than this falls off the grid
## Surface ratchet (carmerge, 2026-11-28): LOD0 visible surfaces per car may not grow above what the shipped model has.
## These are the current counts, not the target: the draw-call target (<= 20 per car) needs a material merge that is not done yet.
const LOD0_SURFACES_MAX: Dictionary = {
	"arden_bruiser": 21, "arden_havoc": 22, "atmaca_modified": 23, "bosfor_yildirim": 23, "kestrel_gtr": 23, "kestrel_marten": 22,
	"kestrel_vanta": 23, "noctra_meridian": 23, "noctra_sable": 23, "noctra_tayfun": 23, "noctra_vela": 22,
	"bosfor_kivilcim": 22, "bosfor_serce": 22, "arden_ramjet": 21, "arden_shaker": 21,
	"noctra_volta": 23, "noctra_sovereign": 23, "noctra_titan": 22,
}


func _ids() -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in CarCatalog.DEFAULT_CARS:
		out.append(str(c["id"]))
	return out


func _spawn(id: String) -> Node3D:
	var packed: PackedScene = load(CarCatalog.scene_path(id)) as PackedScene
	check(packed != null, "%s: scene does not load (%s)" % [id, CarCatalog.scene_path(id)])
	if packed == null:
		return null
	return add(packed.instantiate()) as Node3D


func _visible_objects(root: Node) -> int:
	var n: int = 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.name != "col_body" and mi.visible and mi.mesh != null:
			n += 1
	return n


func _visible_surfaces(root: Node) -> int:
	var n: int = 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.name != "col_body" and mi.visible and mi.mesh != null:
			n += mi.mesh.get_surface_count()
	return n


func test_every_car_has_scene_lods_and_nodes() -> void:
	for id: String in _ids():
		var car: Node3D = _spawn(id)
		if car == null:
			continue
		await frames(1)
		for lod_name: String in ["LOD0", "LOD1", "LOD2"]:
			check(car.get_node_or_null(lod_name) != null, "%s: %s missing" % [id, lod_name])
		var lod0: Node = car.get_node_or_null("LOD0")
		if lod0 != null:
			for nm: String in REQUIRED:
				check(lod0.find_child(nm, true, false) != null, "%s: LOD0 has no node %s" % [id, nm])
		await cleanup([car])


func test_every_car_spec_is_physical() -> void:
	for id: String in _ids():
		var spec: CarSpec = load(CarCatalog.spec_path(id)) as CarSpec
		check(spec != null, "%s: spec does not load as CarSpec" % id)
		if spec == null:
			continue
		check(not spec.display_name.strip_edges().is_empty(), "%s: display_name empty" % id)
		check_range(spec.mass_kg, 600.0, 3000.0, "%s mass_kg" % id)
		check_range(spec.wheel_radius_front, 0.2, 0.45, "%s wheel_radius_front" % id)
		check_range(spec.wheel_radius_rear, 0.2, 0.45, "%s wheel_radius_rear" % id)
		check_range(spec.track_front, 1.2, 2.2, "%s track_front" % id)
		check_range(spec.track_rear, 1.2, 2.2, "%s track_rear" % id)
		check_range(spec.wheelbase, 2.0, 3.2, "%s wheelbase" % id)
		check_range(spec.body_size.x, 1.4, 2.3, "%s body_size.x" % id)
		check(spec.top_speed_kmh > 0.0 and spec.engine_force > 0.0, "%s: no top speed or engine force" % id)
		check(spec.brake_force > 0.0 and spec.grip_front > 0.0 and spec.grip_rear > 0.0, "%s: brake or grip missing" % id)
		if CarCatalog.info(id).get("rival", false):
			check(spec.top_speed_kmh >= TRACK_MAX_SPEED_KMH, "%s: rival top speed %.0f below track %.0f km/h" % [id, spec.top_speed_kmh, TRACK_MAX_SPEED_KMH])


func test_every_car_wheels_sit_on_the_ground() -> void:
	for id: String in _ids():
		var car: Node3D = _spawn(id)
		if car == null:
			continue
		await frames(1)
		var spec: CarSpec = load(CarCatalog.spec_path(id)) as CarSpec
		var lod0: Node3D = car.get_node_or_null("LOD0") as Node3D
		if spec == null or lod0 == null:
			await cleanup([car])
			continue
		for nm: String in ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]:
			var w: Node3D = lod0.find_child(nm, true, false) as Node3D
			if w == null:
				check(false, "%s: %s missing" % [id, nm])
				continue
			var radius: float = spec.wheel_radius_front if nm.ends_with("FL") or nm.ends_with("FR") else spec.wheel_radius_rear
			var y: float = w.global_position.y - car.global_position.y
			check(absf(y - radius) <= WHEEL_Y_TOL_M, "%s: %s centre %.3f m, spec radius %.3f m" % [id, nm, y, radius])
		await cleanup([car])


func test_every_car_lod0_nodes_and_surfaces_within_limits() -> void:
	for id: String in _ids():
		var car: Node3D = _spawn(id)
		if car == null:
			continue
		await frames(1)
		var lod0: Node = car.get_node_or_null("LOD0")
		if lod0 != null:
			var n: int = _visible_objects(lod0)
			var surfaces: int = _visible_surfaces(lod0)
			metric("%s_lod0_objects" % id, n)
			metric("%s_lod0_surfaces" % id, surfaces)
			check(n <= LOD0_NODES_MAX, "%s: LOD0 has %d visible mesh nodes, limit %d" % [id, n, LOD0_NODES_MAX])
			check(surfaces <= int(LOD0_SURFACES_MAX.get(id, 0)), "%s: LOD0 has %d visible surfaces, ratchet %d" % [id, surfaces, int(LOD0_SURFACES_MAX.get(id, 0))])
		await cleanup([car])
