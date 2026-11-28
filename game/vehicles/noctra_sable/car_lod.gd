class_name CarLod
extends Node3D
## Root of the Noctra Sable scene. Holds LOD0, LOD1 and LOD2 models, switches them by distance with visibility
## ranges, hides col_body in every LOD and says which LOD's wheel nodes are the active set (get_wheel_nodes).
## Applies the engine materials to all LODs with one paint per car (CarMaterials.apply).

const LOD_NAMES: PackedStringArray = ["LOD0", "LOD1", "LOD2"]
const COL_NAME: String = "col_body"
const WHEEL_NAMES: PackedStringArray = ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]
const BRAKE_NAMES: PackedStringArray = ["brake_FL", "brake_FR", "brake_RL", "brake_RR"]
const DETAIL_LAYER_BIT: int = 1 << 2  ## LOD0 meshes (instead of the default bit 0): the planar mirror leaves them out
const MIRROR_LAYER_BIT: int = 1 << 3  ## mirror-only LOD1 copy: the main, chase and replay cameras leave it out
const MIRROR_LOD_NAME: String = "LOD1Mirror"
const MIRROR_LOD2_NAME: String = "LOD2Mirror"
const MIRROR_LOD2_START_M: float = 10.0  ## the mirror shows the 7k-tri LOD2 copy from here to lod2_start_m: a blurry wet-road reflection does not need LOD1 there

@export var lod1_start_m: float = 22.0  ## LOD0 ends and LOD1 starts here (metres from the camera)
@export var lod2_start_m: float = 70.0  ## LOD1 ends and LOD2 starts here
@export var fade_margin_m: float = 2.0  ## dithered fade band at each switch, metres
@export var force_lod0: bool = false  ## player car and garage: LOD0 always, no distance switching
@export var force_lod: int = -1  ## capture and tests: -1 automatic, 0..2 forces that LOD
@export var paint_colour: Color = CarMaterials.DEFAULT_PAINT

var _lods: Array[Node3D] = []
var _active: int = 0
var _mirror_lod: Node3D = null
var _mirror_lod2: Node3D = null


func _ready() -> void:
	for n: String in LOD_NAMES:
		_lods.append(get_node_or_null(n) as Node3D)
	for lod: Node3D in _lods:
		if lod != null:
			_hide_col_body(lod)
	CarMaterials.apply(self, paint_colour)
	_apply_ranges()


func _process(_delta: float) -> void:
	_active = lod_for_distance(_distance_to_camera())
	if _forced_index() >= 0:
		_active = _forced_index()


## Race only: copies of LOD1 and LOD2 (shared meshes and materials) on the mirror-only layer, LOD0 and LOD1 on the
## detail layer. With the mirror camera excluding the detail layer and every other camera excluding the mirror layer,
## the road reflection of a car costs LOD1 up to MIRROR_LOD2_START_M and LOD2 beyond, instead of LOD0/LOD1. Call after _ready().
func build_mirror_lod() -> void:
	if _mirror_lod != null or _lods.size() < 2 or _lods[0] == null or _lods[1] == null:
		return
	_mirror_lod = _make_mirror_copy(_lods[1], MIRROR_LOD_NAME)
	if _lods.size() > 2 and _lods[2] != null:
		_mirror_lod2 = _make_mirror_copy(_lods[2], MIRROR_LOD2_NAME)
	for lod: Node3D in [_lods[0], _lods[1]]:
		for n: Node in lod.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.layers & MIRROR_LAYER_BIT == 0:  # not the copies (a copy of LOD1 sits under the car, not under LOD1)
				mi.layers = (mi.layers & ~1) | DETAIL_LAYER_BIT  # no default bit: a camera that skips the detail layer must not see it
	_apply_ranges()


func _make_mirror_copy(src: Node3D, copy_name: String) -> Node3D:
	var copy: Node3D = src.duplicate() as Node3D
	copy.name = copy_name
	add_child(copy)
	for n: Node in copy.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).layers = MIRROR_LAYER_BIT
	return copy


func get_mirror_lod() -> Node3D:
	return _mirror_lod


## Forces LOD index (-1 back to distance switching) after the car is in the tree.
func set_forced(index: int) -> void:
	force_lod = index
	if is_node_ready():
		_apply_ranges()


## LOD index a camera at this distance (metres) sees. Matches the visibility ranges written by _apply_ranges.
func lod_for_distance(d: float) -> int:
	if force_lod0:
		return 0
	if force_lod >= 0:
		return clampi(force_lod, 0, 2)
	if d < lod1_start_m:
		return 0
	if d < lod2_start_m:
		return 1
	return 2


## The LOD the distance rule or force picks this frame (updated each process frame).
func get_active_lod() -> int:
	return _active


## Wheel nodes (wheel_FL, wheel_FR, wheel_RL, wheel_RR) of the active LOD. CarVisual drives this set only.
func get_wheel_nodes() -> Array[Node3D]:
	return _nodes_of(_lod_root(_active), WHEEL_NAMES)


## Brake disc and caliper nodes of the active LOD (LOD2 has none, so the result is empty there).
func get_brake_nodes() -> Array[Node3D]:
	return _nodes_of(_lod_root(_active), BRAKE_NAMES)


func _forced_index() -> int:
	if force_lod0:
		return 0
	return force_lod if force_lod >= 0 else -1


## Distance ranges per LOD (0 = no limit). A forced LOD is the only one drawn and has no range at all.
func _apply_ranges() -> void:
	var f: int = _forced_index()
	for i: int in _lods.size():
		var lod: Node3D = _lods[i]
		if lod == null:
			continue
		var forced: bool = f >= 0
		lod.visible = not forced or i == f
		var begin: float = 0.0 if i == 0 else (lod1_start_m if i == 1 else lod2_start_m)
		var end: float = lod1_start_m if i == 0 else (lod2_start_m if i == 1 else 0.0)
		var margin: float = fade_margin_m if i < 2 else 0.0
		var begin_margin: float = fade_margin_m if i > 0 else 0.0  ## the next LOD fades in over the band the last one fades out
		if forced:
			begin = 0.0
			end = 0.0
			margin = 0.0
			begin_margin = 0.0
		for n: Node in lod.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n as MeshInstance3D
			mi.visibility_range_begin = begin
			mi.visibility_range_begin_margin = begin_margin
			mi.visibility_range_end = end
			mi.visibility_range_end_margin = margin
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_apply_mirror_ranges(f)


## Mirror view of a car (LOD1 is on the detail layer, so the mirror sees only these copies and the regular LOD2):
## LOD1 copy from 0 to the split, LOD2 copy from the split to lod2_start_m. LOD0 or LOD1 forced: the LOD1 copy with
## no range stands in; LOD2 forced: the regular LOD2 is seen by the mirror and the copies are hidden. Hard switches: no fade in a mirror.
func _apply_mirror_ranges(forced: int) -> void:
	if _mirror_lod == null:
		return
	var split: float = minf(MIRROR_LOD2_START_M, lod1_start_m)
	_set_mirror_range(_mirror_lod, forced <= 1, 0.0, split if forced < 0 and _mirror_lod2 != null else (lod2_start_m if forced < 0 else 0.0))
	if _mirror_lod2 != null:
		_set_mirror_range(_mirror_lod2, forced < 0, split, lod2_start_m)


func _set_mirror_range(root: Node3D, shown: bool, begin: float, end: float) -> void:
	root.visible = shown
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		mi.visibility_range_begin = begin
		mi.visibility_range_begin_margin = 0.0
		mi.visibility_range_end = end
		mi.visibility_range_end_margin = 0.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _distance_to_camera() -> float:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	return cam.global_position.distance_to(global_position)


func _lod_root(i: int) -> Node3D:
	if i < 0 or i >= _lods.size():
		return null
	return _lods[i]


func _nodes_of(root: Node3D, names: PackedStringArray) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if root == null:
		return out
	for nm: String in names:
		var n: Node = root.find_child(nm, true, false)
		if n is Node3D:
			out.append(n as Node3D)
	return out


func _hide_col_body(lod: Node3D) -> void:
	for n: Node in lod.find_children(COL_NAME, "", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi != null:
			mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
