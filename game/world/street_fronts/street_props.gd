class_name StreetProps
extends Node3D
## Street life in front of the photo rows (PhotoFronts) on every track: cafe tables outside some shops, planters by
## the doors, and kerb-side bins, hydrants, utility boxes, crates and bags. The props are CC0 Poly Haven models
## (game/assets/world/props_cc0/, processed by assets_src/third_party/process_polyhaven_props.py; ASSET_MANIFEST.json).
## Placement is seeded per shop, so a street always looks the same, and every prop keeps clear of the race corridor.
## Drawn as MultiMeshes in CELL_M cells out to LOD1_END_M (the meshes carry Godot's automatic LODs), nothing beyond.

const DIR: String = "res://assets/world/props_cc0/"
const KERB_M: float = 7.0  ## the kerbs are 7 m from the centre line (StreetFronts)
const CLEAR_M: float = 7.6  ## props stay this far from the centre line
const CELL_M: float = 70.0
const LOD0_END_M: float = 45.0
const LOD1_END_M: float = 120.0
const FADE_M: float = 6.0
## Per track flavour: share of shops with tables outside, planters, and the kerb-side props that fit the district.
const FLAVOUR: Dictionary = {
	"istanbul_bogaz": {"cafe": 0.35, "planter": 0.45, "kerb": ["trash_can", "fire_hydrant", "potted_plant", "utility_box"]},
	"istanbul_maslak": {"cafe": 0.12, "planter": 0.55, "kerb": ["trash_can", "utility_box_b", "fire_hydrant", "street_seating"]},
	"city_01": {"cafe": 0.25, "planter": 0.25, "kerb": ["trash_can", "wooden_crate", "plastic_crate", "trash_bag", "utility_box", "fire_hydrant"]},
}

var placed: Dictionary = {}  ## prop name -> instance count (tests, metrics)
var _cells: Dictionary = {}  ## Vector2i cell -> {prop name -> Array[Transform3D]}


## shops: Array of {"xf": Transform3D (house space: street face at z 0 facing -Z), "w": width in metres}.
func setup(track: Track, shops: Array, low_preset: bool = false) -> void:
	var flavour: Dictionary = {}
	for key: String in FLAVOUR:
		if track.scene_file_path.contains(key):
			flavour = FLAVOUR[key]
	if flavour.is_empty() or shops.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	for i: int in shops.size():
		var shop: Dictionary = shops[i]
		var xf: Transform3D = shop["xf"]
		var w: float = float(shop["w"])
		rng.seed = hash(Vector3i(roundi(xf.origin.x * 4.0), roundi(xf.origin.y * 4.0), roundi(xf.origin.z * 4.0)))
		var lat: float = absf(track.get_lateral_offset(xf.origin))
		var pavement: float = lat - KERB_M
		if pavement < 1.2:
			continue
		var r: float = rng.randf()
		if pavement >= 3.0 and r < float(flavour["cafe"]) and w >= 3.5:
			var n: int = 1 if w < 6.0 else 2
			for k: int in n:
				var x: float = lerpf(-w * 0.3, w * 0.3, (float(k) + 0.5) / float(n)) + rng.randf_range(-0.3, 0.3)
				_put(track, "cafe_set", xf, Vector3(x, 0.0, -1.5), rng.randf_range(-0.3, 0.3))
		elif r < float(flavour["cafe"]) + float(flavour["planter"]):
			var kind: String = "planter_box" if rng.randf() < 0.6 else "planter_box_b"
			for s: float in [1.0, -1.0]:
				_put(track, kind, xf, Vector3(s * (w / 2.0 - 0.7), 0.0, -0.45), PI / 2.0)
		if rng.randf() < 0.45:  # kerb side: one district prop, its back to the road
			var kerb: Array = flavour["kerb"]
			var kname: String = kerb[rng.randi() % kerb.size()]
			_put(track, kname, xf, Vector3(rng.randf_range(-w * 0.35, w * 0.35), 0.0, -(pavement - 0.55)), rng.randf_range(-0.2, 0.2))
	_build(low_preset)


func _put(track: Track, prop: String, xf: Transform3D, local: Vector3, yaw: float) -> void:
	if not ResourceLoader.exists(DIR + prop + ".glb"):
		return
	var at: Vector3 = xf * local
	if absf(track.get_lateral_offset(at)) < CLEAR_M:
		return
	var basis := Basis(Vector3.UP, atan2(-xf.basis.z.x, -xf.basis.z.z) + yaw)
	var cell := Vector2i(floori(at.x / CELL_M), floori(at.z / CELL_M))
	if not _cells.has(cell):
		_cells[cell] = {}
	var by: Dictionary = _cells[cell]
	if not by.has(prop):
		by[prop] = []
	(by[prop] as Array).append(Transform3D(basis, at))
	placed[prop] = int(placed.get(prop, 0)) + 1


func _build(low_preset: bool) -> void:
	var meshes: Dictionary = {}
	for cell: Vector2i in _cells:
		var by: Dictionary = _cells[cell]
		for prop: String in by:
			for lod: int in [0]:  # the GLB mesh carries its own automatic LODs (Godot import)
				var key: String = prop
				if not meshes.has(key):
					meshes[key] = _mesh_of(DIR + key + ".glb")
				var mesh: Mesh = meshes[key]
				if mesh == null:
					continue
				var xfs: Array = by[prop]
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = mesh
				mm.instance_count = xfs.size()
				for j: int in xfs.size():
					mm.set_instance_transform(j, xfs[j])
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "%s_%d_%d" % [key, cell.x, cell.y]
				mmi.multimesh = mm
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if low_preset else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				mmi.visibility_range_begin = 0.0 if (lod == 0 or low_preset) else LOD0_END_M
				mmi.visibility_range_begin_margin = 0.0 if (lod == 0 or low_preset) else FADE_M
				mmi.visibility_range_end = LOD1_END_M
				mmi.visibility_range_end_margin = FADE_M
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				add_child(mmi)


static func _mesh_of(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var root: Node = (load(path) as PackedScene).instantiate()
	var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
	root.free()
	return mesh
