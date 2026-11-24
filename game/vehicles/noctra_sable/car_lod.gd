class_name CarLod
extends Node3D
## Root of the Noctra Sable scene. Holds LOD0, LOD1 and LOD2 models, switches them by distance with visibility
## ranges, hides col_body in every LOD and says which LOD's wheel nodes are the active set (get_wheel_nodes).
## Applies the engine materials to all LODs with one paint per car (CarMaterials.apply).

const LOD_NAMES: PackedStringArray = ["LOD0", "LOD1", "LOD2"]
const COL_NAME: String = "col_body"
const WHEEL_NAMES: PackedStringArray = ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]
const BRAKE_NAMES: PackedStringArray = ["brake_FL", "brake_FR", "brake_RL", "brake_RR"]

@export var lod1_start_m: float = 22.0  ## LOD0 ends and LOD1 starts here (metres from the camera)
@export var lod2_start_m: float = 70.0  ## LOD1 ends and LOD2 starts here
@export var fade_margin_m: float = 2.0  ## dithered fade band at each switch, metres
@export var force_lod0: bool = false  ## player car and garage: LOD0 always, no distance switching
@export var force_lod: int = -1  ## capture and tests: -1 automatic, 0..2 forces that LOD
@export var paint_colour: Color = CarMaterials.DEFAULT_PAINT

var _lods: Array[Node3D] = []
var _active: int = 0


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
		if forced:
			begin = 0.0
			end = 0.0
			margin = 0.0
		for n: Node in lod.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n as MeshInstance3D
			mi.visibility_range_begin = begin
			mi.visibility_range_end = end
			mi.visibility_range_end_margin = margin
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
