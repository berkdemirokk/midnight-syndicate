class_name TrafficCar
extends RigidBody3D
## One civilian car: a velocity-driven RigidBody3D (no gravity, upright, height follows the road). TrafficSystem
## decides the wanted speed and lane; drive() steers to it. A race car that hits it pushes it for HIT_FREE_S
## (the driving controller is off), then it eases back to its lane. Forward is -Z, the Arden Civic is modelled
## nose +Z so its visual is turned 180 degrees.

const BODY_LAYER: int = 2  ## vehicles, the layer the race cars collide with
const BODY_MASK: int = 3  ## world 1 + vehicles 2
const MIRROR_SKIP_BIT: int = 1 << 4  ## small props and parked cars use this instead of bit 0: left out of the wet-road mirror
const LOD_END_M: Array[float] = [30.0, 80.0, 170.0]
const LOD_FADE_M: float = 4.0
const MASS_KG: float = 1200.0
const BODY_SIZE: Vector3 = Vector3(1.8, 1.25, 4.5)
const BODY_LIFT_M: float = 0.2  ## collider bottom above the road
const HIT_MIN_SPEED: float = 4.0  ## m/s relative speed of a race car contact that counts as a hit
const HIT_FREE_S: float = 2.5
const LOOK_MIN_M: float = 6.0
const LOOK_MAX_M: float = 28.0
const ACCEL: float = 3.0  ## m/s^2
const BRAKE: float = 7.0
const VEL_BLEND: float = 14.0  ## m/s^2 that the velocity is pulled to the wanted one
const YAW_GAIN: float = 3.0
const YAW_MAX: float = 1.1  ## rad/s
const Y_GAIN: float = 14.0
const Y_MAX: float = 12.0
const BRAKE_ON_DECEL: float = 0.8  ## m/s below the current speed that lights the brake lamps
const TAIL_IDLE: float = 0.7
const TAIL_BRAKE: float = 3.0
const HEAD_ON: float = 3.0
const HEAD_OFF: float = 0.05
const LOST_LAT_M: float = 7.0  ## farther than this from its lane: lost, the system respawns it

var dir: int = 1  ## +1 drives with the race direction, -1 against it
var lat: float = 0.0  ## lane centre, m right of the racing line (race direction)
var s: float = 0.0  ## progress along the line
var cruise: float = 12.0  ## m/s
var speed: float = 0.0  ## m/s along the heading
var hit_t: float = 0.0
var hits: int = 0
var braking: bool = false
var placed: bool = false  ## false until the first place()
var lane_err: float = 0.0  ## m from the lane target at the last drive()
var hit_cb: Callable = Callable()  ## called with (car) on a hit, for tests and FX

var _tail: StandardMaterial3D = null
var _head: StandardMaterial3D = null
var _road_y: float = 0.0
var _lift: float = 0.0
var _v_prev: Vector3 = Vector3.ZERO


func _init() -> void:
	gravity_scale = 0.0
	can_sleep = false
	mass = MASS_KG
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	collision_layer = BODY_LAYER
	collision_mask = BODY_MASK
	freeze = true
	visible = false
	contact_monitor = true
	max_contacts_reported = 4
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.3
	physics_material_override.bounce = 0.0


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BODY_SIZE
	cs.shape = box
	cs.position = Vector3(0.0, BODY_LIFT_M + BODY_SIZE.y * 0.5, 0.0)
	add_child(cs)
	body_entered.connect(_on_body_entered)


## Builds the three LODs under a turned Visual node. paint_slot picks the colour.
func build_visual(paint_slot: int) -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.basis = Basis(Vector3.UP, PI)
	add_child(visual)
	_tail = StandardMaterial3D.new()
	_tail.albedo_color = Color(0.25, 0.01, 0.01)
	_tail.emission_enabled = true
	_tail.emission = Color(1.0, 0.0, 0.0)
	_head = StandardMaterial3D.new()
	_head.albedo_color = Color(0.9, 0.95, 1.0)
	_head.emission_enabled = true
	_head.emission = Color(0.85, 0.93, 1.0)
	var first_lod: int = 1 if Settings.get_preset_id() == "low" else 0  # Low: no LOD0 (draw budget 250)
	for i: int in range(first_lod, TrafficModels.LOD_COUNT):
		var m: Dictionary = TrafficModels.lod(i)
		var box: AABB = m["aabb"]
		_lift = maxf(_lift, -box.position.y)
		var holder := Node3D.new()
		holder.name = "Lod%d" % i
		holder.position.y = -box.position.y
		visual.add_child(holder)
		for key: String in ["body", "paint", "head", "tail"]:
			var mi := MeshInstance3D.new()
			mi.name = key
			mi.mesh = m[key] as Mesh
			mi.layers = MIRROR_SKIP_BIT
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if key == "paint":
				mi.material_override = TrafficModels.paint_material(paint_slot)
			elif key == "head":
				mi.material_override = _head
			elif key == "tail":
				mi.material_override = _tail
			mi.visibility_range_begin = 0.0 if i == first_lod else LOD_END_M[i - 1]
			mi.visibility_range_begin_margin = LOD_FADE_M if i > first_lod else 0.0
			mi.visibility_range_end = LOD_END_M[i]
			mi.visibility_range_end_margin = LOD_FADE_M
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			holder.add_child(mi)
	set_headlights(true)
	_set_brake(false)
	ContactShadow.attach(self, false, LOD_END_M[LOD_END_M.size() - 1])  # grounding blob, one draw; origin is the road contact


func set_headlights(on: bool) -> void:
	if _head != null:
		_head.emission_energy_multiplier = HEAD_ON if on else HEAD_OFF


func _set_brake(on: bool) -> void:
	braking = on
	if _tail != null:
		_tail.emission_energy_multiplier = TAIL_BRAKE if on else TAIL_IDLE


## Puts the car on the road at progress s_new in its lane, heading along its direction, at cruise speed.
func place(track: Track, s_new: float) -> void:
	placed = true
	freeze = false
	visible = true
	s = fposmod(s_new, track.length)
	var c: Vector3 = track.get_point_at(s)
	var t: Vector3 = track.get_tangent_at(s)
	var right := Vector3(-t.z, 0.0, t.x)
	var fwd := Vector3(t.x, 0.0, t.z) * float(dir)
	global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), c + right * lat)
	speed = cruise
	linear_velocity = fwd * cruise
	angular_velocity = Vector3.ZERO
	hit_t = 0.0
	_road_y = c.y
	_set_brake(false)


## One physics tick. want is the speed limit from the system (curve, cars ahead), lat_target the lane to hold.
func drive(track: Track, delta: float, want: float, lat_target: float) -> void:
	s = track.get_progress(global_position, s)
	var c0: Vector3 = track.get_point_at(s)
	_road_y = c0.y
	var vy: float = clampf((_road_y - global_position.y) * Y_GAIN, -Y_MAX, Y_MAX)
	var v: Vector3 = linear_velocity
	_v_prev = v
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var look: float = clampf(LOOK_MIN_M + absf(speed) * 0.6, LOOK_MIN_M, LOOK_MAX_M)
	var s_t: float = s + float(dir) * look
	var t: Vector3 = track.get_tangent_at(s_t)
	var target: Vector3 = track.get_point_at(s_t) + Vector3(-t.z, 0.0, t.x) * lat_target
	var aim: Vector3 = target - global_position
	aim.y = 0.0
	lane_err = absf(track.get_lateral_offset(global_position, s) - lat)
	if hit_t > 0.0:
		hit_t -= delta
		linear_damp = 0.6
		angular_damp = 1.5
		linear_velocity = Vector3(v.x, vy, v.z)
		_set_brake(true)
		speed = v.dot(fwd)
		return
	linear_damp = 0.0
	angular_damp = 0.0
	if aim.length_squared() > 0.01:
		var err: float = fwd.signed_angle_to(aim.normalized(), Vector3.UP)
		angular_velocity = Vector3(0.0, clampf(err * YAW_GAIN, -YAW_MAX, YAW_MAX), 0.0)
	var cur: float = v.dot(fwd)
	var rate: float = ACCEL if want > cur else BRAKE
	var new_speed: float = move_toward(cur, want, rate * delta)
	var flat := Vector3(v.x, 0.0, v.z).move_toward(fwd * new_speed, VEL_BLEND * delta)
	linear_velocity = Vector3(flat.x, vy, flat.z)
	speed = new_speed
	var brake_now: bool = want < cur - BRAKE_ON_DECEL
	if brake_now != braking:
		_set_brake(brake_now)


func _on_body_entered(other: Node) -> void:
	if not other is ArcadeCar:
		return
	var rel: float = (_v_prev - (other as ArcadeCar).linear_velocity).length()
	if rel < HIT_MIN_SPEED:
		return
	hit_t = HIT_FREE_S
	hits += 1
	if hit_cb.is_valid():
		hit_cb.call(self)
