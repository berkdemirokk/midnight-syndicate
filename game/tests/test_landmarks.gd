extends "res://tests/test_case.gd"
## Waterfront landmark (Landmarks): kit budgets and surfaces, placement on the sea side of the Bogaz track and clear of
## the layout's props and buildings, the collider, the two lights and the night look.

const TRACK: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const LAYOUT: String = "res://assets/world/istanbul_bogaz/istanbul_bogaz_layout.json"
const DIR: String = "res://assets/world/kits/landmarks/"
const LOD_MAX_TRIS: Array = [22000, 6000, 600]
const LOD_FILES: PackedStringArray = ["landmark_mosque_lod0.glb", "landmark_mosque_lod1.glb", "landmark_mosque_lod2.glb"]
const SURFACES: PackedStringArray = ["M_Stone", "M_Dome", "M_Glass", "M_Lamp", "M_Iron", "M_Paving"]
const MAX_MATERIALS: int = 6
## Quay in landmark-local metres (Godot: +Z landward, -Z seaward), from the kit build
const QUAY_HALF_X: float = 40.0
const QUAY_SEA_Z: float = -32.0
const CLEAR_LAT_M: float = -11.5  ## quay edge must stay this far seaward: the road bends about 1.5 m over the 80 m quay, the kerb is at -7


func _tris(mesh: Mesh) -> int:
	var total: int = 0
	for i: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += (idx.size() if not idx.is_empty() else verts.size()) / 3
	return total


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


func _populate() -> Array:
	var track: Track = (load(TRACK) as PackedScene).instantiate() as Track
	add(track)
	await frames(2)
	var lm := Landmarks.new()
	track.add_child(lm)
	lm.setup(track)
	await frames(2)
	return [track, lm]


func test_kit_budgets_and_surfaces() -> void:
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "landmark_mosque_report.json"))
	check(report is Dictionary, "kit report missing")
	for lod: int in 3:
		var path: String = DIR + LOD_FILES[lod]
		check(ResourceLoader.exists(path), "missing GLB " + path)
		var scene: PackedScene = load(path) as PackedScene
		check(scene != null, "GLB does not load " + path)
		if scene == null:
			continue
		var root: Node = scene.instantiate()
		var tris: int = 0
		var names: Dictionary = {}
		for mi: MeshInstance3D in _meshes(root):
			tris += _tris(mi.mesh)
			for i: int in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(i)
				names[m.resource_name if m != null else ""] = true
		root.free()
		metric("landmark_lod%d_tris" % lod, tris)
		check(tris <= int(LOD_MAX_TRIS[lod]), "LOD%d %d tris > %d" % [lod, tris, LOD_MAX_TRIS[lod]])
		check(names.size() <= MAX_MATERIALS, "LOD%d uses %d materials" % [lod, names.size()])
		for k: Variant in names.keys():
			check(SURFACES.has(String(k)), "LOD%d unknown surface material '%s'" % [lod, k])


func test_lod_vertex_colours_are_baked_ao() -> void:
	## LOD0 and LOD1 carry the baked ambient occlusion as vertex colours, and not all of it is white
	for lod: int in 2:
		var scene: PackedScene = load(DIR + LOD_FILES[lod]) as PackedScene
		check(scene != null, "GLB does not load " + LOD_FILES[lod])
		if scene == null:
			continue
		var root: Node = scene.instantiate()
		var coloured: int = 0
		var dark: int = 0
		for mi: MeshInstance3D in _meshes(root):
			if mi.mesh == null:
				continue
			for i: int in mi.mesh.get_surface_count():
				var cols: Variant = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
				if cols == null:
					continue
				coloured += 1
				for c: Color in cols:
					if c.r < 0.99:
						dark += 1
						break
		root.free()
		check(coloured > 0, "LOD%d has no vertex colours (baked AO missing)" % lod)
		check(dark > 0, "LOD%d vertex colours are all white" % lod)


func test_sea_side_and_clear_of_layout() -> void:
	var pair: Array = await _populate()
	var track: Track = pair[0]
	var lm: Landmarks = pair[1]
	var origin_lat: float = track.get_lateral_offset(lm.global_transform.origin)
	metric("landmark_origin_lateral_m", snappedf(origin_lat, 0.01))
	check(absf(origin_lat - Landmarks.EDGE_LAT_M) < 0.25, "quay edge not on the railing line: lateral %.2f" % origin_lat)
	check(origin_lat < 0.0, "landmark must be on the sea side (negative lateral)")
	for corner: Vector3 in [Vector3(-QUAY_HALF_X, 0.15, 0.0), Vector3(QUAY_HALF_X, 0.15, 0.0),
			Vector3(-QUAY_HALF_X, 0.15, QUAY_SEA_Z), Vector3(QUAY_HALF_X, 0.15, QUAY_SEA_Z)]:
		var lat: float = track.get_lateral_offset(lm.to_global(corner))
		check(lat <= CLEAR_LAT_M, "quay corner %s at lateral %.2f reaches the road" % [str(corner), lat])
	check(track.get_lateral_offset(lm.hall_centre()) < -20.0, "prayer hall must stand clear of the quay edge")
	# No layout prop or building may stand on the quay or in the hall footprint (seaward of the railing).
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	check(layout is Dictionary, "layout JSON missing")
	if layout is Dictionary:
		var inv: Transform3D = lm.global_transform.affine_inverse()
		var hits: int = 0
		for inst: Variant in (layout as Dictionary)["instances"]:
			var d: Dictionary = inst
			var p: Array = d["position"]
			var local: Vector3 = inv * Vector3(float(p[0]), float(p[1]), float(p[2]))
			if absf(local.x) <= QUAY_HALF_X + 2.0 and local.z <= -0.8 and local.z >= QUAY_SEA_Z - 2.0:
				hits += 1
		metric("layout_instances_in_footprint", hits)
		check(hits == 0, "%d layout instances inside the landmark footprint" % hits)
	await cleanup([track])


func test_collider_is_two_boxes_and_never_blocks_the_road() -> void:
	var pair: Array = await _populate()
	var track: Track = pair[0]
	var lm: Landmarks = pair[1]
	var body: StaticBody3D = lm.get_node("Collider") as StaticBody3D
	check(body != null, "no collider body")
	if body != null:
		check(body.collision_layer == 1 and body.collision_mask == 0, "collider layer/mask must be world layer 1, mask 0")
		var boxes: int = 0
		for c: Node in body.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				boxes += 1
		check(boxes == 2, "collider needs 2 box shapes, has %d" % boxes)
	await cleanup([track])


func test_night_look_and_two_lights() -> void:
	var pair: Array = await _populate()
	var track: Track = pair[0]
	var lm: Landmarks = pair[1]
	var lights: Array[OmniLight3D] = []
	for n: Node in lm.find_children("*", "OmniLight3D", true, false):
		lights.append(n as OmniLight3D)
	check(lights.size() == 2, "landmark needs exactly 2 OmniLights, has %d" % lights.size())
	var shader_surfaces: int = 0
	var plain_surfaces: int = 0
	for mi: MeshInstance3D in _meshes(lm):
		for i: int in mi.mesh.get_surface_count():
			var o: Material = mi.get_surface_override_material(i)
			if o is ShaderMaterial:
				shader_surfaces += 1
			else:
				plain_surfaces += 1
	check(plain_surfaces == 0 and shader_surfaces > 0, "every landmark surface needs the landmark shader")
	lm.set_night(1.0)
	for l: OmniLight3D in lights:
		check(l.visible and l.light_energy > 0.0, "%s must light at night" % l.name)
	check(_night_param(lm) == 1.0, "night uniform not 1 at night")
	lm.set_night(0.0)
	for l: OmniLight3D in lights:
		check(not l.visible, "%s must be off by day" % l.name)
	check(_night_param(lm) == 0.0, "night uniform not 0 by day")
	await cleanup([track])


func _night_param(lm: Landmarks) -> float:
	for mi: MeshInstance3D in _meshes(lm):
		if mi.mesh.get_surface_count() > 0:
			var m: ShaderMaterial = mi.get_surface_override_material(0) as ShaderMaterial
			if m != null:
				return float(m.get_shader_parameter("night"))
	return -1.0


func test_mirror_layers() -> void:
	## LOD0 is left out of the wet-road mirror; the LOD1 near range has a mirror-only copy (no shadows, 0 to LOD0 end)
	var pair: Array = await _populate()
	var track: Track = pair[0]
	var lm: Landmarks = pair[1]
	var lod0_end: float = float(Landmarks.LOD_RANGES[0][1])
	var lod1_mains: int = 0
	var mirror_copies: int = 0
	for mi: MeshInstance3D in _meshes(lm):
		if mi.visibility_range_begin == 0.0:
			check((mi.layers & 1) == 0, "near landmark mesh still on the default layer, the mirror draws it")
		if mi.layers == Landmarks.MIRROR_ONLY_BIT:
			mirror_copies += 1
			check(mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "mirror-only copy casts shadows")
			check(is_equal_approx(mi.visibility_range_end, lod0_end), "mirror-only copy range end is not the LOD0 end")
		elif mi.visibility_range_begin == float(Landmarks.LOD_RANGES[1][0]):
			lod1_mains += 1
	metric("landmark_mirror_copies", mirror_copies)
	check(mirror_copies > 0 and mirror_copies == lod1_mains, "one mirror-only copy per LOD1 mesh (%d vs %d)" % [mirror_copies, lod1_mains])
	# the copy's bit is not a car light bit, is in the mirror's cull mask and is kept out of the current camera
	check(Landmarks.MIRROR_ONLY_BIT & RaceScene.CAR_LIGHT_MASK == 0, "landmark mirror copy is lit by the car fill and rim lights")
	check(Landmarks.MIRROR_ONLY_BIT & PlanarReflection.new().excluded_layers == 0, "planar mirror leaves the landmark copy out")
	var cam := Camera3D.new()
	track.add_child(cam)
	cam.make_current()
	await frames(2)
	check(cam.cull_mask & Landmarks.MIRROR_ONLY_BIT == 0, "current camera still draws the landmark mirror copy")
	await cleanup([track])
