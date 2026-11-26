class_name CarSpec
extends Resource
## Every tunable number of a car. Starting values are for the Noctra Sable R.
## Units: metres, kilograms, seconds, newtons. Angles in degrees unless the name says rad.

@export var display_name: String = "Noctra Sable R"

@export_group("Chassis")
@export var mass_kg: float = 1320.0
@export var wheelbase: float = 2.66
@export var track_front: float = 1.66
@export var track_rear: float = 1.64
@export var wheel_radius_front: float = 0.335
@export var wheel_radius_rear: float = 0.35
@export var center_of_mass_height: float = 0.32  ## metres above ground at rest; sets the custom centre of mass
@export var weight_front: float = 0.44  ## static front axle share (mid-engine); sets the centre of mass fore-aft
@export var body_size: Vector3 = Vector3(1.86, 0.50, 4.30)  ## box collider, used when the node has no CollisionShape3D
@export var mount_height: float = -0.20  ## suspension mount height in car local Y (origin = box centre)

@export_group("Suspension")
@export var suspension_rest: float = 0.32  ## unloaded mount-to-ground ray length in m; the static load compresses it about 5 cm
@export var suspension_travel: float = 0.16  ## compression and droop limit in m; compression beyond it meets the bump stop
@export var spring_stiffness: float = 62000.0  ## N/m per wheel
@export var spring_damping: float = 5200.0  ## N*s/m per wheel
@export var anti_roll: float = 9000.0  ## N/m per axle
@export var bump_stop_stiffness: float = 250000.0  ## extra N/m of spring beyond full compression
@export var max_spring_force: float = 24000.0  ## N per wheel, clamp

@export_group("Engine")
@export var top_speed_kmh: float = 286.0
@export var engine_force: float = 13500.0  ## peak drive force in N (arcade, not real torque)
@export var engine_force_curve: Curve  ## x = speed/top_speed 0..1, y = force multiplier
@export var reverse_speed_kmh: float = 45.0
@export var reverse_force_share: float = 0.5  ## reverse drive as a fraction of engine_force
@export var reverse_engage_ms: float = 0.5  ## below this forward speed (m/s), brake input means reverse
@export var brake_force: float = 21000.0
@export var brake_front_share: float = 0.62  ## fraction of brake force on the front axle
@export var engine_brake: float = 1400.0
@export var gear_count: int = 6
@export var gear_ratios: PackedFloat32Array = PackedFloat32Array()  ## per-gear ratio, 1st first; empty = legacy speed-curve drive, no gearbox
@export var final_drive: float = 3.2
@export var drivetrain_efficiency: float = 0.9
@export var peak_torque_nm: float = 520.0
@export var torque_curve: Curve  ## x = rpm / redline_rpm 0..1, y = torque multiplier; null = default
@export var idle_rpm: float = 1000.0
@export var redline_rpm: float = 7500.0
@export var launch_rpm: float = 4200.0  ## clutch slip: torque is read at least at this rpm while the car is slow
@export var shift_time_s: float = 0.16  ## torque cut during an upshift
@export var upshift_rpm_norm: float = 0.97  ## upshift at this fraction of redline
@export var downshift_rpm_norm: float = 0.42
@export var min_shift_gap_s: float = 0.4  ## no second shift sooner than this
@export var brake_ramp_rate: float = 7.0  ## 1/s, how fast the brake pedal builds pressure (releases twice as fast)
@export var gear_dip_s: float = 0.15  ## rpm dip after an upshift, seconds
@export var gear_dip_mult: float = 0.6  ## rpm multiplier during the dip
@export var drag: float = 0.42  ## quadratic air drag coefficient (arcade lumped)
@export var rolling_resistance: float = 180.0

@export_group("Grip")
@export var grip_front: float = 1.5  ## peak lateral friction coefficient, arcade
@export var grip_rear: float = 1.6
@export var lateral_stiffness: float = 1.0  ## lateral grip saturates at this slip speed (m/s) when standing still
@export var peak_slip_deg: float = 8.0  ## tyre slip angle at peak grip; above it the grip is saturated
@export var downforce: float = 1.0  ## N per (m/s)^2, lumped on the body
@export var tyre_falloff_ratio: float = 1.0  ## grip kept in a full slide as a fraction of peak (1.0 = no falloff, legacy)
@export var tyre_falloff_slip_mult: float = 3.0  ## slip, as a multiple of the peak slip, where the falloff is complete
@export var load_sensitivity: float = 0.0  ## 0 = grip scales linearly with load; 0.1 = a loaded tyre gives less grip per newton

@export_group("Steering")
@export var steer_angle_low_deg: float = 32.0  ## at standstill
@export var steer_angle_high_deg: float = 6.5  ## at top speed
@export var steer_speed: float = 5.5  ## how fast the wheel follows the input, 1/s
@export var steer_speed_exponent: float = 1.0  ## below 1 the lock shrinks sooner as speed rises
@export var steer_return_speed: float = 0.0  ## 1/s, wheel centring rate; 0 = same as steer_speed
@export var yaw_damping: float = 1.6  ## yaw rate decay in 1/s, applied as torque on the car mass

@export_group("Drift")
@export var drift_rear_grip_mult: float = 0.48
@export var drift_entry_speed_kmh: float = 55.0
@export var drift_entry_slip_deg: float = 25.0  ## a slip this large starts a drift without the handbrake
@export var drift_min_angle_deg: float = 9.0  ## below this for drift_exit_time the drift ends
@export var drift_max_angle_deg: float = 48.0  ## counter-steer assist pushes back past this
@export var drift_exit_time: float = 0.35
@export var counter_steer_assist: float = 1.0  ## 0 none .. 1 full
@export var counter_steer_start: float = 0.5  ## fraction of drift_max_angle_deg where the assist starts
@export var drift_yaw_damp_mult: float = 6.0  ## extra yaw damping at full assist, so a spin past drift_max_angle_deg is caught
@export var drift_throttle_grip: float = 0.5  ## while drifting, drive may use this fraction of the tyre load (throttle holds the slide)
@export var drift_lift_grip_mult: float = 0.0  ## rear grip mult in a drift with throttle off; 0 = same as drift_rear_grip_mult (legacy)
@export var drift_straighten_steer: float = 0.0  ## |steer| below this lets rear grip return, so a straightened wheel ends the drift; 0 = off (legacy)
@export var drift_grip_recover: float = 100.0  ## 1/s, how fast rear grip returns when the drift ends or throttle lifts
@export var drift_score_rate: float = 12.0  ## points per second per 10 deg at 100 km/h
@export var drift_score_slip_norm_deg: float = 10.0  ## slip angle that scores one unit of drift_score_rate
@export var drift_score_speed_norm_kmh: float = 100.0  ## speed that scores one unit of drift_score_rate
@export var drift_min_speed_ms: float = 1.0  ## slip angle is zero below this speed (m/s)
@export var drift_stop_fraction: float = 0.5  ## a drift also ends below this fraction of drift_entry_speed_kmh

@export_group("Nitro")
@export var nitro_force_mult: float = 1.55
@export var nitro_top_speed_mult: float = 1.16
@export var nitro_capacity_s: float = 3.2
@export var nitro_refill_passive: float = 0.035  ## fraction per second
@export var nitro_refill_drift: float = 0.16  ## fraction per second while drifting
@export var nitro_min_to_start: float = 0.15

@export_group("Arcade assists")
@export var airborne_gravity_mult: float = 1.6  ## gravity multiplier while no wheel touches
@export var air_control_torque: float = 1500.0  ## N*m yaw torque per unit steer while airborne
@export var upright_stiffness: float = 15000.0  ## N*m per rad of tilt
@export var upright_damping: float = 3000.0  ## N*m*s per rad/s of tilt rate
@export var air_pitch_align: float = 0.0  ## N*m per rad: nose follows the flight path while airborne
@export var air_ang_damp: float = 0.0  ## N*m*s per rad/s of spin while airborne
@export var hit_min_impulse: float = 1500.0  ## contact impulse (N*s per tick) that emits hit
@export var max_contacts_reported: int = 8  ## body contacts read per tick for the hit signal


## Default engine torque curve (x = rpm / redline), used by the gearbox when a spec has none.
static func make_default_torque_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.13, 0.45))
	curve.add_point(Vector2(0.35, 0.8))
	curve.add_point(Vector2(0.55, 1.0))
	curve.add_point(Vector2(0.75, 0.95))
	curve.add_point(Vector2(0.88, 0.82))
	curve.add_point(Vector2(1.0, 0.66))
	return curve


## Default engine force curve, used when a spec has none. Keep in step with specs/noctra_sable.tres
## (test_vehicle checks that they match).
static func make_default_force_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.2, 0.92))
	curve.add_point(Vector2(0.4, 0.75))
	curve.add_point(Vector2(0.6, 0.5))
	curve.add_point(Vector2(0.8, 0.33))
	curve.add_point(Vector2(1.0, 0.21))
	return curve
