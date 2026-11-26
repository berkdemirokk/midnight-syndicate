# Vehicle tuning: Noctra Sable R (ArcadeCar)

Owner: Vehicle Physics Agent. Code: `game/vehicles/arcade_car.gd`. Spec: `game/vehicles/specs/noctra_sable.tres` (class `game/vehicles/car_spec.gd`). Tests: `game/tests/test_vehicle.gd`.

## The model in plain words

- A RigidBody3D box (1.86 x 0.50 x 4.30 m, 1320 kg) with a low custom centre of mass. The box bottom sits about 0.22 m above ground at rest, so the suspension carries the car.
- Four rays cast down from mount points (track and wheelbase from the spec). Each contact gets a spring-damper force along the ground normal, clamped to [0, 24 kN]. Compression past the travel limit meets a stiff bump stop. Anti-roll adds force to the more compressed side of each axle and takes it from the other side.
- Tyre force per wheel: lateral force removes the sideways contact velocity, saturating at the peak slip angle (8 deg). A friction circle caps the longitudinal force. Front wheels steer.
- Rear wheels get drive from engine_force times a speed curve, times throttle, with nitro. Brake is on all wheels with a 62 % front bias. Rolling resistance and engine braking act on top. Forces that would reverse a wheel within one tick are clamped to zero.
- Drag and downforce act on the body. Upright torque and yaw damping keep the car level and settled. Airborne: extra gravity and gentle yaw control, no drive.
- Drift starts with the handbrake above 55 km/h, or with a slip angle above 25 deg. Rear grip is multiplied by 0.48. Counter-steer assist ramps in from 24 deg slip to full at 48 deg. Extra yaw damping (x10 at full assist) catches a spin. Throttle may use half the rear tyre load, so it holds the slide. The drift ends when slip stays below 9 deg for 0.35 s, or when speed falls below 50 % of the entry speed (27.5 km/h).
- Nitro: 3.2 s full tank, drains while held, starts at 15 % charge. Drive x1.55, speed cap x1.16. Passive refill 3.5 %/s, 16 %/s while drifting.
- Steering lock goes from 32 deg at standstill to 6.5 deg at top speed. The wheel follows the input at 5.5 1/s.
- Reverse: brake at near standstill drives backwards at half engine force, up to 45 km/h.

## Final spec values (changes from the first draft in brackets)

| Group | Values |
|---|---|
| Chassis | mass 1320 kg, wheelbase 2.66, track 1.66 / 1.64, wheel radius 0.335 / 0.35, CoG 0.32 m above ground, weight front 0.44 |
| Suspension | rest 0.32 m, travel 0.16 m, k 62 kN/m, c 5.2 kN s/m, anti-roll 9 kN/m per axle, bump stop 250 kN/m, max 24 kN |
| Engine | top 286 km/h, force 13.5 kN, curve 1.00 / 0.92 / 0.75 / 0.50 / 0.33 / 0.21 at 0 .. 1.0 of top speed, reverse 45 km/h at 0.5 force, brake 21 kN (62 % front), engine brake 1.4 kN, drag 0.42, rolling 180 N |
| Grip | mu front 1.5 [was 2.15], rear 1.6 [was 2.25], saturation floor 1.0 m/s, peak slip 8 deg, downforce 1.0 N/(m/s)^2 [was 1.9] |
| Steering | 32 deg low, 6.5 deg high, follow 5.5 1/s, yaw damping 1.6 1/s |
| Drift | rear grip x0.48, entry 55 km/h or slip 25 deg, end below 9 deg for 0.35 s, assist 24..48 deg, assist 1.0 [was 0.55], max 48 deg, yaw damp x10 [was x6], throttle grip 0.5 |
| Nitro | force x1.55, cap x1.16, capacity 3.2 s, refill 0.035 /s, 0.16 /s drifting, start at 0.15 |
| Assists | airborne gravity x1.6, air yaw torque 1.5 kN m, upright 15 kN m/rad, damping 3 kN m s/rad |

Tuning guards that were code constants are now spec fields: reverse engage speed, drift minimum speed, drift stop fraction, score normalisers, max contacts reported.

## Measured numbers (headless, 60 Hz, `test_vehicle`, 18 tests, all pass)

| Test | Measured | Accepted range |
|---|---|---|
| 1 settle: vertical speed at 2 s / creep over 5 s | 0.0000004 m/s / 0.00007 m | < 0.05 m/s / < 0.05 m |
| 2 accel 0-100 / 0-200 km/h | 3.08 s / 8.55 s | 2.8 to 4.5 s / < 12 s |
| 3 top speed / reach 96 % / lateral wander | 284.9 km/h / 25.0 s / 0.00001 m | +-4 % of 286 / < 45 s / < 1.0 m |
| 4 nitro top speed (ratio) | 331.8 km/h (1.160 x) | >= 1.10 x |
| 4 full tank drain / passive refill 5 s from 0.5 | 3.22 s / +0.175 | 2.72 to 3.68 s / +0.12 to +0.22 |
| 4 nitro signals | started 1, ended 1 | 1 each |
| 5 braking 100-0 / heading | 25.2 m / 1.0 deg | 18 to 40 m / < 5 deg |
| 5 braking 200-0 / heading | 94.4 m / 0.9 deg | < 130 m / < 5 deg |
| 6 circle at 60 km/h, full lock | 29.0 m radius | 12 to 30 m |
| 6 lateral g at 200 km/h, full lock (slip, yaw) | 1.55 g (5.4 deg, 0.30 rad/s) | 0.9 to 2.2 g (< 12 deg, < 1.0 rad/s) |
| 7 handbrake entry / still drifting 1 s after throttle | 0.02 s / yes | < 1 s / yes |
| 7 slip sustained 15..50 deg / peak slip | 5.0 s / 42.6 deg | >= 2 s / <= 48 deg (drift_max) and <= 70 |
| 7 drift score gain | 160 (chain 179) | rises |
| 7 drift end after release / slip under 8 deg | 1.40 s / 1.73 s | < 2 s / < 3 s |
| 8 reverse | 45.3 km/h | 25 to 50 km/h |
| 9 chaos 30 s | no NaN (checked every tick), upright 0.9999, min height 0.47 m | no NaN, upright > 0.5 |
| 10 drop 1.5 m, flat / onto 0.5 m platform, vertical speed at 3 s | 0.0000003 m/s both, creep 0.03 mm | test 1 conditions |
| 11 10 % slope to 60 km/h / rise over run | 1.97 s, climbed 16.8 m / 0.100 | < 40 s / 0.07 to 0.13 |
| 12 anti-roll, roll in 80 km/h full-lock turn | 1.32 deg with bar, 1.63 deg without | with < without |
| 13 hit on side landing from 6 m | impulse 4595 N s, 0.13 m below ground | >= 1500 N s |
| 14 frozen car drift under throttle / speed 2 s after unfreeze | 0.000 m / 68 km/h | 0 m / > 20 km/h |
| 15 gear upshifts to 150 km/h / max gear / dip ticks | 3 / 4 / 24 checked, 0 off the dip rule | >= 2 / >= 4 / >= 10, 0 off |
| 16 wheel compression at rest / FL centre height | 0.29 of travel / 0.335 m | 0.2 to 0.45 / radius +-0.03 m |
| 16 rear wheel spin step vs speed | matches within 1e-4 rad | 0.1 % + 1e-4 rad |
| 17 default force curve vs noctra_sable.tres | max diff 0 | < 1e-4 |

## Margins and known limits

- Circle radius (29.0 m, limit 30) and drift end (1.40 s, limit 2) have little room. Retune before changing grip or assist.
- Counter-steer start at 0.35 (ramp from 17 deg) kept the peak under 48 deg but stopped the drift from ending on release. The chosen fix is the yaw damping x10 instead.
- The tyre model is a saturating brush with a peak slip angle. No load transfer curve and no wheel spin model.
- Top speed uses a drag equilibrium with the curve value at 1.0. Changing drag or the curve moves it.
- The nitro top-speed test keeps the tank full by writing `nitro_amount` each tick. The car itself does not cheat.
- Test 7 keeps throttle on during the steering release, so the drift end is measured with throttle held.
- Not measured: performance cost. A Jolt "job system exceeded the maximum number of jobs" warning appeared once in an earlier run and did not recur in three later runs. Cause not investigated.

## Handling pass (arcade-sim hybrid)

New spec fields are all backwards compatible: with the defaults (empty `gear_ratios`, `tyre_falloff_ratio` 1.0, `load_sensitivity` 0, `drift_lift_grip_mult` 0, `steer_return_speed` 0, `drift_straighten_steer` 0, `air_*` 0) a spec behaves as before. The Sable opts in.

- **Tyre**: lateral force follows slip angle: `sin` rise to the peak slip (8 deg), then a smooth fall to `tyre_falloff_ratio` (0.88) of peak at `tyre_falloff_slip_mult` (3x) the peak slip. Past the peak the car pushes (understeer) instead of gripping harder. The friction circle is unchanged: lateral has priority, so a braking car can still steer (the ABS-like feel).
- **Load transfer**: comes from the rigid body (CoG 0.32 m, springs, anti-roll): braking loads the front, acceleration the rear, cornering the outside. It feeds grip because friction is `mu * spring load`. `load_sensitivity` (0.08) makes `mu` fall as `(load / static)^-s`, so transferred load costs total grip. `test_handling` asserts front load under braking, rear under acceleration, outside under cornering.
- **Drivetrain**: a real gearbox. Torque = `peak_torque_nm` (520) x `torque_curve(rpm / redline)` x gear x final drive (3.2) x 0.9 / rear wheel radius. 6 gears (2.4, 2.0, 1.69, 1.39, 1.14, 0.934), idle 1000, redline 7500, clutch-slip floor `launch_rpm` 3300, 0.16 s torque cut per upshift, upshift at 97 % redline, downshift below 42 %. `rpm_norm` = (rpm - idle) / (redline - idle), smoothed. `gear` is the real gear. The limiter cuts drive at redline; the nitro speed cap (top x 1.16) is reached at the top-gear redline. `top_speed_kmh` is still a drag equilibrium (torque x ratio vs drag), so retune torque or ratios together with drag.
- **Brakes**: pedal pressure builds at `brake_ramp_rate` (7/s) and releases twice as fast. `brake_force` 16.5 kN (was 21 kN) for a believable 100-0.
- **Steering**: lock follows `lerp(32, 6.5, t^0.8)` with t = speed / top. Centring runs at `steer_return_speed` (11/s), turn-in at `steer_speed` (5.5/s).
- **Drift**: the rear grip multiplier is throttle-modulated: `drift_rear_grip_mult` (0.48) at full throttle, `drift_lift_grip_mult` (0.85) off throttle, so more throttle widens the angle and lifting tightens it. It drops at once and returns at `drift_grip_recover` (3/s), so the exit is a ramp. A straightened wheel (`|steer| < drift_straighten_steer` 0.1) lets grip return and ends the drift. Counter-steer assist and yaw damping are unchanged.
- **Air**: `air_pitch_align` (5 kN m/rad) points the nose along the flight path, `air_ang_damp` (1.2 kN m s/rad) kills spin. A landing from a 25 deg nose-down, 12 deg rolled jump ends upright (dot 1.000) and grounded.

### Measured, before and after (headless, 60 Hz, Windows 11 / RTX 5060 Ti host, `test_handling`)

| Metric | Before | After |
|---|---|---|
| 0-100 km/h | 3.10 s | 4.03 s |
| 0-200 km/h (`test_vehicle`) | 8.55 s | 11.7 s (limit 12) |
| Top speed | 284.9 km/h | 286.0 km/h |
| Braking 100-0 / 200-0 | 25.2 m / 94.4 m | 32.1 m / 120.6 m |
| Braking load transfer, front / rear compression | 0.42 / 0.26 | 0.40 / 0.28 |
| Acceleration load transfer, front / rear | 0.22 / 0.44 | 0.24 / 0.42 |
| Skidpad lateral g at 70 / 110 / 160 km/h | 1.20 / 1.30 / 1.43 | 1.16 / 1.25 / 1.38 |
| Circle radius at 60 km/h, full lock | 29.0 m | 29.8 m (limit 30) |
| Steering lock at 200 km/h | 15.4 deg | 13.3 deg |
| Steering centring to 10 % | 0.40 s | 0.20 s |
| Drift hold (4 s test, slip 12-50 deg) | 4.0 s, max 41 deg | 4.0 s, max 40 deg |
| Drift exit to < 6 deg after lift | 2.98 s | 1.12 s, max 0.83 deg per tick |
| Drift end after steering release, throttle held (`test_vehicle`) | 1.40 s | 1.07 s |

Limits: `test_gear_rpm` in `test_vehicle.gd` was rewritten for the real gearbox (rpm falls after an upshift instead of a cosmetic dip). Circle radius (29.8 of 30) and 0-200 (11.7 of 12) have little room. There is no wheel-spin model and no ABS pulse: the brake is limited by the friction circle, not a slip-ratio controller. Numbers are desktop headless physics, not iPhone.
