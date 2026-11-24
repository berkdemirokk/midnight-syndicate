class_name CarFx
extends Node3D
## Put under an ArcadeCar. Drives nitro flames, tyre smoke, hit sparks, headlights and speed lines
## from the car's signals and state only. Everything it creates is a child of this node, so freeing
## the car frees every emitter. Pools are built once in _ready; nothing is allocated per frame.

const RL: int = 2  ## rear-left index in ArcadeCar.wheel_slip
const RR: int = 3
const NITRO_FULL_KMH: float = 250.0

## Local to the car (forward is -Z). Measured from noctra_sable_lod0.glb: the two exhaust pipe tips sit at
## x = +-0.045, y = 0.33, z = 2.19 (rear), and the flames start just behind them.
@export var exhaust_points: PackedVector3Array = PackedVector3Array([Vector3(-0.045, 0.33, 2.2), Vector3(0.045, 0.33, 2.2)])
## Approximate rear contact points: wheelbase 2.66 m, rear track 1.64 m (check against the spec).
@export var rear_wheel_offsets: PackedVector3Array = PackedVector3Array([Vector3(-0.82, -0.2, 1.33), Vector3(0.82, -0.2, 1.33)])
## Rear slip angle above which tyre smoke starts, and the angle range over which it reaches full amount.
@export var smoke_slip_deg: float = 8.0
## Wheelspin smoke only from a standing start: below this speed and at this throttle or more.
@export var smoke_launch_max_kmh: float = 40.0
@export var smoke_launch_throttle: float = 0.5
const SMOKE_SLIP_RANGE_DEG: float = 12.0
const SMOKE_MIN_SPEED_MS: float = 3.0  ## below this the slip angle is noise
@export var spark_min_impulse: float = 0.0  ## the car only emits hit above spec.hit_min_impulse already
@export var headlights_on: bool = true
## Full-screen overlay: off by default. race_scene gives every car a CarFx, so only the player's
## HUD speed lines should be driven; an opponent with this on would draw streaks on the player's screen.
@export var speed_lines_on: bool = false

var car: ArcadeCar = null
var flames: NitroFlame
var smoke: TireSmoke
var sparks: Sparks
var headlights: Headlights
var speed_lines: SpeedLines
var _wheel_world: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var _slip_out: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])


func _ready() -> void:
	car = get_parent() as ArcadeCar
	if car == null:
		push_warning("CarFx must be a child of an ArcadeCar; effects disabled")
		set_process(false)
		return
	# Flame meshes take the car body's render layers, so the car-only fill light treats them like the body.
	var body_layers: int = 1
	for n: Node in car.find_children("*", "MeshInstance3D", true, false):
		body_layers = (n as MeshInstance3D).layers
		break
	flames = NitroFlame.new()
	smoke = TireSmoke.new()
	sparks = Sparks.new()
	headlights = Headlights.new()
	add_child(flames)
	flames.set_mesh_layers(body_layers)
	add_child(smoke)
	add_child(sparks)
	add_child(headlights)
	if speed_lines_on:
		speed_lines = SpeedLines.new()
		add_child(speed_lines)
	flames.set_exhaust_points(exhaust_points)
	flames.set_active(false)
	headlights.set_on(headlights_on)
	car.nitro_started.connect(_on_nitro_started)
	car.nitro_ended.connect(_on_nitro_ended)
	car.hit.connect(_on_hit)


func _exit_tree() -> void:
	if car != null and is_instance_valid(car):
		if car.nitro_started.is_connected(_on_nitro_started):
			car.nitro_started.disconnect(_on_nitro_started)
		if car.nitro_ended.is_connected(_on_nitro_ended):
			car.nitro_ended.disconnect(_on_nitro_ended)
		if car.hit.is_connected(_on_hit):
			car.hit.disconnect(_on_hit)


func _process(_delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var xf: Transform3D = car.global_transform
	# Nitro flame strength follows speed while the flames are on.
	flames.set_strength(clampf(car.speed_kmh / NITRO_FULL_KMH, 0.0, 1.0))
	# Tyre smoke: rear wheels only, and only while sliding. wheel_slip is grip usage (high under
	# plain acceleration), so it is not used here.
	var lateral: float = car.linear_velocity.dot(xf.basis.x)
	for i: int in 2:
		var idx: int = RL + i
		var amount: float = 0.0
		if car.wheel_contact[idx]:
			var slip_deg: float = _rear_slip_deg(i, xf)
			amount = clampf((slip_deg - smoke_slip_deg) / SMOKE_SLIP_RANGE_DEG, 0.0, 1.0)
			if car.is_drifting:
				amount = maxf(amount, 0.5)
			elif car.speed_kmh < smoke_launch_max_kmh and car.input.throttle >= smoke_launch_throttle:
				amount = maxf(amount, 0.6)  ## standing-start wheelspin
		_slip_out[i] = amount
		_wheel_world[i] = xf * rear_wheel_offsets[i]
	smoke.update_puffs(_wheel_world, _slip_out, xf.basis.x * signf(lateral), absf(lateral))
	# Speed lines: none below 160 km/h, full at 180 km/h, stronger with nitro (SpeedLines.intensity_for).
	if speed_lines != null:
		speed_lines.set_speed(car.speed_kmh, car.nitro_active)


## Lateral slip angle in degrees at rear wheel i: the velocity of that contact point, body frame.
func _rear_slip_deg(i: int, xf: Transform3D) -> float:
	var r: Vector3 = xf.basis * (rear_wheel_offsets[i] - car.center_of_mass)
	var v: Vector3 = car.linear_velocity + car.angular_velocity.cross(r)
	if v.length() < SMOKE_MIN_SPEED_MS:
		return 0.0
	var lat: float = absf(v.dot(xf.basis.x))
	var long: float = absf(v.dot(-xf.basis.z))
	return rad_to_deg(atan2(lat, long))


func _on_nitro_started() -> void:
	flames.set_active(true)
	flames.pop()


func _on_nitro_ended() -> void:
	flames.set_active(false)


func _on_hit(impulse: float, world_pos: Vector3) -> void:
	if impulse >= spark_min_impulse:
		sparks.burst(world_pos)


func set_headlights(on: bool) -> void:
	headlights.set_on(on)
