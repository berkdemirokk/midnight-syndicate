# Drive telemetry (measured, no physics changes)

Machine: Windows 11 dev PC, AMD Ryzen 5 7600, NVIDIA RTX 5060 Ti 8 GB, Godot 4.7.2. Not a phone. Desktop numbers are never phone numbers.

## What was measured and how

- Runner: `game/devtools/scenarios/drive_telemetry_run.gd`, launched by `drive_telemetry.gd`. It drives the real race scene (`race/race_scene.tscn`) with `RaceConfig.autopilot = true`. The autopilot is an `AIDriver`, not a human. Its skill is a stand-in for a player, not a newcomer test.
- Race results go to `user://telemetry_save.json`, not the owner's profile. `game/tests/test_drive_telemetry.gd` checks that the scratch save is not `user://save.json`, that cleanup removes only the scratch file, and that the best-lap helper is correct.
- Sim runs: headless, `--fixed-fps 60`, `--audio-driver Dummy`. Rendered run: one GPU job under the lock helper, default vsync.
- "Contact events" are contact-impulse signal counts from `ArcadeCar.hit`. They are NOT verified collisions.
- "Teleports" are per-tick jumps over 5 m while racing. AI resets also count.
- A car counted as unfinished when it had not completed the laps when the race ended.
- Matrix note: the two track processes ran at the same time and shared `user://telemetry_save.json`. Race outcomes are held in memory, so the measurements should be unaffected, but this was not isolated.

## Files

- `evidence/telemetry/sim_restart.json`
- `evidence/telemetry/sim_first_race.json`
- `evidence/telemetry/sim_matrix_bogaz.json`
- `evidence/telemetry/sim_matrix_city01.json`
- `evidence/telemetry/sim_fairness.json` (CONFIG-DERIVED, not a race measurement)
- `evidence/telemetry/hitch_rendered.json` (rendered, GPU-locked)

## 1. Restart reliability (bogaz, Tayfun, grid 4, 2 laps, 4 runs in one process)

| run | finished | race time s | player pos | nodes after finish |
|---|---|---|---|---|
| 1 | yes | 121.37 | 3 | 4049 |
| 2 | yes | 119.38 | 4 | 4049 |
| 3 | yes | 119.53 | 4 | 4049 |
| 4 | yes | 112.28 | 3 | 4049 |

Node count before the first race was 4039. It was 4049 after every run, so there is no growth across retries. After the scene was freed it was 18. All 4 runs finished, with 4-7 stuck recoveries and 2-7 teleports per run.

## 2. First race (ortakoy_night, starter Tayfun, autopilot stand-in)

Event rivals are fixed by the event config: skills 0.70, 0.68, 0.66, grid 4, 1 lap.

| autopilot skill | player pos | race time s | 0-100 s | stuck | teleports | contacts (player) |
|---|---|---|---|---|---|---|
| 0.80 | 2 | 54.88 | 3.98 | 0 | 0 | 4 |
| 0.90 | 4 | 69.03 | 3.98 | 3 | 2 | 17 |
| 0.97 | 1 | 46.53 | 3.98 | 0 | 0 | 1 |

Answer to the brief's question: a stand-in at 0.80 to 0.97 places 1st to 4th against the event's rivals. This does not prove a human newcomer can place. The 0.90 run placed 4th only after repeated stuck events. Human testing is still needed.

## 3. Matrix (2 laps, rival_mix off, autopilot 0.97, night)

Grid 4 = 3 AI + player. Grid 8 = 7 AI + player. "Player total s" is the player's finish time (`player_total_time_s`); the race itself ends up to 15 s later (`race_time_s` in the JSON). "Unfinished" is the count of cars that had not completed 2 laps when the race ended.

| track | car | grid | pos | player total s | best lap s | 0-100 s | 0-200 s | top km/h (spec) | rival top max | stuck | teleports | contacts per lap (all) | unfinished |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bogaz | Tayfun | 4 | 3 | 112.82 | 53.95 | 3.50 | 9.68 | 211.1 (268) | 209.5 | 6 | 3 | 16.5 | 0 |
| bogaz | Tayfun | 8 | 4 | 109.28 | 54.12 | 3.80 | 9.90 | 214.2 (268) | 209.6 | 8 | 7 | 44.0 | 0 |
| bogaz | Marten | 4 | 2 | 117.43 | 54.35 | 2.97 | 6.95 | 231.4 (316) | 226.6 | 7 | 5 | 41.0 | 0 |
| bogaz | Marten | 8 | 4 | 131.05 | 58.28 | 3.18 | 49.23 | 226.7 (316) | 223.4 | 21 | 15 | 99.5 | 1 |
| bogaz | Yildirim | 4 | 4 | 139.40 | 61.93 | 3.62 | 7.68 | 227.6 (352) | 223.8 | 12 | 8 | 37.0 | 0 |
| bogaz | Yildirim | 8 | 2 | 112.73 | 56.27 | 3.80 | 8.02 | 230.4 (352) | 227.4 | 16 | 9 | 98.5 | 3 |
| city01 | Tayfun | 4 | 1 | 139.43 | 68.28 | 3.43 | 76.72 | 204.3 (268) | 203.6 | 1 | 0 | 13.5 | 1 |
| city01 | Tayfun | 8 | 1 | 143.92 | 69.92 | 3.72 | not reached | 197.7 (268) | 198.2 | 9 | 6 | 33.0 | 1 |
| city01 | Marten | 4 | 1 | 141.45 | 68.57 | 2.97 | 75.12 | 220.8 (316) | 219.5 | 1 | 0 | 9.0 | 0 |
| city01 | Marten | 8 | 4 | 162.78 | 79.73 | 3.17 | not reached | 198.5 (316) | 207.2 | 14 | 11 | 56.0 | 0 |
| city01 | Yildirim | 4 | 2 | 154.18 | 75.63 | 3.62 | 83.07 | 223.7 (352) | 213.0 | 6 | 3 | 22.5 | 0 |
| city01 | Yildirim | 8 | 1 | 143.32 | 70.93 | 3.77 | 76.45 | 222.4 (352) | 222.8 | 13 | 9 | 46.5 | 5 |

- Timed out: none (900 s cap). Teleports are AI resets, not a race fault by themselves.
- Lap times are only 2-lap samples. A 2-lap best lap is noisy.
- Player classification is the autopilot's, not a human's.

## 4. Opponent class fairness (CONFIG-DERIVED, not measured in races)

`sim_fairness.json` lists the rival models that `CarCatalog.rival_models` picks for each career event, with the starter Tayfun at 268 km/h top speed:

- ortakoy_night (street, 3 opponents): Sable 286, Tayfun 268, Sable 286. 2 of 3 faster.
- wharf_sprint (street, 3): same picks. 2 of 3 faster.
- neon_strip_circuit (any class, 5): Sable, Bruiser, Gtr, Vanta, Havoc. 4 of 5 faster.
- midnight_time_trial: no rivals.
- overpass_duel (1): Yildirim 352. 1 of 1 faster.
- harbour_run (5): 3 of 5 faster.
- syndicate_final (5): includes Marten 316.

The top-speed numbers are spec values from the catalog. They say nothing about how rivals perform in races. The per-race rival top speeds in section 3 are the only race-based rival data here.

## 5. Rendered start hitch (bogaz, Tayfun, grid 8, rendered, RTX 5060 Ti, default vsync, screen 180 Hz)

- Countdown starts at 1892 ms after scene start. GO at 4888 ms.
- Max frame before the countdown: 482.5 ms (scene build, not a race frame).
- Max frame during countdown: 57.5 ms.
- Max frame in the first 5 s after GO: 34.6 ms.
- First 5 s after GO: 301 frames, median 15.6 ms, 52 frames over 25 ms (20 of 121 in the first 2 s, median 14.9 ms; 32 of 180 in 2-5 s). So the start runs at about 60 fps with repeated 25-35 ms spikes, not a sustained 30 fps. Whole run: 96 frames over 25 ms. Desktop only, one run.

## Ranked driving problems (measured; parameters are NOT changed)

1. Stuck and reset churn grows with grid size. 4 to 21 stuck recoveries per 2-lap race, 0 to 15 teleports. Grid 8 Marten on bogaz had 21 stuck and 15 teleports. The recovery trigger is `stuck_time` (2.0 s) and `stuck_progress_m` (2.0 m). The teleport fallback is `reset_yaw_deg` (40 deg). File: `game/ai/ai_driver.gd`.
2. Contact pressure is high. All cars together: 9 to 41 contact events per lap at grid 4 and 33 to 99.5 at grid 8 (matrix). In the 1-lap first race the player alone had 1 to 17. Some of these are wall or rival touches. The avoidance inputs are `car_width` (1.9 m), `side_clearance` (0.8 m), `lane_margin` (0.6 m), `ttc_brake` (1.5 s). File: `game/ai/ai_driver.gd`. The contact impulse threshold in `ArcadeCar` was not read.
3. Top speed in races is far below spec. Tayfun reaches 198 to 214 km/h against 268 km/h spec. Marten and Yildirim reach 198 to 232 km/h against 316 and 352, so the car spec barely separates the classes. The hard cap is the track speed profile: `max_speed` = 70 m/s (252 km/h, `track_max_speed_kmh` in the JSON) in `game/world/track.gd`, below every spec top speed. The AI then drives a fraction of that profile: `skill` (0.97 in the matrix) in `game/ai/ai_driver.gd`.
4. City01 almost never reaches 200 km/h: 0-200 is 75 s or more in 4 of 6 city runs and not reached in the other 2 (grid 8). The cap is the same 252 km/h as bogaz, so the limit is the corner speed profile: `lateral_accel_limit` = 9.5 m/s^2 (v = sqrt(a * r)) in `game/world/track.gd`, applied to city01's tighter curvature. Not verified per segment.
5. Race ends with cars unfinished. On city01 grid 8, Yildirim left 5 of 8 cars unfinished at the end. Up to 3 unfinished on bogaz. This decides which cars are classified. The race ends `finish_wait_s` = 15 s after the player finishes (or when all cars finish), so slower cars are cut off and classified by distance. File: `game/race/race_manager.gd`.

## Not done or risky

- The first-race and newcomer checks use autopilot skills, not a human player. The 0.80 to 0.97 stand-ins are not a newcomer test.
- Contact events are impulse counts, not verified collisions.
- Matrix runs shared one scratch save file in parallel (see Matrix note).
- Single rendered hitch run. Desktop, not phone.
- The rendered hitch was only one run, measured with vsync.
- Rival data for races: only the 2-lap matrix and the first race. No per-race rival finish data was compared with the config picks.
- The full suite (358 tests, 0 failed) printed "Parse JSON failed" messages to the log. These were not investigated in this package.

## After: AI churn (package ai, 2026-11-28)

Code: `game/ai/ai_driver.gd`. Tests: `game/tests/test_ai_churn.gd` (2 tests). Same matrix, same sim (`--fixed-fps 60`, headless, `--part=matrix`, bogaz and city01, 3 cars x grid 4 and 8 each). Before = the commit before this package (168c27a). The matrix is deterministic for a fixed code state: the before numbers reproduced the table above, and the final after run reproduced the candidate run exactly. The lead review re-ran the after matrix on commit 7fd1fa1 and got the same numbers.

Evidence: before = `evidence/telemetry/sim_matrix_bogaz.json`, `evidence/telemetry/sim_matrix_city01.json`; after = `evidence/telemetry/sim_matrix_bogaz_after_ai.json`, `evidence/telemetry/sim_matrix_city01_after_ai.json`.

### Causes found (stuck events)
Detector: `stuck_time` 2.0 s without 2 m of forward progress. Debug prints of each stuck event (speed, yaw, lateral, traffic) on city01 and bogaz showed three things:
1. Queued cars were counted as stuck. A car held behind a car that is stopped (the follow cap, or the start of a pack) makes no progress, but it is not wedged. Each stopped car in a queue made the cars behind it count stuck. Fix: time spent held by the car ahead (`cap < want`) does not count.
2. The recovery could never free a car. `_tick_reverse` drove the car back along the line (reverse brake), then required 2 m of *forward* progress to count as free, so every recovery fell through to the teleport. Fix: free means the car moved 2 m along the line in either direction, and its heading is within `reset_yaw_deg`.
3. Pack contacts were the main source of spins. Contacts came from a car closing on the car ahead with only the speed-matching brake (`brake_gain` 0.2 per m/s), which is too weak once the bumper gap is small. Most stuck events in those logs had yaw 90 to 180 deg and speed near 0. The contact log showed rear-end and side touches with the bumper gap near 0 and closing speeds of about 4 m/s or more. Fix: a kinematic follow brake, closing speed squared over (2 x bumper gap x `follow_decel`), so the car brakes for the closing speed (no throttle while doing so). `follow_decel` = 4.0 m/s^2 (not the 6.0 tried first; 3.0 was worse).

### Before and after (same runs, 6 races per track, 3 cars each)
Totals over the 12 races:

| metric | bogaz before | bogaz after | city01 before | city01 after |
|---|---|---|---|---|
| stuck recoveries | 70 | 43 | 44 | 23 |
| teleports (jumps over 5 m) | 47 | 19 | 29 | 11 |
| contact events (all cars) | 673 | 557 | 361 | 205 |
| unfinished cars at race end | 4 | 0 | 7 | 2 |
| mean AI best lap, s (all AI cars with a best lap) | 55.55 | 54.89 | 76.65 | 75.04 |

Per grid (same runs):

| track | grid | metric | before | after |
|---|---|---|---|---|
| bogaz | 4 | stuck recoveries (3 races) | 25 | 10 |
| bogaz | 4 | teleports (3 races) | 16 | 6 |
| bogaz | 4 | contacts per lap, mean of 3 races | 31.5 | 31.3 |
| bogaz | 4 | unfinished cars at race end (sum) | 0 | 0 |
| bogaz | 4 | mean AI best lap s | 54.25 | 53.87 |
| bogaz | 4 | player position, 3 cars | 3/2/4 | 4/2/4 |
| bogaz | 4 | player total time s, 3 cars | 112.8/117.4/139.4 | 116.8/101.2/132.0 |
| bogaz | 8 | stuck recoveries (3 races) | 45 | 33 |
| bogaz | 8 | teleports (3 races) | 31 | 13 |
| bogaz | 8 | contacts per lap, mean of 3 races | 80.7 | 61.3 |
| bogaz | 8 | unfinished cars at race end (sum) | 4 | 0 |
| bogaz | 8 | mean AI best lap s | 56.10 | 55.33 |
| bogaz | 8 | player position, 3 cars | 4/4/2 | 7/4/6 |
| bogaz | 8 | player total time s, 3 cars | 109.3/131.1/112.7 | 120.0/117.8/129.7 |
| city01 | 4 | stuck recoveries (3 races) | 8 | 11 |
| city01 | 4 | teleports (3 races) | 3 | 5 |
| city01 | 4 | contacts per lap, mean of 3 races | 15.0 | 12.2 |
| city01 | 4 | unfinished cars at race end (sum) | 1 | 2 |
| city01 | 4 | mean AI best lap s | 74.89 | 76.05 |
| city01 | 4 | player position, 3 cars | 1/1/2 | 1/1/1 |
| city01 | 4 | player total time s, 3 cars | 139.4/141.4/154.2 | 139.7/148.5/143.1 |
| city01 | 8 | stuck recoveries (3 races) | 36 | 12 |
| city01 | 8 | teleports (3 races) | 26 | 6 |
| city01 | 8 | contacts per lap, mean of 3 races | 45.2 | 22.0 |
| city01 | 8 | unfinished cars at race end (sum) | 6 | 0 |
| city01 | 8 | mean AI best lap s | 77.40 | 74.60 |
| city01 | 8 | player position, 3 cars | 1/4/1 | 3/1/4 |
| city01 | 8 | player total time s, 3 cars | 143.9/162.8/143.3 | 144.8/147.2/155.3 |

Matched AI cars (same race, same slot, two laps in both runs, n = 47): mean best lap 63.40 s before and 63.44 s after (+0.07 %). Single cars move a lot between runs (the worst one, bogaz grid 8 bosfor slot 2, 52.6 to 67.1 s, is in the table above only as part of its mean; it is a traffic effect, see open items). Lap times are 2-lap samples and noisy.

### Tuning and rejected variants (same matrix)
| variant | bogaz stuck / teleports / contacts | city01 stuck / teleports / contacts | note |
|---|---|---|---|
| held rule + free by distance (no follow brake) | 44 / 22 / 550 | 41 / 26 / 370 | first step |
| + follow brake, follow_decel 6.0 | 53 / 27 / 565 | 33 / 25 / 283 | |
| + follow brake, follow_decel 4.0 (shipped) | 43 / 19 / 557 | 23 / 11 / 205 | |
| + follow brake, follow_decel 3.0 | 53 / 31 / 604 | 28 / 13 / 234 | |
| shipped + no reverse into a car behind (reset instead) | 49 / 24 / 516 | 23 / 11 / 191 | rejected: more stuck and teleports on bogaz |

### Tests
- `test_ai_churn`: queued car behind two stopped side blockers, not stuck (0; the lead review confirmed it fails without the held rule) and stops short of the car ahead. Closing car at 25 m/s from 40 m, no contact. The closing test passes with or without the follow brake, so it guards against contact regressions only; it does not prove the follow brake.
- `test_ai_race` 10 of 10 and `test_city_race` 10 of 10 pass unchanged (city 8-car stuck counts: order A 1/0/0, order B 2/3/1 (lead review re-run) at nitro 0/100/140).
- Full suite: 382 tests, 0 failed (380 before plus the 2 new ones).

### Not done or risky
- Stuck events left: most are cars that stopped after a spin or a kerb hit. The recovery still resets (teleports) after a reverse that does not free the car; a steering-aware reverse was not built.
- City01 grid 4 regresses and is accepted as a regression, not called noise: stuck 8 to 11, teleports 3 to 5, unfinished 1 to 2, mean AI best lap 74.89 to 76.05 s (+1.55 %). The matrix has no seed option, so it was not separated from run-to-run variation; n = 3 races. Every other cell and every total improved.
- Contacts are impulse counts (`ArcadeCar.hit`), not verified collisions.
- The follow brake slows a car that is closing on a slower car in its lane, so one car can get a slower lap (the 27 % car above). Pace on average is unchanged. Per track, matched AI cars: bogaz +1.59 % (n = 26), city01 -1.27 % (n = 21), both inside the 3 % limit. 19 matched cars moved more than 5 % (12 slower, 7 faster); single 2-lap samples in traffic.
- The follow brake uses a bumper gap floored at 0.05 m. A car in our lane band that overlaps us along the track (along under `car_length`) gives full brake at a closing speed above about 0.45 m/s. The old time rule already matched speed there; the new rule brakes harder. Not analysed per event.
- Sim runs only (Windows dev PC, headless, `--fixed-fps 60`). The rendered run was not repeated.
- The autopilot is a stand-in for a player. Nothing here says anything about a newcomer.
