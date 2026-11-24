# Racing AI, race manager and track

Code: `game/ai/ai_driver.gd` (AIDriver), `game/race/race_manager.gd` (RaceManager), `game/world/track.gd` (Track).
Test circuit: `game/tests/helpers/test_track.gd`. Tests: `game/tests/test_ai_race.gd` (9 tests on the test circuit),
`game/tests/test_city_race.gd` (2 tests on city_01: a 6-car race and a 2-lap regression).
Diagnostics (not tests, run with `--headless --fixed-fps 60 --path game -s res://ai/<file>`):
`game/ai/diag_ai_stuck.gd` (race with stuck and contact logging; options `--cars=N`, `--out=file.json`,
`--slide=<m/s>` turns the slide rule off with a large value, `--s=a,b` traces cars inside that progress window)
and `game/ai/diag_probe_walls.gd` (ray scan of road-side colliders along a track range).
Output: `evidence/logs/stuck_events.json` (final 6-car run), `evidence/logs/stuck_events_run2.json` (before the fix).

## Track
- RacingLine is a closed Catmull-Rom Curve3D (last point repeats the first). Sampled every 4 m at `_ready`.
- Target speed profile: `v = min(max_speed, sqrt(a_lat * r))`, then a backward pass for braking (11 m/s^2)
  and a forward pass for acceleration (9 m/s^2), both around the loop twice. The corner limit a_lat is 9.5 m/s^2.
- Progress: nearest sample plus projection on its two neighbouring segments. An optional hint narrows the search to 120 m.
  No allocation per call.
- Lateral offset: positive = right of the race direction (+X when driving -Z). Curvature: signed, positive = right turn.

## AI driver
- Runs before its ArcadeCar (physics priority -1), so the car reads this tick's input.
- Pure pursuit: look-ahead 8 m + 0.45 s x speed (8 to 45 m), aimed at the racing line shifted by the lane offset.
- Speed: target = min(profile at car, profile 0.6 s ahead) x skill x rubber band, capped at the car top speed.
  Throttle or brake is proportional to the error. Nitro only on straights (radius over 250 m) when the target is
  more than 10 m/s (36 km/h) above the speed.
- Slide rule (added with the city_01 fix): the sideways speed of the car across the track (its velocity
  projected on the track's lateral direction) is read each tick. The throttle is multiplied by a ramp that is 1 up to
  `slide_lift_ms` (2.5 m/s), 0 at `slide_cut_ms` (4.0 m/s), linear in between. Brake is not changed. Nitro is not gated
  by this rule (open item below).
- Noise: two smooth sines, phase from `noise_seed`. RaceManager sets it to the grid slot, so drivers differ.
  Braking points +-4 % of target speed, steering +-0.03.
- Overtaking: a slower car within 20 m ahead in our lane triggers a 2.5 m lane shift to the side with the most room.
  A side is refused when a car is alongside on it (7 m along, 3.2 m across). The shift returns at 1.5 m/s.
- Stuck: under 5 km/h for 2.5 s while racing starts a 1.5 s reverse. If still under 5 km/h, the car is reset onto the line facing forward.
- Rubber band: RaceManager pushes the player's unwrapped race distance minus ours each tick. Gap beyond 150 m moves
  target speed by up to +-8 % (ahead of the player: down, behind: up). Never above the top speed. Neutral without a gap.
- Finished or idle cars brake at 0.5 while above 20 km/h, then coast to a stop.

## Race manager
- Grid: cars on Grid0..7 (two columns, 9 m rows), frozen. Countdown emits 3, 2, 1, 0 (GO), unfreezes, emits race_started.
- Laps: four virtual gates at 25, 50, 75 and 100 % of the line. Only a forward step into the next quarter counts, and only
  when the previous gates were passed in order. Crossing the line on the grid or reversing across it adds no lap.
- Positions: finished cars by finish order, then unfinished cars by unwrapped race distance. position_changed fires only on change.
- End: when the player finishes, the rest get 15 s. When all cars finish, the race ends at once. Unfinished cars get
  `race_time x total_distance / distance_so_far`. race_finished fires once with results sorted by total_time.
- Wrong way: the player's velocity along the line below -3 m/s for 0.5 s emits wrong_way_changed(true); forward clears it.
- setup() resets the race state, so a second race on the same node works.

## city_01 stuck investigation (6 and 8 cars, 1 lap)
Setup: `diag_ai_stuck.gd`, skills 1.0 / 0.97 / 0.94 / 0.91 / 0.88 / 0.85 (8-car run adds 0.9 and 0.87), grid order,
no player, 60 Hz. Numbers are simulated. Every run finished the race.

Before the fix (AI as it was at the start of this task):
- 6 cars: race 94.63 s, 6 stuck events (cars 1: 2, 3: 1, 5: 3). All six at s = 1127 to 1133 m, lateral 4.6 to 7.5 m
  from the racing line, speed 0, throttle 1.0, colliding with `bld_parking_01_b` or `bld_waterfront_01_a`.
- 8 cars: race 100.38 s, 10 stuck events (in three places, see open items).
- Solo, skill 1.0: lap 63.95 s, 0 stuck (the 63.9 s baseline).

Findings, with data:
1. Layout: the right-hand side of the road is occupied by building colliders at s 1080 to 1108 m
   (`bld_parking_01_a`) and s 1136 to 1176 m (`bld_parking_01_b`). A horizontal ray scan every 2 m from the racing line
   (`diag_probe_walls.gd`) finds the first right-hand collider at lateral +2.5 to +3.0 m in the first range and +3.9 to
   +2.6 m in the second. The road is 14 m wide (kerb 6.8 m). `bld_waterfront_01_a` gives +8.5 m at 1114 to 1134 m.
   The layout entries seem to put the building centres about 11 m right of the line with about 24 m half depths; the owner must check the
   footprints. This is the cause of the wedging, but it is in the layout, which is not owned here.
2. AI: between 1080 and 1150 m the racing line is a left-hand sweep of radius about 220 m. The track profile allows
   about 160 to 185 km/h there. Solo, with throttle near 1.0 on the way in, the car slides right: yaw error grows to
   -8 deg and the sideways speed to 6 to 7.5 m/s, so the car crosses the line by about 5 m (lateral -2.6 m to +2.3 m).
   It touches `bld_parking_01_b` at 1143 m even alone (speed 166 to 133 km/h) and survives only by bouncing.
3. Cars in traffic reach the same spot at 140 to 165 km/h and end up pinned at 2.9 to 3.8 m with throttle 1.0.
   The wedged car then creeps at 5 to 12 km/h, so the 2.5 s under 5 km/h of the stuck detector never accrues. In the
   6-car baseline car 1 stayed pinned for about 6 s (first contact at 34.8 s, stuck event at 40.6 s).
4. Rejected: a corner-speed margin in the AI (its own profile at 7 m/s^2) made the solo lap 70.7 s (+10 %) and the car
   still slid 4 m, so the slide is not a speed problem alone. It was removed.

Fix (AI only): the slide rule above. A step cut of the throttle (no ramp) gave the same 6-car count, but it moved the
race scene's racing wheel error from 0.3 mm to 1.31 mm (limit 1 mm, `test_race_scene`). The wheel visual is one
physics tick behind (interpolation), so a sudden suspension change shows as error. The ramp keeps it at 0.3 mm.
Threshold scan with the step version (not repeated for the ramp): 2.0 m/s gave 2 stuck events, 2.5 gave 1, 3.0 gave 2.

After the fix (AI as shipped):
| Run | Race time | Stuck events | Notes |
|---|---|---|---|
| 6 cars, before | 94.63 s | 6 | `stuck_events_run2.json` |
| 6 cars, after | 80.4 s | 1 | car 5 (skill 0.85) at s 1132.9 m, pinned by `bld_parking_01_b` |
| 8 cars, before | 100.38 s | 10 | rule disabled with `--slide=1000` |
| 8 cars, after | 95.5 s | 7 | three clusters, see open items |
| Solo lap, before / after | 63.95 s / 64.97 s | 0 / 0 | +1.6 % lap time |

The earlier note "an 8-car race does not finish in 170 s headless" was not reproduced: with these skills all 8 cars
finish in 95 to 100 s. Its settings are not recorded, so the difference is open.

## Measured (headless, --fixed-fps 60, test circuit 1265 m, 316 samples, after the fix)
| Metric | Value |
|---|---|
| Length vs summed sample chords | within 1 % (test range) |
| Progress error vs walked offset | 0.000012 m |
| Target speed hairpin / straight | 16.0 / 58.2 m/s |
| Lateral offset at +-3 m | +3.0000 / -3.0000 m |
| Solo AI, skill 1.0: lap 1 / lap 2 | 52.2 s / 50.0 s (was 51.6 / 49.1) |
| Solo AI max abs lateral (limit 7 m) | 5.83 m (was 5.72) |
| Solo AI stuck events | 0 |
| 4 AI race totals by position (skills 1.0/0.95/0.9/0.85) | 103.2 / 104.8 / 122.8 / 126.9 s |
| 4 AI race best laps by position | 50.2 / 51.2 / 58.3 / 53.6 s |
| Min car up.y over race (no flips) | 0.9996 |
| Countdown: movement before GO | 0.0 m |
| Reverse across start: laps added | 0 (reverse and forward crossing), 1 for the forward lap |
| Rubber band at +75 / +225 / +700 / -225 / -700 m | 1.00 / 1.04 / 1.08 / 0.96 / 0.92 |
| Overtake: max lateral shift reached, 30 m behind a parked car | 2.88 m (`overtake_max_shift_m`; the earlier 4.87 m was a different metric) |
| Stuck: events while held 3 s / forward after release 8 s | 1 / 169 m |
| Wrong-way signal | true after 0.5 s backwards, false after forward |

city_01 (`test_city_race.gd`, dev PC, RTX 5060 Ti, desktop, Mobile renderer; simulated numbers are the same on any machine
at --fixed-fps 60):
| Metric | Value |
|---|---|
| 6-car, one lap: race time | 80.4 s, all 6 classified, positions 1 to 6 unique |
| 6-car: stuck events in total | 1 (limit 1) |
| 6-car: min basis.y.y (upright) | 0.9918 (limit 0.5) |
| 6-car: wall-clock for the test | 3.2 s (limit 120 s, set by the test) |
| Single car, 2 laps: lap 1 / lap 2 | 64.97 s / 65.85 s (limit 67.1 s = 63.9 s +5 %) |
| Single car: stuck events | 0 |
| test_city_01 single AI lap | 64.97 s, max lateral 5.81 m, 0 stuck |

## Limits and open items
- Layout defect (not fixed here, owner: Environment): the parking buildings intrude into the road at s 1080 to 1108 m and
  1136 to 1176 m (right side, 2.5 to 3.9 m from the line). Any car sliding there can be wedged. The AI cannot see colliders.
- 8 cars, after the fix: 7 stuck events in three places. (a) s 449 m, lateral 6.3 m, `bld_neon_03_b`, target 37 m/s.
  (b) s 506 m, lateral 6.5 to 7.2 m, `wall_04` and `bld_downtown_03_a`: one car went to a yaw error of -90 deg after a
  hit at 496 m (source not identified) and hit the same wall three times, because the stuck reset puts it back on the line and the same line leads to the wall.
  (c) s 1133 to 1139 m, the parking intrusion again.
- Contacts: about 10 unique car pairs per race (`contacts` in the JSON). Most are rear-end touches at 100 to 125 km/h at the
  race start (s 390 to 436 m) and during the finish bunch-up. Not analysed in detail.
- Stuck detection is still speed-based. A progress-based detector (no progress for N seconds) would catch the creeping
  wedge sooner. Not built.
- Nitro is not gated by the slide rule. Nitro while sliding may increase the excursions. Not measured.
- The stuck recovery still teleports to the line after a failed reverse. This is a fallback, not a fix.
- Lateral accel limit tuned to 9.5 m/s^2 after 13 m/s^2 gave 11 m excursions at the car grip limit under throttle.
- Solo lateral margin (5.8 of 7 m) is modest. Re-check after any grip or steering change in ArcadeCar.
- Track length is 1.27 km (test circuit), a little above the 1.2 km target.
- Estimated times for unfinished cars are a pace extrapolation, not simulated.
