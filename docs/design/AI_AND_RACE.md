# Racing AI, race manager and track

Code: `game/ai/ai_driver.gd` (AIDriver), `game/race/race_manager.gd` (RaceManager), `game/world/track.gd` (Track).
Test circuit: `game/tests/helpers/test_track.gd`. Tests: `game/tests/test_ai_race.gd` (9 tests on the test circuit),
`game/tests/test_city_race.gd` (3 tests on city_01: a 6-car race, an 8-car stuck limit, and a 2-lap regression with the lap-2 top speed).
Diagnostics (not tests, run with `--headless --fixed-fps 60 --path game -s res://ai/<file>`):
`game/ai/diag_ai_stuck.gd` (race with stuck and contact logging; options `--cars=N`, `--out=file.json`,
`--slide=<m/s>` turns the slide rule off with a large value, `--s=a,b` traces cars inside that progress window)
and `game/ai/diag_probe_walls.gd` (ray scan of road-side colliders along a track range).
Round 3: `game/ai/diag_nitro.gd` (solo nitro and speed per tick, per lap, with the target profile; `--out=<file>`).
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
  Throttle or brake is proportional to the error. Nitro (round 3): starts above 0.3 charge and then runs until the charge is empty;
  needs the target more than 5 m/s above the speed, no slower car in follow range, and a road with |curvature| under 0.004 1/m
  (radius over 250 m) for 90 m ahead (`nitro_look_m`).
- Slide rule (added with the city_01 fix): the sideways speed of the car across the track (its velocity
  projected on the track's lateral direction) is read each tick. The throttle is multiplied by a ramp that is 1 up to
  `slide_lift_ms` (2.5 m/s), 0 at `slide_cut_ms` (4.0 m/s), linear in between. Brake is not changed. Nitro is not gated
  by this rule (open item below).
- Noise: two smooth sines, phase from `noise_seed`. RaceManager sets it to the grid slot, so drivers differ.
  Braking points +-4 % of target speed, steering +-0.03.
- Overtaking: a slower car within 20 m ahead in our lane triggers a 2.5 m lane shift to the side with the most room.
  A side is refused when a car is alongside on it (7 m along, 3.2 m across). The shift returns at 1.5 m/s.
  Round 3: a side is also refused when the shift would put the car within 1.5 m of the kerb (`kerb_margin`), and when it goes
  to the outside of a bend tighter than 0.006 1/m. Shifts move at full rate below 0.006 1/m, at a damped rate up to 0.008 1/m,
  and not at all from 0.008 1/m (radius 125 m). A bend bias moves the lane up to 1.5 m to the inside between 0.006 and 0.0075 1/m.
- Stuck (round 2, progress-based): while racing, no 2 m of forward progress along the line within 2 s starts recovery.
  Recovery brakes for 1.5 s (reverse by brake once stopped). The car is free only if it gained 2 m of progress since the
  recovery started and its heading is within 40 deg of the line; otherwise it is teleported onto the line (last resort).
- Follow (round 2): a slower car within 18 m ahead in our lane (1.5 lane widths) caps the target at its speed plus 0.6 m/s per
  m beyond a 6 m gap. Not applied while a lane shift is under way (passing).
- Slide brake (round 2): sideways speed above 2.5 m/s also brakes, 0.15 per m/s (full at about 9 m/s), so the tyres get back grip.
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

## city_01 round 2 (after the Environment corridor push)
Diagnostics: `diag_ai_stuck.gd --cars=6|8|1 --out=...`; numbers from `evidence/logs/stuck_events_round2.json`
(6 cars, 8 cars, solo) and the runs listed below. Simulated, 60 Hz, all runs finished.

Start of round 2 (the intrusions at 1080 to 1176 m were pushed out, but the clusters below remained):
| Run | Race time | Stuck events | Where |
|---|---|---|---|
| 6 cars | 74.57 s | 4 (car 0 x4) | s 1265 to 1273 m, lat -11.4, `wall_10` (left side) |
| 8 cars | 77.18 s | 16 | s 470 to 477 m (`bld_neon_03_a`, car 4 and 5), s 615 to 660 m (`bld_downtown_01/02_b`, cars 4, 6, 7) |

Causes, from traces (`--s=<a>,<b>` windows):
1. s 1150 to 1230 m, car 0 alone at skill 1.0: 155 km/h on the left sweep with throttle 0 and sideways speed 8 m/s, then yaw
   swings from +4 to +42 deg with sideways speed -20 m/s. The slide rule only cut the throttle; nothing braked the slide.
   Fix: slide brake (above). After it, 0 stuck events in the 6-car race and the same car stays on the road.
2. s 430 to 460 m, car 4: cars bunched at the start touched (contacts at s 390 to 440 m). The AI had no car-following, so a
   car at 100 to 108 km/h kept throttle on into the car ahead. Yaw error reached -56 deg at 458 m. Fix: follow cap.
3. Stuck recovery did not free a spun car. The reverse only braked (no steering), and the car was released at 23 km/h
   facing back along the road (yaw -112 deg). Fix: the teleport only when the car did not gain progress or still faces
   more than 40 deg from the line.
4. Speed-based detector: a car pinned at 5 to 12 km/h never triggered the 5 km/h test. Fix: progress-based detector.
5. Overtake with the follow cap: the cap slowed the chaser before the shift could start (test_overtake_shifts_lane
   failed at 0.70 m). Fix: no follow cap while a lane shift is under way (1.61 m shift).

Round 2 final runs (current code):
| Run | Race time | Stuck events | Notes |
|---|---|---|---|
| 6 cars | 74.10 s | 0 | 6 contacts, min basis.y.y 0.9963 |
| 8 cars | 85.13 s | 3 | cars 5 and 6 at s 500 to 505 m (lat -4.4 to -7.5, left kerb, `Colliders_02`), car 6 at s 1472 m (right kerb) |
| solo, skill 1.0 | 65.37 s | 0 | lap 1; test_city_race lap 1 65.33 s, lap 2 66.68 s |

Before the overtake skip (the cap also applied while passing) the 8-car run had 0 stuck events, but the overtake test failed.
The 3 events are the trade-off of that choice. The overtake shift at s 480 m moved the car to the left kerb while car 6 on its
right pushed it further; the lane limit (5.5 m) is not enough when two cars share the side. Open.

Targets (round 2 brief):
- 6 cars, 0 stuck: met (0).
- 8 cars, at most 1: not met (3).
- Solo lap, at most 66 s: met (65.37 s; 0 stuck).
- Autopilot car reaches 220 km/h on a lap: not met (solo max 174.7 km/h, see limits).

Tests: test_ai_race 9 of 9 pass; test_city_race 2 of 2 pass with MAX_STUCK_TOTAL = 0 (6 cars). Full suite once: 119 tests,
0 failed (run exit 0, no SCRIPT ERROR, Parse Error or SHADER ERROR in the log).

## city_01 round 3 (nitro use, 8-car stuck)
Diagnostics: `diag_nitro.gd` (solo car, skill 1.0, 2 laps, every tick logged to `evidence/logs/nitro_*.json`, with the target
speed profile) and `diag_ai_stuck.gd --cars=8|6 --out=stuck_r3_*.json`. Simulated, 60 Hz, dev PC (headless, Mobile renderer
not used). Track length 2184.5 m. The brief's Neon Strip offsets (1900 to 2203 to 260) do not match this layout: the low-curvature
run is s 2120 to 2184 and 0 to about 230 m (the start line at 0), and the car is still in a corner at s 1900 to 1950 (target 93 to 108 km/h).

Nitro, before (solo, `nitro_trace.json`): lap 1 max 174.7 km/h at s 321 m, lap 2 max 199.8 km/h at s 270 m. Nitro ran 3.6 s per
lap in 22 and 13 short bursts. Causes from the rows:
1. The gate `target - speed > 10 m/s` stayed closed from the lap start until s 106 m (the target rises slowly out of the corner).
2. Nitro ended at nitro charge 0.30: the start threshold (0.3) also applied while nitro ran, so the last 0.3 of the charge was never used.
3. The charge went into short bursts in corners and bends, so little was left for the Neon Strip.

Changes: nitro runs until the charge is empty (0.3 only starts it); gap 10 to 5 m/s; the road must stay under 0.004 1/m for 90 m
ahead; no nitro while a slower car is in follow range (a rule, not measured on its own).
Tried and rejected: curvature limit 0.005 or 0.006 (203.9 and 204.6 km/h, charge spent in bends); a lateral-load gate in place of the
look-ahead gate (201.7 km/h, charge spent in bends).

| Solo, skill 1.0 | Lap 1 max | Lap 2 max | Nitro lap 1 / lap 2 | Lap times |
|---|---|---|---|---|
| before (diag, fresh process) | 174.7 km/h at s 321 | 199.8 km/h at s 270 | 3.6 s, 22 starts / 3.6 s, 13 starts | race 132.00 s, 2 laps |
| after (diag, fresh process) | 176.0 km/h at s 321 | 216.0 km/h at s 250 | 5.2 s, 4 starts / 5.3 s, 4 starts | race 132.0 s, 2 laps |
| after (`test_city_race`) | | 216.1 km/h | | lap 1 65.43 s, lap 2 66.67 s (limit 67.1 s) |

Lap 2 nitro bins: s 0 to 190 m (full 3.2 s charge on the Neon Strip) and s 1250 to 1330 m (weaker, lower speed).
Waterfront straight: the brief does not give its offsets, so it is not isolated; the only other lap-2 nitro is s 1250 to 1330 m
(113 to 136 km/h) and at s 1600 m (178 km/h).

Stuck, before (8 cars, fresh process): 3 events, 85.13 s. Cars 5 and 6 at s 501 to 505 m on the left kerb (lat -4.4 to -6.7 m; a shift
to the outside of a right bend at about 0.008 1/m, and pushed by each other), car 6 at s 1472 m on the right kerb.
Changes: kerb margin, outside-of-bend refusal, damped shifts, bend bias (above).

| Run (8 cars unless noted) | Stuck events | Note |
|---|---|---|
| before | 3 | s 501 to 505 m and 1472 m, 85.13 s |
| kerb margin + damp at 0.004 1/m, nitro gates | 0 | 6 cars 0, but test_overtake_shifts_lane failed (the test chaser passes at 0.004 to 0.0065 1/m) |
| damp 0.006 to 0.008 1/m, no outside rule | 2 | s 767 to 770 m, left kerb in a right bend (0.0065 to 0.008 1/m) |
| + outside-of-bend refusal | 0 | 75.03 s |
| + bend bias 1.5 m | 1 | s 588 m, right kerb (lat +6.8 m), 80.6 s |
| same code, test order (6-car race first) | 1 | 80.23 s (test); full suite 80.58 s |
| 6 cars, final | 0 | 73.93 s, 6 contacts; min upright 0.9963 |

Sensitivity: before the bend bias, the 8-car result depended on the process: 0 events when the 8-car race ran first, 2 when it ran after
the 6-car race in the same process (events at s 912 to 915 m, left kerb, cars 5 and 7). Physics ordering inside the process changes the
contacts, so the count sits at the limit (1 of 1 allowed). Treat 8-car counts as a noisy statistic until a multi-seed run is done.
Contacts (touches, not stuck events): 8 cars 34 in the fresh run (was 34), 6 cars 10 (was 6).

Tests: `test_ai_race` 9 of 9 pass (solo test circuit lap 51.43 / 48.42 s, max lateral 5.01 m, limit 7). `test_city_race` 3 of 3 pass:
6 cars 0 stuck (limit 0); 8 cars at most 1 stuck (limit 1, brief target); solo lap 1 65.43 s and lap 2 66.67 s (limit 67.1 s),
lap 2 max 216.1 km/h (new assertion, > 200 km/h). Full suite once: 120 tests, 1 failed,
`test_race_scene::test_planar_reflection_bound_on_real_track_by_preset` ("Medium: mirror missing or wrong size"). It fails alone too,
and it does not use the AI code this round changed. Not investigated (race scene is not owned here).

Targets (round 3 brief):
- Lap-2 solo max above 200 km/h with nitro, target 210+: met (216.0 km/h in the diagnostic, 216.1 in the test).
- 8 cars: at most 1 stuck event: met (1), with no margin; see the sensitivity note.
- 6 cars: 0 stuck: met (0).
- Per-lap max speed and where: lap 1 176.0 km/h at s 321 m; lap 2 216.0 km/h at s 250 m (fresh diagnostic).

## Limits and open items
- Layout defect (not fixed here, owner: Environment): the parking buildings intrude into the road at s 1080 to 1108 m and
  1136 to 1176 m (right side, 2.5 to 3.9 m from the line). Any car sliding there can be wedged. The AI cannot see colliders.
- 8 cars, after the fix: 7 stuck events in three places. (a) s 449 m, lateral 6.3 m, `bld_neon_03_b`, target 37 m/s.
  (b) s 506 m, lateral 6.5 to 7.2 m, `wall_04` and `bld_downtown_03_a`: one car went to a yaw error of -90 deg after a
  hit at 496 m (source not identified) and hit the same wall three times, because the stuck reset puts it back on the line and the same line leads to the wall.
  (c) s 1133 to 1139 m, the parking intrusion again.
- Contacts: about 10 unique car pairs per race (`contacts` in the JSON). Most are rear-end touches at 100 to 125 km/h at the
  race start (s 390 to 436 m) and during the finish bunch-up. Not analysed in detail.
- Nitro is not gated by the slide rule. Nitro while sliding may increase the excursions. Not measured.
- Stuck recovery teleports to the line only after a failed reverse (round 2). Measured: 0 teleports in the 6-car race.
- 8 cars, round 2: 3 stuck events (limit 1). Round 3: 1 event (see round 3). Met, at the limit.
- 220 km/h on a lap: not reached. Solo max 174.7 km/h; the start straight (s 145 to 260 m) has target 216 to 252 km/h, but
  the car is still accelerating at 175 km/h when the straight ends at about s 330 m. Needs a longer straight or more power
  (not an AI setting). Nitro state was not logged in the trace, so the nitro use on that straight is not verified.
- Lateral accel limit tuned to 9.5 m/s^2 after 13 m/s^2 gave 11 m excursions at the car grip limit under throttle.
- Solo lateral margin (5.8 of 7 m) is modest. Re-check after any grip or steering change in ArcadeCar.
- Track length is 1.27 km (test circuit), a little above the 1.2 km target.
- Estimated times for unfinished cars are a pace extrapolation, not simulated.
- Round 3: the nitro limit on a single straight is the charge (3.2 s per burst). Lap 2 reaches 216 km/h on the Neon Strip, so 220 km/h on a lap is still not reached.
- Round 3: the 8-car stuck count changes with the process state (Jolt body order). The limit of 1 is met in the fresh run, the full suite and the test-only run, but with no margin. A multi-seed or multi-order check is open.
- Round 3: `test_race_scene::test_planar_reflection_bound_on_real_track_by_preset` fails in the full suite (not in the AI area; not investigated).
