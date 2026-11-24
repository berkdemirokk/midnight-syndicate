class_name CarSpec
extends Resource
## Every tunable number of a car. Starting values are for the Noctra Sable R.

@export var display_name: String = "Noctra Sable R"

@export_group("Chassis")
@export var mass_kg: float = 1320.0
@export var wheelbase: float = 2.66
@export var track_front: float = 1.66
@export var track_rear: float = 1.64
@export var wheel_radius_front: float = 0.335
@export var wheel_radius_rear: float = 0.35
@export var center_of_mass_height: float = 0.32  ## above ground at rest; low for stability
@export var weight_front: float = 0.44  ## static front axle share (mid-engine)

@export_group("Suspension")
@export var suspension_rest: float = 0.30  ## ray length from mount to wheel centre at full droop
@export var suspension_travel: float = 0.16
@export var spring_stiffness: float = 62000.0  ## N/m per wheel
@export var spring_damping: float = 5200.0  ## N*s/m per wheel
@export var anti_roll: float = 9000.0  ## N/m per axle

@export_group("Engine")
@export var top_speed_kmh: float = 286.0
@export var engine_force: float = 13500.0  ## peak drive force in N (arcade, not real torque)
@export var engine_force_curve: Curve  ## x = speed/top_speed 0..1, y = force multiplier
@export var reverse_speed_kmh: float = 45.0
@export var brake_force: float = 21000.0
@export var engine_brake: float = 1400.0
@export var gear_count: int = 6
@export var drag: float = 0.42  ## quadratic air drag coefficient (arcade lumped)
@export var rolling_resistance: float = 180.0

@export_group("Grip")
@export var grip_front: float = 2.15  ## peak lateral friction coefficient, arcade (above real)
@export var grip_rear: float = 2.25
@export var lateral_stiffness: float = 9.0  ## how quickly lateral force builds with slip velocity
@export var downforce: float = 1.9  ## N per (m/s)^2

@export_group("Steering")
@export var steer_angle_low_deg: float = 32.0  ## at standstill
@export var steer_angle_high_deg: float = 6.5  ## at top speed
@export var steer_speed: float = 5.5  ## how fast the wheel follows the input, 1/s
@export var yaw_damping: float = 1.6

@export_group("Drift")
@export var drift_rear_grip_mult: float = 0.48
@export var drift_entry_speed_kmh: float = 55.0
@export var drift_min_angle_deg: float = 9.0  ## below this for drift_exit_time the drift ends
@export var drift_max_angle_deg: float = 48.0  ## assist pushes back past this
@export var drift_exit_time: float = 0.35
@export var counter_steer_assist: float = 0.55  ## 0 none .. 1 full
@export var drift_score_rate: float = 12.0  ## points per second per 10 deg at 100 km/h

@export_group("Nitro")
@export var nitro_force_mult: float = 1.55
@export var nitro_top_speed_mult: float = 1.16
@export var nitro_capacity_s: float = 3.2
@export var nitro_refill_passive: float = 0.035  ## fraction per second
@export var nitro_refill_drift: float = 0.16  ## fraction per second while drifting
@export var nitro_min_to_start: float = 0.15
