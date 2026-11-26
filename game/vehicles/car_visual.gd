class_name CarVisual
extends Node3D
## Cosmetic driver of a car model. Lives under the ArcadeCar and only reads its state.
## Wheels and brakes are placed in car space from ArcadeCar, so the model follows physics without
## touching the car. Physics values are stored per tick and interpolated per frame with the physics fraction.

const WHEEL_NAMES: PackedStringArray = ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]
const BRAKE_NAMES: PackedStringArray = ["brake_FL", "brake_FR", "brake_RL", "brake_RR"]
const MAT_PAINT: String = "M_Paint"
const MAT_LIGHT_REAR: String = "M_LightRear"
const WHEEL_COUNT: int = 4
const FRONT_COUNT: int = 2
const MIN_DT: float = 0.0001  ## divisor floor for the acceleration estimate, not a tunable
const STATIC_SAG_M: float = 0.05  ## the car's own weight compresses the springs about this much (measured 0.046-0.058)

@export var tilt_max_rad: float = 0.03  ## body pitch and roll clamp
@export var tilt_per_accel: float = 0.0025  ## rad per m/s^2 of acceleration
@export var tilt_per_compression: float = 0.12  ## rad per unit of suspension compression difference
@export var tilt_smooth_hz: float = 6.0  ## 1/s, how fast the body follows the target tilt
@export var light_rest: float = 0.6  ## rear light emission multiplier at rest
@export var light_brake: float = 4.0  ## rear light emission multiplier while braking
@export var light_smooth_hz: float = 12.0
@export var brake_input_min: float = 0.05  ## brake input below this does not light the rear lamps

var _car: ArcadeCar = null
var _model: Node3D = null
var _tilt_node: Node3D = null  ## the node that carries the body tilt (the Visual under the car)
var _tilt_rest: Transform3D = Transform3D.IDENTITY
var _wheels: Array[Node3D] = []
var _brakes: Array[Node3D] = []
var _wheel_rest: Array[Basis] = []
var _brake_rest: Array[Basis] = []
var _prev_pos: Array[Vector3] = []
var _curr_pos: Array[Vector3] = []
var _prev_spin: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _curr_spin: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _prev_steer: float = 0.0
var _curr_steer: float = 0.0
var _prev_vel: Vector3 = Vector3.ZERO
var _accel_local: Vector3 = Vector3.ZERO  ## m/s^2 in car space, x right, z backward
var _compression: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _pitch: float = 0.0
var _roll: float = 0.0
var _light_now: float = 0.0
var _paint_mats: Array[StandardMaterial3D] = []
var _light_mats: Array[StandardMaterial3D] = []
var _warned: bool = false


func _init() -> void:
	process_physics_priority = 1  ## after the car (priority 0) has stepped this tick


## Binds to a car and its model. The model must be a descendant of the car. Call once, after the car is built.
func setup(car: ArcadeCar, model: Node3D) -> void:
	_car = car
	_model = model
	_tilt_node = model.get_parent() as Node3D
	if _tilt_node == null or _tilt_node == car:
		_tilt_node = model
	_tilt_rest = _tilt_node.transform
	for i: int in WHEEL_COUNT:
		var w: Node3D = _find(WHEEL_NAMES[i])
		var b: Node3D = _find(BRAKE_NAMES[i])
		_wheels.append(w)
		_brakes.append(b)
		_wheel_rest.append(_chain(w).basis if w != null else Basis.IDENTITY)
		_brake_rest.append(_chain(b).basis if b != null else Basis.IDENTITY)
		var p: Vector3 = _car.get_wheel_local_position(i)
		_prev_pos.append(p)
		_curr_pos.append(p)
		_compression[i] = _car.wheel_compression[i]
		_prev_spin[i] = _car.wheel_spin_rad[i]
		_curr_spin[i] = _car.wheel_spin_rad[i]
	_prev_steer = _car.steer_angle_rad
	_curr_steer = _car.steer_angle_rad
	_prev_vel = _car.linear_velocity
	_seat_model_on_suspension()
	_collect_materials(model)


## The model's wheels rest where its author put them (Noctra: wheel centres 0.49 m above where the suspension holds
## them), so the body floated over wheels pulled down to the physics position, and LOD1/LOD2 cars hovered. Lower the
## whole model so its resting wheel centres sit at the physics rest height (mount - rest length + radius + static sag).
func _seat_model_on_suspension() -> void:
	if _car.spec == null:
		return
	var model_y: float = 0.0
	var phys_y: float = 0.0
	var n: int = 0
	for i: int in WHEEL_COUNT:
		if _wheels[i] == null:
			continue
		var radius: float = _car.spec.wheel_radius_front if i < FRONT_COUNT else _car.spec.wheel_radius_rear
		model_y += _chain(_wheels[i]).origin.y
		phys_y += _car.spec.mount_height - _car.spec.suspension_rest + radius + STATIC_SAG_M
		n += 1
	if n == 0:
		return
	_tilt_rest.origin.y += (phys_y - model_y) / float(n)
	_tilt_node.transform = _tilt_rest


## Sets the albedo of every M_Paint material. Materials were duplicated in setup, so cars never share them.
func set_paint(colour: Color) -> void:
	for m: StandardMaterial3D in _paint_mats:
		m.albedo_color = colour


## Car-space origin of a wheel node, read from the scene tree (not from the cached target).
func wheel_car_origin(index: int) -> Vector3:
	if not has_wheel(index):
		return Vector3.ZERO
	return _chain(_wheels[index]).origin


func has_wheel(index: int) -> bool:
	return index >= 0 and index < _wheels.size() and _wheels[index] != null


func _physics_process(delta: float) -> void:
	if _car == null:
		return
	for i: int in WHEEL_COUNT:
		_prev_pos[i] = _curr_pos[i]
		_curr_pos[i] = _car.get_wheel_local_position(i)
		_prev_spin[i] = _curr_spin[i]
		_curr_spin[i] = _car.wheel_spin_rad[i]
		_compression[i] = _car.wheel_compression[i]
	_prev_steer = _curr_steer
	_curr_steer = _car.steer_angle_rad
	var v: Vector3 = _car.linear_velocity
	var a: Vector3 = (v - _prev_vel) / maxf(delta, MIN_DT)
	_prev_vel = v
	_accel_local = _car.global_basis.transposed() * a


func _process(delta: float) -> void:
	if _car == null:
		return
	var f: float = Engine.get_physics_interpolation_fraction()
	_update_tilt(delta)
	_place_wheels(f)
	_update_lights(delta)


func _update_tilt(delta: float) -> void:
	var ax: float = -_accel_local.z * tilt_per_accel  # braking (negative forward accel) dips the nose
	var ay: float = -_accel_local.x * tilt_per_accel  # the body leans away from the centre of a turn
	var comp_front: float = (_compression[0] + _compression[1]) * 0.5
	var comp_rear: float = (_compression[2] + _compression[3]) * 0.5
	var comp_left: float = (_compression[0] + _compression[2]) * 0.5
	var comp_right: float = (_compression[1] + _compression[3]) * 0.5
	ax += (comp_rear - comp_front) * tilt_per_compression
	ay += (comp_left - comp_right) * tilt_per_compression
	var k: float = 1.0 - exp(-tilt_smooth_hz * delta)
	_pitch = lerpf(_pitch, clampf(ax, -tilt_max_rad, tilt_max_rad), k)
	_roll = lerpf(_roll, clampf(ay, -tilt_max_rad, tilt_max_rad), k)
	if _tilt_node != null:
		_tilt_node.transform = Transform3D(Basis.from_euler(Vector3(_pitch, 0.0, _roll)) * _tilt_rest.basis, _tilt_rest.origin)


func _place_wheels(f: float) -> void:
	var steer: float = lerpf(_prev_steer, _curr_steer, f)
	var steer_basis: Basis = Basis(Vector3.UP, -steer)  ## positive steer = right; a right turn is a negative yaw
	for i: int in WHEEL_COUNT:
		var pos: Vector3 = _prev_pos[i].lerp(_curr_pos[i], f)
		var spin: float = lerpf(_prev_spin[i], _curr_spin[i], f)
		var yaw: Basis = steer_basis if i < FRONT_COUNT else Basis.IDENTITY
		var w: Node3D = _wheels[i]
		if w != null:
			_set_car_pose(w, Transform3D(yaw * _wheel_rest[i] * Basis(Vector3.RIGHT, spin), pos))
		var br: Node3D = _brakes[i]
		if br != null:
			_set_car_pose(br, Transform3D(yaw * _brake_rest[i], pos))


func _update_lights(delta: float) -> void:
	var braking: bool = _car.input != null and _car.input.brake > brake_input_min
	var target: float = light_brake if braking else light_rest
	_light_now = lerpf(_light_now, target, 1.0 - exp(-light_smooth_hz * delta))
	for m: StandardMaterial3D in _light_mats:
		m.emission_energy_multiplier = _light_now


## Writes a car-space pose into a node by converting through its parent chain, which may carry the tilt.
func _set_car_pose(node: Node3D, car_xf: Transform3D) -> void:
	var parent: Node3D = node.get_parent() as Node3D
	var parent_xf: Transform3D = _chain(parent) if parent != null else Transform3D.IDENTITY
	node.transform = parent_xf.affine_inverse() * car_xf


## Transform of node in car space: the product of local transforms from node up to the car, node included.
func _chain(node: Node) -> Transform3D:
	var xf: Transform3D = Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != _car and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _find(node_name: String) -> Node3D:
	var n: Node = _model.find_child(node_name, true, false)
	if n == null:
		if not _warned:
			push_warning("CarVisual: model has no node named %s" % node_name)
		return null
	return n as Node3D


## Gives every M_Paint and M_LightRear surface its own duplicate, so cars built from one scene stay independent.
func _collect_materials(root: Node) -> void:
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		# A mesh-wide override would replace every surface, so move it onto each surface first.
		var base: Material = mi.material_override
		if base != null:
			mi.material_override = null
			for s: int in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, base)
		for s: int in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			if not (mat is StandardMaterial3D):
				continue
			var mat_name: String = mat.resource_name
			if mat_name != MAT_PAINT and mat_name != MAT_LIGHT_REAR:
				continue
			var dup: StandardMaterial3D = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			mi.set_surface_override_material(s, dup)
			if mat_name == MAT_PAINT:
				_paint_mats.append(dup)
			else:
				dup.emission_enabled = true
				_light_mats.append(dup)
