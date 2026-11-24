class_name GarageStats
extends RefCounted
## Four 0..1 stat bars from the CarSpec and the upgrade levels. Pure functions, so tests can check them.
## Upgrade effects (per level): engine +4 km/h top speed and +5% drive force, tyres +4% grip,
## nitro +10% capacity, weight -2% mass. Reference values map a stat to a full bar.

const KMH_FULL: float = 320.0
const ACCEL_FULL: float = 12.8  ## drive force per kg (N/kg) that fills the acceleration bar
const GRIP_FULL: float = 2.0  ## average peak grip that fills the handling bar
const NITRO_FULL_S: float = 5.0
const ENGINE_KMH: float = 4.0
const ENGINE_FORCE: float = 0.05
const TYRE_GRIP: float = 0.04
const NITRO_CAP: float = 0.1
const WEIGHT_MASS: float = 0.02


## Returns {speed, accel, handling, nitro} in 0..1. upgrades maps part name to level (0..5).
static func compute(spec: CarSpec, upgrades: Dictionary) -> Dictionary:
	var eng: float = float(upgrades.get("engine", 0))
	var tyr: float = float(upgrades.get("tires", 0))
	var nit: float = float(upgrades.get("nitro", 0))
	var wgt: float = float(upgrades.get("weight", 0))
	var top_kmh: float = spec.top_speed_kmh + ENGINE_KMH * eng
	var mass: float = spec.mass_kg * (1.0 - WEIGHT_MASS * wgt)
	var force: float = spec.engine_force * (1.0 + ENGINE_FORCE * eng)
	var grip: float = (spec.grip_front + spec.grip_rear) * 0.5 * (1.0 + TYRE_GRIP * tyr)
	var nitro_s: float = spec.nitro_capacity_s * (1.0 + NITRO_CAP * nit)
	return {
		"speed": clampf(top_kmh / KMH_FULL, 0.0, 1.0),
		"accel": clampf(force / maxf(mass, 1.0) / ACCEL_FULL, 0.0, 1.0),
		"handling": clampf(grip / GRIP_FULL, 0.0, 1.0),
		"nitro": clampf(nitro_s / NITRO_FULL_S, 0.0, 1.0),
	}
