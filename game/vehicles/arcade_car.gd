class_name ArcadeCar
extends RigidBody3D
## CONTRACT STUB written by the lead. The Vehicle Physics Agent implements the body of this
## class. Public names, types and signals below must not change (other systems depend on them).
## Forward is -Z. See ARCHITECTURE.md.

signal drift_started
signal drift_ended(score: float)
signal nitro_started
signal nitro_ended
signal hit(impulse: float, world_pos: Vector3)

@export var spec: CarSpec

## Written every physics tick by a driver node (player, AI, police). Never null after _ready.
var input: VehicleInput = VehicleInput.new()

# Read-only state for camera, HUD, VFX, audio, AI:
var speed_kmh: float = 0.0
var forward_speed: float = 0.0  ## m/s along -Z, negative when reversing
var is_grounded: bool = false
var grounded_wheels: int = 0
var is_drifting: bool = false
var drift_angle_deg: float = 0.0  ## signed slip angle of the body
var drift_score: float = 0.0  ## score of the current drift chain
var nitro_amount: float = 1.0  ## 0..1
var nitro_active: bool = false
var gear: int = 1
var rpm_norm: float = 0.0  ## 0..1
var wheel_contact: Array[bool] = [false, false, false, false]  ## FL, FR, RL, RR
var wheel_compression: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])  ## 0..1
var wheel_spin_rad: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var wheel_slip: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])  ## 0..1, for smoke and skid audio
var steer_angle_rad: float = 0.0


## Teleport, zero velocities, reset drift and (optionally) nitro.
func reset_to(xf: Transform3D, refill_nitro: bool = true) -> void:
	pass


## While frozen the car holds its place on the grid and ignores input (engine may still rev).
func set_frozen_for_grid(frozen: bool) -> void:
	pass


## Local-space wheel centre for visuals, index 0..3 = FL, FR, RL, RR.
func get_wheel_local_position(index: int) -> Vector3:
	return Vector3.ZERO
