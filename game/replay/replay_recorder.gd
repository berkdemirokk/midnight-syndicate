class_name ReplayRecorder
extends Node
## Records every car's state at 30 Hz between start() and stop() (the race scene calls them on
## race_started and race_finished). Samples go into one preallocated ring buffer: setup() allocates it,
## nothing allocates while recording, and the oldest samples are overwritten once it is full (5 minutes).

const SAMPLE_HZ: float = 30.0
const MAX_SECONDS: float = 300.0
const SAMPLE_PERIOD_S: float = 1.0 / SAMPLE_HZ
const F_POS: int = 0  ## 3: world origin
const F_QUAT: int = 3  ## 4: basis rotation quaternion x y z w
const F_STEER: int = 7  ## front wheel steer angle, rad
const F_SPIN: int = 8  ## 4: wheel spin, rad (FL FR RL RR)
const F_SPEED: int = 12  ## km/h
const F_VEL: int = 13  ## 3: linear velocity
const F_NITRO: int = 16  ## 1 while nitro is active
const F_DRIFT: int = 17  ## 1 while drifting
const F_DRIFT_DEG: int = 18  ## signed slip angle, deg
const F_BRAKE: int = 19  ## brake input 0..1
const F_CONTACT: int = 20  ## bit i set = wheel i in contact (FL FR RL RR)
const F_COMP: int = 21  ## 4: wheel suspension compression 0..1 (FL FR RL RR), so the replayed wheels sit where they were
const STRIDE: int = 25  ## floats per car per sample
const WHEEL_COUNT: int = 4

var capacity: int = 0
var car_count: int = 0
var recording: bool = false
var _cars: Array[ArcadeCar] = []
var _data: PackedFloat32Array = PackedFloat32Array()
var _head: int = 0  ## slot the next sample is written to
var _count: int = 0  ## valid samples, up to capacity
var _acc: float = 0.0


## Allocates the ring for these cars. Call once, before the race starts.
func setup(cars: Array[ArcadeCar]) -> void:
	_cars = cars.duplicate()
	car_count = _cars.size()
	capacity = int(ceilf(SAMPLE_HZ * MAX_SECONDS))
	_data.resize(capacity * car_count * STRIDE)
	_data.fill(0.0)
	clear()


func start() -> void:
	clear()
	recording = true
	_acc = SAMPLE_PERIOD_S  ## the first physics tick takes the first sample


func stop() -> void:
	recording = false


func clear() -> void:
	_head = 0
	_count = 0
	_acc = 0.0


func has_data() -> bool:
	return _count >= 2


func sample_count() -> int:
	return _count


func duration_s() -> float:
	return maxf(float(_count - 1) * SAMPLE_PERIOD_S, 0.0)


func buffer_size() -> int:
	return _data.size()


func _physics_process(delta: float) -> void:
	if not recording or car_count == 0:
		return
	_acc += delta
	if _acc >= SAMPLE_PERIOD_S:
		_acc -= SAMPLE_PERIOD_S
		_capture()


func _capture() -> void:
	var base: int = _head * car_count * STRIDE
	for i: int in car_count:
		var c: ArcadeCar = _cars[i]
		var o: int = base + i * STRIDE
		var xf: Transform3D = c.global_transform
		var q: Quaternion = xf.basis.get_rotation_quaternion()
		_data[o + F_POS] = xf.origin.x
		_data[o + F_POS + 1] = xf.origin.y
		_data[o + F_POS + 2] = xf.origin.z
		_data[o + F_QUAT] = q.x
		_data[o + F_QUAT + 1] = q.y
		_data[o + F_QUAT + 2] = q.z
		_data[o + F_QUAT + 3] = q.w
		_data[o + F_STEER] = c.steer_angle_rad
		for w: int in WHEEL_COUNT:
			_data[o + F_SPIN + w] = c.wheel_spin_rad[w]
			_data[o + F_COMP + w] = c.wheel_compression[w]
		_data[o + F_SPEED] = c.speed_kmh
		_data[o + F_VEL] = c.linear_velocity.x
		_data[o + F_VEL + 1] = c.linear_velocity.y
		_data[o + F_VEL + 2] = c.linear_velocity.z
		_data[o + F_NITRO] = 1.0 if c.nitro_active else 0.0
		_data[o + F_DRIFT] = 1.0 if c.is_drifting else 0.0
		_data[o + F_DRIFT_DEG] = c.drift_angle_deg
		_data[o + F_BRAKE] = c.input.brake if c.input != null else 0.0
		var bits: int = 0
		for w: int in WHEEL_COUNT:
			if c.wheel_contact[w]:
				bits |= 1 << w
		_data[o + F_CONTACT] = float(bits)
	_head = (_head + 1) % capacity
	_count = mini(_count + 1, capacity)


## Slot of logical sample k (0 = oldest kept sample).
func _slot(k: int) -> int:
	var oldest: int = (_head - _count + capacity) % capacity
	return (oldest + k) % capacity


## Replay clock: t seconds from the oldest kept sample. Fills out (car_count * STRIDE floats) with the
## interpolated state. Positions, velocities, steer and speed are blended; wheel spin, flags, contact take
## the earlier sample (spin wraps at TAU, so blending it would spin the wheels backwards for a frame).
func read(t: float, out: PackedFloat32Array) -> void:
	if _count == 0:
		return
	var f: float = clampf(t / SAMPLE_PERIOD_S, 0.0, float(_count - 1))
	var k0: int = mini(int(f), _count - 1)
	var k1: int = mini(k0 + 1, _count - 1)
	var a: float = f - float(k0)
	var b0: int = _slot(k0) * car_count * STRIDE
	var b1: int = _slot(k1) * car_count * STRIDE
	for i: int in car_count:
		var o0: int = b0 + i * STRIDE
		var o1: int = b1 + i * STRIDE
		var d: int = i * STRIDE
		for j: int in STRIDE:
			var hold: bool = (j >= F_SPIN and j < F_SPIN + WHEEL_COUNT) or j == F_NITRO or j == F_DRIFT or j == F_CONTACT
			out[d + j] = _data[o0 + j] if hold else lerpf(_data[o0 + j], _data[o1 + j], a)
		# Quaternion: take the shorter arc, then renormalise.
		var dot: float = 0.0
		for j: int in 4:
			dot += _data[o0 + F_QUAT + j] * _data[o1 + F_QUAT + j]
		if dot < 0.0:
			for j: int in 4:
				out[d + F_QUAT + j] = lerpf(_data[o0 + F_QUAT + j], -_data[o1 + F_QUAT + j], a)
		var qn: float = 0.0
		for j: int in 4:
			qn += out[d + F_QUAT + j] * out[d + F_QUAT + j]
		var inv: float = 1.0 / sqrt(maxf(qn, 1e-12))
		for j: int in 4:
			out[d + F_QUAT + j] *= inv


## Recorded origin of car i at logical sample k (tests and diagnostics).
func origin_at(car_index: int, k: int) -> Vector3:
	var o: int = _slot(k) * car_count * STRIDE + car_index * STRIDE
	return Vector3(_data[o + F_POS], _data[o + F_POS + 1], _data[o + F_POS + 2])
